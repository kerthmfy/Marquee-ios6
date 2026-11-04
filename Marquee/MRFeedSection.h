//
//  MRFeedSection.h
//  Marquee
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MRFeedSectionKind) {
    MRFeedSectionKindHero = 0,
    MRFeedSectionKindRow
};

typedef NS_ENUM(NSInteger, MRFeedSource) {
    MRFeedSourceConnect = 0,
    MRFeedSourceGenrePicker,
    MRFeedSourceContinueWatching,
    MRFeedSourceSeed,
    MRFeedSourceGenre,
    MRFeedSourceWatchlist,
    MRFeedSourceTrending,
    MRFeedSourcePublicTrending
};

// One unit of the For You feed: a hero card or a horizontal row. Items are
// MRMediaItem objects. Missing values default to empty strings and an empty
// array so a section can always be rendered.
@interface MRFeedSection : NSObject

@property (nonatomic, assign) MRFeedSectionKind kind;
@property (nonatomic, assign) MRFeedSource source;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSArray *items;

+ (instancetype)heroSectionWithSource:(MRFeedSource)source
                                title:(NSString *)title
                             subtitle:(NSString *)subtitle;

+ (instancetype)rowSectionWithSource:(MRFeedSource)source
                               title:(NSString *)title
                               items:(NSArray *)items;

@end
