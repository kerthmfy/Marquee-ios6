//
//  MRImageCache.m
//  Marquee
//

#import "MRImageCache.h"
#import "MRAPIRequestOperation.h"
#import "MRConfig.h"
#import "MRError.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"

static const NSUInteger MRImageMemoryCountLimit = 200;
static const NSUInteger MRImageMemoryCostLimit = 50 * 1024 * 1024;
static const unsigned long long MRImageDiskLimitBytes = 100ULL * 1024ULL * 1024ULL;
static const NSUInteger MRImageConcurrentLoads = 4;
static const NSUInteger MRImageMaxDataBytes = 10 * 1024 * 1024;

// NSCache cost is decoded pixel bytes, not compressed JPEG bytes, so the 50 MB
// limit bounds the memory an image actually occupies once decoded.
static NSUInteger MRImageCostForImage(UIImage *image) {
    if (image == nil) {
        return 0;
    }
    CGFloat scale = image.scale > 0.0 ? image.scale : 1.0;
    double bytes = (double)image.size.width * (double)image.size.height *
                   (double)scale * (double)scale * 4.0;
    if (bytes <= 0.0) {
        return 0;
    }
    if (bytes >= (double)NSUIntegerMax) {
        return NSUIntegerMax;
    }
    return (NSUInteger)bytes;
}

static NSString *MRDefaultImageCacheDirectory(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask,
                                                         YES);
    NSString *caches = paths.count > 0 ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    return [caches stringByAppendingPathComponent:@"Marquee/Images"];
}

// Cache-owned files are exactly 16 lowercase hex characters plus ".jpg".
static BOOL MRImageCacheIsOwnedFileName(NSString *name) {
    if (name.length != 20 || ![name hasSuffix:@".jpg"]) {
        return NO;
    }
    for (NSUInteger index = 0; index < 16; index += 1) {
        unichar character = [name characterAtIndex:index];
        if (!((character >= '0' && character <= '9') ||
              (character >= 'a' && character <= 'f'))) {
            return NO;
        }
    }
    return YES;
}

static NSString *MRImageCacheFileNameForURL(NSString *URL) {
    const unsigned char *bytes = (const unsigned char *)[URL UTF8String];
    uint64_t hash = 14695981039346656037ULL;
    if (bytes != NULL) {
        while (*bytes != '\0') {
            hash ^= (uint64_t)(*bytes);
            hash *= 1099511628211ULL;
            bytes += 1;
        }
    }
    return [NSString stringWithFormat:@"%016llx.jpg", (unsigned long long)hash];
}

@class MRImageLoadOperation;
@class MRImageLoadToken;

@interface MRImageCache ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) id<MRHTTPClient> httpClient;
@property (nonatomic, strong) NSCache *memoryCache;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSOperationQueue *ioQueue;
@property (nonatomic, strong) NSMutableDictionary *operations;
@property (nonatomic, strong) NSMutableDictionary *tokensByURL;

- (BOOL)ensureDirectory;
- (void)touchPath:(NSString *)path;
- (NSString *)diskPathForURL:(NSString *)URL;
- (NSData *)diskDataForURL:(NSString *)URL;
- (void)removeDiskDataForURL:(NSString *)URL;
- (void)storeDiskData:(NSData *)data forURL:(NSString *)URL;
- (void)storeMemoryImage:(UIImage *)image forURL:(NSString *)URL cost:(NSUInteger)cost;
- (NSArray *)ownedFileNames;
- (void)pruneDiskCacheIfNeeded;
- (void)handleMemoryWarning:(NSNotification *)note;
- (void)performIO:(void (^)(void))block;
- (void)trackToken:(MRImageLoadToken *)token forURL:(NSString *)URL;
- (void)finishOperation:(MRImageLoadOperation *)operation
                    URL:(NSString *)URL
                  image:(UIImage *)image
                  error:(NSError *)error;
- (void)deliverToken:(id)token image:(UIImage *)image error:(NSError *)error;
@end

#pragma mark - Load token

// One caller's request. Cancelling a token never affects another token for the
// same URL; the shared load operation only stops once every token is cancelled.
@interface MRImageLoadToken : NSObject
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) void (^completion)(UIImage *image, NSError *error);
- (void)cancel;
- (BOOL)isCancelled;
// Atomically claims one-shot delivery and releases the completion while still
// holding the token lock. Callers capture the token in their completion block,
// so keeping the block after delivery would form token -> block -> token.
- (void (^)(UIImage *image, NSError *error))claimCompletion;
@end

