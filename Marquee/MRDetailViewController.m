//
//  MRDetailViewController.m
//  Marquee
//

#import "MRDetailViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAPIClient.h"
#import "MRAppearance.h"
#import "MRBannerView.h"
#import "MRDetailActions.h"
#import "MRError.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRPlaceholderView.h"
#import "MRPosterCardView.h"
#import "MRPosterImageView.h"
#import "MRStarRatingView.h"
#import "MRStatusPillView.h"
#import "MRToastView.h"
#import "MRURLBuilder.h"
#import "MRWriteResult.h"
#import "MRWriteService.h"

static const CGFloat MRDetailCardGap = 12.0;

static const NSInteger MRDetailSheetChangeStatus = 1001;
static const NSInteger MRDetailSheetRemove = 1002;

static MRDeviceClass MRDetailDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static NSString *MRDetailRating(NSDictionary *ratings, NSString *key) {
    id entry = [ratings isKindOfClass:[NSDictionary class]] ? [ratings objectForKey:key] : nil;
    if ([entry isKindOfClass:[NSDictionary class]]) {
        entry = [entry objectForKey:@"rating"];
    }
    if (entry == nil || entry == [NSNull null]) {
        return nil;
    }
    if (![entry respondsToSelector:@selector(doubleValue)]) {
        return nil;
    }
    double rating = [entry doubleValue];
    if (rating <= 0.0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%.1f", rating];
}

static NSString *MRDetailShortDate(NSString *value) {
    if (value.length < 10) {
        return value;
    }
    if ([value characterAtIndex:4] == '-' &&
        [value characterAtIndex:7] == '-') {
        return [value substringToIndex:10];
    }
    return value;
}

static NSString *MRDetailCapitalized(NSString *value) {
    if (value.length == 0) {
        return value;
    }
    return [value stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                          withString:[[value substringToIndex:1] uppercaseString]];
}

static NSString *MRDetailJoinedGenres(NSArray *genres) {
    NSMutableArray *names = [NSMutableArray array];
    for (id genre in genres) {
        if ([genre isKindOfClass:[NSString class]] && [genre length] > 0) {
            [names addObject:genre];
        }
    }
    return [names componentsJoinedByString:@" · "];
}

static NSString *MRDetailEpisodesText(MRMediaItem *item) {
    if (item.totalEpisodesCount <= 0) {
        return nil;
    }
    if (item.watchedEpisodesCount > 0) {
        return [NSString stringWithFormat:@"%ld of %ld",
                (long)item.watchedEpisodesCount, (long)item.totalEpisodesCount];
    }
    return [NSString stringWithFormat:@"%ld", (long)item.totalEpisodesCount];
}

#pragma mark - Hero

@interface MRDetailHeroView : UIView

@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *genresLabel;
@property (nonatomic, strong) MRStatusPillView *statusPill;
@property (nonatomic, strong) UIButton *simklButton;
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, copy) void (^simklHandler)(void);

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache;

@end

@implementation MRDetailHeroView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
        self.clipsToBounds = YES;

        _posterView = [[MRPosterImageView alloc] initWithImageCache:nil];
        _posterView.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_posterView];

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.82].CGColor
        ];
        _gradientLayer.locations = @[ @0.32, @1.0 ];
        _gradientLayer.startPoint = CGPointMake(0.5, 0.0);
        _gradientLayer.endPoint = CGPointMake(0.5, 1.0);
        [self.layer addSublayer:_gradientLayer];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.65];
        _titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
        _metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _metaLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
        _metaLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_metaLabel];

        _genresLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _genresLabel.backgroundColor = [UIColor clearColor];
        _genresLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
        _genresLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _genresLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        _genresLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:_genresLabel];

        _statusPill = [[MRStatusPillView alloc] initWithFrame:CGRectZero];
        [self addSubview:_statusPill];

        _simklButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _simklButton.backgroundColor = [UIColor clearColor];
        _simklButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _simklButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_simklButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92]
                           forState:UIControlStateNormal];
        [_simklButton setTitle:@"View on Simkl ›" forState:UIControlStateNormal];
        [_simklButton addTarget:self
                         action:@selector(handleSimklTap:)
               forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_simklButton];

        _badgeView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SimklBadge.png"]];
        _badgeView.backgroundColor = [UIColor clearColor];
        _badgeView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_badgeView];
    }
    return self;
}

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache {
    [self.posterView setImageCache:imageCache];
    if (item.fanart.length > 0) {
        [self.posterView setImagePath:item.fanart size:@"_medium"];
    } else if (item.poster.length > 0) {
        [self.posterView setImagePath:item.poster size:@"_w"];
    } else {
        [self.posterView setImageURL:nil];
    }

    self.titleLabel.text = item.title.length > 0 ? item.title : @"Untitled";

    NSMutableArray *meta = [NSMutableArray array];
    if (item.year > 0) {
        [meta addObject:[NSString stringWithFormat:@"%ld", (long)item.year]];
    }
    if (item.runtime > 0) {
        [meta addObject:[NSString stringWithFormat:@"%ld min", (long)item.runtime]];
    }
    [meta addObject:MRMediaTypeDisplayName(item.type)];
    NSString *communityRating = MRDetailRating(item.ratings, @"simkl");
    if (communityRating != nil) {
        [meta addObject:[NSString stringWithFormat:@"★ %@", communityRating]];
    }
    if (item.userRating > 0) {
        [meta addObject:[NSString stringWithFormat:@"Your ★ %ld", (long)item.userRating]];
    }
    self.metaLabel.text = [meta componentsJoinedByString:@" · "];

    NSMutableArray *details = [NSMutableArray array];
    NSString *genres = MRDetailJoinedGenres(item.genres);
    if (genres.length > 0) {
        [details addObject:genres];
    }
    NSString *episodes = MRDetailEpisodesText(item);
    if (episodes != nil && item.type != MRMediaTypeMovie) {
        [details addObject:[episodes stringByAppendingString:@" episodes"]];
    }
    self.genresLabel.text = [details componentsJoinedByString:@" · "];

    [self.statusPill setWatchStatus:item.watchStatus];
    self.simklButton.hidden = item.simklID <= 0;
    self.badgeView.hidden = item.simklID <= 0;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRDetailDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat maxContent = [MRLayout contentMaxWidthForDeviceClass:device];
    CGFloat textInset = (width - MIN(width, maxContent)) / 2.0 + (tablet ? 16.0 : 12.0);
    CGFloat textWidth = MAX(0.0, width - textInset * 2.0);

    self.posterView.frame = self.bounds;
    self.gradientLayer.frame = self.bounds;

    self.titleLabel.font = tablet ? [UIFont boldSystemFontOfSize:28.0]
                                  : [UIFont boldSystemFontOfSize:22.0];
    self.metaLabel.font = tablet ? [UIFont boldSystemFontOfSize:14.0]
                                 : [UIFont boldSystemFontOfSize:12.0];
    self.genresLabel.font = tablet ? [UIFont systemFontOfSize:13.0]
                                   : [UIFont systemFontOfSize:11.0];

    CGFloat bottom = height - (tablet ? 16.0 : 12.0);
    self.simklButton.frame = CGRectMake(textInset, bottom - 20.0, textWidth, 20.0);
    self.badgeView.frame = CGRectMake(CGRectGetMaxX(self.simklButton.frame) - 18.0,
                                      bottom - 18.0, 16.0, 16.0);
    self.genresLabel.frame = CGRectMake(textInset, CGRectGetMinY(self.simklButton.frame) - 4.0 - 16.0,
                                        textWidth, 16.0);
    self.metaLabel.frame = CGRectMake(textInset, CGRectGetMinY(self.genresLabel.frame) - 2.0 - 16.0,
                                      textWidth, 16.0);

    CGFloat titleHeight = tablet ? 68.0 : 48.0;
    self.titleLabel.frame = CGRectMake(textInset, CGRectGetMinY(self.metaLabel.frame) - 4.0 - titleHeight,
                                       textWidth, titleHeight);

    CGSize pillSize = [MRStatusPillView sizeForStatus:self.statusPill.watchStatus];
    self.statusPill.frame = CGRectMake(textInset,
                                       CGRectGetMinY(self.titleLabel.frame) - 4.0 - 16.0,
                                       pillSize.width, pillSize.height);
}

