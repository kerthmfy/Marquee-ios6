//
//  MRAPIClient.m
//  Marquee
//

#import "MRAPIClient.h"
#import "MRClock.h"
#import "MRConfig.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPClient.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRTokenProviding.h"
#import "MRURLBuilder.h"
#import "MROutboxEntry.h"

static const NSTimeInterval MRPublicCacheMaxAge = 24.0 * 60.0 * 60.0;
static const NSTimeInterval MRPublicCacheStaleMaxAge = 10.0 * 365.0 * 24.0 * 60.0 * 60.0;
static const NSInteger MRMaximumServerRetries = 5;
static const NSInteger MRMaximumBurstRetries = 2;

static NSString *MRHeaderValue(NSDictionary *headers, NSString *name) {
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] &&
            [(NSString *)key caseInsensitiveCompare:name] == NSOrderedSame) {
            id value = [headers objectForKey:key];
            if ([value isKindOfClass:[NSString class]]) {
                return value;
            }
            if (value != nil) {
                return [value description];
            }
        }
    }
    return nil;
}

static BOOL MRHeadersCarryQuota(NSDictionary *headers) {
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    for (id key in headers) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        if ([(NSString *)key caseInsensitiveCompare:@"X-RateLimit-Limit"] == NSOrderedSame ||
            [(NSString *)key caseInsensitiveCompare:@"X-RateLimit-Remaining"] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

static void MRDeliverOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), block);
}

@class MRAPIClientCall;

@interface MRAPIClient ()
@property (nonatomic, strong) id<MRHTTPClient> httpClient;
@property (nonatomic, strong) id<MRTokenProviding> tokenProvider;
@property (nonatomic, strong) MRResponseCache *responseCache;
@property (nonatomic, strong) MRQuotaTracker *quotaTracker;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) id<MRClock> clock;

- (void)updateQuotaFromResponse:(MRHTTPResponse *)response kind:(MRErrorKind)kind;
@end

@interface MRAPIClientCall : NSObject <MRHTTPTask>
@property (nonatomic, weak) MRAPIClient *client;
@property (nonatomic, strong) MRHTTPRequest *request;
@property (nonatomic, copy) NSString *cacheKey;
@property (nonatomic, assign) Class expectedClass;
@property (nonatomic, copy) void (^completion)(id json, NSError *error);
@property (nonatomic, assign) BOOL retriesAutomatically;
@property (nonatomic, assign) BOOL allowsEmptyResponse;

- (instancetype)initWithClient:(MRAPIClient *)client
                       request:(MRHTTPRequest *)request
                      cacheKey:(NSString *)cacheKey
                 expectedClass:(Class)expectedClass
                    completion:(void (^)(id json, NSError *error))completion;
- (void)start;
@end

@implementation MRAPIClientCall {
    NSInteger _serverRetries;
    NSInteger _burstRetries;
    BOOL _finished;
    BOOL _cancelled;
    BOOL _responseHandled;
    id<MRHTTPTask> _currentTask;
}

- (instancetype)initWithClient:(MRAPIClient *)client
                       request:(MRHTTPRequest *)request
                      cacheKey:(NSString *)cacheKey
                 expectedClass:(Class)expectedClass
                    completion:(void (^)(id json, NSError *error))completion {
    self = [super init];
    if (self) {
        _client = client;
        _request = request;
        _cacheKey = [cacheKey copy];
        _expectedClass = expectedClass;
        _completion = [completion copy];
        _serverRetries = 0;
        _burstRetries = 0;
        _retriesAutomatically = YES;
        _allowsEmptyResponse = NO;
    }
    return self;
}

- (void)start {
    [self send];
}

- (void)send {
    MRAPIClient *client = self.client;
    if (client == nil || client.httpClient == nil) {
        [self finishWithJSON:nil error:[MRError errorWithKind:MRErrorKindUnknown] response:nil];
        return;
    }

    @synchronized(self) {
        if (_finished || _cancelled) {
            return;
        }
        _responseHandled = NO;
    }

    MRHTTPRequest *request = self.request;
    id<MRHTTPTask> task = [client.httpClient sendRequest:request
                                              completion:^(MRHTTPResponse *response) {
        [self handleResponse:response];
    }];

    @synchronized(self) {
        if (!_responseHandled && !_finished && !_cancelled) {
            _currentTask = task;
        }
    }
}