@implementation MRImageLoadToken {
    BOOL _cancelled;
    BOOL _delivered;
}

- (void)cancel {
    @synchronized(self) {
        _cancelled = YES;
        self.completion = nil;
    }
}

- (BOOL)isCancelled {
    @synchronized(self) {
        return _cancelled;
    }
}

- (void (^)(UIImage *image, NSError *error))claimCompletion {
    @synchronized(self) {
        if (_cancelled || _delivered) {
            return nil;
        }
        _delivered = YES;
        void (^completion)(UIImage *, NSError *) = self.completion;
        self.completion = nil;
        return completion;
    }
}

@end

#pragma mark - Load operation

@interface MRImageLoadOperation : NSOperation
@property (nonatomic, weak) MRImageCache *cache;
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, strong) id<MRHTTPTask> activeTask;
@property (nonatomic, strong) NSMutableArray *tokens;
- (instancetype)initWithCache:(MRImageCache *)cache URL:(NSString *)URL;
@end

@implementation MRImageLoadOperation {
    BOOL _executing;
    BOOL _finished;
}

- (instancetype)initWithCache:(MRImageCache *)cache URL:(NSString *)URL {
    self = [super init];
    if (self) {
        _cache = cache;
        _URL = [URL copy];
        _tokens = [NSMutableArray array];
    }
    return self;
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    @synchronized(self) {
        return _executing;
    }
}

- (BOOL)isFinished {
    @synchronized(self) {
        return _finished;
    }
}

- (void)cancel {
    [super cancel];
    id<MRHTTPTask> task = nil;
    @synchronized(self) {
        task = self.activeTask;
        self.activeTask = nil;
    }
    [task cancel];

    BOOL executing = NO;
    @synchronized(self) {
        executing = _executing;
    }
    // Cancelling before the queue starts the operation is handled by -start;
    // cancelling while I/O is in flight finishes immediately to free the slot.
    if (executing) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
    }
}

- (void)start {
    if (self.isCancelled) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    @synchronized(self) {
        _executing = YES;
    }
    [self didChangeValueForKey:@"isExecuting"];

    MRImageCache *cache = self.cache;
    if (cache == nil) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    // Queue the disk probe on the cache's serial I/O queue and return at once;
    // a network load never ties up an operation-queue worker while waiting.
    [cache performIO:^{
        @autoreleasepool {
            [self load];
        }
    }];
}

- (void)load {
    if (self.isCancelled) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
        return;
    }

    MRImageCache *cache = self.cache;
    NSData *data = [cache diskDataForURL:self.URL];
    if (data.length > 0) {
        if (data.length > MRImageMaxDataBytes) {
            [cache removeDiskDataForURL:self.URL];
            [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindParse]];
            return;
        }
        UIImage *image = [UIImage imageWithData:data];
        if (image != nil) {
            [cache storeMemoryImage:image
                             forURL:self.URL
                               cost:MRImageCostForImage(image)];
            [self finishWithImage:image error:nil];
            return;
        }
        [cache removeDiskDataForURL:self.URL];
    }

    if (self.isCancelled) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
        return;
    }

    [self download];
}

- (void)download {
    MRImageCache *cache = self.cache;
    if (cache == nil) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:self.URL method:@"GET"];
    request.queueKind = MRHTTPQueueKindCatalog;
    request.headers = @{ @"User-Agent": MR_USER_AGENT };

    __weak MRImageLoadOperation *weakSelf = self;
    __weak MRImageCache *weakCache = cache;
    id<MRHTTPTask> task = [cache.httpClient sendRequest:request
                                             completion:^(MRHTTPResponse *result) {
        MRImageLoadOperation *strongSelf = weakSelf;
        MRImageCache *strongCache = weakCache;
        if (strongSelf == nil) {
            return;
        }
        if (strongCache == nil) {
            [strongSelf finishWithImage:nil
                                  error:[MRError errorWithKind:MRErrorKindUnknown]];
            return;
        }
        // The HTTP client delivers on the main queue. Decode and disk writes
        // belong on the cache's serial I/O queue, not on main.
        [strongCache performIO:^{
            @autoreleasepool {
                [strongSelf handleResponse:result];
            }
        }];
    }];

    @synchronized(self) {
        if (self.isCancelled || _finished) {
            [task cancel];
        } else {
            self.activeTask = task;
        }
    }
}

