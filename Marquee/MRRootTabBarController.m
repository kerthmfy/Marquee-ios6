#import "MRRootTabBarController.h"

#import "MRAppearance.h"
#import "MRForYouViewController.h"
#import "MRLibraryViewController.h"
#import "MRSearchViewController.h"
#import "MRProfileViewController.h"

@interface MRRootTabBarController ()
@property (nonatomic, assign) CGFloat styledTabBarWidth;
- (void)restyleTabBarIfNeeded;
@end

@implementation MRRootTabBarController

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // UITabBar can finish creating its item views after -init. Reapply the
    // chrome once the bar is on screen so the iOS 6 selection panel and icons
    // are present on the first launch.
    [self restyleTabBarIfNeeded];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self restyleTabBarIfNeeded];
}

- (void)restyleTabBarIfNeeded
{
    CGFloat width = CGRectGetWidth(self.tabBar.bounds);
    if (width <= 0.0 || width == self.styledTabBarWidth) {
        return;
    }

    [MRAppearance styleTabBar:self.tabBar];
    self.styledTabBarWidth = width;
}

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

        [MRAppearance styleTabBar:self.tabBar];
    }
    return self;
}

- (UINavigationController *)navigationControllerWithRoot:(UIViewController *)rootViewController title:(NSString *)title
{
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:rootViewController];
    [MRAppearance styleNavigationBar:navigationController.navigationBar];
    navigationController.tabBarItem =
        [[UITabBarItem alloc] initWithTitle:title image:nil tag:0];
    return navigationController;
}

@end
