//
//  MRQuotaTracker.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Posted on the main thread when the limit, remaining count, or reset date
// actually changes. The notification object is the tracker.
extern NSString *const MRQuotaDidChangeNotification;

// Tracks Simkl's per-account request quota. Values are persisted per account so
// a relaunch does not forget the last known count. An unknown value is -1; the
// tracker never invents a remaining count when headers are absent.
@interface MRQuotaTracker : NSObject

@property (nonatomic, readonly) NSInteger limit;
@property (nonatomic, readonly) NSInteger remaining;
@property (nonatomic, strong, readonly) NSDate *resetAt;

// The app's own network request count for the current local calendar day. It is
// persisted per account and resets when the day changes.
@property (nonatomic, readonly) NSInteger requestsToday;

- (instancetype)initWithDirectory:(NSString *)directory accountID:(NSInteger)accountID;

// Counts one outbound API request. Cached responses do not count.
- (void)recordRequest;

// Reads X-RateLimit-Limit and X-RateLimit-Remaining case-insensitively. A
// numeric Retry-After is treated as seconds from now. Missing or malformed
// values leave the previous value untouched.
- (void)updateFromHeaders:(NSDictionary *)headers;

@end
