//
//  MRSyncDeltaTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRStorage.h"
#import "MRSyncEngine.h"

#pragma mark - Provider

@interface MRDeltaResponse : NSObject
@property (nonatomic, strong) NSDictionary *json;
@property (nonatomic, strong) NSError *error;
@end

@implementation MRDeltaResponse
@end

@interface MRDeltaProvider : NSObject <MRSyncDataProviding>
@property (nonatomic, strong) NSMutableArray *responses;
@property (nonatomic, strong) NSMutableArray *calls;
@property (nonatomic, assign) BOOL deferred;
@property (nonatomic, copy) void (^pendingCompletion)(NSDictionary *json, NSError *error);
- (void)enqueueJSON:(NSDictionary *)json;
- (void)enqueueError:(NSError *)error;
- (void)completeWithJSON:(NSDictionary *)json error:(NSError *)error;
@end

@implementation MRDeltaProvider

- (id)init {
    self = [super init];
    if (self) {
        _responses = [NSMutableArray array];
        _calls = [NSMutableArray array];
    }
    return self;
}

- (void)enqueueJSON:(NSDictionary *)json {
    MRDeltaResponse *response = [[MRDeltaResponse alloc] init];
    response.json = json;
    [self.responses addObject:response];
}

- (void)enqueueError:(NSError *)error {
    MRDeltaResponse *response = [[MRDeltaResponse alloc] init];
    response.error = error;
    [self.responses addObject:response];
}

- (void)deliverToCompletion:(void (^)(NSDictionary *json, NSError *error))completion {
    if (self.deferred) {
        self.pendingCompletion = completion;
        return;
    }

    MRDeltaResponse *response = nil;
    if (self.responses.count > 0) {
        response = [self.responses objectAtIndex:0];
        [self.responses removeObjectAtIndex:0];
    }
    if (completion != nil) {
        completion(response.json, response.error);
    }
}

- (void)completeWithJSON:(NSDictionary *)json error:(NSError *)error {
    void (^completion)(NSDictionary *, NSError *) = self.pendingCompletion;
    self.pendingCompletion = nil;
    if (completion != nil) {
        completion(json, error);
    }
}

- (id<MRHTTPTask>)fetchActivitiesWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self.calls addObject:@{ @"kind": @"activities" }];
    [self deliverToCompletion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchAllItemsForType:(MRMediaType)type
                                status:(MRWatchStatus)status
                              dateFrom:(NSString *)dateFrom
                               idsOnly:(BOOL)idsOnly
                          nextWatchInfo:(BOOL)nextWatchInfo
                             completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self.calls addObject:@{
        @"kind": @"items",
        @"type": @(type),
        @"status": @(status),
        @"dateFrom": dateFrom ?: @"",
        @"idsOnly": @(idsOnly),
        @"nextWatchInfo": @(nextWatchInfo)
    }];
    [self deliverToCompletion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchRatingsForType:(MRMediaType)type
                             dateFrom:(NSString *)dateFrom
                           completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self.calls addObject:@{
        @"kind": @"ratings",
        @"type": @(type),
        @"dateFrom": dateFrom ?: @""
    }];
    [self deliverToCompletion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchUserSettingsWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self.calls addObject:@{ @"kind": @"settings" }];
    [self deliverToCompletion:completion];
    return nil;
}

@end

#pragma mark - Helpers

static NSString *MRDeltaTestRoot(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-delta-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return root;
}