- (void)handleResponse:(MRHTTPResponse *)response {
    @synchronized(self) {
        if (_finished || _cancelled) {
            return;
        }
        _responseHandled = YES;
        _currentTask = nil;
    }

    if (response == nil) {
        [self finishWithJSON:nil
                       error:[MRError errorWithKind:MRErrorKindUnknown]
                    response:nil];
        return;
    }

    MRErrorKind kind = MRErrorKindUnknown;
    if (response.transportError != nil) {
        kind = [MRError kindForTransportError:response.transportError];
    } else {
        kind = [MRError kindForStatusCode:response.statusCode
                                     body:response.data
                                  headers:response.headers];
    }

    [self.client updateQuotaFromResponse:response kind:kind];

    if (response.transportError == nil && response.statusCode == 304) {
        [self handleNotModified:response];
        return;
    }

    if (response.transportError == nil &&
        response.statusCode >= 200 && response.statusCode <= 299) {
        [self handleSuccess:response];
        return;
    }

    NSError *error = [MRError errorForStatusCode:response.statusCode
                                           body:response.data
                                        headers:response.headers
                                 transportError:response.transportError];

    if ([self shouldRetryKind:kind]) {
        return;
    }

    [self finishWithJSON:nil error:error response:response];
}

- (void)handleSuccess:(MRHTTPResponse *)response {
    id object = nil;
    if (response.data.length > 0) {
        object = [NSJSONSerialization JSONObjectWithData:response.data options:0 error:NULL];
    }

    if (object == nil && self.allowsEmptyResponse) {
        object = (self.expectedClass == [NSArray class]) ? @[] : @{};
    }

    if (object == nil ||
        (self.expectedClass != Nil && ![object isKindOfClass:self.expectedClass])) {
        [self finishWithJSON:nil
                       error:[MRError errorWithKind:MRErrorKindParse]
                    response:response];
        return;
    }

    if (self.cacheKey.length > 0) {
        [self.client.responseCache storeBody:object
                                      forURL:self.cacheKey
                                lastModified:MRHeaderValue(response.headers, @"Last-Modified")];
    }

    [self finishWithJSON:object error:nil response:response];
}

- (void)handleNotModified:(MRHTTPResponse *)response {
    if (self.cacheKey.length == 0) {
        [self finishWithJSON:nil
                       error:[MRError errorWithKind:MRErrorKindParse]
                    response:response];
        return;
    }

    MRResponseCache *cache = self.client.responseCache;
    id body = [cache cachedBodyForURL:self.cacheKey maxAge:MRPublicCacheStaleMaxAge];

    if (body == nil ||
        (self.expectedClass != Nil && ![body isKindOfClass:self.expectedClass])) {
        [self finishWithJSON:nil
                       error:[MRError errorWithKind:MRErrorKindParse]
                    response:response];
        return;
    }

    NSString *lastModified = MRHeaderValue(response.headers, @"Last-Modified");
    if (lastModified.length == 0) {
        lastModified = [cache lastModifiedForURL:self.cacheKey];
    }
    [cache storeBody:body forURL:self.cacheKey lastModified:lastModified];

    [self finishWithJSON:body error:nil response:response];
}

- (BOOL)shouldRetryKind:(MRErrorKind)kind {
    if (!self.retriesAutomatically) {
        return NO;
    }
    if (self.client.clock == nil) {
        return NO;
    }

    if (kind == MRErrorKindServer) {
        if (_serverRetries >= MRMaximumServerRetries) {
            return NO;
        }
        NSTimeInterval delay = (NSTimeInterval)(1 << _serverRetries);
        _serverRetries += 1;
        [self scheduleRetryAfter:delay];
        return YES;
    }

    if (kind == MRErrorKindRateLimitedBurst) {
        if (_burstRetries >= MRMaximumBurstRetries) {
            return NO;
        }
        _burstRetries += 1;
        [self scheduleRetryAfter:1.0];
        return YES;
    }

    return NO;
}

- (void)scheduleRetryAfter:(NSTimeInterval)delay {
    MRAPIClientCall *call = self;
    [self.client.clock after:delay perform:^{
        @synchronized(call) {
            if (call->_finished || call->_cancelled) {
                return;
            }
        }
        [call send];
    }];
}

