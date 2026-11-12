//
//  MRSimklAuth.m
//  Marquee
//

#import "MRSimklAuth.h"

#import "MRClock.h"
#import "MRConfig.h"
#import "MRDeviceCode.h"
#import "MRDeviceFlow.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPClient.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"
#import "MRJSON.h"
#import "MRTokenSession.h"
#import "MRTokenStore.h"
#import "MRURLBuilder.h"

NSString *const MRAuthDidChangeNotification = @"MRAuthDidChangeNotification";
NSString *const MRAuthDidExpireNotification = @"MRAuthDidExpireNotification";

static const NSTimeInterval MRAuthRefreshWindow = 5.0 * 60.0;
static const NSTimeInterval MRAuthAccessTokenLifetime = 7.0 * 24.0 * 60.0 * 60.0;

typedef void (^MRAuthTokenCompletion)(NSString *token, NSError *error);

static void MRAuthDeliverOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        block();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), block);
}

static NSError *MRAuthStorageError(void) {
    return [NSError errorWithDomain:@"MRSimklAuthErrorDomain"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey:
                                           @"Could not securely store your session" }];
}

static NSData *MRAuthFormBody(NSDictionary *fields) {
    NSString *encoded = [MRURLBuilder formEncodedStringForParameters:fields];
    return [encoded dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *MRAuthJSONDictionary(MRHTTPResponse *response) {
    if (response.data.length == 0) {
        return nil;
    }
    id object = [MRJSON objectFromData:response.data error:NULL];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static NSString *MRAuthStringValue(NSDictionary *dictionary, NSString *key) {
    id value = [dictionary objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSTimeInterval MRAuthSecondsValue(NSDictionary *dictionary, NSString *key) {
    id value = [dictionary objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value doubleValue];
    }
    return 0.0;
}

static NSInteger MRAuthAccountID(NSDictionary *json) {
    id account = [json objectForKey:@"account"];
    if (![account isKindOfClass:[NSDictionary class]]) {
        return 0;
    }
    id identifier = [(NSDictionary *)account objectForKey:@"id"];
    if ([identifier isKindOfClass:[NSNumber class]]) {
        return [identifier integerValue];
    }
    if ([identifier isKindOfClass:[NSString class]]) {
        return [(NSString *)identifier integerValue];
    }
    return 0;
}

static NSString *MRAuthAccountName(NSDictionary *json) {
    id user = [json objectForKey:@"user"];
    if (![user isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return MRAuthStringValue((NSDictionary *)user, @"name");
}

static NSError *MRAuthResponseError(MRHTTPResponse *response) {
    return [MRError errorForStatusCode:response.statusCode
                                  body:response.data
                               headers:response.headers
                        transportError:response.transportError];
}

static NSError *MRAuthErrorForRefreshResponse(MRHTTPResponse *response) {
    NSDictionary *json = MRAuthJSONDictionary(response);
    NSString *code = MRAuthStringValue(json, @"error");
    if (code.length == 0) {
        code = MRAuthStringValue(json, @"code");
    }
    if ([code isEqualToString:@"invalid_grant"]) {
        return [MRError errorWithKind:MRErrorKindAuthExpired];
    }
    if ([code isEqualToString:@"invalid_client"]) {
        return [MRError errorWithKind:MRErrorKindClientRejected];
    }
    return MRAuthResponseError(response);
}

static BOOL MRAuthErrorEndsSession(NSError *error) {
    MRErrorKind kind = [MRError kindForError:error];
    return kind == MRErrorKindAuthExpired || kind == MRErrorKindClientRejected;
}

@interface MRSimklAuth ()
@property (nonatomic, strong) id<MRHTTPClient> httpClient;
@property (nonatomic, strong) id<MRTokenStore> tokenStore;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, strong) MRDeviceFlow *deviceFlow;
@end

@implementation MRSimklAuth {
    MRTokenSession *_session;
    BOOL _refreshing;
    NSMutableArray *_refreshWaiters;
    NSUInteger _sessionGeneration;
}

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                        tokenStore:(id<MRTokenStore>)tokenStore
                       diagnostics:(MRDiagnostics *)diagnostics
                             clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _tokenStore = tokenStore;
        _diagnostics = diagnostics;
        _clock = clock;
        _refreshWaiters = [NSMutableArray array];
        _sessionGeneration = 0;
    }
    return self;
}

#pragma mark - State

- (MRTokenSession *)session {
    @synchronized(self) {
        return _session;
    }
}

- (void)setSession:(MRTokenSession *)session {
    @synchronized(self) {
        _session = session;
    }
}

- (BOOL)isSignedIn {
    MRTokenSession *session = self.session;
    return session != nil && session.accessToken.length > 0;
}

- (void)postAuthChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:MRAuthDidChangeNotification
                                                        object:self];
}

#pragma mark - Restore

- (void)restoreWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion {
    MRAuthDeliverOnMain(^{
        NSError *loadError = nil;
        MRTokenSession *loaded = [self.tokenStore loadSession:&loadError];
        if (loaded == nil) {
            if (loadError != nil) {
                [self setSession:nil];
                if (completion != nil) {
                    completion(nil, loadError);
                }
                return;
            }
            [self setSession:nil];
            if (completion != nil) {
                completion(nil, nil);
            }
            return;
        }

        [self setSession:loaded];
        if (loaded.accountID != 0) {
            if (completion != nil) {
                completion(loaded, nil);
            }
            return;
        }

        [self fetchProfileForSession:loaded completion:^(MRTokenSession *updated, NSError *error) {
            if (updated == nil) {
                if (completion != nil) {
                    completion(loaded, error);
                }
                return;
            }

            NSError *saveError = nil;
            if (![self.tokenStore saveSession:updated error:&saveError]) {
                if (completion != nil) {
                    completion(loaded, MRAuthStorageError());
                }
                return;
            }
            [self setSession:updated];
            if (completion != nil) {
                completion(updated, nil);
            }
        }];
    });
}

#pragma mark - Device flow

- (void)beginDeviceFlowWithCompletion:(void (^)(MRDeviceCode *code, NSError *error))completion {
    MRAuthDeliverOnMain(^{
        [self.deviceFlow cancel];
        self.deviceFlow = [[MRDeviceFlow alloc] initWithHTTPClient:self.httpClient
                                                       diagnostics:self.diagnostics
                                                             clock:self.clock];
        [self.deviceFlow startWithCompletion:completion];
    });
}

- (void)pollDeviceFlowWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion {
    MRAuthDeliverOnMain(^{
        MRDeviceFlow *flow = self.deviceFlow;
        if (flow == nil) {
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindUnknown]);
            }
            return;
        }
        [flow pollWithCompletion:^(MRTokenSession *session, NSError *error) {
            [self handleDevicePollSession:session error:error completion:completion];
        }];
    });
}

