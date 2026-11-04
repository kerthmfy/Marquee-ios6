//
//  MRMediaItem.m
//  Marquee
//

#import "MRMediaItem.h"
#import "MRDate.h"

static NSString *MRStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return @"";
}

static NSString *MRNullableStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return nil;
}

static NSInteger MRIntegerValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value integerValue];
    }
    return 0;
}

static NSDictionary *MRDictionaryValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        return value;
    }
    return @{};
}

static NSArray *MRStringArrayValue(id value) {
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *strings = [NSMutableArray array];
    for (id element in value) {
        if ([element isKindOfClass:[NSString class]]) {
            [strings addObject:element];
        }
    }
    return strings;
}

static NSDate *MRDateValue(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [MRDate dateFromISOString:value];
}

static NSDictionary *MRExternalIDs(id value) {
    NSDictionary *ids = MRDictionaryValue(value);
    NSMutableDictionary *external = [NSMutableDictionary dictionary];
    for (NSString *key in ids) {
        if ([key isEqualToString:@"simkl"] ||
            [key isEqualToString:@"simkl_id"] ||
            [key isEqualToString:@"slug"]) {
            continue;
        }
        id identifier = ids[key];
        if (identifier != nil && identifier != [NSNull null]) {
            external[key] = identifier;
        }
    }
    return external;
}

@interface MRMediaItem ()
- (void)populateFromObject:(NSDictionary *)object;
@end

@implementation MRMediaItem

- (id)init {
    self = [super init];
    if (self) {
        _slug = @"";
        _title = @"";
        _poster = @"";
        _fanart = @"";
        _genres = @[];
        _ratings = @{};
        _externalIDs = @{};
        _lastWatched = @"";
        _nextToWatch = @"";
    }
    return self;
}

- (void)populateFromObject:(NSDictionary *)object {
    NSDictionary *entry = MRDictionaryValue(object);
    NSDictionary *ids = MRDictionaryValue(entry[@"ids"]);

    self.simklID = MRIntegerValue(ids[@"simkl"]);
    if (self.simklID == 0) {
        self.simklID = MRIntegerValue(ids[@"simkl_id"]);
    }
    self.slug = MRStringValue(ids[@"slug"]);
    self.title = MRStringValue(entry[@"title"]);
    self.year = MRIntegerValue(entry[@"year"]);
    self.poster = MRStringValue(entry[@"poster"]);
    self.fanart = MRStringValue(entry[@"fanart"]);
    self.genres = MRStringArrayValue(entry[@"genres"]);
    self.runtime = MRIntegerValue(entry[@"runtime"]);
    self.ratings = MRDictionaryValue(entry[@"ratings"]);
    self.externalIDs = MRExternalIDs(ids);
}

+ (instancetype)itemWithSyncDictionary:(NSDictionary *)dictionary
                                  type:(MRMediaType)type {
    MRMediaItem *item = [[self alloc] init];
    NSDictionary *entry = MRDictionaryValue(dictionary);

    NSDictionary *object = MRDictionaryValue(entry[@"show"]);
    if (object.count == 0) {
        object = MRDictionaryValue(entry[@"movie"]);
    }
    if (object.count == 0) {
        object = MRDictionaryValue(entry[@"anime"]);
    }
    [item populateFromObject:object];
    item.type = type;

    item.watchStatus = MRWatchStatusFromKey(MRNullableStringValue(entry[@"status"]));
    item.userRating = MRIntegerValue(entry[@"user_rating"]);
    item.userRatedAt = MRDateValue(entry[@"user_rated_at"]);
    item.lastWatchedAt = MRDateValue(entry[@"last_watched_at"]);
    item.addedToWatchlistAt = MRDateValue(entry[@"added_to_watchlist_at"]);
    item.watchedEpisodesCount = MRIntegerValue(entry[@"watched_episodes_count"]);
    item.totalEpisodesCount = MRIntegerValue(entry[@"total_episodes_count"]);
    item.notAiredEpisodesCount = MRIntegerValue(entry[@"not_aired_episodes_count"]);
    item.lastWatched = MRStringValue(entry[@"last_watched"]);
    item.nextToWatch = MRStringValue(entry[@"next_to_watch"]);

    NSDictionary *next = MRDictionaryValue(entry[@"next_to_watch_info"]);
    if (next.count > 0) {
        item.nextEpisodeSeason = MRIntegerValue(next[@"season"]);
        item.nextEpisodeNumber = MRIntegerValue(next[@"episode"]);
        item.nextEpisodeTitle = MRStringValue(next[@"title"]);
        item.nextEpisodeDate = MRDateValue(next[@"date"]);
    }
    return item;
}

