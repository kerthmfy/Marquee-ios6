//
//  MRLibraryStore.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

@class MRMediaItem;
@class MRStorage;
@class MRUserProfile;

extern NSString *const MRLibraryDidChangeNotification;
extern NSString *const MRLibraryStoreErrorDomain;

typedef NS_ENUM(NSInteger, MRLibraryStoreErrorCode) {
    MRLibraryStoreErrorNeedsRepair = 1
};

// The normalized account library plus the matching state.json metadata. All
// mutators write library.json first, then state.json, with one generation, and
// only update memory and post MRLibraryDidChangeNotification after both writes
// succeed. The notification is delivered on the main thread.
@interface MRLibraryStore : NSObject

@property (nonatomic, copy, readonly) NSArray *items;
@property (nonatomic, strong, readonly) MRUserProfile *profile;
@property (nonatomic, copy, readonly) NSDictionary *activities;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, strong, readonly) NSDate *savedAt;
@property (nonatomic, strong, readonly) NSDate *lastSyncAt;
@property (nonatomic, strong, readonly) NSDate *lastFullSyncAt;

- (instancetype)initWithStorage:(MRStorage *)storage;

// Reads library.json and state.json. A missing snapshot, corrupt file, schema
// mismatch, account mismatch, or generation mismatch leaves the store empty and
// returns NO with MRLibraryStoreErrorNeedsRepair.
- (BOOL)load:(NSError **)error;

// A full-sync replacement. Increments the generation and stamps both sync
// dates. Passing a nil profile preserves the current profile.
- (BOOL)replaceWithItems:(NSArray *)items
              activities:(NSDictionary *)activities
                 profile:(MRUserProfile *)profile
                   error:(NSError **)error;

// A phase-2 merge. Items replace by identifier, removedIdentifiers are removed,
// and ratings maps "<type>:<simklID>" identifiers to NSNumber ratings (NSNull or
// 0 clears). Passing a nil profile preserves the current profile. Increments
// the generation and stamps lastSyncAt but not lastFullSyncAt.
- (BOOL)mergeWithItems:(NSArray *)items
    removedIdentifiers:(NSArray *)removedIdentifiers
               ratings:(NSDictionary *)ratings
            activities:(NSDictionary *)activities
               profile:(MRUserProfile *)profile
                 error:(NSError **)error;

// Saves a refreshed profile without touching the library or generation.
- (BOOL)updateProfile:(MRUserProfile *)profile error:(NSError **)error;

- (MRMediaItem *)itemForType:(MRMediaType)type simklID:(NSInteger)simklID;
- (NSArray *)itemsForType:(MRMediaType)type status:(MRWatchStatus)status;
- (NSDictionary *)countsByStatusForType:(MRMediaType)type;

- (BOOL)applyResolvedStatus:(MRWatchStatus)status
                forItemType:(MRMediaType)type
                    simklID:(NSInteger)simklID
                      error:(NSError **)error;

- (BOOL)applyUserRating:(NSInteger)rating
            forItemType:(MRMediaType)type
                simklID:(NSInteger)simklID
                  error:(NSError **)error;

- (BOOL)removeItemForType:(MRMediaType)type
                  simklID:(NSInteger)simklID
                    error:(NSError **)error;

@end
