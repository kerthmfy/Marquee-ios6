//
//  MRPlaceholderView.m
//  Marquee
//

#import "MRPlaceholderView.h"

#import "MRAppearance.h"

@interface MRPlaceholderView ()
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL hasAction;
@end

@implementation MRPlaceholderView

- (instancetype)initWithMessage:(NSString *)message actionTitle:(NSString *)actionTitle {
    self = [super initWithFrame:CGRectMake(0.0, 0.0, 320.0, 160.0)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        [MRAppearance styleCardView:self first:YES last:YES];

        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.backgroundColor = [UIColor clearColor];
        _messageLabel.font = [MRAppearance bodyFont];
        _messageLabel.textColor = [MRAppearance ink];
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 3;
        _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _messageLabel.text = message != nil ? message : @"";
        [self addSubview:_messageLabel];

        _actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _hasAction = actionTitle.length > 0;
        [_actionButton setBackgroundImage:[MRAppearance actionButtonImage]
                                 forState:UIControlStateNormal];
        _actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [_actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_actionButton setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                                  forState:UIControlStateNormal];
        _actionButton.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        [_actionButton setTitle:(actionTitle != nil ? actionTitle : @"")
                       forState:UIControlStateNormal];
        _actionButton.hidden = !_hasAction;
        [_actionButton addTarget:self
                          action:@selector(handleAction:)
                forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_actionButton];

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
    }
    return self;
}

- (void)setLoading:(BOOL)loading {
    _loading = loading;

    self.actionButton.hidden = loading || !self.hasAction;
    if (loading) {
        self.spinner.hidden = NO;
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);

    self.messageLabel.frame = CGRectMake(24.0, 22.0, width - 48.0, 46.0);

    CGFloat buttonWidth = 160.0;
    CGFloat buttonHeight = 34.0;
    self.actionButton.frame = CGRectMake((width - buttonWidth) / 2.0,
                                         height - 20.0 - buttonHeight,
                                         buttonWidth,
                                         buttonHeight);

    self.spinner.center = CGPointMake(width / 2.0,
                                      height - 20.0 - buttonHeight / 2.0);
}

- (void)handleAction:(UIButton *)sender {
    if (self.actionHandler != nil) {
        self.actionHandler();
    }
}

@end
