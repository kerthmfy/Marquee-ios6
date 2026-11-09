//
//  MRTasteProfileTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import <math.h>
#import "MRTestSupport.h"
#import "MRGenreChoice.h"
#import "MRMediaItem.h"
#import "MRTasteProfile.h"

static MRMediaItem *MRTasteItem(NSInteger simklID,
                                MRMediaType type,
                                NSString *title,
                                NSArray *genres,
                                MRWatchStatus status,
                                NSInteger rating,
                                NSDate *watchedAt) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = simklID;
    item.type = type;
    item.title = title;
    item.genres = genres;
    item.watchStatus = status;
    item.userRating = rating;
    item.lastWatchedAt = watchedAt;
    return item;
}

static MRGenreChoice *MRTasteChoice(MRMediaType type, NSString *name, NSString *slug) {
    return [MRGenreChoice choiceWithType:type name:name slug:slug];
}

static BOOL MRClose(double expected, double actual) {
    return fabs(expected - actual) < 0.0001;
}

void MRRunTasteProfileTests(void) {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1700000000.0];

    // Status weights use an unknown recency (0.8).
    struct { MRWatchStatus status; double expected; } statuses[] = {
        { MRWatchStatusCompleted, 2.4 },
        { MRWatchStatusWatching, 2.0 },
        { MRWatchStatusHold, 0.8 },
        { MRWatchStatusPlanToWatch, 0.96 },
        { MRWatchStatusDropped, -1.6 }
    };
    for (NSUInteger index = 0; index < sizeof(statuses) / sizeof(statuses[0]); index++) {
        MRMediaItem *item = MRTasteItem(1, MRMediaTypeMovie, @"One", @[ @"Drama" ],
                                        statuses[index].status, 0, nil);
        MRTasteProfile *profile = [MRTasteProfile profileWithItems:@[ item ]
                                                      manualGenres:@[]
                                                               now:now];
        MRAssertTrue(MRClose(statuses[index].expected,
                             [profile rawWeightForGenre:@"Drama"]),
                     @"status weight matches the design constants");
    }

    // Rating multipliers, with a 1.2 recency window.
    struct { NSInteger rating; double expected; } ratings[] = {
        { 8, 5.4 }, { 7, 3.96 }, { 6, 3.96 }, { 5, 2.16 }, { 0, 3.6 }
    };
    for (NSUInteger index = 0; index < sizeof(ratings) / sizeof(ratings[0]); index++) {
        MRMediaItem *item = MRTasteItem(1, MRMediaTypeMovie, @"One", @[ @"Drama" ],
                                        MRWatchStatusCompleted, ratings[index].rating, now);
        MRTasteProfile *profile = [MRTasteProfile profileWithItems:@[ item ]
                                                      manualGenres:@[]
                                                               now:now];
        MRAssertTrue(MRClose(ratings[index].expected,
                             [profile rawWeightForGenre:@"Drama"]),
                     @"rating multiplier matches the design constants");
    }

    // Recency multipliers.
    struct { NSTimeInterval age; double expected; } recencies[] = {
        { 30.0 * 86400.0, 3.6 },
        { 200.0 * 86400.0, 3.0 },
        { 700.0 * 86400.0, 2.4 }
    };
    for (NSUInteger index = 0; index < sizeof(recencies) / sizeof(recencies[0]); index++) {
        NSDate *watched = [now dateByAddingTimeInterval:-recencies[index].age];
        MRMediaItem *item = MRTasteItem(1, MRMediaTypeMovie, @"One", @[ @"Drama" ],
                                        MRWatchStatusCompleted, 0, watched);
        MRTasteProfile *profile = [MRTasteProfile profileWithItems:@[ item ]
                                                      manualGenres:@[]
                                                               now:now];
        MRAssertTrue(MRClose(recencies[index].expected,
                             [profile rawWeightForGenre:@"Drama"]),
                     @"recency multiplier matches the design constants");
    }

    // Manual genres add +4.0 to the genre and +2.0 to the matching type.
    MRTasteProfile *manual = [MRTasteProfile
        profileWithItems:@[]
             manualGenres:@[ MRTasteChoice(MRMediaTypeMovie, @"Science Fiction", @"science-fiction") ]
                      now:now];
    MRAssertTrue(MRClose(4.0, [manual rawWeightForGenre:@"Science Fiction"]),
                 @"manual genres add four to the genre");
    MRAssertTrue(MRClose(2.0, [manual rawWeightForType:MRMediaTypeMovie]),
                 @"manual genres add two to the matching type");
    MRAssertTrue(MRClose(1.0, [manual weightForGenre:@"Science Fiction"]),
                 @"genre weights normalize to one");
    MRAssertTrue(MRClose(1.0, [manual weightForType:MRMediaTypeMovie]),
                 @"type weights normalize to one");
    MRAssertEqualIntegers(1, (NSInteger)manual.favoriteGenres.count,
                          @"the manual genre becomes a favorite");

    // Favorite genres: top five, and a weight at or below 0.1 is excluded.
    NSMutableArray *many = [NSMutableArray array];
    NSArray *names = @[ @"A", @"B", @"C", @"D", @"E", @"F" ];
    [many addObject:MRTasteItem(1, MRMediaTypeMovie, @"A", @[ @"A" ],
                                MRWatchStatusCompleted, 0, nil)];
    [many addObject:MRTasteItem(2, MRMediaTypeMovie, @"B", @[ @"B" ],
                                MRWatchStatusCompleted, 9, now)];
    [many addObject:MRTasteItem(3, MRMediaTypeMovie, @"C", @[ @"C" ],
                                MRWatchStatusWatching, 0, now)];
    [many addObject:MRTasteItem(4, MRMediaTypeMovie, @"D", @[ @"D" ],
                                MRWatchStatusPlanToWatch, 0, nil)];
    [many addObject:MRTasteItem(5, MRMediaTypeMovie, @"E", @[ @"E" ],
                                MRWatchStatusHold, 0, nil)];
    [many addObject:MRTasteItem(6, MRMediaTypeMovie, @"F", @[ @"F" ],
                                MRWatchStatusDropped, 0, nil)];
    (void)names;
    MRTasteProfile *favorites = [MRTasteProfile
        profileWithItems:many
             manualGenres:@[ MRTasteChoice(MRMediaTypeMovie, @"A", @"a") ]
                      now:now];
    MRAssertEqualIntegers(5, (NSInteger)favorites.favoriteGenres.count,
                          @"favorite genres stop at five");
    MRAssertEqualObjects(@"A", [favorites.favoriteGenres objectAtIndex:0],
                         @"the strongest genre is first");
    MRAssertTrue([favorites weightForGenre:@"F"] <= 0.1,
                 @"a weak genre is excluded from favorites");

    // Dropped items reduce but do not erase a genre.
    MRMediaItem *loved = MRTasteItem(1, MRMediaTypeMovie, @"Good", @[ @"Superhero" ],
                                     MRWatchStatusCompleted, 0, now);
    MRMediaItem *hated = MRTasteItem(2, MRMediaTypeMovie, @"Bad", @[ @"Superhero", @"Bad Genre" ],
                                     MRWatchStatusDropped, 0, now);
    MRTasteProfile *mixed = [MRTasteProfile profileWithItems:@[ loved, hated ]
                                                manualGenres:@[]
                                                         now:now];
    MRAssertTrue([mixed rawWeightForGenre:@"Superhero"] > 0.0,
                 @"a dropped item does not erase a genre completely");
    MRAssertTrue([mixed rawWeightForGenre:@"Bad Genre"] < 0.0,
                 @"a dropped-only genre keeps its negative weight");
    MRAssertTrue([mixed weightForGenre:@"Superhero"] > 0.1,
                 @"the surviving genre remains a favorite");

    // Seed selection: one per type first, only ratings of 7+.
    NSDate *recent = now;
    NSArray *library = @[
        MRTasteItem(1, MRMediaTypeMovie, @"Movie 9", @[ @"A" ], MRWatchStatusCompleted, 9, recent),
        MRTasteItem(2, MRMediaTypeShow, @"Show 8", @[ @"A" ], MRWatchStatusWatching, 8, recent),
        MRTasteItem(3, MRMediaTypeAnime, @"Anime 10", @[ @"A" ], MRWatchStatusCompleted, 10, recent),
        MRTasteItem(4, MRMediaTypeMovie, @"Movie 7", @[ @"A" ], MRWatchStatusCompleted, 7, recent)
    ];
    MRTasteProfile *seeded = [MRTasteProfile profileWithItems:library
                                                 manualGenres:@[]
                                                          now:now];
    MRAssertEqualIntegers(3, (NSInteger)seeded.seedItems.count,
                          @"seed items stop at three");
    NSMutableSet *seedTypes = [NSMutableSet set];
    for (MRMediaItem *item in seeded.seedItems) {
        [seedTypes addObject:@(item.type)];
        MRAssertTrue(item.userRating >= 7, @"seeds prefer ratings of seven or higher");
    }
    MRAssertEqualIntegers(3, (NSInteger)seedTypes.count,
                          @"seeds prefer one item per type");

    // Without 7+ completed/watching items, unrated completed/watching items
    // come before highly rated watchlist items.
    NSArray *fallback = @[
        MRTasteItem(5, MRMediaTypeShow, @"Unrated", @[ @"A" ], MRWatchStatusCompleted, 0, recent),
        MRTasteItem(6, MRMediaTypeMovie, @"Watchlist 9", @[ @"A" ], MRWatchStatusPlanToWatch, 9, nil),
        MRTasteItem(7, MRMediaTypeMovie, @"Weak 5", @[ @"A" ], MRWatchStatusCompleted, 5, recent)
    ];
    MRTasteProfile *fallbackProfile = [MRTasteProfile profileWithItems:fallback
                                                          manualGenres:@[]
                                                                   now:now];
    MRAssertEqualObjects(@"Unrated", [[fallbackProfile.seedItems objectAtIndex:0] title],
                         @"unrated completed items precede rated watchlist items");
    MRAssertTrue(fallbackProfile.seedItems.count >= 2,
                 @"watchlist fallback fills the seed list");
    MRAssertEqualObjects(@"Watchlist 9", [[fallbackProfile.seedItems objectAtIndex:1] title],
                         @"a highly rated watchlist item is the second seed");
}