- (void)handleSimklTap:(UIButton *)sender {
    if (self.simklHandler != nil) {
        self.simklHandler();
    }
}

@end

#pragma mark - Related row

@interface MRDetailRelatedView : UIView

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSArray *cards;

+ (CGFloat)heightForDeviceClass:(MRDeviceClass)device;
- (void)configureWithTitle:(NSString *)title
                     items:(NSArray *)items
                imageCache:(MRImageCache *)imageCache
                tapHandler:(void (^)(MRMediaItem *item))tapHandler;

@end

@implementation MRDetailRelatedView

+ (CGFloat)heightForDeviceClass:(MRDeviceClass)device {
    return 30.0 + [MRLayout posterRowHeightForDeviceClass:device] + 8.0;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [MRAppearance styleCardView:self first:YES last:YES];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance groupTitleFont];
        _titleLabel.textColor = [MRAppearance muted];
        [self addSubview:_titleLabel];

        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.alwaysBounceHorizontal = YES;
        [self addSubview:_scrollView];

        _items = @[];
        _cards = @[];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                     items:(NSArray *)items
                imageCache:(MRImageCache *)imageCache
                tapHandler:(void (^)(MRMediaItem *item))tapHandler {
    self.titleLabel.text = [(title != nil ? title : @"") uppercaseString];
    self.items = items != nil ? items : @[];

    for (MRPosterCardView *card in self.cards) {
        [card cancelLoading];
        [card removeFromSuperview];
    }

    NSMutableArray *cards = [NSMutableArray array];
    for (MRMediaItem *item in self.items) {
        MRPosterCardView *card = [[MRPosterCardView alloc] initWithImageCache:imageCache];
        card.tapHandler = tapHandler;
        [card setItem:item];
        [self.scrollView addSubview:card];
        [cards addObject:card];
    }
    self.cards = cards;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRDetailDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat inset = tablet ? 16.0 : 12.0;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat rowHeight = [MRLayout posterRowHeightForDeviceClass:device];
    CGFloat cardWidth = [MRLayout posterCardWidthForDeviceClass:device];
    CGFloat gap = [MRLayout posterCardGapForDeviceClass:device];

    self.titleLabel.frame = CGRectMake(inset, 10.0, MAX(0.0, width - inset * 2.0), 16.0);
    self.scrollView.frame = CGRectMake(0.0, 30.0, width, rowHeight);

    CGFloat x = inset;
    for (MRPosterCardView *card in self.cards) {
        card.frame = CGRectMake(x, 0.0, cardWidth, rowHeight);
        x += cardWidth + gap;
    }

    CGFloat contentWidth = x - gap + inset;
    if (contentWidth < width) {
        contentWidth = width;
    }
    self.scrollView.contentSize = CGSizeMake(contentWidth, rowHeight);
}

@end

#pragma mark - Info row

@interface MRDetailInfoRowView : UIView
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (void)configureName:(NSString *)name value:(NSString *)value;
@end

@implementation MRDetailInfoRowView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [MRAppearance smallFont];
        _nameLabel.textColor = [MRAppearance muted];
        [self addSubview:_nameLabel];

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.backgroundColor = [UIColor clearColor];
        _valueLabel.font = [MRAppearance bodyFont];
        _valueLabel.textColor = [MRAppearance ink];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_valueLabel];
    }
    return self;
}

- (void)configureName:(NSString *)name value:(NSString *)value {
    self.nameLabel.text = name;
    self.valueLabel.text = value;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRDetailDeviceClass();
    CGFloat inset = device == MRDeviceClassTablet ? 16.0 : 12.0;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat nameWidth = floor((width - inset * 2.0) * 0.42);
    CGFloat valueWidth = width - inset * 2.0 - nameWidth - 12.0;

    self.nameLabel.font = device == MRDeviceClassTablet
        ? [UIFont systemFontOfSize:13.0] : [MRAppearance smallFont];
    self.valueLabel.font = device == MRDeviceClassTablet
        ? [UIFont systemFontOfSize:15.0] : [MRAppearance bodyFont];

    self.nameLabel.frame = CGRectMake(inset, 0.0, nameWidth, height);
    self.valueLabel.frame = CGRectMake(inset + nameWidth + 12.0, 0.0,
                                       MAX(0.0, valueWidth), height);
}

- (void)drawRect:(CGRect)rect {
    CGFloat scale = self.contentScaleFactor;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        return;
    }
    [[MRAppearance sep] setFill];
    CGContextFillRect(context, CGRectMake(0.0, CGRectGetHeight(self.bounds) - 1.0 / scale,
                                          CGRectGetWidth(self.bounds), 1.0 / scale));
}

@end

#pragma mark - Action row

@interface MRDetailActionRowView : UIControl

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *chevronLabel;
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, assign) BOOL showsChevron;

- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
               destructive:(BOOL)destructive;

@end

@implementation MRDetailActionRowView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance bodyFont];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.backgroundColor = [UIColor clearColor];
        _valueLabel.font = [MRAppearance smallFont];
        _valueLabel.textColor = [MRAppearance muted];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_valueLabel];

        _chevronLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevronLabel.backgroundColor = [UIColor clearColor];
        _chevronLabel.font = [UIFont boldSystemFontOfSize:14.0];
        _chevronLabel.textColor = [MRAppearance muted];
        _chevronLabel.textAlignment = NSTextAlignmentRight;
        _chevronLabel.text = @"›";
        [self addSubview:_chevronLabel];

        _showsChevron = YES;
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
               destructive:(BOOL)destructive {
    self.destructive = destructive;
    self.titleLabel.text = title;
    self.valueLabel.text = value != nil ? value : @"";
    self.titleLabel.textColor = destructive ? [MRAppearance droppedColor]
                                            : [MRAppearance ink];
}

