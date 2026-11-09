//
//  MRWriteServiceTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRAPIClient.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPResponse.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRStubHTTPClient.h"
#import "MRTokenProviding.h"
#import "MRWriteResult.h"
#import "MRWriteService.h"

#pragma mark - Token provider

@interface MRWriteTestTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, copy) NSString *token;
@end

@implementation MRWriteTestTokenProvider
- (void)validAccessTokenWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (completion != nil) {
        completion(self.token, nil);
    }
}
@end

#pragma mark - Context

@interface MRWriteTestContext : NSObject
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MRStubHTTPClient *http;
@property (nonatomic, strong) MRFakeClock *clock;
@property (nonatomic, strong) MRAPIClient *client;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRLibraryStore *store;
@property (nonatomic, strong) MRWriteService *service;
+ (instancetype)contextWithItems:(NSArray *)items;
- (void)teardown;
@end

@implementation MRWriteTestContext

+ (instancetype)contextWithItems:(NSArray *)items {
    MRWriteTestContext *context = [[self alloc] init];
    context.directory =
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MarqueeWriteTests-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:context.directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    context.http = [[MRStubHTTPClient alloc] init];
    context.clock = [[MRFakeClock alloc] init];
    MRResponseCache *cache = [[MRResponseCache alloc] initWithDirectory:context.directory];
    MRQuotaTracker *quota =
        [[MRQuotaTracker alloc] initWithDirectory:context.directory accountID:12345];
    MRDiagnostics *diagnostics =
        [[MRDiagnostics alloc] initWithDirectory:context.directory];
    MRWriteTestTokenProvider *tokenProvider = [[MRWriteTestTokenProvider alloc] init];
    tokenProvider.token = @"TOKEN-123";

    context.client = [[MRAPIClient alloc] initWithHTTPClient:context.http
                                              tokenProvider:tokenProvider
                                              responseCache:cache
                                               quotaTracker:quota
                                                diagnostics:diagnostics
                                                      clock:context.clock];

    context.storage = [[MRStorage alloc] initWithRootDirectory:context.directory
                                                     accountID:12345];
    context.outbox = [[MROutbox alloc] initWithStorage:context.storage];
    context.store = [[MRLibraryStore alloc] initWithStorage:context.storage];

    if (items.count > 0) {
        NSError *error = nil;
        BOOL saved = [context.store replaceWithItems:items
                                          activities:@{}
                                             profile:nil
                                               error:&error];
        MRAssertTrue(saved, @"seed the library snapshot");
    }

    context.service =
        [[MRWriteService alloc] initWithAPIClient:context.client
                                          outbox:context.outbox
                                     libraryStore:context.store
                                           clock:context.clock];
    return context;
}

- (void)teardown {
    if (self.directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.directory error:NULL];
    }
}

@end

#pragma mark - Helpers

static MRMediaItem *MRWriteItem(MRMediaType type, NSInteger simklID,
                                NSString *title, MRWatchStatus status) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.type = type;
    item.simklID = simklID;
    item.slug = [title lowercaseString];
    item.title = title;
    item.year = 2022;
    item.watchStatus = status;
    item.externalIDs = @{ @"imdb": [NSString stringWithFormat:@"tt%ld", (long)simklID] };
    return item;
}

static MRHTTPResponse *MRWriteResponse(NSInteger statusCode, id object) {
    NSData *data = nil;
    if (object != nil) {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    }
    return [MRHTTPResponse responseWithStatusCode:statusCode
                                          headers:nil
                                             data:data
                                   transportError:nil];
}

static void MRWriteEnqueue(MRWriteTestContext *context, NSArray *entries) {
    NSError *error = nil;
    for (MROutboxEntry *entry in entries) {
        BOOL saved = [context.outbox enqueueEntry:entry error:&error];
        MRAssertTrue(saved, @"enqueue an outbox entry");
    }
}

static MRWriteResult *MRWriteSend(MRWriteTestContext *context, NSArray *entries) {
    __block MRWriteResult *result = nil;
    [context.service sendEntries:entries completion:^(MRWriteResult *writeResult) {
        result = writeResult;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return result != nil;
    }, 3.0), @"write service completes");
    return result;
}

