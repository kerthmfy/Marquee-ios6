//
//  MRSyncEngine.m
//  Marquee
//

#import "MRSyncEngine.h"
#import "MRClock.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MRStorage.h"
#import "MRUserProfile.h"

NSString *const MRSyncStatusDidChangeNotification = @"MRSyncStatusDidChangeNotification";

static const NSTimeInterval MRSyncAutomaticInterval = 15.0 * 60.0;
static const NSTimeInterval MRSyncOutboxDrainInterval = 60.0;

static void MRSyncDeliverOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        block();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), block);
}

static NSString *MRSyncTypeKey(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"shows";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movies";
    }
}

static NSArray *MRSyncStatusesForType(MRMediaType type) {
    // Movies do not have watching or hold buckets.
    if (type == MRMediaTypeMovie) {
        return @[ @(MRWatchStatusPlanToWatch), @(MRWatchStatusCompleted),
                  @(MRWatchStatusDropped) ];
    }
    return @[ @(MRWatchStatusWatching), @(MRWatchStatusPlanToWatch),
              @(MRWatchStatusCompleted), @(MRWatchStatusHold),
              @(MRWatchStatusDropped) ];
}

static NSString *MRSyncActivitiesDomainKey(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"tv_shows";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movies";
    }
}

static NSString *MRSyncActivitiesString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static BOOL MRSyncActivitiesStringsDiffer(id first, id second) {
    NSString *left = MRSyncActivitiesString(first);
    NSString *right = MRSyncActivitiesString(second);
    if (left == nil && right == nil) {
        return NO;
    }
    return ![left isEqualToString:right];
}

static NSDictionary *MRSyncActivitiesDomain(NSDictionary *activities, NSString *key) {
    id domain = [activities isKindOfClass:[NSDictionary class]]
        ? [activities objectForKey:key] : nil;
    return [domain isKindOfClass:[NSDictionary class]] ? domain : nil;
}

// Phase 2 is only safe when the saved snapshot carries the complete activities
// shape. Older or partial state falls back to a full phase-1 pull.
static BOOL MRSyncActivitiesAreComplete(NSDictionary *activities) {
    if (![activities isKindOfClass:[NSDictionary class]] ||
        MRSyncActivitiesString([activities objectForKey:@"all"]).length == 0) {
        return NO;
    }
    NSArray *keys = @[ @"tv_shows", @"movies", @"anime" ];
    for (NSString *key in keys) {
        if (MRSyncActivitiesDomain(activities, key) == nil) {
            return NO;
        }
    }
    return YES;
}

@interface MRSyncEngine ()
@property (nonatomic, strong) id<MRSyncDataProviding> dataProvider;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, assign, readwrite, getter=isSyncing) BOOL syncing;
@property (nonatomic, strong, readwrite) NSDate *lastSyncAt;
@property (nonatomic, strong, readwrite) NSDate *lastSyncAttemptAt;
@property (nonatomic, strong, readwrite) NSError *lastSyncError;
- (void)finishCancelled;
- (void)deliverCompletionsWithError:(NSError *)error;
- (void)fetchActivities;
- (void)processPhase2Activities:(NSDictionary *)activities;
- (void)finishPhase2WithActivities:(NSDictionary *)activities;
- (void)fetchPhase2RemovalsForDomains:(NSArray *)domains
                               index:(NSUInteger)index
                          completion:(void (^)(NSError *error))completion;
@end

@implementation MRSyncEngine {
    NSMutableArray *_completionBlocks;
    NSMutableArray *_items;
    NSMutableSet *_itemIdentifiers;
    NSMutableDictionary *_ratings;
    NSMutableArray *_removedIdentifiers;
    MRUserProfile *_profile;
    NSDictionary *_activities;
    NSString *_savedActivitiesAll;
    id<MRHTTPTask> _currentTask;
    BOOL _finished;
    BOOL _cancelled;
    BOOL _needsSync;
    NSDate *_lastOutboxDrainSyncAt;
}

