//
//  MRDeviceFlowTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRConfig.h"
#import "MRDeviceCode.h"
#import "MRDeviceFlow.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPResponse.h"
#import "MRSimklAuth.h"
#import "MRStubHTTPClient.h"
#import "MRTokenSession.h"
#import "MRTokenStore.h"

#pragma mark - Helpers

static MRDiagnostics *MRTestDiagnostics(void) {
    return [[MRDiagnostics alloc] initWithDirectory:nil];
}

static MRHTTPResponse *MRJSONResponse(NSInteger statusCode, NSDictionary *object) {
    NSData *data = nil;
    if (object != nil) {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    }
    return [MRHTTPResponse responseWithStatusCode:statusCode
                                          headers:@{ @"Content-Type": @"application/json" }
                                             data:data
                                   transportError:nil];
}

static MRHTTPResponse *MRDeviceStartResponse(void) {
    return MRJSONResponse(200, @{
        @"device_code": @"DEVICE-SECRET",
        @"user_code": @"BDWP-HQPK",
        @"verification_uri": @"https://simkl.com/pin",
        @"verification_uri_complete": @"https://simkl.com/pin?user_code=BDWP-HQPK",
        @"expires_in": @900,
        @"interval": @5
    });
}

static MRHTTPResponse *MRTokenResponse(void) {
    return MRJSONResponse(200, @{
        @"access_token": @"ACCESS-SECRET",
        @"refresh_token": @"REFRESH-SECRET",
        @"expires_in": @604800
    });
}

static NSString *MRFormDecode(NSString *value) {
    NSString *decoded = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return decoded != nil ? decoded : value;
}

static NSDictionary *MRFormFields(MRHTTPRequest *request) {
    if (request.body.length == 0) {
        return @{};
    }
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *pair in [body componentsSeparatedByString:@"&"]) {
        NSArray *parts = [pair componentsSeparatedByString:@"="];
        NSString *key = [parts objectAtIndex:0];
        NSString *value = parts.count > 1 ? [parts objectAtIndex:1] : @"";
        [fields setObject:MRFormDecode(value) forKey:MRFormDecode(key)];
    }
    return fields;
}

static MRDeviceCode *MRStartDeviceFlow(MRDeviceFlow *flow, MRStubHTTPClient *http) {
    [http enqueueResponse:MRDeviceStartResponse()];
    __block MRDeviceCode *code = nil;
    __block NSError *error = nil;
    [flow startWithCompletion:^(MRDeviceCode *value, NSError *valueError) {
        code = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return code != nil || error != nil;
    }, 2.0), @"device start completes");
    MRAssertTrue(error == nil, @"device start has no error");
    return code;
}

static MRTokenSession *MRRestore(MRSimklAuth *auth, NSError **outError) {
    __block MRTokenSession *session = nil;
    __block NSError *error = nil;
    [auth restoreWithCompletion:^(MRTokenSession *value, NSError *valueError) {
        session = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return session != nil || error != nil;
    }, 2.0), @"restore completes");
    if (outError != NULL) {
        *outError = error;
    }
    return session;
}

#pragma mark - Deferred HTTP client

@interface MRDeferredHTTPTask : NSObject <MRHTTPTask>
@end

@implementation MRDeferredHTTPTask
- (void)cancel {
}
@end

@interface MRDeferredHTTPClient : NSObject <MRHTTPClient>
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, copy) void (^pendingCompletion)(MRHTTPResponse *response);
- (void)respondWithResponse:(MRHTTPResponse *)response;
@end

@implementation MRDeferredHTTPClient

- (id)init {
    self = [super init];
    if (self) {
        _requests = [NSMutableArray array];
    }
    return self;
}

- (id<MRHTTPTask>)sendRequest:(MRHTTPRequest *)request
                   completion:(void (^)(MRHTTPResponse *response))completion {
    if (request != nil) {
        [self.requests addObject:[request copy]];
    }
    self.pendingCompletion = completion;
    return [[MRDeferredHTTPTask alloc] init];
}