static MRWriteResult *MRWriteSendAdvancing(MRWriteTestContext *context, NSArray *entries) {
    __block MRWriteResult *result = nil;
    [context.service sendEntries:entries completion:^(MRWriteResult *writeResult) {
        result = writeResult;
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
    while (result == nil && [deadline timeIntervalSinceNow] > 0) {
        [context.clock advanceBy:1.1];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return result;
}

static NSDictionary *MRWriteBody(MRHTTPRequest *request) {
    if (request.body.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:NULL];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL MRWriteStringContains(NSString *string, NSString *needle) {
    return string != nil && [string rangeOfString:needle].location != NSNotFound;
}

#pragma mark - Tests

static void MRRunStatusWriteBody(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 123, @"The Bear",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{
        @"added": @{ @"shows": @[ @{ @"ids": @{ @"simkl": @123 },
                                      @"to": @"watching" } ] }
    })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"status write completes");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"status write sends one request");
    MRHTTPRequest *request = [context.http requestAtIndex:0];
    MRAssertEqualObjects(@"POST", request.method, @"status write is a POST");
    MRAssertTrue(MRWriteStringContains(request.URL, @"/sync/add-to-list"),
                 @"status write path");
    MRAssertEqualObjects(@{
        @"shows": @[ @{ @"ids": @{ @"simkl": @123 },
                        @"to": @"watching" } ]
    }, MRWriteBody(request), @"exact status body");
    NSString *bodyString = [[NSString alloc] initWithData:request.body
                                                 encoding:NSUTF8StringEncoding];
    MRAssertTrue(!MRWriteStringContains(bodyString, @"allow_rewatch"),
                 @"status body never contains allow_rewatch");
    MRAssertTrue(!MRWriteStringContains(request.URL, @"allow_rewatch"),
                 @"status URL never contains allow_rewatch");

    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"successful status write leaves the outbox");
    MRAssertEqualIntegers(1, (NSInteger)result.succeededEntries.count,
                          @"status result reports success");
    MRAssertEqualIntegers(0, (NSInteger)result.permanentlyFailedEntries.count,
                          @"status result has no permanent failure");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];
    MRAssertEqualIntegers(MRWatchStatusWatching, stored.watchStatus,
                          @"status write reconciles the store");
    [context teardown];
}

static void MRRunAnimeHistoryResolvesStatus(void) {
    MRMediaItem *anime = MRWriteItem(MRMediaTypeAnime, 456, @"Frieren",
                                     MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ anime ]];
    MROutboxEntry *entry =
        [MROutboxEntry historyWholeEntryWithItem:anime
                                          status:MRWatchStatusCompleted];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{
        @"added": @{ @"statuses": @[ @{
            @"ids": @{ @"simkl": @456 },
            @"response": @{ @"status": @"watching" }
        } ] }
    })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"history write completes");
    MRAssertEqualObjects(@{
        @"shows": @[ @{ @"ids": @{ @"simkl": @456 },
                        @"status": @"completed" } ]
    }, MRWriteBody([context.http requestAtIndex:0]),
       @"anime whole history is sent under shows with the requested status");
    MRAssertEqualIntegers(MRWatchStatusWatching,
                          [[result.resolvedStatuses objectForKey:entry.entryID] integerValue],
                          @"result reports the server-resolved status");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeAnime simklID:456];
    MRAssertEqualIntegers(MRWatchStatusWatching, stored.watchStatus,
                          @"resolved watching status updates the local snapshot");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"resolved history write leaves the outbox");
    [context teardown];
}

static void MRRunEpisodeHistoryBody(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 321, @"Severance",
                                    MRWatchStatusWatching);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry historyEpisodeEntryWithItem:show season:2 episode:5];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"episode write completes");
    MRAssertEqualObjects(@{
        @"shows": @[ @{
            @"ids": @{ @"simkl": @321 },
            @"seasons": @[ @{
                @"number": @2,
                @"episodes": @[ @{ @"number": @5 } ]
            } ]
        } ]
    }, MRWriteBody([context.http requestAtIndex:0]), @"exact episode body");
    NSString *bodyString =
        [[NSString alloc] initWithData:[context.http requestAtIndex:0].body
                              encoding:NSUTF8StringEncoding];
    MRAssertTrue(!MRWriteStringContains(bodyString, @"allow_rewatch"),
                 @"episode body never contains allow_rewatch");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"episode write leaves the outbox");
    [context teardown];
}

