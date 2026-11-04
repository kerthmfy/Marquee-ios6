//
//  MRQuotaTrackerTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRQuotaTracker.h"

static NSString *MRCreateQuotaDirectory(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-quota-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

static void MRRemoveQuotaDirectory(NSString *path) {
    if (path != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static void MRRunQuotaInitialStateTest(void) {
    NSString *directory = MRCreateQuotaDirectory();
    MRQuotaTracker *tracker = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:42];

    MRAssertEqualIntegers(-1, tracker.limit, @"unknown limit starts at -1");
    MRAssertEqualIntegers(-1, tracker.remaining, @"unknown remaining starts at -1");
    MRAssertTrue(tracker.resetAt == nil, @"unknown reset starts nil");

    MRRemoveQuotaDirectory(directory);
}

static void MRRunQuotaHeaderTest(void) {
    NSString *directory = MRCreateQuotaDirectory();
    MRQuotaTracker *tracker = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:42];

    [tracker updateFromHeaders:@{ @"x-ratelimit-limit": @"500",
                                  @"X-RATELIMIT-REMAINING": @"499" }];

    MRAssertEqualIntegers(500, tracker.limit, @"reads limit case-insensitively");
    MRAssertEqualIntegers(499, tracker.remaining, @"reads remaining case-insensitively");
    MRAssertTrue(tracker.resetAt == nil, @"no reset without Retry-After");

    NSDate *before = [NSDate date];
    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500",
                                  @"X-RateLimit-Remaining": @"498",
                                  @"Retry-After": @"3600" }];
    NSTimeInterval resetDistance = [tracker.resetAt timeIntervalSinceDate:before];

    MRAssertTrue(resetDistance > 3500.0 && resetDistance < 3700.0,
                 @"numeric Retry-After is seconds from now, not a timestamp");
    MRAssertEqualIntegers(498, tracker.remaining, @"remaining updates with reset");

    MRRemoveQuotaDirectory(directory);
}

static void MRRunQuotaPreservesValuesTest(void) {
    NSString *directory = MRCreateQuotaDirectory();
    MRQuotaTracker *tracker = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:42];

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500",
                                  @"X-RateLimit-Remaining": @"12",
                                  @"Retry-After": @"120" }];
    NSDate *previousReset = tracker.resetAt;

    [tracker updateFromHeaders:@{}];

    MRAssertEqualIntegers(500, tracker.limit, @"absent headers preserve limit");
    MRAssertEqualIntegers(12, tracker.remaining, @"absent headers preserve remaining");
    MRAssertTrue([tracker.resetAt isEqualToDate:previousReset],
                 @"absent headers preserve reset date");

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"junk",
                                  @"X-RateLimit-Remaining": @"also-junk",
                                  @"Retry-After": @"Wed, 21 Oct 2015 07:28:00 GMT" }];

    MRAssertEqualIntegers(500, tracker.limit, @"malformed limit preserves previous");
    MRAssertEqualIntegers(12, tracker.remaining, @"malformed remaining preserves previous");
    MRAssertTrue([tracker.resetAt isEqualToDate:previousReset],
                 @"date-form Retry-After is malformed and preserves previous reset");

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500" }];
    MRAssertEqualIntegers(500, tracker.limit, @"limit-only header updates limit");
    MRAssertEqualIntegers(12, tracker.remaining,
                          @"limit-only header never fabricates remaining");

    MRRemoveQuotaDirectory(directory);
}

static void MRRunQuotaPersistenceTest(void) {
    NSString *directory = MRCreateQuotaDirectory();
    MRQuotaTracker *tracker = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:7];

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500",
                                  @"X-RateLimit-Remaining": @"75" }];

    MRQuotaTracker *reloaded = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:7];
    MRAssertEqualIntegers(500, reloaded.limit, @"limit persists");
    MRAssertEqualIntegers(75, reloaded.remaining, @"remaining persists");

    MRQuotaTracker *otherAccount = [[MRQuotaTracker alloc] initWithDirectory:directory
                                                                  accountID:8];
    MRAssertEqualIntegers(-1, otherAccount.limit, @"other account starts without values");
    MRAssertEqualIntegers(-1, otherAccount.remaining, @"other account starts without values");

    MRRemoveQuotaDirectory(directory);
}

static void MRRunQuotaNotificationTest(void) {
    NSString *directory = MRCreateQuotaDirectory();
    MRQuotaTracker *tracker = [[MRQuotaTracker alloc] initWithDirectory:directory accountID:42];

    __block NSInteger notifications = 0;
    __block BOOL notificationOnMainThread = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRQuotaDidChangeNotification
                    object:tracker
                     queue:nil
                usingBlock:^(NSNotification *note) {
        notifications += 1;
        notificationOnMainThread = [NSThread isMainThread];
    }];

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500",
                                  @"X-RateLimit-Remaining": @"10",
                                  @"Retry-After": @"90" }];
    MRAssertEqualIntegers(1, notifications, @"changed quota posts a notification");
    MRAssertTrue(notificationOnMainThread, @"notification posts on the main thread");

    [tracker updateFromHeaders:@{ @"X-RateLimit-Limit": @"500",
                                  @"X-RateLimit-Remaining": @"10" }];
    MRAssertEqualIntegers(1, notifications, @"unchanged quota does not post");

    [tracker updateFromHeaders:@{ @"X-RateLimit-Remaining": @"9" }];
    MRAssertEqualIntegers(2, notifications, @"changed remaining posts");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [tracker updateFromHeaders:@{ @"X-RateLimit-Remaining": @"8" }];
    });
    MRAssertTrue(MRRunUntil(^BOOL { return notifications >= 3; }, 2.0),
                 @"background change posts notification");
    MRAssertTrue(notificationOnMainThread,
                 @"background change posts notification on the main thread");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    MRRemoveQuotaDirectory(directory);
}

void MRRunQuotaTrackerTests(void) {
    MRRunQuotaInitialStateTest();
    MRRunQuotaHeaderTest();
    MRRunQuotaPreservesValuesTest();
    MRRunQuotaPersistenceTest();
    MRRunQuotaNotificationTest();
}
