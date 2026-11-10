//
//  MRPreferencesStore.m
//  Marquee
//

#import "MRPreferencesStore.h"

#import "MRGenreChoice.h"
#import "MRHiddenTitle.h"
#import "MRMediaItem.h"
#import "MRStorage.h"

NSString *const MRPreferencesStoreErrorDomain = @"MRPreferencesStoreErrorDomain";
NSString *const MRPreferencesDidChangeNotification = @"MRPreferencesDidChangeNotification";

static const NSUInteger MRPreferencesMaximumManualGenres = 5;
static const NSUInteger MRPreferencesMaximumHiddenTitles = 200;
static const NSUInteger MRPreferencesMaximumSearchHistory = 8;

@interface MRPreferencesStore ()
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) NSMutableArray *mutableGenres;
@property (nonatomic, strong) NSMutableArray *mutableHidden;
@property (nonatomic, strong) NSMutableArray *mutableSearches;
@end

@implementation MRPreferencesStore

- (instancetype)initWithStorage:(MRStorage *)storage {
    self = [super init];
    if (self) {
        _storage = storage;
        _mutableGenres = [NSMutableArray array];
        _mutableHidden = [NSMutableArray array];
        _mutableSearches = [NSMutableArray array];
        [self load:NULL];
    }
    return self;
}

- (NSArray *)manualGenres {
    return [self.mutableGenres copy];
}

- (NSArray *)hiddenTitles {
    return [self.mutableHidden copy];
}

- (NSArray *)searchHistory {
    return [self.mutableSearches copy];
}

- (BOOL)load:(NSError **)error {
    [self.mutableGenres removeAllObjects];
    [self.mutableHidden removeAllObjects];
    [self.mutableSearches removeAllObjects];

    if (self.storage == nil) {
        return YES;
    }

    NSError *readError = nil;
    id json = [self.storage readJSONNamed:@"preferences" error:&readError];
    if (json == nil) {
        if (readError != nil && error != NULL) {
            *error = readError;
        }
        return readError == nil;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MRPreferencesStoreErrorDomain
                                         code:MRPreferencesStoreErrorInvalidFile
                                     userInfo:nil];
        }
        return NO;
    }

    NSDictionary *dictionary = (NSDictionary *)json;
    NSNumber *accountID = [dictionary objectForKey:@"accountID"];
    if ([accountID isKindOfClass:[NSNumber class]] &&
        [accountID integerValue] != self.storage.accountID) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MRPreferencesStoreErrorDomain
                                         code:MRPreferencesStoreErrorInvalidFile
                                     userInfo:nil];
        }
        return NO;
    }

    id genres = [dictionary objectForKey:@"manualGenres"];
    if ([genres isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)genres) {
            MRGenreChoice *choice =
                [MRGenreChoice choiceWithDictionaryRepresentation:entry];
            if (choice != nil && self.mutableGenres.count < MRPreferencesMaximumManualGenres) {
                [self.mutableGenres addObject:choice];
            }
        }
    }

    id hidden = [dictionary objectForKey:@"hiddenTitles"];
    if ([hidden isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)hidden) {
            MRHiddenTitle *item =
                [MRHiddenTitle hiddenTitleWithDictionaryRepresentation:entry];
            if (item != nil && self.mutableHidden.count < MRPreferencesMaximumHiddenTitles) {
                [self.mutableHidden addObject:item];
            }
        }
    }

    id searches = [dictionary objectForKey:@"searchHistory"];
    if ([searches isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)searches) {
            if ([entry isKindOfClass:[NSString class]] && [(NSString *)entry length] > 0) {
                [self.mutableSearches addObject:entry];
                if (self.mutableSearches.count >= MRPreferencesMaximumSearchHistory) {
                    break;
                }
            }
        }
    }
    return YES;
}

- (BOOL)save:(NSError **)error {
    if (self.storage == nil) {
        return YES;
    }

    NSMutableArray *genres = [NSMutableArray array];
    for (MRGenreChoice *choice in self.mutableGenres) {
        [genres addObject:[choice dictionaryRepresentation]];
    }
    NSMutableArray *hidden = [NSMutableArray array];
    for (MRHiddenTitle *item in self.mutableHidden) {
        [hidden addObject:[item dictionaryRepresentation]];
    }

    NSDictionary *json = @{
        @"schema": @1,
        @"accountID": @(self.storage.accountID),
        @"manualGenres": genres,
        @"hiddenTitles": hidden,
        @"searchHistory": [self.mutableSearches copy]
    };
    BOOL saved = [self.storage writeJSON:json named:@"preferences" error:error];
    if (!saved && error != NULL && *error == nil) {
        *error = [NSError errorWithDomain:MRPreferencesStoreErrorDomain
                                     code:MRPreferencesStoreErrorSaveFailed
                                 userInfo:nil];
    }
    return saved;
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MRPreferencesDidChangeNotification
                      object:self];
}

- (NSError *)errorWithCode:(MRPreferencesStoreErrorCode)code {
    return [NSError errorWithDomain:MRPreferencesStoreErrorDomain
                               code:code
                           userInfo:nil];
}