- (void)finishWithJSON:(id)json error:(NSError *)error response:(MRHTTPResponse *)response {
    @synchronized(self) {
        if (_finished) {
            return;
        }
        _finished = YES;
        _currentTask = nil;
    }

    if (error != nil) {
        [self.client.diagnostics recordError:error request:self.request response:response];
    }

    void (^completion)(id, NSError *) = self.completion;
    if (completion != nil) {
        MRDeliverOnMain(^{
            completion(json, error);
        });
    }
}

#pragma mark - MRHTTPTask

- (void)cancel {
    id<MRHTTPTask> task = nil;
    @synchronized(self) {
        if (_finished) {
            return;
        }
        _cancelled = YES;
        _finished = YES;
        task = _currentTask;
        _currentTask = nil;
    }

    [task cancel];

    void (^completion)(id, NSError *) = self.completion;
    if (completion != nil) {
        MRDeliverOnMain(^{
            completion(nil, [MRError errorWithKind:MRErrorKindCancelled]);
        });
    }
}

@end

#pragma mark - Authenticated calls

@interface MRAPIClientAuthenticatedCall : NSObject <MRHTTPTask>
@property (nonatomic, strong) MRAPIClient *client;
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, assign) BOOL allowsEmptyResponse;
@property (nonatomic, assign) Class expectedClass;
@property (nonatomic, copy) void (^completion)(id json, NSError *error);
- (instancetype)initWithClient:(MRAPIClient *)client
                           URL:(NSString *)URL
                        method:(NSString *)method
                          body:(NSData *)body
              allowsEmptyResponse:(BOOL)allowsEmptyResponse
                 expectedClass:(Class)expectedClass
                    completion:(void (^)(id json, NSError *error))completion;
- (void)start;
@end

@implementation MRAPIClientAuthenticatedCall {
    BOOL _finished;
    BOOL _cancelled;
    id<MRHTTPTask> _task;
}

- (instancetype)initWithClient:(MRAPIClient *)client
                           URL:(NSString *)URL
                        method:(NSString *)method
                          body:(NSData *)body
              allowsEmptyResponse:(BOOL)allowsEmptyResponse
                 expectedClass:(Class)expectedClass
                    completion:(void (^)(id json, NSError *error))completion {
    self = [super init];
    if (self) {
        _client = client;
        _URL = [URL copy];
        _method = [(method.length > 0 ? method : @"GET") copy];
        _body = [body copy];
        _allowsEmptyResponse = allowsEmptyResponse;
        _expectedClass = expectedClass;
        _completion = [completion copy];
    }
    return self;
}

- (void)start {
    MRAPIClient *client = self.client;
    if (client == nil || client.tokenProvider == nil) {
        [self finishWithJSON:nil error:[MRError errorWithKind:MRErrorKindAuthExpired]];
        return;
    }

    __weak MRAPIClientAuthenticatedCall *weakSelf = self;
    [client.tokenProvider validAccessTokenWithCompletion:^(NSString *token, NSError *error) {
        MRAPIClientAuthenticatedCall *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished || strongSelf->_cancelled) {
            return;
        }
        if (error != nil) {
            [strongSelf finishWithJSON:nil error:error];
            return;
        }
        if (token.length == 0) {
            [strongSelf finishWithJSON:nil
                                 error:[MRError errorWithKind:MRErrorKindAuthExpired]];
            return;
        }

        MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:strongSelf.URL
                                                            method:strongSelf.method];
        request.queueKind = MRHTTPQueueKindAPI;
        request.timeout = 30.0;
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        [headers setObject:@"application/json" forKey:@"Accept"];
        [headers setObject:[@"Bearer " stringByAppendingString:token]
                    forKey:@"Authorization"];
        [headers setObject:MR_USER_AGENT forKey:@"User-Agent"];
        if (strongSelf.body.length > 0) {
            [headers setObject:@"application/json" forKey:@"Content-Type"];
            request.body = strongSelf.body;
        }
        request.headers = headers;

        MRAPIClientCall *call = [[MRAPIClientCall alloc]
            initWithClient:client
                   request:request
                  cacheKey:nil
             expectedClass:strongSelf.expectedClass
                completion:^(id json, NSError *callError) {
            [strongSelf finishWithJSON:json error:callError];
        }];
        call.retriesAutomatically =
            [strongSelf.method isEqualToString:@"GET"];
        call.allowsEmptyResponse = strongSelf.allowsEmptyResponse;

        @synchronized(strongSelf) {
            if (strongSelf->_finished || strongSelf->_cancelled) {
                [call cancel];
                return;
            }
            strongSelf->_task = call;
        }
        [call start];
    }];
}

