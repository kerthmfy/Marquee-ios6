//
//  MRLibraryStore.m
//  Marquee
//

#import "MRLibraryStore.h"
#import "MRDate.h"
#import "MRError.h"
#import "MRMediaItem.h"
#import "MRStorage.h"
#import "MRUserProfile.h"

NSString *const MRLibraryDidChangeNotification = @"MRLibraryDidChangeNotification";
NSString *const MRLibraryStoreErrorDomain = @"MRLibraryStoreErrorDomain";

static const NSInteger MRLibraryStoreSchema = 1;

static NSError *MRLibraryRepairError(NSString *description, NSError *underlying) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] =
        description.length > 0 ? description : @"The library snapshot needs repair.";
    if (underlying != nil) {
        userInfo[NSUnderlyingErrorKey] = underlying;
    }
    return [NSError errorWithDomain:MRLibraryStoreErrorDomain
                               code:MRLibraryStoreErrorNeedsRepair
                           userInfo:userInfo];
}

static void MRLibraryPostChange(void) {
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MRLibraryDidChangeNotification
                          object:nil];
    };
    if ([NSThread isMainThread]) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

static NSInteger MRLibraryIntegerValue(id value, NSInteger fallback) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value integerValue];
    }
    return fallback;
}

static NSDictionary *MRLibraryDictionaryValue(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

static NSArray *MRLibraryArrayValue(id value) {
    return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : nil;
}

static NSDate *MRLibraryDateValue(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [MRDate dateFromISOString:(NSString *)value];
}

@interface MRLibraryStore ()
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, strong) MRUserProfile *profile;
@property (nonatomic, copy) NSDictionary *activities;
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, strong) NSDate *savedAt;
@property (nonatomic, strong) NSDate *lastSyncAt;
@property (nonatomic, strong) NSDate *lastFullSyncAt;
@property (nonatomic, assign) BOOL hasSnapshot;
@end

@implementation MRLibraryStore {
    NSMutableArray *_mutableItems;
    NSMutableDictionary *_mutableItemsByIdentifier;
}

- (instancetype)initWithStorage:(MRStorage *)storage {
    self = [super init];
    if (self) {
        _storage = storage;
        _mutableItems = [NSMutableArray array];
        _mutableItemsByIdentifier = [NSMutableDictionary dictionary];
        _activities = @{};
        _generation = 0;
        _hasSnapshot = NO;
    }
    return self;
}

#pragma mark - Loading

- (void)resetMemory {
    [_mutableItems removeAllObjects];
    [_mutableItemsByIdentifier removeAllObjects];
    self.items = @[];
    self.profile = nil;
    self.activities = @{};
    self.generation = 0;
    self.savedAt = nil;
    self.lastSyncAt = nil;
    self.lastFullSyncAt = nil;
    self.hasSnapshot = NO;
}

- (BOOL)validateSnapshotLibrary:(NSDictionary *)library
                           state:(NSDictionary *)state
                           error:(NSError **)error {
    NSInteger expectedAccountID = self.storage.accountID;
    NSInteger libraryAccountID = MRLibraryIntegerValue([library objectForKey:@"accountID"], 0);
    NSInteger stateAccountID = MRLibraryIntegerValue([state objectForKey:@"accountID"], 0);
    if (libraryAccountID != stateAccountID ||
        (expectedAccountID != 0 && libraryAccountID != expectedAccountID)) {
        if (error != NULL) {
            *error = MRLibraryRepairError(@"The library snapshot belongs to another account.",
                                          nil);
        }
        return NO;
    }

    NSInteger librarySchema = MRLibraryIntegerValue([library objectForKey:@"schema"], 0);
    NSInteger stateSchema = MRLibraryIntegerValue([state objectForKey:@"schema"], 0);
    if (librarySchema != MRLibraryStoreSchema || stateSchema != MRLibraryStoreSchema) {
        if (error != NULL) {
            *error = MRLibraryRepairError(@"The library snapshot uses an unsupported schema.",
                                          nil);
        }
        return NO;
    }

    NSInteger libraryGeneration =
        MRLibraryIntegerValue([library objectForKey:@"generation"], -1);
    NSInteger stateGeneration =
        MRLibraryIntegerValue([state objectForKey:@"generation"], -2);
    if (libraryGeneration < 0 || libraryGeneration != stateGeneration) {
        if (error != NULL) {
            *error = MRLibraryRepairError(@"The library and state generations differ.", nil);
        }
        return NO;
    }

    if (MRLibraryArrayValue([library objectForKey:@"items"]) == nil) {
        if (error != NULL) {
            *error = MRLibraryRepairError(@"The library snapshot has no items array.", nil);
        }
        return NO;
    }
    return YES;
}

