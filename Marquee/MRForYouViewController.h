//
//  MRForYouViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAPIClient;
@class MRImageCache;

@interface MRForYouViewController : UIViewController

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                       imageCache:(MRImageCache *)imageCache;

@end
