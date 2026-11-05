//
//  MRConnectViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRSimklAuth;
@class MRTokenSession;

// The modal AUTH V2 device/PIN screen. Present it inside a
// UINavigationController. The controller starts the flow on appearance and
// dismisses itself after the token and profile are available.
@interface MRConnectViewController : UIViewController

- (instancetype)initWithAuth:(MRSimklAuth *)auth;

// Called after a successful sign-in, or when the screen is dismissed. The
// session is nil when the user cancelled.
@property (nonatomic, copy) void (^completionHandler)(MRTokenSession *session);

@end
