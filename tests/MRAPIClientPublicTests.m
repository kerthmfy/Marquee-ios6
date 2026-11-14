//
//  MRAPIClientPublicTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRAPIClient.h"
#import "MRConfig.h"
#import "MRDate.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPResponse.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRStubHTTPClient.h"
#import "MRTokenProviding.h"

// Test-only access to the deterministic cache path so the 304 test can make an
// entry stale without waiting 24 hours.
@interface MRResponseCache (MRAPIClientPublicTests)
- (NSString *)pathForURL:(NSString *)URL;
@end

@interface MRSpyTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, assign) NSInteger calls;
@end

@implementation MRSpyTokenProvider

- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    self.calls += 1;
    if (completion != nil) {
        completion(@"SHOULD-NOT-BE-USED", nil);
    }
}

@end

@interface MRAPIClientTestContext : NSObject
@property (nonatomic, strong) NSString *directory;
@property (nonatomic, strong) MRStubHTTPClient *http;
@property (nonatomic, strong) MRFakeClock *clock;
@property (nonatomic, strong) MRResponseCache *cache;
@property (nonatomic, strong) MRQuotaTracker *quota;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) MRSpyTokenProvider *tokenProvider;
@property (nonatomic, strong) MRAPIClient *client;
+ (instancetype)context;
- (void)teardown;
@end

@implementation MRAPIClientTestContext

+ (instancetype)context {
    MRAPIClientTestContext *context = [[self alloc] init];
    NSString *name = [NSString stringWithFormat:@"marquee-api-client-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    context.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:context.directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    context.http = [[MRStubHTTPClient alloc] init];
    context.clock = [[MRFakeClock alloc] init];
    context.cache = [[MRResponseCache alloc] initWithDirectory:context.directory];
    context.quota = [[MRQuotaTracker alloc] initWithDirectory:context.directory accountID:1];
    context.diagnostics = [[MRDiagnostics alloc] initWithDirectory:context.directory];
    context.tokenProvider = [[MRSpyTokenProvider alloc] init];
    context.client = [[MRAPIClient alloc] initWithHTTPClient:context.http
                                              tokenProvider:context.tokenProvider
                                              responseCache:context.cache
                                               quotaTracker:context.quota
                                                diagnostics:context.diagnostics
                                                      clock:context.clock];
    return context;
}

- (void)teardown {
    if (self.directory != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:self.directory error:NULL];
    }
}

@end

static NSData *MRFixtureData(NSString *name) {
    NSString *file = [name pathExtension].length > 0 ? name : [name stringByAppendingPathExtension:@"json"];
    NSString *path = [@"tests/fixtures" stringByAppendingPathComponent:file];
    return [NSData dataWithContentsOfFile:path];
}

static MRHTTPResponse *MRResponseWithJSON(NSInteger statusCode, id object,
                                          NSDictionary *headers) {
    NSData *data = nil;
    if (object != nil) {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    }
    return [MRHTTPResponse responseWithStatusCode:statusCode
                                          headers:headers
                                             data:data
                                   transportError:nil];
}

static MRHTTPResponse *MRResponseWithBody(NSInteger statusCode, NSString *body,
                                          NSDictionary *headers) {
    NSData *data = body.length > 0 ? [body dataUsingEncoding:NSUTF8StringEncoding] : nil;
    return [MRHTTPResponse responseWithStatusCode:statusCode
                                          headers:headers
                                             data:data
                                   transportError:nil];
}

static NSDictionary *MRTrendingHeaders(void) {
    return @{ @"Last-Modified": @"Wed, 04 Nov 2026 11:55:00 GMT" };
}

static NSString *MRCommonQuery(void) {
    return [NSString stringWithFormat:@"?client_id=%@&app-name=%@&app-version=%@",
            MR_SIMKL_CLIENT_ID, MR_APP_NAME, MR_APP_VERSION];
}

static NSString *MRTrendingURL(void) {
    return [@"https://data.simkl.in/discover/trending/week_100.json"
            stringByAppendingString:MRCommonQuery()];
}

