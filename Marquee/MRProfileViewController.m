#import "MRProfileViewController.h"

@implementation MRProfileViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Profile";
    self.view.backgroundColor = [UIColor whiteColor];

    UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:22.0];
    label.text = @"Profile";
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
}

@end
