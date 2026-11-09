//
//  MRHiddenTitle.m
//  Marquee
//

#import "MRHiddenTitle.h"
#import "MRMediaItem.h"

@implementation MRHiddenTitle

+ (instancetype)hiddenTitleWithItem:(MRMediaItem *)item {
    if (item == nil || item.simklID <= 0) {
        return nil;
    }
    MRHiddenTitle *hidden = [[self alloc] init];
    hidden.type = item.type;
    hidden.simklID = item.simklID;
    hidden.title = item.title != nil ? item.title : @"";
    hidden.year = item.year;
    hidden.poster = item.poster != nil ? item.poster : @"";
    return hidden;
}

- (BOOL)matchesType:(MRMediaType)type simklID:(NSInteger)simklID {
    return self.type == type && self.simklID == simklID;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"type": @(self.type),
        @"simklID": @(self.simklID),
        @"title": self.title != nil ? self.title : @"",
        @"year": @(self.year),
        @"poster": self.poster != nil ? self.poster : @""
    };
}

+ (instancetype)hiddenTitleWithDictionaryRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSNumber *type = [dictionary objectForKey:@"type"];
    NSNumber *simklID = [dictionary objectForKey:@"simklID"];
    NSString *title = [dictionary objectForKey:@"title"];
    if (![type isKindOfClass:[NSNumber class]] ||
        ![simklID isKindOfClass:[NSNumber class]] ||
        [simklID integerValue] <= 0 ||
        ![title isKindOfClass:[NSString class]] || title.length == 0) {
        return nil;
    }

    NSInteger typeValue = [type integerValue];
    if (typeValue < MRMediaTypeMovie || typeValue > MRMediaTypeAnime) {
        return nil;
    }

    MRHiddenTitle *hidden = [[self alloc] init];
    hidden.type = (MRMediaType)typeValue;
    hidden.simklID = [simklID integerValue];
    hidden.title = title;
    NSNumber *year = [dictionary objectForKey:@"year"];
    hidden.year = [year isKindOfClass:[NSNumber class]] ? [year integerValue] : 0;
    NSString *poster = [dictionary objectForKey:@"poster"];
    hidden.poster = [poster isKindOfClass:[NSString class]] ? poster : @"";
    return hidden;
}

@end
