//
//  MRStubHTTPClient.m
//  Marquee tests
//

#import "MRStubHTTPClient.h"

@interface MRStubHTTPTask : NSObject <MRHTTPTask>
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation MRStubHTTPTask
- (void)cancel {
    self.cancelled = YES;
}
@end

@implementation MRStubHTTPClient {
    NSMutableArray *_requests;
    NSMutableArray *_responses;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _requests = [NSMutableArray array];
        _responses = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)requests {
    @synchronized(self) {
        return [_requests copy];
    }
}

- (void)enqueueResponse:(MRHTTPResponse *)response {
    if (response == nil) {
        return;
    }
    @synchronized(self) {
        [_responses addObject:response];
    }
}

- (void)enqueueResponses:(NSArray *)responses {
    for (MRHTTPResponse *response in responses) {
        [self enqueueResponse:response];
    }
}

- (NSUInteger)requestCount {
    @synchronized(self) {
        return _requests.count;
    }
}

- (MRHTTPRequest *)requestAtIndex:(NSUInteger)index {
    @synchronized(self) {
        if (index >= _requests.count) {
            return nil;
        }
        return [_requests objectAtIndex:index];
    }
}

- (MRHTTPRequest *)lastRequest {
    @synchronized(self) {
        if (_requests.count == 0) {
            return nil;
        }
        return [_requests lastObject];
    }
}

- (id<MRHTTPTask>)sendRequest:(MRHTTPRequest *)request
                   completion:(void (^)(MRHTTPResponse *response))completion {
    MRHTTPResponse *response = nil;
    @synchronized(self) {
        if (request != nil) {
            [_requests addObject:[request copy]];
        }
        if (_responses.count > 0) {
            response = [_responses objectAtIndex:0];
            [_responses removeObjectAtIndex:0];
        } else {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorUnknown
                                             userInfo:nil];
            response = [MRHTTPResponse responseWithStatusCode:0
                                                     headers:nil
                                                        data:nil
                                              transportError:error];
        }
    }

    MRStubHTTPTask *task = [[MRStubHTTPTask alloc] init];
    if (completion != nil) {
        completion(response);
    }
    return task;
}

@end