static NSString *MRDetailURL(MRMediaType type, NSInteger simklID) {
    return [[NSString stringWithFormat:@"https://api.simkl.com/%@/%ld",
             MRMediaTypeAPIPath(type), (long)simklID] stringByAppendingString:MRCommonQuery()];
}

static void MRPumpMain(void) {
    MRRunUntil(^BOOL {
        return NO;
    }, 0.05);
}

static void MRMakeEntryStale(NSString *directory, NSString *URL) {
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:directory];
    NSString *path = [cache pathForURL:URL];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:object];
    NSDate *staleDate = [NSDate dateWithTimeIntervalSinceNow:-(2.0 * 24.0 * 60.0 * 60.0)];
    [entry setObject:[MRDate isoStringFromDate:staleDate] forKey:@"fetchedAt"];
    NSData *updated = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL];
    [updated writeToFile:path atomically:YES];
}

static void MRRunTrendingURLTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                                headers:MRTrendingHeaders()
                                                                   data:MRFixtureData(@"trending-week")
                                                         transportError:nil]];

    __block NSUInteger completions = 0;
    __block NSDictionary *json = nil;
    __block NSError *error = nil;
    __block BOOL onMain = NO;

    id<MRHTTPTask> task = [context.client fetchTrendingWeekWithCompletion:
                           ^(NSDictionary *result, NSError *resultError) {
        completions += 1;
        json = result;
        error = resultError;
        onMain = [NSThread isMainThread];
    }];
    MRAssertTrue(task != nil, @"trending network fetch returns a task");
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"trending completion delivered");
    MRPumpMain();

    MRAssertEqualIntegers(1, (NSInteger)completions, @"trending completion exactly once");
    MRAssertTrue(onMain, @"trending completion on main thread");
    MRAssertTrue(error == nil, @"trending has no error");
    MRAssertEqualObjects(MRFixture(@"trending-week"), json,
                         @"trending json parsed");

    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"trending sends one request");
    MRHTTPRequest *request = [context.http requestAtIndex:0];
    MRAssertEqualObjects(MRTrendingURL(), request.URL, @"trending url and common params");
    MRAssertEqualObjects(@"GET", request.method, @"trending uses GET");
    MRAssertEqualIntegers(MRHTTPQueueKindCatalog, request.queueKind,
                          @"trending uses the catalog queue");
    MRAssertEqualObjects(MR_USER_AGENT, [request.headers objectForKey:@"User-Agent"],
                         @"trending sends the Marquee user agent");
    MRAssertTrue([request.headers objectForKey:@"Authorization"] == nil,
                 @"public trending has no Authorization header");
    MRAssertEqualIntegers(0, context.tokenProvider.calls,
                          @"public trending never asks for a token");

    [context teardown];
}

static void MRRunGenreURLTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSArray *genre = @[ @{ @"id": @"action", @"name": @"Action" } ];

    [context.http enqueueResponse:MRResponseWithJSON(200, genre, nil)];
    __block NSUInteger indexCompletions = 0;
    __block NSArray *indexResult = nil;
    [context.client fetchGenreIndexForType:MRMediaTypeMovie completion:
     ^(NSArray *result, NSError *error) {
        indexCompletions += 1;
        indexResult = result;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return indexCompletions > 0; }, 2.0),
                 @"genre index completion delivered");
    MRAssertEqualObjects(genre, indexResult, @"genre index parsed");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"genre index sends one request");

    MRHTTPRequest *request = [context.http requestAtIndex:0];
    NSString *expected = [@"https://data.simkl.in/discover/trending/movies/genre/index.json"
                          stringByAppendingString:MRCommonQuery()];
    MRAssertEqualObjects(expected, request.URL, @"movie genre index url");
    MRAssertEqualObjects(MR_USER_AGENT, [request.headers objectForKey:@"User-Agent"],
                         @"genre index user agent");
    MRAssertTrue([request.headers objectForKey:@"Authorization"] == nil,
                 @"genre index has no Authorization header");

    // TV and anime use their API path segment. A fresh context per type keeps
    // the URL assertion independent of the cache.
    NSArray *types = @[ @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
    NSArray *segments = @[ @"tv", @"anime" ];
    NSUInteger index = 0;
    for (NSNumber *typeNumber in types) {
        MRAPIClientTestContext *typeContext = [MRAPIClientTestContext context];
        [typeContext.http enqueueResponse:MRResponseWithJSON(200, genre, nil)];
        __block NSUInteger typeCompletions = 0;
        [typeContext.client fetchGenreIndexForType:(MRMediaType)[typeNumber integerValue]
                                        completion:^(NSArray *result, NSError *error) {
            typeCompletions += 1;
        }];
        MRAssertTrue(MRRunUntil(^BOOL { return typeCompletions > 0; }, 2.0),
                     @"genre index completion delivered for every type");
        NSString *typeExpected = [NSString stringWithFormat:
            @"https://data.simkl.in/discover/trending/%@/genre/index.json%@",
            [segments objectAtIndex:index], MRCommonQuery()];
        MRAssertEqualObjects(typeExpected, [[typeContext.http requestAtIndex:0] URL],
                             @"genre index url for tv/anime");
        [typeContext teardown];
        index += 1;
    }

    [context teardown];
}

