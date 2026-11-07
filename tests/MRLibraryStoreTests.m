//
//  MRLibraryStoreTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDate.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRStorage.h"
#import "MRUserProfile.h"

static NSString *MRLibraryTestDirectory(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-library-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

static void MRRemoveLibraryTestDirectory(NSString *directory) {
    if (directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    }
}

static MRUserProfile *MRLibraryTestProfile(void) {
    return [MRUserProfile profileWithSettingsDictionary:@{
        @"user": @{ @"name": @"kerth", @"joined_at": @"2018-01-15T00:00:00Z" },
        @"account": @{ @"id": @12345, @"timezone": @"Europe/Madrid", @"type": @"free" }
    }];
}

@interface MRLibraryTestFailingStorage : MRStorage
@property (nonatomic, assign) BOOL failStateWrites;
@end

@implementation MRLibraryTestFailingStorage

- (BOOL)writeJSON:(id)json named:(NSString *)name error:(NSError **)error {
    if (self.failStateWrites && [name isEqualToString:@"state.json"]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MRLibraryTestFailingStorage"
                                         code:1
                                     userInfo:nil];
        }
        return NO;
    }
    return [super writeJSON:json named:name error:error];
}

@end

static MRMediaItem *MRLibraryShowItem(void) {
    return [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-shows")[@"shows"][0]
                                          type:MRMediaTypeShow];
}

static MRMediaItem *MRLibraryMovieItem(void) {
    return [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-movies")[@"movies"][0]
                                          type:MRMediaTypeMovie];
}

static MRMediaItem *MRLibraryAnimeItem(void) {
    return [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-anime")[@"anime"][0]
                                          type:MRMediaTypeAnime];
}

static NSArray *MRLibraryAllItems(void) {
    return @[ MRLibraryShowItem(), MRLibraryMovieItem(), MRLibraryAnimeItem() ];
}

static void MRRunReplaceAndLoad(void) {
    NSString *root = MRLibraryTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];

    __block NSUInteger changes = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRLibraryDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        changes += 1;
    }];

    NSDictionary *activities = @{ @"all": @"2026-11-04T12:00:00Z",
                                  @"tv_shows": @{ @"all": @"2026-11-03T10:00:00Z" } };
    NSError *error = nil;
    BOOL replaced = [store replaceWithItems:MRLibraryAllItems()
                                 activities:activities
                                    profile:MRLibraryTestProfile()
                                      error:&error];
    MRAssertTrue(replaced, @"replace persists a fresh snapshot");
    MRAssertTrue(error == nil, @"replace has no error");
    MRAssertEqualIntegers(1, store.generation, @"first replacement is generation 1");
    MRAssertEqualIntegers(3, (NSInteger)store.items.count, @"replace stores every item");
    MRAssertEqualObjects(activities, store.activities, @"replace stores activities");
    MRAssertEqualObjects(@"kerth", store.profile.name, @"replace stores the profile");
    MRAssertTrue(store.savedAt != nil, @"replace records savedAt");
    MRAssertTrue(store.lastSyncAt != nil, @"replace records lastSyncAt");
    MRAssertTrue(store.lastFullSyncAt != nil, @"replace records lastFullSyncAt");
    MRAssertEqualIntegers(1, (NSInteger)changes,
                          @"replace posts one library-change notification");

    MRMediaItem *show = [store itemForType:MRMediaTypeShow simklID:3407];
    MRAssertTrue(show != nil, @"itemForType finds the show");
    MRAssertEqualObjects(@"Futurama", show.title, @"stored show title");
    MRAssertEqualIntegers(MRWatchStatusWatching, show.watchStatus,
                          @"stored show status");

    NSArray *watching = [store itemsForType:MRMediaTypeShow
                                     status:MRWatchStatusWatching];
    MRAssertEqualIntegers(1, (NSInteger)watching.count,
                          @"itemsForType filters by type and status");
    NSArray *allShows = [store itemsForType:MRMediaTypeShow status:MRWatchStatusNone];
    MRAssertEqualIntegers(1, (NSInteger)allShows.count,
                          @"status None returns every item of the type");

    NSDictionary *showCounts = [store countsByStatusForType:MRMediaTypeShow];
    MRAssertEqualIntegers(1, [[showCounts objectForKey:@"watching"] integerValue],
                          @"show counts include watching");
    MRAssertEqualIntegers(0, [[showCounts objectForKey:@"completed"] integerValue],
                          @"show counts include zero buckets");
    NSDictionary *movieCounts = [store countsByStatusForType:MRMediaTypeMovie];
    MRAssertEqualIntegers(1, [[movieCounts objectForKey:@"completed"] integerValue],
                          @"movie counts include completed");

    MRLibraryStore *reloaded = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *loadError = nil;
    BOOL loaded = [reloaded load:&loadError];
    MRAssertTrue(loaded, @"a matching snapshot loads");
    MRAssertTrue(loadError == nil, @"a matching snapshot has no error");
    MRAssertEqualIntegers(1, reloaded.generation, @"load restores the generation");
    MRAssertEqualIntegers(3, (NSInteger)reloaded.items.count,
                          @"load restores every item");
    MRAssertEqualObjects(activities, reloaded.activities,
                         @"load restores activities");
    MRAssertEqualObjects(@"kerth", reloaded.profile.name,
                         @"load restores the profile");
    MRAssertEqualObjects(@"Europe/Madrid", reloaded.profile.timezone,
                         @"load restores the profile timezone");
    MRAssertTrue(reloaded.savedAt != nil, @"load restores savedAt");
    MRAssertTrue(reloaded.lastSyncAt != nil, @"load restores lastSyncAt");
    MRAssertTrue(reloaded.lastFullSyncAt != nil, @"load restores lastFullSyncAt");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    MRRemoveLibraryTestDirectory(root);
}

