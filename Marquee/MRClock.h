//
//  MRClock.h
//  Marquee
//

#import <Foundation/Foundation.h>

@protocol MRClock <NSObject>
- (NSDate *)now;
- (void)after:(NSTimeInterval)delay perform:(void (^)(void))block;
@end

// Production clock. Tests inject MRFakeClock instead so they never wait on a
// real wall-clock interval.
@interface MRSystemClock : NSObject <MRClock>
@end
