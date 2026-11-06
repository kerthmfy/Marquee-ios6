//
//  MRPosterCardView.m
//  Marquee
//

#import "MRPosterCardView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRMediaItem.h"
#import "MRMediaType.h"
#import "MRPosterImageView.h"

@interface MRPosterCardView ()
@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) MRMediaItem *item;
@end

@implementation MRPosterCardView

- (instancetype)initWithImageCache:(MRImageCache *)imageCache {
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat cardWidth = [MRLayout posterCardWidthForDeviceClass:device];
    CGFloat cardHeight = [MRLayout posterCardHeightForDeviceClass:device];
    CGFloat imageHeight = [MRLayout posterCardImageHeightForDeviceClass:device];
    CGFloat scale = cardWidth / 100.0;

    self = [super initWithFrame:CGRectMake(0.0, 0.0, cardWidth, cardHeight)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _posterView = [[MRPosterImageView alloc] initWithImageCache:imageCache];
        _posterView.frame = CGRectMake(0.0, 0.0, cardWidth, imageHeight);
        _posterView.layer.cornerRadius = 3.0;
        _posterView.layer.masksToBounds = YES;
        [self addSubview:_posterView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                               imageHeight + 4.0 * scale,
                                                               cardWidth,
                                                               28.0 * scale)];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = device == MRDeviceClassTablet
            ? [UIFont boldSystemFontOfSize:13.0]
            : [UIFont boldSystemFontOfSize:11.0];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0,
                                                              imageHeight + 34.0 * scale,
                                                              cardWidth,
                                                              14.0 * scale)];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.font = device == MRDeviceClassTablet
            ? [UIFont systemFontOfSize:11.0]
            : [UIFont systemFontOfSize:10.0];
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

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat scale = width / 100.0;
    CGFloat imageHeight = [MRLayout posterCardImageHeightForDeviceClass:device];

    self.posterView.frame = CGRectMake(0.0, 0.0, width, imageHeight);
    self.titleLabel.frame = CGRectMake(0.0, imageHeight + 4.0 * scale,
                                       width, 28.0 * scale);
    self.metaLabel.frame = CGRectMake(0.0, imageHeight + 34.0 * scale,
                                      width, 14.0 * scale);
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
