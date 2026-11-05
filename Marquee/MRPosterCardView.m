//
//  MRPosterCardView.m
//  Marquee
//

#import "MRPosterCardView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"
#import "MRImageCache.h"
#import "MRMediaItem.h"
#import "MRMediaType.h"
#import "MRPosterImageView.h"

static const CGFloat MRPosterCardWidth = 100.0;
static const CGFloat MRPosterCardPosterHeight = 150.0;
static const CGFloat MRPosterCardHeight = 210.0;
static const CGFloat MRPosterCardTitleTop = 154.0;
static const CGFloat MRPosterCardTitleHeight = 28.0;
static const CGFloat MRPosterCardMetaTop = 184.0;
static const CGFloat MRPosterCardMetaHeight = 14.0;

@interface MRPosterCardView ()
@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) MRMediaItem *item;
@end

@implementation MRPosterCardView

- (instancetype)initWithImageCache:(MRImageCache *)imageCache {
    self = [super initWithFrame:CGRectMake(0.0, 0.0, MRPosterCardWidth, MRPosterCardHeight)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _posterView = [[MRPosterImageView alloc] initWithImageCache:imageCache];
        _posterView.frame = CGRectMake(0.0, 0.0, MRPosterCardWidth, MRPosterCardPosterHeight);
        _posterView.layer.cornerRadius = 3.0;
        _posterView.layer.masksToBounds = YES;
        [self addSubview:_posterView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                               MRPosterCardTitleTop,
                                                               MRPosterCardWidth,
                                                               MRPosterCardTitleHeight)];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                              MRPosterCardMetaTop,
                                                              MRPosterCardWidth,
                                                              MRPosterCardMetaHeight)];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.font = [UIFont systemFontOfSize:10.0];
        _metaLabel.textColor = [MRAppearance muted];
        _metaLabel.numberOfLines = 1;
        _metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_metaLabel];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setItem:(MRMediaItem *)item {
    _item = item;

    if (item == nil) {
        [_posterView cancelLoading];
        _titleLabel.text = @"";
        _metaLabel.text = @"";
        return;
    }

    [_posterView setImagePath:item.poster size:@"_m"];
    _titleLabel.text = item.title;

    NSString *type = MRMediaTypeDisplayName(item.type);
    if (item.year > 0) {
        _metaLabel.text = [NSString stringWithFormat:@"%ld · %@", (long)item.year, type];
    } else {
        _metaLabel.text = type;
    }
}

- (void)cancelLoading {
    [_posterView cancelLoading];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }
    if (self.tapHandler != nil && self.item != nil) {
        self.tapHandler(self.item);
    }
}

@end
