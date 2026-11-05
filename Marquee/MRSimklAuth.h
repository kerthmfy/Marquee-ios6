//
//  MRSimklAuth.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRTokenProviding.h"

@class MRDeviceCode;
@class MRDiagnostics;
@class MRTokenSession;
@protocol MRClock;
@protocol MRHTTPClient;
@protocol MRTokenStore;

// Posted whenever the signed-in state changes. object is the MRSimklAuth.
extern NSString *const MRAuthDidChangeNotification;

// Owns the device flow, the Keychain session, token refresh serialization, and
// the /users/settings identity lookup. Every state change and completion is
// delivered on the main thread.
@interface MRSimklAuth : NSObject <MRTokenProviding>

@property (nonatomic, strong, readonly) MRTokenSession *session;
@property (nonatomic, readonly, getter=isSignedIn) BOOL signedIn;

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                        tokenStore:(id<MRTokenStore>)tokenStore
                       diagnostics:(MRDiagnostics *)diagnostics
                             clock:(id<MRClock>)clock;

- (void)restoreWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion;
- (void)beginDeviceFlowWithCompletion:(void (^)(MRDeviceCode *code, NSError *error))completion;
- (void)pollDeviceFlowWithCompletion:(void (^)(MRTokenSession *session, NSError *error))completion;
- (void)cancelDeviceFlow;
- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion;
- (void)signOut;

@end
