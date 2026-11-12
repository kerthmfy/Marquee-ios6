//
//  MRRecommendationEngine.m
//  Marquee
//

#import "MRRecommendationEngine.h"

#import <math.h>

#import "MRClock.h"
#import "MRDate.h"
#import "MRGenreChoice.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRError.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRTasteProfile.h"
#import "MRURLBuilder.h"

NSString *const MRRecommendationsDidResetNotification =
    @"MRRecommendationsDidResetNotification";

static const NSTimeInterval MRRecommendationCacheMaxAge = 6.0 * 60.0 * 60.0;
static const NSTimeInterval MRRecommendationRefreshThrottle = 5.0 * 60.0;
static const NSUInteger MRRecommendationSeedLimit = 3;
static const NSUInteger MRRecommendationRowLimit = 12;
static const NSUInteger MRRecommendationMinimumRow = 3;
static const NSUInteger MRRecommendationContinueLimit = 10;

@implementation MRRecommendationCandidate

+ (instancetype)candidateWithItem:(MRMediaItem *)item
                        baseScore:(double)baseScore
                           source:(MRFeedSource)source
                      proxyGenres:(NSArray *)proxyGenres {
    MRRecommendationCandidate *candidate = [[self alloc] init];
    candidate.item = item;
    candidate.baseScore = baseScore;
    candidate.source = source;
    candidate.proxyGenres = proxyGenres != nil ? proxyGenres : @[];
    return candidate;
}

@end

#pragma mark - Helpers

static double MRRecommendationBaseScoreForSource(MRFeedSource source) {
    switch (source) {
        case MRFeedSourceGenre: return 0.70;
        case MRFeedSourceGenrePicker: return 0.75;
        case MRFeedSourceWatchlist: return 0.60;
        case MRFeedSourceTrending:
        case MRFeedSourcePublicTrending:
            return 0.45;
        case MRFeedSourceSeed:
            return 0.85;
        default:
            return 0.45;
    }
}

static BOOL MRRecommendationIsAdultGenre(NSString *genre) {
    if (![genre isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *lowercase = [genre lowercaseString];
    return [lowercase isEqualToString:@"erotica"] ||
           [lowercase isEqualToString:@"hentai"] ||
           [lowercase isEqualToString:@"video-game-play"] ||
           [lowercase isEqualToString:@"video game play"];
}

static double MRRecommendationClamp(double value, double low, double high) {
    if (value < low) {
        return low;
    }
    if (value > high) {
        return high;
    }
    return value;
}

static NSComparisonResult MRRecommendationItemDateOrder(MRMediaItem *left,
                                                        MRMediaItem *right) {
    NSDate *leftDate = left.lastWatchedAt != nil ? left.lastWatchedAt : [NSDate distantPast];
    NSDate *rightDate = right.lastWatchedAt != nil ? right.lastWatchedAt : [NSDate distantPast];
    NSComparisonResult order = [rightDate compare:leftDate];
    if (order != NSOrderedSame) {
        return order;
    }
    NSComparisonResult titleOrder = [left.title caseInsensitiveCompare:right.title];
    if (titleOrder != NSOrderedSame) {
        return titleOrder;
    }
    if (left.simklID < right.simklID) {
        return NSOrderedAscending;
    }
    if (left.simklID > right.simklID) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

static MRFeedSection *MRRecommendationRow(MRFeedSource source,
                                          NSString *title,
                                          NSString *subtitle,
                                          NSArray *items,
                                          BOOL allowsSingle) {
    NSUInteger minimum = allowsSingle ? 1 : MRRecommendationMinimumRow;
    if (items.count < minimum) {
        return nil;
    }
    if (items.count > MRRecommendationRowLimit) {
        items = [items subarrayWithRange:NSMakeRange(0, MRRecommendationRowLimit)];
    }
    MRFeedSection *section = [MRFeedSection rowSectionWithSource:source
                                                          title:title
                                                          items:items];
    section.subtitle = subtitle != nil ? subtitle : @"";
    return section;
}

#pragma mark - Context

@interface MRRecommendationContext : NSObject
@property (nonatomic, strong) MRTasteProfile *profile;
@property (nonatomic, copy) NSArray *seeds;
@property (nonatomic, strong) NSMutableArray *candidates;
@property (nonatomic, strong) NSMutableArray *genreIndexes;
@property (nonatomic, strong) NSMutableArray *genreRequests;
@property (nonatomic, strong) NSMutableArray *trendingCandidates;
@property (nonatomic, strong) NSMutableArray *watchlistCandidates;
@end

@implementation MRRecommendationContext

- (id)init {
    self = [super init];
    if (self) {
        _candidates = [NSMutableArray array];
        _genreIndexes = [NSMutableArray arrayWithObjects:
                         [NSNull null], [NSNull null], [NSNull null], nil];
        _genreRequests = [NSMutableArray array];
        _trendingCandidates = [NSMutableArray array];
        _watchlistCandidates = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - Engine

@interface MRRecommendationEngine ()
@property (nonatomic, strong) id<MRRecommendationDataProviding> dataProvider;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRPreferencesStore *preferences;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MRResponseCache *responseCache;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, copy) NSArray *cached;
@property (nonatomic, strong) NSDate *cachedAt;
@property (nonatomic, copy) NSString *cachedFingerprint;
@property (nonatomic, strong) NSDate *lastAttemptAt;
@property (nonatomic, strong) id workQueue;
- (void)generateWithCompletion:(void (^)(NSArray *, NSError *))completion
                         force:(BOOL)force;
@end

@implementation MRRecommendationEngine

- (instancetype)initWithDataProvider:(id<MRRecommendationDataProviding>)provider
                        libraryStore:(MRLibraryStore *)libraryStore
                         preferences:(MRPreferencesStore *)preferences
                              storage:(MRStorage *)storage
                       responseCache:(MRResponseCache *)responseCache
                               clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _dataProvider = provider;
        _libraryStore = libraryStore;
        _preferences = preferences;
        _storage = storage;
        _responseCache = responseCache;
        _clock = clock;
        _workQueue = dispatch_queue_create("com.marquee.recommendations", NULL);
        [self loadCache];
    }
    return self;
}

- (NSArray *)cachedSections {
    return self.cached;
}

- (void)invalidateCache {
    self.cached = nil;
    self.cachedAt = nil;
    self.cachedFingerprint = nil;
    [self.storage removeFileNamed:@"recommendations" error:NULL];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MRRecommendationsDidResetNotification
                          object:self];
    });
}

