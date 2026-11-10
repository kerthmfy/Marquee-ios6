//
//  MRProfileStats.m
//  Marquee
//

#import "MRProfileStats.h"

#import "MRMediaItem.h"

@implementation MRProfileStats

+ (instancetype)statsWithItems:(NSArray *)items {
    MRProfileStats *stats = [[MRProfileStats alloc] init];
    if (![items isKindOfClass:[NSArray class]]) {
        return stats;
    }

    NSInteger movies = 0;
    NSInteger shows = 0;
    NSInteger anime = 0;
    NSInteger episodes = 0;
    NSInteger ratings = 0;
    NSInteger watchlist = 0;

    for (MRMediaItem *item in items) {
        if (![item isKindOfClass:[MRMediaItem class]]) {
            continue;
        }

        switch (item.type) {
            case MRMediaTypeMovie:
                movies += 1;
                break;
            case MRMediaTypeShow:
                shows += 1;
                episodes += MAX(0, item.watchedEpisodesCount);
                break;
            case MRMediaTypeAnime:
                anime += 1;
                episodes += MAX(0, item.watchedEpisodesCount);
                break;
            default:
                continue;
        }

        if (item.userRating > 0) {
            ratings += 1;
        }
        if (item.watchStatus == MRWatchStatusPlanToWatch) {
            watchlist += 1;
        }
    }

    stats->_movieCount = movies;
    stats->_showCount = shows;
    stats->_animeCount = anime;
    stats->_episodesWatched = episodes;
    stats->_ratingsCount = ratings;
    stats->_watchlistCount = watchlist;
    return stats;
}

@end