static void MRRunGenreFileURLTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSArray *genre = @[ @{ @"title": @"Frieren" } ];
    [context.http enqueueResponse:MRResponseWithJSON(200, genre, nil)];

    __block NSUInteger completions = 0;
    __block NSArray *result = nil;
    [context.client fetchGenre:@"isekai" forType:MRMediaTypeAnime completion:
     ^(NSArray *json, NSError *error) {
        completions += 1;
        result = json;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"genre file completion delivered");
    MRAssertEqualObjects(genre, result, @"genre file parsed");

    NSString *expected = [@"https://data.simkl.in/discover/trending/anime/genre/"
                          @"isekai_month_500.json" stringByAppendingString:MRCommonQuery()];
    MRAssertEqualObjects(expected, [[context.http requestAtIndex:0] URL],
                         @"genre file url shape");
    [context teardown];
}

static void MRRunDetailURLTest(void) {
    NSArray *types = @[ @(MRMediaTypeMovie), @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
    NSArray *segments = @[ @"movies", @"tv", @"anime" ];
    NSUInteger index = 0;
    for (NSNumber *typeNumber in types) {
        MRAPIClientTestContext *context = [MRAPIClientTestContext context];
        [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                                    headers:nil
                                                                       data:MRFixtureData(@"movie-detail")
                                                             transportError:nil]];
        __block NSUInteger completions = 0;
        __block NSDictionary *result = nil;
        [context.client fetchDetailForType:(MRMediaType)[typeNumber integerValue]
                                  simklID:342994
                                completion:^(NSDictionary *json, NSError *error) {
            completions += 1;
            result = json;
        }];
        MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                     @"detail completion delivered for every type");
        MRAssertEqualObjects(MRFixture(@"movie-detail"), result,
                             @"detail json parsed");

        NSString *expected = [NSString stringWithFormat:
            @"https://api.simkl.com/%@/342994%@", [segments objectAtIndex:index],
            MRCommonQuery()];
        MRAssertEqualObjects(expected, [[context.http requestAtIndex:0] URL],
                             @"detail url shape");
        MRAssertEqualObjects(MR_USER_AGENT,
                             [[[context.http requestAtIndex:0] headers] objectForKey:@"User-Agent"],
                             @"detail user agent");
        MRAssertTrue([[[context.http requestAtIndex:0] headers]
                      objectForKey:@"Authorization"] == nil,
                     @"detail has no Authorization header");
        [context teardown];
        index += 1;
    }
}