- (void)loadCache {
    if (self.storage == nil) {
        return;
    }
    id json = [self.storage readJSONNamed:@"recommendations" error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dictionary = (NSDictionary *)json;
    NSNumber *accountID = [dictionary objectForKey:@"accountID"];
    if ([accountID isKindOfClass:[NSNumber class]] &&
        [accountID integerValue] != self.storage.accountID) {
        return;
    }
    NSDate *generatedAt =
        [MRDate dateFromISOString:[dictionary objectForKey:@"generatedAt"]];
    NSString *fingerprint = [dictionary objectForKey:@"fingerprint"];
    id storedSections = [dictionary objectForKey:@"sections"];
    if (generatedAt == nil || ![fingerprint isKindOfClass:[NSString class]] ||
        ![storedSections isKindOfClass:[NSArray class]]) {
        return;
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (id entry in (NSArray *)storedSections) {
        MRFeedSection *section = [MRFeedSection sectionWithDictionaryRepresentation:entry];
        if (section != nil) {
            [sections addObject:section];
        }
    }
    self.cached = sections;
    self.cachedAt = generatedAt;
    self.cachedFingerprint = fingerprint;
    self.lastAttemptAt = generatedAt;
}

- (NSString *)trendingCacheURL {
    return [MRURLBuilder dataURLForPath:@"discover/trending/week_100.json" query:nil];
}

- (NSString *)genreIndexCacheURLForType:(MRMediaType)type {
    NSString *path = [NSString stringWithFormat:
                      @"discover/trending/%@/genre/index.json",
                      MRMediaTypeAPIPath(type)];
    return [MRURLBuilder dataURLForPath:path query:nil];
}

- (NSString *)currentFingerprint {
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"generation:%ld",
                      (long)self.libraryStore.generation]];

    NSDate *trendingDate =
        [self.responseCache fetchedAtForURL:[self trendingCacheURL]];
    [parts addObject:[NSString stringWithFormat:@"trending:%.0f",
                      trendingDate != nil ? [trendingDate timeIntervalSince1970] : 0.0]];

    for (NSInteger type = MRMediaTypeMovie; type <= MRMediaTypeAnime; type++) {
        NSDate *date = [self.responseCache
            fetchedAtForURL:[self genreIndexCacheURLForType:(MRMediaType)type]];
        [parts addObject:[NSString stringWithFormat:@"genre-%ld:%.0f", (long)type,
                          date != nil ? [date timeIntervalSince1970] : 0.0]];
    }

    NSMutableArray *manual = [NSMutableArray array];
    for (MRGenreChoice *choice in self.preferences.manualGenres) {
        [manual addObject:[NSString stringWithFormat:@"%ld:%@",
                           (long)choice.type, choice.slug]];
    }
    [manual sortUsingSelector:@selector(compare:)];
    [parts addObject:[NSString stringWithFormat:@"manual:%@",
                      [manual componentsJoinedByString:@","]]];
    [parts addObject:[NSString stringWithFormat:@"hidden:%lu",
                      (unsigned long)self.preferences.hiddenTitles.count]];
    return [parts componentsJoinedByString:@"|"];
}

- (NSDate *)nowDate {
    NSDate *now = [self.clock now];
    return now != nil ? now : [NSDate date];
}

- (NSInteger)currentYear {
    NSDate *now = [self nowDate];
    NSDateComponents *components =
        [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:now];
    return [components year];
}

- (void)deliverCompletion:(void (^)(NSArray *sections, NSError *error))completion
                 sections:(NSArray *)sections
                    error:(NSError *)error {
    if (completion == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(sections, error);
    });
}

- (void)generateWithCompletion:(void (^)(NSArray *sections, NSError *error))completion {
    [self generateWithCompletion:completion force:NO];
}

