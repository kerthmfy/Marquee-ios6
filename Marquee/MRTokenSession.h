//
//  MRTokenSession.h
//  Marquee
//

#import <Foundation/Foundation.h>

// The value stored in the Keychain after a successful device-flow exchange.
// accountID is zero until /users/settings reports the account identity.
@interface MRTokenSession : NSObject

@property (nonatomic, copy, readonly) NSString *accessToken;
@property (nonatomic, copy, readonly) NSString *refreshToken;
@property (nonatomic, strong, readonly) NSDate *expiresAt;
@property (nonatomic, assign, readonly) NSInteger accountID;
@property (nonatomic, copy, readonly) NSString *accountName;

- (instancetype)initWithAccessToken:(NSString *)accessToken
                       refreshToken:(NSString *)refreshToken
                          expiresAt:(NSDate *)expiresAt
                          accountID:(NSInteger)accountID
                        accountName:(NSString *)accountName;

@end