- (instancetype)initWithDataProvider:(id<MRSyncDataProviding>)dataProvider
                        libraryStore:(MRLibraryStore *)libraryStore
                             storage:(MRStorage *)storage
                               clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _dataProvider = dataProvider;
        _libraryStore = libraryStore;
        _storage = storage;
        _clock = clock;
        _lastSyncAt = libraryStore.lastSyncAt;
        _completionBlocks = [NSMutableArray array];
    }
    return self;
}

- (NSUInteger)pendingCount {
    return self.outbox.pendingCount;
}

- (void)setOutbox:(MROutbox *)outbox {
    _outbox = outbox;
}

#pragma mark - State

- (void)postStatusChange {
    MRSyncDeliverOnMain(^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MRSyncStatusDidChangeNotification
                          object:self];
    });
}

- (void)addCompletion:(void (^)(NSError *error))completion {
    if (completion != nil) {
        [_completionBlocks addObject:[completion copy]];
    }
}

#pragma mark - Public

- (void)syncWithCompletion:(void (^)(NSError *error))completion {
    MRSyncDeliverOnMain(^{
        if (self.isSyncing) {
            // The next pass gets a fresh activities gate; callers wait for it.
            _needsSync = YES;
            [self addCompletion:completion];
            return;
        }

        self.syncing = YES;
        self.lastSyncError = nil;
        self.lastSyncAttemptAt = [self.clock now];
        _finished = NO;
        _cancelled = NO;
        _needsSync = NO;
        _activities = nil;
        _savedActivitiesAll = nil;
        _items = [NSMutableArray array];
        _itemIdentifiers = [NSMutableSet set];
        _ratings = [NSMutableDictionary dictionary];
        _removedIdentifiers = [NSMutableArray array];
        _profile = nil;
        [_completionBlocks removeAllObjects];
        [self addCompletion:completion];
        [self postStatusChange];
        [self fetchActivities];
    });
}

- (void)noteForegroundAtDate:(NSDate *)date {
    MRSyncDeliverOnMain(^{
        NSDate *now = date != nil ? date : [self.clock now];
        NSDate *attempt = self.lastSyncAttemptAt;
        if (attempt != nil &&
            [now timeIntervalSinceDate:attempt] < MRSyncAutomaticInterval) {
            return;
        }
        [self syncWithCompletion:nil];
    });
}

- (void)noteOutboxDrainedAtDate:(NSDate *)date {
    MRSyncDeliverOnMain(^{
        NSDate *now = date != nil ? date : [self.clock now];
        if (_lastOutboxDrainSyncAt != nil &&
            [now timeIntervalSinceDate:_lastOutboxDrainSyncAt] <
                MRSyncOutboxDrainInterval) {
            return;
        }
        _lastOutboxDrainSyncAt = now;
        [self syncWithCompletion:nil];
    });
}

- (void)cancel {
    MRSyncDeliverOnMain(^{
        if (!self.isSyncing) {
            return;
        }
        _cancelled = YES;
        id<MRHTTPTask> task = _currentTask;
        _currentTask = nil;
        [task cancel];
        [self finishCancelled];
    });
}

- (void)forceFullSyncWithCompletion:(void (^)(NSError *error))completion {
    MRSyncDeliverOnMain(^{
        if (self.isSyncing) {
            [self cancel];
        }
        // library.json and state.json are rebuilt from the network. Pending
        // writes live in outbox.json and are deliberately left alone.
        [self.storage removeFileNamed:@"library" error:NULL];
        [self.storage removeFileNamed:@"state" error:NULL];
        [self syncWithCompletion:completion];
    });
}

#pragma mark - Phase 1

