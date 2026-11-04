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

@interface MRImageCache ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) id<MRHTTPClient> httpClient;
@property (nonatomic, strong) NSCache *memoryCache;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSMutableDictionary *operations;
@property (nonatomic, strong) NSMutableDictionary *completions;
@property (nonatomic, strong) NSMutableDictionary *generations;

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
- (void)finishLoadForURL:(NSString *)URL
              generation:(NSUInteger)generation
                   image:(UIImage *)image
                   error:(NSError *)error;
@end

#pragma mark - Load operation

@interface MRImageLoadOperation : NSOperation
@property (nonatomic, strong) MRImageCache *cache;
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) id<MRHTTPTask> activeTask;
- (instancetype)initWithCache:(MRImageCache *)cache
                          URL:(NSString *)URL
                   generation:(NSUInteger)generation;
@end

@implementation MRImageLoadOperation

- (instancetype)initWithCache:(MRImageCache *)cache
                          URL:(NSString *)URL
                   generation:(NSUInteger)generation {
    self = [super init];
    if (self) {
        _cache = cache;
        _URL = [URL copy];
        _generation = generation;
    }
    return self;
}

- (void)cancel {
    [super cancel];
    id<MRHTTPTask> task = nil;
    @synchronized(self) {
        task = self.activeTask;
        self.activeTask = nil;
    }
    [task cancel];
}

- (void)main {
    @autoreleasepool {
        if (self.isCancelled) {
            return;
        }

        NSData *data = [self.cache diskDataForURL:self.URL];
        if (data.length > 0) {
            UIImage *image = [UIImage imageWithData:data];
            if (image != nil) {
                [self.cache storeMemoryImage:image
                                      forURL:self.URL
                                        cost:(NSUInteger)data.length];
                [self.cache finishLoadForURL:self.URL
                                  generation:self.generation
                                       image:image
                                       error:nil];
                return;
            }
            [self.cache removeDiskDataForURL:self.URL];
        }

        if (self.isCancelled) {
            return;
        }

        [self download];
    }
}

- (void)download {
    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:self.URL method:@"GET"];
    request.queueKind = MRHTTPQueueKindCatalog;
    request.headers = @{ @"User-Agent": MR_USER_AGENT };

    NSCondition *condition = [[NSCondition alloc] init];
    __block MRHTTPResponse *response = nil;

    id<MRHTTPTask> task = [self.cache.httpClient sendRequest:request
                                                  completion:^(MRHTTPResponse *result) {
        [condition lock];
        response = result;
        [condition broadcast];
        [condition unlock];
    }];
    @synchronized(self) {
        self.activeTask = task;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:request.timeout + 5.0];
    [condition lock];
    while (response == nil && !self.isCancelled && [deadline timeIntervalSinceNow] > 0.0) {
        [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    MRHTTPResponse *result = response;
    [condition unlock];

    @synchronized(self) {
        self.activeTask = nil;
    }

    if (self.isCancelled) {
        [task cancel];
        return;
    }

    if (result == nil) {
        [task cancel];
        [self.cache finishLoadForURL:self.URL
                          generation:self.generation
                               image:nil
                               error:[MRError errorWithKind:MRErrorKindOffline]];
        return;
    }

    if (result.transportError == nil &&
        result.statusCode >= 200 && result.statusCode <= 299 &&
        result.data.length > 0) {
        UIImage *image = [UIImage imageWithData:result.data];
        if (image != nil) {
            [self.cache storeDiskData:result.data forURL:self.URL];
            [self.cache storeMemoryImage:image
                                  forURL:self.URL
                                    cost:(NSUInteger)result.data.length];
            [self.cache finishLoadForURL:self.URL
                              generation:self.generation
                                   image:image
                                   error:nil];
            return;
        }
        [self.cache finishLoadForURL:self.URL
                          generation:self.generation
                               image:nil
                               error:[MRError errorWithKind:MRErrorKindParse]];
        return;
    }

    NSError *error = [MRError errorForStatusCode:result.statusCode
                                           body:result.data
                                        headers:result.headers
                                 transportError:result.transportError];
    [self.cache finishLoadForURL:self.URL
                      generation:self.generation
                           image:nil
                           error:error];
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
        _completions = [NSMutableDictionary dictionary];
        _generations = [NSMutableDictionary dictionary];

        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = (NSInteger)MRImageConcurrentLoads;
        _operationQueue.name = @"com.marquee.images";

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

- (void)loadImageForURL:(NSString *)URL
             completion:(void (^)(UIImage *image, NSError *error))completion {
    if (URL.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindUnknown]);
            }
        });
        return;
    }

    UIImage *cached = [self.memoryCache objectForKey:URL];
    if (cached != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(cached, nil);
            }
        });
        return;
    }

    MRImageLoadOperation *operation = nil;
    @synchronized(self) {
        MRImageLoadOperation *existing = [self.operations objectForKey:URL];
        if (existing != nil) {
            NSMutableArray *blocks = [self.completions objectForKey:URL];
            if (blocks == nil) {
                blocks = [NSMutableArray array];
                [self.completions setObject:blocks forKey:URL];
            }
            if (completion != nil) {
                [blocks addObject:[completion copy]];
            }
            return;
        }

        NSUInteger generation =
            [[self.generations objectForKey:URL] unsignedIntegerValue] + 1;
        [self.generations setObject:@(generation) forKey:URL];

        operation = [[MRImageLoadOperation alloc] initWithCache:self
                                                          URL:URL
                                                   generation:generation];
        [self.operations setObject:operation forKey:URL];

        NSMutableArray *blocks = [NSMutableArray array];
        if (completion != nil) {
            [blocks addObject:[completion copy]];
        }
        [self.completions setObject:blocks forKey:URL];
    }

    [self.operationQueue addOperation:operation];
}

- (void)cancelLoadForURL:(NSString *)URL {
    if (URL.length == 0) {
        return;
    }

    MRImageLoadOperation *operation = nil;
    @synchronized(self) {
        NSUInteger generation =
            [[self.generations objectForKey:URL] unsignedIntegerValue] + 1;
        [self.generations setObject:@(generation) forKey:URL];
        operation = [self.operations objectForKey:URL];
        [self.operations removeObjectForKey:URL];
        [self.completions removeObjectForKey:URL];
    }
    [operation cancel];
}

- (void)finishLoadForURL:(NSString *)URL
              generation:(NSUInteger)generation
                   image:(UIImage *)image
                   error:(NSError *)error {
    NSArray *blocks = nil;
    @synchronized(self) {
        NSNumber *current = [self.generations objectForKey:URL];
        if (current == nil || [current unsignedIntegerValue] != generation) {
            return;
        }
        [self.operations removeObjectForKey:URL];
        blocks = [[self.completions objectForKey:URL] copy];
        [self.completions removeObjectForKey:URL];
    }

    for (id stored in blocks) {
        void (^block)(UIImage *, NSError *) = (void (^)(UIImage *, NSError *))stored;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL deliver = NO;
            @synchronized(self) {
                NSNumber *latest = [self.generations objectForKey:URL];
                deliver = (latest != nil && [latest unsignedIntegerValue] == generation);
            }
            if (deliver) {
                block(image, error);
            }
        });
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
