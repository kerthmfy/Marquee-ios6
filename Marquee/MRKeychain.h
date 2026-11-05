//
//  MRKeychain.h
//  Marquee
//

#import <Foundation/Foundation.h>

extern NSString *const MRKeychainService;
extern NSString *const MRKeychainAccountAccessToken;
extern NSString *const MRKeychainAccountRefreshToken;
extern NSString *const MRKeychainAccountExpiresAt;
extern NSString *const MRKeychainAccountID;
extern NSString *const MRKeychainAccountName;

// A small wrapper over the generic-password Keychain items Marquee owns. It
// never logs or describes the stored values.
@interface MRKeychain : NSObject

+ (NSString *)stringForAccount:(NSString *)account error:(NSError **)error;
+ (BOOL)setString:(NSString *)string forAccount:(NSString *)account error:(NSError **)error;
+ (BOOL)removeItemForAccount:(NSString *)account error:(NSError **)error;
+ (BOOL)removeAllItems:(NSError **)error;

@end