- (void)cancelDeviceFlow {
    MRAuthDeliverOnMain(^{
        [self.deviceFlow cancel];
        self.deviceFlow = nil;
    });
}

- (void)handleDevicePollSession:(MRTokenSession *)session
                          error:(NSError *)error
                     completion:(void (^)(MRTokenSession *session, NSError *error))completion {
    if (session == nil) {
        if (completion != nil) {
            completion(nil, error);
        }
        return;
    }

    NSError *saveError = nil;
    if (![self.tokenStore saveSession:session error:&saveError]) {
        if (completion != nil) {
            completion(nil, MRAuthStorageError());
        }
        return;
    }

    [self setSession:session];
    _sessionGeneration += 1;

    [self fetchProfileForSession:session completion:^(MRTokenSession *updated, NSError *profileError) {
        if (updated == nil) {
            [self postAuthChange];
            if (completion != nil) {
                completion(session, profileError);
            }
            return;
        }

        NSError *profileSaveError = nil;
        if (![self.tokenStore saveSession:updated error:&profileSaveError]) {
            [self setSession:session];
            [self postAuthChange];
            if (completion != nil) {
                completion(session, MRAuthStorageError());
            }
            return;
        }

        [self setSession:updated];
        [self postAuthChange];
        if (completion != nil) {
            completion(updated, nil);
        }
    }];
}

#pragma mark - Settings