- (void)finishWithJSON:(id)json error:(NSError *)error {
    @synchronized(self) {
        if (_finished) {
            return;
        }
        _finished = YES;
        _task = nil;
    }

    void (^completion)(id, NSError *) = self.completion;
    if (completion != nil) {
        MRDeliverOnMain(^{
            completion(json, error);
        });
    }
}

#pragma mark - MRHTTPTask

- (void)cancel {
    id<MRHTTPTask> task = nil;
    @synchronized(self) {
        if (_finished) {
            return;
        }
        _cancelled = YES;
        task = _task;
        _task = nil;
    }

    [task cancel];
    [self finishWithJSON:nil error:[MRError errorWithKind:MRErrorKindCancelled]];
}

@end

@implementation MRAPIClient

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                     tokenProvider:(id<MRTokenProviding>)tokenProvider
                     responseCache:(MRResponseCache *)responseCache
                      quotaTracker:(MRQuotaTracker *)quotaTracker
                       diagnostics:(MRDiagnostics *)diagnostics
                             clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _tokenProvider = tokenProvider;
        _responseCache = responseCache;
        _quotaTracker = quotaTracker;
        _diagnostics = diagnostics;
        _clock = clock;
    }
    return self;
}

- (void)updateQuotaFromResponse:(MRHTTPResponse *)response kind:(MRErrorKind)kind {
    if (self.quotaTracker == nil || response == nil) {
        return;
    }

    // A burst 429's Retry-After is not the daily reset. When such a response
    // also carries quota headers, pass those through but strip Retry-After.
    if (kind == MRErrorKindRateLimitedBurst) {
        if (!MRHeadersCarryQuota(response.headers)) {
            return;
        }
        NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
        for (id key in response.headers) {
            if ([key isKindOfClass:[NSString class]] &&
                [(NSString *)key caseInsensitiveCompare:@"Retry-After"] == NSOrderedSame) {
                continue;
            }
            [filtered setObject:[response.headers objectForKey:key] forKey:key];
        }
        [self.quotaTracker updateFromHeaders:filtered];
        return;
    }

    if (kind == MRErrorKindDailyLimit || MRHeadersCarryQuota(response.headers)) {
        [self.quotaTracker updateFromHeaders:response.headers];
    }
}

- (id<MRHTTPTask>)fetchURL:(NSString *)URL
             expectedClass:(Class)expectedClass
                completion:(void (^)(id json, NSError *error))completion {
    if (URL.length == 0) {
        MRDeliverOnMain(^{
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindUnknown]);
            }
        });
        return nil;
    }

    id cached = [self.responseCache cachedBodyForURL:URL maxAge:MRPublicCacheMaxAge];
    if (cached != nil && expectedClass != Nil && ![cached isKindOfClass:expectedClass]) {
        cached = nil;
    }
    if (cached != nil) {
        MRDeliverOnMain(^{
            if (completion != nil) {
                completion(cached, nil);
            }
        });
        return nil;
    }

    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:URL method:@"GET"];
    request.queueKind = MRHTTPQueueKindCatalog;

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [headers setObject:MR_USER_AGENT forKey:@"User-Agent"];
    NSString *lastModified = [self.responseCache lastModifiedForURL:URL];
    if (lastModified.length > 0) {
        [headers setObject:lastModified forKey:@"If-Modified-Since"];
    }
    request.headers = headers;

    MRAPIClientCall *call = [[MRAPIClientCall alloc] initWithClient:self
                                                           request:request
                                                          cacheKey:URL
                                                     expectedClass:expectedClass
                                                        completion:completion];
    [call start];
    return call;
}

