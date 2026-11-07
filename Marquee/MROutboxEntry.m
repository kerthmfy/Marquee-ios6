//
//  MROutboxEntry.m
//  Marquee
//

#import "MROutboxEntry.h"

#import "MRDate.h"
#import "MRMediaItem.h"

static NSString *MROutboxStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return nil;
}

static NSInteger MROutboxIntegerValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value integerValue];
    }
    return 0;
}

static NSDictionary *MROutboxDictionaryValue(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : @{};
}

@implementation MROutboxEntry

+ (instancetype)entryWithItem:(MRMediaItem *)item kind:(MROutboxEntryKind)kind {
    MROutboxEntry *entry = [[self alloc] init];
    entry.entryID = [[NSUUID UUID] UUIDString];
    entry.createdAt = [NSDate date];
    entry.kind = kind;
    entry.type = item.type;
    entry.simklID = item.simklID;
    entry.title = item.title;
    entry.year = item.year;
    entry.externalIDs = item.externalIDs != nil ? item.externalIDs : @{};
    entry.status = MRWatchStatusNone;
    entry.rating = 0;
    entry.season = 0;
    entry.episode = 0;
    entry.previousStatus = item.watchStatus;
    entry.previousRating = item.userRating;
    entry.attempts = 0;
    return entry;
}

+ (instancetype)statusEntryWithItem:(MRMediaItem *)item
                              status:(MRWatchStatus)status
                      previousStatus:(MRWatchStatus)previousStatus {
    MROutboxEntry *entry = [self entryWithItem:item kind:MROutboxEntryKindStatus];
    entry.status = status;
    entry.previousStatus = previousStatus;
    return entry;
}

+ (instancetype)historyWholeEntryWithItem:(MRMediaItem *)item
                                   status:(MRWatchStatus)status {
    MROutboxEntry *entry =
        [self entryWithItem:item kind:MROutboxEntryKindHistoryWhole];
    entry.status = status;
    return entry;
}

+ (instancetype)historyEpisodeEntryWithItem:(MRMediaItem *)item
                                     season:(NSInteger)season
                                    episode:(NSInteger)episode {
    MROutboxEntry *entry =
        [self entryWithItem:item kind:MROutboxEntryKindHistoryEpisode];
    entry.season = season;
    entry.episode = episode;
    return entry;
}

+ (instancetype)ratingEntryWithItem:(MRMediaItem *)item
                             rating:(NSInteger)rating
                     previousRating:(NSInteger)previousRating {
    MROutboxEntry *entry = [self entryWithItem:item kind:MROutboxEntryKindRating];
    entry.rating = rating;
    entry.previousRating = previousRating;
    return entry;
}

+ (instancetype)ratingRemoveEntryWithItem:(MRMediaItem *)item
                            previousRating:(NSInteger)previousRating {
    MROutboxEntry *entry =
        [self entryWithItem:item kind:MROutboxEntryKindRatingRemove];
    entry.previousRating = previousRating;
    return entry;
}

+ (instancetype)removeEntryWithItem:(MRMediaItem *)item
                     previousStatus:(MRWatchStatus)previousStatus
                     previousRating:(NSInteger)previousRating {
    MROutboxEntry *entry = [self entryWithItem:item kind:MROutboxEntryKindRemove];
    entry.previousStatus = previousStatus;
    entry.previousRating = previousRating;
    return entry;
}

+ (NSString *)kindKeyForKind:(MROutboxEntryKind)kind {
    switch (kind) {
        case MROutboxEntryKindHistoryWhole:
            return @"historyWhole";
        case MROutboxEntryKindHistoryEpisode:
            return @"historyEpisode";
        case MROutboxEntryKindRating:
            return @"rating";
        case MROutboxEntryKindRatingRemove:
            return @"ratingRemove";
        case MROutboxEntryKindRemove:
            return @"remove";
        case MROutboxEntryKindStatus:
        default:
            return @"status";
    }
}

+ (MROutboxEntryKind)kindForKindKey:(NSString *)key {
    if ([key isEqualToString:@"historyWhole"]) {
        return MROutboxEntryKindHistoryWhole;
    }
    if ([key isEqualToString:@"historyEpisode"]) {
        return MROutboxEntryKindHistoryEpisode;
    }
    if ([key isEqualToString:@"rating"]) {
        return MROutboxEntryKindRating;
    }
    if ([key isEqualToString:@"ratingRemove"]) {
        return MROutboxEntryKindRatingRemove;
    }
    if ([key isEqualToString:@"remove"]) {
        return MROutboxEntryKindRemove;
    }
    if ([key isEqualToString:@"status"]) {
        return MROutboxEntryKindStatus;
    }
    return (MROutboxEntryKind)-1;
}

+ (NSString *)typeKeyForType:(MRMediaType)type {
    switch (type) {
        case MRMediaTypeShow:
            return @"show";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movie";
    }
}

