//
//  MRWriteReconciliationTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRAPIClient.h"
#import "MRDetailActions.h"
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

@interface MRReconciliationTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, copy) NSString *token;
@end

@implementation MRReconciliationTokenProvider
- (void)validAccessTokenWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (completion != nil) {
        completion(self.token, nil);
    }
}
@end

@interface MRReconciliationContext : NSObject
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) MRStubHTTPClient *http;
@property (nonatomic, strong) MRFakeClock *clock;
@property (nonatomic, strong) MRAPIClient *client;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRLibraryStore *store;
@property (nonatomic, strong) MRWriteService *service;
@property (nonatomic, strong) MRDetailActions *actions;
+ (instancetype)contextWithItems:(NSArray *)items;
- (void)teardown;
@end

@implementation MRReconciliationContext

+ (instancetype)contextWithItems:(NSArray *)items {
    MRReconciliationContext *context = [[self alloc] init];
    context.directory =
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MarqueeReconciliationTests-%@",
                [[NSUUID UUID] UUIDString]]];
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
    MRReconciliationTokenProvider *tokenProvider =
        [[MRReconciliationTokenProvider alloc] init];
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
        MRAssertTrue([context.store replaceWithItems:items
                                          activities:@{}
                                             profile:nil
                                               error:&error],
                     @"seed the reconciliation library");
    }

    context.service =
        [[MRWriteService alloc] initWithAPIClient:context.client
                                          outbox:context.outbox
                                     libraryStore:context.store
                                           clock:context.clock];
    context.actions =
        [[MRDetailActions alloc] initWithLibraryStore:context.store
                                               outbox:context.outbox
                                         writeService:context.service];
    return context;
}

- (void)teardown {
    if (self.directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.directory error:NULL];
    }
}

@end

static MRMediaItem *MRReconciliationItem(MRMediaType type, NSInteger simklID,
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

static MRHTTPResponse *MRReconciliationResponse(NSInteger statusCode, id object) {
    NSData *data = nil;
    if (object != nil) {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    }
    return [MRHTTPResponse responseWithStatusCode:statusCode
                                          headers:nil
                                             data:data
                                   transportError:nil];
}

static MRWriteResult *MRReconciliationFlush(MRReconciliationContext *context) {
    __block MRWriteResult *result = nil;
    [context.actions flushWithCompletion:^(MRWriteResult *writeResult) {
        result = writeResult;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return result != nil;
    }, 3.0), @"reconciliation flush completes");
    return result;
}

static MRWriteResult *MRReconciliationFlushAdvancing(MRReconciliationContext *context) {
    __block MRWriteResult *result = nil;
    [context.actions flushWithCompletion:^(MRWriteResult *writeResult) {
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

static void MRRunResolvedStatusReconciliation(void) {
    MRMediaItem *show = MRReconciliationItem(MRMediaTypeShow, 123, @"The Bear",
                                             MRWatchStatusPlanToWatch);
    MRReconciliationContext *context = [MRReconciliationContext contextWithItems:@[ show ]];
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];

    __block NSUInteger libraryChanges = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRLibraryDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        libraryChanges += 1;
    }];

    NSError *error = nil;
    MROutboxEntry *entry =
        [context.actions setWatchStatus:MRWatchStatusCompleted
                                forItem:stored
                                  error:&error];
    MRAssertTrue(entry != nil, @"completed status action enqueues");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"completed status is in the outbox");
    MRAssertEqualIntegers(MRWatchStatusCompleted,
                          [context.store itemForType:MRMediaTypeShow simklID:123].watchStatus,
                          @"completed status is optimistic");

    [context.http enqueueResponse:MRReconciliationResponse(200, @{
        @"added": @{ @"statuses": @[ @{
            @"ids": @{ @"simkl": @123 },
            @"response": @{ @"status": @"watching" }
        } ] }
    })];

    MRWriteResult *result = MRReconciliationFlush(context);
    MRAssertTrue(result != nil, @"resolved status write completes");
    MRAssertEqualIntegers(MRWatchStatusWatching,
                          [context.store itemForType:MRMediaTypeShow simklID:123].watchStatus,
                          @"server-resolved watching replaces the optimistic completed");
    MRAssertEqualIntegers(MRWatchStatusWatching,
                          [[result.resolvedStatuses objectForKey:entry.entryID] integerValue],
                          @"result carries the resolved status");
    MRAssertTrue(libraryChanges >= 2,
                 @"optimistic and resolved mutations post library changes");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"resolved status leaves the outbox");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [context teardown];
}

