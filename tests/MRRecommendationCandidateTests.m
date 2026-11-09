//
//  MRRecommendationCandidateTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import <math.h>
#import "MRTestSupport.h"
#import "MRGenreChoice.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"
#import "MRRecommendationEngine.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRTasteProfile.h"
#import "MRClock.h"

static NSString *MRRecommendationTestRoot(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"marquee-recommendations-%@",
             [[NSProcessInfo processInfo] globallyUniqueString]]];
}

static MRMediaItem *MRRecommendationItem(NSInteger simklID,
                                         MRMediaType type,
                                         NSString *title,
                                         NSArray *genres,
                                         NSInteger year,
                                         NSNumber *rating,
                                         NSInteger watched) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = simklID;
    item.type = type;
    item.title = title;
    item.genres = genres != nil ? genres : @[];
    item.year = year;
    item.watchedCount = watched;
    if (rating != nil) {
        item.ratings = @{ @"simkl": rating };
    }
    return item;
}

static NSArray *MRRecommendationArrayFixture(NSString *name) {
    NSString *path = [@"tests/fixtures" stringByAppendingPathComponent:
                      [name stringByAppendingPathExtension:@"json"]];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        MRAssertTrue(NO, @"recommendation fixture can be read");
        return @[];
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:[NSArray class]] ? object : @[];
}

static MRRecommendationCandidate *MRRecommendationCandidateFor(MRMediaItem *item,
                                                               double base,
                                                               MRFeedSource source,
                                                               NSArray *proxy) {
    return [MRRecommendationCandidate candidateWithItem:item
                                              baseScore:base
                                                   source:source
                                             proxyGenres:proxy];
}

static BOOL MRRecommendationClose(double expected, double actual) {
    return fabs(expected - actual) < 0.0001;
}

