//
//  MRRowHeaderView.m
//  Marquee
//

#import "MRRowHeaderView.h"

#import "MRAppearance.h"
#import "MRLayout.h"

static const CGFloat MRRowHeaderBadgeSide = 16.0;

@interface MRRowHeaderView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *badgeView;
@end

@implementation MRRowHeaderView

- (instancetype)initWithTitle:(NSString *)title showsSimklBadge:(BOOL)showsSimklBadge {
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    self = [super initWithFrame:CGRectMake(0.0, 0.0,
        [MRLayout contentMaxWidthForDeviceClass:device],
        [MRLayout rowHeaderHeightForDeviceClass:device])];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        // Plain table headers pin to the top while scrolling. Use an opaque
        // charcoal bar so rows scrolling underneath cannot show through.
        self.backgroundColor = [MRAppearance chromeBarColor];
        self.opaque = YES;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance rowHeaderFont];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.65];
        _titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        _titleLabel.text = title != nil ? title : @"";
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        if (showsSimklBadge) {
            _badgeView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SimklBadge.png"]];
            _badgeView.contentMode = UIViewContentModeScaleAspectFit;
            _badgeView.backgroundColor = [UIColor clearColor];
            [self addSubview:_badgeView];
        }

        [self setNeedsLayout];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat width = CGRectGetWidth(self.bounds);
    CGSize titleSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font];
    CGFloat titleWidth = ceil(titleSize.width);

    if (self.badgeView != nil) {
        CGFloat available = width - inset * 2.0 -
            MRRowHeaderBadgeSide - 6.0;
        if (titleWidth > available) {
            titleWidth = MAX(available, 0.0);
        }
    } else {
        titleWidth = width - inset * 2.0;
    }

    CGFloat titleY = device == MRDeviceClassTablet
        ? (height - 17.0) / 2.0
        : 9.0;
    self.titleLabel.frame = CGRectMake(inset,
                                       titleY,
                                       titleWidth,
                                       17.0);

    if (self.badgeView != nil) {
        self.badgeView.frame = CGRectMake(inset + titleWidth + 6.0,
                                          (height - MRRowHeaderBadgeSide) / 2.0,
                                          MRRowHeaderBadgeSide,
                                          MRRowHeaderBadgeSide);
    }
}

- (void)drawRect:(CGRect)rect {
    CGFloat scale = self.contentScaleFactor;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGFloat hairline = 1.0 / scale;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL) {
        return;
    }

    NSArray *colors = @[
        (__bridge id)[UIColor colorWithWhite:0.22 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0.16 alpha:1.0].CGColor
    ];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)colors,
                                                        NULL);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, height),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    [[UIColor colorWithWhite:1.0 alpha:0.030] setFill];
    for (CGFloat x = 0.0; x < width; x += 4.0) {
        CGContextFillRect(ctx, CGRectMake(x, 0.0, 1.0, height));
    }

    [[UIColor colorWithWhite:1.0 alpha:0.040] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width, hairline));
    [[UIColor colorWithWhite:0.0 alpha:0.72] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, height - hairline, width, hairline));
}

@end
