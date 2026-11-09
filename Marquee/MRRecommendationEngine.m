//
//  MRRecommendationEngine.m
//  Marquee
//

#import "MRRecommendationEngine.h"

#import <math.h>

#import "MRGenreChoice.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRError.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"
#import "MRResponseCache.h"
#import "MRStorage.h"
#import "MRTasteProfile.h"

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

@interface MRRecommendationEngine ()
@property (nonatomic, strong) id<MRRecommendationDataProviding> dataProvider;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRPreferencesStore *preferences;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MRResponseCache *responseCache;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, copy) NSArray *cached;
@property (nonatomic, strong) NSDate *cachedAt;
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
    }
    return self;
}

- (NSArray *)cachedSections {
    return self.cached;
}

- (void)invalidateCache {
    self.cached = nil;
    self.cachedAt = nil;
    [self.storage removeFileNamed:@"recommendations" error:NULL];
}

- (void)generateWithCompletion:(void (^)(NSArray *sections, NSError *error))completion {
    // Row composition and its cache land in the next task; keep callers honest
    // until then instead of returning a half-built page.
    if (completion != nil) {
        completion(@[], [MRError errorWithKind:MRErrorKindUnknown]);
    }
}

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