+ (instancetype)itemWithSearchDictionary:(NSDictionary *)dictionary {
    MRMediaItem *item = [[self alloc] init];
    NSDictionary *entry = MRDictionaryValue(dictionary);
    [item populateFromObject:entry];
    item.type = MRMediaTypeFromSearchKey(MRNullableStringValue(entry[@"endpoint_type"]));
    return item;
}

+ (instancetype)itemWithTrendingDictionary:(NSDictionary *)dictionary
                                      type:(MRMediaType)type {
    MRMediaItem *item = [[self alloc] init];
    [item populateFromObject:MRDictionaryValue(dictionary)];
    item.type = type;
    return item;
}

+ (instancetype)itemWithDetailDictionary:(NSDictionary *)dictionary
                                    type:(MRMediaType)type {
    MRMediaItem *item = [[self alloc] init];
    [item populateFromObject:MRDictionaryValue(dictionary)];
    item.type = type;
    return item;
}

+ (instancetype)itemWithDictionaryRepresentation:(NSDictionary *)dictionary {
    MRMediaItem *item = [[self alloc] init];
    NSDictionary *entry = MRDictionaryValue(dictionary);

    item.simklID = MRIntegerValue(entry[@"simklID"]);
    item.slug = MRStringValue(entry[@"slug"]);
    item.type = (MRMediaType)MRIntegerValue(entry[@"type"]);
    item.title = MRStringValue(entry[@"title"]);
    item.year = MRIntegerValue(entry[@"year"]);
    item.poster = MRStringValue(entry[@"poster"]);
    item.fanart = MRStringValue(entry[@"fanart"]);
    item.genres = MRStringArrayValue(entry[@"genres"]);
    item.runtime = MRIntegerValue(entry[@"runtime"]);
    item.ratings = MRDictionaryValue(entry[@"ratings"]);
    item.externalIDs = MRDictionaryValue(entry[@"externalIDs"]);

    item.watchStatus = (MRWatchStatus)MRIntegerValue(entry[@"watchStatus"]);
    item.userRating = MRIntegerValue(entry[@"userRating"]);
    item.userRatedAt = MRDateValue(entry[@"userRatedAt"]);
    item.lastWatchedAt = MRDateValue(entry[@"lastWatchedAt"]);
    item.addedToWatchlistAt = MRDateValue(entry[@"addedToWatchlistAt"]);
    item.watchedEpisodesCount = MRIntegerValue(entry[@"watchedEpisodesCount"]);
    item.totalEpisodesCount = MRIntegerValue(entry[@"totalEpisodesCount"]);
    item.notAiredEpisodesCount = MRIntegerValue(entry[@"notAiredEpisodesCount"]);
    item.lastWatched = MRStringValue(entry[@"lastWatched"]);
    item.nextToWatch = MRStringValue(entry[@"nextToWatch"]);
    item.nextEpisodeSeason = MRIntegerValue(entry[@"nextEpisodeSeason"]);
    item.nextEpisodeNumber = MRIntegerValue(entry[@"nextEpisodeNumber"]);
    item.nextEpisodeTitle = MRNullableStringValue(entry[@"nextEpisodeTitle"]);
    item.nextEpisodeDate = MRDateValue(entry[@"nextEpisodeDate"]);
    item.detailFetchedAt = MRDateValue(entry[@"detailFetchedAt"]);
    return item;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    dictionary[@"simklID"] = [NSNumber numberWithInteger:self.simklID];
    dictionary[@"slug"] = self.slug ?: @"";
    dictionary[@"type"] = [NSNumber numberWithInteger:self.type];
    dictionary[@"title"] = self.title ?: @"";
    dictionary[@"year"] = [NSNumber numberWithInteger:self.year];
    dictionary[@"poster"] = self.poster ?: @"";
    dictionary[@"fanart"] = self.fanart ?: @"";
    dictionary[@"genres"] = self.genres ?: @[];
    dictionary[@"runtime"] = [NSNumber numberWithInteger:self.runtime];
    dictionary[@"ratings"] = self.ratings ?: @{};
    dictionary[@"externalIDs"] = self.externalIDs ?: @{};

    dictionary[@"watchStatus"] = [NSNumber numberWithInteger:self.watchStatus];
    dictionary[@"userRating"] = [NSNumber numberWithInteger:self.userRating];
    dictionary[@"watchedEpisodesCount"] =
        [NSNumber numberWithInteger:self.watchedEpisodesCount];
    dictionary[@"totalEpisodesCount"] =
        [NSNumber numberWithInteger:self.totalEpisodesCount];
    dictionary[@"notAiredEpisodesCount"] =
        [NSNumber numberWithInteger:self.notAiredEpisodesCount];
    dictionary[@"lastWatched"] = self.lastWatched ?: @"";
    dictionary[@"nextToWatch"] = self.nextToWatch ?: @"";
    dictionary[@"nextEpisodeSeason"] =
        [NSNumber numberWithInteger:self.nextEpisodeSeason];
    dictionary[@"nextEpisodeNumber"] =
        [NSNumber numberWithInteger:self.nextEpisodeNumber];

    if (self.nextEpisodeTitle != nil) {
        dictionary[@"nextEpisodeTitle"] = self.nextEpisodeTitle;
    }
    if (self.userRatedAt != nil) {
        dictionary[@"userRatedAt"] = [MRDate isoStringFromDate:self.userRatedAt];
    }
    if (self.lastWatchedAt != nil) {
        dictionary[@"lastWatchedAt"] = [MRDate isoStringFromDate:self.lastWatchedAt];
    }
    if (self.addedToWatchlistAt != nil) {
        dictionary[@"addedToWatchlistAt"] =
            [MRDate isoStringFromDate:self.addedToWatchlistAt];
    }
    if (self.nextEpisodeDate != nil) {
        dictionary[@"nextEpisodeDate"] = [MRDate isoStringFromDate:self.nextEpisodeDate];
    }
    if (self.detailFetchedAt != nil) {
        dictionary[@"detailFetchedAt"] = [MRDate isoStringFromDate:self.detailFetchedAt];
    }
    return dictionary;
}

