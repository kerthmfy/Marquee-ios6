//
//  MRLibraryFilter.m
//  Marquee
//

#import "MRLibraryFilter.h"
#import "MRMediaItem.h"

const MRMediaType MRLibraryFilterAllTypes = (MRMediaType)-1;

static NSComparisonResult MRFilterCompareDatesDescending(NSDate *left, NSDate *right) {
    if (left == nil && right == nil) {
        return NSOrderedSame;
    }
    if (left == nil) {
        return NSOrderedDescending;
    }
    if (right == nil) {
        return NSOrderedAscending;
    }
    return [right compare:left];
}

@implementation MRLibraryFilter

+ (NSArray *)items:(NSArray *)items
              type:(MRMediaType)type
            status:(MRWatchStatus)status {
    NSMutableArray *result = [NSMutableArray array];
    for (id entry in items) {
        if (![entry isKindOfClass:[MRMediaItem class]]) {
            continue;
        }
        MRMediaItem *item = (MRMediaItem *)entry;
        if (type != MRLibraryFilterAllTypes && item.type != type) {
            continue;
        }
        if (status != MRWatchStatusNone && item.watchStatus != status) {
            continue;
        }
        [result addObject:item];
    }
    return result;
}

+ (NSArray *)sortedItems:(NSArray *)items {
    NSArray *source = [items isKindOfClass:[NSArray class]] ? items : @[];
    return [source sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
        MRMediaItem *leftItem = [left isKindOfClass:[MRMediaItem class]] ? left : nil;
        MRMediaItem *rightItem = [right isKindOfClass:[MRMediaItem class]] ? right : nil;
        if (leftItem == nil || rightItem == nil) {
            if (leftItem == rightItem) {
                return NSOrderedSame;
            }
            return leftItem == nil ? NSOrderedDescending : NSOrderedAscending;
        }

        NSComparisonResult result =
            MRFilterCompareDatesDescending(leftItem.lastWatchedAt, rightItem.lastWatchedAt);
        if (result != NSOrderedSame) {
            return result;
        }
        result =
            MRFilterCompareDatesDescending(leftItem.addedToWatchlistAt,
                                           rightItem.addedToWatchlistAt);
        if (result != NSOrderedSame) {
            return result;
        }

        result = [leftItem.title localizedCaseInsensitiveCompare:rightItem.title];
        if (result != NSOrderedSame) {
            return result;
        }
        if (leftItem.type != rightItem.type) {
            return leftItem.type < rightItem.type ? NSOrderedAscending : NSOrderedDescending;
        }
        if (leftItem.simklID != rightItem.simklID) {
            return leftItem.simklID < rightItem.simklID ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

@end