- (void)setShowsChevron:(BOOL)showsChevron {
    _showsChevron = showsChevron;
    self.chevronLabel.hidden = !showsChevron;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted
        ? [UIColor colorWithWhite:0.0 alpha:0.06]
        : [UIColor clearColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRDetailDeviceClass();
    CGFloat inset = device == MRDeviceClassTablet ? 16.0 : 12.0;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat chevronWidth = self.showsChevron ? 12.0 : 0.0;
    CGFloat valueWidth = floor((width - inset * 2.0) * 0.46);

    self.titleLabel.font = device == MRDeviceClassTablet
        ? [UIFont systemFontOfSize:15.0] : [MRAppearance bodyFont];
    self.valueLabel.font = device == MRDeviceClassTablet
        ? [UIFont systemFontOfSize:13.0] : [MRAppearance smallFont];

    self.chevronLabel.frame = CGRectMake(width - inset - chevronWidth, 0.0,
                                         chevronWidth, height);
    self.valueLabel.frame =
        CGRectMake(width - inset - chevronWidth - valueWidth - 6.0, 0.0,
                   MAX(0.0, valueWidth), height);
    self.titleLabel.frame =
        CGRectMake(inset, 0.0,
                   MAX(0.0, width - inset * 2.0 - valueWidth - chevronWidth - 18.0),
                   height);
}

- (void)drawRect:(CGRect)rect {
    CGFloat scale = self.contentScaleFactor;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        return;
    }
    [[MRAppearance sep] setFill];
    CGContextFillRect(context, CGRectMake(0.0, CGRectGetHeight(self.bounds) - 1.0 / scale,
                                          CGRectGetWidth(self.bounds), 1.0 / scale));
}

@end

#pragma mark - Controller

@interface MRDetailViewController () <UIActionSheetDelegate>

@property (nonatomic, strong) MRMediaItem *item;
@property (nonatomic, strong) MRAPIClient *apiClient;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRWriteService *writeService;
@property (nonatomic, strong) MRDetailActions *actions;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) MRDetailHeroView *heroView;
@property (nonatomic, strong) UIView *actionsCard;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) MRDetailActionRowView *rateRow;
@property (nonatomic, strong) MRStarRatingView *ratingView;
@property (nonatomic, strong) UIButton *removeRatingButton;
@property (nonatomic, strong) MRDetailActionRowView *statusRow;
@property (nonatomic, strong) MRDetailActionRowView *removeRow;
@property (nonatomic, strong) MRBannerView *bannerView;
@property (nonatomic, copy) NSArray *statusChoices;
@property (nonatomic, assign) BOOL ratingExpanded;
@property (nonatomic, assign) BOOL flushing;
@property (nonatomic, assign) BOOL flushAgain;
@property (nonatomic, copy) NSString *removeEntryID;
@property (nonatomic, strong) id libraryObserver;
@property (nonatomic, strong) UIView *offlineCard;
@property (nonatomic, strong) UILabel *offlineLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIView *overviewCard;
@property (nonatomic, strong) UILabel *overviewTitleLabel;
@property (nonatomic, strong) UILabel *overviewBodyLabel;
@property (nonatomic, strong) UIView *infoCard;
@property (nonatomic, strong) UILabel *infoTitleLabel;
@property (nonatomic, copy) NSArray *infoRows;
@property (nonatomic, strong) UIView *nextCard;
@property (nonatomic, strong) UILabel *nextTitleLabel;
@property (nonatomic, strong) UILabel *nextPrimaryLabel;
@property (nonatomic, strong) UILabel *nextSecondaryLabel;
@property (nonatomic, strong) MRDetailRelatedView *similarView;
@property (nonatomic, strong) MRDetailRelatedView *recommendedView;
@property (nonatomic, strong) UIView *footerCard;
@property (nonatomic, strong) UIImageView *footerBadge;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) UIButton *footerLink;
@property (nonatomic, strong) MRPlaceholderView *errorView;

@property (nonatomic, strong) id<MRHTTPTask> detailTask;
@property (nonatomic, strong) NSDictionary *detailDictionary;
@property (nonatomic, copy) NSArray *similarItems;
@property (nonatomic, copy) NSArray *recommendedItems;
@property (nonatomic, assign) BOOL offlineVisible;

@end

@implementation MRDetailViewController

- (instancetype)initWithItem:(MRMediaItem *)item
                   apiClient:(MRAPIClient *)apiClient
                libraryStore:(MRLibraryStore *)libraryStore
                  imageCache:(MRImageCache *)imageCache
                      outbox:(MROutbox *)outbox
                writeService:(MRWriteService *)writeService {
    self = [super init];
    if (self) {
        _item = [item copy];
        _apiClient = apiClient;
        _libraryStore = libraryStore;
        _imageCache = imageCache;
        _outbox = outbox;
        _writeService = writeService;
        if (libraryStore != nil && writeService != nil) {
            _actions = [[MRDetailActions alloc] initWithLibraryStore:libraryStore
                                                              outbox:outbox
                                                        writeService:writeService];
        }
        _similarItems = @[];
        _recommendedItems = @[];
        _infoRows = @[];
    }
    return self;
}

- (instancetype)initWithItem:(MRMediaItem *)item
                   apiClient:(MRAPIClient *)apiClient
                libraryStore:(MRLibraryStore *)libraryStore
                  imageCache:(MRImageCache *)imageCache {
    return [self initWithItem:item
                    apiClient:apiClient
                 libraryStore:libraryStore
                   imageCache:imageCache
                       outbox:nil
                 writeService:nil];
}

- (id)init {
    return [self initWithItem:nil
                    apiClient:nil
                 libraryStore:nil
                   imageCache:nil
                       outbox:nil
                 writeService:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [MRAppearance groupBackground];
    self.title = self.item.title.length > 0 ? self.item.title : @"Details";

    if (self.item == nil) {
        [self buildErrorState];
        return;
    }

    [self buildContent];
    [self updateContent];
    [self fetchDetail];

    __weak MRDetailViewController *weakSelf = self;
    self.libraryObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:MRLibraryDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [weakSelf libraryDidChange];
    }];
}

- (void)dealloc {
    [self.detailTask cancel];
    if (self.libraryObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.libraryObserver];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshItemFromStore];
    [self updateContent];
}

#pragma mark - View construction

- (void)buildErrorState {
    MRPlaceholderView *card =
        [[MRPlaceholderView alloc] initWithMessage:@"This title couldn't be loaded."
                                       actionTitle:nil];
    [self.view addSubview:card];
    self.errorView = card;
}