- (BOOL)load:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    [self resetMemory];

    NSError *libraryReadError = nil;
    id libraryObject = [self.storage readJSONNamed:@"library.json" error:&libraryReadError];
    NSError *stateReadError = nil;
    id stateObject = [self.storage readJSONNamed:@"state.json" error:&stateReadError];

    NSDictionary *library = MRLibraryDictionaryValue(libraryObject);
    NSDictionary *state = MRLibraryDictionaryValue(stateObject);
    if (library == nil || state == nil) {
        NSError *underlying = libraryReadError != nil ? libraryReadError : stateReadError;
        if (error != NULL) {
            *error = MRLibraryRepairError(@"No trustworthy library snapshot is available.",
                                          underlying);
        }
        return NO;
    }

    NSError *validationError = nil;
    if (![self validateSnapshotLibrary:library state:state error:&validationError]) {
        if (error != NULL) {
            *error = validationError;
        }
        return NO;
    }

    NSMutableArray *loadedItems = [NSMutableArray array];
    NSMutableDictionary *loadedByIdentifier = [NSMutableDictionary dictionary];
    for (id entry in MRLibraryArrayValue([library objectForKey:@"items"])) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        MRMediaItem *item = [MRMediaItem itemWithDictionaryRepresentation:entry];
        if (item.simklID <= 0) {
            continue;
        }
        NSString *identifier = [item identifier];
        if ([loadedByIdentifier objectForKey:identifier] != nil) {
            continue;
        }
        [loadedItems addObject:item];
        [loadedByIdentifier setObject:item forKey:identifier];
    }

    NSDictionary *storedProfile = MRLibraryDictionaryValue([state objectForKey:@"profile"]);
    self.profile = storedProfile != nil
        ? [MRUserProfile profileWithDictionaryRepresentation:storedProfile]
        : nil;
    NSDictionary *storedActivities = MRLibraryDictionaryValue([state objectForKey:@"activities"]);
    self.activities = storedActivities != nil ? [storedActivities copy] : @{};
    self.generation = MRLibraryIntegerValue([state objectForKey:@"generation"], 0);
    self.savedAt = MRLibraryDateValue([state objectForKey:@"savedAt"]);
    self.lastSyncAt = MRLibraryDateValue([state objectForKey:@"lastSyncAt"]);
    self.lastFullSyncAt = MRLibraryDateValue([state objectForKey:@"lastFullSyncAt"]);

    [_mutableItems setArray:loadedItems];
    [_mutableItemsByIdentifier setDictionary:loadedByIdentifier];
    self.items = [loadedItems copy];
    self.hasSnapshot = YES;
    return YES;
}

#pragma mark - Persistence

- (NSDictionary *)libraryDictionaryWithItems:(NSArray *)items
                                  generation:(NSInteger)generation
                                     savedAt:(NSDate *)savedAt {
    NSMutableArray *representations = [NSMutableArray arrayWithCapacity:items.count];
    for (MRMediaItem *item in items) {
        [representations addObject:[item dictionaryRepresentation]];
    }
    return @{
        @"schema": @(MRLibraryStoreSchema),
        @"accountID": @(self.storage.accountID),
        @"generation": @(generation),
        @"savedAt": [MRDate isoStringFromDate:savedAt] ?: @"",
        @"items": representations
    };
}

- (NSDictionary *)stateDictionaryWithGeneration:(NSInteger)generation
                                        savedAt:(NSDate *)savedAt
                                     activities:(NSDictionary *)activities
                                        profile:(MRUserProfile *)profile
                                     lastSyncAt:(NSDate *)lastSyncAt
                                 lastFullSyncAt:(NSDate *)lastFullSyncAt {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"schema"] = @(MRLibraryStoreSchema);
    state[@"accountID"] = @(self.storage.accountID);
    state[@"generation"] = @(generation);
    state[@"savedAt"] = [MRDate isoStringFromDate:savedAt] ?: @"";
    state[@"activities"] = activities ?: @{};
    if (profile != nil) {
        state[@"profile"] = [profile dictionaryRepresentation];
    }
    if (lastSyncAt != nil) {
        state[@"lastSyncAt"] = [MRDate isoStringFromDate:lastSyncAt];
    }
    if (lastFullSyncAt != nil) {
        state[@"lastFullSyncAt"] = [MRDate isoStringFromDate:lastFullSyncAt];
    }
    return state;
}

