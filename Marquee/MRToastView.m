//
//  MRToastView.m
//  Marquee
//

#import "MRToastView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"

static const NSInteger MRToastViewTag = 0x4D525453; // 'MRTS'
static const NSTimeInterval MRToastVisibleSeconds = 1.5;

@implementation MRToastView

+ (void)showMessage:(NSString *)message inView:(UIView *)view {
    [self showMessage:message inView:view duration:MRToastVisibleSeconds];
}

+ (void)showMessage:(NSString *)message
             inView:(UIView *)view
           duration:(NSTimeInterval)duration {
    if (view == nil || message.length == 0) {
        return;
    }

    for (UIView *subview in [view.subviews copy]) {
        if (subview.tag == MRToastViewTag) {
            [subview removeFromSuperview];
        }
    }

    UIFont *font = [UIFont boldSystemFontOfSize:12.0];
    CGSize textSize = [message sizeWithFont:font];
    CGFloat width = ceil(textSize.width) + 28.0;
    CGFloat height = 28.0;

    MRToastView *toast =
        [[MRToastView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
    toast.tag = MRToastViewTag;
    toast.backgroundColor = [MRAppearance toastColor];
    toast.alpha = 0.0;
    toast.layer.cornerRadius = 8.0;
    toast.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin;

    UILabel *label = [[UILabel alloc] initWithFrame:toast.bounds];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.text = message;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [toast addSubview:label];

    CGRect bounds = view.bounds;
    toast.center = CGPointMake(CGRectGetMidX(bounds),
                               CGRectGetMaxY(bounds) - 74.0);
    [view addSubview:toast];

    [UIView animateWithDuration:0.15 animations:^{
        toast.alpha = 1.0;
    }];

    __weak MRToastView *weakToast = toast;
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(duration * (NSTimeInterval)NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        MRToastView *strongToast = weakToast;
        if (strongToast == nil) {
            return;
        }
        [UIView animateWithDuration:0.25 animations:^{
            strongToast.alpha = 0.0;
        } completion:^(BOOL finished) {
            [strongToast removeFromSuperview];
        }];
    });
}

@end
