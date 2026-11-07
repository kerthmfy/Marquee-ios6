#import <UIKit/UIKit.h>

@class MRAppEnvironment;

@interface MRRootTabBarController : UITabBarController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment;

@end
