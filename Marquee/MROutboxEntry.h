//
//  MROutboxEntry.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

@class MRMediaItem;

typedef NS_ENUM(NSInteger, MROutboxEntryKind) {
    MROutboxEntryKindStatus = 0,
    MROutboxEntryKindHistoryWhole,
    MROutboxEntryKindHistoryEpisode,
    MROutboxEntryKindRating,
    MROutboxEntryKindRatingRemove,
    MROutboxEntryKindRemove
};

// One persisted write. The entry carries the item identity plus the fields
// needed to build the Simkl request without consulting the library snapshot.
// previousStatus/previousRating exist for a future undo path; v1 only uses them
// for persistence and diagnostics.
@interface MROutboxEntry : NSObject

@property (nonatomic, copy) NSString *entryID;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) MROutboxEntryKind kind;
@property (nonatomic, assign) MRMediaType type;
@property (nonatomic, assign) NSInteger simklID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger year;
@property (nonatomic, copy) NSDictionary *externalIDs;
@property (nonatomic, assign) MRWatchStatus status;
@property (nonatomic, assign) NSInteger rating;
@property (nonatomic, assign) NSInteger season;
@property (nonatomic, assign) NSInteger episode;
@property (nonatomic, assign) MRWatchStatus previousStatus;
@property (nonatomic, assign) NSInteger previousRating;
@property (nonatomic, assign) NSInteger attempts;

+ (instancetype)statusEntryWithItem:(MRMediaItem *)item
                              status:(MRWatchStatus)status
                      previousStatus:(MRWatchStatus)previousStatus;

+ (instancetype)historyWholeEntryWithItem:(MRMediaItem *)item
                                   status:(MRWatchStatus)status;

+ (instancetype)historyEpisodeEntryWithItem:(MRMediaItem *)item
                                     season:(NSInteger)season
                                    episode:(NSInteger)episode;

+ (instancetype)ratingEntryWithItem:(MRMediaItem *)item
                             rating:(NSInteger)rating
                     previousRating:(NSInteger)previousRating;

+ (instancetype)ratingRemoveEntryWithItem:(MRMediaItem *)item
                            previousRating:(NSInteger)previousRating;

+ (instancetype)removeEntryWithItem:(MRMediaItem *)item
                     previousStatus:(MRWatchStatus)previousStatus
                     previousRating:(NSInteger)previousRating;

+ (NSString *)kindKeyForKind:(MROutboxEntryKind)kind;
+ (MROutboxEntryKind)kindForKindKey:(NSString *)key;
+ (NSString *)typeKeyForType:(MRMediaType)type;
+ (MRMediaType)typeForTypeKey:(NSString *)key;

- (instancetype)initWithDictionaryRepresentation:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

- (NSString *)itemIdentifier;
- (BOOL)targetsSameItemAsEntry:(MROutboxEntry *)other;

@end
