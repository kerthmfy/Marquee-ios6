//
//  MRHTTPResponse.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Raw transport result. data and transportError are both preserved so callers
// can parse a body even when the connection failed partway through.
@interface MRHTTPResponse : NSObject

@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, copy) NSData *data;
@property (nonatomic, strong) NSError *transportError;

- (instancetype)initWithStatusCode:(NSInteger)statusCode
                           headers:(NSDictionary *)headers
                              data:(NSData *)data
                    transportError:(NSError *)transportError;

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode
                               headers:(NSDictionary *)headers
                                  data:(NSData *)data
                        transportError:(NSError *)transportError;

@end