static void MRRunMovieHistoryBody(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 789, @"Arrival",
                                     MRWatchStatusCompleted);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie ]];
    MROutboxEntry *entry =
        [MROutboxEntry historyWholeEntryWithItem:movie
                                          status:MRWatchStatusCompleted];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"movie history write completes");
    MRAssertEqualObjects(@{
        @"movies": @[ @{ @"ids": @{ @"simkl": @789 } } ]
    }, MRWriteBody([context.http requestAtIndex:0]),
       @"whole movie history sends only the Simkl ID");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"movie history write leaves the outbox");
    [context teardown];
}

static void MRRunMixedTypeStatusBody(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 100, @"Movie",
                                     MRWatchStatusPlanToWatch);
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 200, @"Show",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie, show ]];
    MROutboxEntry *movieEntry =
        [MROutboxEntry statusEntryWithItem:movie
                                   status:MRWatchStatusCompleted
                           previousStatus:MRWatchStatusPlanToWatch];
    MROutboxEntry *showEntry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ movieEntry, showEntry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *result = MRWriteSend(context, @[ movieEntry, showEntry ]);
    MRAssertTrue(result != nil, @"mixed status write completes");
    MRAssertEqualObjects(@{
        @"movies": @[ @{ @"ids": @{ @"simkl": @100 },
                        @"to": @"completed" } ],
        @"shows": @[ @{ @"ids": @{ @"simkl": @200 },
                       @"to": @"watching" } ]
    }, MRWriteBody([context.http requestAtIndex:0]),
       @"mixed status batch groups by media type");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"mixed status batch leaves the outbox");
    [context teardown];
}

static void MRRunRatingBody(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 789, @"Arrival",
                                     MRWatchStatusCompleted);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie ]];
    MROutboxEntry *entry =
        [MROutboxEntry ratingEntryWithItem:movie rating:8 previousRating:0];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"rating write completes");
    MRAssertTrue(MRWriteStringContains([context.http requestAtIndex:0].URL,
                                       @"/sync/ratings"),
                 @"rating write path");
    MRAssertEqualObjects(@{
        @"movies": @[ @{ @"ids": @{ @"simkl": @789 }, @"rating": @8 } ]
    }, MRWriteBody([context.http requestAtIndex:0]), @"exact rating body");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeMovie simklID:789];
    MRAssertEqualIntegers(8, stored.userRating, @"rating writes reconcile the store");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"rating write leaves the outbox");
    [context teardown];
}

static void MRRunRatingRemovalBody(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 789, @"Arrival",
                                     MRWatchStatusCompleted);
    movie.userRating = 8;
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie ]];
    MROutboxEntry *entry =
        [MROutboxEntry ratingRemoveEntryWithItem:movie previousRating:8];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"rating removal completes");
    MRAssertTrue(MRWriteStringContains([context.http requestAtIndex:0].URL,
                                       @"/sync/ratings/remove"),
                 @"rating removal path");
    MRAssertEqualObjects(@{
        @"movies": @[ @{ @"ids": @{ @"simkl": @789 } } ]
    }, MRWriteBody([context.http requestAtIndex:0]), @"rating removal body");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeMovie simklID:789];
    MRAssertEqualIntegers(0, stored.userRating,
                          @"rating removal clears the local rating");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"rating removal leaves the outbox");
    [context teardown];
}

static void MRRunRemoveBodyAndStore(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 321, @"Severance",
                                    MRWatchStatusWatching);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry removeEntryWithItem:show
                            previousStatus:MRWatchStatusWatching
                            previousRating:0];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{
        @"deleted": @{ @"shows": @[ @321 ] }
    })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"remove write completes");
    MRAssertTrue(MRWriteStringContains([context.http requestAtIndex:0].URL,
                                       @"/sync/history/remove"),
                 @"remove write path");
    NSDictionary *body = MRWriteBody([context.http requestAtIndex:0]);
    MRAssertEqualObjects(@{
        @"shows": @[ @{ @"ids": @{ @"simkl": @321 } } ]
    }, body, @"remove body is the whole item without to or status");
    MRAssertTrue([body objectForKey:@"to"] == nil, @"remove body has no to key");
    MRAssertTrue(MRWriteStringContains(
        [[NSString alloc] initWithData:[context.http requestAtIndex:0].body
                              encoding:NSUTF8StringEncoding],
        @"simkl"), @"remove body names the item");
    MRAssertTrue([context.store itemForType:MRMediaTypeShow simklID:321] == nil,
                 @"successful remove deletes the local item");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"remove write leaves the outbox");
    [context teardown];
}

