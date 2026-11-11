//
//  MRSyncInitialTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRAPIClient.h"
#import "MRConfig.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPResponse.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRStubHTTPClient.h"
#import "MRSyncEngine.h"
#import "MRTokenProviding.h"
#import "MRUserProfile.h"

#pragma mark - Sync data-provider stub

@interface MRSyncStubResponse : NSObject
@property (nonatomic, strong) NSDictionary *json;
@property (nonatomic, strong) NSError *error;
+ (instancetype)responseWithJSON:(NSDictionary *)json;
+ (instancetype)responseWithError:(NSError *)error;
@end

@implementation MRSyncStubResponse
+ (instancetype)responseWithJSON:(NSDictionary *)json {
    MRSyncStubResponse *response = [[self alloc] init];
    response.json = json;
    return response;
}
+ (instancetype)responseWithError:(NSError *)error {
    MRSyncStubResponse *response = [[self alloc] init];
    response.error = error;
    return response;
}
@end

@interface MRSyncStubProvider : NSObject <MRSyncDataProviding>
@property (nonatomic, strong) NSMutableArray *responses;
@property (nonatomic, strong) NSMutableArray *calls;
- (void)enqueueJSON:(NSDictionary *)json;
- (void)enqueueError:(NSError *)error;
@end

@implementation MRSyncStubProvider

- (id)init {
    self = [super init];
    if (self) {
        _responses = [NSMutableArray array];
        _calls = [NSMutableArray array];
    }
    return self;
}

- (void)enqueueJSON:(NSDictionary *)json {
    [self.responses addObject:[MRSyncStubResponse responseWithJSON:json]];
}

- (void)enqueueError:(NSError *)error {
    [self.responses addObject:[MRSyncStubResponse responseWithError:error]];
}

- (MRSyncStubResponse *)nextResponse {
    if (self.responses.count == 0) {
        return [MRSyncStubResponse responseWithError:[MRError errorWithKind:MRErrorKindUnknown]];
    }
    MRSyncStubResponse *response = [self.responses objectAtIndex:0];
    [self.responses removeObjectAtIndex:0];
    return response;
}

- (void)recordCall:(NSDictionary *)call {
    [self.calls addObject:call];
}

- (id<MRHTTPTask>)fetchActivitiesWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"activities" }];
    MRSyncStubResponse *response = [self nextResponse];
    if (completion != nil) {
        completion(response.json, response.error);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchAllItemsForType:(MRMediaType)type
                                status:(MRWatchStatus)status
                              dateFrom:(NSString *)dateFrom
                               idsOnly:(BOOL)idsOnly
                          nextWatchInfo:(BOOL)nextWatchInfo
                             completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{
        @"kind": @"items",
        @"type": @(type),
        @"status": @(status),
        @"dateFrom": dateFrom ?: @"",
        @"idsOnly": @(idsOnly),
        @"nextWatchInfo": @(nextWatchInfo)
    }];
    MRSyncStubResponse *response = [self nextResponse];
    if (completion != nil) {
        completion(response.json, response.error);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchRatingsForType:(MRMediaType)type
                             dateFrom:(NSString *)dateFrom
                           completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"ratings", @"type": @(type),
                        @"dateFrom": dateFrom ?: @"" }];
    MRSyncStubResponse *response = [self nextResponse];
    if (completion != nil) {
        completion(response.json, response.error);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchUserSettingsWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"settings" }];
    MRSyncStubResponse *response = [self nextResponse];
    if (completion != nil) {
        completion(response.json, response.error);
    }
    return nil;
}

@end

// A provider that records one request at a time and lets the test resolve it.
// This is how the tests reach the in-flight and cancellation states that the
// synchronous stub above completes before the engine can be observed.
@interface MRSyncDeferredProvider : NSObject <MRSyncDataProviding>
@property (nonatomic, strong) NSMutableArray *calls;
@property (nonatomic, copy) void (^pendingCompletion)(NSDictionary *json, NSError *error);
- (void)completeWithJSON:(NSDictionary *)json error:(NSError *)error;
@end

@implementation MRSyncDeferredProvider

- (id)init {
    self = [super init];
    if (self) {
        _calls = [NSMutableArray array];
    }
    return self;
}

