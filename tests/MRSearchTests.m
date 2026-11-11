//
//  MRSearchTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRAPIClient.h"
#import "MRClock.h"
#import "MRDiagnostics.h"
#import "MRHTTPResponse.h"
#import "MRHTTPRequest.h"
#import "MRMediaItem.h"
#import "MRPreferencesStore.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRSearchPagination.h"
#import "MRStorage.h"
#import "MRStubHTTPClient.h"
#import "MRTokenProviding.h"
#import "MRURLBuilder.h"

@interface MRSearchTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, copy) NSString *token;
@end

@implementation MRSearchTokenProvider

- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    if (completion != nil) {
        completion(self.token, nil);
    }
}

@end

static NSString *MRSearchTestRoot(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"marquee-search-%@",
             [[NSProcessInfo processInfo] globallyUniqueString]]];
}

static NSData *MRSearchJSONData(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
}

void MRRunSearchTests(void) {
    // URL encoding covers spaces, colons, ampersands, and non-ASCII text.
    {
        NSString *URL = [MRURLBuilder searchURLWithQuery:@"Amélie & Co: Part 2" page:3];
        MRAssertTrue([URL rangeOfString:@"q=Am%C3%A9lie%20%26%20Co%3A%20Part%202"].location != NSNotFound,
                     @"search query is strictly percent-encoded");
        MRAssertTrue([URL rangeOfString:@"extended=full"].location != NSNotFound,
                     @"search requests full records");
        MRAssertTrue([URL rangeOfString:@"limit=30"].location != NSNotFound,
                     @"search requests thirty results");
        MRAssertTrue([URL rangeOfString:@"page=3"].location != NSNotFound,
                     @"search includes the requested page");
    }

    // endpoint_type selects the media type, and ids.simkl_id is the identity.
    {
        MRMediaItem *movie = [MRMediaItem itemWithSearchDictionary:@{
            @"endpoint_type": @"movies",
            @"title": @"Dune",
            @"ids": @{ @"simkl_id": @(342994) }
        }];
        MRMediaItem *show = [MRMediaItem itemWithSearchDictionary:@{
            @"endpoint_type": @"tv",
            @"title": @"The Bear",
            @"ids": @{ @"simkl_id": @(1515418) }
        }];
        MRMediaItem *anime = [MRMediaItem itemWithSearchDictionary:@{
            @"endpoint_type": @"anime",
            @"title": @"Frieren",
            @"ids": @{ @"simkl_id": @(4162) }
        }];

        MRAssertEqualIntegers(MRMediaTypeMovie, movie.type,
                              @"movies endpoint maps to a movie");
        MRAssertEqualIntegers(MRMediaTypeShow, show.type,
                              @"tv endpoint maps to a show");
        MRAssertEqualIntegers(MRMediaTypeAnime, anime.type,
                              @"anime endpoint maps to anime");
        MRAssertEqualIntegers(342994, movie.simklID,
                              @"a search result uses ids.simkl_id");
    }

    // Recent searches deduplicate case-insensitively and cap at eight.
    {
        NSString *root = MRSearchTestRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:7];
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        [preferences recordSearch:@"Dune" error:NULL];
        [preferences recordSearch:@"DUNE" error:NULL];
        [preferences recordSearch:@"  The Bear  " error:NULL];
        MRAssertEqualIntegers(2, (NSInteger)preferences.searchHistory.count,
                              @"recent searches deduplicate case-insensitively");
        MRAssertEqualObjects(@"The Bear", [preferences.searchHistory objectAtIndex:0],
                             @"the newest search is first");

        for (NSInteger index = 0; index < 10; index++) {
            [preferences recordSearch:[NSString stringWithFormat:@"Query %ld", (long)index]
                                error:NULL];
        }
        MRAssertEqualIntegers(8, (NSInteger)preferences.searchHistory.count,
                              @"recent searches cap at eight");
        MRAssertEqualObjects(@"Query 9", [preferences.searchHistory objectAtIndex:0],
                             @"the cap keeps the newest searches");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // Pagination rules: three characters, thirty results, five pages.
    {
        MRAssertTrue(![MRSearchPagination shouldSearchForQuery:@""],
                     @"an empty query never searches");
        MRAssertTrue(![MRSearchPagination shouldSearchForQuery:@"  ab  "],
                     @"queries shorter than three characters do not search");
        MRAssertTrue([MRSearchPagination shouldSearchForQuery:@"  abc  "],
                     @"three non-space characters start a search");
        MRAssertTrue(![MRSearchPagination shouldSearchForQuery:nil],
                     @"a nil query never searches");

        MRAssertTrue([MRSearchPagination canLoadMoreForPage:1 resultCount:30],
                     @"a full first page offers more");
        MRAssertTrue(![MRSearchPagination canLoadMoreForPage:1 resultCount:29],
                     @"a short page does not offer more");
        MRAssertTrue(![MRSearchPagination canLoadMoreForPage:5 resultCount:30],
                     @"the fifth page never offers more");
        MRAssertEqualIntegers(2, (NSInteger)[MRSearchPagination nextPageForPage:1],
                              @"the next page increments by one");
        MRAssertEqualIntegers(5, (NSInteger)[MRSearchPagination nextPageForPage:5],
                              @"the next page is capped at five");
    }

    // The authenticated search request carries the bearer token and query.
    {
        NSString *root = MRSearchTestRoot();
        [[NSFileManager defaultManager] createDirectoryAtPath:root
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
        MRSearchTokenProvider *tokens = [[MRSearchTokenProvider alloc] init];
        tokens.token = @"search-token";
        MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:root];
        MRQuotaTracker *quota = [[MRQuotaTracker alloc] initWithDirectory:root accountID:7];
        MRDiagnostics *diagnostics = [[MRDiagnostics alloc] initWithDirectory:root];
        MRFakeClock *clock = [[MRFakeClock alloc] init];
        MRAPIClient *client = [[MRAPIClient alloc] initWithHTTPClient:http
                                                       tokenProvider:tokens
                                                       responseCache:cache
                                                        quotaTracker:quota
                                                         diagnostics:diagnostics
                                                               clock:clock];

        NSArray *payload = @[
            @{ @"endpoint_type": @"tv",
               @"title": @"The Bear",
               @"ids": @{ @"simkl_id": @(1515418) } }
        ];
        [http enqueueResponse:[MRHTTPResponse responseWithStatusCode:200
                                                            headers:nil
                                                               data:MRSearchJSONData(payload)
                                                     transportError:nil]];

        __block NSArray *received = nil;
        __block NSError *receivedError = nil;
        [client searchAllWithQuery:@"The Bear" page:2 completion:^(NSArray *json, NSError *error) {
            received = json;
            receivedError = error;
        }];
        MRAssertTrue(MRRunUntil(^BOOL { return received != nil || receivedError != nil; }, 2.0),
                     @"the search completion runs");

        MRAssertTrue(receivedError == nil, @"the search request succeeds");
        MRAssertEqualIntegers(1, (NSInteger)received.count,
                              @"the search response array is returned");
        MRHTTPRequest *request = [http lastRequest];
        MRAssertTrue([request.URL rangeOfString:@"/search/all?"].location != NSNotFound,
                     @"search calls the search/all endpoint");
        MRAssertTrue([request.URL rangeOfString:@"q=The%20Bear"].location != NSNotFound,
                     @"search encodes the query");
        MRAssertTrue([request.URL rangeOfString:@"page=2"].location != NSNotFound,
                     @"search sends the page");
        MRAssertTrue([request.URL rangeOfString:@"extended=full"].location != NSNotFound,
                     @"search requests full records");
        MRAssertTrue([request.URL rangeOfString:@"limit=30"].location != NSNotFound,
                     @"search requests thirty results");
        NSString *authorization = [request.headers objectForKey:@"Authorization"];
        MRAssertEqualObjects(@"Bearer search-token", authorization,
                             @"search sends the bearer token");
        MRAssertEqualIntegers(1, (NSInteger)quota.requestsToday,
                              @"search counts against the quota");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}
