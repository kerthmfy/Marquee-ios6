//
//  MRRecommendationRowsTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRClock.h"
#import "MRFeedSection.h"
#import "MRGenreChoice.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"
#import "MRRecommendationEngine.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRURLBuilder.h"

#pragma mark - Stub response cache

// The engine only consults fetchedAtForURL: for its fingerprint. This stub
// makes those dates deterministic without touching the filesystem.
@interface MRRowsStubCache : MRResponseCache
@property (nonatomic, strong) NSMutableDictionary *dates;
- (void)setFetchedAt:(NSDate *)date forURL:(NSString *)URL;
@end

@implementation MRRowsStubCache

- (id)init {
    self = [super initWithDirectory:nil];
    if (self) {
        _dates = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setFetchedAt:(NSDate *)date forURL:(NSString *)URL {
    if (URL.length == 0) {
        return;
    }
    if (date == nil) {
        [self.dates removeObjectForKey:URL];
    } else {
        [self.dates setObject:date forKey:URL];
    }
}

- (NSDate *)fetchedAtForURL:(NSString *)URL {
    return [self.dates objectForKey:URL];
}

@end

#pragma mark - Stub data provider

@interface MRRowsStubProvider : NSObject <MRRecommendationDataProviding>
@property (atomic, assign) NSInteger totalCalls;
@property (nonatomic, strong) NSDictionary *trending;
@property (nonatomic, strong) NSMutableDictionary *genreIndexes;
@property (nonatomic, strong) NSMutableDictionary *genreFiles;
@property (nonatomic, strong) NSMutableDictionary *seedDetails;

- (void)setGenreIndex:(NSArray *)index forType:(MRMediaType)type;
- (void)setGenreFile:(NSArray *)items forType:(MRMediaType)type slug:(NSString *)slug;
- (void)setSeedDetail:(NSDictionary *)detail forType:(MRMediaType)type simklID:(NSInteger)simklID;
@end

@implementation MRRowsStubProvider

- (id)init {
    self = [super init];
    if (self) {
        _genreIndexes = [NSMutableDictionary dictionary];
        _genreFiles = [NSMutableDictionary dictionary];
        _seedDetails = [NSMutableDictionary dictionary];
        _trending = @{};
    }
    return self;
}

- (void)recordCall {
    self.totalCalls = self.totalCalls + 1;
}

- (NSString *)genreKeyForType:(MRMediaType)type slug:(NSString *)slug {
    return [NSString stringWithFormat:@"%ld:%@", (long)type, slug];
}

- (NSString *)seedKeyForType:(MRMediaType)type simklID:(NSInteger)simklID {
    return [NSString stringWithFormat:@"%ld:%ld", (long)type, (long)simklID];
}

- (void)setGenreIndex:(NSArray *)index forType:(MRMediaType)type {
    [self.genreIndexes setObject:(index != nil ? index : @[]) forKey:@(type)];
}

- (void)setGenreFile:(NSArray *)items forType:(MRMediaType)type slug:(NSString *)slug {
    [self.genreFiles setObject:(items != nil ? items : @[])
                        forKey:[self genreKeyForType:type slug:slug]];
}

- (void)setSeedDetail:(NSDictionary *)detail
              forType:(MRMediaType)type
             simklID:(NSInteger)simklID {
    if (detail != nil) {
        [self.seedDetails setObject:detail
                             forKey:[self seedKeyForType:type simklID:simklID]];
    }
}

- (id<MRHTTPTask>)fetchTrendingWeekWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall];
    if (completion != nil) {
        completion(self.trending != nil ? self.trending : @{}, nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchGenreIndexForType:(MRMediaType)type
                              completion:(void (^)(NSArray *json, NSError *error))completion {
    [self recordCall];
    NSArray *index = [self.genreIndexes objectForKey:@(type)];
    if (completion != nil) {
        completion(index != nil ? index : @[], nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchGenre:(NSString *)slug
                     forType:(MRMediaType)type
                  completion:(void (^)(NSArray *json, NSError *error))completion {
    [self recordCall];
    NSArray *items = [self.genreFiles objectForKey:[self genreKeyForType:type slug:slug]];
    if (completion != nil) {
        completion(items != nil ? items : @[], nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchDetailForType:(MRMediaType)type
                            simklID:(NSInteger)simklID
                         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self recordCall];
    NSDictionary *detail =
        [self.seedDetails objectForKey:[self seedKeyForType:type simklID:simklID]];
    if (completion != nil) {
        if (detail != nil) {
            completion(detail, nil);
        } else {
            completion(nil, [NSError errorWithDomain:@"MRRowsStub"
                                                code:1
                                            userInfo:nil]);
        }
    }
    return nil;
}

@end

#pragma mark - Helpers

static NSString *MRRowsRoot(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"marquee-recommendation-rows-%@",
             [[NSProcessInfo processInfo] globallyUniqueString]]];
}

static MRMediaItem *MRRowsItem(NSInteger simklID,
                               MRMediaType type,
                               NSString *title,
                               NSInteger year,
                               NSArray *genres,
                               MRWatchStatus status,
                               NSInteger rating,
                               NSDate *lastWatchedAt) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = simklID;
    item.slug = [title lowercaseString];
    item.type = type;
    item.title = title;
    item.year = year;
    item.poster = @"poster/path";
    item.genres = genres != nil ? genres : @[];
    item.watchStatus = status;
    item.userRating = rating;
    item.lastWatchedAt = lastWatchedAt;
    return item;
}

static NSDictionary *MRRowsTrendingEntry(NSInteger simklID,
                                         NSString *title,
                                         NSInteger year,
                                         NSNumber *rating,
                                         NSInteger watched) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    [entry setObject:title forKey:@"title"];
    [entry setObject:@(year) forKey:@"year"];
    [entry setObject:[title lowercaseString] forKey:@"slug"];
    [entry setObject:@{
        @"simkl_id": @(simklID),
        @"slug": [title lowercaseString]
    } forKey:@"ids"];
    [entry setObject:@"poster/path" forKey:@"poster"];
    [entry setObject:@[] forKey:@"genres"];
    if (rating != nil) {
        [entry setObject:@{ @"simkl": rating } forKey:@"ratings"];
    }
    [entry setObject:@(watched) forKey:@"watched"];
    return entry;
}

static NSDictionary *MRRowsRelated(NSInteger simklID,
                                   NSString *title,
                                   NSString *type,
                                   NSInteger year,
                                   NSNumber *rating) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    [entry setObject:title forKey:@"title"];
    [entry setObject:type forKey:@"type"];
    [entry setObject:@(year) forKey:@"year"];
    [entry setObject:@{
        @"simkl_id": @(simklID),
        @"slug": [title lowercaseString]
    } forKey:@"ids"];
    [entry setObject:@"poster/path" forKey:@"poster"];
    [entry setObject:@[] forKey:@"genres"];
    if (rating != nil) {
        [entry setObject:@{ @"simkl": rating } forKey:@"ratings"];
    }
    return entry;
}

static NSDictionary *MRRowsGenreEntry(NSInteger simklID,
                                     NSString *title,
                                     NSArray *genres,
                                     NSInteger year,
                                     NSNumber *rating) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    [entry setObject:title forKey:@"title"];
    [entry setObject:@(year) forKey:@"year"];
    [entry setObject:genres != nil ? genres : @[] forKey:@"genres"];
    [entry setObject:@{
        @"simkl_id": @(simklID),
        @"slug": [title lowercaseString]
    } forKey:@"ids"];
    [entry setObject:@"poster/path" forKey:@"poster"];
    if (rating != nil) {
        [entry setObject:@{ @"simkl": rating } forKey:@"ratings"];
    }
    [entry setObject:@(100) forKey:@"watched"];
    return entry;
}

static MRFeedSection *MRRowsSection(NSArray *sections, MRFeedSource source) {
    for (MRFeedSection *section in sections) {
        if (section.source == source && section.kind == MRFeedSectionKindRow) {
            return section;
        }
    }
    return nil;
}

static NSArray *MRRowsTitles(MRFeedSection *section) {
    NSMutableArray *titles = [NSMutableArray array];
    for (MRMediaItem *item in section.items) {
        [titles addObject:item.title != nil ? item.title : @""];
    }
    return titles;
}

static NSArray *MRRunRowsGeneration(MRRecommendationEngine *engine, NSError **outError) {
    __block NSArray *result = nil;
    __block NSError *resultError = nil;
    __block BOOL finished = NO;
    [engine generateWithCompletion:^(NSArray *sections, NSError *error) {
        result = sections != nil ? sections : @[];
        resultError = error;
        finished = YES;
    }];
    BOOL completed = MRRunUntil(^BOOL {
        return finished;
    }, 8.0);
    MRAssertTrue(completed, @"recommendation generation completes");
    if (outError != NULL) {
        *outError = resultError;
    }
    return result != nil ? result : @[];
}

static NSArray *MRRunRowsRefresh(MRRecommendationEngine *engine,
                                 BOOL force,
                                 NSError **outError) {
    __block NSArray *result = nil;
    __block NSError *resultError = nil;
    __block BOOL finished = NO;
    [engine refreshWithForce:force completion:^(NSArray *sections, NSError *error) {
        result = sections != nil ? sections : @[];
        resultError = error;
        finished = YES;
    }];
    BOOL completed = MRRunUntil(^BOOL {
        return finished;
    }, 8.0);
    MRAssertTrue(completed, @"recommendation refresh completes");
    if (outError != NULL) {
        *outError = resultError;
    }
    return result != nil ? result : @[];
}

static NSString *MRRowsTrendingURL(void) {
    return [MRURLBuilder dataURLForPath:@"discover/trending/week_100.json" query:nil];
}

static NSString *MRRowsGenreIndexURL(MRMediaType type) {
    NSString *path = [NSString stringWithFormat:@"discover/trending/%@/genre/index.json",
                      MRMediaTypeAPIPath(type)];
    return [MRURLBuilder dataURLForPath:path query:nil];
}

#pragma mark - Tests

static void MRRunRecommendationRowsAndSeedTests(MRRowsStubProvider *provider,
                                                NSDate *now) {
    NSString *root = MRRowsRoot();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
    MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
    [library load:NULL];

    MRMediaItem *seedMovie = MRRowsItem(101, MRMediaTypeMovie, @"Seed Movie",
                                        2024, @[], MRWatchStatusCompleted, 9, now);
    MRMediaItem *showA = MRRowsItem(201, MRMediaTypeShow, @"Show A",
                                    2023, @[], MRWatchStatusWatching, 0,
                                    [now dateByAddingTimeInterval:-3600.0]);
    showA.nextEpisodeSeason = 2;
    showA.nextEpisodeNumber = 5;
    showA.totalEpisodesCount = 10;
    showA.watchedEpisodesCount = 4;
    MRMediaItem *showB = MRRowsItem(202, MRMediaTypeShow, @"Show B",
                                    2022, @[], MRWatchStatusWatching, 0,
                                    [now dateByAddingTimeInterval:-7200.0]);
    showB.totalEpisodesCount = 10;
    showB.watchedEpisodesCount = 5;
    MRMediaItem *movieC = MRRowsItem(203, MRMediaTypeMovie, @"Movie C",
                                     2021, @[], MRWatchStatusWatching, 0,
                                     [now dateByAddingTimeInterval:-800.0]);
    MRMediaItem *watchlistNine = MRRowsItem(301, MRMediaTypeMovie, @"Watchlist Nine",
                                            2024, @[], MRWatchStatusPlanToWatch, 9, nil);
    MRMediaItem *watchlistFive = MRRowsItem(302, MRMediaTypeMovie, @"Watchlist Five",
                                            2024, @[], MRWatchStatusPlanToWatch, 5, nil);
    MRMediaItem *watchlistEight = MRRowsItem(303, MRMediaTypeMovie, @"Watchlist Eight",
                                             2024, @[], MRWatchStatusPlanToWatch, 8, nil);
    watchlistNine.ratings = @{ @"simkl": @9.0 };
    watchlistFive.ratings = @{ @"simkl": @5.0 };
    watchlistEight.ratings = @{ @"simkl": @8.0 };
    MRMediaItem *libraryTrending = MRRowsItem(401, MRMediaTypeMovie, @"Library Trending",
                                              2024, @[], MRWatchStatusCompleted, 0, nil);

    NSError *libraryError = nil;
    BOOL replaced = [library replaceWithItems:@[
        seedMovie, showA, showB, movieC,
        watchlistNine, watchlistFive, watchlistEight, libraryTrending
    ] activities:@{} profile:nil error:&libraryError];
    MRAssertTrue(replaced, @"library replacement succeeds");
    MRAssertTrue(libraryError == nil, @"library replacement has no error");

    [provider setSeedDetail:@{
        @"users_recommendations": @[
            MRRowsRelated(1001, @"Seed Rec One", @"movie", 2026, @8.6),
            MRRowsRelated(1002, @"Seed Rec Two", @"movie", 2026, @8.6)
        ],
        @"similar": @[
            MRRowsRelated(1003, @"Seed Similar One", @"movie", 2020, @8.0),
            MRRowsRelated(1004, @"Seed Similar Two", @"movie", 2020, @8.0)
        ]
    } forType:MRMediaTypeMovie simklID:101];
    [provider setSeedDetail:@{
        @"users_recommendations": @[
            MRRowsRelated(1101, @"Show A Rec One", @"tv", 2015, @7.0),
            MRRowsRelated(1102, @"Show A Rec Two", @"tv", 2015, @7.0)
        ]
    } forType:MRMediaTypeShow simklID:201];

    provider.trending = @{
        @"movies": @[
            MRRowsTrendingEntry(2001, @"Trending One", 2026, @8.0, 4000),
            MRRowsTrendingEntry(2002, @"Trending Two", 2025, @8.0, 3000),
            MRRowsTrendingEntry(2003, @"Trending Three", 2024, @8.0, 2000),
            MRRowsTrendingEntry(401, @"Library Trending", 2024, @9.0, 9000)
        ]
    };

    MRPreferencesStore *preferences = [[MRPreferencesStore alloc] initWithStorage:storage];
    MRRowsStubCache *cache = [[MRRowsStubCache alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRRecommendationEngine *engine =
        [[MRRecommendationEngine alloc] initWithDataProvider:provider
                                               libraryStore:library
                                                preferences:preferences
                                                     storage:storage
                                              responseCache:cache
                                                      clock:clock];

    NSError *generationError = nil;
    NSArray *sections = MRRunRowsGeneration(engine, &generationError);
    MRAssertTrue(generationError == nil, @"the populated feed generates without an error");
    MRAssertEqualIntegers(5, (NSInteger)sections.count,
                          @"the populated feed has hero, continue, seed, watchlist, trending");

    MRFeedSection *hero = [sections objectAtIndex:0];
    MRAssertEqualIntegers(MRFeedSectionKindHero, hero.kind, @"the first section is the hero");
    MRAssertEqualObjects(@"Seed Rec One", hero.title,
                         @"the hero is the highest-scored new candidate");
    MRAssertTrue([hero.subtitle rangeOfString:@"Seed Movie"].location != NSNotFound,
                 @"the hero explains its seed");
    MRAssertEqualIntegers(1, (NSInteger)hero.items.count, @"the hero contains one item");

    MRFeedSection *continueSection =
        MRRowsSection(sections, MRFeedSourceContinueWatching);
    MRAssertTrue(continueSection != nil, @"Continue Watching is present");
    MRAssertEqualObjects((@[ @"Show A", @"Show B" ]), MRRowsTitles(continueSection),
                         @"Continue Watching is most recent first and skips finished movies");

    MRFeedSection *seedSection = MRRowsSection(sections, MRFeedSourceSeed);
    MRAssertTrue(seedSection != nil, @"Because You Watched is present");
    MRAssertEqualObjects(@"Because You Watched Seed Movie", seedSection.title,
                         @"the strongest seed names the row");
    MRAssertEqualObjects((@[ @"Seed Rec Two", @"Seed Similar One", @"Seed Similar Two",
                             @"Show A Rec One", @"Show A Rec Two" ]),
                         MRRowsTitles(seedSection),
                         @"recommendations precede similar and the next seed fills the row");

    MRFeedSection *watchlistSection = MRRowsSection(sections, MRFeedSourceWatchlist);
    MRAssertTrue(watchlistSection != nil, @"From Your Watchlist is present");
    MRAssertEqualObjects((@[ @"Watchlist Nine", @"Watchlist Eight", @"Watchlist Five" ]),
                         MRRowsTitles(watchlistSection),
                         @"the watchlist row orders by affinity and rating");

    MRFeedSection *trendingSection = MRRowsSection(sections, MRFeedSourceTrending);
    MRAssertTrue(trendingSection != nil, @"Simkl Trending is present");
    MRAssertEqualObjects(@"Simkl Trending This Week", trendingSection.title,
                         @"the trending row title names Simkl and trending");
    NSArray *trendingTitles = MRRowsTitles(trendingSection);
    MRAssertEqualIntegers(3, (NSInteger)trendingTitles.count,
                          @"the trending row drops the library item");
    MRAssertTrue(![trendingTitles containsObject:@"Library Trending"],
                 @"trending is filtered against the library");

    NSMutableSet *identifiers = [NSMutableSet set];
    NSUInteger itemCount = 0;
    NSUInteger heroOccurrences = 0;
    for (MRFeedSection *section in sections) {
        for (MRMediaItem *item in section.items) {
            itemCount += 1;
            [identifiers addObject:item.identifier];
            if ([item.title isEqualToString:hero.title]) {
                heroOccurrences += 1;
            }
        }
    }
    MRAssertEqualIntegers((NSInteger)identifiers.count, (NSInteger)itemCount,
                          @"no item appears twice on the page");
    MRAssertEqualIntegers(1, (NSInteger)heroOccurrences,
                          @"the hero does not repeat inside a row");

    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

void MRRunRecommendationRowsTests(void) {
    MRFakeClock *nowClock = [[MRFakeClock alloc] init];
    NSDate *now = [nowClock now];

    MRRowsStubProvider *provider = [[MRRowsStubProvider alloc] init];
    MRRunRecommendationRowsAndSeedTests(provider, now);
    (void)nowClock;

    // Continue Watching may show a single item.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(501, MRMediaTypeMovie, @"Solo Seed",
                                       2024, @[], MRWatchStatusCompleted, 9, now);
        MRMediaItem *watching = MRRowsItem(502, MRMediaTypeShow, @"Only Watching",
                                           2024, @[], MRWatchStatusWatching, 0,
                                           [now dateByAddingTimeInterval:-60.0]);
        watching.nextEpisodeSeason = 1;
        watching.nextEpisodeNumber = 2;
        [library replaceWithItems:@[ seed, watching ] activities:@{} profile:nil error:NULL];

        MRRowsStubProvider *singleProvider = [[MRRowsStubProvider alloc] init];
        singleProvider.trending = @{};
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:singleProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:[[MRRowsStubCache alloc] init]
                                                          clock:nowClock];
        NSArray *sections = MRRunRowsGeneration(engine, NULL);
        MRFeedSection *continueSection =
            MRRowsSection(sections, MRFeedSourceContinueWatching);
        MRAssertTrue(continueSection != nil,
                     @"Continue Watching still appears with one item");
        MRAssertEqualIntegers(1, (NSInteger)continueSection.items.count,
                              @"Continue Watching keeps a single item");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // Rows below the minimum are omitted and an empty page gets the search card.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(511, MRMediaTypeMovie, @"Two Item Seed",
                                       2024, @[], MRWatchStatusCompleted, 9, now);
        [library replaceWithItems:@[ seed ] activities:@{} profile:nil error:NULL];

        MRRowsStubProvider *twoProvider = [[MRRowsStubProvider alloc] init];
        twoProvider.trending = @{
            @"movies": @[
                MRRowsTrendingEntry(2101, @"Only Trending One", 2026, @8.0, 100),
                MRRowsTrendingEntry(2102, @"Only Trending Two", 2025, @8.0, 100)
            ]
        };
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:twoProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:[[MRRowsStubCache alloc] init]
                                                          clock:nowClock];
        NSArray *sections = MRRunRowsGeneration(engine, NULL);
        MRAssertEqualIntegers(2, (NSInteger)sections.count,
                              @"one hero and the empty card remain");
        MRAssertEqualIntegers(MRFeedSectionKindHero,
                              (NSInteger)[(MRFeedSection *)[sections objectAtIndex:0] kind],
                              @"a two-item source can still supply the hero");
        MRFeedSection *empty = [sections objectAtIndex:1];
        MRAssertEqualObjects(@"Find something to watch", empty.title,
                             @"the empty card names the search action");
        MRAssertEqualIntegers(MRFeedSourceEmptyState, empty.source,
                              @"the card uses the empty-state source");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // A page with no candidates at all still gets the empty card.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(521, MRMediaTypeMovie, @"Quiet Seed",
                                       2024, @[], MRWatchStatusCompleted, 9, now);
        [library replaceWithItems:@[ seed ] activities:@{} profile:nil error:NULL];

        MRRowsStubProvider *emptyProvider = [[MRRowsStubProvider alloc] init];
        emptyProvider.trending = @{};
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:emptyProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:[[MRRowsStubCache alloc] init]
                                                          clock:nowClock];
        NSArray *sections = MRRunRowsGeneration(engine, NULL);
        MRAssertEqualIntegers(1, (NSInteger)sections.count,
                              @"an empty page contains only the empty card");
        MRAssertEqualObjects(@"Find something to watch",
                             [[sections objectAtIndex:0] title],
                             @"the empty page names the search action");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // Genre row and watchlist affinity.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(601, MRMediaTypeMovie, @"Drama Seed",
                                       2024, @[ @"Drama" ], MRWatchStatusCompleted, 9, now);
        MRMediaItem *dramaNine = MRRowsItem(701, MRMediaTypeMovie, @"Drama Watchlist Nine",
                                            2024, @[ @"Drama" ],
                                            MRWatchStatusPlanToWatch, 9, nil);
        MRMediaItem *dramaFive = MRRowsItem(702, MRMediaTypeMovie, @"Drama Watchlist Five",
                                            2024, @[ @"Drama" ],
                                            MRWatchStatusPlanToWatch, 5, nil);
        MRMediaItem *comedyEight = MRRowsItem(703, MRMediaTypeMovie, @"Comedy Watchlist Eight",
                                              2024, @[ @"Comedy" ],
                                              MRWatchStatusPlanToWatch, 8, nil);
        dramaNine.ratings = @{ @"simkl": @9.0 };
        dramaFive.ratings = @{ @"simkl": @5.0 };
        comedyEight.ratings = @{ @"simkl": @8.0 };
        [library replaceWithItems:@[ seed, dramaNine, dramaFive, comedyEight ]
                       activities:@{} profile:nil error:NULL];

        MRRowsStubProvider *genreProvider = [[MRRowsStubProvider alloc] init];
        [genreProvider setGenreIndex:@[
            @{ @"name": @"Drama", @"slug": @"drama" },
            @{ @"name": @"Comedy", @"slug": @"comedy" }
        ] forType:MRMediaTypeMovie];
        [genreProvider setGenreFile:@[
            MRRowsGenreEntry(801, @"Drama Genre One", @[ @"Drama" ], 2025, @8.5),
            MRRowsGenreEntry(802, @"Drama Genre Two", @[ @"Drama" ], 2025, @8.2),
            MRRowsGenreEntry(803, @"Drama Genre Three", @[ @"Drama" ], 2024, @8.0),
            MRRowsGenreEntry(804, @"Drama Genre Four", @[ @"Drama" ], 2023, @7.8),
            MRRowsGenreEntry(805, @"Drama Genre Five", @[ @"Drama" ], 2022, @7.5)
        ] forType:MRMediaTypeMovie slug:@"drama"];
        [genreProvider setGenreFile:@[
            MRRowsGenreEntry(811, @"Comedy Genre One", @[ @"Comedy" ], 2025, @9.0),
            MRRowsGenreEntry(812, @"Comedy Genre Two", @[ @"Comedy" ], 2025, @9.0),
            MRRowsGenreEntry(813, @"Comedy Genre Three", @[ @"Comedy" ], 2025, @9.0)
        ] forType:MRMediaTypeMovie slug:@"comedy"];
        genreProvider.trending = @{
            @"movies": @[
                MRRowsTrendingEntry(2201, @"Genre Trending One", 2026, @8.0, 500),
                MRRowsTrendingEntry(2202, @"Genre Trending Two", 2025, @8.0, 500),
                MRRowsTrendingEntry(2203, @"Genre Trending Three", 2024, @8.0, 500)
            ]
        };

        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:genreProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:[[MRRowsStubCache alloc] init]
                                                          clock:nowClock];
        NSArray *sections = MRRunRowsGeneration(engine, NULL);

        MRFeedSection *genreSection = MRRowsSection(sections, MRFeedSourceGenre);
        MRAssertTrue(genreSection != nil, @"Because You Like is present");
        MRAssertEqualObjects(@"Because You Like Drama", genreSection.title,
                             @"the row uses the top favorite genre");
        MRAssertEqualIntegers(4, (NSInteger)genreSection.items.count,
                              @"the hero is removed from the genre row");
        for (MRMediaItem *item in genreSection.items) {
            MRAssertEqualObjects(@"Drama", [item.genres firstObject],
                                 @"the genre row uses the top genre file");
        }
        MRAssertTrue(![MRRowsTitles(genreSection) containsObject:@"Comedy Genre One"],
                     @"a second favorite genre does not get a personalized row");

        MRFeedSection *watchlistSection = MRRowsSection(sections, MRFeedSourceWatchlist);
        MRAssertTrue(watchlistSection != nil, @"the watchlist row is present");
        MRAssertEqualObjects((@[ @"Drama Watchlist Nine",
                                 @"Drama Watchlist Five",
                                 @"Comedy Watchlist Eight" ]),
                             MRRowsTitles(watchlistSection),
                             @"watchlist scoring favors genre affinity and rating");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // Cold start order: genre card, manual rows, trending, optional type rows.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        [preferences addManualGenre:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                              name:@"Drama"
                                                              slug:@"drama"]
                              error:NULL];
        [preferences addManualGenre:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                              name:@"Comedy"
                                                              slug:@"comedy"]
                              error:NULL];

        MRRowsStubProvider *coldProvider = [[MRRowsStubProvider alloc] init];
        [coldProvider setGenreIndex:@[
            @{ @"name": @"Drama", @"slug": @"drama" },
            @{ @"name": @"Comedy", @"slug": @"comedy" }
        ] forType:MRMediaTypeMovie];
        [coldProvider setGenreFile:@[
            MRRowsGenreEntry(3001, @"Cold Drama One", @[ @"Drama" ], 2025, @8.0),
            MRRowsGenreEntry(3002, @"Cold Drama Two", @[ @"Drama" ], 2024, @8.0),
            MRRowsGenreEntry(3003, @"Cold Drama Three", @[ @"Drama" ], 2023, @8.0)
        ] forType:MRMediaTypeMovie slug:@"drama"];
        [coldProvider setGenreFile:@[
            MRRowsGenreEntry(3101, @"Cold Comedy One", @[ @"Comedy" ], 2025, @8.0),
            MRRowsGenreEntry(3102, @"Cold Comedy Two", @[ @"Comedy" ], 2024, @8.0),
            MRRowsGenreEntry(3103, @"Cold Comedy Three", @[ @"Comedy" ], 2023, @8.0)
        ] forType:MRMediaTypeMovie slug:@"comedy"];
        coldProvider.trending = @{
            @"movies": @[
                MRRowsTrendingEntry(4001, @"Cold Trending Movie One", 2026, @8.0, 500),
                MRRowsTrendingEntry(4002, @"Cold Trending Movie Two", 2025, @8.0, 500),
                MRRowsTrendingEntry(4003, @"Cold Trending Movie Three", 2024, @8.0, 500)
            ],
            @"tv": @[
                MRRowsTrendingEntry(4101, @"Cold Trending Show One", 2026, @8.0, 500),
                MRRowsTrendingEntry(4102, @"Cold Trending Show Two", 2025, @8.0, 500),
                MRRowsTrendingEntry(4103, @"Cold Trending Show Three", 2024, @8.0, 500)
            ],
            @"anime": @[
                MRRowsTrendingEntry(4201, @"Cold Trending Anime One", 2026, @8.0, 500),
                MRRowsTrendingEntry(4202, @"Cold Trending Anime Two", 2025, @8.0, 500),
                MRRowsTrendingEntry(4203, @"Cold Trending Anime Three", 2024, @8.0, 500)
            ]
        };

        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:coldProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:[[MRRowsStubCache alloc] init]
                                                          clock:nowClock];
        NSArray *sections = MRRunRowsGeneration(engine, NULL);
        MRAssertEqualIntegers(7, (NSInteger)sections.count,
                              @"cold start has a card, two genre rows, trending, and three type rows");

        MRFeedSection *hero = [sections objectAtIndex:0];
        MRAssertEqualIntegers(MRFeedSectionKindHero, hero.kind,
                              @"the cold-start page begins with a hero card");
        MRAssertEqualObjects(@"Make For You yours", hero.title,
                             @"the cold-start hero asks for genres");

        MRFeedSection *drama = [sections objectAtIndex:1];
        MRFeedSection *comedy = [sections objectAtIndex:2];
        MRFeedSection *trending = [sections objectAtIndex:3];
        MRAssertEqualObjects(@"Because You Like Drama", drama.title,
                             @"the first manual genre comes first");
        MRAssertEqualObjects(@"Because You Like Comedy", comedy.title,
                             @"the second manual genre comes second");
        MRAssertEqualObjects(@"Simkl Trending This Week", trending.title,
                             @"trending follows the manual genre rows");
        MRAssertEqualIntegers(9, (NSInteger)trending.items.count,
                              @"the trending row includes all three types");
        MRAssertEqualObjects(@"Trending Movies on Simkl",
                             [[sections objectAtIndex:4] title],
                             @"movies come first in the optional type rows");
        MRAssertEqualObjects(@"Trending TV on Simkl",
                             [[sections objectAtIndex:5] title],
                             @"TV follows movies");
        MRAssertEqualObjects(@"Trending Anime on Simkl",
                             [[sections objectAtIndex:6] title],
                             @"anime follows TV");
        MRAssertEqualIntegers(3, (NSInteger)[[sections objectAtIndex:4] items].count,
                              @"the movie row holds the movie trending items");
        MRAssertEqualIntegers(3, (NSInteger)[[sections objectAtIndex:5] items].count,
                              @"the TV row holds the TV trending items");
        MRAssertEqualIntegers(3, (NSInteger)[[sections objectAtIndex:6] items].count,
                              @"the anime row holds the anime trending items");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // The fingerprint responds to every input in its contract.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(901, MRMediaTypeMovie, @"Fingerprint Seed",
                                       2024, @[], MRWatchStatusCompleted, 9, now);
        [library replaceWithItems:@[ seed ] activities:@{} profile:nil error:NULL];

        MRRowsStubCache *cache = [[MRRowsStubCache alloc] init];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000000.0]
                     forURL:MRRowsTrendingURL()];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000100.0]
                     forURL:MRRowsGenreIndexURL(MRMediaTypeMovie)];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000200.0]
                     forURL:MRRowsGenreIndexURL(MRMediaTypeShow)];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000300.0]
                     forURL:MRRowsGenreIndexURL(MRMediaTypeAnime)];

        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRecommendationEngine *engine =
            [[MRRecommendationEngine alloc] initWithDataProvider:nil
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:cache
                                                          clock:nowClock];
        NSString *original = [engine currentFingerprint];
        MRAssertTrue(original.length > 0, @"the fingerprint is not empty");

        [library replaceWithItems:@[ seed, MRRowsItem(902, MRMediaTypeMovie,
                                                      @"Second Seed", 2024, @[],
                                                      MRWatchStatusCompleted, 8, now) ]
                       activities:@{} profile:nil error:NULL];
        NSString *afterGeneration = [engine currentFingerprint];
        MRAssertTrue(![afterGeneration isEqualToString:original],
                     @"a library generation change changes the fingerprint");

        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000001.0]
                     forURL:MRRowsTrendingURL()];
        NSString *afterTrending = [engine currentFingerprint];
        MRAssertTrue(![afterTrending isEqualToString:afterGeneration],
                     @"a trending cache date change changes the fingerprint");

        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000101.0]
                     forURL:MRRowsGenreIndexURL(MRMediaTypeMovie)];
        NSString *afterGenre = [engine currentFingerprint];
        MRAssertTrue(![afterGenre isEqualToString:afterTrending],
                     @"a genre cache date change changes the fingerprint");

        [preferences addManualGenre:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                              name:@"Drama"
                                                              slug:@"drama"]
                              error:NULL];
        NSString *afterManual = [engine currentFingerprint];
        MRAssertTrue(![afterManual isEqualToString:afterGenre],
                     @"a manual genre change changes the fingerprint");

        [preferences hideTitle:MRRowsItem(950, MRMediaTypeMovie, @"Hidden Fingerprint",
                                         2024, @[], MRWatchStatusNone, 0, nil)
                         error:NULL];
        NSString *afterHidden = [engine currentFingerprint];
        MRAssertTrue(![afterHidden isEqualToString:afterManual],
                     @"a hidden count change changes the fingerprint");

        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // A matching fingerprint under six hours returns the cache without calls.
    {
        NSString *root = MRRowsRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:1];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRRowsItem(951, MRMediaTypeMovie, @"Cache Seed",
                                       2024, @[], MRWatchStatusCompleted, 9, now);
        [library replaceWithItems:@[ seed ] activities:@{} profile:nil error:NULL];
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRRowsStubCache *cache = [[MRRowsStubCache alloc] init];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000000.0]
                     forURL:MRRowsTrendingURL()];
        [cache setFetchedAt:[NSDate dateWithTimeIntervalSince1970:1000000100.0]
                     forURL:MRRowsGenreIndexURL(MRMediaTypeMovie)];

        NSDictionary *trending = @{
            @"movies": @[
                MRRowsTrendingEntry(5001, @"Cache Trending One", 2026, @8.0, 500),
                MRRowsTrendingEntry(5002, @"Cache Trending Two", 2025, @8.0, 500),
                MRRowsTrendingEntry(5003, @"Cache Trending Three", 2024, @8.0, 500),
                MRRowsTrendingEntry(5004, @"Cache Trending Four", 2023, @8.0, 500)
            ]
        };
        MRRowsStubProvider *firstProvider = [[MRRowsStubProvider alloc] init];
        firstProvider.trending = trending;
        MRFakeClock *cacheClock = [[MRFakeClock alloc] init];
        MRRecommendationEngine *first =
            [[MRRecommendationEngine alloc] initWithDataProvider:firstProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:cache
                                                          clock:cacheClock];
        NSArray *firstSections = MRRunRowsGeneration(first, NULL);
        MRAssertEqualIntegers(2, (NSInteger)firstSections.count,
                              @"the first generation adds the hero and trending row");
        MRAssertTrue(firstProvider.totalCalls > 0,
                     @"the first generation calls the provider");
        NSDictionary *stored = [storage readJSONNamed:@"recommendations" error:NULL];
        MRAssertTrue([stored isKindOfClass:[NSDictionary class]],
                     @"recommendations.json is persisted");
        MRAssertTrue([stored objectForKey:@"fingerprint"] != nil,
                     @"the persisted feed stores its fingerprint");

        MRRowsStubProvider *secondProvider = [[MRRowsStubProvider alloc] init];
        secondProvider.trending = trending;
        MRRecommendationEngine *second =
            [[MRRecommendationEngine alloc] initWithDataProvider:secondProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:cache
                                                          clock:cacheClock];
        NSArray *cachedSections = MRRunRowsGeneration(second, NULL);
        MRAssertEqualIntegers((NSInteger)firstSections.count,
                              (NSInteger)cachedSections.count,
                              @"the cached feed has the same shape");
        MRAssertEqualIntegers(0, secondProvider.totalCalls,
                              @"a matching fingerprint under six hours skips the network");
        MRAssertEqualObjects([[firstSections objectAtIndex:0] title],
                             [[cachedSections objectAtIndex:0] title],
                             @"the cached hero is returned");

        [preferences addManualGenre:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                              name:@"Drama"
                                                              slug:@"drama"]
                              error:NULL];
        NSInteger callsBeforeThrottle = secondProvider.totalCalls;
        [cacheClock advanceBy:60.0];
        NSArray *throttledSections = MRRunRowsRefresh(second, NO, NULL);
        MRAssertEqualIntegers(callsBeforeThrottle, secondProvider.totalCalls,
                              @"a refresh inside five minutes is throttled");
        MRAssertEqualIntegers((NSInteger)cachedSections.count,
                              (NSInteger)throttledSections.count,
                              @"the throttled refresh returns the complete cache");
        MRAssertEqualObjects([[cachedSections objectAtIndex:0] title],
                             [[throttledSections objectAtIndex:0] title],
                             @"the throttled refresh returns the cache");

        NSInteger callsBeforeForced = secondProvider.totalCalls;
        MRRunRowsRefresh(second, YES, NULL);
        MRAssertTrue(secondProvider.totalCalls > callsBeforeForced,
                     @"a forced refresh bypasses the five-minute throttle");

        NSInteger callsBeforeExpiry = secondProvider.totalCalls;
        [cacheClock advanceBy:6.0 * 60.0 * 60.0 + 1.0];
        NSArray *expiredSections = MRRunRowsGeneration(second, NULL);
        MRAssertTrue(expiredSections != nil, @"an expired cache regenerates");
        MRAssertTrue(secondProvider.totalCalls > callsBeforeExpiry,
                     @"a cache older than six hours calls the provider");

        MRRowsStubProvider *thirdProvider = [[MRRowsStubProvider alloc] init];
        thirdProvider.trending = trending;
        [preferences addManualGenre:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                              name:@"Comedy"
                                                              slug:@"comedy"]
                              error:NULL];
        MRRecommendationEngine *third =
            [[MRRecommendationEngine alloc] initWithDataProvider:thirdProvider
                                                   libraryStore:library
                                                    preferences:preferences
                                                         storage:storage
                                                  responseCache:cache
                                                          clock:cacheClock];
        MRRunRowsGeneration(third, NULL);
        MRAssertTrue(thirdProvider.totalCalls > 0,
                     @"a fingerprint mismatch regenerates even under six hours");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}
