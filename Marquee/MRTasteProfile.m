//
//  MRTasteProfile.m
//  Marquee
//

#import "MRTasteProfile.h"

#import "MRGenreChoice.h"
#import "MRMediaItem.h"
#import "MRWatchStatus.h"

static const NSTimeInterval MRDayInterval = 24.0 * 60.0 * 60.0;

static double MRStatusWeight(MRWatchStatus status) {
    switch (status) {
        case MRWatchStatusCompleted: return 3.0;
        case MRWatchStatusWatching: return 2.5;
        case MRWatchStatusHold: return 1.0;
        case MRWatchStatusPlanToWatch: return 1.2;
        case MRWatchStatusDropped: return -2.0;
        default: return 0.0;
    }
}

static double MRRatingMultiplier(NSInteger rating) {
    if (rating >= 8) {
        return 1.5;
    }
    if (rating >= 6) {
        return 1.1;
    }
    if (rating >= 1) {
        return 0.6;
    }
    return 1.0;
}

static double MRRecencyMultiplier(NSDate *watchedAt, NSDate *now) {
    if (watchedAt == nil || now == nil) {
        return 0.8;
    }
    NSTimeInterval age = [now timeIntervalSinceDate:watchedAt];
    if (age < 0.0) {
        age = 0.0;
    }
    if (age <= 90.0 * MRDayInterval) {
        return 1.2;
    }
    if (age <= 365.0 * MRDayInterval) {
        return 1.0;
    }
    return 0.8;
}

static NSDate *MRSeedDate(MRMediaItem *item) {
    if (item.lastWatchedAt != nil) {
        return item.lastWatchedAt;
    }
    if (item.addedToWatchlistAt != nil) {
        return item.addedToWatchlistAt;
    }
    if (item.userRatedAt != nil) {
        return item.userRatedAt;
    }
    return [NSDate distantPast];
}

