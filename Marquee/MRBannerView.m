//
//  MRBannerView.m
//  Marquee
//

#import "MRBannerView.h"

#import "MRAppearance.h"

static const CGFloat MRBannerHeight = 32.0;

@interface MRBannerView ()
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, copy) NSString *retryTitle;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, assign) MRBannerStyle style;
@end

@implementation MRBannerView

+ (CGFloat)height {
    return MRBannerHeight;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.hidden = YES;

        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.backgroundColor = [UIColor clearColor];
        _messageLabel.font = [UIFont boldSystemFontOfSize:11.0];
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_messageLabel];

        _retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _retryButton.backgroundColor = [UIColor clearColor];
        _retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        [_retryButton setTitleColor:[UIColor whiteColor]
                           forState:UIControlStateNormal];
        [_retryButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.45]
                           forState:UIControlStateHighlighted];
        [_retryButton addTarget:self
                         action:@selector(retryTapped:)
               forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_retryButton];
    }
    return self;
}

- (void)showMessage:(NSString *)message
              style:(MRBannerStyle)style
         retryTitle:(NSString *)retryTitle {
    self.message = message != nil ? message : @"";
    self.style = style;
    self.retryTitle = retryTitle;
    self.messageLabel.text = self.message;
    [self.retryButton setTitle:retryTitle != nil ? retryTitle : @""
                      forState:UIControlStateNormal];
    self.retryButton.hidden = retryTitle.length == 0;
    self.backgroundColor = [self backgroundColorForStyle:style];
    self.hidden = NO;
    [self setNeedsLayout];
}

- (void)hide {
    self.hidden = YES;
}

- (UIColor *)backgroundColorForStyle:(MRBannerStyle)style {
    switch (style) {
        case MRBannerStylePending:
            return [MRAppearance bannerPendingColor];
        case MRBannerStyleWarning:
            return [MRAppearance bannerWarningColor];
        case MRBannerStyleError:
            return [MRAppearance bannerErrorColor];
        case MRBannerStyleNeutral:
        default:
            return [MRAppearance bannerNeutralColor];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat retryWidth = self.retryButton.hidden ? 0.0 : 58.0;
    CGFloat inset = 12.0;

    self.messageLabel.frame =
        CGRectMake(inset, 0.0, MAX(0.0, width - inset * 2.0 - retryWidth), height);
    self.retryButton.frame =
        CGRectMake(width - inset - retryWidth, 0.0, retryWidth, height);
}

- (void)retryTapped:(UIButton *)sender {
    if (self.retryHandler != nil) {
        self.retryHandler();
    }
}

@end