- (BOOL)persistItems:(NSArray *)items
         activities:(NSDictionary *)activities
            profile:(MRUserProfile *)profile
         generation:(NSInteger)generation
            savedAt:(NSDate *)savedAt
         lastSyncAt:(NSDate *)lastSyncAt
     lastFullSyncAt:(NSDate *)lastFullSyncAt
              error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    NSDictionary *library = [self libraryDictionaryWithItems:items
                                                  generation:generation
                                                     savedAt:savedAt];
    NSDictionary *state = [self stateDictionaryWithGeneration:generation
                                                      savedAt:savedAt
                                                   activities:activities
                                                      profile:profile
                                                   lastSyncAt:lastSyncAt
                                               lastFullSyncAt:lastFullSyncAt];

    NSError *writeError = nil;
    if (![self.storage writeJSON:library named:@"library.json" error:&writeError]) {
        if (error != NULL) {
            *error = writeError;
        }
        return NO;
    }
    if (![self.storage writeJSON:state named:@"state.json" error:&writeError]) {
        if (error != NULL) {
            *error = writeError;
        }
        return NO;
    }
    return YES;
}

- (void)commitItems:(NSArray *)items
         activities:(NSDictionary *)activities
            profile:(MRUserProfile *)profile
         generation:(NSInteger)generation
            savedAt:(NSDate *)savedAt
         lastSyncAt:(NSDate *)lastSyncAt
     lastFullSyncAt:(NSDate *)lastFullSyncAt {
    [_mutableItems setArray:items];
    [_mutableItemsByIdentifier removeAllObjects];
    for (MRMediaItem *item in items) {
        [_mutableItemsByIdentifier setObject:item forKey:[item identifier]];
    }
    self.items = [items copy];
    self.activities = activities != nil ? [activities copy] : @{};
    if (profile != nil) {
        self.profile = profile;
    }
    self.generation = generation;
    self.savedAt = savedAt;
    self.lastSyncAt = lastSyncAt;
    self.lastFullSyncAt = lastFullSyncAt;
    self.hasSnapshot = YES;
    MRLibraryPostChange();
}

- (BOOL)storeStateWithGeneration:(NSInteger)generation
                         savedAt:(NSDate *)savedAt
                      activities:(NSDictionary *)activities
                         profile:(MRUserProfile *)profile
                      lastSyncAt:(NSDate *)lastSyncAt
                  lastFullSyncAt:(NSDate *)lastFullSyncAt
                           error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    NSDictionary *state = [self stateDictionaryWithGeneration:generation
                                                      savedAt:savedAt
                                                   activities:activities
                                                      profile:profile
                                                   lastSyncAt:lastSyncAt
                                               lastFullSyncAt:lastFullSyncAt];
    NSError *writeError = nil;
    if (![self.storage writeJSON:state named:@"state.json" error:&writeError]) {
        if (error != NULL) {
            *error = writeError;
        }
        return NO;
    }
    return YES;
}

#pragma mark - Replacement and merge

- (NSArray *)deduplicatedItems:(NSArray *)items {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id entry in items) {
        if (![entry isKindOfClass:[MRMediaItem class]]) {
            continue;
        }
        MRMediaItem *item = (MRMediaItem *)entry;
        if (item.simklID <= 0) {
            continue;
        }
        NSString *identifier = [item identifier];
        if ([seen containsObject:identifier]) {
            continue;
        }
        [seen addObject:identifier];
        [result addObject:item];
    }
    return result;
}

- (BOOL)replaceWithItems:(NSArray *)items
              activities:(NSDictionary *)activities
                 profile:(MRUserProfile *)profile
                   error:(NSError **)error {
    NSArray *deduplicated = [self deduplicatedItems:items];
    NSInteger generation = self.generation + 1;
    NSDate *now = [NSDate date];
    MRUserProfile *nextProfile = profile != nil ? profile : self.profile;
    NSDictionary *nextActivities = activities != nil ? activities : @{};

    if (![self persistItems:deduplicated
                 activities:nextActivities
                    profile:nextProfile
                 generation:generation
                    savedAt:now
                 lastSyncAt:now
             lastFullSyncAt:now
                      error:error]) {
        return NO;
    }
    [self commitItems:deduplicated
           activities:nextActivities
              profile:nextProfile
           generation:generation
              savedAt:now
           lastSyncAt:now
       lastFullSyncAt:now];
    return YES;
}

- (NSArray *)copiedItems:(NSArray *)items {
    NSMutableArray *copies = [NSMutableArray arrayWithCapacity:items.count];
    for (MRMediaItem *item in items) {
        [copies addObject:[item copy]];
    }
    return copies;
}