void MRRunRecommendationCandidateTests(void) {
    NSString *root = MRRecommendationTestRoot();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:7];
    MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
    [library load:NULL];
    MRPreferencesStore *preferences = [[MRPreferencesStore alloc] initWithStorage:storage];
    MRResponseCache *cache = [[MRResponseCache alloc]
        initWithDirectory:[root stringByAppendingPathComponent:@"responses"]];
    MRSystemClock *clock = [[MRSystemClock alloc] init];
    MRRecommendationEngine *engine =
        [[MRRecommendationEngine alloc] initWithDataProvider:nil
                                               libraryStore:library
                                                preferences:preferences
                                                     storage:storage
                                              responseCache:cache
                                                      clock:clock];

    // Seed details contribute recommendations at 1.00 and similar at 0.85,
    // and the seed genres become proxy genres.
    MRMediaItem *seed = MRRecommendationItem(501, MRMediaTypeShow, @"Seed Show",
                                             @[ @"Drama", @"Science Fiction" ],
                                             2019, @8.4, 0);
    NSArray *seedCandidates =
        [engine candidatesFromSeedDetail:MRFixture(@"seed-detail") seed:seed];
    MRAssertEqualIntegers(2, (NSInteger)seedCandidates.count,
                          @"seed detail yields recommendations and similar");
    for (MRRecommendationCandidate *candidate in seedCandidates) {
        if ([candidate.item.title isEqualToString:@"Recommended One"]) {
            MRAssertTrue(MRRecommendationClose(1.0, candidate.baseScore),
                         @"users_recommendations use base 1.00");
        } else if ([candidate.item.title isEqualToString:@"Similar One"]) {
            MRAssertTrue(MRRecommendationClose(0.85, candidate.baseScore),
                         @"similar uses base 0.85");
        } else {
            MRAssertTrue(NO, @"unexpected seed candidate");
        }
        MRAssertEqualObjects(seed.genres, candidate.proxyGenres,
                             @"seed candidates inherit the seed genres");
    }

    // Source base scores.
    NSArray *genreItems = MRRecommendationArrayFixture(@"genre-movies");
    NSArray *genreCandidates = [engine candidatesFromItems:genreItems
                                                       type:MRMediaTypeMovie
                                                    source:MRFeedSourceGenre];
    MRAssertTrue(genreCandidates.count == 2, @"genre file yields its items");
    MRAssertTrue(MRRecommendationClose(0.70,
        [[genreCandidates objectAtIndex:0] baseScore]),
        @"genre files use base 0.70");
    NSArray *manualCandidates = [engine candidatesFromItems:genreItems
                                                       type:MRMediaTypeMovie
                                                    source:MRFeedSourceGenrePicker];
    MRAssertTrue(MRRecommendationClose(0.75,
        [[manualCandidates objectAtIndex:0] baseScore]),
        @"manual genres use base 0.75");
    NSArray *watchlistCandidates = [engine candidatesFromItems:genreItems
                                                       type:MRMediaTypeMovie
                                                        source:MRFeedSourceWatchlist];
    MRAssertTrue(MRRecommendationClose(0.60,
        [[watchlistCandidates objectAtIndex:0] baseScore]),
        @"watchlist uses base 0.60");
    NSArray *trendingCandidates = [engine candidatesFromItems:genreItems
                                                       type:MRMediaTypeMovie
                                                       source:MRFeedSourceTrending];
    MRAssertTrue(MRRecommendationClose(0.45,
        [[trendingCandidates objectAtIndex:0] baseScore]),
        @"trending uses base 0.45");

    // Exclusions and duplicate handling.
    MRMediaItem *inLibrary = MRRecommendationItem(1, MRMediaTypeMovie, @"In Library",
                                                  @[ @"Drama" ], 2020, @7, 0);
    [library replaceWithItems:@[ inLibrary ] activities:@{} profile:nil error:NULL];

    MRMediaItem *hidden = MRRecommendationItem(2, MRMediaTypeMovie, @"Hidden",
                                               @[ @"Drama" ], 2020, @7, 0);
    [preferences hideTitle:hidden error:NULL];

    MRMediaItem *adult = MRRecommendationItem(3, MRMediaTypeMovie, @"Adult",
                                              @[ @"Erotica" ], 2020, @7, 0);
    MRMediaItem *missing = MRRecommendationItem(0, MRMediaTypeMovie, @"Missing ID",
                                                @[ @"Drama" ], 2020, @7, 0);
    MRMediaItem *duplicate = MRRecommendationItem(5, MRMediaTypeMovie, @"Duplicate",
                                                  @[ @"Drama" ], 2020, @7, 0);

    NSArray *candidates = @[
        MRRecommendationCandidateFor(inLibrary, 0.45, MRFeedSourceTrending, nil),
        MRRecommendationCandidateFor(hidden, 0.45, MRFeedSourceTrending, nil),
        MRRecommendationCandidateFor(adult, 0.70, MRFeedSourceGenre, nil),
        MRRecommendationCandidateFor(missing, 0.70, MRFeedSourceGenre, nil),
        MRRecommendationCandidateFor(duplicate, 0.45, MRFeedSourceTrending, nil),
        MRRecommendationCandidateFor(duplicate, 0.70, MRFeedSourceGenre, nil)
    ];
    NSArray *eligible = [engine eligibleCandidates:candidates];
    MRAssertEqualIntegers(1, (NSInteger)eligible.count,
                          @"ineligible and duplicate candidates are removed");
    MRAssertTrue(MRRecommendationClose(0.70,
        [[eligible objectAtIndex:0] baseScore]),
        @"duplicates keep the highest base score");

    // Watchlist items are the one exception to library exclusion.
    NSArray *watchlistEligible = [engine eligibleCandidates:@[
        MRRecommendationCandidateFor(inLibrary, 0.60, MRFeedSourceWatchlist, nil)
    ]];
    MRAssertEqualIntegers(1, (NSInteger)watchlistEligible.count,
                          @"watchlist candidates may be local library items");

    // Exact score formula and half-strength proxy genres.
    NSArray *manualGenres = @[
        [MRGenreChoice choiceWithType:MRMediaTypeMovie name:@"Drama" slug:@"drama"],
        [MRGenreChoice choiceWithType:MRMediaTypeShow name:@"Drama" slug:@"drama"],
        [MRGenreChoice choiceWithType:MRMediaTypeMovie name:@"Other" slug:@"other"]
    ];
    MRTasteProfile *profile = [MRTasteProfile profileWithItems:@[]
                                                 manualGenres:manualGenres
                                                          now:[NSDate dateWithTimeIntervalSince1970:1760000000.0]];
    MRAssertTrue(MRRecommendationClose(1.0, [profile weightForGenre:@"Drama"]),
                 @"the test profile gives Drama full weight");
    MRAssertTrue(MRRecommendationClose(0.5, [profile weightForType:MRMediaTypeShow]),
                 @"the test profile gives shows half type weight");

    MRMediaItem *scored = MRRecommendationItem(700, MRMediaTypeShow, @"Scored",
                                               @[ @"Drama" ], 2025, @8, 9999);
    MRRecommendationCandidate *scoredCandidate =
        MRRecommendationCandidateFor(scored, 0.70, MRFeedSourceGenre, nil);
    double score = [MRRecommendationEngine scoreForCandidate:scoredCandidate
                                                    profile:profile
                                                currentYear:2026];
    // 0.70 base + 0.35 genre + 0.09 rating + 0.10 recency
    // + 0.05 popularity + 0.05 type = 1.34.
    MRAssertTrue(MRRecommendationClose(1.34, score),
                 @"the score formula matches the design constants");

    MRMediaItem *proxy = MRRecommendationItem(701, MRMediaTypeShow, @"Proxy",
                                              @[], 2025, @8, 9999);
    MRRecommendationCandidate *proxyCandidate =
        MRRecommendationCandidateFor(proxy, 0.70, MRFeedSourceSeed, @[ @"Drama" ]);
    double proxyScore = [MRRecommendationEngine scoreForCandidate:proxyCandidate
                                                         profile:profile
                                                     currentYear:2026];
    MRAssertTrue(MRRecommendationClose(1.165, proxyScore),
                 @"proxy genres count at half strength");

    // Deterministic tie-break: title, then SimKL ID.
    MRMediaItem *beta = MRRecommendationItem(900, MRMediaTypeMovie, @"Beta",
                                             @[ @"Drama" ], 2020, @7, 0);
    MRMediaItem *alpha = MRRecommendationItem(901, MRMediaTypeMovie, @"Alpha",
                                              @[ @"Drama" ], 2020, @7, 0);
    MRMediaItem *alphaLowerID = MRRecommendationItem(899, MRMediaTypeMovie, @"Alpha",
                                                     @[ @"Drama" ], 2020, @7, 0);
    NSArray *sorted = [MRRecommendationEngine sortedCandidates:@[
        MRRecommendationCandidateFor(beta, 0.70, MRFeedSourceGenre, nil),
        MRRecommendationCandidateFor(alpha, 0.70, MRFeedSourceGenre, nil),
        MRRecommendationCandidateFor(alphaLowerID, 0.70, MRFeedSourceGenre, nil)
    ] profile:profile currentYear:2020];
    MRAssertEqualObjects(@"Alpha", [[[sorted objectAtIndex:0] item] title],
                         @"ties break by title");
    MRAssertEqualIntegers(899, [[[sorted objectAtIndex:0] item] simklID],
                          @"equal titles break by SimKL ID");
    MRAssertEqualObjects(@"Beta", [[[sorted objectAtIndex:2] item] title],
                         @"title ordering is deterministic");

    // An empty library still yields manual genres and no seeds.
    MRTasteProfile *empty = [MRTasteProfile profileWithItems:@[]
                                                manualGenres:manualGenres
                                                         now:[NSDate date]];
    MRAssertTrue(empty.seedItems.count == 0, @"an empty library has no seeds");
    MRAssertEqualObjects(@"Drama", [empty.favoriteGenres objectAtIndex:0],
                         @"manual genres drive an empty profile");

    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}
