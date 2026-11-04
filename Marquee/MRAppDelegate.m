#import "MRAppDelegate.h"

#import "MRRootTabBarController.h"

@implementation MRAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.rootTabBarController = [[MRRootTabBarController alloc] init];
    self.window.rootViewController = self.rootTabBarController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
