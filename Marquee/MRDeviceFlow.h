//
//  MRDeviceFlow.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRDeviceCode;
@class MRDiagnostics;
@class MRTokenSession;
@protocol MRClock;
@protocol MRHTTPClient;

// The AUTH V2 device/PIN state machine. It owns the device code and the poll
// schedule; callers only start, poll, and cancel. Every state change and
// completion is delivered on the main thread.
@interface MRDeviceFlow : NSObject

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                        diagnostics:(MRDiagnostics *)diagnostics
                              clock:(id<MRClock>)clock;

- (void)startWithCompletion:(void (^)(MRDeviceCode *code, NSError *error))completion;
- (void)pollWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion;
- (void)cancel;

@end
