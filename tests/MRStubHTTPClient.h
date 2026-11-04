//
//  MRStubHTTPClient.h
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRHTTPClient.h"

// Records every request and returns queued responses in FIFO order. This is a
// Foundation-only test double; completions are delivered synchronously from
// -sendRequest:completion: and end up on the main queue at the API client.
@interface MRStubHTTPClient : NSObject <MRHTTPClient>

@property (nonatomic, readonly) NSArray *requests;

- (void)enqueueResponse:(MRHTTPResponse *)response;
- (void)enqueueResponses:(NSArray *)responses;

- (NSUInteger)requestCount;
- (MRHTTPRequest *)requestAtIndex:(NSUInteger)index;
- (MRHTTPRequest *)lastRequest;

@end