- (void)recordCall:(NSDictionary *)call
        completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self.calls addObject:call];
    self.pendingCompletion = completion;
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
    [self recordCall:@{ @"kind": @"activities" } completion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchAllItemsForType:(MRMediaType)type
                                status:(MRWatchStatus)status
                              dateFrom:(NSString *)dateFrom
                               idsOnly:(BOOL)idsOnly
                          nextWatchInfo:(BOOL)nextWatchInfo
                             completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"items", @"type": @(type), @"status": @(status) }
          completion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchRatingsForType:(MRMediaType)type
                             dateFrom:(NSString *)dateFrom
                           completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"ratings", @"type": @(type) } completion:completion];
    return nil;
}

- (id<MRHTTPTask>)fetchUserSettingsWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall:@{ @"kind": @"settings" } completion:completion];
    return nil;
}

@end

#pragma mark - Test helpers

static NSString *MRSyncTestDirectory(NSString *suffix) {
    NSString *name = [NSString stringWithFormat:@"marquee-sync-%@-%@",
                      suffix, [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

static void MRRemoveSyncTestDirectory(NSString *directory) {
    if (directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    }
}

static MRLibraryStore *MRSyncStoreAtRoot(NSString *root) {
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    return [[MRLibraryStore alloc] initWithStorage:storage];
}

static NSDictionary *MRSyncShowEntry(MRWatchStatus status, NSInteger simklID) {
    return @{
        @"status": MRWatchStatusKey(status),
        @"show": @{
            @"title": [NSString stringWithFormat:@"Show %ld", (long)simklID],
            @"year": @2020,
            @"ids": @{ @"simkl": @(simklID), @"slug": @"show" }
        }
    };
}

static NSDictionary *MRSyncMovieEntry(MRWatchStatus status, NSInteger simklID) {
    return @{
        @"status": MRWatchStatusKey(status),
        @"movie": @{
            @"title": [NSString stringWithFormat:@"Movie %ld", (long)simklID],
            @"year": @2021,
            @"ids": @{ @"simkl": @(simklID), @"slug": @"movie" }
        }
    };
}

static NSDictionary *MRSyncCall(MRSyncStubProvider *provider, NSUInteger index) {
    if (index >= provider.calls.count) {
        return nil;
    }
    return [provider.calls objectAtIndex:index];
}

static MRMediaItem *MRSyncShowItem(void) {
    return [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-shows")[@"shows"][0]
                                         type:MRMediaTypeShow];
}

#pragma mark - Sync engine tests

static void MRRunSyncSequence(void) {
    NSString *root = MRSyncTestDirectory(@"sequence");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRSyncStubProvider *provider = [[MRSyncStubProvider alloc] init];

    NSDictionary *activities = @{ @"all": @"2026-11-04T12:00:00Z" };
    [provider enqueueJSON:activities];
    [provider enqueueJSON:MRFixture(@"sync-shows")];
    [provider enqueueJSON:MRFixture(@"sync-movies")];
    [provider enqueueJSON:MRFixture(@"sync-anime")];

    __block NSUInteger statusChanges = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRSyncStatusDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        statusChanges += 1;
    }];

    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:provider
                                                        libraryStore:store
                                                             storage:nil
                                                               clock:clock];
    __block BOOL finished = NO;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        finished = YES;
        resultError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"initial sync completes");
    MRAssertTrue(resultError == nil, @"initial sync succeeds");

    MRAssertEqualIntegers(4, (NSInteger)provider.calls.count,
                          @"phase 1 makes exactly four calls");
    MRAssertEqualObjects(@"activities", [MRSyncCall(provider, 0) objectForKey:@"kind"],
                         @"activities come first");
    MRAssertEqualIntegers(MRMediaTypeShow,
                          [[MRSyncCall(provider, 1) objectForKey:@"type"] integerValue],
                          @"shows come second");
    MRAssertEqualIntegers(MRMediaTypeMovie,
                          [[MRSyncCall(provider, 2) objectForKey:@"type"] integerValue],
                          @"movies come third");
    MRAssertEqualIntegers(MRMediaTypeAnime,
                          [[MRSyncCall(provider, 3) objectForKey:@"type"] integerValue],
                          @"anime comes fourth");

    MRAssertEqualIntegers(MRWatchStatusNone,
                          [[MRSyncCall(provider, 1) objectForKey:@"status"] integerValue],
                          @"shows use the omitted status");
    MRAssertTrue([[MRSyncCall(provider, 1) objectForKey:@"nextWatchInfo"] boolValue],
                 @"shows request next watch info");
    MRAssertTrue(![[MRSyncCall(provider, 2) objectForKey:@"nextWatchInfo"] boolValue],
                 @"movies do not request next watch info");
    MRAssertTrue([[MRSyncCall(provider, 3) objectForKey:@"nextWatchInfo"] boolValue],
                 @"anime requests next watch info");
    MRAssertTrue(![[MRSyncCall(provider, 1) objectForKey:@"idsOnly"] boolValue],
                 @"a full pull is not ids-only");
    MRAssertEqualObjects(@"", [MRSyncCall(provider, 1) objectForKey:@"dateFrom"],
                         @"a full pull has no date_from");

    MRAssertEqualIntegers(3, (NSInteger)store.items.count,
                          @"the three fixtures become three items");
    MRAssertEqualObjects(activities, store.activities,
                         @"the activities snapshot is saved");
    MRAssertEqualIntegers(1, store.generation, @"the initial sync increments generation");
    MRAssertTrue(store.lastSyncAt != nil, @"the initial sync records lastSyncAt");
    MRAssertTrue(store.lastFullSyncAt != nil,
                 @"the initial sync records lastFullSyncAt");
    MRAssertTrue(engine.lastSyncAt != nil, @"engine records lastSyncAt");
    MRAssertTrue(engine.lastSyncAttemptAt != nil,
                 @"engine records lastSyncAttemptAt");
    MRAssertTrue(engine.lastSyncError == nil, @"engine clears the sync error");
    MRAssertTrue(!engine.isSyncing, @"engine is idle after sync");
    MRAssertEqualObjects(clock.now, engine.lastSyncAt,
                         @"engine timestamps the sync with the injected clock");

    MRMediaItem *show = [store itemForType:MRMediaTypeShow simklID:3407];
    MRAssertTrue(show != nil, @"the show was normalized");
    MRAssertEqualIntegers(8, show.nextEpisodeSeason,
                          @"next_to_watch_info season is populated");
    MRAssertEqualIntegers(3, show.nextEpisodeNumber,
                          @"next_to_watch_info episode is populated");
    MRAssertEqualObjects(@"The Prisoner of Benda", show.nextEpisodeTitle,
                         @"next_to_watch_info title is populated");
    MRAssertTrue(show.nextEpisodeDate != nil,
                 @"next_to_watch_info date is populated");
    MRAssertEqualIntegers(0, show.userRating,
                          @"a missing user_rating becomes zero");

    MRAssertTrue(statusChanges >= 2,
                 @"sync start and finish post status notifications");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    MRRemoveSyncTestDirectory(root);
}

