//
//  MRDetailPosterPanelView.m
//  Marquee
//

#import "MRDetailPosterPanelView.h"

#import "MRAppearance.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRMediaItem.h"
#import "MRPosterImageView.h"

static NSString *MRPanelRatingText(NSDictionary *ratings) {
    for (NSString *key in @[ @"simkl", @"imdb", @"mal" ]) {
        id entry = [ratings isKindOfClass:[NSDictionary class]] ? ratings[key] : nil;
        if ([entry isKindOfClass:[NSDictionary class]]) {
            entry = entry[@"rating"];
        }
        if (entry == nil || entry == [NSNull null] ||
            ![entry respondsToSelector:@selector(doubleValue)]) {
            continue;
        }
        double rating = [entry doubleValue];
        if (rating > 0.0) {
            return [NSString stringWithFormat:@"%.1f", rating];
        }
    }
    return nil;
}

static NSString *MRPanelGenresText(NSArray *genres) {
    NSMutableArray *names = [NSMutableArray array];
    for (id genre in genres) {
        if ([genre isKindOfClass:[NSString class]] && [genre length] > 0) {
            [names addObject:genre];
        }
    }
    return [names componentsJoinedByString:@", "];
}

@interface MRDetailPosterPanelView ()

@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *headlineLabel;
@property (nonatomic, strong) UILabel *factsLabel;
@property (nonatomic, strong) UILabel *genresLabel;
@property (nonatomic, assign) BOOL hasContent;
@property (nonatomic, assign) BOOL showsPoster;

@end

@implementation MRDetailPosterPanelView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [MRAppearance styleCardView:self first:YES last:YES];

        _posterView = [[MRPosterImageView alloc] initWithImageCache:nil];
        _posterView.contentMode = UIViewContentModeScaleAspectFill;
        [MRAppearance stylePosterThumbnailView:_posterView];
        [self addSubview:_posterView];

        _headlineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _headlineLabel.backgroundColor = [UIColor clearColor];
        _headlineLabel.textColor = [MRAppearance ink];
        _headlineLabel.numberOfLines = 1;
        _headlineLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_headlineLabel];

        _factsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _factsLabel.backgroundColor = [UIColor clearColor];
        _factsLabel.textColor = [MRAppearance muted];
        _factsLabel.numberOfLines = 0;
        _factsLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:_factsLabel];

        _genresLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _genresLabel.backgroundColor = [UIColor clearColor];
        _genresLabel.textColor = [MRAppearance muted];
        _genresLabel.numberOfLines = 2;
        _genresLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:_genresLabel];
    }
    return self;
}

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache {
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    BOOL tablet = device == MRDeviceClassTablet;
    self.headlineLabel.font = tablet ? [UIFont boldSystemFontOfSize:15.0]
                                     : [UIFont boldSystemFontOfSize:12.0];
    self.factsLabel.font = tablet ? [UIFont systemFontOfSize:13.0]
                                  : [UIFont systemFontOfSize:11.0];
    self.genresLabel.font = tablet ? [UIFont systemFontOfSize:13.0]
                                   : [UIFont systemFontOfSize:11.0];

    [self.posterView setImageCache:imageCache];
    self.showsPoster = item.poster.length > 0;
    if (self.showsPoster) {
        [self.posterView setImagePath:item.poster size:@"_m"];
    } else {
        [self.posterView setImageURL:nil];
    }
    self.posterView.hidden = !self.showsPoster;

    NSMutableArray *headline = [NSMutableArray array];
    NSString *rating = MRPanelRatingText(item.ratings);
    if (rating.length > 0) {
        [headline addObject:[NSString stringWithFormat:@"★ %@", rating]];
    }
    if (item.runtime > 0) {
        [headline addObject:[NSString stringWithFormat:@"%ld min", (long)item.runtime]];
    }
    if (item.certification.length > 0) {
        [headline addObject:item.certification];
    }
    self.headlineLabel.text = [headline componentsJoinedByString:@" · "];

    NSMutableArray *facts = [NSMutableArray array];
    if (item.type == MRMediaTypeMovie) {
        if (item.director.length > 0) {
            [facts addObject:[NSString stringWithFormat:@"Director  %@", item.director]];
        }
    } else if (item.network.length > 0) {
        [facts addObject:[NSString stringWithFormat:@"Network  %@", item.network]];
    }
    NSString *yearText = nil;
    if (item.year > 0) {
        yearText = [NSString stringWithFormat:@"%ld", (long)item.year];
    } else if (item.releaseDate.length >= 4) {
        yearText = [item.releaseDate substringToIndex:4];
    }
    if (yearText.length > 0) {
        NSString *label = item.type == MRMediaTypeMovie ? @"Released" : @"First aired";
        [facts addObject:[NSString stringWithFormat:@"%@  %@", label, yearText]];
    }
    if (item.country.length > 0) {
        [facts addObject:[NSString stringWithFormat:@"Country  %@", item.country]];
    }
    if (item.type != MRMediaTypeMovie && item.totalEpisodesCount > 0) {
        [facts addObject:[NSString stringWithFormat:@"Episodes  %ld",
                          (long)item.totalEpisodesCount]];
    }
    self.factsLabel.text = [facts componentsJoinedByString:@"\n"];

    NSString *genres = MRPanelGenresText(item.genres);
    self.genresLabel.text = genres;

    self.hasContent = self.showsPoster ||
        self.headlineLabel.text.length > 0 ||
        self.factsLabel.text.length > 0 ||
        self.genresLabel.text.length > 0;
    self.hidden = !self.hasContent;
    [self setNeedsLayout];
}

