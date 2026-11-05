//
//  MRTokenSession.m
//  Marquee
//

#import "MRTokenSession.h"

@implementation MRTokenSession

- (instancetype)initWithAccessToken:(NSString *)accessToken
                       refreshToken:(NSString *)refreshToken
                          expiresAt:(NSDate *)expiresAt
                          accountID:(NSInteger)accountID
                        accountName:(NSString *)accountName {
    self = [super init];
    if (self) {
        _accessToken = [accessToken copy] ?: @"";
        _refreshToken = [refreshToken copy] ?: @"";
        _expiresAt = expiresAt;
        _accountID = accountID;
        _accountName = [accountName copy] ?: @"";
    }
    return self;
}

@end
