//
//  MRTokenStoreTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRTokenSession.h"
#import "MRTokenStore.h"

void MRRunTokenStoreTests(void) {
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];

    NSError *error = nil;
    MRAssertTrue([store loadSession:&error] == nil, @"empty store loads nothing");
    MRAssertTrue(error == nil, @"empty store has no error");

    NSDate *expires = [NSDate dateWithTimeIntervalSince1970:1793774400.0];
    MRTokenSession *session =
        [[MRTokenSession alloc] initWithAccessToken:@"ACCESS"
                                       refreshToken:@"REFRESH"
                                          expiresAt:expires
                                          accountID:0
                                        accountName:@""];

    MRAssertTrue([store saveSession:session error:&error], @"zero-account session saves");
    MRAssertTrue(error == nil, @"save has no error");

    MRTokenSession *loaded = [store loadSession:&error];
    MRAssertTrue(loaded != nil, @"zero-account session loads");
    MRAssertEqualObjects(loaded.accessToken, @"ACCESS", @"access token round-trips");
    MRAssertEqualObjects(loaded.refreshToken, @"REFRESH", @"refresh token round-trips");
    MRAssertEqualObjects(loaded.expiresAt, expires, @"expiry round-trips");
    MRAssertEqualIntegers(loaded.accountID, 0, @"zero account ID round-trips");
    MRAssertEqualObjects(loaded.accountName, @"", @"blank account name round-trips");

    MRTokenSession *named =
        [[MRTokenSession alloc] initWithAccessToken:@"A2"
                                       refreshToken:@"R2"
                                          expiresAt:[expires dateByAddingTimeInterval:60.0]
                                          accountID:12345
                                        accountName:@"Ada"];
    MRAssertTrue([store saveSession:named error:&error], @"named session saves");
    MRTokenSession *namedLoaded = [store loadSession:&error];
    MRAssertEqualObjects(namedLoaded.accessToken, @"A2", @"named access token round-trips");
    MRAssertEqualIntegers(namedLoaded.accountID, 12345, @"named account ID round-trips");
    MRAssertEqualObjects(namedLoaded.accountName, @"Ada", @"named account name round-trips");

    MRAssertTrue([store clearSession:&error], @"session clears");
    MRAssertTrue([store loadSession:NULL] == nil, @"cleared store loads nothing");
}