static void MRRunSyncFailureKeepsSnapshot(void) {
    NSString *root = MRSyncTestDirectory(@"failure");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    NSError *setupError = nil;
    MRMediaItem *oldShow =
        [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-shows")[@"shows"][0]
                                       type:MRMediaTypeShow];
    NSDictionary *oldActivities = @{ @"all": @"old" };
    MRAssertTrue([store replaceWithItems:@[ oldShow ]
                              activities:oldActivities
                                 profile:nil
                                   error:&setupError],
                 @"failure setup saves an old snapshot");
    NSInteger oldGeneration = store.generation;
    NSDate *previousSyncAt = store.lastSyncAt;

    MRSyncStubProvider *provider = [[MRSyncStubProvider alloc] init];
    [provider enqueueJSON:@{ @"all": @"new" }];
    [provider enqueueJSON:MRFixture(@"sync-shows")];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindServer]];
    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:provider
                                                        libraryStore:store
                                                             storage:nil
                                                               clock:[[MRFakeClock alloc] init]];

    __block BOOL finished = NO;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        finished = YES;
        resultError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"a failed initial sync completes");
    MRAssertTrue(resultError != nil, @"a failed movie pull surfaces an error");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:resultError],
                          @"the server error is preserved");
    MRAssertEqualIntegers(oldGeneration, store.generation,
                          @"a failed sync keeps the old generation");
    MRAssertEqualIntegers(1, (NSInteger)store.items.count,
                          @"a failed sync keeps the old items");
    MRAssertEqualObjects(@"Futurama",
                         [store itemForType:MRMediaTypeShow simklID:3407].title,
                         @"the old snapshot is untouched");
    MRAssertEqualObjects(oldActivities, store.activities,
                         @"a failed sync keeps the old activities");
    MRAssertTrue(engine.lastSyncError != nil, @"the engine records the failure");
    MRAssertEqualObjects(previousSyncAt, engine.lastSyncAt,
                         @"a failure keeps the previous sync time");
    MRAssertTrue(engine.lastSyncAttemptAt != nil, @"a failure records the attempt");
    MRAssertTrue(!engine.isSyncing, @"the engine is idle after a failure");

    MRRemoveSyncTestDirectory(root);
}

