//
//  MRResponseCacheTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRResponseCache.h"

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

void MRRunResponseCacheTests(void) {
    MRRunCacheRoundTripTest();
    MRRunDeterministicFilenameTest();
    MRRunURLCollisionTest();
    MRRunMissingEntryTest();
}
