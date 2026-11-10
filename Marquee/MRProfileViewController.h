//
//  MRProfileViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAppEnvironment;

// The settings tab: account header, local stats, sync status, recommendation
// preferences, About, Sign Out, and Remove Local Data. Signed out it becomes a
// Connect Simkl card plus About.
@interface MRProfileViewController : UIViewController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment;

@end