- (BOOL)hasManualGenre:(MRGenreChoice *)choice {
    if (choice == nil) {
        return NO;
    }
    return [self.mutableGenres containsObject:choice];
}

- (BOOL)addManualGenre:(MRGenreChoice *)choice error:(NSError **)error {
    if (choice == nil) {
        return NO;
    }
    if ([self hasManualGenre:choice]) {
        return YES;
    }
    if (self.mutableGenres.count >= MRPreferencesMaximumManualGenres) {
        if (error != NULL) {
            *error = [self errorWithCode:MRPreferencesStoreErrorManualGenreLimit];
        }
        return NO;
    }

    [self.mutableGenres addObject:choice];
    if (![self save:error]) {
        [self.mutableGenres removeLastObject];
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)removeManualGenre:(MRGenreChoice *)choice error:(NSError **)error {
    if (choice == nil || ![self hasManualGenre:choice]) {
        return YES;
    }
    [self.mutableGenres removeObject:choice];
    if (![self save:error]) {
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)setManualGenres:(NSArray *)choices error:(NSError **)error {
    if (![choices isKindOfClass:[NSArray class]]) {
        if (error != NULL) {
            *error = [self errorWithCode:MRPreferencesStoreErrorInvalidFile];
        }
        return NO;
    }

    NSMutableArray *validated = [NSMutableArray array];
    for (id entry in (NSArray *)choices) {
        if (![entry isKindOfClass:[MRGenreChoice class]]) {
            if (error != NULL) {
                *error = [self errorWithCode:MRPreferencesStoreErrorInvalidFile];
            }
            return NO;
        }
        if (![validated containsObject:entry]) {
            [validated addObject:entry];
        }
    }
    if (validated.count > MRPreferencesMaximumManualGenres) {
        if (error != NULL) {
            *error = [self errorWithCode:MRPreferencesStoreErrorManualGenreLimit];
        }
        return NO;
    }

    NSArray *previous = [self.mutableGenres copy];
    [self.mutableGenres setArray:validated];
    if (![self save:error]) {
        [self.mutableGenres setArray:previous];
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)isHiddenType:(MRMediaType)type simklID:(NSInteger)simklID {
    for (MRHiddenTitle *item in self.mutableHidden) {
        if ([item matchesType:type simklID:simklID]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hideTitle:(MRMediaItem *)item error:(NSError **)error {
    MRHiddenTitle *hidden = [MRHiddenTitle hiddenTitleWithItem:item];
    if (hidden == nil) {
        return NO;
    }
    if ([self isHiddenType:hidden.type simklID:hidden.simklID]) {
        return YES;
    }
    if (self.mutableHidden.count >= MRPreferencesMaximumHiddenTitles) {
        if (error != NULL) {
            *error = [self errorWithCode:MRPreferencesStoreErrorHiddenTitleLimit];
        }
        return NO;
    }

    [self.mutableHidden insertObject:hidden atIndex:0];
    if (![self save:error]) {
        [self.mutableHidden removeObjectAtIndex:0];
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)unhideTitleForType:(MRMediaType)type
                   simklID:(NSInteger)simklID
                     error:(NSError **)error {
    NSUInteger index = NSNotFound;
    for (NSUInteger cursor = 0; cursor < self.mutableHidden.count; cursor++) {
        MRHiddenTitle *item = [self.mutableHidden objectAtIndex:cursor];
        if ([item matchesType:type simklID:simklID]) {
            index = cursor;
            break;
        }
    }
    if (index == NSNotFound) {
        return YES;
    }

    MRHiddenTitle *removed = [self.mutableHidden objectAtIndex:index];
    [self.mutableHidden removeObjectAtIndex:index];
    if (![self save:error]) {
        [self.mutableHidden insertObject:removed atIndex:index];
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)recordSearch:(NSString *)query error:(NSError **)error {
    if (![query isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *trimmed =
        [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return YES;
    }

    NSUInteger existing = NSNotFound;
    for (NSUInteger index = 0; index < self.mutableSearches.count; index++) {
        NSString *entry = [self.mutableSearches objectAtIndex:index];
        if ([entry caseInsensitiveCompare:trimmed] == NSOrderedSame) {
            existing = index;
            break;
        }
    }
    NSString *previous = existing != NSNotFound
        ? [self.mutableSearches objectAtIndex:existing]
        : nil;
    if (existing != NSNotFound) {
        [self.mutableSearches removeObjectAtIndex:existing];
    }
    [self.mutableSearches insertObject:trimmed atIndex:0];
    while (self.mutableSearches.count > MRPreferencesMaximumSearchHistory) {
        [self.mutableSearches removeLastObject];
    }

    if (![self save:error]) {
        if (existing != NSNotFound) {
            [self.mutableSearches removeObject:trimmed];
            [self.mutableSearches insertObject:previous ?: trimmed atIndex:existing];
        }
        return NO;
    }
    [self postChange];
    return YES;
}

- (BOOL)clearSearchHistory:(NSError **)error {
    NSArray *previous = [self.mutableSearches copy];
    [self.mutableSearches removeAllObjects];
    if (![self save:error]) {
        [self.mutableSearches setArray:previous];
        return NO;
    }
    [self postChange];
    return YES;
}

@end
