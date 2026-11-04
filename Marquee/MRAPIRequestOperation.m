//
//  MRAPIRequestOperation.m
//  Marquee
//

#import "MRAPIRequestOperation.h"

@implementation MRAPIRequestOperation {
    BOOL _executing;
    BOOL _finished;
    NSURLConnection *_connection;
    NSMutableData *_buffer;
    NSHTTPURLResponse *_httpResponse;
    void (^_completion)(MRHTTPResponse *response);
}

+ (instancetype)sharedClient {
    static MRAPIRequestOperation *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[MRAPIRequestOperation alloc] init];
    });
    return client;
}

+ (NSOperationQueue *)apiQueue {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        queue.name = @"com.marquee.api";
    });
    return queue;
}

+ (NSOperationQueue *)catalogQueue {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 2;
        queue.name = @"com.marquee.catalog";
    });
    return queue;
}

- (instancetype)initWithRequest:(MRHTTPRequest *)request
                     completion:(void (^)(MRHTTPResponse *response))completion {
    self = [super init];
    if (self) {
        _request = [request copy];
        _completion = [completion copy];
    }
    return self;
}

#pragma mark - MRHTTPClient

- (id<MRHTTPTask>)sendRequest:(MRHTTPRequest *)request
                   completion:(void (^)(MRHTTPResponse *response))completion {
    MRAPIRequestOperation *operation = [[MRAPIRequestOperation alloc] initWithRequest:request
                                                                           completion:completion];
    NSOperationQueue *queue = (request.queueKind == MRHTTPQueueKindCatalog)
        ? [[self class] catalogQueue]
        : [[self class] apiQueue];
    [queue addOperation:operation];
    return operation;
}

#pragma mark - NSOperation

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    @synchronized(self) {
        return _executing;
    }
}

- (BOOL)isFinished {
    @synchronized(self) {
        return _finished;
    }
}

- (void)cancel {
    [super cancel];
    NSURLConnection *connection = nil;
    @synchronized(self) {
        connection = _connection;
    }
    [connection cancel];
}

- (void)start {
    if (self.isCancelled) {
        [self finishWithResponse:[self cancelledResponse]];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    @synchronized(self) {
        _executing = YES;
    }
    [self didChangeValueForKey:@"isExecuting"];

    if (self.request.URL.length == 0) {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorBadURL
                                         userInfo:nil];
        [self finishWithResponse:[MRHTTPResponse responseWithStatusCode:0
                                                                headers:nil
                                                                   data:nil
                                                         transportError:error]];
        return;
    }

    NSURL *URL = [NSURL URLWithString:self.request.URL];
    if (URL == nil) {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorBadURL
                                         userInfo:nil];
        [self finishWithResponse:[MRHTTPResponse responseWithStatusCode:0
                                                                headers:nil
                                                                   data:nil
                                                         transportError:error]];
        return;
    }

    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:URL];
    urlRequest.HTTPMethod = self.request.method.length > 0 ? self.request.method : @"GET";
    urlRequest.timeoutInterval = self.request.timeout > 0 ? self.request.timeout : 30.0;
    urlRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (self.request.body.length > 0) {
        urlRequest.HTTPBody = self.request.body;
    }
    for (NSString *header in self.request.headers) {
        id value = [self.request.headers objectForKey:header];
        if (value != nil) {
            [urlRequest setValue:[value description] forHTTPHeaderField:header];
        }
    }

    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:urlRequest
                                                                 delegate:self
                                                         startImmediately:NO];
    @synchronized(self) {
        _connection = connection;
        _buffer = [NSMutableData data];
    }
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [connection start];

    while (![self isFinished]) {
        if (self.isCancelled) {
            break;
        }
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }

    if (self.isCancelled && ![self isFinished]) {
        [connection cancel];
        [self finishWithResponse:[self cancelledResponse]];
    }
}

#pragma mark - NSURLConnection delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    @synchronized(self) {
        _httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? (NSHTTPURLResponse *)response
            : nil;
        _buffer = [NSMutableData data];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    @synchronized(self) {
        [_buffer appendData:data];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    MRHTTPResponse *response = nil;
    @synchronized(self) {
        response = [MRHTTPResponse responseWithStatusCode:_httpResponse.statusCode
                                                  headers:_httpResponse.allHeaderFields
                                                     data:[_buffer copy]
                                           transportError:nil];
    }
    [self finishWithResponse:response];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    MRHTTPResponse *response = nil;
    @synchronized(self) {
        response = [MRHTTPResponse responseWithStatusCode:_httpResponse.statusCode
                                                  headers:_httpResponse.allHeaderFields
                                                     data:[_buffer copy]
                                           transportError:error];
    }
    [self finishWithResponse:response];
}

#pragma mark - Completion

- (MRHTTPResponse *)cancelledResponse {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorCancelled
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"The Simkl request was cancelled."}];
    return [MRHTTPResponse responseWithStatusCode:0
                                         headers:nil
                                            data:nil
                                  transportError:error];
}

- (void)finishWithResponse:(MRHTTPResponse *)response {
    // Checking the guard, mutating state, and sending the KVO notifications must
    // happen under one lock; otherwise two threads can both pass the guard and
    // deliver two completions.
    @synchronized(self) {
        if (_finished) {
            return;
        }

        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        _executing = NO;
        _finished = YES;
        _response = response;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }

    void (^completion)(MRHTTPResponse *) = _completion;
    if (completion != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(response);
        });
    }
}

@end
