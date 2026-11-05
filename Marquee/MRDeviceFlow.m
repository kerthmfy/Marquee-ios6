//
//  MRDeviceFlow.m
//  Marquee
//

#import "MRDeviceFlow.h"

#import "MRClock.h"
#import "MRConfig.h"
#import "MRDeviceCode.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPClient.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"
#import "MRJSON.h"
#import "MRTokenSession.h"
#import "MRURLBuilder.h"

static const NSTimeInterval MRDeviceFlowDeadline = 15.0 * 60.0;
static const NSTimeInterval MRDeviceFlowDefaultInterval = 5.0;
static const NSTimeInterval MRDeviceFlowSlowDownIncrement = 5.0;
static const NSTimeInterval MRAccessTokenLifetime = 7.0 * 24.0 * 60.0 * 60.0;

static void MRDeviceFlowDeliverOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        block();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), block);
}

static NSData *MRFormBody(NSDictionary *fields) {
    NSString *encoded = [MRURLBuilder formEncodedStringForParameters:fields];
    return [encoded dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *MRJSONDictionary(MRHTTPResponse *response) {
    if (response.data.length == 0) {
        return nil;
    }
    id object = [MRJSON objectFromData:response.data error:NULL];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static NSString *MRStringValue(NSDictionary *dictionary, NSString *key) {
    id value = [dictionary objectForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

static NSTimeInterval MRSecondsValue(NSDictionary *dictionary, NSString *key) {
    id value = [dictionary objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value doubleValue];
    }
    return 0.0;
}

static NSError *MRDeviceResponseError(MRHTTPResponse *response) {
    return [MRError errorForStatusCode:response.statusCode
                                  body:response.data
                               headers:response.headers
                        transportError:response.transportError];
}

@interface MRDeviceFlow ()
@property (nonatomic, strong) id<MRHTTPClient> httpClient;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, strong) MRDeviceCode *deviceCode;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) BOOL pollInFlight;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) NSUInteger pollGeneration;
@end

@implementation MRDeviceFlow

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                        diagnostics:(MRDiagnostics *)diagnostics
                              clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _diagnostics = diagnostics;
        _clock = clock;
        _interval = MRDeviceFlowDefaultInterval;
        _pollGeneration = 0;
    }
    return self;
}

- (NSDate *)deadline {
    if (self.startedAt == nil) {
        return nil;
    }
    return [self.startedAt dateByAddingTimeInterval:MRDeviceFlowDeadline];
}

- (BOOL)hasReachedDeadline {
    NSDate *deadline = self.deadline;
    return deadline != nil && [[self.clock now] compare:deadline] != NSOrderedAscending;
}

- (MRHTTPRequest *)formRequestForPath:(NSString *)path fields:(NSDictionary *)fields {
    NSString *URL = [MRURLBuilder apiURLForPath:path query:nil];
    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:URL method:@"POST"];
    request.headers = @{
        @"Accept": @"application/json",
        @"Content-Type": @"application/x-www-form-urlencoded",
        @"User-Agent": MR_USER_AGENT
    };
    request.body = MRFormBody(fields);
    request.timeout = 30.0;
    request.queueKind = MRHTTPQueueKindAPI;
    return request;
}

#pragma mark - Start

- (void)startWithCompletion:(void (^)(MRDeviceCode *code, NSError *error))completion {
    MRDeviceFlowDeliverOnMain(^{
        self.cancelled = NO;
        self.finished = NO;
        self.pollInFlight = NO;
        self.deviceCode = nil;
        self.interval = MRDeviceFlowDefaultInterval;
        self.startedAt = [self.clock now];
        self.pollGeneration += 1;

        MRHTTPRequest *request = [self formRequestForPath:@"oauth2/device" fields:@{
            @"client_id": MR_SIMKL_CLIENT_ID,
            @"scope": @"media:read media:write"
        }];
        [self.httpClient sendRequest:request completion:^(MRHTTPResponse *response) {
            MRDeviceFlowDeliverOnMain(^{
                [self handleStartResponse:response request:request completion:completion];
            });
        }];
    });
}