static void MRRunMissingAndMismatchedSnapshots(void) {
    NSString *emptyRoot = MRLibraryTestDirectory();
    MRStorage *emptyStorage = [[MRStorage alloc] initWithRootDirectory:emptyRoot
                                                              accountID:12345];
    MRLibraryStore *emptyStore = [[MRLibraryStore alloc] initWithStorage:emptyStorage];
    NSError *missingError = nil;
    BOOL missingLoaded = [emptyStore load:&missingError];
    MRAssertTrue(!missingLoaded, @"a missing snapshot is not trustworthy");
    MRAssertTrue(missingError != nil, @"a missing snapshot reports a repair error");
    MRAssertEqualIntegers(0, (NSInteger)emptyStore.items.count,
                          @"a missing snapshot leaves no items");
    MRRemoveLibraryTestDirectory(emptyRoot);

    NSString *root = MRLibraryTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *replaceError = nil;
    MRAssertTrue([store replaceWithItems:MRLibraryAllItems()
                              activities:@{ @"all": @"1" }
                                 profile:MRLibraryTestProfile()
                                   error:&replaceError],
                 @"mismatch setup writes a snapshot");

    NSError *readError = nil;
    NSDictionary *state = [storage readJSONNamed:@"state.json" error:&readError];
    MRAssertTrue(state != nil, @"mismatch setup reads state.json");
    NSMutableDictionary *mutated = [NSMutableDictionary dictionaryWithDictionary:state];
    [mutated setObject:@(store.generation + 1) forKey:@"generation"];
    NSError *writeError = nil;
    MRAssertTrue([storage writeJSON:mutated named:@"state.json" error:&writeError],
                 @"mismatch setup bumps only the state generation");

    MRLibraryStore *reloaded = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *mismatchError = nil;
    BOOL loaded = [reloaded load:&mismatchError];
    MRAssertTrue(!loaded, @"a generation mismatch is not trustworthy");
    MRAssertTrue(mismatchError != nil, @"a generation mismatch reports a repair error");
    MRAssertEqualIntegers(0, (NSInteger)reloaded.items.count,
                          @"a generation mismatch leaves no items");

    MRRemoveLibraryTestDirectory(root);
}