- (void)fetchActivities {
    if (_finished || _cancelled) {
        return;
    }
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchActivitiesWithCompletion:
                    ^(NSDictionary *json, NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            [strongSelf finishWithError:error];
            return;
        }
        if (![json isKindOfClass:[NSDictionary class]]) {
            [strongSelf finishWithError:[MRError errorWithKind:MRErrorKindParse]];
            return;
        }
        NSDictionary *activities = (NSDictionary *)json;
        if (MRSyncActivitiesAreComplete(strongSelf.libraryStore.activities)) {
            [strongSelf processPhase2Activities:activities];
            return;
        }

        strongSelf->_activities = [activities copy];
        [strongSelf fetchType:MRMediaTypeShow
                nextWatchInfo:YES
                   completion:^(NSError *typeError) {
            if (typeError != nil) {
                [strongSelf finishWithError:typeError];
                return;
            }
            [strongSelf fetchType:MRMediaTypeMovie
                    nextWatchInfo:NO
                       completion:^(NSError *movieError) {
                if (movieError != nil) {
                    [strongSelf finishWithError:movieError];
                    return;
                }
                [strongSelf fetchType:MRMediaTypeAnime
                        nextWatchInfo:YES
                           completion:^(NSError *animeError) {
                    if (animeError != nil) {
                        [strongSelf finishWithError:animeError];
                        return;
                    }
                    [strongSelf finishSuccessfully];
                }];
            }];
        }];
    }];
}

- (void)fetchType:(MRMediaType)type
    nextWatchInfo:(BOOL)nextWatchInfo
       completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:MRWatchStatusNone
                                                  dateFrom:nil
                                                   idsOnly:NO
                                              nextWatchInfo:nextWatchInfo
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil && [MRError kindForError:error] == MRErrorKindTooLarge) {
            [strongSelf fetchBucketsForType:type
                             nextWatchInfo:nextWatchInfo
                                completion:completion];
            return;
        }
        if (error != nil) {
            completion(error);
            return;
        }
        NSError *parseError = nil;
        NSArray *items = [strongSelf itemsFromJSON:json type:type error:&parseError];
        if (items == nil) {
            completion(parseError);
            return;
        }
        [strongSelf appendItems:items];
        completion(nil);
    }];
}

- (void)fetchBucketsForType:(MRMediaType)type
              nextWatchInfo:(BOOL)nextWatchInfo
                 completion:(void (^)(NSError *error))completion {
    NSArray *statuses = MRSyncStatusesForType(type);
    [self fetchBucketAtIndex:0
                        type:type
                    statuses:statuses
               nextWatchInfo:nextWatchInfo
                  completion:completion];
}

- (void)fetchBucketAtIndex:(NSUInteger)index
                      type:(MRMediaType)type
                  statuses:(NSArray *)statuses
             nextWatchInfo:(BOOL)nextWatchInfo
                completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    if (index >= statuses.count) {
        completion(nil);
        return;
    }

    MRWatchStatus status = (MRWatchStatus)[[statuses objectAtIndex:index] integerValue];
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:status
                                                  dateFrom:nil
                                                   idsOnly:NO
                                              nextWatchInfo:nextWatchInfo
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            if ([MRError kindForError:error] == MRErrorKindTooLarge) {
                completion([MRError errorWithKind:MRErrorKindTooLarge]);
            } else {
                completion(error);
            }
            return;
        }
        NSError *parseError = nil;
        NSArray *items = [strongSelf itemsFromJSON:json type:type error:&parseError];
        if (items == nil) {
            completion(parseError);
            return;
        }
        [strongSelf appendItems:items];
        [strongSelf fetchBucketAtIndex:index + 1
                                   type:type
                               statuses:statuses
                          nextWatchInfo:nextWatchInfo
                             completion:completion];
    }];
}

- (NSArray *)itemsFromJSON:(NSDictionary *)json
                      type:(MRMediaType)type
                     error:(NSError **)error {
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return nil;
    }

    id entries = [json objectForKey:MRSyncTypeKey(type)];
    if (entries == nil ||
        (![entries isKindOfClass:[NSArray class]] && entries != [NSNull null])) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return nil;
    }
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        MRMediaItem *item = [MRMediaItem itemWithSyncDictionary:entry type:type];
        if (item.simklID <= 0) {
            continue;
        }
        [items addObject:item];
    }
    return items;
}

