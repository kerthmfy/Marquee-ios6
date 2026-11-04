#import "MRRootTabBarController.h"

#import "MRForYouViewController.h"
#import "MRLibraryViewController.h"
#import "MRSearchViewController.h"
#import "MRProfileViewController.h"

@implementation MRRootTabBarController

- (id)init
{
    self = [super init];
    if (self) {
        MRForYouViewController *forYou = [[MRForYouViewController alloc] init];
        MRLibraryViewController *library = [[MRLibraryViewController alloc] init];
        MRSearchViewController *search = [[MRSearchViewController alloc] init];
        MRProfileViewController *profile = [[MRProfileViewController alloc] init];

        NSArray *viewControllers = [NSArray arrayWithObjects:
                                    [self navigationControllerWithRoot:forYou title:@"For You"],
                                    [self navigationControllerWithRoot:library title:@"Library"],
                                    [self navigationControllerWithRoot:search title:@"Search"],
                                    [self navigationControllerWithRoot:profile title:@"Profile"],
                                    nil];
        self.viewControllers = viewControllers;
        self.selectedIndex = 0;
    }
    return self;
}

- (UINavigationController *)navigationControllerWithRoot:(UIViewController *)rootViewController title:(NSString *)title
{
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:rootViewController];
    navigationController.tabBarItem =
        [[UITabBarItem alloc] initWithTitle:title image:nil tag:0];
    return navigationController;
}

@end
