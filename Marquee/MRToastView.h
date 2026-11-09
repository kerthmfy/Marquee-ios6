//
//  MRToastView.h
//  Marquee
//

#import <UIKit/UIKit.h>

// A small dark confirmation toast that fades out after a short delay.
@interface MRToastView : UIView

+ (void)showMessage:(NSString *)message inView:(UIView *)view;
+ (void)showMessage:(NSString *)message
             inView:(UIView *)view
           duration:(NSTimeInterval)duration;

@end