- (void)respondWithResponse:(MRHTTPResponse *)response {
    void (^completion)(MRHTTPResponse *) = self.pendingCompletion;
    self.pendingCompletion = nil;
    if (completion != nil) {
        completion(response);
    }
}

@end

@interface MRFailingTokenStore : NSObject <MRTokenStore>
@property (nonatomic, strong) MRTokenSession *session;
@end

@implementation MRFailingTokenStore

- (MRTokenSession *)loadSession:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    return self.session;
}

- (BOOL)saveSession:(MRTokenSession *)session error:(NSError **)error {
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"MRFailingTokenStore"
                                     code:1
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 @"Could not securely store your session" }];
    }
    return NO;
}

- (BOOL)clearSession:(NSError **)error {
    self.session = nil;
    if (error != NULL) {
        *error = nil;
    }
    return YES;
}

@end

#pragma mark - Device flow

static void MRDeviceStartTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];

    MRDeviceCode *code = MRStartDeviceFlow(flow, http);
    MRAssertTrue(code != nil, @"start returns a device code");
    MRAssertEqualObjects(code.deviceCode, @"DEVICE-SECRET", @"device code parsed");
    MRAssertEqualObjects(code.userCode, @"BDWP-HQPK", @"user code parsed");
    MRAssertEqualObjects(code.verificationURI, @"https://simkl.com/pin", @"verification uri parsed");
    MRAssertEqualObjects(code.verificationURIComplete,
                         @"https://simkl.com/pin?user_code=BDWP-HQPK",
                         @"complete verification uri parsed");
    MRAssertTrue([code.expiresAt timeIntervalSinceDate:[clock now]] == 900.0,
                 @"expires_in becomes an absolute date");
    MRAssertTrue(code.interval == 5.0, @"interval parsed");

    MRAssertEqualIntegers(http.requestCount, 1, @"one start request");
    MRHTTPRequest *request = [http requestAtIndex:0];
    MRAssertEqualObjects(request.method, @"POST", @"start uses POST");
    MRAssertTrue([request.URL rangeOfString:@"/oauth2/device"].location != NSNotFound,
                 @"start posts to /oauth2/device");
    MRAssertEqualObjects([request.headers objectForKey:@"Content-Type"],
                         @"application/x-www-form-urlencoded",
                         @"start sends a form");
    NSDictionary *fields = MRFormFields(request);
    MRAssertEqualObjects([fields objectForKey:@"client_id"], MR_SIMKL_CLIENT_ID,
                         @"start form carries the client id");
    MRAssertEqualObjects([fields objectForKey:@"scope"], @"media:read media:write",
                         @"start form carries the scope");
}

static void MRDevicePollRequestTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [http enqueueResponse:MRTokenResponse()];
    __block MRTokenSession *session = nil;
    __block NSError *error = nil;
    [flow pollWithCompletion:^(MRTokenSession *value, NSError *valueError) {
        session = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return session != nil || error != nil;
    }, 2.0), @"poll completes");
    MRAssertTrue(error == nil, @"poll has no error");
    MRAssertEqualObjects(session.accessToken, @"ACCESS-SECRET", @"access token parsed");
    MRAssertEqualObjects(session.refreshToken, @"REFRESH-SECRET", @"refresh token parsed");
    MRAssertEqualIntegers(session.accountID, 0, @"poll session has no account id yet");
    MRAssertTrue([session.expiresAt timeIntervalSinceDate:[clock now]] == 604800.0,
                 @"token expires_in becomes an absolute date");

    MRAssertEqualIntegers(http.requestCount, 2, @"start plus one poll");
    MRHTTPRequest *request = [http requestAtIndex:1];
    MRAssertEqualObjects(request.method, @"POST", @"poll uses POST");
    MRAssertTrue([request.URL rangeOfString:@"/oauth2/token"].location != NSNotFound,
                 @"poll posts to /oauth2/token");
    MRAssertEqualObjects([request.headers objectForKey:@"Content-Type"],
                         @"application/x-www-form-urlencoded",
                         @"poll sends a form");
    NSDictionary *fields = MRFormFields(request);
    MRAssertEqualObjects([fields objectForKey:@"grant_type"],
                         @"urn:ietf:params:oauth:grant-type:device_code",
                         @"poll grant type");
    MRAssertEqualObjects([fields objectForKey:@"client_id"], MR_SIMKL_CLIENT_ID,
                         @"poll client id");
    MRAssertEqualObjects([fields objectForKey:@"device_code"], @"DEVICE-SECRET",
                         @"poll device code");
}

static void MRDeviceAuthorizationPendingTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [http enqueueResponse:MRJSONResponse(400, @{ @"error": @"authorization_pending" })];
    __block BOOL completed = NO;
    [flow pollWithCompletion:^(MRTokenSession *session, NSError *error) {
        completed = YES;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 2;
    }, 2.0), @"pending response was processed");
    MRAssertTrue(!completed, @"pending does not complete the flow");

    [http enqueueResponse:MRJSONResponse(400, @{ @"error": @"authorization_pending" })];
    [clock advanceBy:4.9];
    MRAssertTrue(!MRRunUntil(^BOOL {
        return http.requestCount >= 3;
    }, 0.05), @"no poll before the current interval elapses");

    [clock advanceBy:0.1];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 3;
    }, 2.0), @"pending polls again after the current interval");
    MRAssertTrue(!completed, @"still pending");
}

static void MRDeviceSlowDownTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [http enqueueResponse:MRJSONResponse(400, @{ @"error": @"slow_down" })];
    __block BOOL completed = NO;
    [flow pollWithCompletion:^(MRTokenSession *session, NSError *error) {
        completed = YES;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 2;
    }, 2.0), @"slow_down response was processed");
    MRAssertTrue(!completed, @"slow_down keeps polling");

    [clock advanceBy:9.0];
    MRAssertTrue(!MRRunUntil(^BOOL {
        return http.requestCount >= 3;
    }, 0.05), @"slow_down adds five seconds to the original interval");

    [http enqueueResponse:MRJSONResponse(400, @{ @"error": @"authorization_pending" })];
    [clock advanceBy:1.0];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 3;
    }, 2.0), @"poll resumes at the increased interval");
    MRAssertTrue(!completed, @"still waiting");
}

static void MRDeviceExpiredTokenTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [http enqueueResponse:MRJSONResponse(400, @{ @"error": @"expired_token" })];
    __block NSError *error = nil;
    [flow pollWithCompletion:^(MRTokenSession *session, NSError *valueError) {
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"expired token completes");
    MRAssertEqualIntegers([MRError kindForError:error], MRErrorKindAuthExpired,
                          @"expired token maps to auth expired");

    [clock advanceBy:60.0];
    MRAssertTrue(!MRRunUntil(^BOOL {
        return http.requestCount >= 3;
    }, 0.05), @"expired flow does not poll again");
}

static void MRDeviceInvalidClientTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [http enqueueResponse:MRJSONResponse(401, @{ @"error": @"invalid_client" })];
    __block NSError *error = nil;
    [flow pollWithCompletion:^(MRTokenSession *session, NSError *valueError) {
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"invalid client completes");
    MRAssertEqualIntegers([MRError kindForError:error], MRErrorKindClientRejected,
                          @"invalid client maps to client rejected");
}

static void MRDeviceDeadlineTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRDeviceFlow *flow = [[MRDeviceFlow alloc] initWithHTTPClient:http
                                                      diagnostics:MRTestDiagnostics()
                                                            clock:clock];
    MRStartDeviceFlow(flow, http);

    [clock advanceBy:900.0];
    __block NSError *error = nil;
    [flow pollWithCompletion:^(MRTokenSession *session, NSError *valueError) {
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"deadline completes");
    MRAssertEqualIntegers([MRError kindForError:error], MRErrorKindAuthExpired,
                          @"deadline maps to auth expired");
    MRAssertEqualIntegers(http.requestCount, 1,
                          @"no token poll is sent after the fifteen-minute deadline");
}

#pragma mark - Token refresh