- (void)refreshWithForce:(BOOL)force
              completion:(void (^)(NSArray *sections, NSError *error))completion {
    if (completion == nil) {
        return;
    }
    if (!force && self.cached != nil && self.lastAttemptAt != nil &&
        [[self nowDate] timeIntervalSinceDate:self.lastAttemptAt] <
            MRRecommendationRefreshThrottle) {
        [self deliverCompletion:completion sections:self.cached error:nil];
        return;
    }
    [self generateWithCompletion:completion force:force];
}

- (void)generateWithCompletion:(void (^)(NSArray *sections, NSError *error))completion
                         force:(BOOL)force {
    if (completion == nil) {
        return;
    }

    NSString *fingerprint = [self currentFingerprint];
    if (!force && self.cached != nil && self.cachedAt != nil &&
        [[self nowDate] timeIntervalSinceDate:self.cachedAt] < MRRecommendationCacheMaxAge &&
        [self.cachedFingerprint isEqualToString:fingerprint]) {
        [self deliverCompletion:completion sections:self.cached error:nil];
        return;
    }

    self.lastAttemptAt = [self nowDate];

    if (self.dataProvider == nil) {
        [self deliverCompletion:completion
                       sections:self.cached != nil ? self.cached : @[]
                          error:[MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    MRTasteProfile *profile = [MRTasteProfile
        profileWithItems:self.libraryStore.items
            manualGenres:self.preferences.manualGenres
                     now:[self nowDate]];
    MRRecommendationContext *context = [[MRRecommendationContext alloc] init];
    context.profile = profile;
    context.seeds = profile.seedItems;

    __weak MRRecommendationEngine *weakSelf = self;
    dispatch_async(self.workQueue, ^{
        MRRecommendationEngine *strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf fetchGenreIndexesForContext:context index:0 completion:completion];
        }
    });
}

#pragma mark - Generation steps

- (void)nextStepOnWorkQueue:(void (^)(void))block {
    dispatch_async(self.workQueue, block);
}

- (void)fetchGenreIndexesForContext:(MRRecommendationContext *)context
                              index:(NSInteger)index
                         completion:(void (^)(NSArray *, NSError *))completion {
    if (index >= 3 || context.profile.favoriteGenres.count == 0) {
        [self fetchSeedDetailsForContext:context index:0 completion:completion];
        return;
    }

    __weak MRRecommendationEngine *weakSelf = self;
    [self.dataProvider fetchGenreIndexForType:(MRMediaType)index
                                   completion:^(NSArray *json, NSError *error) {
        [weakSelf nextStepOnWorkQueue:^{
            if (json != nil && error == nil) {
                [context.genreIndexes replaceObjectAtIndex:(NSUInteger)index
                                                withObject:json];
            }
            [weakSelf fetchGenreIndexesForContext:context
                                           index:index + 1
                                      completion:completion];
        }];
    }];
}

- (void)fetchSeedDetailsForContext:(MRRecommendationContext *)context
                             index:(NSInteger)index
                        completion:(void (^)(NSArray *, NSError *))completion {
    if (index >= (NSInteger)context.seeds.count ||
        index >= (NSInteger)MRRecommendationSeedLimit) {
        [self buildGenreRequestsForContext:context];
        [self fetchGenreFilesForContext:context index:0 completion:completion];
        return;
    }

    MRMediaItem *seed = [context.seeds objectAtIndex:(NSUInteger)index];
    __weak MRRecommendationEngine *weakSelf = self;
    [self.dataProvider fetchDetailForType:seed.type
                                 simklID:seed.simklID
                               completion:^(NSDictionary *json, NSError *error) {
        [weakSelf nextStepOnWorkQueue:^{
            MRRecommendationEngine *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (json != nil && error == nil) {
                MRMediaItem *merged = [seed itemByMergingDetailDictionary:json];
                if ([strongSelf.libraryStore itemForType:merged.type
                                                simklID:merged.simklID] != nil) {
                    [strongSelf.libraryStore updateItem:merged error:NULL];
                }
                NSArray *produced = [strongSelf candidatesFromSeedDetail:json seed:merged];
                for (MRRecommendationCandidate *candidate in produced) {
                    candidate.seedIdentifier = seed.identifier;
                    candidate.seedTitle = merged.title;
                    candidate.seedTier = candidate.baseScore >= 1.0 ? 0 : 1;
                    [context.candidates addObject:candidate];
                }
            }
            [strongSelf fetchSeedDetailsForContext:context
                                            index:index + 1
                                       completion:completion];
        }];
    }];
}

- (NSString *)genreRequestKeyForType:(MRMediaType)type slug:(NSString *)slug {
    return [NSString stringWithFormat:@"%ld:%@", (long)type, slug];
}

- (MRGenreChoice *)indexEntryForName:(NSString *)name
                                type:(MRMediaType)type
                               index:(NSArray *)index {
    for (id entry in index) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *entryName = [entry objectForKey:@"name"];
        NSString *slug = [entry objectForKey:@"slug"];
        if ([entryName isKindOfClass:[NSString class]] &&
            [entryName caseInsensitiveCompare:name] == NSOrderedSame &&
            [slug isKindOfClass:[NSString class]] && slug.length > 0) {
            return [MRGenreChoice choiceWithType:type name:entryName slug:slug];
        }
    }
    return nil;
}