static void MRRunNotFoundIsPermanent(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 123, @"The Bear",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{
        @"not_found": @{ @"shows": @[ @123 ] }
    })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"not_found write completes");
    MRAssertEqualIntegers(1, (NSInteger)result.permanentlyFailedEntries.count,
                          @"not_found is a permanent failure");
    MRAssertEqualIntegers(0, (NSInteger)result.succeededEntries.count,
                          @"not_found is not a success");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"a permanent failure drops the outbox entry");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"a permanent failure is not retried");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];
    MRAssertEqualIntegers(MRWatchStatusPlanToWatch, stored.watchStatus,
                          @"not_found leaves the local item unchanged");
    [context.clock advanceBy:5.0];
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"permanent failure schedules no later retry");
    [context teardown];
}

static void MRRunClientRejectedIsPermanent(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 55, @"Arrival",
                                     MRWatchStatusNone);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:movie
                                   status:MRWatchStatusPlanToWatch
                           previousStatus:MRWatchStatusNone];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(412, @{ @"error": @"invalid" })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"client rejection completes");
    MRAssertEqualIntegers(1, (NSInteger)result.permanentlyFailedEntries.count,
                          @"client rejection is permanent");
    MRAssertEqualIntegers(0, (NSInteger)result.succeededEntries.count,
                          @"client rejection is not a success");
    MRAssertEqualIntegers(MRErrorKindClientRejected,
                          [MRError kindForError:result.error],
                          @"the result carries the client rejection");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"client rejection drops the outbox entry");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"client rejection is not retried");
    [context.clock advanceBy:20.0];
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"client rejection schedules no later retry");
    [context teardown];
}

static void MRRunValidationRejectionIsPermanent(void) {
    MRMediaItem *movie = MRWriteItem(MRMediaTypeMovie, 56, @"Moon",
                                     MRWatchStatusNone);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ movie ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:movie
                                   status:MRWatchStatusPlanToWatch
                           previousStatus:MRWatchStatusNone];
    MRWriteEnqueue(context, @[ entry ]);
    [context.http enqueueResponse:MRWriteResponse(400, @{ @"error": @"invalid" })];

    MRWriteResult *result = MRWriteSend(context, @[ entry ]);
    MRAssertTrue(result != nil, @"validation rejection completes");
    MRAssertEqualIntegers(1, (NSInteger)result.permanentlyFailedEntries.count,
                          @"unrecognized validation is permanent");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"validation rejection drops the outbox entry");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"validation rejection is not retried");
    [context teardown];
}

static void MRRunServerRetryStaysQueued(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 123, @"The Bear",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ entry ]);
    for (NSInteger index = 0; index < 6; index += 1) {
        [context.http enqueueResponse:MRWriteResponse(500, @{ @"error": @"server" })];
    }

    MRWriteResult *result = MRWriteSendAdvancing(context, @[ entry ]);
    MRAssertTrue(result != nil, @"server retries eventually complete");
    MRAssertEqualIntegers(6, (NSInteger)context.http.requestCount,
                          @"server errors retry five times after the first attempt");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"a transient server failure keeps the entry queued");
    MRAssertEqualIntegers(6, [[context.outbox.entries firstObject] attempts],
                          @"attempts are persisted");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:result.error],
                          @"the result carries the transient error");
    MRAssertEqualIntegers(0, (NSInteger)result.succeededEntries.count,
                          @"a transient failure has no successes");
    MRAssertEqualIntegers(0, (NSInteger)result.permanentlyFailedEntries.count,
                          @"a transient failure is not permanent");
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];
    MRAssertEqualIntegers(MRWatchStatusPlanToWatch, stored.watchStatus,
                          @"a transient failure does not undo local state");
    [context teardown];
}