static void MRAuthSingleRefreshTest(void) {
    MRDeferredHTTPClient *http = [[MRDeferredHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];

    MRTokenSession *stored =
        [[MRTokenSession alloc] initWithAccessToken:@"OLD-ACCESS"
                                       refreshToken:@"OLD-REFRESH"
                                          expiresAt:[[clock now] dateByAddingTimeInterval:60.0]
                                          accountID:12345
                                        accountName:@"Ada"];
    [store saveSession:stored error:NULL];

    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];
    MRAssertTrue(MRRestore(auth, NULL) != nil, @"restore loads the stored session");

    __block NSString *firstToken = nil;
    __block NSString *secondToken = nil;
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [auth validAccessTokenWithCompletion:^(NSString *token, NSError *error) {
        firstToken = token;
        firstError = error;
    }];
    [auth validAccessTokenWithCompletion:^(NSString *token, NSError *error) {
        secondToken = token;
        secondError = error;
    }];

    MRAssertEqualIntegers(http.requests.count, 1,
                          @"concurrent expiring calls send one refresh request");
    MRAssertTrue(firstToken == nil && secondToken == nil, @"waiters wait for the refresh");

    MRHTTPRequest *request = [http.requests lastObject];
    MRAssertTrue([request.URL rangeOfString:@"/oauth2/token"].location != NSNotFound,
                 @"refresh posts to /oauth2/token");
    NSDictionary *fields = MRFormFields(request);
    MRAssertEqualObjects([fields objectForKey:@"grant_type"], @"refresh_token",
                         @"refresh grant type");
    MRAssertEqualObjects([fields objectForKey:@"client_id"], MR_SIMKL_CLIENT_ID,
                         @"refresh client id");
    MRAssertEqualObjects([fields objectForKey:@"refresh_token"], @"OLD-REFRESH",
                         @"refresh token");

    [http respondWithResponse:MRJSONResponse(200, @{
        @"access_token": @"NEW-ACCESS",
        @"refresh_token": @"NEW-REFRESH",
        @"expires_in": @604800
    })];

    MRAssertTrue(MRRunUntil(^BOOL {
        return firstToken != nil && secondToken != nil;
    }, 2.0), @"both waiters resume");
    MRAssertTrue(firstError == nil && secondError == nil, @"refresh has no error");
    MRAssertEqualObjects(firstToken, @"NEW-ACCESS", @"first waiter gets the new token");
    MRAssertEqualObjects(secondToken, @"NEW-ACCESS", @"second waiter gets the new token");

    MRTokenSession *updated = [store loadSession:NULL];
    MRAssertEqualObjects(updated.accessToken, @"NEW-ACCESS", @"new access token stored");
    MRAssertEqualObjects(updated.refreshToken, @"NEW-REFRESH", @"new refresh token stored");
    MRAssertEqualIntegers(updated.accountID, 12345, @"refresh keeps the account id");
    MRAssertEqualObjects(updated.accountName, @"Ada", @"refresh keeps the account name");
    MRAssertTrue([updated.expiresAt timeIntervalSinceDate:[clock now]] == 604800.0,
                 @"refresh stores the new expiry");
}

static void MRAuthRefreshInvalidGrantTest(void) {
    MRDeferredHTTPClient *http = [[MRDeferredHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];
    MRTokenSession *stored =
        [[MRTokenSession alloc] initWithAccessToken:@"OLD-ACCESS"
                                       refreshToken:@"OLD-REFRESH"
                                          expiresAt:[[clock now] dateByAddingTimeInterval:60.0]
                                          accountID:12345
                                        accountName:@"Ada"];
    [store saveSession:stored error:NULL];

    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];
    MRRestore(auth, NULL);

    __block NSUInteger notifications = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRAuthDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        notifications += 1;
    }];

    __block NSString *token = nil;
    __block NSError *error = nil;
    [auth validAccessTokenWithCompletion:^(NSString *value, NSError *valueError) {
        token = value;
        error = valueError;
    }];
    [http respondWithResponse:MRJSONResponse(400, @{ @"error": @"invalid_grant" })];

    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"invalid grant completes the refresh");
    MRAssertTrue(token == nil, @"invalid grant returns no token");
    MRAssertEqualIntegers([MRError kindForError:error], MRErrorKindAuthExpired,
                          @"invalid grant maps to auth expired");
    MRAssertTrue(!auth.isSignedIn, @"invalid grant signs out");
    MRAssertTrue([store loadSession:NULL] == nil, @"invalid grant clears the token store");
    MRAssertEqualIntegers((NSInteger)notifications, 1,
                          @"invalid grant posts exactly one auth-change notification");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

