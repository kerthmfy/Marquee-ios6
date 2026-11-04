//
//  MRTestSupport.h
//  Marquee tests
//

#import <Foundation/Foundation.h>

// Assertions record a failure and print a diagnostic, but keep running so a
// single run reports every problem it finds.
void MRAssertTrue(BOOL condition, NSString *message);
void MRAssertEqualObjects(id expected, id actual, NSString *message);
void MRAssertEqualIntegers(NSInteger expected, NSInteger actual, NSString *message);

// Reads tests/fixtures/<name>.json relative to the repository root.
// A ".json" suffix is optional.
NSDictionary *MRFixture(NSString *name);

// main.m uses these to report a non-zero exit status.
void MRTestBeginSuite(NSString *name);
NSUInteger MRTestFailureCount(void);