- (NSArray *)itemsByApplyingItems:(NSArray *)items
                       removals:(NSArray *)removedIdentifiers {
    NSMutableArray *merged = [NSMutableArray arrayWithArray:[self copiedItems:_mutableItems]];
    NSMutableDictionary *indexes = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < merged.count; index += 1) {
        MRMediaItem *item = [merged objectAtIndex:index];
        [indexes setObject:@(index) forKey:[item identifier]];
    }

    for (id entry in items) {
        if (![entry isKindOfClass:[MRMediaItem class]]) {
            continue;
        }
        MRMediaItem *item = (MRMediaItem *)entry;
        if (item.simklID <= 0) {
            continue;
        }
        NSString *identifier = [item identifier];
        NSNumber *index = [indexes objectForKey:identifier];
        if (index != nil) {
            [merged replaceObjectAtIndex:[index unsignedIntegerValue] withObject:item];
        } else {
            [indexes setObject:@(merged.count) forKey:identifier];
            [merged addObject:item];
        }
    }

    NSMutableSet *removed = [NSMutableSet set];
    for (id identifier in removedIdentifiers) {
        if ([identifier isKindOfClass:[NSString class]]) {
            [removed addObject:identifier];
        }
    }
    if (removed.count > 0) {
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:merged.count];
        for (MRMediaItem *item in merged) {
            if (![removed containsObject:[item identifier]]) {
                [kept addObject:item];
            }
        }
        merged = kept;
    }
    return merged;
}

- (BOOL)mergeWithItems:(NSArray *)items
    removedIdentifiers:(NSArray *)removedIdentifiers
               ratings:(NSDictionary *)ratings
            activities:(NSDictionary *)activities
               profile:(MRUserProfile *)profile
                 error:(NSError **)error {
    NSArray *applied = [self itemsByApplyingItems:items removals:removedIdentifiers];
    NSMutableArray *merged = [NSMutableArray arrayWithArray:applied];
    NSMutableDictionary *mergedByIdentifier = [NSMutableDictionary dictionary];
    for (MRMediaItem *item in merged) {
        [mergedByIdentifier setObject:item forKey:[item identifier]];
    }

    if ([ratings isKindOfClass:[NSDictionary class]]) {
        for (id key in ratings) {
            if (![key isKindOfClass:[NSString class]]) {
                continue;
            }
            MRMediaItem *item = [mergedByIdentifier objectForKey:key];
            if (item == nil) {
                continue;
            }
            id value = [ratings objectForKey:key];
            NSInteger rating = 0;
            if ([value isKindOfClass:[NSNumber class]]) {
                rating = [value integerValue];
            }
            if (rating < 0) {
                rating = 0;
            }
            if (rating > 10) {
                rating = 10;
            }
            item.userRating = rating;
        }
    }

    NSInteger generation = self.generation + 1;
    NSDate *now = [NSDate date];
    MRUserProfile *nextProfile = profile != nil ? profile : self.profile;
    NSDictionary *nextActivities = activities != nil ? activities : @{};

    if (![self persistItems:merged
                 activities:nextActivities
                    profile:nextProfile
                 generation:generation
                    savedAt:now
                 lastSyncAt:now
             lastFullSyncAt:self.lastFullSyncAt
                      error:error]) {
        return NO;
    }
    [self commitItems:merged
           activities:nextActivities
              profile:nextProfile
           generation:generation
              savedAt:now
           lastSyncAt:now
       lastFullSyncAt:self.lastFullSyncAt];
    return YES;
}

- (BOOL)updateProfile:(MRUserProfile *)profile error:(NSError **)error {
    if (profile == nil) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindUnknown];
        }
        return NO;
    }

    if (!self.hasSnapshot) {
        // The initial sync will persist the profile along with the first
        // library snapshot. Do not create a state-only file pair.
        self.profile = profile;
        if (error != NULL) {
            *error = nil;
        }
        MRLibraryPostChange();
        return YES;
    }

    NSDate *now = [NSDate date];
    if (![self storeStateWithGeneration:self.generation
                                savedAt:now
                             activities:self.activities
                                profile:profile
                             lastSyncAt:self.lastSyncAt
                         lastFullSyncAt:self.lastFullSyncAt
                                  error:error]) {
        return NO;
    }
    self.profile = profile;
    self.savedAt = now;
    MRLibraryPostChange();
    return YES;
}

#pragma mark - Reads

- (MRMediaItem *)itemForType:(MRMediaType)type simklID:(NSInteger)simklID {
    NSString *identifier = [NSString stringWithFormat:@"%ld:%ld", (long)type, (long)simklID];
    return [_mutableItemsByIdentifier objectForKey:identifier];
}