- (id<MRHTTPTask>)fetchTrendingWeekWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    NSString *URL = [MRURLBuilder dataURLForPath:@"discover/trending/week_100.json" query:nil];
    return [self fetchURL:URL
            expectedClass:[NSDictionary class]
               completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchGenreIndexForType:(MRMediaType)type
                              completion:(void (^)(NSArray *json, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"discover/trending/%@/genre/index.json",
                      MRMediaTypeAPIPath(type)];
    NSString *URL = [MRURLBuilder dataURLForPath:path query:nil];
    return [self fetchURL:URL
            expectedClass:[NSArray class]
               completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSArray *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchGenre:(NSString *)slug
                     forType:(MRMediaType)type
                  completion:(void (^)(NSArray *json, NSError *error))completion {
    if (slug.length == 0) {
        MRDeliverOnMain(^{
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindNotFound]);
            }
        });
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"discover/trending/%@/genre/%@_month_500.json",
                      MRMediaTypeAPIPath(type), slug];
    NSString *URL = [MRURLBuilder dataURLForPath:path query:nil];
    return [self fetchURL:URL
            expectedClass:[NSArray class]
               completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSArray *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchDetailForType:(MRMediaType)type
                            simklID:(NSInteger)simklID
                          completion:(void (^)(NSDictionary *json, NSError *error))completion {
    if (simklID <= 0) {
        MRDeliverOnMain(^{
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindNotFound]);
            }
        });
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"%@/%ld",
                      MRMediaTypeAPIPath(type), (long)simklID];
    NSString *URL = [MRURLBuilder apiURLForPath:path query:nil];
    return [self fetchURL:URL
            expectedClass:[NSDictionary class]
               completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

#pragma mark - Authenticated sync reads

static NSString *MRAPIClientSyncTypeKey(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"shows";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movies";
    }
}

- (id<MRHTTPTask>)fetchAuthenticatedPath:(NSString *)path
                                   query:(NSDictionary *)query
                           expectedClass:(Class)expectedClass
                              completion:(void (^)(id json, NSError *error))completion {
    if (path.length == 0) {
        MRDeliverOnMain(^{
            if (completion != nil) {
                completion(nil, [MRError errorWithKind:MRErrorKindUnknown]);
            }
        });
        return nil;
    }

    NSString *URL = [MRURLBuilder apiURLForPath:path query:query];
    MRAPIClientAuthenticatedCall *call =
        [[MRAPIClientAuthenticatedCall alloc] initWithClient:self
                                                         URL:URL
                                                      method:@"GET"
                                                        body:nil
                                         allowsEmptyResponse:NO
                                               expectedClass:expectedClass
                                                  completion:completion];
    [call start];
    return call;
}

- (id<MRHTTPTask>)fetchActivitiesWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    return [self fetchAuthenticatedPath:@"sync/activities"
                                  query:@{ @"language": @"en" }
                          expectedClass:[NSDictionary class]
                             completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchAllItemsForType:(MRMediaType)type
                                status:(MRWatchStatus)status
                              dateFrom:(NSString *)dateFrom
                               idsOnly:(BOOL)idsOnly
                          nextWatchInfo:(BOOL)nextWatchInfo
                             completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"sync/all-items/%@",
                      MRAPIClientSyncTypeKey(type)];
    if (status != MRWatchStatusNone) {
        path = [path stringByAppendingFormat:@"/%@", MRWatchStatusKey(status)];
    }

    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    [query setObject:@"en" forKey:@"language"];
    if (dateFrom != nil) {
        [query setObject:dateFrom forKey:@"date_from"];
    }
    if (idsOnly) {
        [query setObject:@"simkl_ids_only" forKey:@"extended"];
    }
    if (nextWatchInfo) {
        [query setObject:@"yes" forKey:@"next_watch_info"];
    }

    return [self fetchAuthenticatedPath:path
                                  query:query
                          expectedClass:[NSDictionary class]
                             completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchRatingsForType:(MRMediaType)type
                             dateFrom:(NSString *)dateFrom
                           completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"sync/ratings/%@",
                      MRAPIClientSyncTypeKey(type)];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    [query setObject:@"en" forKey:@"language"];
    if (dateFrom != nil) {
        [query setObject:dateFrom forKey:@"date_from"];
    }

    return [self fetchAuthenticatedPath:path
                                  query:query
                          expectedClass:[NSDictionary class]
                             completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

- (id<MRHTTPTask>)fetchUserSettingsWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    return [self fetchAuthenticatedPath:@"users/settings"
                                  query:nil
                          expectedClass:[NSDictionary class]
                             completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
}

#pragma mark - Authenticated writes

static NSString *MRAPIClientWriteTypeKey(MROutboxEntry *entry, BOOL animeAsShows) {
    if (entry.type == MRMediaTypeMovie) {
        return @"movies";
    }
    if (entry.type == MRMediaTypeAnime && !animeAsShows) {
        return @"anime";
    }
    return @"shows";
}

static NSDictionary *MRAPIClientWriteIdentity(MROutboxEntry *entry) {
    return @{ @"ids": @{ @"simkl": @(entry.simklID) } };
}

static void MRAPIClientAppendWriteItem(NSMutableDictionary *body,
                                       NSString *typeKey,
                                       NSDictionary *item) {
    NSMutableArray *items = [body objectForKey:typeKey];
    if (items == nil) {
        items = [NSMutableArray array];
        [body setObject:items forKey:typeKey];
    }
    [items addObject:item];
}

- (id<MRHTTPTask>)postAuthenticatedPath:(NSString *)path
                                   body:(NSDictionary *)body
                             completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSData *data = nil;
    if (body != nil) {
        data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }

    NSString *URL = [MRURLBuilder apiURLForPath:path query:nil];
    MRAPIClientAuthenticatedCall *call =
        [[MRAPIClientAuthenticatedCall alloc] initWithClient:self
                                                         URL:URL
                                                      method:@"POST"
                                                        body:data
                                         allowsEmptyResponse:YES
                                               expectedClass:[NSDictionary class]
                                                  completion:^(id json, NSError *error) {
        if (completion != nil) {
            completion((NSDictionary *)json, error);
        }
    }];
    [call start];
    return call;
}