static void MRRunMutators(void) {
    NSString *root = MRLibraryTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *error = nil;
    MRAssertTrue([store replaceWithItems:@[ MRLibraryShowItem() ]
                              activities:@{ @"all": @"1" }
                                 profile:MRLibraryTestProfile()
                                   error:&error],
                 @"mutator setup writes a show");

    __block NSUInteger changes = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRLibraryDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        changes += 1;
    }];

    NSError *statusError = nil;
    MRAssertTrue([store applyResolvedStatus:MRWatchStatusCompleted
                                forItemType:MRMediaTypeShow
                                    simklID:3407
                                      error:&statusError],
                 @"applyResolvedStatus updates an existing item");
    MRAssertEqualIntegers(MRWatchStatusCompleted,
                          [store itemForType:MRMediaTypeShow simklID:3407].watchStatus,
                          @"resolved status is stored");
    MRAssertEqualIntegers(2, store.generation,
                          @"mutators increment the generation");

    NSError *ratingError = nil;
    MRAssertTrue([store applyUserRating:9
                            forItemType:MRMediaTypeShow
                                simklID:3407
                                  error:&ratingError],
                 @"applyUserRating updates an existing item");
    MRAssertEqualIntegers(9,
                          [store itemForType:MRMediaTypeShow simklID:3407].userRating,
                          @"user rating is stored");
    MRAssertTrue([store applyUserRating:0
                            forItemType:MRMediaTypeShow
                                simklID:3407
                                  error:&ratingError],
                 @"applyUserRating clears an existing item");
    MRAssertEqualIntegers(0,
                          [store itemForType:MRMediaTypeShow simklID:3407].userRating,
                          @"zero clears the user rating");
    MRAssertEqualIntegers(3, (NSInteger)changes,
                          @"every mutator posts a library-change notification");

    NSError *missingError = nil;
    MRAssertTrue(![store applyUserRating:5
                             forItemType:MRMediaTypeShow
                                 simklID:999
                                   error:&missingError],
                 @"a missing item cannot be rated");
    MRAssertTrue([MRError kindForError:missingError] == MRErrorKindNotFound,
                 @"a missing item reports NotFound");

    MRLibraryStore *reloaded = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *loadError = nil;
    MRAssertTrue([reloaded load:&loadError], @"mutated snapshot reloads");
    MRAssertEqualIntegers(MRWatchStatusCompleted,
                          [reloaded itemForType:MRMediaTypeShow simklID:3407].watchStatus,
                          @"resolved status persisted");
    MRAssertEqualIntegers(0,
                          [reloaded itemForType:MRMediaTypeShow simklID:3407].userRating,
                          @"cleared rating persisted");

    NSError *removeError = nil;
    MRAssertTrue([store removeItemForType:MRMediaTypeShow simklID:3407 error:&removeError],
                 @"removeItem removes an existing item");
    MRAssertTrue([store itemForType:MRMediaTypeShow simklID:3407] == nil,
                 @"removed item is gone from memory");
    MRLibraryStore *afterRemove = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *afterRemoveError = nil;
    MRAssertTrue([afterRemove load:&afterRemoveError],
                 @"an empty but valid snapshot still loads");
    MRAssertEqualIntegers(0, (NSInteger)afterRemove.items.count,
                          @"removed item is gone from disk");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    MRRemoveLibraryTestDirectory(root);
}

