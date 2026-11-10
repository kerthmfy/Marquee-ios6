//
//  MRDiagnosticsReport.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Builds the plain-text report used by Copy Diagnostics. The builder is pure:
// it never reads the Keychain, the network, or device state. Every supplied
// value is scrubbed for token-bearing text before it is emitted.
@interface MRDiagnosticsReport : NSObject

// Recognized keys: appVersion, build, osVersion, deviceModel, accountName,
// accountID, lastSyncAttempt, lastSyncResult, pendingCount, requestsToday,
// quotaLimit, quotaRemaining, quotaResetAt, cacheBytes, errors.
+ (NSString *)reportWithFields:(NSDictionary *)fields;

@end