- (void)handleResponse:(MRHTTPResponse *)result {
    if (self.isCancelled) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
        return;
    }

    if (result == nil) {
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindOffline]];
        return;
    }

    if (result.transportError == nil &&
        result.statusCode >= 200 && result.statusCode <= 299 &&
        result.data.length > 0) {
        if (result.data.length > MRImageMaxDataBytes) {
            [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindParse]];
            return;
        }

        UIImage *image = [UIImage imageWithData:result.data];
        if (image != nil) {
            MRImageCache *cache = self.cache;
            [cache storeDiskData:result.data forURL:self.URL];
            [cache storeMemoryImage:image
                             forURL:self.URL
                               cost:MRImageCostForImage(image)];
            [self finishWithImage:image error:nil];
            return;
        }
        [self finishWithImage:nil error:[MRError errorWithKind:MRErrorKindParse]];
        return;
    }

    NSError *error = [MRError errorForStatusCode:result.statusCode
                                           body:result.data
                                        headers:result.headers
                                 transportError:result.transportError];
    [self finishWithImage:nil error:error];
}

- (void)finishWithImage:(UIImage *)image error:(NSError *)error {
    MRImageCache *cache = self.cache;
    NSString *URL = self.URL;

    @synchronized(self) {
        if (_finished) {
            return;
        }
        BOOL wasExecuting = _executing;
        if (wasExecuting) {
            [self willChangeValueForKey:@"isExecuting"];
        }
        [self willChangeValueForKey:@"isFinished"];
        _executing = NO;
        _finished = YES;
        self.activeTask = nil;
        if (wasExecuting) {
            [self didChangeValueForKey:@"isExecuting"];
        }
        [self didChangeValueForKey:@"isFinished"];
    }

    [cache finishOperation:self URL:URL image:image error:error];
}

@end

#pragma mark - Image cache

@implementation MRImageCache

- (instancetype)init {
    return [self initWithDirectory:MRDefaultImageCacheDirectory()
                        httpClient:[MRAPIRequestOperation sharedClient]];
}

- (instancetype)initWithDirectory:(NSString *)directory
                      httpClient:(id<MRHTTPClient>)httpClient {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _httpClient = httpClient != nil ? httpClient : [MRAPIRequestOperation sharedClient];

        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = MRImageMemoryCountLimit;
        _memoryCache.totalCostLimit = MRImageMemoryCostLimit;
        _memoryCache.name = @"MarqueeImages";

        _operations = [NSMutableDictionary dictionary];
        _tokensByURL = [NSMutableDictionary dictionary];

        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = (NSInteger)MRImageConcurrentLoads;
        _operationQueue.name = @"com.marquee.images";

        // Disk reads, decodes, and JPEG writes are serialized off the operation
        // queue so a slow file never blocks a network completion on main.
        _ioQueue = [[NSOperationQueue alloc] init];
        _ioQueue.maxConcurrentOperationCount = 1;
        _ioQueue.name = @"com.marquee.images.io";

        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(handleMemoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_operationQueue cancelAllOperations];
    [_ioQueue cancelAllOperations];
}

- (void)performIO:(void (^)(void))block {
    if (block == nil) {
        return;
    }
    [self.ioQueue addOperationWithBlock:block];
}

- (void)handleMemoryWarning:(NSNotification *)note {
    [self clearMemoryCache];
}

#pragma mark - Memory

- (UIImage *)cachedImageForURL:(NSString *)URL {
    if (URL.length == 0) {
        return nil;
    }
    return [self.memoryCache objectForKey:URL];
}

- (void)clearMemoryCache {
    [self.memoryCache removeAllObjects];
}

- (void)storeMemoryImage:(UIImage *)image forURL:(NSString *)URL cost:(NSUInteger)cost {
    if (image == nil || URL.length == 0) {
        return;
    }
    [self.memoryCache setObject:image forKey:URL cost:cost];
}

#pragma mark - Loading

