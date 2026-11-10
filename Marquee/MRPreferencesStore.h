//
//  MRPreferencesStore.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

@class MRGenreChoice;
@class MRHiddenTitle;
@class MRMediaItem;
@class MRStorage;

extern NSString *const MRPreferencesStoreErrorDomain;
extern NSString *const MRPreferencesDidChangeNotification;

typedef NS_ENUM(NSInteger, MRPreferencesStoreErrorCode) {
    MRPreferencesStoreErrorManualGenreLimit = 1,
    MRPreferencesStoreErrorHiddenTitleLimit = 2,
    MRPreferencesStoreErrorInvalidFile = 3,
    MRPreferencesStoreErrorSaveFailed = 4
};

// Per-account manual genres, hidden titles, and recent searches, persisted to
// preferences.json. Mutations save immediately and post
// MRPreferencesDidChangeNotification on the main thread.
@interface MRPreferencesStore : NSObject

@property (nonatomic, copy, readonly) NSArray *manualGenres;
@property (nonatomic, copy, readonly) NSArray *hiddenTitles;
@property (nonatomic, copy, readonly) NSArray *searchHistory;

- (instancetype)initWithStorage:(MRStorage *)storage;

- (BOOL)load:(NSError **)error;
- (BOOL)save:(NSError **)error;

- (BOOL)addManualGenre:(MRGenreChoice *)choice error:(NSError **)error;
- (BOOL)removeManualGenre:(MRGenreChoice *)choice error:(NSError **)error;
// Atomically replaces the picker's selections. The array is deduplicated; more
// than five choices returns MRPreferencesStoreErrorManualGenreLimit and leaves
// the previous selections untouched.
- (BOOL)setManualGenres:(NSArray *)choices error:(NSError **)error;
- (BOOL)hasManualGenre:(MRGenreChoice *)choice;

- (BOOL)isHiddenType:(MRMediaType)type simklID:(NSInteger)simklID;
- (BOOL)hideTitle:(MRMediaItem *)item error:(NSError **)error;
- (BOOL)unhideTitleForType:(MRMediaType)type
                   simklID:(NSInteger)simklID
                     error:(NSError **)error;

- (BOOL)recordSearch:(NSString *)query error:(NSError **)error;
- (BOOL)clearSearchHistory:(NSError **)error;

@end
