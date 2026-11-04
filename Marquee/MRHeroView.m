//
//  MRHeroView.m
//  Marquee
//

#import "MRHeroView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"

@interface MRHeroView ()
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@end

@implementation MRHeroView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 9.0;
        self.layer.masksToBounds = YES;

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.colors = @[
            (__bridge id)[UIColor colorWithRed:0.20 green:0.23 blue:0.27 alpha:1.0].CGColor,
            (__bridge id)[UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0].CGColor
        ];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(0.0, 1.0);
        [self.layer addSublayer:_gradientLayer];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:21.0];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [UIFont systemFontOfSize:12.0];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.78];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        _actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_actionButton setBackgroundImage:[MRAppearance actionButtonImage]
                                 forState:UIControlStateNormal];
        _actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [_actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_actionButton setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                                  forState:UIControlStateNormal];
        _actionButton.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        [_actionButton addTarget:self
                          action:@selector(handleAction:)
                forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               buttonTitle:(NSString *)buttonTitle {
    self.titleLabel.text = title != nil ? title : @"";
    self.subtitleLabel.text = subtitle != nil ? subtitle : @"";
    [self.actionButton setTitle:buttonTitle forState:UIControlStateNormal];
    self.actionButton.hidden = buttonTitle.length == 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gradientLayer.frame = self.bounds;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat leftInset = 16.0;
    CGFloat textWidth = width - leftInset * 2.0;

    CGFloat buttonHeight = 34.0;
    CGFloat buttonWidth = 160.0;
    BOOL hasButton = !self.actionButton.hidden;

    if (hasButton) {
        self.actionButton.frame = CGRectMake(leftInset,
                                             height - 16.0 - buttonHeight,
                                             buttonWidth,
                                             buttonHeight);
        self.subtitleLabel.frame = CGRectMake(leftInset,
                                              CGRectGetMinY(self.actionButton.frame) - 8.0 - 34.0,
                                              textWidth,
                                              34.0);
        self.titleLabel.frame = CGRectMake(leftInset,
                                           CGRectGetMinY(self.subtitleLabel.frame) - 30.0,
                                           textWidth,
                                           30.0);
    } else {
        self.titleLabel.frame = CGRectMake(leftInset,
                                           height / 2.0 - 38.0,
                                           textWidth,
                                           30.0);
        self.subtitleLabel.frame = CGRectMake(leftInset,
                                              height / 2.0 - 6.0,
                                              textWidth,
                                              34.0);
    }
}

- (void)handleAction:(UIButton *)sender {
    if (self.actionHandler != nil) {
        self.actionHandler();
    }
}

@end