static void MRDeltaRemoveRoot(NSString *root) {
    if (root.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}

static MRLibraryStore *MRDeltaStore(NSString *root) {
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    return [[MRLibraryStore alloc] initWithStorage:storage];
}

static MRMediaItem *MRDeltaShow(NSInteger simklID,
                                MRWatchStatus status,
                                NSInteger rating,
                                NSInteger watched) {
    return [MRMediaItem itemWithSyncDictionary:@{
        @"status": MRWatchStatusKey(status),
        @"user_rating": @(rating),
        @"watched_episodes_count": @(watched),
        @"show": @{
            @"title": @"Old Show",
            @"year": @2020,
            @"ids": @{ @"simkl": @(simklID) }
        }
    } type:MRMediaTypeShow];
}

static MRMediaItem *MRDeltaMovie(NSInteger simklID, NSInteger rating) {
    return [MRMediaItem itemWithSyncDictionary:@{
        @"status": @"completed",
        @"user_rating": @(rating),
        @"movie": @{
            @"title": @"Old Movie",
            @"year": @2021,
            @"ids": @{ @"simkl": @(simklID) }
        }
    } type:MRMediaTypeMovie];
}

static MRLibraryStore *MRDeltaStoreWithSnapshot(NSString *root,
                                                NSArray *items,
                                                NSDictionary *activities) {
    MRLibraryStore *store = MRDeltaStore(root);
    NSError *error = nil;
    MRAssertTrue([store replaceWithItems:items
                              activities:activities
                                 profile:nil
                                   error:&error],
                 @"delta test setup saves a snapshot");
    MRAssertTrue(error == nil, @"delta test setup has no error");
    return store;
}

static MRSyncEngine *MRDeltaEngine(MRDeltaProvider *provider,
                                   MRLibraryStore *store,
                                   MRFakeClock *clock) {
    return [[MRSyncEngine alloc] initWithDataProvider:provider
                                         libraryStore:store
                                              storage:nil
                                                clock:clock];
}

static BOOL MRDeltaWaitForIdle(MRSyncEngine *engine) {
    return MRRunUntil(^BOOL {
        return !engine.isSyncing;
    }, 2.0);
}

static NSError *MRDeltaSync(MRSyncEngine *engine) {
    __block BOOL finished = NO;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        finished = YES;
        resultError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"delta sync completes");
    return resultError;
}

#pragma mark - Tests

static void MRRunDeltaGateMatchTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root,
        @[ MRDeltaShow(777, MRWatchStatusCompleted, 2, 1) ], saved);
    NSInteger generation = store.generation;

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:saved];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    NSError *error = MRDeltaSync(engine);
    MRAssertTrue(error == nil, @"an unchanged activities gate succeeds");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"an unchanged gate makes only the activities call");
    MRAssertEqualObjects(@"activities", [[provider.calls objectAtIndex:0] objectForKey:@"kind"],
                         @"the gate is the only call");
    MRAssertEqualIntegers(generation, store.generation,
                          @"an unchanged gate does not bump the generation");
    MRAssertEqualObjects(saved, store.activities,
                         @"an unchanged gate keeps the activities snapshot");

    MRDeltaRemoveRoot(root);
}

static void MRRunDeltaMovedDomainsTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root, @[
        MRDeltaShow(777, MRWatchStatusCompleted, 2, 1),
        MRDeltaMovie(888, 0)
    ], saved);
    NSInteger generation = store.generation;
    NSDate *fullSyncDate = store.lastFullSyncAt;

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-moved")];
    [provider enqueueJSON:MRFixture(@"sync-delta-shows")];
    [provider enqueueJSON:MRFixture(@"ratings-delta")];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    NSError *error = MRDeltaSync(engine);
    MRAssertTrue(error == nil, @"a moved-domain delta succeeds");
    MRAssertEqualIntegers(3, (NSInteger)provider.calls.count,
                          @"only the moved show delta and movie ratings are fetched");

    NSDictionary *itemCall = [provider.calls objectAtIndex:1];
    MRAssertEqualObjects(@"items", [itemCall objectForKey:@"kind"],
                         @"the show delta is an all-items call");
    MRAssertEqualIntegers(MRMediaTypeShow,
                          [[itemCall objectForKey:@"type"] integerValue],
                          @"the show domain fetches shows");
    MRAssertEqualIntegers(MRWatchStatusNone,
                          [[itemCall objectForKey:@"status"] integerValue],
                          @"the delta uses no status bucket");
    MRAssertEqualObjects([saved objectForKey:@"all"],
                         [itemCall objectForKey:@"dateFrom"],
                         @"the delta uses the saved top-level all");
    MRAssertTrue(![[itemCall objectForKey:@"idsOnly"] boolValue],
                 @"the item delta is not ids-only");
    MRAssertTrue([[itemCall objectForKey:@"nextWatchInfo"] boolValue],
                 @"show deltas request next watch info");

    NSDictionary *ratingCall = [provider.calls objectAtIndex:2];
    MRAssertEqualObjects(@"ratings", [ratingCall objectForKey:@"kind"],
                         @"the movie rating move fetches ratings");
    MRAssertEqualIntegers(MRMediaTypeMovie,
                          [[ratingCall objectForKey:@"type"] integerValue],
                          @"the rating domain fetches movies");
    MRAssertEqualObjects([saved objectForKey:@"all"],
                         [ratingCall objectForKey:@"dateFrom"],
                         @"ratings use the saved top-level all");

    MRMediaItem *show = [store itemForType:MRMediaTypeShow simklID:777];
    MRAssertTrue(show != nil, @"the delta replaces the existing show");
    MRAssertEqualObjects(@"Delta Show", show.title, @"the delta updates the title");
    MRAssertEqualIntegers(MRWatchStatusWatching, show.watchStatus,
                          @"the delta updates the status");
    MRAssertEqualIntegers(9, show.userRating, @"the delta updates the rating");
    MRAssertEqualIntegers(5, show.watchedEpisodesCount,
                          @"the delta updates watched episodes");
    MRAssertEqualIntegers(10, show.totalEpisodesCount,
                          @"the delta updates total episodes");
    MRAssertEqualIntegers(2, show.nextEpisodeSeason,
                          @"the delta updates next season");
    MRAssertEqualIntegers(3, show.nextEpisodeNumber,
                          @"the delta updates next episode");
    MRAssertEqualObjects(@"Delta Next", show.nextEpisodeTitle,
                         @"the delta updates next episode title");

    MRMediaItem *movie = [store itemForType:MRMediaTypeMovie simklID:888];
    MRAssertEqualIntegers(6, movie.userRating,
                          @"the ratings delta merges into the movie");
    MRAssertEqualObjects(MRFixture(@"activities-moved"), store.activities,
                         @"a successful delta saves the new activities");
    MRAssertEqualIntegers(generation + 1, store.generation,
                          @"a successful delta increments the generation");
    MRAssertEqualObjects(fullSyncDate, store.lastFullSyncAt,
                         @"a delta keeps the full-sync date");
    MRAssertEqualObjects(clock.now, engine.lastSyncAt,
                         @"a delta timestamps the engine with the injected clock");

    MRDeltaRemoveRoot(root);
}

static void MRRunDeltaNullRatingTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root,
        @[ MRDeltaMovie(888, 5) ], saved);

    NSMutableDictionary *current =
        [NSMutableDictionary dictionaryWithDictionary:MRFixture(@"activities-moved")];
    NSMutableDictionary *shows =
        [NSMutableDictionary dictionaryWithDictionary:[current objectForKey:@"tv_shows"]];
    [shows setObject:[[saved objectForKey:@"tv_shows"] objectForKey:@"all"]
              forKey:@"all"];
    [current setObject:shows forKey:@"tv_shows"];

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:current];
    [provider enqueueJSON:@{ @"movies": @[
        @{ @"ids": @{ @"simkl": @(888) }, @"user_rating": [NSNull null] }
    ] }];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    NSError *error = MRDeltaSync(engine);
    MRAssertTrue(error == nil, @"a null rating delta succeeds");
    MRMediaItem *movie = [store itemForType:MRMediaTypeMovie simklID:888];
    MRAssertEqualIntegers(0, movie.userRating,
                          @"user_rating null clears the local rating");

    MRDeltaRemoveRoot(root);
}