- (void)buildGenreRequestsForContext:(MRRecommendationContext *)context {
    NSMutableSet *keys = [NSMutableSet set];

    NSUInteger manualCount = 0;
    for (MRGenreChoice *choice in self.preferences.manualGenres) {
        if (manualCount >= 2) {
            break;
        }
        NSString *key = [self genreRequestKeyForType:choice.type slug:choice.slug];
        if ([keys containsObject:key]) {
            continue;
        }
        [keys addObject:key];
        [context.genreRequests addObject:@{
            @"type": @(choice.type),
            @"slug": choice.slug,
            @"source": @(MRFeedSourceGenrePicker),
            @"name": choice.name
        }];
        manualCount += 1;
    }

    NSMutableArray *types = [NSMutableArray arrayWithObjects:
                             @(MRMediaTypeMovie), @(MRMediaTypeShow), @(MRMediaTypeAnime), nil];
    [types sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
        double leftWeight = [context.profile weightForType:(MRMediaType)[left integerValue]];
        double rightWeight = [context.profile weightForType:(MRMediaType)[right integerValue]];
        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        return [left compare:right];
    }];

    NSUInteger favoriteCount = 0;
    for (NSString *genre in context.profile.favoriteGenres) {
        if (favoriteCount >= 2) {
            break;
        }
        MRGenreChoice *match = nil;
        for (NSNumber *typeNumber in types) {
            MRMediaType type = (MRMediaType)[typeNumber integerValue];
            id index = [context.genreIndexes objectAtIndex:(NSUInteger)type];
            if (![index isKindOfClass:[NSArray class]]) {
                continue;
            }
            match = [self indexEntryForName:genre type:type index:index];
            if (match != nil) {
                break;
            }
        }
        if (match == nil) {
            continue;
        }
        NSString *key = [self genreRequestKeyForType:match.type slug:match.slug];
        favoriteCount += 1;
        if ([keys containsObject:key]) {
            continue;
        }
        [keys addObject:key];
        [context.genreRequests addObject:@{
            @"type": @(match.type),
            @"slug": match.slug,
            @"source": @(MRFeedSourceGenre),
            @"name": genre
        }];
    }
}

- (void)fetchGenreFilesForContext:(MRRecommendationContext *)context
                            index:(NSInteger)index
                       completion:(void (^)(NSArray *, NSError *))completion {
    if (index >= (NSInteger)context.genreRequests.count) {
        [self fetchTrendingForContext:context completion:completion];
        return;
    }

    NSDictionary *request = [context.genreRequests objectAtIndex:(NSUInteger)index];
    MRMediaType type = (MRMediaType)[[request objectForKey:@"type"] integerValue];
    NSString *slug = [request objectForKey:@"slug"];
    MRFeedSource source = (MRFeedSource)[[request objectForKey:@"source"] integerValue];
    NSString *name = [request objectForKey:@"name"];

    __weak MRRecommendationEngine *weakSelf = self;
    [self.dataProvider fetchGenre:slug
                          forType:type
                       completion:^(NSArray *json, NSError *error) {
        [weakSelf nextStepOnWorkQueue:^{
            MRRecommendationEngine *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (json != nil && error == nil) {
                NSArray *produced = [strongSelf candidatesFromItems:json
                                                               type:type
                                                             source:source];
                for (MRRecommendationCandidate *candidate in produced) {
                    candidate.genreName = name;
                    [context.candidates addObject:candidate];
                }
            }
            [strongSelf fetchGenreFilesForContext:context
                                            index:index + 1
                                       completion:completion];
        }];
    }];
}

