//
//  MRDeviceCode.h
//  Marquee
//

#import <Foundation/Foundation.h>

// The values returned by POST /oauth2/device. expiresAt is an absolute date
// computed from the response's expires_in; interval is in seconds.
@interface MRDeviceCode : NSObject

@property (nonatomic, copy, readonly) NSString *deviceCode;
@property (nonatomic, copy, readonly) NSString *userCode;
@property (nonatomic, copy, readonly) NSString *verificationURI;
@property (nonatomic, copy, readonly) NSString *verificationURIComplete;
@property (nonatomic, strong, readonly) NSDate *expiresAt;
@property (nonatomic, assign, readonly) NSTimeInterval interval;

- (instancetype)initWithDeviceCode:(NSString *)deviceCode
                          userCode:(NSString *)userCode
                   verificationURI:(NSString *)verificationURI
           verificationURIComplete:(NSString *)verificationURIComplete
                         expiresAt:(NSDate *)expiresAt
                          interval:(NSTimeInterval)interval;

@end