static NSComparisonResult MRSeedComparison(MRMediaItem *left, MRMediaItem *right) {
    NSComparisonResult dateOrder = [MRSeedDate(right) compare:MRSeedDate(left)];
    if (dateOrder != NSOrderedSame) {
        return dateOrder;
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

@interface MRTasteProfile ()
@property (nonatomic, copy) NSDictionary *rawGenres;
@property (nonatomic, copy) NSDictionary *normalizedGenres;
@property (nonatomic, copy) NSArray *rawTypes;
@property (nonatomic, copy) NSArray *normalizedTypes;
@property (nonatomic, copy) NSArray *favorites;
@property (nonatomic, copy) NSArray *seeds;
@property (nonatomic, strong) NSDate *now;
@property (nonatomic, copy) NSArray *items;
@end

@implementation MRTasteProfile

+ (instancetype)profileWithItems:(NSArray *)items
                    manualGenres:(NSArray *)manualGenres
                             now:(NSDate *)now {
    MRTasteProfile *profile = [[self alloc] init];
    profile.now = now != nil ? now : [NSDate date];
    profile.items = [items isKindOfClass:[NSArray class]] ? items : @[];
    [profile buildWithManualGenres:
        ([manualGenres isKindOfClass:[NSArray class]] ? manualGenres : @[])];
    return profile;
}

- (void)buildWithManualGenres:(NSArray *)manualGenres {
    NSMutableDictionary *genres = [NSMutableDictionary dictionary];
    NSMutableArray *types = [NSMutableArray arrayWithObjects:@0.0, @0.0, @0.0, nil];

    for (MRMediaItem *item in self.items) {
        double signal = MRStatusWeight(item.watchStatus) *
                        MRRatingMultiplier(item.userRating) *
                        MRRecencyMultiplier(item.lastWatchedAt, self.now);
        for (NSString *genre in item.genres) {
            double existing = [[genres objectForKey:genre] doubleValue];
            [genres setObject:@(existing + signal) forKey:genre];
        }
        double typeWeight = [[types objectAtIndex:(NSUInteger)item.type] doubleValue];
        typeWeight += MAX(signal, 0.0);
        [types replaceObjectAtIndex:(NSUInteger)item.type withObject:@(typeWeight)];
    }

    for (MRGenreChoice *choice in manualGenres) {
        double existingGenre = [[genres objectForKey:choice.name] doubleValue];
        [genres setObject:@(existingGenre + 4.0) forKey:choice.name];
        double typeWeight = [[types objectAtIndex:(NSUInteger)choice.type] doubleValue];
        typeWeight += 2.0;
        [types replaceObjectAtIndex:(NSUInteger)choice.type withObject:@(typeWeight)];
    }

    self.rawGenres = genres;
    self.rawTypes = types;

    double maxGenre = 0.0;
    for (NSNumber *value in [genres allValues]) {
        if ([value doubleValue] > maxGenre) {
            maxGenre = [value doubleValue];
        }
    }
    NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
    for (NSString *genre in genres) {
        double raw = [[genres objectForKey:genre] doubleValue];
        double value = maxGenre > 0.0 ? raw / maxGenre : 0.0;
        [normalized setObject:@(value) forKey:genre];
    }
    self.normalizedGenres = normalized;

    double maxType = 0.0;
    for (NSNumber *value in types) {
        if ([value doubleValue] > maxType) {
            maxType = [value doubleValue];
        }
    }
    NSMutableArray *normalizedTypes = [NSMutableArray array];
    for (NSNumber *value in types) {
        double raw = [value doubleValue];
        [normalizedTypes addObject:@(maxType > 0.0 ? raw / maxType : 0.0)];
    }
    self.normalizedTypes = normalizedTypes;

    NSMutableArray *favorites = [NSMutableArray array];
    for (NSString *genre in normalized) {
        if ([[normalized objectForKey:genre] doubleValue] > 0.1) {
            [favorites addObject:genre];
        }
    }
    [favorites sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        double leftWeight = [[normalized objectForKey:left] doubleValue];
        double rightWeight = [[normalized objectForKey:right] doubleValue];
        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        return [left caseInsensitiveCompare:right];
    }];
    if (favorites.count > 5) {
        [favorites removeObjectsInRange:NSMakeRange(5, favorites.count - 5)];
    }
    self.favorites = favorites;
    self.seeds = [self buildSeeds];
}

- (NSArray *)buildSeeds {
    NSMutableArray *completed = [NSMutableArray array];
    NSMutableArray *watchlist = [NSMutableArray array];
    for (MRMediaItem *item in self.items) {
        if (item.watchStatus == MRWatchStatusCompleted ||
            item.watchStatus == MRWatchStatusWatching) {
            [completed addObject:item];
        } else if ((item.watchStatus == MRWatchStatusHold ||
                    item.watchStatus == MRWatchStatusPlanToWatch) &&
                   item.userRating >= 7) {
            [watchlist addObject:item];
        }
    }
    [completed sortUsingComparator:^NSComparisonResult(MRMediaItem *left, MRMediaItem *right) {
        return MRSeedComparison(left, right);
    }];
    [watchlist sortUsingComparator:^NSComparisonResult(MRMediaItem *left, MRMediaItem *right) {
        return MRSeedComparison(left, right);
    }];

    NSMutableArray *seeds = [NSMutableArray array];
    NSMutableSet *types = [NSMutableSet set];
    NSMutableSet *identifiers = [NSMutableSet set];

    // One highly rated item per type.
    for (MRMediaItem *item in completed) {
        if (seeds.count >= 3) {
            break;
        }
        if (item.userRating < 7 || [types containsObject:@(item.type)]) {
            continue;
        }
        [seeds addObject:item];
        [types addObject:@(item.type)];
        [identifiers addObject:item.identifier];
    }
    // Then any remaining highly rated item.
    for (MRMediaItem *item in completed) {
        if (seeds.count >= 3) {
            break;
        }
        if (item.userRating < 7 || [identifiers containsObject:item.identifier]) {
            continue;
        }
        [seeds addObject:item];
        [identifiers addObject:item.identifier];
    }
    // Then recent unrated completed/watching items.
    for (MRMediaItem *item in completed) {
        if (seeds.count >= 3) {
            break;
        }
        if (item.userRating != 0 || [identifiers containsObject:item.identifier]) {
            continue;
        }
        [seeds addObject:item];
        [identifiers addObject:item.identifier];
    }
    // Finally, highly rated hold/plan-to-watch items.
    for (MRMediaItem *item in watchlist) {
        if (seeds.count >= 3) {
            break;
        }
        if ([identifiers containsObject:item.identifier]) {
            continue;
        }
        [seeds addObject:item];
        [identifiers addObject:item.identifier];
    }
    return seeds;
}

- (double)weightForGenre:(NSString *)genre {
    NSNumber *value = [self.normalizedGenres objectForKey:genre];
    return [value doubleValue];
}

- (double)rawWeightForGenre:(NSString *)genre {
    NSNumber *value = [self.rawGenres objectForKey:genre];
    return [value doubleValue];
}

- (double)weightForType:(MRMediaType)type {
    if (type < MRMediaTypeMovie || type > MRMediaTypeAnime) {
        return 0.0;
    }
    return [[self.normalizedTypes objectAtIndex:(NSUInteger)type] doubleValue];
}

- (double)rawWeightForType:(MRMediaType)type {
    if (type < MRMediaTypeMovie || type > MRMediaTypeAnime) {
        return 0.0;
    }
    return [[self.rawTypes objectAtIndex:(NSUInteger)type] doubleValue];
}

- (NSArray *)favoriteGenres {
    return self.favorites;
}

- (NSArray *)seedItems {
    return self.seeds;
}

@end
