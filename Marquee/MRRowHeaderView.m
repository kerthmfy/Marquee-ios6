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
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance rowHeaderFont];
        _titleLabel.textColor = [MRAppearance muted];
        _titleLabel.text = [(title != nil ? title : @"") uppercaseString];
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

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL) {
        return;
    }
    [[MRAppearance sep] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0,
                                      CGRectGetHeight(self.bounds) - 1.0 / scale,
                                      CGRectGetWidth(self.bounds),
                                      1.0 / scale));
}

@end