- (void)appendItems:(NSArray *)items {
    for (MRMediaItem *item in items) {
        NSString *identifier = [item identifier];
        if ([_itemIdentifiers containsObject:identifier]) {
            continue;
        }
        [_itemIdentifiers addObject:identifier];
        [_items addObject:item];
    }
}

- (NSArray *)phase2DomainsWithSavedActivities:(NSDictionary *)saved
                                    current:(NSDictionary *)current {
    NSArray *types = @[ @(MRMediaTypeShow), @(MRMediaTypeMovie), @(MRMediaTypeAnime) ];
    NSMutableArray *domains = [NSMutableArray array];
    for (NSNumber *number in types) {
        MRMediaType type = (MRMediaType)[number integerValue];
        NSString *key = MRSyncActivitiesDomainKey(type);
        NSDictionary *savedDomain = MRSyncActivitiesDomain(saved, key);
        NSDictionary *currentDomain = MRSyncActivitiesDomain(current, key);
        BOOL itemsMoved = MRSyncActivitiesStringsDiffer(
            [savedDomain objectForKey:@"all"], [currentDomain objectForKey:@"all"]);
        BOOL ratingsMoved = MRSyncActivitiesStringsDiffer(
            [savedDomain objectForKey:@"rated_at"],
            [currentDomain objectForKey:@"rated_at"]);
        BOOL removalsMoved = MRSyncActivitiesStringsDiffer(
            [savedDomain objectForKey:@"removed_from_list"],
            [currentDomain objectForKey:@"removed_from_list"]);
        if (!itemsMoved && !ratingsMoved && !removalsMoved) {
            continue;
        }
        [domains addObject:@{
            @"type": number,
            @"items": @(itemsMoved),
            @"ratings": @(ratingsMoved),
            @"removals": @(removalsMoved)
        }];
    }
    return domains;
}

- (void)processPhase2Activities:(NSDictionary *)activities {
    if (_finished || _cancelled) {
        return;
    }
    NSDictionary *saved = self.libraryStore.activities;
    NSString *savedAll = MRSyncActivitiesString([saved objectForKey:@"all"]);
    NSString *currentAll = MRSyncActivitiesString([activities objectForKey:@"all"]);
    if (savedAll.length == 0 || currentAll.length == 0) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindParse]];
        return;
    }

    if ([currentAll isEqualToString:savedAll]) {
        NSDate *now = [self.clock now];
        NSError *saveError = nil;
        if (![self.libraryStore updateLastSyncAt:now error:&saveError]) {
            [self finishWithError:saveError != nil
                                     ? saveError
                                     : [MRError errorWithKind:MRErrorKindUnknown]];
            return;
        }
        self.lastSyncAt = now;
        [self finishWithError:nil];
        return;
    }

    _savedActivitiesAll = [savedAll copy];
    _activities = [activities copy];
    NSArray *domains = [self phase2DomainsWithSavedActivities:saved
                                                      current:activities];
    __weak MRSyncEngine *weakSelf = self;
    [self fetchPhase2ItemsForDomains:domains
                               index:0
                          completion:^(NSError *itemsError) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        if (itemsError != nil) {
            [strongSelf finishWithError:itemsError];
            return;
        }
        [strongSelf fetchPhase2RemovalsForDomains:domains
                                            index:0
                                       completion:^(NSError *removalsError) {
            MRSyncEngine *removalSelf = weakSelf;
            if (removalSelf == nil || removalSelf->_finished) {
                return;
            }
            if (removalsError != nil) {
                [removalSelf finishWithError:removalsError];
                return;
            }
            [removalSelf fetchPhase2SettingsForActivities:activities
                                                completion:^(NSError *settingsError) {
                MRSyncEngine *settingsSelf = weakSelf;
                if (settingsSelf == nil || settingsSelf->_finished) {
                    return;
                }
                if (settingsError != nil) {
                    [settingsSelf finishWithError:settingsError];
                    return;
                }
                [settingsSelf fetchPhase2RatingsForDomains:domains
                                                     index:0
                                                completion:^(NSError *ratingsError) {
                    MRSyncEngine *innerSelf = weakSelf;
                    if (innerSelf == nil || innerSelf->_finished) {
                        return;
                    }
                    if (ratingsError != nil) {
                        [innerSelf finishWithError:ratingsError];
                        return;
                    }
                    [innerSelf finishPhase2WithActivities:activities];
                }];
            }];
        }];
    }];
}