static void MRRunConcurrentSyncJoins(void) {
    NSString *root = MRSyncTestDirectory(@"concurrent");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    MRSyncDeferredProvider *provider = [[MRSyncDeferredProvider alloc] init];
    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:provider
                                                         libraryStore:store
                                                              storage:nil
                                                                clock:[[MRFakeClock alloc] init]];

    __block NSUInteger completions = 0;
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        completions += 1;
        firstError = error;
    }];
    MRAssertTrue(engine.isSyncing, @"the first sync is in flight");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the first sync starts with activities");

    [engine syncWithCompletion:^(NSError *error) {
        completions += 1;
        secondError = error;
    }];
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"a second sync joins instead of starting another pull");

    [provider completeWithJSON:MRFixture(@"activities-saved") error:nil];
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"shows follow the resolved activities");
    [provider completeWithJSON:MRFixture(@"sync-shows") error:nil];
    [provider completeWithJSON:MRFixture(@"sync-movies") error:nil];
    [provider completeWithJSON:MRFixture(@"sync-anime") error:nil];

    MRAssertTrue(engine.isSyncing, @"a joined request queued one more pass");
    MRAssertEqualIntegers(5, (NSInteger)provider.calls.count,
                          @"the queued pass starts with a fresh activities gate");
    [provider completeWithJSON:MRFixture(@"activities-saved") error:nil];

    MRAssertTrue(!engine.isSyncing, @"the joined sync completes once");
    MRAssertEqualIntegers(2, (NSInteger)completions,
                          @"both callers get exactly one completion");
    MRAssertTrue(firstError == nil, @"the first caller sees success");
    MRAssertTrue(secondError == nil, @"the joining caller sees success");
    MRAssertEqualIntegers(1, store.generation,
                          @"the joined sync saves exactly one snapshot");

    MRRemoveSyncTestDirectory(root);
}

static void MRRunSyncCancellation(void) {
    NSString *root = MRSyncTestDirectory(@"cancel");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    MRSyncDeferredProvider *provider = [[MRSyncDeferredProvider alloc] init];
    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:provider
                                                         libraryStore:store
                                                              storage:nil
                                                                clock:[[MRFakeClock alloc] init]];

    __block NSUInteger completions = 0;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        completions += 1;
        resultError = error;
    }];
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"the sync has one request in flight");

    [engine cancel];
    MRAssertTrue(!engine.isSyncing, @"cancellation stops the sync");
    MRAssertEqualIntegers(1, (NSInteger)completions,
                          @"cancellation completes the caller");
    MRAssertEqualIntegers(MRErrorKindCancelled, [MRError kindForError:resultError],
                          @"cancellation reports Cancelled");
    MRAssertTrue(engine.lastSyncError == nil,
                 @"a cancellation is not recorded as a sync failure");

    [provider completeWithJSON:@{ @"all": @"2026-11-04T12:00:00Z" } error:nil];
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"a late completion does not resume the cancelled sync");
    MRAssertEqualIntegers(0, (NSInteger)store.items.count,
                          @"a cancelled sync saves no items");

    MRRemoveSyncTestDirectory(root);
}

static void MRRunEngineResumesLastSyncAt(void) {
    NSString *root = MRSyncTestDirectory(@"resume");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    NSError *setupError = nil;
    MRAssertTrue([store replaceWithItems:@[ MRSyncShowItem() ]
                              activities:@{ @"all": @"1" }
                                 profile:nil
                                   error:&setupError],
                 @"resume setup saves a snapshot");
    NSDate *savedSyncDate = store.lastSyncAt;

    MRSyncEngine *engine = [[MRSyncEngine alloc]
        initWithDataProvider:[[MRSyncStubProvider alloc] init]
                libraryStore:store
                     storage:nil
                       clock:[[MRFakeClock alloc] init]];
    MRAssertEqualObjects(savedSyncDate, engine.lastSyncAt,
                         @"a new engine resumes the stored last sync time");

    MRRemoveSyncTestDirectory(root);
}

