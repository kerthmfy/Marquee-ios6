//
//  MRDeviceCode.m
//  Marquee
//

#import "MRDeviceCode.h"

@implementation MRDeviceCode

- (instancetype)initWithDeviceCode:(NSString *)deviceCode
                          userCode:(NSString *)userCode
                   verificationURI:(NSString *)verificationURI
           verificationURIComplete:(NSString *)verificationURIComplete
                         expiresAt:(NSDate *)expiresAt
                          interval:(NSTimeInterval)interval {
    self = [super init];
    if (self) {
        _deviceCode = [deviceCode copy] ?: @"";
        _userCode = [userCode copy] ?: @"";
        _verificationURI = [verificationURI copy] ?: @"";
        _verificationURIComplete = [verificationURIComplete copy] ?: @"";
        _expiresAt = expiresAt;
        _interval = interval > 0.0 ? interval : 5.0;
    }
    return self;
}

@end