- (BOOL)applyRemovalsJSON:(NSDictionary *)json
                     type:(MRMediaType)type
                    error:(NSError **)error {
    id entries = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        entries = [json objectForKey:MRSyncTypeKey(type)];
    }
    if (entries == [NSNull null]) {
        entries = @[];
    }
    if (![entries isKindOfClass:[NSArray class]]) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return NO;
    }

    NSMutableSet *remoteIdentifiers = [NSMutableSet set];
    for (id entry in (NSArray *)entries) {
        if ([entry isKindOfClass:[NSNumber class]] ||
            [entry isKindOfClass:[NSString class]]) {
            NSInteger simklID = [entry integerValue];
            if (simklID > 0) {
                [remoteIdentifiers addObject:
                    [NSString stringWithFormat:@"%ld:%ld", (long)type, (long)simklID]];
            }
            continue;
        }
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dictionary = (NSDictionary *)entry;
        NSInteger simklID = 0;
        NSDictionary *ids = [dictionary objectForKey:@"ids"];
        if ([ids isKindOfClass:[NSDictionary class]]) {
            id value = [ids objectForKey:@"simkl"];
            if (value == nil) {
                value = [ids objectForKey:@"simkl_id"];
            }
            simklID = [value integerValue];
        }
        if (simklID <= 0) {
            id value = [dictionary objectForKey:@"simkl_id"];
            if (value == nil && [dictionary objectForKey:@"id"] != nil) {
                value = [dictionary objectForKey:@"id"];
            }
            simklID = [value integerValue];
        }
        if (simklID > 0) {
            [remoteIdentifiers addObject:
                [NSString stringWithFormat:@"%ld:%ld", (long)type, (long)simklID]];
        }
    }

    for (MRMediaItem *item in self.libraryStore.items) {
        if (item.type != type) {
            continue;
        }
        if (![remoteIdentifiers containsObject:[item identifier]]) {
            [_removedIdentifiers addObject:[item identifier]];
        }
    }
    return YES;
}

- (void)fetchPhase2RemovalsForDomains:(NSArray *)domains
                               index:(NSUInteger)index
                          completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    if (index >= domains.count) {
        completion(nil);
        return;
    }

    NSDictionary *domain = [domains objectAtIndex:index];
    if (![[domain objectForKey:@"removals"] boolValue]) {
        [self fetchPhase2RemovalsForDomains:domains
                                      index:index + 1
                                 completion:completion];
        return;
    }

    MRMediaType type = (MRMediaType)[[domain objectForKey:@"type"] integerValue];
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:MRWatchStatusNone
                                                  dateFrom:nil
                                                   idsOnly:YES
                                              nextWatchInfo:NO
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            completion(error);
            return;
        }
        NSError *parseError = nil;
        if (![strongSelf applyRemovalsJSON:json type:type error:&parseError]) {
            completion(parseError);
            return;
        }
        [strongSelf fetchPhase2RemovalsForDomains:domains
                                           index:index + 1
                                      completion:completion];
    }];
}