static void MRRunDeltaFailureKeepsSnapshotTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root,
        @[ MRDeltaShow(777, MRWatchStatusCompleted, 2, 1),
           MRDeltaMovie(888, 0) ], saved);
    NSInteger generation = store.generation;

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-moved")];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindServer]];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    NSError *error = MRDeltaSync(engine);
    MRAssertTrue(error != nil, @"a failed delta reports an error");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:error],
                          @"the server error is preserved");
    MRAssertEqualIntegers(generation, store.generation,
                          @"a failed delta keeps the old generation");
    MRAssertEqualObjects(saved, store.activities,
                         @"a failed delta keeps the old activities");
    MRMediaItem *show = [store itemForType:MRMediaTypeShow simklID:777];
    MRAssertEqualObjects(@"Old Show", show.title,
                         @"a failed delta leaves the old item untouched");
    MRAssertEqualIntegers(MRWatchStatusCompleted, show.watchStatus,
                          @"a failed delta leaves the old status untouched");
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"the failure stops before ratings");
    MRAssertEqualObjects([saved objectForKey:@"all"],
                         [[provider.calls objectAtIndex:1] objectForKey:@"dateFrom"],
                         @"a failed delta used the saved top-level all");

    // The next attempt must retry with the same date_from because the saved
    // activities were never advanced.
    [provider enqueueJSON:MRFixture(@"activities-moved")];
    [provider enqueueJSON:MRFixture(@"sync-delta-shows")];
    [provider enqueueJSON:MRFixture(@"ratings-delta")];
    NSError *retryError = MRDeltaSync(engine);
    MRAssertTrue(retryError == nil, @"the retry succeeds");
    MRAssertEqualObjects([saved objectForKey:@"all"],
                         [[provider.calls objectAtIndex:3] objectForKey:@"dateFrom"],
                         @"the retry reuses the saved top-level all");
    MRAssertEqualIntegers(generation + 1, store.generation,
                          @"the retry commits one new generation");

    MRDeltaRemoveRoot(root);
}

static void MRRunOutboxDrainThrottleTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root,
        @[ MRDeltaShow(777, MRWatchStatusCompleted, 2, 1) ], saved);

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:saved];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    [engine noteOutboxDrainedAtDate:clock.now];
    MRAssertTrue(MRDeltaWaitForIdle(engine), @"the outbox-drain sync finishes");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the first outbox drain starts one delta sync");

    [engine noteOutboxDrainedAtDate:[clock.now dateByAddingTimeInterval:30.0]];
    MRAssertTrue(!engine.isSyncing, @"an outbox drain inside one minute is ignored");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the outbox-drain throttle sends no request before a minute");

    [provider enqueueJSON:saved];
    [clock advanceBy:61.0];
    [engine noteOutboxDrainedAtDate:clock.now];
    MRAssertTrue(MRDeltaWaitForIdle(engine), @"the throttled outbox-drain sync finishes");
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"an outbox drain after a minute starts a new delta sync");

    MRDeltaRemoveRoot(root);
}

static void MRRunForegroundThrottleTest(void) {
    NSString *root = MRDeltaTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeltaStoreWithSnapshot(root,
        @[ MRDeltaShow(777, MRWatchStatusCompleted, 2, 1) ], saved);

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    [provider enqueueJSON:saved];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    [engine noteForegroundAtDate:clock.now];
    MRAssertTrue(MRDeltaWaitForIdle(engine), @"the first foreground sync finishes");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the first foreground event starts a sync");

    [clock advanceBy:899.0];
    [engine noteForegroundAtDate:clock.now];
    MRAssertTrue(!engine.isSyncing, @"a foreground event inside 15 minutes is ignored");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the throttle sends no request before 15 minutes");

    [provider enqueueJSON:saved];
    [clock advanceBy:2.0];
    [engine noteForegroundAtDate:clock.now];
    MRAssertTrue(MRDeltaWaitForIdle(engine), @"the throttled foreground sync finishes");
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"a foreground event after 15 minutes starts a new sync");

    MRDeltaRemoveRoot(root);
}

