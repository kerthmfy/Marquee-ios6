//
//  MRProfileStats.h
//  Marquee
//

#import <Foundation/Foundation.h>

// The pure summary shown on the Profile stats card. Computed from the local
// library snapshot; never performs API calls.
@interface MRProfileStats : NSObject

@property (nonatomic, readonly) NSInteger movieCount;
@property (nonatomic, readonly) NSInteger showCount;
@property (nonatomic, readonly) NSInteger animeCount;
@property (nonatomic, readonly) NSInteger episodesWatched;
@property (nonatomic, readonly) NSInteger ratingsCount;
@property (nonatomic, readonly) NSInteger watchlistCount;

+ (instancetype)statsWithItems:(NSArray *)items;

@end