static void MRRunMaxItemsSplit(void) {
    NSString *root = MRSyncTestDirectory(@"max-items");
    MRLibraryStore *store = MRSyncStoreAtRoot(root);
    MRSyncStubProvider *provider = [[MRSyncStubProvider alloc] init];

    [provider enqueueJSON:@{ @"all": @"2026-11-04T12:00:00Z" }];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindTooLarge]];
    [provider enqueueJSON:@{ @"shows": @[ MRSyncShowEntry(MRWatchStatusWatching, 101) ] }];
    [provider enqueueJSON:@{ @"shows": @[ MRSyncShowEntry(MRWatchStatusPlanToWatch, 102) ] }];
    [provider enqueueJSON:@{ @"shows": @[ MRSyncShowEntry(MRWatchStatusCompleted, 103) ] }];
    [provider enqueueJSON:@{ @"shows": @[ MRSyncShowEntry(MRWatchStatusHold, 104) ] }];
    [provider enqueueJSON:@{ @"shows": @[ MRSyncShowEntry(MRWatchStatusDropped, 105) ] }];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindTooLarge]];
    [provider enqueueJSON:@{ @"movies": @[ MRSyncMovieEntry(MRWatchStatusPlanToWatch, 201) ] }];
    [provider enqueueJSON:@{ @"movies": @[ MRSyncMovieEntry(MRWatchStatusCompleted, 202) ] }];
    [provider enqueueJSON:@{ @"movies": @[ MRSyncMovieEntry(MRWatchStatusDropped, 203) ] }];
    [provider enqueueJSON:MRFixture(@"sync-anime")];

    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:provider
                                                        libraryStore:store
                                                             storage:nil
                                                               clock:[[MRFakeClock alloc] init]];
    __block BOOL finished = NO;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        finished = YES;
        resultError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"the split sync completes");
    MRAssertTrue(resultError == nil, @"the split sync succeeds");

    MRAssertEqualIntegers(12, (NSInteger)provider.calls.count,
                          @"both max_items types split and retry by bucket");
    NSArray *expectedShowStatuses = @[
        @(MRWatchStatusWatching), @(MRWatchStatusPlanToWatch),
        @(MRWatchStatusCompleted), @(MRWatchStatusHold), @(MRWatchStatusDropped)
    ];
    NSArray *expectedMovieStatuses = @[
        @(MRWatchStatusPlanToWatch), @(MRWatchStatusCompleted), @(MRWatchStatusDropped)
    ];

    MRAssertEqualIntegers(MRMediaTypeShow,
                          [[MRSyncCall(provider, 1) objectForKey:@"type"] integerValue],
                          @"the failed combined call is shows");
    for (NSUInteger index = 0; index < expectedShowStatuses.count; index += 1) {
        NSDictionary *call = MRSyncCall(provider, index + 2);
        MRAssertEqualIntegers(MRMediaTypeShow,
                              [[call objectForKey:@"type"] integerValue],
                              @"show bucket type");
        MRAssertEqualIntegers([[expectedShowStatuses objectAtIndex:index] integerValue],
                              [[call objectForKey:@"status"] integerValue],
                              @"show buckets follow the fixed order");
        MRAssertTrue([[call objectForKey:@"nextWatchInfo"] boolValue],
                     @"show buckets keep next watch info");
    }

    MRAssertEqualIntegers(MRMediaTypeMovie,
                          [[MRSyncCall(provider, 7) objectForKey:@"type"] integerValue],
                          @"the second combined failure is movies");
    for (NSUInteger index = 0; index < expectedMovieStatuses.count; index += 1) {
        NSDictionary *call = MRSyncCall(provider, index + 8);
        MRAssertEqualIntegers(MRMediaTypeMovie,
                              [[call objectForKey:@"type"] integerValue],
                              @"movie bucket type");
        MRAssertEqualIntegers([[expectedMovieStatuses objectAtIndex:index] integerValue],
                              [[call objectForKey:@"status"] integerValue],
                              @"movies skip watching and hold");
        MRAssertTrue(![[call objectForKey:@"nextWatchInfo"] boolValue],
                     @"movie buckets keep next watch info off");
    }

    MRAssertEqualIntegers(MRMediaTypeAnime,
                          [[MRSyncCall(provider, 11) objectForKey:@"type"] integerValue],
                          @"anime follows the split movies");
    MRAssertEqualIntegers(9, (NSInteger)store.items.count,
                          @"all bucket items are merged into one snapshot");

    MRRemoveSyncTestDirectory(root);
}

static void MRRunNullRating(void) {
    NSDictionary *entry = @{
        @"status": @"watching",
        @"user_rating": [NSNull null],
        @"show": @{ @"title": @"Null Rating", @"ids": @{ @"simkl": @99 } }
    };
    MRMediaItem *item = [MRMediaItem itemWithSyncDictionary:entry
                                                       type:MRMediaTypeShow];
    MRAssertEqualIntegers(99, item.simklID, @"null-rating entry keeps its id");
    MRAssertEqualObjects(@"Null Rating", item.title, @"null-rating entry keeps its title");
    MRAssertEqualIntegers(0, item.userRating,
                          @"user_rating null normalizes to zero");
}

#pragma mark - Authenticated API client tests