static void MRRunMerge(void) {
    NSString *root = MRLibraryTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *error = nil;
    MRAssertTrue([store replaceWithItems:@[ MRLibraryShowItem() ]
                              activities:@{ @"all": @"1" }
                                 profile:MRLibraryTestProfile()
                                   error:&error],
                 @"merge setup writes a show");
    NSDate *fullSyncDate = store.lastFullSyncAt;
    NSString *showIdentifier = [MRLibraryShowItem() identifier];

    NSError *mergeError = nil;
    BOOL merged = [store mergeWithItems:@[ MRLibraryMovieItem() ]
                     removedIdentifiers:@[ showIdentifier ]
                                ratings:@{ [MRLibraryMovieItem() identifier]: @8 }
                             activities:@{ @"all": @"2" }
                                profile:nil
                                  error:&mergeError];
    MRAssertTrue(merged, @"merge applies items, removals, and ratings");
    MRAssertTrue(mergeError == nil, @"merge has no error");
    MRAssertEqualIntegers(1, (NSInteger)store.items.count, @"merge removes the show");
    MRMediaItem *movie = [store itemForType:MRMediaTypeMovie simklID:250822];
    MRAssertTrue(movie != nil, @"merge adds the movie");
    MRAssertEqualIntegers(8, movie.userRating, @"merge applies the rating");
    MRAssertEqualObjects(@"kerth", store.profile.name,
                         @"merge preserves the profile when passed nil");
    MRAssertEqualObjects(@"2", [store.activities objectForKey:@"all"],
                         @"merge replaces activities");
    MRAssertEqualIntegers(2, store.generation, @"merge increments the generation");
    MRAssertEqualObjects(fullSyncDate, store.lastFullSyncAt,
                         @"merge keeps the full-sync date");

    MRRemoveLibraryTestDirectory(root);
}

static void MRRunProfileUpdateRollback(void) {
    NSString *root = MRLibraryTestDirectory();
    MRLibraryTestFailingStorage *storage =
        [[MRLibraryTestFailingStorage alloc] initWithRootDirectory:root accountID:12345];
    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *error = nil;
    MRAssertTrue([store replaceWithItems:@[ MRLibraryShowItem() ]
                              activities:@{ @"all": @"1" }
                                 profile:MRLibraryTestProfile()
                                   error:&error],
                 @"profile setup writes a snapshot");

    MRUserProfile *nextProfile = [MRUserProfile profileWithSettingsDictionary:@{
        @"user": @{ @"name": @"renamed" },
        @"account": @{ @"id": @12345, @"timezone": @"Europe/Madrid" }
    }];

    __block NSUInteger changes = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRLibraryDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        changes += 1;
    }];

    storage.failStateWrites = YES;
    NSError *updateError = nil;
    MRAssertTrue(![store updateProfile:nextProfile error:&updateError],
                 @"a failed state write fails the profile update");
    MRAssertTrue(updateError != nil, @"a failed profile update reports an error");
    MRAssertEqualObjects(@"kerth", store.profile.name,
                         @"a failed profile update keeps the old profile in memory");
    MRAssertEqualIntegers(0, (NSInteger)changes,
                          @"a failed profile update posts no change");

    MRLibraryStore *unchanged = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *unchangedError = nil;
    MRAssertTrue([unchanged load:&unchangedError],
                 @"the old snapshot still loads after a failed update");
    MRAssertEqualObjects(@"kerth", unchanged.profile.name,
                         @"a failed profile update keeps the old profile on disk");

    storage.failStateWrites = NO;
    NSError *secondError = nil;
    MRAssertTrue([store updateProfile:nextProfile error:&secondError],
                 @"a profile update succeeds when the state write works");
    MRAssertEqualObjects(@"renamed", store.profile.name,
                         @"a successful profile update changes memory");
    MRAssertEqualIntegers(1, (NSInteger)changes,
                          @"a successful profile update posts one change");

    MRLibraryStore *reloaded = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *reloadError = nil;
    MRAssertTrue([reloaded load:&reloadError],
                 @"the updated snapshot loads");
    MRAssertEqualObjects(@"renamed", reloaded.profile.name,
                         @"a successful profile update changes disk");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    MRRemoveLibraryTestDirectory(root);
}

void MRRunMRLibraryStoreTests(void) {
    MRRunReplaceAndLoad();
    MRRunMissingAndMismatchedSnapshots();
    MRRunMutators();
    MRRunMerge();
    MRRunProfileUpdateRollback();
}