+ (MRMediaType)typeForTypeKey:(NSString *)key {
    if ([key isEqualToString:@"show"] || [key isEqualToString:@"shows"] ||
        [key isEqualToString:@"tv"]) {
        return MRMediaTypeShow;
    }
    if ([key isEqualToString:@"anime"]) {
        return MRMediaTypeAnime;
    }
    if ([key isEqualToString:@"movie"] || [key isEqualToString:@"movies"]) {
        return MRMediaTypeMovie;
    }
    return (MRMediaType)-1;
}

- (instancetype)initWithDictionaryRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    MROutboxEntryKind kind =
        [MROutboxEntry kindForKindKey:MROutboxStringValue(dictionary[@"kind"])];
    MRMediaType type =
        [MROutboxEntry typeForTypeKey:MROutboxStringValue(dictionary[@"type"])];
    NSInteger simklID = MROutboxIntegerValue(dictionary[@"simklID"]);
    if (kind == (MROutboxEntryKind)-1 || type == (MRMediaType)-1 || simklID <= 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        NSString *entryID = MROutboxStringValue(dictionary[@"id"]);
        _entryID = entryID.length > 0 ? [entryID copy]
                                      : [[NSUUID UUID] UUIDString];
        _createdAt = [MRDate dateFromISOString:
                         MROutboxStringValue(dictionary[@"createdAt"])];
        if (_createdAt == nil) {
            _createdAt = [NSDate date];
        }
        _kind = kind;
        _type = type;
        _simklID = simklID;
        _title = [MROutboxStringValue(dictionary[@"title"]) copy] ?: @"";
        _year = MROutboxIntegerValue(dictionary[@"year"]);

        NSMutableDictionary *externalIDs = [NSMutableDictionary dictionary];
        NSDictionary *ids = MROutboxDictionaryValue(dictionary[@"ids"]);
        for (id key in ids) {
            if ([key isKindOfClass:[NSString class]] &&
                ![(NSString *)key isEqualToString:@"simkl"]) {
                id value = [ids objectForKey:key];
                if (value != nil && value != (id)[NSNull null]) {
                    [externalIDs setObject:value forKey:key];
                }
            }
        }
        _externalIDs = externalIDs;

        _status = MRWatchStatusFromKey(MROutboxStringValue(dictionary[@"status"]));
        _rating = MROutboxIntegerValue(dictionary[@"rating"]);
        _season = MROutboxIntegerValue(dictionary[@"season"]);
        _episode = MROutboxIntegerValue(dictionary[@"episode"]);
        _previousStatus = MRWatchStatusFromKey(
            MROutboxStringValue(dictionary[@"previousStatus"]));
        _previousRating = MROutboxIntegerValue(dictionary[@"previousRating"]);
        _attempts = MROutboxIntegerValue(dictionary[@"attempts"]);
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *ids = [NSMutableDictionary dictionary];
    if ([self.externalIDs isKindOfClass:[NSDictionary class]]) {
        [ids addEntriesFromDictionary:self.externalIDs];
    }
    ids[@"simkl"] = @(self.simklID);

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"id"] = self.entryID != nil ? self.entryID : @"";
    NSString *createdAt = [MRDate isoStringFromDate:self.createdAt];
    dictionary[@"createdAt"] = createdAt != nil ? createdAt : [NSNull null];
    dictionary[@"kind"] = [MROutboxEntry kindKeyForKind:self.kind];
    dictionary[@"type"] = [MROutboxEntry typeKeyForType:self.type];
    dictionary[@"simklID"] = @(self.simklID);
    dictionary[@"title"] = self.title != nil ? self.title : @"";
    dictionary[@"year"] = @(self.year);
    dictionary[@"ids"] = ids;
    dictionary[@"status"] = self.status != MRWatchStatusNone
        ? MRWatchStatusKey(self.status) : [NSNull null];
    dictionary[@"rating"] = self.rating > 0 ? @(self.rating) : [NSNull null];
    dictionary[@"season"] = self.season > 0 ? @(self.season) : [NSNull null];
    dictionary[@"episode"] = self.episode > 0 ? @(self.episode) : [NSNull null];
    dictionary[@"previousStatus"] = self.previousStatus != MRWatchStatusNone
        ? MRWatchStatusKey(self.previousStatus) : [NSNull null];
    dictionary[@"previousRating"] = self.previousRating > 0
        ? @(self.previousRating) : [NSNull null];
    dictionary[@"attempts"] = @(self.attempts);
    return dictionary;
}

- (NSString *)itemIdentifier {
    return [NSString stringWithFormat:@"%ld:%ld", (long)self.type,
            (long)self.simklID];
}

- (BOOL)targetsSameItemAsEntry:(MROutboxEntry *)other {
    return other != nil && self.type == other.type && self.simklID == other.simklID;
}

@end
