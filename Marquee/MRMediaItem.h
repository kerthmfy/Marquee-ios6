//
//  MRMediaItem.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

// A normalized Simkl movie, show, or anime. Constructors accept the different
// dictionary shapes used by the sync, search, trending, and detail endpoints.
@interface MRMediaItem : NSObject <NSCopying>

@property (nonatomic, assign) NSInteger simklID;
@property (nonatomic, copy) NSString *slug;
@property (nonatomic, assign) MRMediaType type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger year;
@property (nonatomic, copy) NSString *poster;
@property (nonatomic, copy) NSString *fanart;
@property (nonatomic, copy) NSArray *genres;
@property (nonatomic, assign) NSInteger runtime;
@property (nonatomic, copy) NSDictionary *ratings;
@property (nonatomic, copy) NSDictionary *externalIDs;
@property (nonatomic, copy) NSString *overview;
@property (nonatomic, copy) NSString *network;
@property (nonatomic, copy) NSString *country;
@property (nonatomic, copy) NSString *releaseDate;
@property (nonatomic, copy) NSString *airStatus;

@property (nonatomic, assign) MRWatchStatus watchStatus;
@property (nonatomic, assign) NSInteger userRating;
@property (nonatomic, strong) NSDate *userRatedAt;
@property (nonatomic, strong) NSDate *lastWatchedAt;
@property (nonatomic, strong) NSDate *addedToWatchlistAt;
@property (nonatomic, assign) NSInteger watchedEpisodesCount;
@property (nonatomic, assign) NSInteger totalEpisodesCount;
@property (nonatomic, assign) NSInteger notAiredEpisodesCount;
@property (nonatomic, copy) NSString *lastWatched;
@property (nonatomic, copy) NSString *nextToWatch;
@property (nonatomic, assign) NSInteger nextEpisodeSeason;
@property (nonatomic, assign) NSInteger nextEpisodeNumber;
@property (nonatomic, copy) NSString *nextEpisodeTitle;
@property (nonatomic, strong) NSDate *nextEpisodeDate;
@property (nonatomic, strong) NSDate *detailFetchedAt;

// /sync/all-items entry: the entry's status and progress plus the nested
// show/movie object.
+ (instancetype)itemWithSyncDictionary:(NSDictionary *)dictionary
                                  type:(MRMediaType)type;

// /search/all result, with endpoint_type deciding the type.
+ (instancetype)itemWithSearchDictionary:(NSDictionary *)dictionary;

// Trending and genre-file item (ids.simkl_id), with an explicit type.
+ (instancetype)itemWithTrendingDictionary:(NSDictionary *)dictionary
                                      type:(MRMediaType)type;

// Detail response (ids.simkl), with an explicit type.
+ (instancetype)itemWithDetailDictionary:(NSDictionary *)dictionary
                                    type:(MRMediaType)type;

// A similar or users_recommendations mini object. The type comes from the
// object's "type" key; entries without a positive ids.simkl are skipped by
// +itemsWithRelatedDictionaries:.
+ (instancetype)itemWithRelatedDictionary:(NSDictionary *)dictionary;
+ (NSArray *)itemsWithRelatedDictionaries:(NSArray *)dictionaries;

// Copies the receiver and replaces the public metadata present in a detail
// response. Library-only fields (watch status, user rating, progress, dates)
// are preserved.
- (MRMediaItem *)itemByMergingDetailDictionary:(NSDictionary *)dictionary;

// Round-trips dictionaryRepresentation.
+ (instancetype)itemWithDictionaryRepresentation:(NSDictionary *)dictionary;

- (NSDictionary *)dictionaryRepresentation;

// "<type>:<simklID>", used to deduplicate items across feed rows.
- (NSString *)identifier;

@end