- (void)handleStartResponse:(MRHTTPResponse *)response
                    request:(MRHTTPRequest *)request
                 completion:(void (^)(MRDeviceCode *code, NSError *error))completion {
    if (self.cancelled) {
        return;
    }

    if (response == nil) {
        [self finishStartWithError:[MRError errorWithKind:MRErrorKindUnknown]
                           request:request
                          response:nil
                        completion:completion];
        return;
    }

    if (response.transportError != nil ||
        response.statusCode < 200 || response.statusCode > 299) {
        NSError *error = MRDeviceResponseError(response);
        [self finishStartWithError:error
                           request:request
                          response:response
                        completion:completion];
        return;
    }

    NSDictionary *json = MRJSONDictionary(response);
    NSString *deviceCode = MRStringValue(json, @"device_code");
    NSString *userCode = MRStringValue(json, @"user_code");
    NSString *verificationURI = MRStringValue(json, @"verification_uri");
    NSString *verificationComplete = MRStringValue(json, @"verification_uri_complete");
    if (deviceCode.length == 0 || userCode.length == 0 || verificationURI.length == 0) {
        [self finishStartWithError:[MRError errorWithKind:MRErrorKindParse]
                           request:request
                          response:response
                        completion:completion];
        return;
    }

    NSTimeInterval expiresIn = MRSecondsValue(json, @"expires_in");
    if (expiresIn <= 0.0) {
        expiresIn = MRDeviceFlowDeadline;
    }
    NSTimeInterval interval = MRSecondsValue(json, @"interval");
    if (interval <= 0.0) {
        interval = MRDeviceFlowDefaultInterval;
    }

    MRDeviceCode *code =
        [[MRDeviceCode alloc] initWithDeviceCode:deviceCode
                                       userCode:userCode
                                verificationURI:verificationURI
                        verificationURIComplete:verificationComplete
                                      expiresAt:[[self.clock now] dateByAddingTimeInterval:expiresIn]
                                       interval:interval];
    self.deviceCode = code;
    self.interval = interval;

    if (completion != nil) {
        completion(code, nil);
    }
}

#pragma mark - Poll

- (void)pollWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion {
    MRDeviceFlowDeliverOnMain(^{
        if (self.cancelled) {
            [self deliverSession:nil
                           error:[MRError errorWithKind:MRErrorKindCancelled]
                      completion:completion];
            return;
        }
        if (self.finished) {
            [self deliverSession:nil
                           error:[MRError errorWithKind:MRErrorKindAuthExpired]
                      completion:completion];
            return;
        }
        if (self.deviceCode == nil) {
            [self deliverSession:nil
                           error:[MRError errorWithKind:MRErrorKindUnknown]
                      completion:completion];
            return;
        }
        if (self.pollInFlight) {
            // Exactly one poll may be in flight. The existing poll resumes the
            // schedule and completion when it returns.
            return;
        }
        if ([self hasReachedDeadline]) {
            [self finishWithError:[MRError errorWithKind:MRErrorKindAuthExpired]
                          request:nil
                         response:nil
                       completion:completion];
            return;
        }

        self.pollGeneration += 1;
        NSUInteger generation = self.pollGeneration;
        self.pollInFlight = YES;

        MRHTTPRequest *request = [self formRequestForPath:@"oauth2/token" fields:@{
            @"grant_type": @"urn:ietf:params:oauth:grant-type:device_code",
            @"client_id": MR_SIMKL_CLIENT_ID,
            @"device_code": self.deviceCode.deviceCode
        }];
        [self.httpClient sendRequest:request completion:^(MRHTTPResponse *response) {
            MRDeviceFlowDeliverOnMain(^{
                [self handlePollResponse:response
                                request:request
                             generation:generation
                             completion:completion];
            });
        }];
    });
}

