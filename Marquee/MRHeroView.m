//
//  MRHeroView.m
//  Marquee
//

#import "MRHeroView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"
#import "MRImageCache.h"
#import "MRURLBuilder.h"

static const CGFloat MRHeroLeftInset = 16.0;
static const CGFloat MRHeroBottomInset = 14.0;
static const CGFloat MRHeroButtonHeight = 34.0;
static const CGFloat MRHeroButtonWidth = 150.0;

@interface MRHeroView ()
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) CAGradientLayer *scrimLayer;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) id artworkToken;
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

        _artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _artworkView.backgroundColor = [UIColor clearColor];
        _artworkView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkView.clipsToBounds = YES;
        _artworkView.hidden = YES;
        [self addSubview:_artworkView];

        _scrimLayer = [CAGradientLayer layer];
        _scrimLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.55].CGColor,
            (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.90].CGColor
        ];
        _scrimLayer.locations = @[ @0.12, @0.55, @1.0 ];
        _scrimLayer.startPoint = CGPointMake(0.0, 0.0);
        _scrimLayer.endPoint = CGPointMake(0.0, 1.0);
        _scrimLayer.hidden = YES;
        [self.layer addSublayer:_scrimLayer];

        _eyebrowLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _eyebrowLabel.backgroundColor = [UIColor clearColor];
        _eyebrowLabel.font = [UIFont boldSystemFontOfSize:10.0];
        _eyebrowLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
        _eyebrowLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_eyebrowLabel];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:21.0];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _metadataLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metadataLabel.backgroundColor = [UIColor clearColor];
        _metadataLabel.font = [UIFont systemFontOfSize:12.0];
        _metadataLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
        _metadataLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_metadataLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [UIFont systemFontOfSize:12.0];
        _subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.78];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        NSArray *textLabels = @[ _eyebrowLabel, _titleLabel, _metadataLabel, _subtitleLabel ];
        for (UILabel *label in textLabels) {
            label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
            label.shadowOffset = CGSizeMake(0.0, 1.0);
        }

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

- (void)dealloc {
    [self cancelArtwork];
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                   eyebrow:(NSString *)eyebrow
                  metadata:(NSString *)metadata
               buttonTitle:(NSString *)buttonTitle {
    self.eyebrowLabel.text = eyebrow.length > 0 ? [eyebrow uppercaseString] : @"";
    self.eyebrowLabel.hidden = eyebrow.length == 0;

    self.titleLabel.text = title != nil ? title : @"";

    self.metadataLabel.text = metadata != nil ? metadata : @"";
    self.metadataLabel.hidden = metadata.length == 0;

    self.subtitleLabel.text = subtitle != nil ? subtitle : @"";
    self.subtitleLabel.hidden = subtitle.length == 0;

    [self.actionButton setTitle:buttonTitle forState:UIControlStateNormal];
    self.actionButton.hidden = buttonTitle.length == 0;
    [self setNeedsLayout];
}

- (void)setArtworkFanartPath:(NSString *)fanartPath
                  posterPath:(NSString *)posterPath
                  imageCache:(MRImageCache *)imageCache {
    [self cancelArtwork];
    self.imageCache = imageCache;

    NSString *URL = nil;
    if (fanartPath.length > 0) {
        URL = [MRURLBuilder fanartURLForPath:fanartPath size:@"_medium"];
    } else if (posterPath.length > 0) {
        URL = [MRURLBuilder posterURLForPath:posterPath size:@"_w"];
    }
    if (URL.length == 0 || imageCache == nil) {
        return;
    }

    UIImage *cached = [imageCache cachedImageForURL:URL];
    if (cached != nil) {
        [self showArtwork:cached];
        return;
    }

    __weak MRHeroView *weakSelf = self;
    // The cache retains the request and its completion. Keep the token weak so
    // a pending load cannot form a view -> token -> block -> view cycle.
    __block __weak id loadToken = nil;
    loadToken = [imageCache loadImageForURL:URL completion:^(UIImage *image, NSError *error) {
        MRHeroView *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.artworkToken != loadToken) {
            return;
        }
        strongSelf.artworkToken = nil;
        if (image != nil) {
            [strongSelf showArtwork:image];
        }
    }];
    self.artworkToken = loadToken;
}

- (void)cancelArtwork {
    id token = self.artworkToken;
    self.artworkToken = nil;
    if (token != nil) {
        [self.imageCache cancelLoad:token];
    }
    self.artworkView.image = nil;
    self.artworkView.hidden = YES;
    self.scrimLayer.hidden = YES;
}

- (void)showArtwork:(UIImage *)image {
    self.artworkView.image = image;
    self.artworkView.hidden = NO;
    self.scrimLayer.hidden = NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.gradientLayer.frame = self.bounds;
    self.artworkView.frame = self.bounds;
    self.scrimLayer.frame = self.bounds;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat textWidth = MAX(0.0, width - MRHeroLeftInset * 2.0);
    CGFloat cursorY = height - MRHeroBottomInset;

    BOOL hasButton = !self.actionButton.hidden;
    if (hasButton) {
        self.actionButton.frame = CGRectMake(MRHeroLeftInset,
                                             cursorY - MRHeroButtonHeight,
                                             MRHeroButtonWidth,
                                             MRHeroButtonHeight);
        cursorY -= MRHeroButtonHeight;
    }

    CGFloat subtitleHeight = 0.0;
    if (!self.subtitleLabel.hidden) {
        CGSize size = [self.subtitleLabel.text
            sizeWithFont:self.subtitleLabel.font
            constrainedToSize:CGSizeMake(textWidth, 30.0)
            lineBreakMode:NSLineBreakByTruncatingTail];
        subtitleHeight = MIN(30.0, ceil(size.height));
        cursorY -= 8.0;
        self.subtitleLabel.frame = CGRectMake(MRHeroLeftInset,
                                              cursorY - subtitleHeight,
                                              textWidth,
                                              subtitleHeight);
        cursorY -= subtitleHeight;
    }

    if (!self.metadataLabel.hidden) {
        cursorY -= 4.0;
        self.metadataLabel.frame = CGRectMake(MRHeroLeftInset,
                                              cursorY - 15.0,
                                              textWidth,
                                              15.0);
        cursorY -= 15.0;
    }

    CGSize titleSize = [self.titleLabel.text
        sizeWithFont:self.titleLabel.font
        constrainedToSize:CGSizeMake(textWidth, 50.0)
        lineBreakMode:NSLineBreakByTruncatingTail];
    CGFloat titleHeight = MIN(50.0, MAX(25.0, ceil(titleSize.height)));
    cursorY -= 2.0;
    self.titleLabel.frame = CGRectMake(MRHeroLeftInset,
                                       cursorY - titleHeight,
                                       textWidth,
                                       titleHeight);
    cursorY -= titleHeight;

    if (!self.eyebrowLabel.hidden) {
        cursorY -= 2.0;
        self.eyebrowLabel.frame = CGRectMake(MRHeroLeftInset,
                                             MAX(6.0, cursorY - 12.0),
                                             textWidth,
                                             12.0);
    }
}

- (void)handleAction:(UIButton *)sender {
    if (self.actionHandler != nil) {
        self.actionHandler();
    }
}

@end