static void MRRunEpisodeURLTest(void) {
    NSArray *types = @[ @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
    NSArray *segments = @[ @"tv", @"anime" ];
    NSArray *ids = @[ @17465, @39793 ];
    NSUInteger index = 0;
    for (NSNumber *typeNumber in types) {
        MRAPIClientTestContext *context = [MRAPIClientTestContext context];
        NSArray *episodes = @[ @{
            @"season": @1,
            @"episode": @1,
            @"title": @"Winter Is Coming",
            @"description": @"A first episode.",
            @"runtime": @61,
            @"date": @"2011-04-17T21:00:00-04:00"
        } ];
        [context.http enqueueResponse:MRResponseWithJSON(200, episodes, nil)];

        __block NSUInteger completions = 0;
        __block NSArray *result = nil;
        [context.client fetchEpisodesForType:(MRMediaType)[typeNumber integerValue]
                                    simklID:[[ids objectAtIndex:index] integerValue]
                                  completion:^(NSArray *json, NSError *error) {
            completions += 1;
            result = json;
        }];
        MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                     @"episode completion delivered for tv and anime");
        MRAssertEqualObjects(episodes, result, @"episode array parsed");

        NSString *expected = [NSString stringWithFormat:
            @"https://api.simkl.com/%@/episodes/%@%@",
            [segments objectAtIndex:index], [ids objectAtIndex:index],
            MRCommonQuery()];
        MRAssertEqualObjects(expected, [[context.http requestAtIndex:0] URL],
                             @"episode url shape");
        MRAssertEqualObjects(MR_USER_AGENT,
                             [[[context.http requestAtIndex:0] headers] objectForKey:@"User-Agent"],
                             @"episode user agent");
        MRAssertTrue([[[context.http requestAtIndex:0] headers]
                      objectForKey:@"Authorization"] == nil,
                     @"episode fetch has no Authorization header");
        [context teardown];
        index += 1;
    }

    MRAPIClientTestContext *movieContext = [MRAPIClientTestContext context];
    __block NSUInteger movieCompletions = 0;
    __block NSError *movieError = nil;
    [movieContext.client fetchEpisodesForType:MRMediaTypeMovie
                                      simklID:342994
                                    completion:^(NSArray *json, NSError *error) {
        movieCompletions += 1;
        movieError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return movieCompletions > 0; }, 2.0),
                 @"movie episode request completion delivered");
    MRAssertEqualIntegers(MRErrorKindNotFound, [MRError kindForError:movieError],
                          @"movie episode request is not found");
    MRAssertEqualIntegers(0, (NSInteger)[movieContext.http requestCount],
                          @"movie episode request sends no HTTP");
    [movieContext teardown];
}

static void MRRunFreshCacheTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                                headers:MRTrendingHeaders()
                                                                   data:MRFixtureData(@"trending-week")
                                                         transportError:nil]];

    __block NSUInteger completions = 0;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *error) {
        completions += 1;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions == 1; }, 2.0),
                 @"first trending fetch completes");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"first trending fetch sends a request");

    __block NSUInteger secondCompletions = 0;
    __block NSDictionary *cached = nil;
    __block NSError *cachedError = nil;
    id<MRHTTPTask> cachedTask = [context.client fetchTrendingWeekWithCompletion:
                                 ^(NSDictionary *json, NSError *error) {
        secondCompletions += 1;
        cached = json;
        cachedError = error;
    }];
    MRAssertTrue(cachedTask == nil, @"fresh cache hit returns no task");
    MRAssertTrue(MRRunUntil(^BOOL { return secondCompletions > 0; }, 2.0),
                 @"cached completion delivered");
    MRPumpMain();

    MRAssertEqualIntegers(1, (NSInteger)secondCompletions,
                          @"cached completion exactly once");
    MRAssertTrue(cachedError == nil, @"cached response has no error");
    MRAssertEqualObjects(MRFixture(@"trending-week"), cached,
                         @"cached response reuses the body");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"fresh cache hit sends no HTTP request");
    MRAssertEqualIntegers(0, context.tokenProvider.calls,
                          @"cached read never asks for a token");

    [context teardown];
}

static void MRRunGenreAndDetailCacheTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSArray *genre = @[ @{ @"id": @"action", @"name": @"Action" } ];
    [context.http enqueueResponse:MRResponseWithJSON(200, genre, nil)];
    [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                                headers:nil
                                                                   data:MRFixtureData(@"movie-detail")
                                                         transportError:nil]];

    __block NSUInteger completions = 0;
    [context.client fetchGenreIndexForType:MRMediaTypeMovie completion:
     ^(NSArray *json, NSError *error) {
        completions += 1;
    }];
    [context.client fetchDetailForType:MRMediaTypeMovie simklID:342994 completion:
     ^(NSDictionary *json, NSError *error) {
        completions += 1;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions == 2; }, 2.0),
                 @"genre and detail first fetches complete");
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"genre and detail first fetches use HTTP");

    __block NSUInteger cachedCompletions = 0;
    __block NSArray *cachedGenre = nil;
    __block NSDictionary *cachedDetail = nil;
    id<MRHTTPTask> genreTask = [context.client fetchGenreIndexForType:MRMediaTypeMovie
                                                           completion:^(NSArray *json, NSError *error) {
        cachedCompletions += 1;
        cachedGenre = json;
    }];
    id<MRHTTPTask> detailTask = [context.client fetchDetailForType:MRMediaTypeMovie
                                                          simklID:342994
                                                        completion:^(NSDictionary *json, NSError *error) {
        cachedCompletions += 1;
        cachedDetail = json;
    }];
    MRAssertTrue(genreTask == nil, @"genre cache hit returns no task");
    MRAssertTrue(detailTask == nil, @"detail cache hit returns no task");
    MRAssertTrue(MRRunUntil(^BOOL { return cachedCompletions == 2; }, 2.0),
                 @"genre and detail cached completions complete");
    MRAssertEqualObjects(genre, cachedGenre, @"genre cache reuses the array");
    MRAssertEqualObjects(MRFixture(@"movie-detail"), cachedDetail,
                         @"detail cache reuses the dictionary");
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"genre and detail cache hits send no HTTP request");

    [context teardown];
}

static void MRRun304RefreshTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                                headers:MRTrendingHeaders()
                                                                   data:MRFixtureData(@"trending-week")
                                                         transportError:nil]];

    __block NSUInteger completions = 0;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *error) {
        completions += 1;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions == 1; }, 2.0),
                 @"304 setup fetch completes");

    NSString *URL = MRTrendingURL();
    NSDate *oldFetchedAt = [context.cache fetchedAtForURL:URL];
    MRAssertTrue(oldFetchedAt != nil, @"304 setup stored fetchedAt");
    MRMakeEntryStale(context.directory, URL);
    NSDate *staleFetchedAt = [context.cache fetchedAtForURL:URL];
    MRAssertTrue(staleFetchedAt != nil &&
                 [staleFetchedAt timeIntervalSinceDate:oldFetchedAt] < -1000.0,
                 @"304 setup entry is stale");

    [context.http enqueueResponse:[MRHTTPResponse responseWithStatusCode:304
                                                                headers:nil
                                                                   data:nil
                                                         transportError:nil]];

    __block NSUInteger secondCompletions = 0;
    __block NSDictionary *body = nil;
    __block NSError *error = nil;
    id<MRHTTPTask> task = [context.client fetchTrendingWeekWithCompletion:
                           ^(NSDictionary *json, NSError *resultError) {
        secondCompletions += 1;
        body = json;
        error = resultError;
    }];
    MRAssertTrue(task != nil, @"stale cache triggers a task");
    MRAssertTrue(MRRunUntil(^BOOL { return secondCompletions > 0; }, 2.0),
                 @"304 completion delivered");

    MRAssertTrue(error == nil, @"304 reuses the cached body");
    MRAssertEqualObjects(MRFixture(@"trending-week"), body,
                         @"304 cached body returned");
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"304 follows one stale HTTP request");
    MRHTTPRequest *request = [context.http requestAtIndex:1];
    MRAssertEqualObjects(@"Wed, 04 Nov 2026 11:55:00 GMT",
                         [request.headers objectForKey:@"If-Modified-Since"],
                         @"304 request carries If-Modified-Since");
    MRAssertTrue([context.cache lastModifiedForURL:URL] != nil,
                 @"304 keeps the stored Last-Modified");
    NSDate *refreshedAt = [context.cache fetchedAtForURL:URL];
    MRAssertTrue(refreshedAt != nil && [refreshedAt timeIntervalSinceNow] > -5.0,
                 @"304 refreshes the cache timestamp");

    [context teardown];
}

static void MRRunAuthorizationRequiredTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:MRResponseWithBody(401,
                                                     @"{\"error\":\"user_token_failed\"}",
                                                     nil)];
    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"401 completion delivered without advancing the clock");
    MRAssertEqualIntegers(MRErrorKindAuthExpired, [MRError kindForError:error],
                          @"401 user_token_failed maps to AuthExpired");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"401 is not retried");
    MRAssertEqualIntegers(1, (NSInteger)[[context.diagnostics records] count],
                          @"401 records one diagnostic");
    [context teardown];
}

static void MRRunDailyLimitTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSDictionary *headers = @{ @"Retry-After": @"3600",
                               @"X-RateLimit-Limit": @"500",
                               @"X-RateLimit-Remaining": @"0" };
    [context.http enqueueResponse:MRResponseWithBody(429,
                                                     @"{\"error\":\"user_limit_exceeded\"}",
                                                     headers)];
    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"daily limit completion delivered without a retry clock advance");
    MRAssertEqualIntegers(MRErrorKindDailyLimit, [MRError kindForError:error],
                          @"429 user_limit_exceeded maps to DailyLimit");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"daily limit is not retried");
    MRAssertEqualIntegers(0, context.quota.remaining,
                          @"daily limit updates the quota remaining count");
    MRAssertEqualIntegers(500, context.quota.limit,
                          @"daily limit updates the quota limit");
    MRAssertTrue(context.quota.resetAt != nil,
                 @"daily limit records the reset date");
    NSTimeInterval resetDistance = [context.quota.resetAt timeIntervalSinceNow];
    MRAssertTrue(resetDistance > 3500.0 && resetDistance < 3700.0,
                 @"daily reset is seconds from now");
    [context teardown];
}

static void MRRunNotFoundTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:MRResponseWithBody(400,
                                                     @"{\"error\":\"id_err\"}",
                                                     nil)];
    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchDetailForType:MRMediaTypeMovie
                              simklID:342994
                            completion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"400 completion delivered without a retry clock advance");
    MRAssertEqualIntegers(MRErrorKindNotFound, [MRError kindForError:error],
                          @"400 id_err maps to NotFound");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"400 id_err is not retried");
    [context teardown];
}

static void MRRunParseFailureTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    [context.http enqueueResponse:MRResponseWithBody(200, @"not json", nil)];
    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"parse failure completion delivered without a retry clock advance");
    MRAssertEqualIntegers(MRErrorKindParse, [MRError kindForError:error],
                          @"malformed JSON maps to Parse");
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"parse failure is not retried");
    MRAssertEqualIntegers(1, (NSInteger)[[context.diagnostics records] count],
                          @"parse failure records one diagnostic");
    [context teardown];
}

static void MRRunServerRetryTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSMutableArray *responses = [NSMutableArray array];
    for (NSUInteger index = 0; index < 6; index += 1) {
        [responses addObject:MRResponseWithBody(500, @"{\"error\":\"server_error\"}", nil)];
    }
    [context.http enqueueResponses:responses];

    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];

    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"server failure starts with one request");
    MRAssertEqualIntegers(0, (NSInteger)completions,
                          @"server failure does not complete while retries are pending");
    MRAssertEqualIntegers(0, (NSInteger)[[context.diagnostics records] count],
                          @"retry attempts are not recorded in diagnostics");

    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"first server retry waits one second");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"first server retry fires at one second");

    [context.clock advanceBy:1.5];
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"second server retry waits two seconds");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(3, (NSInteger)[context.http requestCount],
                          @"second server retry fires at three seconds");

    [context.clock advanceBy:3.5];
    MRAssertEqualIntegers(3, (NSInteger)[context.http requestCount],
                          @"third server retry waits four seconds");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(4, (NSInteger)[context.http requestCount],
                          @"third server retry fires at seven seconds");

    [context.clock advanceBy:7.5];
    MRAssertEqualIntegers(4, (NSInteger)[context.http requestCount],
                          @"fourth server retry waits eight seconds");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(5, (NSInteger)[context.http requestCount],
                          @"fourth server retry fires at fifteen seconds");

    [context.clock advanceBy:15.5];
    MRAssertEqualIntegers(5, (NSInteger)[context.http requestCount],
                          @"fifth server retry waits sixteen seconds");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(6, (NSInteger)[context.http requestCount],
                          @"fifth server retry fires at thirty-one seconds");

    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"terminal server failure completes after six attempts");
    MRPumpMain();
    MRAssertEqualIntegers(1, (NSInteger)completions,
                          @"terminal server failure completes exactly once");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:error],
                          @"500 maps to Server after retries");
    MRAssertEqualIntegers(6, (NSInteger)[context.http requestCount],
                          @"server failure makes six total attempts");
    MRAssertEqualIntegers(1, (NSInteger)[[context.diagnostics records] count],
                          @"only the terminal server failure is recorded");
    MRAssertEqualObjects(MRTrendingURL(),
                         [[context.http requestAtIndex:5] URL],
                         @"retries reissue the same request");

    [context teardown];
}