- (CGFloat)heightForWidth:(CGFloat)width {
    if (width <= 0.0 || !self.hasContent) {
        return 0.0;
    }

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat pad = tablet ? 16.0 : 12.0;
    CGFloat posterWidth = tablet ? 120.0 : 86.0;
    CGFloat posterHeight = tablet ? 180.0 : 129.0;
    CGFloat gap = tablet ? 16.0 : 12.0;

    CGFloat textWidth = width - pad * 2.0;
    if (self.showsPoster) {
        textWidth -= posterWidth + gap;
    }
    textWidth = MAX(0.0, textWidth);

    CGFloat textHeight = [self textHeightForWidth:textWidth];
    CGFloat posterColumn = self.showsPoster ? posterHeight : 0.0;
    return ceil(pad * 2.0 + MAX(posterColumn, textHeight));
}

- (CGFloat)textHeightForWidth:(CGFloat)width {
    CGFloat height = 0.0;
    height += [self heightForLabel:self.headlineLabel width:width];
    if (self.factsLabel.text.length > 0) {
        if (height > 0.0) {
            height += 6.0;
        }
        height += [self heightForLabel:self.factsLabel width:width];
    }
    if (self.genresLabel.text.length > 0) {
        if (height > 0.0) {
            height += 6.0;
        }
        height += [self heightForLabel:self.genresLabel width:width];
    }
    return height;
}

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.text.length == 0 || width <= 0.0) {
        return 0.0;
    }
    CGSize size = [label.text sizeWithFont:label.font
                        constrainedToSize:CGSizeMake(width, 10000.0)
                            lineBreakMode:label.lineBreakMode];
    return ceil(size.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat pad = tablet ? 16.0 : 12.0;
    CGFloat posterWidth = tablet ? 120.0 : 86.0;
    CGFloat posterHeight = tablet ? 180.0 : 129.0;
    CGFloat gap = tablet ? 16.0 : 12.0;
    CGFloat width = CGRectGetWidth(self.bounds);

    CGFloat textX = pad;
    if (self.showsPoster) {
        self.posterView.frame = CGRectMake(pad, pad, posterWidth, posterHeight);
        textX = pad + posterWidth + gap;
    } else {
        self.posterView.frame = CGRectZero;
    }
    CGFloat textWidth = MAX(0.0, width - textX - pad);

    CGFloat y = pad;
    CGFloat headlineHeight = [self heightForLabel:self.headlineLabel width:textWidth];
    self.headlineLabel.frame = CGRectMake(textX, y, textWidth, headlineHeight);
    y += headlineHeight;

    if (self.factsLabel.text.length > 0) {
        if (headlineHeight > 0.0) {
            y += 6.0;
        }
        CGFloat factsHeight = [self heightForLabel:self.factsLabel width:textWidth];
        self.factsLabel.frame = CGRectMake(textX, y, textWidth, factsHeight);
        y += factsHeight;
    } else {
        self.factsLabel.frame = CGRectZero;
    }

    if (self.genresLabel.text.length > 0) {
        if (y > pad) {
            y += 6.0;
        }
        CGFloat genresHeight = [self heightForLabel:self.genresLabel width:textWidth];
        self.genresLabel.frame = CGRectMake(textX, y, textWidth, genresHeight);
    } else {
        self.genresLabel.frame = CGRectZero;
    }
}

@end