- (void)fetchProfileForSession:(MRTokenSession *)session
                    completion:(void (^)(MRTokenSession *session, NSError *error))completion {
    NSUInteger generation = _sessionGeneration;
    MRHTTPRequest *request =
        [[MRHTTPRequest alloc] initWithURL:[MRURLBuilder apiURLForPath:@"users/settings" query:nil]
                                    method:@"GET"];
    request.headers = @{
        @"Accept": @"application/json",
        @"Authorization": [@"Bearer " stringByAppendingString:session.accessToken ?: @""],
        @"User-Agent": MR_USER_AGENT
    };
    request.timeout = 30.0;
    request.queueKind = MRHTTPQueueKindAPI;

    [self.httpClient sendRequest:request completion:^(MRHTTPResponse *response) {
        MRAuthDeliverOnMain(^{
            if (generation != self->_sessionGeneration) {
                if (completion != nil) {
                    completion(nil, [MRError errorWithKind:MRErrorKindCancelled]);
                }
                return;
            }

            NSError *error = nil;
            NSDictionary *json = nil;
            if (response == nil) {
                error = [MRError errorWithKind:MRErrorKindUnknown];
            } else if (response.transportError != nil ||
                       response.statusCode < 200 || response.statusCode > 299) {
                error = MRAuthResponseError(response);
            } else {
                json = MRAuthJSONDictionary(response);
                if (json == nil) {
                    error = [MRError errorWithKind:MRErrorKindParse];
                }
            }

            NSInteger accountID = MRAuthAccountID(json);
            NSString *name = MRAuthAccountName(json);
            if (error == nil && accountID <= 0) {
                error = [MRError errorWithKind:MRErrorKindParse];
            }

            if (error != nil) {
                [self.diagnostics recordError:error request:request response:response];
                if (completion != nil) {
                    completion(nil, error);
                }
                return;
            }

            MRTokenSession *updated =
                [[MRTokenSession alloc] initWithAccessToken:session.accessToken
                                              refreshToken:session.refreshToken
                                                 expiresAt:session.expiresAt
                                                 accountID:accountID
                                               accountName:name.length > 0 ? name : session.accountName];
            if (completion != nil) {
                completion(updated, nil);
            }
        });
    }];
}

#pragma mark - Refresh

- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    MRAuthDeliverOnMain(^{
        [self validAccessTokenOnMain:completion];
    });
}

- (void)validAccessTokenOnMain:(MRAuthTokenCompletion)completion {
    MRTokenSession *session = self.session;
    if (session == nil || session.accessToken.length == 0) {
        if (completion != nil) {
            completion(nil, [MRError errorWithKind:MRErrorKindAuthExpired]);
        }
        return;
    }

    NSDate *expiresAt = session.expiresAt;
    if (expiresAt != nil &&
        [expiresAt timeIntervalSinceDate:[self.clock now]] > MRAuthRefreshWindow) {
        if (completion != nil) {
            completion(session.accessToken, nil);
        }
        return;
    }

    if (completion != nil) {
        [_refreshWaiters addObject:[completion copy]];
    }
    if (_refreshing) {
        return;
    }
    _refreshing = YES;

    if (session.refreshToken.length == 0) {
        [self endSessionWithError:[MRError errorWithKind:MRErrorKindAuthExpired]];
        return;
    }

    MRHTTPRequest *request =
        [[MRHTTPRequest alloc] initWithURL:[MRURLBuilder apiURLForPath:@"oauth2/token" query:nil]
                                    method:@"POST"];
    request.headers = @{
        @"Accept": @"application/json",
        @"Content-Type": @"application/x-www-form-urlencoded",
        @"User-Agent": MR_USER_AGENT
    };
    request.body = MRAuthFormBody(@{
        @"grant_type": @"refresh_token",
        @"client_id": MR_SIMKL_CLIENT_ID,
        @"refresh_token": session.refreshToken
    });
    request.timeout = 30.0;
    request.queueKind = MRHTTPQueueKindAPI;

    [self.httpClient sendRequest:request completion:^(MRHTTPResponse *response) {
        MRAuthDeliverOnMain(^{
            [self handleRefreshResponse:response request:request];
        });
    }];
}

