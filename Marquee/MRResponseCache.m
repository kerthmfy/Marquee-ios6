//
//  MRResponseCache.m
//  Marquee
//

#import "MRResponseCache.h"
#import "MRDate.h"
#import "MRJSON.h"

static const unsigned long long MRResponseCacheMaximumBytes = 50ULL * 1024ULL * 1024ULL;

static NSString *MRResponseCacheFileNameForURL(NSString *URL) {
    // FNV-1a over the UTF-8 bytes. A 64-bit hash keeps accidental collisions
    // vanishingly unlikely while staying deterministic across launches.
    const unsigned char *bytes = (const unsigned char *)[URL UTF8String];
    uint64_t hash = 14695981039346656037ULL;
    if (bytes != NULL) {
        while (*bytes != '\0') {
            hash ^= (uint64_t)(*bytes);
            hash *= 1099511628211ULL;
            bytes += 1;
        }
    }
    return [NSString stringWithFormat:@"%016llx.json", (unsigned long long)hash];
}

@interface MRResponseCache ()
@property (nonatomic, copy) NSString *directory;
@end

@implementation MRResponseCache

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _directory = [directory copy];
    }
    return self;
}

- (NSString *)pathForURL:(NSString *)URL {
    if (self.directory.length == 0 || URL.length == 0) {
        return nil;
    }
    return [self.directory stringByAppendingPathComponent:MRResponseCacheFileNameForURL(URL)];
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

- (NSDictionary *)entryForURL:(NSString *)URL {
    NSString *path = [self pathForURL:URL];
    if (path == nil) {
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }

    NSError *error = nil;
    id object = [MRJSON objectFromData:data error:&error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *entry = (NSDictionary *)object;
    id storedURL = [entry objectForKey:@"url"];
    if (![storedURL isKindOfClass:[NSString class]] ||
        ![(NSString *)storedURL isEqualToString:URL]) {
        // A hash collision or a stale/corrupt file. Never trust a body that
        // belongs to another URL.
        return nil;
    }
    return entry;
}

- (NSDate *)fetchedAtForURL:(NSString *)URL {
    @synchronized(self) {
        NSDictionary *entry = [self entryForURL:URL];
        id value = [entry objectForKey:@"fetchedAt"];
        if (![value isKindOfClass:[NSString class]]) {
            return nil;
        }
        return [MRDate dateFromISOString:(NSString *)value];
    }
}

- (NSString *)lastModifiedForURL:(NSString *)URL {
    @synchronized(self) {
        NSDictionary *entry = [self entryForURL:URL];
        id value = [entry objectForKey:@"lastModified"];
        if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
            return nil;
        }
        return (NSString *)value;
    }
}

- (id)cachedBodyForURL:(NSString *)URL maxAge:(NSTimeInterval)maxAge {
    @synchronized(self) {
        NSDictionary *entry = [self entryForURL:URL];
        if (entry == nil) {
            return nil;
        }

        id fetchedAtValue = [entry objectForKey:@"fetchedAt"];
        if (![fetchedAtValue isKindOfClass:[NSString class]]) {
            return nil;
        }
        NSDate *fetchedAt = [MRDate dateFromISOString:(NSString *)fetchedAtValue];
        if (fetchedAt == nil) {
            return nil;
        }

        NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:fetchedAt];
        if (age > maxAge) {
            return nil;
        }

        id body = [entry objectForKey:@"body"];
        if (body == nil || [body isKindOfClass:[NSNull class]]) {
            return nil;
        }
        return body;
    }
}

- (void)storeBody:(id)body forURL:(NSString *)URL lastModified:(NSString *)lastModified {
    if (body == nil || URL.length == 0) {
        return;
    }

    // Validate before touching disk so a non-JSON body never replaces a good
    // entry with a broken file.
    NSError *error = nil;
    if ([MRJSON dataFromObject:body error:&error] == nil) {
        return;
    }

    @synchronized(self) {
        if (![self ensureDirectory]) {
            return;
        }

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        [entry setObject:URL forKey:@"url"];
        [entry setObject:[MRDate isoStringFromDate:[NSDate date]] forKey:@"fetchedAt"];
        [entry setObject:@200 forKey:@"status"];
        [entry setObject:body forKey:@"body"];
        if (lastModified.length > 0) {
            [entry setObject:lastModified forKey:@"lastModified"];
        }

        NSData *data = [MRJSON dataFromObject:entry error:&error];
        if (data == nil) {
            return;
        }

        NSString *path = [self pathForURL:URL];
        if (path == nil) {
            return;
        }
        [data writeToFile:path atomically:YES];

        [self pruneIfNeeded];
    }
}

- (NSArray *)cacheFileNames {
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
        if ([[name pathExtension] isEqualToString:@"json"]) {
            [names addObject:name];
        }
    }
    return names;
}

- (void)pruneIfNeeded {
    NSArray *names = [self cacheFileNames];
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

    if (totalBytes <= MRResponseCacheMaximumBytes) {
        return;
    }

    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *file in files) {
        NSString *path = [file objectForKey:@"path"];
        NSDate *fetchedAt = nil;

        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length > 0) {
            id object = [MRJSON objectFromData:data error:NULL];
            if ([object isKindOfClass:[NSDictionary class]]) {
                id value = [(NSDictionary *)object objectForKey:@"fetchedAt"];
                if ([value isKindOfClass:[NSString class]]) {
                    fetchedAt = [MRDate dateFromISOString:(NSString *)value];
                }
            }
        }
        if (fetchedAt == nil) {
            fetchedAt = [file objectForKey:@"modifiedAt"];
        }

        [entries addObject:@{ @"path": path,
                              @"fetchedAt": fetchedAt,
                              @"modifiedAt": [file objectForKey:@"modifiedAt"] }];
    }

    NSArray *sorted = [entries sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
        NSDictionary *leftEntry = (NSDictionary *)left;
        NSDictionary *rightEntry = (NSDictionary *)right;
        NSComparisonResult result = [[leftEntry objectForKey:@"fetchedAt"]
                                     compare:[rightEntry objectForKey:@"fetchedAt"]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[leftEntry objectForKey:@"modifiedAt"]
                  compare:[rightEntry objectForKey:@"modifiedAt"]];
        if (result != NSOrderedSame) {
            return result;
        }
        return [[leftEntry objectForKey:@"path"] compare:[rightEntry objectForKey:@"path"]];
    }];

    // Oldest first: drop files until the cache fits under the cap.
    for (NSDictionary *entry in sorted) {
        if (totalBytes <= MRResponseCacheMaximumBytes) {
            break;
        }
        NSString *path = [entry objectForKey:@"path"];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        unsigned long long size = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        if ([manager removeItemAtPath:path error:NULL]) {
            if (totalBytes >= size) {
                totalBytes -= size;
            } else {
                totalBytes = 0;
            }
        }
    }
}

@end
