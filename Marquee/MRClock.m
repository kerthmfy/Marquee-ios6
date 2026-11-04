//
//  MRClock.m
//  Marquee
//

#import "MRClock.h"
#import <dispatch/dispatch.h>

@implementation MRSystemClock

- (NSDate *)now {
    return [NSDate date];
}

- (void)after:(NSTimeInterval)delay perform:(void (^)(void))block {
    if (block == nil) {
        return;
    }
    if (delay < 0.0) {
        delay = 0.0;
    }
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(delay * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), block);
}

@end
