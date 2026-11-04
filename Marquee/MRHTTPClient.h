//
//  MRHTTPClient.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"

@protocol MRHTTPTask <NSObject>
- (void)cancel;
@end

@protocol MRHTTPClient <NSObject>
- (id<MRHTTPTask>)sendRequest:(MRHTTPRequest *)request
                   completion:(void (^)(MRHTTPResponse *response))completion;
@end