static void MRRunBurstRetryPolicy(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 123, @"The Bear",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ entry ]);
    for (NSInteger index = 0; index < 3; index += 1) {
        [context.http enqueueResponse:MRWriteResponse(429, @{ @"error": @"rate_limit" })];
    }

    MRWriteResult *result = MRWriteSendAdvancing(context, @[ entry ]);
    MRAssertTrue(result != nil, @"burst retries complete");
    MRAssertEqualIntegers(3, (NSInteger)context.http.requestCount,
                          @"burst errors retry twice after the first attempt");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"burst failure keeps the entry queued");
    MRAssertEqualIntegers(3, [[context.outbox.entries firstObject] attempts],
                          @"burst attempts are persisted");
    [context teardown];
}

static void MRRunWriteLockedRetryPolicy(void) {
    MRMediaItem *show = MRWriteItem(MRMediaTypeShow, 123, @"The Bear",
                                    MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ show ]];
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:show
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ entry ]);
    for (NSInteger index = 0; index < 4; index += 1) {
        [context.http enqueueResponse:MRWriteResponse(400, @{ @"error": @"RATE_LIMIT" })];
    }

    MRWriteResult *result = MRWriteSendAdvancing(context, @[ entry ]);
    MRAssertTrue(result != nil, @"write-lock retries complete");
    MRAssertEqualIntegers(4, (NSInteger)context.http.requestCount,
                          @"write-lock errors retry three times after the first attempt");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"write-lock failure keeps the entry queued");
    MRAssertEqualIntegers(4, [[context.outbox.entries firstObject] attempts],
                          @"write-lock attempts are persisted");
    [context teardown];
}

static void MRRunPostsAreSpaced(void) {
    MRMediaItem *first = MRWriteItem(MRMediaTypeShow, 100, @"First",
                                     MRWatchStatusPlanToWatch);
    MRMediaItem *second = MRWriteItem(MRMediaTypeShow, 200, @"Second",
                                      MRWatchStatusPlanToWatch);
    MRWriteTestContext *context = [MRWriteTestContext contextWithItems:@[ first, second ]];
    MROutboxEntry *firstEntry =
        [MROutboxEntry statusEntryWithItem:first
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MROutboxEntry *secondEntry =
        [MROutboxEntry statusEntryWithItem:second
                                   status:MRWatchStatusWatching
                           previousStatus:MRWatchStatusPlanToWatch];
    MRWriteEnqueue(context, @[ firstEntry, secondEntry ]);
    [context.http enqueueResponse:MRWriteResponse(200, @{})];
    [context.http enqueueResponse:MRWriteResponse(200, @{})];

    MRWriteResult *firstResult = MRWriteSend(context, @[ firstEntry ]);
    MRAssertTrue(firstResult != nil, @"first spaced write completes");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"first spaced write sends immediately");

    __block MRWriteResult *secondResult = nil;
    [context.service sendEntries:@[ secondEntry ] completion:^(MRWriteResult *result) {
        secondResult = result;
    }];
    BOOL completedTooSoon = MRRunUntil(^BOOL {
        return secondResult != nil;
    }, 0.2);
    MRAssertTrue(!completedTooSoon, @"second write waits for the spacing gate");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"second write is not sent before 1.1 seconds");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"the queued second write remains pending");

    [context.clock advanceBy:1.1];
    MRAssertTrue(MRRunUntil(^BOOL {
        return secondResult != nil;
    }, 2.0), @"second write completes after the spacing gate");
    MRAssertEqualIntegers(2, (NSInteger)context.http.requestCount,
                          @"second write is sent after 1.1 seconds");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"both spaced writes leave the outbox");
    [context teardown];
}

void MRRunWriteServiceTests(void) {
    MRRunStatusWriteBody();
    MRRunAnimeHistoryResolvesStatus();
    MRRunEpisodeHistoryBody();
    MRRunMovieHistoryBody();
    MRRunMixedTypeStatusBody();
    MRRunRatingBody();
    MRRunRatingRemovalBody();
    MRRunRemoveBodyAndStore();
    MRRunNotFoundIsPermanent();
    MRRunClientRejectedIsPermanent();
    MRRunValidationRejectionIsPermanent();
    MRRunServerRetryStaysQueued();
    MRRunBurstRetryPolicy();
    MRRunWriteLockedRetryPolicy();
    MRRunPostsAreSpaced();
}