- (void)buildContent {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.backgroundColor = [MRAppearance groupBackground];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    MRDetailHeroView *hero = [[MRDetailHeroView alloc] initWithFrame:CGRectZero];
    __weak MRDetailViewController *weakSelf = self;
    hero.simklHandler = ^{
        [weakSelf openOnSimkl];
    };
    [scrollView addSubview:hero];
    self.heroView = hero;

    [self buildActionsCard];
    [self buildBanner];

    UIView *offline = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:offline first:YES last:YES];
    UILabel *offlineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    offlineLabel.backgroundColor = [UIColor clearColor];
    offlineLabel.font = [MRAppearance smallFont];
    offlineLabel.textColor = [MRAppearance holdColor];
    offlineLabel.text = @"Details unavailable offline";
    offlineLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [offline addSubview:offlineLabel];

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeCustom];
    retry.backgroundColor = [UIColor clearColor];
    retry.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [retry setTitle:@"Retry" forState:UIControlStateNormal];
    [retry setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
    [retry addTarget:self action:@selector(retryTapped:)
    forControlEvents:UIControlEventTouchUpInside];
    [offline addSubview:retry];

    [scrollView addSubview:offline];
    self.offlineCard = offline;
    self.offlineLabel = offlineLabel;
    self.retryButton = retry;

    UIView *overview = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:overview first:YES last:YES];
    UILabel *overviewTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    overviewTitle.backgroundColor = [UIColor clearColor];
    overviewTitle.font = [MRAppearance groupTitleFont];
    overviewTitle.textColor = [MRAppearance muted];
    overviewTitle.text = @"OVERVIEW";
    [overview addSubview:overviewTitle];

    UILabel *overviewBody = [[UILabel alloc] initWithFrame:CGRectZero];
    overviewBody.backgroundColor = [UIColor clearColor];
    overviewBody.font = [MRAppearance bodyFont];
    overviewBody.textColor = [MRAppearance ink];
    overviewBody.numberOfLines = 0;
    overviewBody.lineBreakMode = NSLineBreakByWordWrapping;
    [overview addSubview:overviewBody];

    [scrollView addSubview:overview];
    self.overviewCard = overview;
    self.overviewTitleLabel = overviewTitle;
    self.overviewBodyLabel = overviewBody;

    UIView *info = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:info first:YES last:YES];
    UILabel *infoTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    infoTitle.backgroundColor = [UIColor clearColor];
    infoTitle.font = [MRAppearance groupTitleFont];
    infoTitle.textColor = [MRAppearance muted];
    infoTitle.text = @"INFO";
    [info addSubview:infoTitle];
    [scrollView addSubview:info];
    self.infoCard = info;
    self.infoTitleLabel = infoTitle;

    UIView *next = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:next first:YES last:YES];
    UILabel *nextTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    nextTitle.backgroundColor = [UIColor clearColor];
    nextTitle.font = [MRAppearance groupTitleFont];
    nextTitle.textColor = [MRAppearance muted];
    nextTitle.text = @"NEXT EPISODE";
    [next addSubview:nextTitle];

    UILabel *nextPrimary = [[UILabel alloc] initWithFrame:CGRectZero];
    nextPrimary.backgroundColor = [UIColor clearColor];
    nextPrimary.font = [MRAppearance cardTitleFont];
    nextPrimary.textColor = [MRAppearance ink];
    nextPrimary.lineBreakMode = NSLineBreakByTruncatingTail;
    [next addSubview:nextPrimary];

    UILabel *nextSecondary = [[UILabel alloc] initWithFrame:CGRectZero];
    nextSecondary.backgroundColor = [UIColor clearColor];
    nextSecondary.font = [MRAppearance smallFont];
    nextSecondary.textColor = [MRAppearance muted];
    nextSecondary.lineBreakMode = NSLineBreakByTruncatingTail;
    [next addSubview:nextSecondary];

    [scrollView addSubview:next];
    self.nextCard = next;
    self.nextTitleLabel = nextTitle;
    self.nextPrimaryLabel = nextPrimary;
    self.nextSecondaryLabel = nextSecondary;

    MRDetailRelatedView *similar = [[MRDetailRelatedView alloc] initWithFrame:CGRectZero];
    [scrollView addSubview:similar];
    self.similarView = similar;

    MRDetailRelatedView *recommended = [[MRDetailRelatedView alloc] initWithFrame:CGRectZero];
    [scrollView addSubview:recommended];
    self.recommendedView = recommended;

    UIView *footer = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:footer first:YES last:YES];
    UIImageView *badge =
        [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SimklBadge.png"]];
    badge.backgroundColor = [UIColor clearColor];
    badge.contentMode = UIViewContentModeScaleAspectFit;
    [footer addSubview:badge];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    footerLabel.backgroundColor = [UIColor clearColor];
    footerLabel.font = [MRAppearance smallFont];
    footerLabel.textColor = [MRAppearance muted];
    footerLabel.text = @"Movie, TV and anime data from Simkl";
    footerLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [footer addSubview:footerLabel];

    UIButton *footerLink = [UIButton buttonWithType:UIButtonTypeCustom];
    footerLink.backgroundColor = [UIColor clearColor];
    footerLink.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    footerLink.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [footerLink setTitle:@"simkl.com" forState:UIControlStateNormal];
    [footerLink setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
    [footerLink addTarget:self
                   action:@selector(openSimklSite:)
         forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:footerLink];

    [scrollView addSubview:footer];
    self.footerCard = footer;
    self.footerBadge = badge;
    self.footerLabel = footerLabel;
    self.footerLink = footerLink;
}

- (void)buildActionsCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    [MRAppearance styleCardView:card first:YES last:YES];
    [self.scrollView addSubview:card];
    self.actionsCard = card;

    UIButton *primary = [UIButton buttonWithType:UIButtonTypeCustom];
    [primary setBackgroundImage:[MRAppearance actionButtonImage]
                       forState:UIControlStateNormal];
    [primary setBackgroundImage:[MRAppearance actionButtonImage]
                       forState:UIControlStateHighlighted];
    primary.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [primary setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                        forState:UIControlStateNormal];
    primary.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [primary addTarget:self
                action:@selector(primaryActionTapped:)
      forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:primary];
    self.primaryButton = primary;

    __weak MRDetailViewController *weakSelf = self;

    MRDetailActionRowView *rateRow =
        [[MRDetailActionRowView alloc] initWithFrame:CGRectZero];
    [rateRow configureWithTitle:@"Rate" value:nil destructive:NO];
    [rateRow addTarget:self
                action:@selector(rateRowTapped:)
      forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:rateRow];
    self.rateRow = rateRow;

    MRStarRatingView *stars =
        [[MRStarRatingView alloc] initWithFrame:CGRectZero];
    stars.hidden = YES;
    stars.ratingHandler = ^(NSInteger rating) {
        [weakSelf setRating:rating];
    };
    [card addSubview:stars];
    self.ratingView = stars;

    UIButton *removeRating = [UIButton buttonWithType:UIButtonTypeCustom];
    removeRating.backgroundColor = [UIColor clearColor];
    removeRating.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    removeRating.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    [removeRating setTitle:@"Remove rating" forState:UIControlStateNormal];
    [removeRating setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
    [removeRating setTitleColor:[MRAppearance muted]
                       forState:UIControlStateDisabled];
    [removeRating addTarget:self
                     action:@selector(removeRatingTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    removeRating.hidden = YES;
    [card addSubview:removeRating];
    self.removeRatingButton = removeRating;

    MRDetailActionRowView *statusRow =
        [[MRDetailActionRowView alloc] initWithFrame:CGRectZero];
    [statusRow configureWithTitle:@"Change Status" value:nil destructive:NO];
    [statusRow addTarget:self
                  action:@selector(changeStatusTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:statusRow];
    self.statusRow = statusRow;

    MRDetailActionRowView *removeRow =
        [[MRDetailActionRowView alloc] initWithFrame:CGRectZero];
    [removeRow configureWithTitle:@"Remove from Library" value:nil destructive:YES];
    removeRow.showsChevron = NO;
    [removeRow addTarget:self
                  action:@selector(removeTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:removeRow];
    self.removeRow = removeRow;
}

- (void)buildBanner {
    MRBannerView *banner = [[MRBannerView alloc] initWithFrame:CGRectZero];
    __weak MRDetailViewController *weakSelf = self;
    banner.retryHandler = ^{
        [weakSelf flushOutbox];
    };
    [self.view addSubview:banner];
    self.bannerView = banner;
}

#pragma mark - Content

- (void)updateContent {
    MRMediaItem *item = self.item;
    if (item == nil) {
        return;
    }

    self.title = item.title.length > 0 ? item.title : @"Details";
    [self.heroView configureWithItem:item imageCache:self.imageCache];

    self.overviewBodyLabel.text = item.overview != nil ? item.overview : @"";
    [self rebuildInfoRows];

    BOOL hasNext = [self hasNextEpisodeInfo];
    if (hasNext) {
        if (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) {
            NSMutableString *primary =
                [NSMutableString stringWithFormat:@"S%ldE%ld",
                 (long)item.nextEpisodeSeason, (long)item.nextEpisodeNumber];
            if (item.nextEpisodeTitle.length > 0) {
                [primary appendFormat:@" · %@", item.nextEpisodeTitle];
            }
            self.nextPrimaryLabel.text = primary;
            self.nextSecondaryLabel.text =
                item.nextEpisodeDate != nil ? [self dateText:item.nextEpisodeDate] : @"";
        } else {
            self.nextPrimaryLabel.text = item.nextToWatch;
            self.nextSecondaryLabel.text = @"";
        }
    }

    __weak MRDetailViewController *weakSelf = self;
    void (^relatedTap)(MRMediaItem *) = ^(MRMediaItem *related) {
        [weakSelf openRelatedItem:related];
    };

    if (self.similarItems.count > 0) {
        [self.similarView configureWithTitle:@"More Like This"
                                      items:self.similarItems
                                 imageCache:self.imageCache
                                 tapHandler:relatedTap];
    }
    if (self.recommendedItems.count > 0) {
        [self.recommendedView configureWithTitle:@"Viewers Also Watched"
                                           items:self.recommendedItems
                                      imageCache:self.imageCache
                                      tapHandler:relatedTap];
    }

    [self updateActionsCard];
    [self.view setNeedsLayout];
}

- (void)updateActionsCard {
    BOOL available = self.actions != nil && self.item != nil;
    self.actionsCard.hidden = !available;
    if (!available) {
        return;
    }

    MRMediaItem *item = self.item;
    BOOL tracked = item.watchStatus != MRWatchStatusNone;

    MRDetailPrimaryAction action = [MRDetailActions primaryActionForItem:item];
    [self.primaryButton setTitle:[MRDetailActions titleForPrimaryAction:action
                                                                  item:item]
                        forState:UIControlStateNormal];

    NSString *ratingValue = item.userRating > 0
        ? [NSString stringWithFormat:@"★ %ld", (long)item.userRating]
        : @"Not rated";
    [self.rateRow configureWithTitle:@"Rate" value:ratingValue destructive:NO];

    self.ratingView.rating = item.userRating;
    self.removeRatingButton.enabled = item.userRating > 0;

    [self.statusRow configureWithTitle:@"Change Status"
                                 value:tracked ? MRWatchStatusDisplayName(item.watchStatus)
                                               : nil
                           destructive:NO];
    self.statusRow.hidden = !tracked;
    self.removeRow.hidden = !tracked;

    self.ratingView.hidden = !self.ratingExpanded;
    self.removeRatingButton.hidden = !self.ratingExpanded;
}

- (void)rebuildInfoRows {
    for (UIView *row in self.infoRows) {
        [row removeFromSuperview];
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *pair in [self infoPairs]) {
        MRDetailInfoRowView *row = [[MRDetailInfoRowView alloc] initWithFrame:CGRectZero];
        [row configureName:[pair objectForKey:@"name"] value:[pair objectForKey:@"value"]];
        [self.infoCard addSubview:row];
        [rows addObject:row];
    }
    self.infoRows = rows;
}

- (NSArray *)infoPairs {
    MRMediaItem *item = self.item;
    NSMutableArray *pairs = [NSMutableArray array];

    if (item.network.length > 0) {
        [pairs addObject:@{ @"name": @"Network", @"value": item.network }];
    }
    if (item.country.length > 0) {
        [pairs addObject:@{ @"name": @"Country", @"value": item.country }];
    }
    if (item.releaseDate.length > 0) {
        NSString *name = item.type == MRMediaTypeMovie ? @"Released" : @"First aired";
        [pairs addObject:@{ @"name": name,
                            @"value": MRDetailShortDate(item.releaseDate) }];
    }
    if (item.airStatus.length > 0) {
        [pairs addObject:@{ @"name": @"Status",
                            @"value": MRDetailCapitalized(item.airStatus) }];
    }
    NSString *episodes = MRDetailEpisodesText(item);
    if (episodes != nil && item.type != MRMediaTypeMovie) {
        [pairs addObject:@{ @"name": @"Episodes", @"value": episodes }];
    }
    if (item.runtime > 0) {
        [pairs addObject:@{ @"name": @"Runtime",
                            @"value": [NSString stringWithFormat:@"%ld min", (long)item.runtime] }];
    }

    NSString *simkl = MRDetailRating(item.ratings, @"simkl");
    if (simkl != nil) {
        [pairs addObject:@{ @"name": @"Simkl rating", @"value": simkl }];
    }
    NSString *imdb = MRDetailRating(item.ratings, @"imdb");
    if (imdb != nil) {
        [pairs addObject:@{ @"name": @"IMDb rating", @"value": imdb }];
    }
    NSString *mal = MRDetailRating(item.ratings, @"mal");
    if (mal != nil) {
        [pairs addObject:@{ @"name": @"MAL rating", @"value": mal }];
    }

    return pairs;
}

- (BOOL)hasNextEpisodeInfo {
    if (self.item.type == MRMediaTypeMovie) {
        return NO;
    }
    if (self.item.nextEpisodeSeason > 0 && self.item.nextEpisodeNumber > 0) {
        return YES;
    }
    return self.item.nextToWatch.length > 0;
}

- (NSString *)dateText:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    return [formatter stringFromDate:date];
}

#pragma mark - Fetch

- (void)fetchDetail {
    [self.detailTask cancel];
    self.detailTask = nil;

    if (self.item == nil) {
        return;
    }
    if (self.item.simklID <= 0 || self.apiClient == nil) {
        self.offlineVisible = YES;
        [self updateContent];
        return;
    }

    self.retryButton.enabled = NO;
    __weak MRDetailViewController *weakSelf = self;
    self.detailTask =
        [self.apiClient fetchDetailForType:self.item.type
                                  simklID:self.item.simklID
                                completion:^(NSDictionary *json, NSError *error) {
        MRDetailViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.detailTask = nil;
        strongSelf.retryButton.enabled = YES;

        if (error != nil) {
            if ([MRError kindForError:error] == MRErrorKindCancelled) {
                return;
            }
            strongSelf.offlineVisible = YES;
            [strongSelf updateContent];
            return;
        }
        if (![json isKindOfClass:[NSDictionary class]] || json.count == 0) {
            strongSelf.offlineVisible = YES;
            [strongSelf updateContent];
            return;
        }

        strongSelf.detailDictionary = json;
        strongSelf.item = [strongSelf.item itemByMergingDetailDictionary:json];
        strongSelf.similarItems =
            [MRMediaItem itemsWithRelatedDictionaries:[json objectForKey:@"similar"]];
        strongSelf.recommendedItems =
            [MRMediaItem itemsWithRelatedDictionaries:
                [json objectForKey:@"users_recommendations"]];
        strongSelf.offlineVisible = NO;
        [strongSelf updateContent];
    }];
}

- (void)retryTapped:(UIButton *)sender {
    [self fetchDetail];
}

#pragma mark - Actions

- (void)primaryActionTapped:(UIButton *)sender {
    if (self.actions == nil) {
        return;
    }

    MRDetailPrimaryAction action = [MRDetailActions primaryActionForItem:self.item];
    if (action == MRDetailPrimaryActionChangeStatus) {
        [self showStatusSheet];
        return;
    }

    NSError *error = nil;
    MROutboxEntry *entry =
        [self.actions performPrimaryActionForItem:self.item error:&error];
    [self handleEnqueuedEntry:entry error:error];
}

- (void)rateRowTapped:(id)sender {
    self.ratingExpanded = !self.ratingExpanded;
    [self updateActionsCard];
    [self.view setNeedsLayout];
}

- (void)setRating:(NSInteger)rating {
    if (rating == self.item.userRating) {
        return;
    }
    NSError *error = nil;
    MROutboxEntry *entry = [self.actions setRating:rating
                                           forItem:self.item
                                             error:&error];
    [self handleEnqueuedEntry:entry error:error];
}

- (void)removeRatingTapped:(id)sender {
    NSError *error = nil;
    MROutboxEntry *entry = [self.actions clearRatingForItem:self.item error:&error];
    [self handleEnqueuedEntry:entry error:error];
}

- (void)changeStatusTapped:(id)sender {
    [self showStatusSheet];
}

- (void)removeTapped:(id)sender {
    [self showRemoveSheet];
}

- (void)showStatusSheet {
    if (self.actions == nil || self.item == nil) {
        return;
    }

    NSArray *statuses = [MRDetailActions validStatusesForType:self.item.type];
    self.statusChoices = statuses;

    UIActionSheet *sheet =
        [[UIActionSheet alloc] initWithTitle:@"Change Status"
                                   delegate:self
                          cancelButtonTitle:nil
                     destructiveButtonTitle:nil
                          otherButtonTitles:nil];
    for (NSNumber *number in statuses) {
        MRWatchStatus status = (MRWatchStatus)[number integerValue];
        NSString *title = MRWatchStatusDisplayName(status);
        if (status == self.item.watchStatus) {
            title = [@"✓ " stringByAppendingString:title];
        }
        [sheet addButtonWithTitle:title];
    }
    [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = sheet.numberOfButtons - 1;
    sheet.tag = MRDetailSheetChangeStatus;
    [self presentActionSheet:sheet];
}

- (void)showRemoveSheet {
    if (self.actions == nil || self.item == nil) {
        return;
    }

    NSString *title = [NSString stringWithFormat:@"Remove \"%@\" from your library?",
                       self.item.title.length > 0 ? self.item.title : @"this title"];
    UIActionSheet *sheet =
        [[UIActionSheet alloc] initWithTitle:title
                                   delegate:self
                          cancelButtonTitle:@"Cancel"
                     destructiveButtonTitle:@"Remove from Library"
                          otherButtonTitles:nil];
    sheet.tag = MRDetailSheetRemove;
    [self presentActionSheet:sheet];
}

- (void)presentActionSheet:(UIActionSheet *)sheet {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        CGRect anchor = [self.primaryButton convertRect:self.primaryButton.bounds
                                                 toView:self.view];
        [sheet showFromRect:anchor inView:self.view animated:YES];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == MRDetailSheetChangeStatus) {
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)self.statusChoices.count) {
            return;
        }
        MRWatchStatus status = (MRWatchStatus)
            [[self.statusChoices objectAtIndex:(NSUInteger)buttonIndex] integerValue];
        if (status == self.item.watchStatus) {
            return;
        }
        NSError *error = nil;
        MROutboxEntry *entry = [self.actions setWatchStatus:status
                                                    forItem:self.item
                                                      error:&error];
        [self handleEnqueuedEntry:entry error:error];
        return;
    }

    if (actionSheet.tag == MRDetailSheetRemove &&
        buttonIndex == actionSheet.destructiveButtonIndex) {
        NSError *error = nil;
        MROutboxEntry *entry = [self.actions removeFromLibraryForItem:self.item
                                                                error:&error];
        [self handleEnqueuedEntry:entry error:error];
    }
}

- (void)handleEnqueuedEntry:(MROutboxEntry *)entry error:(NSError *)error {
    if (entry == nil) {
        if (error != nil) {
            [self showAlertWithTitle:@"Couldn't Save"
                             message:error.localizedDescription];
        }
        return;
    }

    [self applyEntryToLocalItem:entry];
    if (entry.kind == MROutboxEntryKindRemove) {
        self.removeEntryID = entry.entryID;
    }
    [self updateContent];
    [self.view setNeedsLayout];
    [MRToastView showMessage:@"Saved" inView:self.view];
    [self flushOutbox];
}

- (void)applyEntryToLocalItem:(MROutboxEntry *)entry {
    switch (entry.kind) {
        case MROutboxEntryKindStatus:
        case MROutboxEntryKindHistoryWhole:
            if (entry.status != MRWatchStatusNone) {
                self.item.watchStatus = entry.status;
            }
            break;
        case MROutboxEntryKindHistoryEpisode:
            // The next-episode marker comes from sync; leave it until the
            // response or the next refresh resolves it.
            break;
        case MROutboxEntryKindRating:
            self.item.userRating = entry.rating;
            break;
        case MROutboxEntryKindRatingRemove:
            self.item.userRating = 0;
            break;
        case MROutboxEntryKindRemove:
            // Removal is confirmed by the server before the local item drops.
            break;
        default:
            break;
    }
}

- (void)flushOutbox {
    if (self.actions == nil) {
        return;
    }
    if (self.flushing) {
        self.flushAgain = YES;
        return;
    }

    self.flushing = YES;
    [self.bannerView showMessage:@"Syncing changes…"
                           style:MRBannerStylePending
                      retryTitle:nil];

    __weak MRDetailViewController *weakSelf = self;
    [self.actions flushWithCompletion:^(MRWriteResult *result) {
        MRDetailViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.flushing = NO;
        if (strongSelf.flushAgain) {
            strongSelf.flushAgain = NO;
            [strongSelf flushOutbox];
            return;
        }
        [strongSelf handleWriteResult:result];
    }];
}

- (void)handleWriteResult:(MRWriteResult *)result {
    if (result == nil) {
        return;
    }

    BOOL removeSucceeded = NO;
    BOOL removeFailed = NO;
    if (self.removeEntryID.length > 0) {
        for (MROutboxEntry *entry in result.succeededEntries) {
            if ([entry.entryID isEqualToString:self.removeEntryID]) {
                removeSucceeded = YES;
                break;
            }
        }
        for (MROutboxEntry *entry in result.permanentlyFailedEntries) {
            if ([entry.entryID isEqualToString:self.removeEntryID]) {
                removeFailed = YES;
                break;
            }
        }
    }

    if (removeSucceeded) {
        self.removeEntryID = nil;
        MRMediaItem *remaining = [self.libraryStore itemForType:self.item.type
                                                        simklID:self.item.simklID];
        if (remaining == nil && self.navigationController != nil) {
            [self.bannerView hide];
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }
    }
    if (removeFailed) {
        self.removeEntryID = nil;
    }

    if (result.permanentlyFailedEntries.count > 0) {
        [self.bannerView hide];
        [self showAlertWithTitle:@"Couldn't Update"
                         message:@"Simkl couldn't save that change. Refresh the library and try again."];
        [self fetchDetail];
    } else if (result.error != nil) {
        MRErrorKind kind = [MRError kindForError:result.error];
        if (kind == MRErrorKindDailyLimit || kind == MRErrorKindAuthExpired) {
            [self.bannerView showMessage:@"Simkl needs attention. Check your connection."
                                   style:MRBannerStyleError
                              retryTitle:@"Retry"];
        } else {
            [self.bannerView showMessage:@"Will sync when online"
                                   style:MRBannerStyleWarning
                              retryTitle:@"Retry"];
        }
        return;
    } else {
        [self.bannerView hide];
    }

    for (MROutboxEntry *entry in result.succeededEntries) {
        NSNumber *resolvedNumber =
            [result.resolvedStatuses objectForKey:entry.entryID];
        if (resolvedNumber == nil) {
            continue;
        }
        MRWatchStatus resolved = (MRWatchStatus)[resolvedNumber integerValue];
        if (resolved != MRWatchStatusNone &&
            entry.status != MRWatchStatusNone &&
            resolved != entry.status) {
            [MRToastView showMessage:
                [NSString stringWithFormat:@"Simkl set this to %@",
                 MRWatchStatusDisplayName(resolved)]
                              inView:self.view];
            break;
        }
    }

    [self refreshItemFromStore];
    [self updateContent];
    [self.view setNeedsLayout];
}

- (void)refreshItemFromStore {
    if (self.libraryStore == nil || self.item == nil) {
        return;
    }
    MRMediaItem *stored =
        [self.libraryStore itemForType:self.item.type simklID:self.item.simklID];
    if (stored != nil) {
        self.item = [stored copy];
    }
}

- (void)libraryDidChange {
    if (self.item == nil || self.libraryStore == nil) {
        return;
    }
    MRMediaItem *stored =
        [self.libraryStore itemForType:self.item.type simklID:self.item.simklID];
    if (stored == nil) {
        return;
    }
    self.item = [stored copy];
    [self updateContent];
    [self.view setNeedsLayout];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)openOnSimkl {
    if (self.item.simklID <= 0) {
        return;
    }
    NSString *string = [MRURLBuilder simklWebURLForType:self.item.type
                                              simklID:self.item.simklID
                                                 slug:self.item.slug];
    NSURL *URL = [NSURL URLWithString:string];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)openSimklSite:(UIButton *)sender {
    NSURL *URL = [NSURL URLWithString:@"https://simkl.com"];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)openRelatedItem:(MRMediaItem *)related {
    if (related == nil) {
        return;
    }

    MRMediaItem *known = [self.libraryStore itemForType:related.type
                                               simklID:related.simklID];
    MRMediaItem *target = known != nil ? known : related;

    MRDetailViewController *detail =
        [[MRDetailViewController alloc] initWithItem:target
                                           apiClient:self.apiClient
                                        libraryStore:self.libraryStore
                                          imageCache:self.imageCache
                                              outbox:self.outbox
                                        writeService:self.writeService];
    if (self.navigationController != nil) {
        [self.navigationController pushViewController:detail animated:YES];
    }
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
    self.bannerView.frame = CGRectMake(0.0, 0.0, viewWidth,
                                       [MRBannerView height]);

    if (self.errorView != nil) {
        MRDeviceClass device = MRDetailDeviceClass();
        CGFloat width = CGRectGetWidth(self.view.bounds);
        CGFloat cardWidth = MIN(width - 24.0,
                                [MRLayout contentMaxWidthForDeviceClass:device]);
        self.errorView.frame = CGRectMake(floor((width - cardWidth) / 2.0),
                                          floor((CGRectGetHeight(self.view.bounds) - 160.0) / 2.0),
                                          cardWidth, 160.0);
        return;
    }

    [self layoutContentForWidth:CGRectGetWidth(self.view.bounds)];
}

- (CGFloat)actionsCardHeight {
    MRDeviceClass device = MRDetailDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat rowHeight = tablet ? 40.0 : 36.0;
    CGFloat height = 12.0 + (tablet ? 44.0 : 40.0) + 10.0;
    height += rowHeight;
    if (self.ratingExpanded) {
        height += [MRStarRatingView preferredHeight] + 28.0;
    }
    if (self.item.watchStatus != MRWatchStatusNone) {
        height += rowHeight * 2.0;
    }
    height += 8.0;
    return height;
}

- (void)layoutActionsCard {
    MRDeviceClass device = MRDetailDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat inset = tablet ? 16.0 : 12.0;
    CGFloat rowHeight = tablet ? 40.0 : 36.0;
    CGFloat width = CGRectGetWidth(self.actionsCard.bounds);
    CGFloat y = 12.0;

    self.primaryButton.frame =
        CGRectMake(inset, y, MAX(0.0, width - inset * 2.0),
                   tablet ? 44.0 : 40.0);
    y += (tablet ? 44.0 : 40.0) + 10.0;

    self.rateRow.frame = CGRectMake(0.0, y, width, rowHeight);
    y += rowHeight;

    if (self.ratingExpanded) {
        self.ratingView.frame =
            CGRectMake(inset, y, MAX(0.0, width - inset * 2.0),
                       [MRStarRatingView preferredHeight]);
        y += [MRStarRatingView preferredHeight];
        self.removeRatingButton.frame =
            CGRectMake(inset, y, MAX(0.0, width - inset * 2.0), 28.0);
        y += 28.0;
    }

    if (self.item.watchStatus != MRWatchStatusNone) {
        self.statusRow.frame = CGRectMake(0.0, y, width, rowHeight);
        y += rowHeight;
        self.removeRow.frame = CGRectMake(0.0, y, width, rowHeight);
    }
}

- (void)layoutContentForWidth:(CGFloat)width {
    if (width <= 0.0 || self.scrollView == nil) {
        return;
    }

    MRDeviceClass device = MRDetailDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat inset = tablet ? 16.0 : 12.0;
    CGFloat pad = tablet ? 16.0 : 12.0;
    CGFloat maxContent = [MRLayout contentMaxWidthForDeviceClass:device];
    CGFloat contentWidth = MIN(width, maxContent);
    CGFloat x = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);

    CGRect screen = [[UIScreen mainScreen] bounds];
    CGFloat availableHeight = MAX(CGRectGetWidth(screen), CGRectGetHeight(screen));
    CGFloat heroHeight =
        [MRLayout heroHeightForDeviceClass:device
                               orientation:[MRLayout orientationForSize:self.view.bounds.size]
                           availableHeight:availableHeight];
    self.heroView.frame = CGRectMake(0.0, 0.0, width, heroHeight);

    CGFloat y = heroHeight + MRDetailCardGap;

    BOOL showsActions = self.actionsCard != nil && !self.actionsCard.hidden;
    if (showsActions) {
        CGFloat cardHeight = [self actionsCardHeight];
        self.actionsCard.frame = CGRectMake(x, y, cardWidth, cardHeight);
        [self layoutActionsCard];
        y += cardHeight + MRDetailCardGap;
    }

    BOOL showsOffline = self.offlineVisible && self.item != nil;
    self.offlineCard.hidden = !showsOffline;
    if (showsOffline) {
        self.offlineCard.frame = CGRectMake(x, y, cardWidth, 44.0);
        self.offlineLabel.frame = CGRectMake(pad, 0.0, cardWidth - pad * 2.0 - 64.0, 44.0);
        self.retryButton.frame = CGRectMake(cardWidth - pad - 56.0, 0.0, 56.0, 44.0);
        y += 44.0 + MRDetailCardGap;
    }

    NSString *overview = self.overviewBodyLabel.text != nil ? self.overviewBodyLabel.text : @"";
    BOOL showsOverview = overview.length > 0;
    self.overviewCard.hidden = !showsOverview;
    if (showsOverview) {
        CGFloat bodyWidth = MAX(0.0, cardWidth - pad * 2.0);
        self.overviewBodyLabel.font = tablet ? [UIFont systemFontOfSize:15.0]
                                             : [MRAppearance bodyFont];
        CGSize bodySize = [overview sizeWithFont:self.overviewBodyLabel.font
                               constrainedToSize:CGSizeMake(bodyWidth, 10000.0)
                                   lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat bodyHeight = ceil(bodySize.height);
        CGFloat cardHeight = 10.0 + 16.0 + 8.0 + bodyHeight + 12.0;

        self.overviewCard.frame = CGRectMake(x, y, cardWidth, cardHeight);
        self.overviewTitleLabel.frame = CGRectMake(pad, 10.0, bodyWidth, 16.0);
        self.overviewBodyLabel.frame = CGRectMake(pad, 34.0, bodyWidth, bodyHeight);
        y += cardHeight + MRDetailCardGap;
    }

    NSUInteger infoCount = self.infoRows.count;
    BOOL showsInfo = infoCount > 0;
    self.infoCard.hidden = !showsInfo;
    if (showsInfo) {
        CGFloat rowHeight = tablet ? 32.0 : 26.0;
        CGFloat cardHeight = 10.0 + 16.0 + 8.0 + rowHeight * infoCount + 8.0;

        self.infoCard.frame = CGRectMake(x, y, cardWidth, cardHeight);
        self.infoTitleLabel.frame = CGRectMake(pad, 10.0, cardWidth - pad * 2.0, 16.0);
        CGFloat rowY = 34.0;
        for (MRDetailInfoRowView *row in self.infoRows) {
            row.frame = CGRectMake(0.0, rowY, cardWidth, rowHeight);
            rowY += rowHeight;
        }
        y += cardHeight + MRDetailCardGap;
    }

    BOOL showsNext = [self hasNextEpisodeInfo];
    self.nextCard.hidden = !showsNext;
    if (showsNext) {
        CGFloat cardHeight = tablet ? 84.0 : 76.0;
        self.nextCard.frame = CGRectMake(x, y, cardWidth, cardHeight);
        self.nextTitleLabel.frame = CGRectMake(pad, 10.0, cardWidth - pad * 2.0, 16.0);
        self.nextPrimaryLabel.frame = CGRectMake(pad, 30.0, cardWidth - pad * 2.0, 20.0);
        self.nextPrimaryLabel.font = tablet ? [UIFont boldSystemFontOfSize:16.0]
                                            : [MRAppearance cardTitleFont];
        self.nextSecondaryLabel.frame = CGRectMake(pad, 52.0, cardWidth - pad * 2.0, 16.0);
        y += cardHeight + MRDetailCardGap;
    }

    BOOL showsSimilar = self.similarItems.count > 0;
    self.similarView.hidden = !showsSimilar;
    if (showsSimilar) {
        CGFloat cardHeight = [MRDetailRelatedView heightForDeviceClass:device];
        self.similarView.frame = CGRectMake(x, y, cardWidth, cardHeight);
        y += cardHeight + MRDetailCardGap;
    }

    BOOL showsRecommended = self.recommendedItems.count > 0;
    self.recommendedView.hidden = !showsRecommended;
    if (showsRecommended) {
        CGFloat cardHeight = [MRDetailRelatedView heightForDeviceClass:device];
        self.recommendedView.frame = CGRectMake(x, y, cardWidth, cardHeight);
        y += cardHeight + MRDetailCardGap;
    }

    CGFloat footerHeight = tablet ? 60.0 : 52.0;
    self.footerCard.frame = CGRectMake(x, y, cardWidth, footerHeight);
    CGFloat badgeSide = tablet ? 26.0 : 22.0;
    CGFloat textX = pad + badgeSide + 8.0;
    self.footerBadge.frame = CGRectMake(pad, (footerHeight - badgeSide) / 2.0,
                                        badgeSide, badgeSide);
    self.footerLabel.font = tablet ? [UIFont systemFontOfSize:12.0]
                                   : [MRAppearance smallFont];
    self.footerLabel.frame = CGRectMake(textX, 10.0,
                                        MAX(0.0, cardWidth - textX - pad), 16.0);
    self.footerLink.frame = CGRectMake(textX, 27.0, 100.0, 16.0);

    CGFloat contentHeight = y + footerHeight + 16.0;
    self.scrollView.contentSize = CGSizeMake(width, contentHeight);
}

@end