- (void)fetchPhase2SettingsForActivities:(NSDictionary *)activities
                              completion:(void (^)(NSError *error))completion {
    NSDictionary *saved = self.libraryStore.activities;
    NSString *savedSettings = MRSyncActivitiesString(
        [MRSyncActivitiesDomain(saved, @"settings") objectForKey:@"all"]);
    NSString *currentSettings = MRSyncActivitiesString(
        [MRSyncActivitiesDomain(activities, @"settings") objectForKey:@"all"]);
    if (!MRSyncActivitiesStringsDiffer(savedSettings, currentSettings)) {
        completion(nil);
        return;
    }

    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchUserSettingsWithCompletion:
                    ^(NSDictionary *json, NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            completion(error);
            return;
        }
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion([MRError errorWithKind:MRErrorKindParse]);
            return;
        }
        MRUserProfile *profile = [MRUserProfile profileWithSettingsDictionary:json];
        if (profile.accountID > 0 &&
            strongSelf.libraryStore.profile.accountID > 0 &&
            profile.accountID != strongSelf.libraryStore.profile.accountID) {
            completion([MRError errorWithKind:MRErrorKindParse]);
            return;
        }
        strongSelf->_profile = profile;
        completion(nil);
    }];
}

- (void)fetchPhase2ItemsForDomains:(NSArray *)domains
                             index:(NSUInteger)index
                        completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    if (index >= domains.count) {
        completion(nil);
        return;
    }

    NSDictionary *domain = [domains objectAtIndex:index];
    if (![[domain objectForKey:@"items"] boolValue]) {
        [self fetchPhase2ItemsForDomains:domains index:index + 1 completion:completion];
        return;
    }

    MRMediaType type = (MRMediaType)[[domain objectForKey:@"type"] integerValue];
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:MRWatchStatusNone
                                                  dateFrom:_savedActivitiesAll
                                                   idsOnly:NO
                                              nextWatchInfo:type != MRMediaTypeMovie
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            completion(error);
            return;
        }
        // Simkl returns an empty object when a delta has no changed items.
        // That is a valid no-op, not a parse failure.
        if (json.count == 0) {
            [strongSelf fetchPhase2ItemsForDomains:domains
                                             index:index + 1
                                        completion:completion];
            return;
        }
        NSError *parseError = nil;
        NSArray *items = [strongSelf itemsFromJSON:json type:type error:&parseError];
        if (items == nil) {
            completion(parseError);
            return;
        }
        [strongSelf appendItems:items];
        [strongSelf fetchPhase2ItemsForDomains:domains
                                         index:index + 1
                                    completion:completion];
    }];
}

- (BOOL)applyRatingsJSON:(NSDictionary *)json
                    type:(MRMediaType)type
                   error:(NSError **)error {
    id entries = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        entries = json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        // An empty object means no rating changes in this delta.
        if (json.count == 0) {
            return YES;
        }
        entries = [json objectForKey:MRSyncTypeKey(type)];
    }
    if (![entries isKindOfClass:[NSArray class]]) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return NO;
    }

    for (id entry in (NSArray *)entries) {
        NSInteger simklID = 0;
        id rating = nil;
        if ([entry isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictionary = (NSDictionary *)entry;
            NSDictionary *ids = [dictionary objectForKey:@"ids"];
            if ([ids isKindOfClass:[NSDictionary class]]) {
                id value = [ids objectForKey:@"simkl"];
                if (value == nil) {
                    value = [ids objectForKey:@"simkl_id"];
                }
                simklID = [value integerValue];
            }
            if (simklID <= 0) {
                simklID = [[dictionary objectForKey:@"simkl_id"] integerValue];
            }
            if ([dictionary objectForKey:@"user_rating"] != nil) {
                rating = [dictionary objectForKey:@"user_rating"];
            }
        } else if ([entry isKindOfClass:[NSNumber class]] ||
                   [entry isKindOfClass:[NSString class]]) {
            simklID = [entry integerValue];
        }
        if (simklID <= 0 || rating == nil) {
            continue;
        }

        id value = [NSNull null];
        if ([rating isKindOfClass:[NSNumber class]]) {
            value = rating;
        } else if ([rating isKindOfClass:[NSString class]] && [rating length] > 0) {
            value = @([rating integerValue]);
        }
        NSString *identifier = [NSString stringWithFormat:@"%ld:%ld",
                                (long)type, (long)simklID];
        [_ratings setObject:value forKey:identifier];
    }
    return YES;
}

