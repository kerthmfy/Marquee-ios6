//
//  MRTestSupport.h
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRClock.h"

// Assertions record a failure and print a diagnostic, but keep running so a
// single run reports every problem it finds.
void MRAssertTrue(BOOL condition, NSString *message);
void MRAssertEqualObjects(id expected, id actual, NSString *message);
void MRAssertEqualIntegers(NSInteger expected, NSInteger actual, NSString *message);

// Reads tests/fixtures/<name>.json relative to the repository root.
// A ".json" suffix is optional.
NSDictionary *MRFixture(NSString *name);

// Pumps the main run loop in short slices until the condition is true or the
// timeout expires. Returns YES when the condition became true. Never sleeps.
BOOL MRRunUntil(BOOL (^condition)(void), NSTimeInterval timeout);

// A deterministic clock for retry tests. Blocks are recorded and run in
// fire-date order when -advanceBy: is called. No wall-clock time is used.
@interface MRFakeClock : NSObject <MRClock>
- (void)advanceBy:(NSTimeInterval)seconds;
@end

// main.m uses these to report a non-zero exit status.
void MRTestBeginSuite(NSString *name);
NSUInteger MRTestFailureCount(void);
