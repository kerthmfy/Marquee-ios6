//
//  MRSyncDeletionTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRStorage.h"
#import "MRSyncEngine.h"
#import "MRUserProfile.h"

#pragma mark - Provider

@interface MRDeletionResponse : NSObject
@property (nonatomic, strong) NSDictionary *json;
@property (nonatomic, strong) NSError *error;
@end

@implementation MRDeletionResponse
@end

@interface MRDeletionProvider : NSObject <MRSyncDataProviding>
@property (nonatomic, strong) NSMutableArray *responses;
@property (nonatomic, strong) NSMutableArray *calls;
- (void)enqueueJSON:(NSDictionary *)json;
- (void)enqueueError:(NSError *)error;
@end

@implementation MRDeletionProvider

- (id)init {
    self = [super init];
    if (self) {
        _responses = [NSMutableArray array];
        _calls = [NSMutableArray array];
    }
    return self;
}

- (void)enqueueJSON:(NSDictionary *)json {
    MRDeletionResponse *response = [[MRDeletionResponse alloc] init];
    response.json = json;
    [self.responses addObject:response];
}

- (void)enqueueError:(NSError *)error {
    MRDeletionResponse *response = [[MRDeletionResponse alloc] init];
    response.error = error;
    [self.responses addObject:response];
}

