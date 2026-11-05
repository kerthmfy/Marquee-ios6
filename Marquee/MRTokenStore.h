//
//  MRTokenStore.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRTokenSession;

// The persistence boundary for the Simkl token session. MRKeychainTokenStore is
// the production implementation; tests use an in-memory store.
@protocol MRTokenStore <NSObject>

- (MRTokenSession *)loadSession:(NSError **)error;
- (BOOL)saveSession:(MRTokenSession *)session error:(NSError **)error;
- (BOOL)clearSession:(NSError **)error;

@end
