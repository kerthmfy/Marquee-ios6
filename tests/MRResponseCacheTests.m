//
//  MRResponseCacheTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRResponseCache.h"
#import "MRDate.h"

// Test-only access to the deterministic path helper so pruning tests can inspect
// and rewrite the exact cache file without duplicating the hash.
@interface MRResponseCache (MRTestPath)
- (NSString *)pathForURL:(NSString *)URL;
@end

static NSString *MRCreateCacheDirectory(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-response-cache-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

static void MRRemoveCacheDirectory(NSString *path) {
    if (path != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static NSArray *MRJSONFilesInDirectory(NSString *directory) {
    NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory
                                                                          error:NULL];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *entry in entries) {
        if ([[entry pathExtension] isEqualToString:@"json"]) {
            [files addObject:entry];
        }
    }
    return files;
}

static BOOL MRIsCacheOwnedFileName(NSString *name) {
    if (name.length != 21 || ![name hasSuffix:@".json"]) {
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

static unsigned long long MRTotalCacheBytes(NSString *directory) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *entries = [manager contentsOfDirectoryAtPath:directory error:NULL];
    unsigned long long total = 0;
    for (NSString *name in entries) {
        if (!MRIsCacheOwnedFileName(name)) {
            continue;
        }
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
    }
    return total;
}

static void MRSetFetchedAt(NSString *path, NSDate *date) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:object];
    [entry setObject:[MRDate isoStringFromDate:date] forKey:@"fetchedAt"];
    NSData *updated = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    [updated writeToFile:path atomically:YES];
}

static void MRRunCacheRoundTripTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];
    NSString *URL = @"https://data.simkl.in/trending/movie/day.json";
    NSDictionary *body = @{ @"items": @[ @{ @"title": @"Matinee" } ] };

    [cache storeBody:body forURL:URL lastModified:@"Wed, 04 Nov 2026 11:55:00 GMT"];

    MRAssertEqualObjects(body, [cache cachedBodyForURL:URL maxAge:60.0],
                         @"cache returns stored body inside max age");
    MRAssertTrue([cache cachedBodyForURL:URL maxAge:-1.0] == nil,
                 @"cache misses outside max age");
    MRAssertEqualObjects(@"Wed, 04 Nov 2026 11:55:00 GMT",
                         [cache lastModifiedForURL:URL],
                         @"last modified round-trips");
    MRAssertTrue([cache fetchedAtForURL:URL] != nil, @"fetchedAt is stored");
    MRAssertTrue([[cache fetchedAtForURL:URL] timeIntervalSinceNow] > -5.0,
                 @"fetchedAt is recent");

    MRRemoveCacheDirectory(directory);
}

static void MRRunDeterministicFilenameTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];
    NSString *firstURL = @"https://data.simkl.in/trending/movie/day.json";
    NSString *secondURL = @"https://data.simkl.in/trending/tv/day.json";

    [cache storeBody:@{ @"value": @"first" } forURL:firstURL lastModified:nil];
    [cache storeBody:@{ @"value": @"first-again" } forURL:firstURL lastModified:nil];

    MRAssertEqualIntegers(1, (NSInteger)[MRJSONFilesInDirectory(directory) count],
                          @"same url reuses one deterministic file");

    [cache storeBody:@{ @"value": @"second" } forURL:secondURL lastModified:nil];

    MRAssertEqualIntegers(2, (NSInteger)[MRJSONFilesInDirectory(directory) count],
                          @"different url creates a second file");

    MRAssertEqualObjects(@{ @"value": @"first-again" },
                         [cache cachedBodyForURL:firstURL maxAge:60.0],
                         @"same url reads the latest body");
    MRAssertEqualObjects(@{ @"value": @"second" },
                         [cache cachedBodyForURL:secondURL maxAge:60.0],
                         @"different url has its own body");

    MRRemoveCacheDirectory(directory);
}

static void MRRunURLCollisionTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];
    NSArray *URLs = @[ @"https://api.simkl.com/movies/1",
                       @"https://api.simkl.com/movies/2",
                       @"https://data.simkl.in/genre/movie/action.json" ];

    NSUInteger index = 0;
    for (NSString *URL in URLs) {
        [cache storeBody:@{ @"index": @(index) } forURL:URL lastModified:nil];
        index += 1;
    }

    index = 0;
    for (NSString *URL in URLs) {
        MRAssertEqualObjects(@{ @"index": @(index) },
                             [cache cachedBodyForURL:URL maxAge:60.0],
                             @"distinct urls do not collide");
        index += 1;
    }

    MRRemoveCacheDirectory(directory);
}

static void MRRunMissingEntryTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];

    MRAssertTrue([cache cachedBodyForURL:@"https://api.simkl.com/none" maxAge:60.0] == nil,
                 @"missing cache entry returns nil");
    MRAssertTrue([cache lastModifiedForURL:@"https://api.simkl.com/none"] == nil,
                 @"missing last modified returns nil");
    MRAssertTrue([cache fetchedAtForURL:@"https://api.simkl.com/none"] == nil,
                 @"missing fetchedAt returns nil");

    MRRemoveCacheDirectory(directory);
}

static void MRRunStoredURLMismatchTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];
    NSString *URL = @"https://api.simkl.com/movies/1";
    NSString *otherURL = @"https://api.simkl.com/movies/2";

    [cache storeBody:@{ @"value": @"secret" } forURL:URL lastModified:nil];

    // Simulate a hash collision or a tampered file: the deterministic path still
    // exists but points at a body that claims to belong to another URL.
    NSString *path = [cache pathForURL:URL];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:
                                  [NSJSONSerialization JSONObjectWithData:data
                                                                  options:0
                                                                    error:NULL]];
    [entry setObject:otherURL forKey:@"url"];
    NSData *tampered = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    MRAssertTrue([tampered writeToFile:path atomically:YES],
                 @"tampered cache entry was written");

    MRAssertTrue([cache cachedBodyForURL:URL maxAge:1000000000.0] == nil,
                 @"stored url mismatch never returns another url's body");
    MRAssertTrue([cache lastModifiedForURL:URL] == nil,
                 @"stored url mismatch never returns metadata");
    MRAssertTrue([cache fetchedAtForURL:URL] == nil,
                 @"stored url mismatch never returns fetchedAt");

    MRRemoveCacheDirectory(directory);
}

static void MRRunPruneProtectsForeignFilesTest(void) {
    NSString *directory = MRCreateCacheDirectory();
    NSFileManager *manager = [NSFileManager defaultManager];
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];

    // Foreign JSON files owned by other components must survive pruning and must
    // not count toward the cache budget.
    NSString *diagnosticsPath = [directory stringByAppendingPathComponent:@"diagnostics.json"];
    NSString *statePath = [directory stringByAppendingPathComponent:@"state.json"];
    NSString *foreignJSON = @"{\"marker\":\"keep-me\",\"records\":[]}";
    [foreignJSON writeToFile:diagnosticsPath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL];
    [foreignJSON writeToFile:statePath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:NULL];
    NSSet *initialEntries = [NSSet setWithArray:
                             [manager contentsOfDirectoryAtPath:directory error:NULL]];

    const NSUInteger entryCount = 52;
    NSString *payload = [@"" stringByPaddingToLength:1024 * 1024
                                          withString:@"x"
                                     startingAtIndex:0];
    NSDate *baseDate = [NSDate dateWithTimeIntervalSince1970:1577836800.0]; // 2020-01-01
    NSMutableSet *createdNames = [NSMutableSet set];
    NSString *oldestURL = nil;
    NSString *newestURL = nil;

    for (NSUInteger index = 0; index < entryCount; index += 1) {
        NSString *URL = [NSString stringWithFormat:
                         @"https://data.simkl.in/prune/%lu.json", (unsigned long)index];
        if (oldestURL == nil) {
            oldestURL = URL;
        }
        newestURL = URL;

        [cache storeBody:@{ @"index": @(index), @"payload": payload }
                  forURL:URL
            lastModified:nil];

        NSString *path = [cache pathForURL:URL];
        [createdNames addObject:[path lastPathComponent]];
        // Give every entry a distinct fetchedAt so prune ordering is exact even
        // when the writes happen inside the same wall-clock second.
        MRSetFetchedAt(path,
                       [baseDate dateByAddingTimeInterval:(NSTimeInterval)index]);
    }

    unsigned long long totalBytes = MRTotalCacheBytes(directory);
    MRAssertTrue(totalBytes > 0,
                 @"pruning test actually retained cache entries");
    MRAssertTrue(totalBytes <= 50ULL * 1024ULL * 1024ULL,
                 @"cache-owned bytes end at or below 50 MB");

    MRAssertTrue(![manager fileExistsAtPath:[cache pathForURL:oldestURL]],
                 @"oldest cache entry is pruned");
    MRAssertTrue([manager fileExistsAtPath:[cache pathForURL:newestURL]],
                 @"newest cache entry is retained");

    id newestBody = [cache cachedBodyForURL:newestURL maxAge:400000000.0];
    MRAssertTrue([newestBody isKindOfClass:[NSDictionary class]] &&
                 [[(NSDictionary *)newestBody objectForKey:@"index"] integerValue] ==
                 (NSInteger)(entryCount - 1),
                 @"newest cache entry still returns its body");

    MRAssertTrue([manager fileExistsAtPath:diagnosticsPath],
                 @"diagnostics.json survives pruning");
    MRAssertTrue([manager fileExistsAtPath:statePath],
                 @"state.json survives pruning");
    MRAssertEqualObjects(foreignJSON,
                         [NSString stringWithContentsOfFile:diagnosticsPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL],
                         @"diagnostics.json contents are untouched");
    MRAssertEqualObjects(foreignJSON,
                         [NSString stringWithContentsOfFile:statePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL],
                         @"state.json contents are untouched");

    NSArray *finalEntries = [manager contentsOfDirectoryAtPath:directory error:NULL];
    NSSet *finalSet = [NSSet setWithArray:finalEntries];
    NSMutableSet *removed = [NSMutableSet setWithSet:createdNames];
    [removed minusSet:finalSet];
    MRAssertTrue(removed.count > 0,
                 @"pruning actually dropped at least one cache file");
    for (NSString *name in removed) {
        MRAssertTrue(MRIsCacheOwnedFileName(name),
                     @"pruning only deletes 16-hex cache-owned files");
    }
    for (NSString *name in finalEntries) {
        MRAssertTrue([initialEntries containsObject:name] ||
                     MRIsCacheOwnedFileName(name),
                     @"cache directory holds no unexpected files");
    }

    MRRemoveCacheDirectory(directory);
}

void MRRunResponseCacheTests(void) {
    MRRunCacheRoundTripTest();
    MRRunDeterministicFilenameTest();
    MRRunURLCollisionTest();
    MRRunMissingEntryTest();
    MRRunStoredURLMismatchTest();
    MRRunPruneProtectsForeignFilesTest();
}
