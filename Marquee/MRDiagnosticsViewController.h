//
//  MRDiagnosticsViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAppEnvironment;

// A device-local support screen: identity, sync state, quota, cache sizes,
// recent redacted API errors, Copy Diagnostics, Clear Image Cache, and Force
// Full Sync.
@interface MRDiagnosticsViewController : UIViewController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment;

@end
