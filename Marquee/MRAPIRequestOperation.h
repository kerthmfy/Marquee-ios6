//
//  MRAPIRequestOperation.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRHTTPClient.h"

// Drives NSURLConnection on its own run loop so requests are cancellable and
// serialized. The operation performs no JSON parsing; it returns the raw body,
// status, headers, and transport error.
@interface MRAPIRequestOperation : NSOperation <MRHTTPTask, MRHTTPClient>

@property (nonatomic, strong, readonly) MRHTTPRequest *request;
@property (nonatomic, strong, readonly) MRHTTPResponse *response;

// The shared client entry point. sendRequest:completion: creates a new
// operation and enqueues it on the API or catalog queue.
+ (instancetype)sharedClient;

+ (NSOperationQueue *)apiQueue;
+ (NSOperationQueue *)catalogQueue;

- (instancetype)initWithRequest:(MRHTTPRequest *)request
                     completion:(void (^)(MRHTTPResponse *response))completion;

@end