- (void)fetchTrendingForContext:(MRRecommendationContext *)context
                     completion:(void (^)(NSArray *, NSError *))completion {
    __weak MRRecommendationEngine *weakSelf = self;
    [self.dataProvider fetchTrendingWeekWithCompletion:
     ^(NSDictionary *json, NSError *error) {
        [weakSelf nextStepOnWorkQueue:^{
            MRRecommendationEngine *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            NSError *generationError = error;
            if (json != nil && error == nil) {
                NSDictionary *payload = [json isKindOfClass:[NSDictionary class]] ? json : @{};
                NSArray *types = @[ @(MRMediaTypeMovie), @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
                NSArray *keys = @[ @"movies", @"tv", @"anime" ];
                for (NSUInteger position = 0; position < keys.count; position++) {
                    NSArray *produced = [strongSelf
                        candidatesFromItems:[payload objectForKey:[keys objectAtIndex:position]]
                                       type:(MRMediaType)[[types objectAtIndex:position] integerValue]
                                     source:MRFeedSourceTrending];
                    [context.trendingCandidates addObjectsFromArray:produced];
                    [context.candidates addObjectsFromArray:produced];
                }
            }

            // Local watchlist candidates only participate in the watchlist row.
            for (NSInteger type = MRMediaTypeMovie; type <= MRMediaTypeAnime; type++) {
                NSArray *plan = [strongSelf.libraryStore itemsForType:(MRMediaType)type
                                                               status:MRWatchStatusPlanToWatch];
                NSArray *produced = [strongSelf candidatesFromItems:plan
                                                               type:(MRMediaType)type
                                                             source:MRFeedSourceWatchlist];
                [context.watchlistCandidates addObjectsFromArray:produced];
            }

            NSArray *sections = [strongSelf sectionsForContext:context];
            if (sections.count == 0 && generationError == nil) {
                generationError = [MRError errorWithKind:MRErrorKindUnknown];
            }
            if (sections.count > 0) {
                generationError = nil;
            }

            if (sections.count > 0) {
                [strongSelf saveSections:sections];
            }

            if (generationError != nil && strongSelf.cached != nil) {
                [strongSelf deliverCompletion:completion
                                     sections:strongSelf.cached
                                        error:generationError];
            } else {
                [strongSelf deliverCompletion:completion
                                     sections:sections
                                        error:generationError];
            }
        }];
    }];
}

#pragma mark - Composition

- (NSArray *)continueWatchingItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSInteger type = MRMediaTypeMovie; type <= MRMediaTypeAnime; type++) {
        NSArray *watching = [self.libraryStore itemsForType:(MRMediaType)type
                                                     status:MRWatchStatusWatching];
        for (MRMediaItem *item in watching) {
            BOOL hasNext = (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) ||
                           item.nextToWatch.length > 0;
            BOOL unfinished = item.totalEpisodesCount > 0 &&
                              item.watchedEpisodesCount < item.totalEpisodesCount;
            if (hasNext || unfinished) {
                [items addObject:item];
            }
        }
    }
    [items sortUsingComparator:^NSComparisonResult(MRMediaItem *left, MRMediaItem *right) {
        return MRRecommendationItemDateOrder(left, right);
    }];
    if (items.count > MRRecommendationContinueLimit) {
        return [items subarrayWithRange:NSMakeRange(0, MRRecommendationContinueLimit)];
    }
    return items;
}

- (NSString *)reasonForCandidate:(MRRecommendationCandidate *)candidate {
    if (candidate.seedTitle.length > 0) {
        return [NSString stringWithFormat:@"Because you watched %@", candidate.seedTitle];
    }
    if (candidate.genreName.length > 0) {
        return [NSString stringWithFormat:@"Because you like %@", candidate.genreName];
    }
    if (candidate.source == MRFeedSourceTrending ||
        candidate.source == MRFeedSourcePublicTrending) {
        return @"Trending this week on Simkl";
    }
    return @"Popular on Simkl this week";
}

