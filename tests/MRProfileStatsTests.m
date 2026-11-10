//
//  MRProfileStatsTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRMediaItem.h"
#import "MRProfileStats.h"

static MRMediaItem *MRStatsItem(MRMediaType type,
                                NSInteger simklID,
                                MRWatchStatus status,
                                NSInteger userRating,
                                NSInteger watchedEpisodes) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.type = type;
    item.simklID = simklID;
    item.title = [NSString stringWithFormat:@"Item %ld", (long)simklID];
    item.watchStatus = status;
    item.userRating = userRating;
    item.watchedEpisodesCount = watchedEpisodes;
    return item;
}

void MRRunProfileStatsTests(void) {
    // Empty library returns zeros.
    {
        MRProfileStats *stats = [MRProfileStats statsWithItems:@[]];
        MRAssertEqualIntegers(0, stats.movieCount, @"empty library has no movies");
        MRAssertEqualIntegers(0, stats.showCount, @"empty library has no shows");
        MRAssertEqualIntegers(0, stats.animeCount, @"empty library has no anime");
        MRAssertEqualIntegers(0, stats.episodesWatched,
                              @"empty library has no watched episodes");
        MRAssertEqualIntegers(0, stats.ratingsCount,
                              @"empty library has no ratings");
        MRAssertEqualIntegers(0, stats.watchlistCount,
                              @"empty library has no watchlist items");
    }

    // Counts, episodes, ratings, and watchlist.
    {
        NSArray *items = @[
            MRStatsItem(MRMediaTypeMovie, 1, MRWatchStatusCompleted, 9, 0),
            MRStatsItem(MRMediaTypeMovie, 2, MRWatchStatusPlanToWatch, 0, 0),
            MRStatsItem(MRMediaTypeShow, 3, MRWatchStatusWatching, 8, 12),
            MRStatsItem(MRMediaTypeShow, 4, MRWatchStatusPlanToWatch, 7, 0),
            MRStatsItem(MRMediaTypeAnime, 5, MRWatchStatusCompleted, 10, 26),
            MRStatsItem(MRMediaTypeAnime, 6, MRWatchStatusDropped, 0, 3)
        ];
        MRProfileStats *stats = [MRProfileStats statsWithItems:items];
        MRAssertEqualIntegers(2, stats.movieCount, @"movie count counts only movies");
        MRAssertEqualIntegers(2, stats.showCount, @"show count counts only shows");
        MRAssertEqualIntegers(2, stats.animeCount, @"anime count counts only anime");
        MRAssertEqualIntegers(41, stats.episodesWatched,
                              @"episodes watched sums shows and anime only");
        MRAssertEqualIntegers(4, stats.ratingsCount,
                              @"ratings count only positive user ratings");
        MRAssertEqualIntegers(2, stats.watchlistCount,
                              @"watchlist counts only plan-to-watch items");
    }

    // Nil and unexpected entries are ignored.
    {
        MRProfileStats *stats = [MRProfileStats statsWithItems:nil];
        MRAssertEqualIntegers(0, stats.movieCount,
                              @"a nil item list behaves like an empty library");
    }
}
