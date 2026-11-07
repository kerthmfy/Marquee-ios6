#import <UIKit/UIKit.h>

@class MRAppEnvironment;
@class MRRootTabBarController;

@interface MRAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) MRRootTabBarController *rootTabBarController;
@property (nonatomic, strong) MRAppEnvironment *environment;

@end
