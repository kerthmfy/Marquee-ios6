//
//  MRBannerView.h
//  Marquee
//

#import <UIKit/UIKit.h>
#import "MRBannerStyle.h"

// A slim status banner shown below the navigation bar. It carries a short
// message and an optional Retry button.
@interface MRBannerView : UIView

@property (nonatomic, copy) void (^retryHandler)(void);
@property (nonatomic, copy, readonly) NSString *message;
@property (nonatomic, assign, readonly) MRBannerStyle style;

+ (CGFloat)height;

- (void)showMessage:(NSString *)message
              style:(MRBannerStyle)style
         retryTitle:(NSString *)retryTitle;
- (void)hide;

@end
