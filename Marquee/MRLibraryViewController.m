#import "MRLibraryViewController.h"

@implementation MRLibraryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Library";
    self.view.backgroundColor = [UIColor whiteColor];

    UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:22.0];
    label.text = @"Library";
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
}

@end
