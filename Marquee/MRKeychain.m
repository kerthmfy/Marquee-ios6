//
//  MRKeychain.m
//  Marquee
//

#import "MRKeychain.h"

#import <Security/Security.h>

NSString *const MRKeychainService = @"com.marquee.app.simkl";
NSString *const MRKeychainAccountAccessToken = @"access_token";
NSString *const MRKeychainAccountRefreshToken = @"refresh_token";
NSString *const MRKeychainAccountExpiresAt = @"expires_at";
NSString *const MRKeychainAccountID = @"account_id";
NSString *const MRKeychainAccountName = @"account_name";

static NSError *MRKeychainError(OSStatus status) {
    NSString *message = [NSString stringWithFormat:@"Keychain error %ld", (long)status];
    return [NSError errorWithDomain:@"MRKeychainErrorDomain"
                               code:(NSInteger)status
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSMutableDictionary *MRKeychainBaseQuery(NSString *account) {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    [query setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
    [query setObject:MRKeychainService forKey:(__bridge id)kSecAttrService];
    if (account.length > 0) {
        [query setObject:account forKey:(__bridge id)kSecAttrAccount];
    }
    return query;
}

@implementation MRKeychain

+ (NSString *)stringForAccount:(NSString *)account error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (account.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MRKeychainErrorDomain"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Missing account" }];
        }
        return nil;
    }

    NSMutableDictionary *query = MRKeychainBaseQuery(account);
    [query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    [query setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        return nil;
    }
    if (status != errSecSuccess) {
        if (error != NULL) {
            *error = MRKeychainError(status);
        }
        return nil;
    }

    NSData *data = (__bridge_transfer NSData *)result;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil && error != NULL) {
        *error = [NSError errorWithDomain:@"MRKeychainErrorDomain"
                                     code:2
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 @"Keychain value is not text" }];
    }
    return string;
}

+ (BOOL)setString:(NSString *)string forAccount:(NSString *)account error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (account.length == 0 || data == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MRKeychainErrorDomain"
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"Could not encode Keychain value" }];
        }
        return NO;
    }

    NSMutableDictionary *query = MRKeychainBaseQuery(account);
    NSDictionary *changes = @{ (__bridge id)kSecValueData: data };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)changes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = MRKeychainBaseQuery(account);
        [item setObject:data forKey:(__bridge id)kSecValueData];
        [item setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock
                 forKey:(__bridge id)kSecAttrAccessible];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }

    if (status != errSecSuccess) {
        if (error != NULL) {
            *error = MRKeychainError(status);
        }
        return NO;
    }
    return YES;
}

+ (BOOL)removeItemForAccount:(NSString *)account error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (account.length == 0) {
        return YES;
    }

    NSMutableDictionary *query = MRKeychainBaseQuery(account);
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status == errSecSuccess || status == errSecItemNotFound) {
        return YES;
    }
    if (error != NULL) {
        *error = MRKeychainError(status);
    }
    return NO;
}

+ (BOOL)removeAllItems:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    NSMutableDictionary *query = MRKeychainBaseQuery(nil);
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status == errSecSuccess || status == errSecItemNotFound) {
        return YES;
    }
    if (error != NULL) {
        *error = MRKeychainError(status);
    }
    return NO;
}

@end
