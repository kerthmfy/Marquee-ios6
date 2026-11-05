//
//  MRKeychainTokenStore.m
//  Marquee
//

#import "MRKeychainTokenStore.h"

#import "MRDate.h"
#import "MRKeychain.h"
#import "MRTokenSession.h"

@implementation MRKeychainTokenStore

- (MRTokenSession *)loadSession:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    NSError *readError = nil;
    NSString *accessToken = [MRKeychain stringForAccount:MRKeychainAccountAccessToken
                                                   error:&readError];
    if (accessToken == nil) {
        if (error != NULL && readError != nil) {
            *error = readError;
        }
        return nil;
    }

    NSString *refreshToken = [MRKeychain stringForAccount:MRKeychainAccountRefreshToken
                                                    error:&readError];
    if (refreshToken == nil) {
        if (error != NULL && readError != nil) {
            *error = readError;
        }
        return nil;
    }

    NSString *expiresString = [MRKeychain stringForAccount:MRKeychainAccountExpiresAt
                                                     error:&readError];
    if (readError != nil) {
        if (error != NULL) {
            *error = readError;
        }
        return nil;
    }
    NSDate *expiresAt = [MRDate dateFromISOString:expiresString];

    NSString *accountIDString = [MRKeychain stringForAccount:MRKeychainAccountID
                                                       error:&readError];
    if (readError != nil) {
        if (error != NULL) {
            *error = readError;
        }
        return nil;
    }

    NSString *accountName = [MRKeychain stringForAccount:MRKeychainAccountName
                                                   error:&readError];
    if (readError != nil) {
        if (error != NULL) {
            *error = readError;
        }
        return nil;
    }

    return [[MRTokenSession alloc] initWithAccessToken:accessToken
                                          refreshToken:refreshToken
                                             expiresAt:expiresAt
                                             accountID:[accountIDString integerValue]
                                           accountName:accountName ?: @""];
}

- (BOOL)saveSession:(MRTokenSession *)session error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (session == nil ||
        session.accessToken.length == 0 ||
        session.refreshToken.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MRKeychainTokenStore"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"Incomplete token session" }];
        }
        return NO;
    }

    NSString *expiresAt = session.expiresAt != nil
        ? [MRDate isoStringFromDate:session.expiresAt]
        : @"";
    NSArray *accounts = @[
        MRKeychainAccountAccessToken,
        MRKeychainAccountRefreshToken,
        MRKeychainAccountExpiresAt,
        MRKeychainAccountID,
        MRKeychainAccountName
    ];
    NSArray *values = @[
        session.accessToken,
        session.refreshToken,
        expiresAt ?: @"",
        [NSString stringWithFormat:@"%ld", (long)session.accountID],
        session.accountName ?: @""
    ];

    NSError *writeError = nil;
    for (NSUInteger index = 0; index < accounts.count; index += 1) {
        NSString *account = [accounts objectAtIndex:index];
        NSString *value = [values objectAtIndex:index];
        if (![MRKeychain setString:value forAccount:account error:&writeError]) {
            // Do not leave a partial session behind.
            [MRKeychain removeAllItems:NULL];
            if (error != NULL && writeError != nil) {
                *error = writeError;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)clearSession:(NSError **)error {
    return [MRKeychain removeAllItems:error];
}

@end