- (NSArray *)sectionsForContext:(MRRecommendationContext *)context {
    NSArray *eligible = [self eligibleCandidates:context.candidates];
    NSArray *sorted = [MRRecommendationEngine sortedCandidates:eligible
                                                       profile:context.profile
                                                   currentYear:[self currentYear]];
    BOOL coldStart = self.libraryStore.items.count == 0;

    if (coldStart) {
        return [self coldStartSectionsWithContext:context sorted:sorted];
    }

    NSMutableArray *sections = [NSMutableArray array];
    NSMutableSet *used = [NSMutableSet set];

    MRRecommendationCandidate *hero =
        sorted.count > 0 ? [sorted objectAtIndex:0] : nil;
    if (hero != nil) {
        [used addObject:hero.item.identifier];
        MRFeedSection *section =
            [MRFeedSection heroSectionWithSource:hero.source
                                           title:hero.item.title
                                        subtitle:[self reasonForCandidate:hero]];
        section.items = @[ hero.item ];
        [sections addObject:section];
    }

    NSArray *continueItems = [self continueWatchingItems];
    MRFeedSection *continueSection =
        MRRecommendationRow(MRFeedSourceContinueWatching,
                            @"Continue Watching",
                            @"",
                            continueItems,
                            YES);
    if (continueSection != nil) {
        [sections addObject:continueSection];
    }

    // Because You Watched <seed>: recommendations before similar, refilling
    // from the next seed only when the strongest seed has fewer than four.
    NSMutableArray *seedRow = [NSMutableArray array];
    NSString *seedTitle = nil;
    for (MRMediaItem *seed in context.seeds) {
        if (seedTitle.length == 0) {
            seedTitle = seed.title;
        }
        NSMutableArray *forSeed = [NSMutableArray array];
        for (MRRecommendationCandidate *candidate in sorted) {
            if (![candidate.seedIdentifier isEqualToString:seed.identifier]) {
                continue;
            }
            if ([used containsObject:candidate.item.identifier]) {
                continue;
            }
            [forSeed addObject:candidate];
        }
        [forSeed sortUsingComparator:^NSComparisonResult(MRRecommendationCandidate *left,
                                                         MRRecommendationCandidate *right) {
            if (left.seedTier < right.seedTier) {
                return NSOrderedAscending;
            }
            if (left.seedTier > right.seedTier) {
                return NSOrderedDescending;
            }
            double leftScore = [MRRecommendationEngine scoreForCandidate:left
                                                                 profile:context.profile
                                                             currentYear:[self currentYear]];
            double rightScore = [MRRecommendationEngine scoreForCandidate:right
                                                                  profile:context.profile
                                                              currentYear:[self currentYear]];
            if (leftScore > rightScore) {
                return NSOrderedAscending;
            }
            if (leftScore < rightScore) {
                return NSOrderedDescending;
            }
            return [left.item.title caseInsensitiveCompare:right.item.title];
        }];
        for (MRRecommendationCandidate *candidate in forSeed) {
            if (seedRow.count >= MRRecommendationRowLimit) {
                break;
            }
            [seedRow addObject:candidate.item];
            [used addObject:candidate.item.identifier];
        }
        if (seedRow.count >= 4) {
            break;
        }
    }
    if (seedTitle.length == 0) {
        seedTitle = @"your library";
    }
    MRFeedSection *seedSection =
        MRRecommendationRow(MRFeedSourceSeed,
                            [NSString stringWithFormat:@"Because You Watched %@", seedTitle],
                            [NSString stringWithFormat:@"Because you watched %@", seedTitle],
                            seedRow,
                            NO);
    if (seedSection != nil) {
        [sections addObject:seedSection];
    }

    // Because You Like <genre>: the top favorite genre's file.
    NSArray *favoriteGenres = context.profile.favoriteGenres;
    NSString *favorite = favoriteGenres.count > 0
        ? [favoriteGenres objectAtIndex:0] : nil;
    if (favorite != nil) {
        NSMutableArray *genreRow = [NSMutableArray array];
        for (MRRecommendationCandidate *candidate in sorted) {
            if (![candidate.genreName isEqualToString:favorite]) {
                continue;
            }
            if ([used containsObject:candidate.item.identifier]) {
                continue;
            }
            [genreRow addObject:candidate.item];
            [used addObject:candidate.item.identifier];
            if (genreRow.count >= MRRecommendationRowLimit) {
                break;
            }
        }
        MRFeedSection *genreSection =
            MRRecommendationRow(MRFeedSourceGenre,
                                [NSString stringWithFormat:@"Because You Like %@", favorite],
                                [NSString stringWithFormat:@"Because you like %@", favorite],
                                genreRow,
                                NO);
        if (genreSection != nil) {
            [sections addObject:genreSection];
        }
    }

    // From Your Watchlist: local plan-to-watch items.
    NSArray *watchlist = [MRRecommendationEngine
        sortedCandidates:[self eligibleCandidates:context.watchlistCandidates]
                 profile:context.profile
             currentYear:[self currentYear]];
    NSMutableArray *watchlistItems = [NSMutableArray array];
    for (MRRecommendationCandidate *candidate in watchlist) {
        [watchlistItems addObject:candidate.item];
    }
    MRFeedSection *watchlistSection =
        MRRecommendationRow(MRFeedSourceWatchlist,
                            @"From Your Watchlist",
                            @"On your watchlist",
                            watchlistItems,
                            NO);
    if (watchlistSection != nil) {
        [sections addObject:watchlistSection];
    }

    // Simkl Trending This Week.
    NSMutableArray *trendingRow = [NSMutableArray array];
    for (MRRecommendationCandidate *candidate in sorted) {
        if (candidate.source != MRFeedSourceTrending &&
            candidate.source != MRFeedSourcePublicTrending) {
            continue;
        }
        if ([used containsObject:candidate.item.identifier]) {
            continue;
        }
        [trendingRow addObject:candidate.item];
        [used addObject:candidate.item.identifier];
        if (trendingRow.count >= MRRecommendationRowLimit) {
            break;
        }
    }
    MRFeedSection *trendingSection =
        MRRecommendationRow(MRFeedSourceTrending,
                            @"Simkl Trending This Week",
                            @"Trending this week on Simkl",
                            trendingRow,
                            NO);
    if (trendingSection != nil) {
        [sections addObject:trendingSection];
    }

    NSUInteger nonHero = sections.count - (hero != nil ? 1 : 0);
    if (nonHero == 0) {
        MRFeedSection *empty =
            [MRFeedSection rowSectionWithSource:MRFeedSourceEmptyState
                                          title:@"Find something on Simkl"
                                          items:@[]];
        empty.subtitle = @"Search Simkl for something new.";
        [sections addObject:empty];
    }
    return sections;
}