@interface MRSyncStaticTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) NSInteger calls;
@end

@implementation MRSyncStaticTokenProvider
- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    self.calls += 1;
    if (completion != nil) {
        completion(self.token, self.error);
    }
}
@end

@interface MRSyncDeferredTokenProvider : NSObject <MRTokenProviding>
@property (nonatomic, copy) void (^pendingCompletion)(NSString *token, NSError *error);
@property (nonatomic, assign) NSInteger calls;
@end

@implementation MRSyncDeferredTokenProvider
- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    self.calls += 1;
    self.pendingCompletion = completion;
}
@end

@interface MRSyncAPIContext : NSObject
@property (nonatomic, strong) NSString *directory;
@property (nonatomic, strong) MRStubHTTPClient *http;
@property (nonatomic, strong) MRFakeClock *clock;
@property (nonatomic, strong) MRResponseCache *cache;
@property (nonatomic, strong) MRQuotaTracker *quota;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) MRSyncStaticTokenProvider *tokenProvider;
@property (nonatomic, strong) MRAPIClient *client;
+ (instancetype)context;
- (void)teardown;
@end

@implementation MRSyncAPIContext

+ (instancetype)context {
    MRSyncAPIContext *context = [[self alloc] init];
    context.directory = MRSyncTestDirectory(@"api");
    context.http = [[MRStubHTTPClient alloc] init];
    context.clock = [[MRFakeClock alloc] init];
    context.cache = [[MRResponseCache alloc] initWithDirectory:context.directory];
    context.quota = [[MRQuotaTracker alloc] initWithDirectory:context.directory
                                                    accountID:12345];
    context.diagnostics = [[MRDiagnostics alloc] initWithDirectory:context.directory];
    context.tokenProvider = [[MRSyncStaticTokenProvider alloc] init];
    context.tokenProvider.token = @"TOKEN-123";
    context.client = [[MRAPIClient alloc] initWithHTTPClient:context.http
                                              tokenProvider:context.tokenProvider
                                              responseCache:context.cache
                                               quotaTracker:context.quota
                                                diagnostics:context.diagnostics
                                                      clock:context.clock];
    return context;
}

- (void)teardown {
    MRRemoveSyncTestDirectory(self.directory);
}

@end