- (void)deliverToCompletion:(void (^)(NSDictionary *json, NSError *error))completion {
    MRDeletionResponse *response = nil;
    if (self.responses.count > 0) {
        response = [self.responses objectAtIndex:0];
        [self.responses removeObjectAtIndex:0];
    }
    if (completion != nil) {
        completion(response.json, response.error);
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
    [self.calls addObject:@{ @"kind": @"ratings", @"type": @(type),
                             @"dateFrom": dateFrom ?: @"" }];
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

static NSString *MRDeletionTestRoot(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-deletion-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return root;
}

static void MRDeletionRemoveRoot(NSString *root) {
    if (root.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}

static MRLibraryStore *MRDeletionStore(NSString *root) {
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    return [[MRLibraryStore alloc] initWithStorage:storage];
}

static MRMediaItem *MRDeletionMovie(NSInteger simklID, NSInteger rating) {
    return [MRMediaItem itemWithSyncDictionary:@{
        @"status": @"completed",
        @"user_rating": @(rating),
        @"movie": @{
            @"title": [NSString stringWithFormat:@"Movie %ld", (long)simklID],
            @"year": @2021,
            @"ids": @{ @"simkl": @(simklID) }
        }
    } type:MRMediaTypeMovie];
}

static MRMediaItem *MRDeletionShow(NSInteger simklID) {
    return [MRMediaItem itemWithSyncDictionary:@{
        @"status": @"watching",
        @"show": @{
            @"title": [NSString stringWithFormat:@"Show %ld", (long)simklID],
            @"year": @2020,
            @"ids": @{ @"simkl": @(simklID) }
        }
    } type:MRMediaTypeShow];
}

static MRLibraryStore *MRDeletionStoreWithSnapshot(NSString *root,
                                                   NSArray *items,
                                                   NSDictionary *activities,
                                                   MRUserProfile *profile) {
    MRLibraryStore *store = MRDeletionStore(root);
    NSError *error = nil;
    MRAssertTrue([store replaceWithItems:items
                              activities:activities
                                 profile:profile
                                   error:&error],
                 @"deletion test setup saves a snapshot");
    MRAssertTrue(error == nil, @"deletion test setup has no error");
    return store;
}

static MRSyncEngine *MRDeletionEngine(MRDeletionProvider *provider,
                                      MRLibraryStore *store,
                                      MRFakeClock *clock) {
    return [[MRSyncEngine alloc] initWithDataProvider:provider
                                         libraryStore:store
                                              storage:nil
                                                clock:clock];
}

static NSError *MRDeletionSync(MRSyncEngine *engine) {
    __block BOOL finished = NO;
    __block NSError *resultError = nil;
    [engine syncWithCompletion:^(NSError *error) {
        finished = YES;
        resultError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL { return finished; }, 2.0),
                 @"deletion sync completes");
    return resultError;
}

static MRUserProfile *MRDeletionProfile(NSString *name) {
    return [MRUserProfile profileWithSettingsDictionary:@{
        @"user": @{ @"name": name },
        @"account": @{ @"id": @12345 }
    }];
}

#pragma mark - Tests

static void MRRunDeletionDiffTest(void) {
    NSString *root = MRDeletionTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeletionStoreWithSnapshot(root, @[
        MRDeletionMovie(777, 8),
        MRDeletionMovie(888, 4),
        MRDeletionMovie(999, 0),
        MRDeletionShow(1234)
    ], saved, nil);
    NSInteger generation = store.generation;

    MRDeletionProvider *provider = [[MRDeletionProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-removals")];
    [provider enqueueJSON:MRFixture(@"sync-ids-movies")];
    MRSyncEngine *engine = MRDeletionEngine(provider, store, [[MRFakeClock alloc] init]);

    NSError *error = MRDeletionSync(engine);
    MRAssertTrue(error == nil, @"the deletion diff succeeds");
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"only the activities gate and id-only fetch run");
    NSDictionary *call = [provider.calls objectAtIndex:1];
    MRAssertEqualObjects(@"items", [call objectForKey:@"kind"],
                         @"the deletion diff is an all-items call");
    MRAssertEqualIntegers(MRMediaTypeMovie,
                          [[call objectForKey:@"type"] integerValue],
                          @"the moved removed_from_list fetches movies");
    MRAssertTrue([[call objectForKey:@"idsOnly"] boolValue],
                 @"the deletion diff requests simkl_ids_only");
    MRAssertEqualObjects(@"", [call objectForKey:@"dateFrom"],
                         @"the deletion diff does not use date_from");
    MRAssertTrue(![[call objectForKey:@"nextWatchInfo"] boolValue],
                 @"the deletion diff does not request next watch info");

    MRAssertTrue([store itemForType:MRMediaTypeMovie simklID:777] == nil,
                 @"a missing remote ID removes the local item");
    MRAssertTrue([store itemForType:MRMediaTypeMovie simklID:888] != nil,
                 @"an ID present remotely is kept");
    MRAssertTrue([store itemForType:MRMediaTypeMovie simklID:999] != nil,
                 @"a second present ID is kept");
    MRAssertTrue([store itemForType:MRMediaTypeShow simklID:1234] != nil,
                 @"the untouched show domain is kept");
    MRAssertEqualObjects(MRFixture(@"activities-removals"), store.activities,
                         @"the deletion sync saves the new activities");
    MRAssertEqualIntegers(generation + 1, store.generation,
                          @"the deletion sync increments the generation");

    MRDeletionRemoveRoot(root);
}

static void MRRunDeletionFetchFailureTest(void) {
    NSString *root = MRDeletionTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeletionStoreWithSnapshot(root,
        @[ MRDeletionMovie(777, 8), MRDeletionMovie(888, 4) ], saved, nil);
    NSInteger generation = store.generation;

    MRDeletionProvider *provider = [[MRDeletionProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-removals")];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindServer]];
    MRSyncEngine *engine = MRDeletionEngine(provider, store, [[MRFakeClock alloc] init]);

    NSError *error = MRDeletionSync(engine);
    MRAssertTrue(error != nil, @"a failed deletion diff reports an error");
    MRAssertEqualIntegers(MRErrorKindServer, [MRError kindForError:error],
                          @"the deletion error is preserved");
    MRAssertTrue([store itemForType:MRMediaTypeMovie simklID:777] != nil,
                 @"a failed id-only fetch removes nothing");
    MRAssertEqualIntegers(8,
        [store itemForType:MRMediaTypeMovie simklID:777].userRating,
        @"a failed deletion diff keeps local ratings");
    MRAssertEqualObjects(saved, store.activities,
                         @"a failed deletion diff keeps the old activities");
    MRAssertEqualIntegers(generation, store.generation,
                          @"a failed deletion diff keeps the generation");

    MRDeletionRemoveRoot(root);
}

static void MRRunSettingsRefreshTest(void) {
    NSString *root = MRDeletionTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRUserProfile *oldProfile = MRDeletionProfile(@"Kerth");
    MRLibraryStore *store = MRDeletionStoreWithSnapshot(root,
        @[ MRDeletionShow(1234) ], saved, oldProfile);
    NSInteger generation = store.generation;

    MRDeletionProvider *provider = [[MRDeletionProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-settings")];
    [provider enqueueJSON:@{
        @"user": @{ @"name": @"Ada", @"loc": @"London" },
        @"account": @{ @"id": @12345, @"type": @"free" }
    }];
    MRSyncEngine *engine = MRDeletionEngine(provider, store, [[MRFakeClock alloc] init]);

    NSError *error = MRDeletionSync(engine);
    MRAssertTrue(error == nil, @"the settings refresh succeeds");
    MRAssertEqualIntegers(2, (NSInteger)provider.calls.count,
                          @"only activities and settings are fetched");
    MRAssertEqualObjects(@"settings",
                         [[provider.calls objectAtIndex:1] objectForKey:@"kind"],
                         @"settings.all triggers /users/settings");
    MRAssertEqualObjects(@"Ada", store.profile.name,
                         @"the refreshed profile name is merged");
    MRAssertEqualObjects(@"London", store.profile.location,
                         @"the refreshed profile location is merged");
    MRAssertEqualObjects(MRFixture(@"activities-settings"), store.activities,
                         @"the settings sync saves the new activities");
    MRAssertEqualIntegers(generation + 1, store.generation,
                          @"the settings sync increments the generation");

    MRLibraryStore *reloaded = MRDeletionStore(root);
    NSError *loadError = nil;
    MRAssertTrue([reloaded load:&loadError], @"the settings snapshot reloads");
    MRAssertEqualObjects(@"Ada", reloaded.profile.name,
                         @"the refreshed profile is persisted");

    MRDeletionRemoveRoot(root);
}

static void MRRunPlaybackIgnoredTest(void) {
    NSString *root = MRDeletionTestRoot();
    NSDictionary *saved = MRFixture(@"activities-saved");
    MRLibraryStore *store = MRDeletionStoreWithSnapshot(root,
        @[ MRDeletionShow(1234) ], saved, nil);
    NSInteger generation = store.generation;

    MRDeletionProvider *provider = [[MRDeletionProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-playback")];
    MRSyncEngine *engine = MRDeletionEngine(provider, store, [[MRFakeClock alloc] init]);

    NSError *error = MRDeletionSync(engine);
    MRAssertTrue(error == nil, @"a playback-only activities move succeeds");
    MRAssertEqualIntegers(1, (NSInteger)provider.calls.count,
                          @"playback and custom_lists moves trigger no fetch");
    MRAssertEqualObjects(MRFixture(@"activities-playback"), store.activities,
                         @"the new activities snapshot is still saved");
    MRAssertEqualIntegers(generation + 1, store.generation,
                          @"a playback-only move still increments the generation");
    MRAssertTrue([store itemForType:MRMediaTypeShow simklID:1234] != nil,
                 @"the library is left in place");

    MRDeletionRemoveRoot(root);
}

static void MRRunMaxItemsBucketFailureTest(void) {
    NSString *root = MRDeletionTestRoot();
    NSDictionary *oldActivities = @{ @"all": @"old" };
    MRLibraryStore *store = MRDeletionStoreWithSnapshot(root,
        @[ MRDeletionShow(1234) ], oldActivities, nil);
    NSInteger generation = store.generation;

    MRDeletionProvider *provider = [[MRDeletionProvider alloc] init];
    [provider enqueueJSON:MRFixture(@"activities-saved")];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindTooLarge]];
    [provider enqueueError:[MRError errorWithKind:MRErrorKindTooLarge]];
    MRSyncEngine *engine = MRDeletionEngine(provider, store, [[MRFakeClock alloc] init]);

    NSError *error = MRDeletionSync(engine);
    MRAssertTrue(error != nil, @"a still-failing bucket reports an error");
    MRAssertEqualIntegers(MRErrorKindTooLarge, [MRError kindForError:error],
                          @"the max_items error is preserved");
    MRAssertTrue([[error localizedDescription] rangeOfString:@"too large for one sync"].location
                     != NSNotFound,
                 @"the max_items error uses the sync-specific message");
    MRAssertEqualIntegers(generation, store.generation,
                          @"a failed bucket keeps the old generation");
    MRAssertTrue([store itemForType:MRMediaTypeShow simklID:1234] != nil,
                 @"a failed bucket keeps the old snapshot");
    MRAssertEqualObjects(oldActivities, store.activities,
                         @"a failed bucket keeps the old activities");

    MRDeletionRemoveRoot(root);
}

void MRRunSyncDeletionTests(void) {
    MRRunDeletionDiffTest();
    MRRunDeletionFetchFailureTest();
    MRRunSettingsRefreshTest();
    MRRunPlaybackIgnoredTest();
    MRRunMaxItemsBucketFailureTest();
}