static void MRAuthRefreshInvalidClientTest(void) {
    MRDeferredHTTPClient *http = [[MRDeferredHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];
    MRTokenSession *stored =
        [[MRTokenSession alloc] initWithAccessToken:@"OLD-ACCESS"
                                       refreshToken:@"OLD-REFRESH"
                                          expiresAt:[[clock now] dateByAddingTimeInterval:60.0]
                                          accountID:12345
                                        accountName:@"Ada"];
    [store saveSession:stored error:NULL];

    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];
    MRRestore(auth, NULL);

    __block NSUInteger notifications = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRAuthDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        notifications += 1;
    }];

    __block NSError *error = nil;
    [auth validAccessTokenWithCompletion:^(NSString *value, NSError *valueError) {
        error = valueError;
    }];
    [http respondWithResponse:MRJSONResponse(401, @{ @"error": @"invalid_client" })];

    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"invalid client completes the refresh");
    MRAssertEqualIntegers([MRError kindForError:error], MRErrorKindClientRejected,
                          @"invalid client maps to client rejected");
    MRAssertTrue(!auth.isSignedIn, @"invalid client signs out");
    MRAssertTrue([store loadSession:NULL] == nil, @"invalid client clears the token store");
    MRAssertEqualIntegers((NSInteger)notifications, 1,
                          @"invalid client posts exactly one auth-change notification");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

#pragma mark - Sign-in persistence and profile

static void MRAuthStorageFailureTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRFailingTokenStore *store = [[MRFailingTokenStore alloc] init];
    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];

    [http enqueueResponse:MRDeviceStartResponse()];
    __block NSError *startError = nil;
    [auth beginDeviceFlowWithCompletion:^(MRDeviceCode *code, NSError *error) {
        startError = error;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return startError != nil || http.requestCount >= 1;
    }, 2.0), @"device flow starts");

    [http enqueueResponse:MRTokenResponse()];
    __block MRTokenSession *session = nil;
    __block NSError *error = nil;
    [auth pollDeviceFlowWithCompletion:^(MRTokenSession *value, NSError *valueError) {
        session = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return error != nil;
    }, 2.0), @"storage failure completes");
    MRAssertTrue(session == nil, @"storage failure returns no session");
    MRAssertTrue(!auth.isSignedIn, @"storage failure does not sign in");
    MRAssertTrue([[error localizedDescription]
                  rangeOfString:@"Could not securely store your session"].location != NSNotFound,
                 @"storage failure uses the exact message");
    MRAssertEqualIntegers(http.requestCount, 2,
                          @"settings is not requested when the session cannot be stored");
}

static void MRAuthProfileSuccessTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];
    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];

    [http enqueueResponse:MRDeviceStartResponse()];
    [auth beginDeviceFlowWithCompletion:^(MRDeviceCode *code, NSError *error) {
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 1;
    }, 2.0), @"device flow starts");

    [http enqueueResponse:MRTokenResponse()];
    [http enqueueResponse:MRJSONResponse(200, @{
        @"user": @{ @"name": @"Ada" },
        @"account": @{ @"id": @12345 }
    })];
    __block MRTokenSession *session = nil;
    __block NSError *error = nil;
    [auth pollDeviceFlowWithCompletion:^(MRTokenSession *value, NSError *valueError) {
        session = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return session != nil || error != nil;
    }, 2.0), @"sign-in completes");
    MRAssertTrue(error == nil, @"profile fetch succeeds");
    MRAssertTrue(session != nil, @"session returned");
    MRAssertEqualIntegers(session.accountID, 12345, @"account id parsed from settings");
    MRAssertEqualObjects(session.accountName, @"Ada", @"account name parsed from settings");
    MRAssertTrue(auth.isSignedIn, @"profile success signs in");

    MRHTTPRequest *settingsRequest = [http lastRequest];
    MRAssertTrue([settingsRequest.URL rangeOfString:@"/users/settings"].location != NSNotFound,
                 @"settings request path");
    MRAssertEqualObjects([settingsRequest.headers objectForKey:@"Authorization"],
                         @"Bearer ACCESS-SECRET",
                         @"settings uses the bearer token");

    MRTokenSession *stored = [store loadSession:NULL];
    MRAssertEqualIntegers(stored.accountID, 12345, @"profile is persisted with the session");
    MRAssertEqualObjects(stored.accountName, @"Ada", @"name is persisted with the session");
}

static void MRAuthProfileFailureAndRetryTest(void) {
    MRStubHTTPClient *http = [[MRStubHTTPClient alloc] init];
    MRFakeClock *clock = [[MRFakeClock alloc] init];
    MRMemoryTokenStore *store = [[MRMemoryTokenStore alloc] init];
    MRSimklAuth *auth = [[MRSimklAuth alloc] initWithHTTPClient:http
                                                     tokenStore:store
                                                    diagnostics:MRTestDiagnostics()
                                                          clock:clock];

    [http enqueueResponse:MRDeviceStartResponse()];
    [auth beginDeviceFlowWithCompletion:^(MRDeviceCode *code, NSError *error) {
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return http.requestCount >= 1;
    }, 2.0), @"device flow starts");

    [http enqueueResponse:MRTokenResponse()];
    [http enqueueResponse:MRJSONResponse(500, @{ @"error": @"server_error" })];
    __block MRTokenSession *session = nil;
    __block NSError *error = nil;
    [auth pollDeviceFlowWithCompletion:^(MRTokenSession *value, NSError *valueError) {
        session = value;
        error = valueError;
    }];
    MRAssertTrue(MRRunUntil(^BOOL {
        return session != nil || error != nil;
    }, 2.0), @"poll completes even when settings fails");
    MRAssertTrue(session != nil, @"token session is kept when settings fails");
    MRAssertTrue(error != nil, @"settings failure is reported");
    MRAssertEqualIntegers(session.accountID, 0, @"profile failure leaves account id zero");
    MRAssertTrue(auth.isSignedIn, @"token is retained after a profile failure");
    MRAssertTrue([store loadSession:NULL].accessToken != nil,
                 @"token is stored despite the profile failure");

    [http enqueueResponse:MRJSONResponse(200, @{
        @"user": @{ @"name": @"Ada" },
        @"account": @{ @"id": @12345 }
    })];
    NSError *retryError = nil;
    MRTokenSession *retried = MRRestore(auth, &retryError);
    MRAssertTrue(retried != nil, @"retry restores the session");
    MRAssertTrue(retryError == nil, @"settings retry succeeds");
    MRAssertEqualIntegers(retried.accountID, 12345, @"retry resolves the account id");
    MRAssertEqualObjects(retried.accountName, @"Ada", @"retry resolves the account name");
    MRAssertEqualIntegers([store loadSession:NULL].accountID, 12345,
                          @"retry persists the account id");
}

#pragma mark - Suite

void MRRunDeviceFlowTests(void) {
    MRDeviceStartTest();
    MRDevicePollRequestTest();
    MRDeviceAuthorizationPendingTest();
    MRDeviceSlowDownTest();
    MRDeviceExpiredTokenTest();
    MRDeviceInvalidClientTest();
    MRDeviceDeadlineTest();
    MRAuthSingleRefreshTest();
    MRAuthRefreshInvalidGrantTest();
    MRAuthRefreshInvalidClientTest();
    MRAuthStorageFailureTest();
    MRAuthProfileSuccessTest();
    MRAuthProfileFailureAndRetryTest();
}