static void MRRunBurstRetryTest(void) {
    MRAPIClientTestContext *context = [MRAPIClientTestContext context];
    NSDictionary *headers = @{ @"Retry-After": @"120",
                               @"X-RateLimit-Limit": @"500",
                               @"X-RateLimit-Remaining": @"10" };
    for (NSUInteger index = 0; index < 3; index += 1) {
        [context.http enqueueResponse:MRResponseWithBody(429,
                                                         @"{\"error\":\"rate_limit\"}",
                                                         headers)];
    }

    __block NSUInteger completions = 0;
    __block NSError *error = nil;
    [context.client fetchTrendingWeekWithCompletion:^(NSDictionary *json, NSError *resultError) {
        completions += 1;
        error = resultError;
    }];

    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"burst failure starts with one request");
    MRAssertEqualIntegers(10, context.quota.remaining,
                          @"burst 429 still reads quota remaining headers");
    MRAssertEqualIntegers(500, context.quota.limit,
                          @"burst 429 still reads the quota limit header");
    MRAssertTrue(context.quota.resetAt == nil,
                 @"burst 429 Retry-After does not move the daily reset");

    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(1, (NSInteger)[context.http requestCount],
                          @"first burst retry waits about one second");
    [context.clock advanceBy:0.5];
    MRAssertEqualIntegers(2, (NSInteger)[context.http requestCount],
                          @"first burst retry fires");
    [context.clock advanceBy:1.0];
    MRAssertEqualIntegers(3, (NSInteger)[context.http requestCount],
                          @"second burst retry fires");

    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"burst failure completes after three attempts");
    MRPumpMain();
    MRAssertEqualIntegers(1, (NSInteger)completions,
                          @"burst failure completes exactly once");
    MRAssertEqualIntegers(MRErrorKindRateLimitedBurst, [MRError kindForError:error],
                          @"429 rate_limit maps to RateLimitedBurst");
    MRAssertEqualIntegers(3, (NSInteger)[context.http requestCount],
                          @"burst failure makes three total attempts");
    MRAssertEqualIntegers(1, (NSInteger)[[context.diagnostics records] count],
                          @"only the terminal burst failure is recorded");
    MRAssertEqualIntegers(10, context.quota.remaining,
                          @"quota counts survive burst retries");
    MRAssertTrue(context.quota.resetAt == nil,
                 @"burst retry never sets the daily reset");

    [context teardown];
}

void MRRunAPIClientPublicTests(void) {
    MRRunTrendingURLTest();
    MRRunGenreURLTest();
    MRRunGenreFileURLTest();
    MRRunDetailURLTest();
    MRRunEpisodeURLTest();
    MRRunFreshCacheTest();
    MRRunGenreAndDetailCacheTest();
    MRRun304RefreshTest();
    MRRunAuthorizationRequiredTest();
    MRRunDailyLimitTest();
    MRRunNotFoundTest();
    MRRunParseFailureTest();
    MRRunServerRetryTest();
    MRRunBurstRetryTest();
}