static void MRRunNotFoundLeavesLocalItem(void) {
    MRMediaItem *show = MRReconciliationItem(MRMediaTypeShow, 123, @"The Bear",
                                             MRWatchStatusPlanToWatch);
    MRReconciliationContext *context = [MRReconciliationContext contextWithItems:@[ show ]];
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];

    NSError *error = nil;
    MROutboxEntry *entry =
        [context.actions setWatchStatus:MRWatchStatusCompleted
                                forItem:stored
                                  error:&error];
    MRAssertTrue(entry != nil, @"not_found action enqueues");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"not_found action starts queued");

    [context.http enqueueResponse:MRReconciliationResponse(200, @{
        @"not_found": @{ @"shows": @[ @123 ] }
    })];

    MRWriteResult *result = MRReconciliationFlush(context);
    MRAssertTrue(result != nil, @"not_found write completes");
    MRAssertEqualIntegers(1, (NSInteger)result.permanentlyFailedEntries.count,
                          @"not_found is permanent");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"not_found drops the outbox entry");
    MRMediaItem *after = [context.store itemForType:MRMediaTypeShow simklID:123];
    MRAssertTrue(after != nil, @"not_found does not remove the local item");
    MRAssertEqualIntegers(MRWatchStatusCompleted, after.watchStatus,
                          @"not_found leaves the service-level local item unchanged");
    [context teardown];
}

static void MRRunTransientFailureKeepsOptimisticState(void) {
    MRMediaItem *show = MRReconciliationItem(MRMediaTypeShow, 123, @"The Bear",
                                             MRWatchStatusPlanToWatch);
    MRReconciliationContext *context = [MRReconciliationContext contextWithItems:@[ show ]];
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:123];

    NSError *error = nil;
    MROutboxEntry *entry =
        [context.actions setWatchStatus:MRWatchStatusWatching
                                forItem:stored
                                  error:&error];
    MRAssertTrue(entry != nil, @"watching action enqueues");
    for (NSInteger index = 0; index < 6; index += 1) {
        [context.http enqueueResponse:MRReconciliationResponse(500, @{ @"error": @"server" })];
    }

    MRWriteResult *result = MRReconciliationFlushAdvancing(context);
    MRAssertTrue(result != nil, @"transient write eventually returns");
    MRAssertEqualIntegers(6, (NSInteger)context.http.requestCount,
                          @"server retries are exhausted");
    MRAssertEqualIntegers(1, (NSInteger)context.outbox.entries.count,
                          @"transient failure keeps the outbox entry");
    MRAssertEqualIntegers(6, [[context.outbox.entries firstObject] attempts],
                          @"transient attempts are persisted");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:result.error],
                          @"transient result carries the server error");
    MRAssertEqualIntegers(MRWatchStatusWatching,
                          [context.store itemForType:MRMediaTypeShow simklID:123].watchStatus,
                          @"transient failure leaves the optimistic status in place");
    [context teardown];
}

static void MRRunClearRatingReconciliation(void) {
    MRMediaItem *movie = MRReconciliationItem(MRMediaTypeMovie, 789, @"Arrival",
                                               MRWatchStatusCompleted);
    movie.userRating = 8;
    MRReconciliationContext *context = [MRReconciliationContext contextWithItems:@[ movie ]];
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeMovie simklID:789];

    NSError *error = nil;
    MROutboxEntry *entry = [context.actions clearRatingForItem:stored error:&error];
    MRAssertTrue(entry != nil, @"clear rating enqueues");
    MRAssertEqualIntegers(MROutboxEntryKindRatingRemove, entry.kind,
                          @"clear rating uses rating removal");
    MRAssertEqualIntegers(0,
                          [context.store itemForType:MRMediaTypeMovie simklID:789].userRating,
                          @"clear rating is optimistic");

    [context.http enqueueResponse:MRReconciliationResponse(200, @{})];
    MRWriteResult *result = MRReconciliationFlush(context);
    MRAssertTrue(result != nil, @"rating removal completes");
    MRAssertEqualIntegers(0,
                          [context.store itemForType:MRMediaTypeMovie simklID:789].userRating,
                          @"clear rating stays cleared after success");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"rating removal leaves the outbox");
    [context teardown];
}

