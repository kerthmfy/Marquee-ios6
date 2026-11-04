//
//  MRHTTPResponse.m
//  Marquee
//

#import "MRHTTPResponse.h"

@implementation MRHTTPResponse

- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(NSDictionary *)headers
                              data:(NSData *)data
                    transportError:(NSError *)transportError {
    self = [super init];
    if (self) {
        _statusCode = statusCode;
        _headers = [headers copy];
        _data = [data copy];
        _transportError = transportError;
    }
    return self;
}

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode
                               headers:(NSDictionary *)headers
                                  data:(NSData *)data
                        transportError:(NSError *)transportError {
    return [[self alloc] initWithStatusCode:statusCode
                                    headers:headers
                                       data:data
                             transportError:transportError];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: status %ld, %lu bytes%@>",
            NSStringFromClass([self class]), (long)self.statusCode,
            (unsigned long)self.data.length,
            self.transportError ? @", transport error" : @""];
}

@end
