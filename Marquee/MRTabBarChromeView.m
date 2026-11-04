//
//  MRTabBarChromeView.m
//  Marquee
//

#import "MRTabBarChromeView.h"

@implementation MRTabBarChromeView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    UITabBar *bar = (UITabBar *)self.superview;
    if (![bar isKindOfClass:[UITabBar class]]) {
        return;
    }

    NSInteger count = bar.items.count;
    if (count < 2) {
        return;
    }

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGFloat hairline = 1.0 / scale;
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // iOS 6 store bars separated items with a white and black hairline pair,
    // not with a floating selection capsule.
    for (NSInteger i = 1; i < count; i++) {
        CGFloat x = floor(width * (CGFloat)i / (CGFloat)count);
        [[UIColor colorWithWhite:1.0 alpha:0.10] setFill];
        CGContextFillRect(ctx, CGRectMake(x - hairline, 1.0, hairline, height - 1.0));
        [[UIColor colorWithWhite:0.0 alpha:0.65] setFill];
        CGContextFillRect(ctx, CGRectMake(x, 1.0, hairline, height - 1.0));
    }
}

@end