- (NSArray *)itemsForType:(MRMediaType)type status:(MRWatchStatus)status {
    NSMutableArray *matching = [NSMutableArray array];
    for (MRMediaItem *item in _mutableItems) {
        if (item.type != type) {
            continue;
        }
        if (status != MRWatchStatusNone && item.watchStatus != status) {
            continue;
        }
        [matching addObject:item];
    }
    return matching;
}

- (NSDictionary *)countsByStatusForType:(MRMediaType)type {
    NSArray *statuses = @[
        @(MRWatchStatusWatching), @(MRWatchStatusPlanToWatch),
        @(MRWatchStatusCompleted), @(MRWatchStatusHold), @(MRWatchStatusDropped)
    ];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSNumber *statusNumber in statuses) {
        [counts setObject:@0 forKey:MRWatchStatusKey((MRWatchStatus)[statusNumber integerValue])];
    }
    for (MRMediaItem *item in _mutableItems) {
        if (item.type != type || item.watchStatus == MRWatchStatusNone) {
            continue;
        }
        NSString *key = MRWatchStatusKey(item.watchStatus);
        NSNumber *current = [counts objectForKey:key];
        if (current != nil) {
            [counts setObject:@([current integerValue] + 1) forKey:key];
        }
    }
    return counts;
}

#pragma mark - Mutators

- (BOOL)persistChangedItems:(NSArray *)items error:(NSError **)error {
    NSInteger generation = self.generation + 1;
    NSDate *now = [NSDate date];
    if (![self persistItems:items
                 activities:self.activities
                    profile:self.profile
                 generation:generation
                    savedAt:now
                 lastSyncAt:self.lastSyncAt
             lastFullSyncAt:self.lastFullSyncAt
                      error:error]) {
        return NO;
    }
    [self commitItems:items
           activities:self.activities
              profile:self.profile
           generation:generation
              savedAt:now
           lastSyncAt:self.lastSyncAt
       lastFullSyncAt:self.lastFullSyncAt];
    return YES;
}

- (BOOL)updateItem:(MRMediaItem *)item error:(NSError **)error {
    if (item == nil || item.simklID <= 0) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindNotFound];
        }
        return NO;
    }
    NSMutableArray *updated = [NSMutableArray arrayWithArray:[self copiedItems:_mutableItems]];
    MRMediaItem *target = nil;
    for (MRMediaItem *candidate in updated) {
        if (candidate.type == item.type && candidate.simklID == item.simklID) {
            target = candidate;
            break;
        }
    }
    if (target == nil) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindNotFound];
        }
        return NO;
    }
    NSUInteger index = [updated indexOfObjectIdenticalTo:target];
    [updated replaceObjectAtIndex:index withObject:[item copy]];
    return [self persistChangedItems:updated error:error];
}

- (BOOL)applyResolvedStatus:(MRWatchStatus)status
                forItemType:(MRMediaType)type
                    simklID:(NSInteger)simklID
                      error:(NSError **)error {
    NSArray *updated = [self copiedItems:_mutableItems];
    MRMediaItem *target = nil;
    for (MRMediaItem *item in updated) {
        if (item.type == type && item.simklID == simklID) {
            target = item;
            break;
        }
    }
    if (target == nil) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindNotFound];
        }
        return NO;
    }
    target.watchStatus = status;
    return [self persistChangedItems:updated error:error];
}

- (BOOL)applyUserRating:(NSInteger)rating
            forItemType:(MRMediaType)type
                simklID:(NSInteger)simklID
                  error:(NSError **)error {
    NSArray *updated = [self copiedItems:_mutableItems];
    MRMediaItem *target = nil;
    for (MRMediaItem *item in updated) {
        if (item.type == type && item.simklID == simklID) {
            target = item;
            break;
        }
    }
    if (target == nil) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindNotFound];
        }
        return NO;
    }
    if (rating < 0) {
        rating = 0;
    }
    if (rating > 10) {
        rating = 10;
    }
    target.userRating = rating;
    return [self persistChangedItems:updated error:error];
}

- (BOOL)removeItemForType:(MRMediaType)type
                  simklID:(NSInteger)simklID
                    error:(NSError **)error {
    MRMediaItem *item = [self itemForType:type simklID:simklID];
    if (item == nil) {
        if (error != NULL) {
            *error = nil;
        }
        return YES;
    }

    NSMutableArray *remaining = [NSMutableArray arrayWithCapacity:_mutableItems.count];
    for (MRMediaItem *candidate in _mutableItems) {
        if ([candidate.identifier isEqualToString:item.identifier]) {
            continue;
        }
        [remaining addObject:candidate];
    }
    return [self persistChangedItems:remaining error:error];
}

@end