- (void)fetchPhase2RatingsForDomains:(NSArray *)domains
                               index:(NSUInteger)index
                          completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    if (index >= domains.count) {
        completion(nil);
        return;
    }

    NSDictionary *domain = [domains objectAtIndex:index];
    if (![[domain objectForKey:@"ratings"] boolValue]) {
        [self fetchPhase2RatingsForDomains:domains
                                     index:index + 1
                                completion:completion];
        return;
    }

    MRMediaType type = (MRMediaType)[[domain objectForKey:@"type"] integerValue];
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchRatingsForType:type
                                                 dateFrom:_savedActivitiesAll
                                               completion:^(NSDictionary *json,
                                                            NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            completion(error);
            return;
        }
        NSError *parseError = nil;
        if (![strongSelf applyRatingsJSON:json type:type error:&parseError]) {
            completion(parseError);
            return;
        }
        [strongSelf fetchPhase2RatingsForDomains:domains
                                           index:index + 1
                                      completion:completion];
    }];
}

- (void)finishPhase2WithActivities:(NSDictionary *)activities {
    NSError *saveError = nil;
    BOOL saved = [self.libraryStore mergeWithItems:_items
                                removedIdentifiers:_removedIdentifiers
                                           ratings:_ratings
                                        activities:activities
                                           profile:_profile
                                             error:&saveError];
    if (!saved) {
        [self finishWithError:saveError != nil
                                 ? saveError
                                 : [MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }
    self.lastSyncAt = [self.clock now];
    [self finishWithError:nil];
}

- (void)finishSuccessfully {
    if (_finished) {
        return;
    }
    NSError *saveError = nil;
    BOOL saved = [self.libraryStore replaceWithItems:_items
                                          activities:_activities
                                             profile:self.libraryStore.profile
                                               error:&saveError];
    if (!saved) {
        [self finishWithError:saveError != nil
                                 ? saveError
                                 : [MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    self.lastSyncAt = [self.clock now];
    self.lastSyncError = nil;
    [self finishWithError:nil];
}

- (void)finishCancelled {
    if (_finished) {
        return;
    }
    _finished = YES;
    _needsSync = NO;
    _currentTask = nil;
    self.lastSyncError = nil;
    self.syncing = NO;
    [self postStatusChange];
    [self deliverCompletionsWithError:[MRError errorWithKind:MRErrorKindCancelled]];
}

- (BOOL)beginQueuedPassIfNeededWithError:(NSError *)error {
    if (error != nil || _cancelled || !_needsSync) {
        _needsSync = NO;
        return NO;
    }

    _needsSync = NO;
    _finished = NO;
    _activities = nil;
    _savedActivitiesAll = nil;
    _items = [NSMutableArray array];
    _itemIdentifiers = [NSMutableSet set];
    _ratings = [NSMutableDictionary dictionary];
    _removedIdentifiers = [NSMutableArray array];
    _profile = nil;
    self.lastSyncAttemptAt = [self.clock now];
    [self fetchActivities];
    return YES;
}

- (void)finishWithError:(NSError *)error {
    if (_finished) {
        return;
    }
    _finished = YES;
    _currentTask = nil;
    self.lastSyncError = error;
    if ([self beginQueuedPassIfNeededWithError:error]) {
        return;
    }
    _needsSync = NO;
    self.syncing = NO;
    [self postStatusChange];
    [self deliverCompletionsWithError:error];
}

- (void)deliverCompletionsWithError:(NSError *)error {
    NSArray *blocks = [_completionBlocks copy];
    [_completionBlocks removeAllObjects];
    for (void (^completion)(NSError *) in blocks) {
        MRSyncDeliverOnMain(^{
            completion(error);
        });
    }
}

@end