- (id)loadImageForURL:(NSString *)URL
           completion:(void (^)(UIImage *image, NSError *error))completion {
    MRImageLoadToken *token = [[MRImageLoadToken alloc] init];
    token.URL = [URL copy];
    token.completion = completion;

    if (URL.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self deliverToken:token
                         image:nil
                         error:[MRError errorWithKind:MRErrorKindUnknown]];
        });
        return token;
    }

    UIImage *cached = [self.memoryCache objectForKey:URL];
    if (cached != nil) {
        @synchronized(self) {
            [self trackToken:token forURL:URL];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self deliverToken:token image:cached error:nil];
        });
        return token;
    }

    MRImageLoadOperation *operation = nil;
    @synchronized(self) {
        [self trackToken:token forURL:URL];

        MRImageLoadOperation *existing = [self.operations objectForKey:URL];
        if (existing != nil) {
            [existing.tokens addObject:token];
            return token;
        }

        operation = [[MRImageLoadOperation alloc] initWithCache:self URL:URL];
        [operation.tokens addObject:token];
        [self.operations setObject:operation forKey:URL];
    }

    [self.operationQueue addOperation:operation];
    return token;
}

- (void)cancelLoad:(id)token {
    if (![token isKindOfClass:[MRImageLoadToken class]]) {
        return;
    }
    MRImageLoadToken *loadToken = (MRImageLoadToken *)token;
    MRImageLoadOperation *operation = nil;

    @synchronized(self) {
        [loadToken cancel];

        NSMutableArray *tokens = [self.tokensByURL objectForKey:loadToken.URL];
        if (tokens != nil) {
            [tokens removeObjectIdenticalTo:loadToken];
            if (tokens.count == 0) {
                [self.tokensByURL removeObjectForKey:loadToken.URL];
            }
        }

        // Stop the shared operation only when none of its own callers remain.
        // Other outstanding tokens (including earlier completions waiting for
        // main) keep it alive.
        MRImageLoadOperation *candidate = [self.operations objectForKey:loadToken.URL];
        if (candidate != nil) {
            BOOL hasLiveToken = NO;
            for (MRImageLoadToken *candidateToken in candidate.tokens) {
                if (![candidateToken isCancelled]) {
                    hasLiveToken = YES;
                    break;
                }
            }
            if (!hasLiveToken) {
                operation = candidate;
                [self.operations removeObjectForKey:loadToken.URL];
            }
        }
    }

    [operation cancel];
}

- (void)cancelLoadForURL:(NSString *)URL {
    if (URL.length == 0) {
        return;
    }

    MRImageLoadOperation *operation = nil;
    @synchronized(self) {
        NSArray *tokens = [[self.tokensByURL objectForKey:URL] copy];
        for (MRImageLoadToken *token in tokens) {
            [token cancel];
        }
        [self.tokensByURL removeObjectForKey:URL];

        operation = [self.operations objectForKey:URL];
        [self.operations removeObjectForKey:URL];
    }
    [operation cancel];
}

- (void)trackToken:(MRImageLoadToken *)token forURL:(NSString *)URL {
    NSMutableArray *tokens = [self.tokensByURL objectForKey:URL];
    if (tokens == nil) {
        tokens = [NSMutableArray array];
        [self.tokensByURL setObject:tokens forKey:URL];
    }
    [tokens addObject:token];
}

- (void)deliverToken:(id)token image:(UIImage *)image error:(NSError *)error {
    MRImageLoadToken *loadToken = (MRImageLoadToken *)token;
    if (loadToken == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        void (^completion)(UIImage *, NSError *) = nil;
        @synchronized(self) {
            NSMutableArray *tokens = [self.tokensByURL objectForKey:loadToken.URL];
            if (tokens != nil) {
                [tokens removeObjectIdenticalTo:loadToken];
                if (tokens.count == 0) {
                    [self.tokensByURL removeObjectForKey:loadToken.URL];
                }
            }
            // Removing from the pending set and claiming delivery are one step,
            // so cancelLoad:/cancelLoadForURL: either cancels before this claim
            // or observes a token that has already delivered.
            completion = [loadToken claimCompletion];
        }

        if (completion != nil) {
            completion(image, error);
        }
    });
}

- (void)finishOperation:(MRImageLoadOperation *)operation
                    URL:(NSString *)URL
                  image:(UIImage *)image
                  error:(NSError *)error {
    NSArray *tokens = nil;
    @synchronized(self) {
        // A cancelled operation may have already been replaced by a newer load
        // for the same URL; the stale finisher must not touch that load.
        if ([self.operations objectForKey:URL] != operation) {
            return;
        }
        [self.operations removeObjectForKey:URL];
        tokens = [operation.tokens copy];
        [operation.tokens removeAllObjects];
    }

    for (MRImageLoadToken *token in tokens) {
        [self deliverToken:token image:image error:error];
    }
}

#pragma mark - Disk