- (NSString *)identifier {
    return [NSString stringWithFormat:@"%ld:%ld",
            (long)self.type, (long)self.simklID];
}

- (id)copyWithZone:(NSZone *)zone {
    MRMediaItem *copy = [[[self class] allocWithZone:zone] init];

    copy.simklID = self.simklID;
    copy.slug = self.slug;
    copy.type = self.type;
    copy.title = self.title;
    copy.year = self.year;
    copy.poster = self.poster;
    copy.fanart = self.fanart;
    copy.genres = self.genres;
    copy.runtime = self.runtime;
    copy.ratings = self.ratings;
    copy.externalIDs = self.externalIDs;

    copy.watchStatus = self.watchStatus;
    copy.userRating = self.userRating;
    copy.userRatedAt = self.userRatedAt;
    copy.lastWatchedAt = self.lastWatchedAt;
    copy.addedToWatchlistAt = self.addedToWatchlistAt;
    copy.watchedEpisodesCount = self.watchedEpisodesCount;
    copy.totalEpisodesCount = self.totalEpisodesCount;
    copy.notAiredEpisodesCount = self.notAiredEpisodesCount;
    copy.lastWatched = self.lastWatched;
    copy.nextToWatch = self.nextToWatch;
    copy.nextEpisodeSeason = self.nextEpisodeSeason;
    copy.nextEpisodeNumber = self.nextEpisodeNumber;
    copy.nextEpisodeTitle = self.nextEpisodeTitle;
    copy.nextEpisodeDate = self.nextEpisodeDate;
    copy.detailFetchedAt = self.detailFetchedAt;
    return copy;
}

@end