- (NSArray *)coldStartSectionsWithContext:(MRRecommendationContext *)context
                                    sorted:(NSArray *)sorted {
    NSMutableArray *sections = [NSMutableArray array];
    MRFeedSection *hero =
        [MRFeedSection heroSectionWithSource:MRFeedSourceGenrePicker
                                       title:@"Make For You yours"
                                    subtitle:@"Pick a few genres to get started."];
    [sections addObject:hero];

    NSUInteger manualLimit = 0;
    for (MRGenreChoice *choice in self.preferences.manualGenres) {
        if (manualLimit >= 2) {
            break;
        }
        NSMutableArray *row = [NSMutableArray array];
        for (MRRecommendationCandidate *candidate in sorted) {
            if (candidate.source != MRFeedSourceGenrePicker ||
                ![candidate.genreName isEqualToString:choice.name]) {
                continue;
            }
            [row addObject:candidate.item];
            if (row.count >= MRRecommendationRowLimit) {
                break;
            }
        }
        MRFeedSection *section =
            MRRecommendationRow(MRFeedSourceGenrePicker,
                                [NSString stringWithFormat:@"Because You Like %@", choice.name],
                                [NSString stringWithFormat:@"Because you like %@", choice.name],
                                row,
                                NO);
        if (section != nil) {
            [sections addObject:section];
        }
        manualLimit += 1;
    }

    NSMutableSet *used = [NSMutableSet set];
    NSMutableArray *trending = [NSMutableArray array];
    for (MRRecommendationCandidate *candidate in sorted) {
        if (candidate.source != MRFeedSourceTrending &&
            candidate.source != MRFeedSourcePublicTrending) {
            continue;
        }
        [trending addObject:candidate.item];
        [used addObject:candidate.item.identifier];
        if (trending.count >= MRRecommendationRowLimit) {
            break;
        }
    }
    MRFeedSection *trendingSection =
        MRRecommendationRow(MRFeedSourceTrending,
                            @"Simkl Trending This Week",
                            @"Trending this week on Simkl",
                            trending,
                            NO);
    if (trendingSection != nil) {
        [sections addObject:trendingSection];
    }

    NSArray *typeTitles = @[ @"Trending Movies on Simkl",
                             @"Trending TV on Simkl",
                             @"Trending Anime on Simkl" ];
    for (NSInteger type = MRMediaTypeMovie; type <= MRMediaTypeAnime; type++) {
        NSMutableArray *row = [NSMutableArray array];
        for (MRMediaItem *item in trending) {
            if (item.type != (MRMediaType)type) {
                continue;
            }
            [row addObject:item];
        }
        MRFeedSection *section =
            MRRecommendationRow(MRFeedSourceTrending,
                                [typeTitles objectAtIndex:(NSUInteger)type],
                                @"Popular on Simkl this week",
                                row,
                                NO);
        if (section != nil) {
            [sections addObject:section];
        }
    }

    if (sections.count == 1) {
        MRFeedSection *empty =
            [MRFeedSection rowSectionWithSource:MRFeedSourceEmptyState
                                          title:@"Find something on Simkl"
                                          items:@[]];
        empty.subtitle = @"Search Simkl for something new.";
        [sections addObject:empty];
    }
    return sections;
}

- (BOOL)saveSections:(NSArray *)sections {
    if (self.storage == nil) {
        return NO;
    }
    NSMutableArray *stored = [NSMutableArray array];
    for (MRFeedSection *section in sections) {
        [stored addObject:[section dictionaryRepresentation]];
    }
    NSDate *now = [self nowDate];
    NSDictionary *json = @{
        @"schema": @1,
        @"accountID": @(self.storage.accountID),
        @"generatedAt": [MRDate isoStringFromDate:now],
        @"fingerprint": [self currentFingerprint],
        @"sections": stored
    };
    if (![self.storage writeJSON:json named:@"recommendations" error:NULL]) {
        return NO;
    }
    self.cached = sections;
    self.cachedAt = now;
    self.cachedFingerprint = [self currentFingerprint];
    self.lastAttemptAt = now;
    return YES;
}

#pragma mark - Candidates

