//
//  MREpisode.m
//  Marquee
//

#import "MREpisode.h"

static NSString *MRNullableString(id value) {
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

static BOOL MRHasValue(id value) {
    return value != nil && value != [NSNull null];
}

static NSDate *MRDateFromAirDateString(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || string.length < 10) {
        return nil;
    }

    // Simkl air dates include a timezone offset. The guide only needs the
    // calendar day, so parse the date prefix in UTC.
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd"];
    return [formatter dateFromString:[string substringToIndex:10]];
}

@implementation MREpisode

+ (instancetype)episodeWithDictionary:(NSDictionary *)dictionary
                                 type:(MRMediaType)type {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    MREpisode *episode = [[self alloc] init];
    id seasonValue = dictionary[@"season"];
    BOOL hasSeason = MRHasValue(seasonValue);
    episode.season = hasSeason ? MRIntegerValue(seasonValue) : 1;
    episode.number = MRIntegerValue(dictionary[@"episode"]);
    episode.title = MRNullableString(dictionary[@"title"]) ?: @"";
    episode.summary = MRNullableString(dictionary[@"description"]) ?: @"";
    episode.runtime = MRIntegerValue(dictionary[@"runtime"]);

    NSString *image = MRNullableString(dictionary[@"img"]);
    episode.imagePath = image.length > 0 ? image : nil;

    episode.airDate = MRDateFromAirDateString(MRNullableString(dictionary[@"date"]));

    NSString *episodeType = MRNullableString(dictionary[@"type"]);
    episode.special = [episodeType isEqualToString:@"special"] ||
        (hasSeason && episode.season == 0);

    id airedValue = dictionary[@"aired"];
    episode.aired = [airedValue isKindOfClass:[NSNumber class]]
        ? [airedValue boolValue]
        : YES;
    return episode;
}

+ (NSArray *)episodesWithDictionaries:(NSArray *)dictionaries
                                 type:(MRMediaType)type {
    if (![dictionaries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *episodes = [NSMutableArray array];
    for (id entry in dictionaries) {
        MREpisode *episode = [self episodeWithDictionary:entry type:type];
        if (episode == nil || episode.number <= 0) {
            continue;
        }
        [episodes addObject:episode];
    }

    [episodes sortUsingComparator:^NSComparisonResult(MREpisode *left,
                                                      MREpisode *right) {
        if (left.special != right.special) {
            return left.special ? NSOrderedDescending : NSOrderedAscending;
        }
        if (left.season != right.season) {
            return left.season < right.season ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.number != right.number) {
            return left.number < right.number ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return episodes;
}

- (NSString *)codeText {
    if (self.special) {
        return [NSString stringWithFormat:@"Special %ld", (long)self.number];
    }
    if (self.season > 0) {
        return [NSString stringWithFormat:@"S%ldE%ld",
                (long)self.season, (long)self.number];
    }
    return [NSString stringWithFormat:@"E%ld", (long)self.number];
}

@end