static MRHTTPResponse *MRSyncResponseWithJSON(NSInteger statusCode, id object,
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

static NSString *MRSyncCommonQuery(void) {
    return [NSString stringWithFormat:@"?client_id=%@&app-name=%@&app-version=%@",
            MR_SIMKL_CLIENT_ID, MR_APP_NAME, MR_APP_VERSION];
}

static void MRRunAuthenticatedReadTest(void) {
    MRSyncAPIContext *context = [MRSyncAPIContext context];
    NSString *URL = [@"https://api.simkl.com/sync/activities"
                     stringByAppendingString:[NSString stringWithFormat:@"%@&language=en",
                                              MRSyncCommonQuery()]];
    [context.cache storeBody:@{ @"cached": @YES } forURL:URL lastModified:nil];
    NSDictionary *headers = @{ @"X-RateLimit-Limit": @"500",
                               @"X-RateLimit-Remaining": @"42" };
    [context.http enqueueResponse:MRSyncResponseWithJSON(200,
                                                         @{ @"all": @"2026-11-04T12:00:00Z" },
                                                         headers)];

    __block BOOL finished = NO;
    __block NSDictionary *json = nil;
    __block NSError *error = nil;
    [context.client fetchActivitiesWithCompletion:^(NSDictionary *result,
                                                    NSError *resultError) {
        finished = YES;
        json = result;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"authenticated activities completes");
    MRAssertTrue(error == nil, @"authenticated activities succeeds");
    MRAssertEqualObjects(@"2026-11-04T12:00:00Z", [json objectForKey:@"all"],
                         @"the network body is returned");
    MRAssertEqualIntegers(1, (NSInteger)context.http.requestCount,
                          @"a cached public response is not used");
    MRAssertEqualIntegers(1, context.tokenProvider.calls,
                          @"authenticated reads ask for one token");

    MRHTTPRequest *request = [context.http requestAtIndex:0];
    MRAssertEqualObjects(URL, request.URL, @"activities URL and language");
    MRAssertEqualObjects(@"GET", request.method, @"authenticated reads use GET");
    MRAssertEqualIntegers(MRHTTPQueueKindAPI, request.queueKind,
                          @"authenticated reads use the API queue");
    MRAssertEqualObjects(@"Bearer TOKEN-123",
                         [request.headers objectForKey:@"Authorization"],
                         @"authenticated reads attach the bearer token");
    MRAssertEqualObjects(MR_USER_AGENT, [request.headers objectForKey:@"User-Agent"],
                         @"authenticated reads send the Marquee user agent");
    MRAssertTrue([request.headers objectForKey:@"If-Modified-Since"] == nil,
                 @"authenticated reads never revalidate the public cache");
    MRAssertEqualIntegers(500, context.quota.limit,
                          @"authenticated reads update the quota limit");
    MRAssertEqualIntegers(42, context.quota.remaining,
                          @"authenticated reads update the quota remaining");

    NSDictionary *cached = [context.cache cachedBodyForURL:URL
                                                    maxAge:365.0 * 24.0 * 60.0 * 60.0];
    MRAssertEqualObjects(@{ @"cached": @YES }, cached,
                         @"authenticated reads never overwrite the public cache");

    [context teardown];
}

static void MRRunSyncPathsTest(void) {
    MRSyncAPIContext *context = [MRSyncAPIContext context];
    [context.http enqueueResponse:MRSyncResponseWithJSON(200, @{ @"shows": @[] }, nil)];
    [context.http enqueueResponse:MRSyncResponseWithJSON(200, @{ @"movies": @[] }, nil)];
    [context.http enqueueResponse:MRSyncResponseWithJSON(200, @{ @"shows": @[] }, nil)];
    [context.http enqueueResponse:MRSyncResponseWithJSON(200, @{}, nil)];

    __block NSUInteger completed = 0;
    [context.client fetchAllItemsForType:MRMediaTypeShow
                                  status:MRWatchStatusNone
                                dateFrom:nil
                                 idsOnly:NO
                            nextWatchInfo:YES
                              completion:^(NSDictionary *json, NSError *error) {
        completed += 1;
    }];
    [context.client fetchAllItemsForType:MRMediaTypeMovie
                                  status:MRWatchStatusWatching
                                dateFrom:@"2026-11-04T12:34:56Z"
                                 idsOnly:YES
                            nextWatchInfo:NO
                              completion:^(NSDictionary *json, NSError *error) {
        completed += 1;
    }];
    [context.client fetchRatingsForType:MRMediaTypeShow
                               dateFrom:@"2026-11-04T12:34:56Z"
                             completion:^(NSDictionary *json, NSError *error) {
        completed += 1;
    }];
    [context.client fetchUserSettingsWithCompletion:
        ^(NSDictionary *json, NSError *error) {
        completed += 1;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return completed == 4; }, 2.0),
                 @"all authenticated sync paths complete");
    MRAssertEqualIntegers(4, (NSInteger)context.http.requestCount,
                          @"each authenticated read sends one request");

    NSString *showURL = [@"https://api.simkl.com/sync/all-items/shows"
                         stringByAppendingString:
                         [NSString stringWithFormat:@"%@&language=en&next_watch_info=yes",
                          MRSyncCommonQuery()]];
    MRAssertEqualObjects(showURL, [[context.http requestAtIndex:0] URL],
                         @"watch status None omits the status path segment");
    MRAssertTrue([[[context.http requestAtIndex:0] URL] rangeOfString:@"/none"].location == NSNotFound,
                 @"no /none path segment is requested");
    MRAssertTrue([[[context.http requestAtIndex:0] URL] rangeOfString:@"extended"].location == NSNotFound,
                 @"next watch info does not ask for extended=full");

    NSString *movieURL = [@"https://api.simkl.com/sync/all-items/movies/watching"
                          stringByAppendingString:
                          [NSString stringWithFormat:
                           @"%@&date_from=2026-11-04T12%%3A34%%3A56Z"
                           @"&extended=simkl_ids_only&language=en",
                           MRSyncCommonQuery()]];
    MRAssertEqualObjects(movieURL, [[context.http requestAtIndex:1] URL],
                         @"idsOnly, date_from, and a status bucket map exactly");

    NSString *ratingsURL = [@"https://api.simkl.com/sync/ratings/shows"
                            stringByAppendingString:
                            [NSString stringWithFormat:
                             @"%@&date_from=2026-11-04T12%%3A34%%3A56Z&language=en",
                             MRSyncCommonQuery()]];
    MRAssertEqualObjects(ratingsURL, [[context.http requestAtIndex:2] URL],
                         @"ratings use the sync show name, not tv");

    NSString *settingsURL = [@"https://api.simkl.com/users/settings"
                             stringByAppendingString:MRSyncCommonQuery()];
    MRAssertEqualObjects(settingsURL, [[context.http requestAtIndex:3] URL],
                         @"user settings URL shape");

    for (MRHTTPRequest *request in context.http.requests) {
        MRAssertEqualObjects(@"Bearer TOKEN-123",
                             [request.headers objectForKey:@"Authorization"],
                             @"every authenticated read attaches the bearer token");
    }

    [context teardown];
}

static void MRRunAuthenticatedCancellationTest(void) {
    MRSyncAPIContext *context = [MRSyncAPIContext context];
    MRSyncDeferredTokenProvider *provider = [[MRSyncDeferredTokenProvider alloc] init];
    MRAPIClient *client = [[MRAPIClient alloc] initWithHTTPClient:context.http
                                                   tokenProvider:provider
                                                   responseCache:context.cache
                                                    quotaTracker:context.quota
                                                     diagnostics:context.diagnostics
                                                           clock:context.clock];

    __block NSUInteger completions = 0;
    __block NSError *completionError = nil;
    id<MRHTTPTask> task = [client fetchActivitiesWithCompletion:
                           ^(NSDictionary *json, NSError *error) {
        completions += 1;
        completionError = error;
    }];
    MRAssertTrue(task != nil, @"an authenticated read returns a cancellable task");
    MRAssertEqualIntegers(1, provider.calls, @"the token request is pending");
    [task cancel];

    if (provider.pendingCompletion != nil) {
        provider.pendingCompletion(@"TOKEN-123", nil);
    }
    MRAssertTrue(MRRunUntil(^BOOL { return completions > 0; }, 2.0),
                 @"a cancellation while fetching the token completes");
    MRAssertEqualIntegers(1, (NSInteger)completions,
                          @"cancellation completes exactly once");
    MRAssertEqualIntegers(MRErrorKindCancelled, [MRError kindForError:completionError],
                          @"cancellation reports Cancelled");
    MRAssertEqualIntegers(0, (NSInteger)context.http.requestCount,
                          @"cancellation before the token sends no HTTP request");

    [context teardown];
}

static void MRRunAuthenticatedTokenFailureTest(void) {
    MRSyncAPIContext *context = [MRSyncAPIContext context];
    context.tokenProvider.token = nil;
    context.tokenProvider.error = [MRError errorWithKind:MRErrorKindAuthExpired];

    __block BOOL finished = NO;
    __block NSError *error = nil;
    [context.client fetchActivitiesWithCompletion:^(NSDictionary *json,
                                                    NSError *resultError) {
        finished = YES;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"a token failure completes the read");
    MRAssertEqualIntegers(MRErrorKindAuthExpired, [MRError kindForError:error],
                          @"a token failure surfaces the auth error");
    MRAssertEqualIntegers(0, (NSInteger)context.http.requestCount,
                          @"a token failure sends no HTTP request");

    [context teardown];
}

static void MRRunAuthenticatedErrorKeepsTokenOutOfDiagnostics(void) {
    MRSyncAPIContext *context = [MRSyncAPIContext context];
    [context.http enqueueResponse:MRSyncResponseWithJSON(401,
                                                          @{ @"error": @"user_token_failed" },
                                                          nil)];

    __block BOOL finished = NO;
    __block NSError *error = nil;
    [context.client fetchActivitiesWithCompletion:^(NSDictionary *json,
                                                    NSError *resultError) {
        finished = YES;
        error = resultError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"a failed authenticated read completes");
    MRAssertTrue(error != nil, @"a failed authenticated read reports an error");
    MRAssertTrue([context.diagnostics records].count > 0,
                 @"the failure is recorded in diagnostics");

    NSString *serialized = [[context.diagnostics records] description];
    MRAssertTrue([serialized rangeOfString:@"TOKEN-123"].location == NSNotFound,
                 @"diagnostics never contain the bearer token");
    MRAssertTrue([[serialized lowercaseString] rangeOfString:@"bearer"].location == NSNotFound,
                 @"diagnostics never contain the authorization scheme");

    [context teardown];
}

void MRRunMRSyncInitialTests(void) {
    MRRunSyncSequence();
    MRRunSyncFailureKeepsSnapshot();
    MRRunConcurrentSyncJoins();
    MRRunSyncCancellation();
    MRRunEngineResumesLastSyncAt();
    MRRunMaxItemsSplit();
    MRRunNullRating();
    MRRunAuthenticatedReadTest();
    MRRunSyncPathsTest();
    MRRunAuthenticatedCancellationTest();
    MRRunAuthenticatedTokenFailureTest();
    MRRunAuthenticatedErrorKeepsTokenOutOfDiagnostics();
}