- (NSArray *)candidatesFromSeedDetail:(NSDictionary *)detail
                                 seed:(MRMediaItem *)seed {
    if (![detail isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSMutableArray *candidates = [NSMutableArray array];
    NSArray *recommended = [MRMediaItem itemsWithRelatedDictionaries:
                            [detail objectForKey:@"users_recommendations"]];
    for (MRMediaItem *item in recommended) {
        [candidates addObject:[MRRecommendationCandidate
            candidateWithItem:item
                    baseScore:1.00
                       source:MRFeedSourceSeed
                  proxyGenres:seed.genres]];
    }
    NSArray *similar = [MRMediaItem itemsWithRelatedDictionaries:
                        [detail objectForKey:@"similar"]];
    for (MRMediaItem *item in similar) {
        [candidates addObject:[MRRecommendationCandidate
            candidateWithItem:item
                    baseScore:0.85
                       source:MRFeedSourceSeed
                  proxyGenres:seed.genres]];
    }
    return candidates;
}

- (NSArray *)candidatesFromItems:(NSArray *)items
                            type:(MRMediaType)type
                          source:(MRFeedSource)source {
    if (![items isKindOfClass:[NSArray class]]) {
        return @[];
    }
    double base = MRRecommendationBaseScoreForSource(source);
    NSMutableArray *candidates = [NSMutableArray array];
    for (id entry in (NSArray *)items) {
        MRMediaItem *item = nil;
        if ([entry isKindOfClass:[MRMediaItem class]]) {
            item = entry;
        } else if ([entry isKindOfClass:[NSDictionary class]]) {
            item = [MRMediaItem itemWithTrendingDictionary:entry type:type];
        }
        if (item == nil) {
            continue;
        }
        [candidates addObject:[MRRecommendationCandidate
            candidateWithItem:item
                    baseScore:base
                       source:source
                  proxyGenres:nil]];
    }
    return candidates;
}

- (BOOL)candidateIsEligible:(MRRecommendationCandidate *)candidate {
    MRMediaItem *item = candidate.item;
    if (item == nil || item.simklID <= 0 || item.title.length == 0) {
        return NO;
    }
    for (NSString *genre in item.genres) {
        if (MRRecommendationIsAdultGenre(genre)) {
            return NO;
        }
    }
    if (candidate.source != MRFeedSourceWatchlist &&
        [self.libraryStore itemForType:item.type simklID:item.simklID] != nil) {
        return NO;
    }
    if ([self.preferences isHiddenType:item.type simklID:item.simklID]) {
        return NO;
    }
    return YES;
}

- (NSArray *)eligibleCandidates:(NSArray *)candidates {
    NSMutableArray *eligible = [NSMutableArray array];
    NSMutableDictionary *indexes = [NSMutableDictionary dictionary];
    for (id entry in candidates) {
        if (![entry isKindOfClass:[MRRecommendationCandidate class]]) {
            continue;
        }
        MRRecommendationCandidate *candidate = (MRRecommendationCandidate *)entry;
        if (![self candidateIsEligible:candidate]) {
            continue;
        }
        NSString *identifier = [candidate.item identifier];
        NSNumber *existingIndex = [indexes objectForKey:identifier];
        if (existingIndex == nil) {
            [indexes setObject:@(eligible.count) forKey:identifier];
            [eligible addObject:candidate];
            continue;
        }
        NSUInteger index = [existingIndex unsignedIntegerValue];
        MRRecommendationCandidate *existing = [eligible objectAtIndex:index];
        if (candidate.baseScore > existing.baseScore) {
            [eligible replaceObjectAtIndex:index withObject:candidate];
        }
    }
    return eligible;
}

+ (double)genreScoreForCandidate:(MRRecommendationCandidate *)candidate
                         profile:(MRTasteProfile *)profile {
    NSArray *genres = candidate.item.genres;
    double multiplier = 1.0;
    if (genres.count == 0) {
        genres = candidate.proxyGenres;
        multiplier = 0.5;
    }
    if (genres.count == 0) {
        return 0.0;
    }
    double total = 0.0;
    for (NSString *genre in genres) {
        total += [profile weightForGenre:genre] * multiplier;
    }
    return total / (double)genres.count;
}

+ (double)scoreForCandidate:(MRRecommendationCandidate *)candidate
                    profile:(MRTasteProfile *)profile
                currentYear:(NSInteger)currentYear {
    if (candidate == nil || candidate.item == nil) {
        return 0.0;
    }
    MRMediaItem *item = candidate.item;

    double genreScore = [self genreScoreForCandidate:candidate profile:profile];

    id ratingValue = [item.ratings objectForKey:@"simkl"];
    double ratingScore = 0.5;
    if ([ratingValue isKindOfClass:[NSNumber class]]) {
        ratingScore = MRRecommendationClamp(([ratingValue doubleValue] - 5.0) / 5.0,
                                            0.0, 1.0);
    }

    double recencyScore = 0.3;
    if (item.year > 0) {
        NSInteger age = currentYear - item.year;
        if (age <= 5) {
            recencyScore = 1.0;
        } else if (age <= 15) {
            recencyScore = 0.6;
        }
    }

    double popularityScore = 0.0;
    if (item.watchedCount > 0) {
        popularityScore = MRRecommendationClamp(
            log10(1.0 + (double)item.watchedCount) / 4.0, 0.0, 1.0);
    }

    double typeScore = [profile weightForType:item.type];
    return candidate.baseScore +
           0.35 * genreScore +
           0.15 * ratingScore +
           0.10 * recencyScore +
           0.05 * popularityScore +
           0.10 * typeScore;
}

+ (NSArray *)sortedCandidates:(NSArray *)candidates
                      profile:(MRTasteProfile *)profile
                  currentYear:(NSInteger)currentYear {
    NSMutableArray *sorted = [NSMutableArray array];
    for (id entry in candidates) {
        if ([entry isKindOfClass:[MRRecommendationCandidate class]]) {
            [sorted addObject:entry];
        }
    }
    [sorted sortUsingComparator:^NSComparisonResult(MRRecommendationCandidate *left,
                                                    MRRecommendationCandidate *right) {
        double leftScore = [self scoreForCandidate:left profile:profile
                                       currentYear:currentYear];
        double rightScore = [self scoreForCandidate:right profile:profile
                                        currentYear:currentYear];
        if (leftScore > rightScore) {
            return NSOrderedAscending;
        }
        if (leftScore < rightScore) {
            return NSOrderedDescending;
        }
        NSComparisonResult titleOrder =
            [left.item.title caseInsensitiveCompare:right.item.title];
        if (titleOrder != NSOrderedSame) {
            return titleOrder;
        }
        if (left.item.simklID < right.item.simklID) {
            return NSOrderedAscending;
        }
        if (left.item.simklID > right.item.simklID) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return sorted;
}

@end