static void MRRunRemoveOnlyAfterSuccess(void) {
    MRMediaItem *show = MRReconciliationItem(MRMediaTypeShow, 321, @"Severance",
                                             MRWatchStatusWatching);
    MRReconciliationContext *context = [MRReconciliationContext contextWithItems:@[ show ]];
    MRMediaItem *stored = [context.store itemForType:MRMediaTypeShow simklID:321];

    NSError *error = nil;
    MROutboxEntry *entry = [context.actions removeFromLibraryForItem:stored error:&error];
    MRAssertTrue(entry != nil, @"remove action enqueues");
    MRAssertEqualIntegers(MROutboxEntryKindRemove, entry.kind, @"remove kind");
    MRAssertTrue([context.store itemForType:MRMediaTypeShow simklID:321] != nil,
                 @"remove does not delete the local item before the response");

    [context.http enqueueResponse:MRReconciliationResponse(200, @{
        @"deleted": @{ @"shows": @[ @321 ] }
    })];
    MRWriteResult *result = MRReconciliationFlush(context);
    MRAssertTrue(result != nil, @"remove write completes");
    MRAssertTrue([context.store itemForType:MRMediaTypeShow simklID:321] == nil,
                 @"successful remove deletes the local item");
    MRAssertEqualIntegers(0, (NSInteger)context.outbox.entries.count,
                          @"remove leaves the outbox");
    [context teardown];
}

static void MRRunPrimaryActionTable(void) {
    MRMediaItem *item = MRReconciliationItem(MRMediaTypeMovie, 1, @"Movie",
                                             MRWatchStatusNone);
    MRAssertEqualIntegers(MRDetailPrimaryActionAddToWatchlist,
                          [MRDetailActions primaryActionForItem:item],
                          @"untracked primary action");
    item.watchStatus = MRWatchStatusPlanToWatch;
    MRAssertEqualIntegers(MRDetailPrimaryActionMarkWatched,
                          [MRDetailActions primaryActionForItem:item],
                          @"planned movie primary action");
    item.type = MRMediaTypeShow;
    MRAssertEqualIntegers(MRDetailPrimaryActionStartWatching,
                          [MRDetailActions primaryActionForItem:item],
                          @"planned show primary action");
    item.watchStatus = MRWatchStatusWatching;
    item.nextEpisodeSeason = 2;
    item.nextEpisodeNumber = 5;
    MRAssertEqualIntegers(MRDetailPrimaryActionMarkNextEpisode,
                          [MRDetailActions primaryActionForItem:item],
                          @"watching next episode primary action");
    MRAssertEqualObjects(@"Mark S2E5 Watched",
                         [MRDetailActions titleForPrimaryAction:
                             MRDetailPrimaryActionMarkNextEpisode item:item],
                         @"next episode title");
    item.nextEpisodeSeason = 0;
    item.nextEpisodeNumber = 0;
    MRAssertEqualIntegers(MRDetailPrimaryActionMarkAllWatched,
                          [MRDetailActions primaryActionForItem:item],
                          @"watching without a next episode primary action");
    item.watchStatus = MRWatchStatusCompleted;
    MRAssertEqualIntegers(MRDetailPrimaryActionChangeStatus,
                          [MRDetailActions primaryActionForItem:item],
                          @"completed primary action");
    item.watchStatus = MRWatchStatusHold;
    MRAssertEqualIntegers(MRDetailPrimaryActionMoveToWatching,
                          [MRDetailActions primaryActionForItem:item],
                          @"held primary action");
    item.watchStatus = MRWatchStatusDropped;
    MRAssertEqualIntegers(MRDetailPrimaryActionMoveToWatching,
                          [MRDetailActions primaryActionForItem:item],
                          @"dropped primary action");
}

void MRRunWriteReconciliationTests(void) {
    MRRunResolvedStatusReconciliation();
    MRRunNotFoundLeavesLocalItem();
    MRRunTransientFailureKeepsOptimisticState();
    MRRunClearRatingReconciliation();
    MRRunRemoveOnlyAfterSuccess();
    MRRunPrimaryActionTable();
}
