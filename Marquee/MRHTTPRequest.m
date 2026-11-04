//
//  MRHTTPRequest.m
//  Marquee
//

#import "MRHTTPRequest.h"

@implementation MRHTTPRequest

- (instancetype)init {
    return [self initWithURL:nil method:nil];
}

- (instancetype)initWithURL:(NSString *)URL method:(NSString *)method {
    self = [super init];
    if (self) {
        _URL = [URL copy];
        _method = [method length] > 0 ? [method copy] : @"GET";
        _timeout = 30.0;
        _queueKind = MRHTTPQueueKindAPI;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MRHTTPRequest *copy = [[[self class] allocWithZone:zone] initWithURL:self.URL method:self.method];
    copy.headers = self.headers;
    copy.body = self.body;
    copy.timeout = self.timeout;
    copy.queueKind = self.queueKind;
    return copy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ %@>", NSStringFromClass([self class]),
            self.method, self.URL];
}

@end