- (id<MRHTTPTask>)postStatusEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    for (MROutboxEntry *entry in entries) {
        NSMutableDictionary *item =
            [NSMutableDictionary dictionaryWithDictionary:MRAPIClientWriteIdentity(entry)];
        [item setObject:MRWatchStatusKey(entry.status) forKey:@"to"];
        MRAPIClientAppendWriteItem(body,
                                   MRAPIClientWriteTypeKey(entry, NO),
                                   item);
    }
    return [self postAuthenticatedPath:@"sync/add-to-list"
                                  body:body
                            completion:completion];
}

- (id<MRHTTPTask>)postHistoryEntries:(NSArray<MROutboxEntry *> *)entries
                          completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    for (MROutboxEntry *entry in entries) {
        NSMutableDictionary *item =
            [NSMutableDictionary dictionaryWithDictionary:MRAPIClientWriteIdentity(entry)];

        if (entry.kind == MROutboxEntryKindHistoryEpisode) {
            NSDictionary *season = @{
                @"number": @(entry.season),
                @"episodes": @[ @{ @"number": @(entry.episode) } ]
            };
            [item setObject:@[ season ] forKey:@"seasons"];
        } else if (entry.type != MRMediaTypeMovie &&
                   entry.status != MRWatchStatusNone) {
            [item setObject:MRWatchStatusKey(entry.status) forKey:@"status"];
        }

        MRAPIClientAppendWriteItem(body,
                                   MRAPIClientWriteTypeKey(entry, YES),
                                   item);
    }
    return [self postAuthenticatedPath:@"sync/history"
                                  body:body
                            completion:completion];
}

- (id<MRHTTPTask>)postRatingEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    for (MROutboxEntry *entry in entries) {
        NSMutableDictionary *item =
            [NSMutableDictionary dictionaryWithDictionary:MRAPIClientWriteIdentity(entry)];
        [item setObject:@(entry.rating) forKey:@"rating"];
        MRAPIClientAppendWriteItem(body,
                                   MRAPIClientWriteTypeKey(entry, NO),
                                   item);
    }
    return [self postAuthenticatedPath:@"sync/ratings"
                                  body:body
                            completion:completion];
}

- (id<MRHTTPTask>)postRatingRemovalEntries:(NSArray<MROutboxEntry *> *)entries
                                completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    for (MROutboxEntry *entry in entries) {
        MRAPIClientAppendWriteItem(body,
                                   MRAPIClientWriteTypeKey(entry, NO),
                                   MRAPIClientWriteIdentity(entry));
    }
    return [self postAuthenticatedPath:@"sync/ratings/remove"
                                  body:body
                            completion:completion];
}

- (id<MRHTTPTask>)postRemoveEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    for (MROutboxEntry *entry in entries) {
        MRAPIClientAppendWriteItem(body,
                                   MRAPIClientWriteTypeKey(entry, YES),
                                   MRAPIClientWriteIdentity(entry));
    }
    return [self postAuthenticatedPath:@"sync/history/remove"
                                  body:body
                            completion:completion];
}

@end
