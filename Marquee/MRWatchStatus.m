//
//  MRWatchStatus.m
//  Marquee
//

#import "MRWatchStatus.h"

MRWatchStatus MRWatchStatusFromKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) {
        return MRWatchStatusNone;
    }
    NSString *normalized = [key lowercaseString];
    if ([normalized isEqualToString:@"watching"]) {
        return MRWatchStatusWatching;
    }
    if ([normalized isEqualToString:@"plantowatch"] ||
        [normalized isEqualToString:@"plan-to-watch"] ||
        [normalized isEqualToString:@"plan_to_watch"]) {
        return MRWatchStatusPlanToWatch;
    }
    if ([normalized isEqualToString:@"completed"]) {
        return MRWatchStatusCompleted;
    }
    if ([normalized isEqualToString:@"hold"]) {
        return MRWatchStatusHold;
    }
    if ([normalized isEqualToString:@"dropped"]) {
        return MRWatchStatusDropped;
    }
    return MRWatchStatusNone;
}

NSString *MRWatchStatusKey(MRWatchStatus status) {
    switch (status) {
        case MRWatchStatusWatching:
            return @"watching";
        case MRWatchStatusPlanToWatch:
            return @"plantowatch";
        case MRWatchStatusCompleted:
            return @"completed";
        case MRWatchStatusHold:
            return @"hold";
        case MRWatchStatusDropped:
            return @"dropped";
        case MRWatchStatusNone:
        default:
            return @"";
    }
}

NSString *MRWatchStatusDisplayName(MRWatchStatus status) {
    switch (status) {
        case MRWatchStatusWatching:
            return @"Watching";
        case MRWatchStatusPlanToWatch:
            return @"Plan to Watch";
        case MRWatchStatusCompleted:
            return @"Completed";
        case MRWatchStatusHold:
            return @"On Hold";
        case MRWatchStatusDropped:
            return @"Dropped";
        case MRWatchStatusNone:
        default:
            return @"None";
    }
}