- (void)handleRefreshResponse:(MRHTTPResponse *)response request:(MRHTTPRequest *)request {
    if (!_refreshing) {
        return;
    }

    if (response == nil) {
        [self finishRefreshWithToken:nil
                               error:[MRError errorWithKind:MRErrorKindUnknown]
                        endSession:NO];
        return;
    }

    if (response.transportError == nil &&
        response.statusCode >= 200 && response.statusCode <= 299) {
        NSDictionary *json = MRAuthJSONDictionary(response);
        NSString *accessToken = MRAuthStringValue(json, @"access_token");
        if (accessToken.length == 0) {
            [self finishRefreshWithToken:nil
                                   error:[MRError errorWithKind:MRErrorKindParse]
                            endSession:NO];
            return;
        }

        MRTokenSession *current = self.session;
        if (current == nil) {
            [self finishRefreshWithToken:nil
                                   error:[MRError errorWithKind:MRErrorKindAuthExpired]
                            endSession:YES];
            return;
        }

        NSTimeInterval expiresIn = MRAuthSecondsValue(json, @"expires_in");
        if (expiresIn <= 0.0) {
            expiresIn = MRAuthAccessTokenLifetime;
        }
        NSString *refreshToken = MRAuthStringValue(json, @"refresh_token");
        if (refreshToken.length == 0) {
            refreshToken = current.refreshToken;
        }

        MRTokenSession *updated =
            [[MRTokenSession alloc] initWithAccessToken:accessToken
                                          refreshToken:refreshToken
                                             expiresAt:[[self.clock now] dateByAddingTimeInterval:expiresIn]
                                             accountID:current.accountID
                                           accountName:current.accountName];

        NSError *saveError = nil;
        if (![self.tokenStore saveSession:updated error:&saveError]) {
            [self finishRefreshWithToken:nil error:MRAuthStorageError() endSession:NO];
            return;
        }

        [self setSession:updated];
        [self finishRefreshWithToken:accessToken error:nil endSession:NO];
        return;
    }

    NSError *error = MRAuthErrorForRefreshResponse(response);
    if (MRAuthErrorEndsSession(error)) {
        [self.diagnostics recordError:error request:request response:response];
        [self finishRefreshWithToken:nil error:error endSession:YES];
        return;
    }

    [self.diagnostics recordError:error request:request response:response];
    [self finishRefreshWithToken:nil error:error endSession:NO];
}

- (void)finishRefreshWithToken:(NSString *)token
                         error:(NSError *)error
                    endSession:(BOOL)endSession {
    _refreshing = NO;

    NSArray *waiters = [_refreshWaiters copy];
    [_refreshWaiters removeAllObjects];

    if (endSession) {
        BOOL wasSignedIn = self.isSignedIn;
        [self.tokenStore clearSession:NULL];
        [self setSession:nil];
        if (wasSignedIn) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:MRAuthDidExpireNotification object:self];
        }
        [self postAuthChange];
    }

    for (MRAuthTokenCompletion waiter in waiters) {
        if (token != nil || error == nil) {
            waiter(token, nil);
        } else {
            waiter(nil, error);
        }
    }
}

- (void)endSessionWithError:(NSError *)error {
    _refreshing = NO;
    NSArray *waiters = [_refreshWaiters copy];
    [_refreshWaiters removeAllObjects];

    [self.tokenStore clearSession:NULL];
    [self setSession:nil];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MRAuthDidExpireNotification object:self];
    [self postAuthChange];

    for (MRAuthTokenCompletion waiter in waiters) {
        waiter(nil, error);
    }
}

#pragma mark - Sign out

- (void)signOut {
    MRAuthDeliverOnMain(^{
        BOOL wasSignedIn = self.isSignedIn;
        _sessionGeneration += 1;
        _refreshing = NO;

        NSArray *waiters = [_refreshWaiters copy];
        [_refreshWaiters removeAllObjects];

        [self.deviceFlow cancel];
        self.deviceFlow = nil;
        [self.tokenStore clearSession:NULL];
        [self setSession:nil];

        NSError *cancelled = [MRError errorWithKind:MRErrorKindCancelled];
        for (MRAuthTokenCompletion waiter in waiters) {
            waiter(nil, cancelled);
        }

        if (wasSignedIn) {
            [self postAuthChange];
        }
    });
}

@end