- (NSString *)diskPathForURL:(NSString *)URL {
    if (self.directory.length == 0 || URL.length == 0) {
        return nil;
    }
    return [self.directory stringByAppendingPathComponent:MRImageCacheFileNameForURL(URL)];
}

- (BOOL)ensureDirectory {
    if (self.directory.length == 0) {
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([manager fileExistsAtPath:self.directory isDirectory:&isDirectory] && isDirectory) {
        return YES;
    }
    return [manager createDirectoryAtPath:self.directory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:NULL];
}

- (void)touchPath:(NSString *)path {
    NSDictionary *attributes = @{ NSFileModificationDate: [NSDate date] };
    [[NSFileManager defaultManager] setAttributes:attributes
                                     ofItemAtPath:path
                                            error:NULL];
}

- (NSData *)diskDataForURL:(NSString *)URL {
    @synchronized(self) {
        NSString *path = [self diskPathForURL:URL];
        if (path == nil) {
            return nil;
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) {
            return nil;
        }
        [self touchPath:path];
        return data;
    }
}

- (void)removeDiskDataForURL:(NSString *)URL {
    @synchronized(self) {
        NSString *path = [self diskPathForURL:URL];
        if (path != nil) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
    }
}

- (void)storeDiskData:(NSData *)data forURL:(NSString *)URL {
    if (data.length == 0 || URL.length == 0) {
        return;
    }

    @synchronized(self) {
        if (![self ensureDirectory]) {
            return;
        }
        NSString *path = [self diskPathForURL:URL];
        if (path == nil) {
            return;
        }
        if (![data writeToFile:path atomically:YES]) {
            return;
        }
        [self touchPath:path];
        [self pruneDiskCacheIfNeeded];
    }
}

- (NSArray *)ownedFileNames {
    if (self.directory.length == 0) {
        return nil;
    }
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.directory
                                                                          error:NULL];
    if (entries == nil) {
        return nil;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in entries) {
        if (MRImageCacheIsOwnedFileName(name)) {
            [names addObject:name];
        }
    }
    return names;
}

- (void)pruneDiskCacheIfNeeded {
    NSArray *names = [self ownedFileNames];
    if (names.count == 0) {
        return;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    unsigned long long totalBytes = 0;
    NSMutableArray *files = [NSMutableArray array];

    for (NSString *name in names) {
        NSString *path = [self.directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if (attributes == nil) {
            continue;
        }
        unsigned long long size = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        totalBytes += size;
        NSDate *modifiedAt = [attributes fileModificationDate];
        [files addObject:@{ @"path": path,
                            @"size": @(size),
                            @"modifiedAt": modifiedAt != nil ? modifiedAt : [NSDate distantPast] }];
    }

    if (totalBytes <= MRImageDiskLimitBytes) {
        return;
    }

    NSArray *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
        NSDictionary *leftEntry = (NSDictionary *)left;
        NSDictionary *rightEntry = (NSDictionary *)right;
        NSComparisonResult result = [[leftEntry objectForKey:@"modifiedAt"]
                                     compare:[rightEntry objectForKey:@"modifiedAt"]];
        if (result != NSOrderedSame) {
            return result;
        }
        return [[leftEntry objectForKey:@"path"] compare:[rightEntry objectForKey:@"path"]];
    }];

    for (NSDictionary *entry in sorted) {
        if (totalBytes <= MRImageDiskLimitBytes) {
            break;
        }
        NSString *path = [entry objectForKey:@"path"];
        unsigned long long size = [[entry objectForKey:@"size"] unsignedLongLongValue];
        if ([manager removeItemAtPath:path error:NULL]) {
            totalBytes = totalBytes >= size ? totalBytes - size : 0;
        }
    }
}

- (void)clearDiskCache {
    @synchronized(self) {
        NSArray *names = [self ownedFileNames];
        NSFileManager *manager = [NSFileManager defaultManager];
        for (NSString *name in names) {
            NSString *path = [self.directory stringByAppendingPathComponent:name];
            [manager removeItemAtPath:path error:NULL];
        }
    }
}

- (unsigned long long)diskUsageBytes {
    @synchronized(self) {
        NSArray *names = [self ownedFileNames];
        NSFileManager *manager = [NSFileManager defaultManager];
        unsigned long long total = 0;
        for (NSString *name in names) {
            NSString *path = [self.directory stringByAppendingPathComponent:name];
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
            total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        }
        return total;
    }
}

@end