static void MRRunInFlightNeedsSyncTest(void) {
    NSString *root = MRDeltaTestRoot();
    MRLibraryStore *store = MRDeltaStore(root);
    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    provider.deferred = YES;
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, clock);

    __block NSUInteger completions = 0;
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        completions += 1;
        firstError = error;
    }];
    [engine syncWithCompletion:^(NSError *error) {
        completions += 1;
        secondError = error;
    }];
    MRAssertTrue(engine.isSyncing, @"the first pass is in flight");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the second request joins the in-flight pass");

    [provider completeWithJSON:MRFixture(@"activities-saved") error:nil];
    [provider completeWithJSON:MRFixture(@"sync-shows") error:nil];
    [provider completeWithJSON:MRFixture(@"sync-movies") error:nil];
    [provider completeWithJSON:MRFixture(@"sync-anime") error:nil];

    MRAssertTrue(engine.isSyncing, @"a queued request starts exactly one more pass");
    MRAssertEqualIntegers(5, (NSInteger)provider.calls.count,
                          @"the second pass starts with a fresh activities gate");
    MRAssertEqualIntegers(0, (NSInteger)completions,
                          @"callers wait for the queued pass");
    MRAssertEqualIntegers(1, store.generation,
                          @"the first pass saved one snapshot");

    [provider completeWithJSON:MRFixture(@"activities-saved") error:nil];
    MRAssertTrue(MRDeltaWaitForIdle(engine), @"the queued pass completes");
    MRAssertEqualIntegers(5, (NSInteger)provider.calls.count,
                          @"the equal activities gate stops the second pass");
    MRAssertEqualIntegers(2, (NSInteger)completions,
                          @"both callers finish after the queued pass");
    MRAssertTrue(firstError == nil && secondError == nil,
                 @"both callers see success");
    MRAssertEqualIntegers(1, store.generation,
                          @"the no-op second pass does not bump the generation");

    MRDeltaRemoveRoot(root);
}

static void MRRunPendingCountTest(void) {
    NSString *root = MRDeltaTestRoot();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MROutboxEntry *entry = [MROutboxEntry statusEntryWithItem:MRDeltaShow(777, MRWatchStatusWatching, 0, 0)
                                                      status:MRWatchStatusWatching
                                              previousStatus:MRWatchStatusPlanToWatch];
    NSError *enqueueError = nil;
    MRAssertTrue([outbox enqueueEntry:entry error:&enqueueError],
                 @"the pending-count setup enqueues an entry");
    MRAssertTrue(enqueueError == nil, @"the pending-count setup has no error");

    MRDeltaProvider *provider = [[MRDeltaProvider alloc] init];
    MRSyncEngine *engine = MRDeltaEngine(provider, store, [[MRFakeClock alloc] init]);
    MRAssertEqualIntegers(0, (NSInteger)engine.pendingCount,
                          @"an engine without an outbox has no pending writes");
    [engine setOutbox:outbox];
    MRAssertEqualIntegers(1, (NSInteger)engine.pendingCount,
                          @"the engine reports the outbox pending count");

    MRDeltaRemoveRoot(root);
}

void MRRunSyncDeltaTests(void) {
    MRRunDeltaGateMatchTest();
    MRRunDeltaMovedDomainsTest();
    MRRunDeltaNullRatingTest();
    MRRunDeltaFailureKeepsSnapshotTest();
    MRRunOutboxDrainThrottleTest();
    MRRunForegroundThrottleTest();
    MRRunInFlightNeedsSyncTest();
    MRRunPendingCountTest();
}
