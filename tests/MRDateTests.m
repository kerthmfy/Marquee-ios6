//
//  MRDateTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDate.h"

void MRRunDateTests(void) {
    // 2026-05-14T06:49:56Z
    const NSTimeInterval expectedSecond = 1778741396.0;

    NSDate *whole = [MRDate dateFromISOString:@"2026-05-14T06:49:56Z"];
    MRAssertTrue(whole != nil, @"parses whole-second ISO date");
    MRAssertTrue(floor([whole timeIntervalSince1970]) == expectedSecond,
                 @"whole-second timestamp");

    NSDate *fractional = [MRDate dateFromISOString:@"2026-05-14T06:49:56.123Z"];
    MRAssertTrue(fractional != nil, @"parses fractional ISO date");
    MRAssertTrue(floor([fractional timeIntervalSince1970]) == expectedSecond,
                 @"fractional timestamp shares the same second");
    MRAssertTrue(fabs([fractional timeIntervalSinceDate:whole] - 0.123) < 0.001,
                 @"fractional seconds are preserved");

    MRAssertTrue([MRDate dateFromISOString:nil] == nil, @"nil input returns nil");
    MRAssertTrue([MRDate dateFromISOString:@""] == nil, @"empty input returns nil");

    MRAssertEqualObjects([MRDate isoStringFromDate:whole],
                         @"2026-05-14T06:49:56Z",
                         @"iso string formatting");
    MRAssertTrue([MRDate isoStringFromDate:nil] == nil, @"nil date formats to nil");
}