- (void)handlePollResponse:(MRHTTPResponse *)response
                   request:(MRHTTPRequest *)request
                generation:(NSUInteger)generation
                completion:(void (^)(MRTokenSession *session, NSError *error))completion {
    if (generation != self.pollGeneration) {
        return;
    }
    if (self.cancelled) {
        self.pollInFlight = NO;
        return;
    }

    self.pollInFlight = NO;

    if (response == nil) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindUnknown]
                      request:request
                     response:nil
                   completion:completion];
        return;
    }

    NSDictionary *json = MRJSONDictionary(response);
    NSString *code = MRStringValue(json, @"error");
    if (code.length == 0) {
        code = MRStringValue(json, @"code");
    }

    if (response.transportError == nil &&
        response.statusCode >= 200 && response.statusCode <= 299) {
        NSString *accessToken = MRStringValue(json, @"access_token");
        if (accessToken.length == 0) {
            [self finishWithError:[MRError errorWithKind:MRErrorKindParse]
                          request:request
                         response:response
                       completion:completion];
            return;
        }

        NSTimeInterval expiresIn = MRSecondsValue(json, @"expires_in");
        if (expiresIn <= 0.0) {
            expiresIn = MRAccessTokenLifetime;
        }
        MRTokenSession *session =
            [[MRTokenSession alloc] initWithAccessToken:accessToken
                                          refreshToken:MRStringValue(json, @"refresh_token")
                                             expiresAt:[[self.clock now] dateByAddingTimeInterval:expiresIn]
                                             accountID:0
                                           accountName:@""];
        [self finishWithSession:session];
        if (completion != nil) {
            completion(session, nil);
        }
        return;
    }

    if ([code isEqualToString:@"authorization_pending"]) {
        [self scheduleNextPollWithCompletion:completion generation:generation];
        return;
    }
    if ([code isEqualToString:@"slow_down"]) {
        self.interval += MRDeviceFlowSlowDownIncrement;
        [self scheduleNextPollWithCompletion:completion generation:generation];
        return;
    }
    if ([code isEqualToString:@"expired_token"]) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindAuthExpired]
                      request:request
                     response:response
                   completion:completion];
        return;
    }
    if ([code isEqualToString:@"invalid_client"]) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindClientRejected]
                      request:request
                     response:response
                   completion:completion];
        return;
    }
    if ([code isEqualToString:@"access_denied"]) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindAuthExpired]
                      request:request
                     response:response
                   completion:completion];
        return;
    }

    NSError *error = MRDeviceResponseError(response);
    [self finishWithError:error request:request response:response completion:completion];
}

- (void)scheduleNextPollWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion
                            generation:(NSUInteger)generation {
    if (self.cancelled || self.finished) {
        return;
    }
    if ([self hasReachedDeadline]) {
        [self finishWithError:[MRError errorWithKind:MRErrorKindAuthExpired]
                      request:nil
                     response:nil
                   completion:completion];
        return;
    }

    NSTimeInterval interval = self.interval;
    __weak MRDeviceFlow *weakSelf = self;
    [self.clock after:interval perform:^{
        MRDeviceFlow *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (strongSelf.cancelled || strongSelf.finished) {
            return;
        }
        if (generation != strongSelf.pollGeneration) {
            return;
        }
        [strongSelf pollWithCompletion:completion];
    }];
}

#pragma mark - Completion

- (void)finishWithSession:(MRTokenSession *)session {
    self.finished = YES;
    self.pollInFlight = NO;
    self.pollGeneration += 1;
}

- (void)finishStartWithError:(NSError *)error
                     request:(MRHTTPRequest *)request
                    response:(MRHTTPResponse *)response
                  completion:(void (^)(MRDeviceCode *code, NSError *error))completion {
    self.finished = YES;
    self.pollInFlight = NO;
    self.pollGeneration += 1;

    if (request != nil && error != nil) {
        [self.diagnostics recordError:error request:request response:response];
    }
    if (completion != nil) {
        completion(nil, error);
    }
}

- (void)finishWithError:(NSError *)error
                request:(MRHTTPRequest *)request
               response:(MRHTTPResponse *)response
             completion:(void (^)(MRTokenSession *session, NSError *error))completion {
    self.finished = YES;
    self.pollInFlight = NO;
    self.pollGeneration += 1;

    if (request != nil && error != nil) {
        [self.diagnostics recordError:error request:request response:response];
    }
    if (completion != nil) {
        completion(nil, error);
    }
}

- (void)deliverSession:(MRTokenSession *)session
                 error:(NSError *)error
            completion:(void (^)(MRTokenSession *session, NSError *error))completion {
    if (completion != nil) {
        completion(session, error);
    }
}

- (void)cancel {
    MRDeviceFlowDeliverOnMain(^{
        self.cancelled = YES;
        self.finished = YES;
        self.pollInFlight = NO;
        self.pollGeneration += 1;
        self.deviceCode = nil;
    });
}

@end
