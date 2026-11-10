//
//  MRForYouViewController.m
//  Marquee
//

#import "MRForYouViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAPIClient.h"
#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRBannerView.h"
#import "MRConnectViewController.h"
#import "MRDetailViewController.h"
#import "MRError.h"
#import "MRFeedSection.h"
#import "MRGenreChoice.h"
#import "MRGenrePickerViewController.h"
#import "MRHeroView.h"
#import "MRHTTPClient.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPlaceholderView.h"
#import "MRPosterCardView.h"
#import "MRPreferencesStore.h"
#import "MRPublicFeedBuilder.h"
#import "MRQuotaTracker.h"
#import "MRRecommendationDataProviding.h"
#import "MRRecommendationEngine.h"
#import "MRRowHeaderView.h"
#import "MRSimklAuth.h"
#import "MRSyncEngine.h"
#import "MRToastView.h"
#import "MRURLBuilder.h"

static NSString *const MRForYouActionNotInterested = @"notInterested";
static NSString *const MRForYouActionWhyThis = @"whyThis";
static NSString *const MRForYouActionOpenOnSimkl = @"openOnSimkl";
static const NSInteger MRForYouActionSheetTag = 17001;

static MRDeviceClass MRForYouDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static CGFloat MRForYouAvailableHeight(void) {
    CGRect screen = [[UIScreen mainScreen] bounds];
    return MAX(CGRectGetWidth(screen), CGRectGetHeight(screen));
}

static NSString *MRForYouPreferencesSignature(MRPreferencesStore *preferences) {
    if (preferences == nil) {
        return @"";
    }

    NSMutableArray *parts = [NSMutableArray array];
    for (MRGenreChoice *choice in preferences.manualGenres) {
        [parts addObject:[NSString stringWithFormat:@"%ld:%@",
                          (long)choice.type,
                          [choice.slug lowercaseString]]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    [parts addObject:[NSString stringWithFormat:@"hidden:%lu",
                      (unsigned long)preferences.hiddenTitles.count]];
    return [parts componentsJoinedByString:@"|"];
}

static NSString *MRForYouContinueMetaText(MRMediaItem *item) {
    if (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) {
        NSString *episode = [NSString stringWithFormat:@"S%ldE%ld",
                             (long)item.nextEpisodeSeason,
                             (long)item.nextEpisodeNumber];
        if (item.nextEpisodeTitle.length > 0) {
            return [NSString stringWithFormat:@"%@ · %@", episode, item.nextEpisodeTitle];
        }
        return episode;
    }
    if (item.nextToWatch.length > 0) {
        return item.nextToWatch;
    }
    return @"Continue watching";
}

static CGFloat MRForYouContinueProgress(MRMediaItem *item) {
    if (item.totalEpisodesCount <= 0 || item.watchedEpisodesCount <= 0) {
        return 0.0;
    }
    CGFloat progress = (CGFloat)item.watchedEpisodesCount /
                       (CGFloat)item.totalEpisodesCount;
    if (progress < 0.0) {
        return 0.0;
    }
    if (progress > 1.0) {
        return 1.0;
    }
    return progress;
}

#pragma mark - Skeleton

@interface MRForYouSkeletonView : UIView
@property (nonatomic, strong) UIView *heroBlock;
@property (nonatomic, strong) NSMutableArray *headerBlocks;
@property (nonatomic, strong) NSMutableArray *cardBlocks;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation MRForYouSkeletonView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [MRAppearance groupBackground];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        _heroBlock = [self blockView];
        [self addSubview:_heroBlock];

        _headerBlocks = [NSMutableArray array];
        _cardBlocks = [NSMutableArray array];
        MRDeviceClass device = MRForYouDeviceClass();
        CGFloat cardWidth = [MRLayout posterCardWidthForDeviceClass:device];
        CGFloat imageHeight = [MRLayout posterCardImageHeightForDeviceClass:device];
        for (NSInteger row = 0; row < 2; row++) {
            UIView *header = [self blockView];
            header.frame = CGRectMake(12.0, 0.0, 140.0, 11.0);
            [_headerBlocks addObject:header];
            [self addSubview:header];

            for (NSInteger column = 0; column < 3; column++) {
                UIView *card = [self blockView];
                card.frame = CGRectMake(0.0, 0.0, cardWidth, imageHeight);
                [_cardBlocks addObject:card];
                [self addSubview:card];
            }
        }

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [_spinner startAnimating];
        [self addSubview:_spinner];
    }
    return self;
}

- (UIView *)blockView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [MRAppearance placeholder];
    view.layer.cornerRadius = 5.0;
    return view;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat heroInset = [MRLayout heroSideInsetForDeviceClass:device];
    CGFloat rowInset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat cardWidth = [MRLayout posterCardWidthForDeviceClass:device];
    CGFloat cardGap = [MRLayout posterCardGapForDeviceClass:device];
    CGFloat imageHeight = [MRLayout posterCardImageHeightForDeviceClass:device];
    CGFloat heroHeight =
        [MRLayout heroHeightForDeviceClass:device
                               orientation:[MRLayout orientationForSize:self.bounds.size]
                           availableHeight:MRForYouAvailableHeight()];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat contentX = (width - contentWidth) / 2.0;

    self.heroBlock.frame = CGRectMake(contentX + heroInset, heroInset,
                                      MAX(0.0, contentWidth - heroInset * 2.0),
                                      heroHeight);

    CGFloat y = heroInset + heroHeight + 18.0;
    NSUInteger cardIndex = 0;
    for (NSUInteger row = 0; row < self.headerBlocks.count; row++) {
        UIView *header = [self.headerBlocks objectAtIndex:row];
        header.frame = CGRectMake(contentX + rowInset, y, 140.0, 11.0);
        y += 11.0 + 12.0;

        for (NSInteger column = 0; column < 3; column++) {
            UIView *card = [self.cardBlocks objectAtIndex:cardIndex];
            card.frame = CGRectMake(contentX + rowInset +
                                    (CGFloat)column * (cardWidth + cardGap),
                                    y,
                                    cardWidth,
                                    imageHeight);
            cardIndex += 1;
        }
        y += imageHeight + 18.0;
    }

    self.spinner.center = CGPointMake(width / 2.0, CGRectGetMidY(self.bounds));
}

@end

#pragma mark - Cells

@interface MRForYouHeroCell : UITableViewCell
@property (nonatomic, strong) MRHeroView *heroView;
- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               buttonTitle:(NSString *)buttonTitle
                   handler:(void (^)(void))handler;
@end

@implementation MRForYouHeroCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _heroView = [[MRHeroView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_heroView];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               buttonTitle:(NSString *)buttonTitle
                   handler:(void (^)(void))handler {
    self.heroView.actionHandler = handler;
    [self.heroView configureWithTitle:title
                             subtitle:subtitle
                          buttonTitle:buttonTitle];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat inset = [MRLayout heroSideInsetForDeviceClass:device];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat x = (width - contentWidth) / 2.0 + inset;
    self.heroView.frame = CGRectMake(x,
                                     inset,
                                     MAX(0.0, contentWidth - inset * 2.0),
                                     MAX(0.0, CGRectGetHeight(self.contentView.bounds) -
                                              inset * 2.0));
}

@end

@interface MRForYouRowCell : UITableViewCell
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *cards;
- (void)configureWithImageCache:(MRImageCache *)imageCache
                          items:(NSArray *)items
                         source:(MRFeedSource)source
                     tapHandler:(void (^)(MRMediaItem *item))tapHandler
                longPressHandler:(void (^)(MRMediaItem *item, UIView *sourceView))longPressHandler;
- (void)cancelLoading;
@end

@implementation MRForYouRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.alwaysBounceHorizontal = YES;
        [self.contentView addSubview:_scrollView];

        _cards = [NSMutableArray array];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.contentView.bounds;
}

- (void)configureWithImageCache:(MRImageCache *)imageCache
                          items:(NSArray *)items
                         source:(MRFeedSource)source
                     tapHandler:(void (^)(MRMediaItem *item))tapHandler
                longPressHandler:(void (^)(MRMediaItem *item, UIView *sourceView))longPressHandler {
    [self cancelLoading];
    for (MRPosterCardView *card in self.cards) {
        [card removeFromSuperview];
    }
    [self.cards removeAllObjects];

    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat rowInset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat cardWidth = [MRLayout posterCardWidthForDeviceClass:device];
    CGFloat cardGap = [MRLayout posterCardGapForDeviceClass:device];
    CGFloat rowHeight = [MRLayout posterRowHeightForDeviceClass:device];

    CGFloat x = rowInset;
    for (MRMediaItem *item in items) {
        MRPosterCardView *card =
            [[MRPosterCardView alloc] initWithImageCache:imageCache];
        card.frame = CGRectMake(x, 0.0, cardWidth, rowHeight);
        card.tapHandler = tapHandler;
        __weak MRPosterCardView *weakCard = card;
        card.longPressHandler = longPressHandler != nil
            ? ^(MRMediaItem *pressed) { longPressHandler(pressed, weakCard); }
            : nil;
        [card setItem:item];
        if (source == MRFeedSourceContinueWatching) {
            [card setMetaText:MRForYouContinueMetaText(item)];
            [card setProgress:MRForYouContinueProgress(item)];
        }
        [self.scrollView addSubview:card];
        [self.cards addObject:card];
        x += cardWidth + cardGap;
    }

    CGFloat contentWidth = x - cardGap + rowInset;
    if (contentWidth < CGRectGetWidth(self.contentView.bounds)) {
        contentWidth = CGRectGetWidth(self.contentView.bounds);
    }
    self.scrollView.contentSize = CGSizeMake(contentWidth, rowHeight);
    self.scrollView.contentOffset = CGPointZero;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.scrollView.contentOffset = CGPointZero;
}

- (void)cancelLoading {
    for (MRPosterCardView *card in self.cards) {
        [card cancelLoading];
    }
}

- (void)dealloc {
    [self cancelLoading];
}

@end

@interface MRForYouEmptyCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, copy) void (^searchTapHandler)(void);
- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                 tapHandler:(void (^)(void))tapHandler;
@end

@implementation MRForYouEmptyCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _card = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_card first:YES last:YES];
        [self.contentView addSubview:_card];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance cardTitleFont];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_card addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [MRAppearance smallFont];
        _subtitleLabel.textColor = [MRAppearance muted];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_card addSubview:_subtitleLabel];

        _searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_searchButton setBackgroundImage:[MRAppearance actionButtonImage]
                                 forState:UIControlStateNormal];
        [_searchButton setBackgroundImage:[MRAppearance actionButtonImage]
                                 forState:UIControlStateHighlighted];
        _searchButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [_searchButton setTitleColor:[UIColor whiteColor]
                            forState:UIControlStateNormal];
        [_searchButton setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                                  forState:UIControlStateNormal];
        _searchButton.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        [_searchButton setTitle:@"Search" forState:UIControlStateNormal];
        [_searchButton addTarget:self
                          action:@selector(searchTapped:)
                forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_searchButton];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                 tapHandler:(void (^)(void))tapHandler {
    self.titleLabel.text = title != nil ? title : @"";
    self.subtitleLabel.text = subtitle != nil ? subtitle : @"";
    self.searchTapHandler = tapHandler;
}

- (void)searchTapped:(UIButton *)sender {
    if (self.searchTapHandler != nil) {
        self.searchTapHandler();
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    CGFloat cardHeight = 144.0;
    self.card.frame = CGRectMake((width - contentWidth) / 2.0 + inset,
                                 8.0,
                                 cardWidth,
                                 cardHeight);

    CGFloat buttonWidth = 140.0;
    CGFloat buttonHeight = 34.0;
    self.titleLabel.frame = CGRectMake(16.0, 18.0, cardWidth - 32.0, 20.0);
    self.subtitleLabel.frame = CGRectMake(16.0, 42.0, cardWidth - 32.0, 32.0);
    self.searchButton.frame = CGRectMake((cardWidth - buttonWidth) / 2.0,
                                         cardHeight - 16.0 - buttonHeight,
                                         buttonWidth,
                                         buttonHeight);
}

@end

#pragma mark - Controller

@interface MRForYouViewController () <UITableViewDataSource, UITableViewDelegate,
                                      UIActionSheetDelegate>

@property (nonatomic, strong) MRAppEnvironment *environment;
@property (nonatomic, strong) MRRecommendationEngine *explicitRecommendationEngine;
@property (nonatomic, strong) MRPreferencesStore *explicitPreferences;
@property (nonatomic, strong) MRLibraryStore *explicitLibraryStore;
@property (nonatomic, strong) MRImageCache *explicitImageCache;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, assign, getter=isLoadingFeed) BOOL loadingFeed;
@property (nonatomic, assign, getter=isLoadingPublicFeed) BOOL loadingPublicFeed;
@property (nonatomic, assign) BOOL pendingForceRefresh;
@property (nonatomic, strong) id<MRHTTPTask> publicTask;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) MRForYouSkeletonView *skeletonView;
@property (nonatomic, strong) MRPlaceholderView *retryView;
@property (nonatomic, strong) MRBannerView *bannerView;
@property (nonatomic, copy) NSString *refreshBannerMessage;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@property (nonatomic, assign) BOOL observedWasSyncing;
@property (nonatomic, copy) NSString *preferencesSignature;
@property (nonatomic, assign) BOOL suppressPreferencesRefresh;

@property (nonatomic, strong) MRMediaItem *actionItem;
@property (nonatomic, strong) MRFeedSection *actionSection;
@property (nonatomic, strong) UIView *actionSourceView;
@property (nonatomic, copy) NSArray *actionIdentifiers;

@end

@implementation MRForYouViewController

- (instancetype)initWithRecommendationEngine:(MRRecommendationEngine *)engine
                                 preferences:(MRPreferencesStore *)preferences
                                libraryStore:(MRLibraryStore *)libraryStore
                                  imageCache:(MRImageCache *)imageCache {
    self = [super init];
    if (self) {
        _explicitRecommendationEngine = engine;
        _explicitPreferences = preferences;
        _explicitLibraryStore = libraryStore;
        _explicitImageCache = imageCache;
        _sections = @[];
        _preferencesSignature = MRForYouPreferencesSignature(preferences);
    }
    return self;
}

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment {
    self = [super init];
    if (self) {
        _environment = environment;
        _sections = @[];
    }
    return self;
}

- (id)init {
    return [self initWithEnvironment:nil];
}

#pragma mark - Resolved dependencies

- (MRRecommendationEngine *)recommendationEngine {
    if (self.environment.recommendationEngine != nil) {
        return self.environment.recommendationEngine;
    }
    return self.explicitRecommendationEngine;
}

- (MRPreferencesStore *)preferences {
    if (self.environment.preferences != nil) {
        return self.environment.preferences;
    }
    return self.explicitPreferences;
}

- (MRLibraryStore *)libraryStore {
    if (self.environment.libraryStore != nil) {
        return self.environment.libraryStore;
    }
    return self.explicitLibraryStore;
}

- (MRImageCache *)imageCache {
    if (self.environment.imageCache != nil) {
        return self.environment.imageCache;
    }
    return self.explicitImageCache;
}

- (MRAPIClient *)apiClient {
    return self.environment.apiClient;
}

- (MRSimklAuth *)auth {
    return self.environment.auth;
}

- (BOOL)isSignedIn {
    if (self.environment.auth != nil) {
        return self.environment.auth.isSignedIn;
    }
    return self.explicitRecommendationEngine != nil && self.explicitPreferences != nil;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"For You";
    self.view.backgroundColor = [MRAppearance groupBackground];

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                          style:UITableViewStylePlain];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    tableView.backgroundColor = [MRAppearance groupBackground];
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:tableView];
    self.tableView = tableView;

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self
                action:@selector(refreshPulled:)
      forControlEvents:UIControlEventValueChanged];
    [tableView addSubview:refresh];
    self.refreshControl = refresh;

    self.skeletonView = [[MRForYouSkeletonView alloc] initWithFrame:self.view.bounds];
    self.skeletonView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.skeletonView.hidden = YES;
    [self.view addSubview:self.skeletonView];

    MRPlaceholderView *retry =
        [[MRPlaceholderView alloc] initWithMessage:@"Couldn't load For You."
                                       actionTitle:@"Retry"];
    __weak MRForYouViewController *weakSelf = self;
    retry.actionHandler = ^{
        [weakSelf refreshFeedForce:YES];
    };
    retry.hidden = YES;
    [self.view addSubview:retry];
    self.retryView = retry;

    MRBannerView *banner = [[MRBannerView alloc] initWithFrame:CGRectZero];
    banner.retryHandler = ^{
        [weakSelf refreshFeedForce:YES];
    };
    self.bannerView = banner;

    [self registerObservers];
    [self updatePreferencesSignature];

    NSArray *cached = [self.recommendationEngine cachedSections];
    if (self.isSignedIn && cached.count > 0) {
        [self applySections:cached allowShortRows:NO];
    }

    [self refreshFeedForce:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.sections.count == 0 &&
        !self.isLoadingFeed && !self.isLoadingPublicFeed) {
        [self refreshFeedForce:NO];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) {
        return;
    }

    [self layoutRetryView];
    self.skeletonView.frame = self.view.bounds;

    if (self.bannerView != nil && !self.bannerView.hidden) {
        CGRect frame = self.bannerView.frame;
        frame.size.width = width;
        self.bannerView.frame = frame;
        if (self.tableView.tableHeaderView == self.bannerView) {
            self.tableView.tableHeaderView = self.bannerView;
        }
    }

    if (width != self.lastLayoutWidth) {
        self.lastLayoutWidth = width;
        [self.tableView reloadData];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    id<MRHTTPTask> task = self.publicTask;
    self.publicTask = nil;
    [task cancel];
}

- (void)layoutRetryView {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGFloat contentWidth = MIN(width,
        [MRLayout contentMaxWidthForDeviceClass:MRForYouDeviceClass()]);
    self.retryView.frame = CGRectMake(floor((width - contentWidth) / 2.0),
                                      floor((height - 160.0) / 2.0),
                                      contentWidth,
                                      160.0);
}

#pragma mark - Notifications

- (void)registerObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(authDidChange:)
                   name:MRAuthDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(libraryDidChange:)
                   name:MRLibraryDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(syncStatusDidChange:)
                   name:MRSyncStatusDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(preferencesDidChange:)
                   name:MRPreferencesDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(recommendationsDidReset:)
                   name:MRRecommendationsDidResetNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(applicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(quotaDidChange:)
                   name:MRQuotaDidChangeNotification
                 object:nil];

    MRSyncEngine *engine = self.environment.syncEngine;
    self.observedWasSyncing = engine.isSyncing;
}

- (void)authDidChange:(NSNotification *)notification {
    [self hideRefreshBanner];
    self.sections = @[];
    [self.tableView reloadData];
    [self updatePreferencesSignature];
    [self refreshFeedForce:YES];
}

- (void)libraryDidChange:(NSNotification *)notification {
    if (!self.isSignedIn || self.recommendationEngine == nil) {
        return;
    }
    [self updatePreferencesSignature];
    [self refreshFeedForce:NO];
}

- (void)syncStatusDidChange:(NSNotification *)notification {
    MRSyncEngine *engine = self.environment.syncEngine;
    BOOL syncing = engine.isSyncing;
    if (self.observedWasSyncing && !syncing && engine.lastSyncError == nil) {
        [self refreshFeedForce:NO];
    }
    self.observedWasSyncing = syncing;
}

- (void)preferencesDidChange:(NSNotification *)notification {
    if (self.suppressPreferencesRefresh) {
        self.suppressPreferencesRefresh = NO;
        return;
    }

    NSString *signature = MRForYouPreferencesSignature(self.preferences);
    if ([signature isEqualToString:self.preferencesSignature]) {
        return;
    }
    self.preferencesSignature = signature;

    if (self.isSignedIn) {
        [self refreshFeedForce:YES];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self refreshFeedForce:NO];
}

- (void)recommendationsDidReset:(NSNotification *)notification {
    if (self.isSignedIn) {
        [self refreshFeedForce:YES];
    }
}

- (void)quotaDidChange:(NSNotification *)notification {
    [self updateBannerDisplay];
}

- (void)updatePreferencesSignature {
    self.preferencesSignature = MRForYouPreferencesSignature(self.preferences);
}

#pragma mark - Feed loading

- (void)refreshFeedForce:(BOOL)force {
    if (self.isLoadingFeed || self.isLoadingPublicFeed) {
        self.pendingForceRefresh = self.pendingForceRefresh || force;
        return;
    }
    if (!self.isSignedIn) {
        [self loadPublicFeed];
        return;
    }
    if (self.recommendationEngine == nil) {
        // The account bootstrap creates the engine after auth restores. Keep
        // the loading state instead of showing a false public fallback.
        if (self.sections.count == 0) {
            [self showSkeleton];
        }
        return;
    }

    self.loadingFeed = YES;
    self.pendingForceRefresh = NO;
    if (self.sections.count == 0) {
        [self showSkeleton];
    }

    __weak MRForYouViewController *weakSelf = self;
    [self.recommendationEngine refreshWithForce:force completion:
     ^(NSArray *sections, NSError *error) {
        MRForYouViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.loadingFeed = NO;
        [strongSelf.refreshControl endRefreshing];

        if (sections.count > 0) {
            [strongSelf applySections:sections allowShortRows:NO];
            if (error != nil) {
                [strongSelf showRefreshBannerWithMessage:@"Couldn't refresh recommendations"];
            } else {
                [strongSelf hideRefreshBanner];
            }
        } else if (strongSelf.sections.count > 0) {
            [strongSelf hideSkeleton];
            [strongSelf showRefreshBannerWithMessage:@"Couldn't refresh recommendations"];
            [strongSelf.tableView reloadData];
        } else {
            [strongSelf hideSkeleton];
            [strongSelf loadPublicFallback];
        }

        if (strongSelf.pendingForceRefresh) {
            strongSelf.pendingForceRefresh = NO;
            [strongSelf refreshFeedForce:YES];
        }
    }];
}

- (void)loadPublicFeed {
    if (self.isLoadingPublicFeed || self.isLoadingFeed) {
        return;
    }
    if (self.apiClient == nil) {
        [self showRetryState];
        return;
    }

    self.loadingPublicFeed = YES;
    self.pendingForceRefresh = NO;
    if (self.sections.count == 0) {
        [self showSkeleton];
    }

    __weak MRForYouViewController *weakSelf = self;
    self.publicTask = [self.apiClient fetchTrendingWeekWithCompletion:
                       ^(NSDictionary *json, NSError *error) {
        MRForYouViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.loadingPublicFeed = NO;
        strongSelf.publicTask = nil;
        [strongSelf.refreshControl endRefreshing];

        if (error == nil) {
            NSArray *publicSections =
                [MRPublicFeedBuilder signedOutSectionsWithTrending:json];
            [strongSelf applySections:publicSections allowShortRows:YES];
            if (strongSelf.isSignedIn) {
                [strongSelf showRefreshBannerWithMessage:@"Couldn't refresh recommendations"];
            } else {
                [strongSelf hideRefreshBanner];
            }
        } else if (strongSelf.sections.count > 0) {
            [strongSelf hideSkeleton];
            [strongSelf showRefreshBannerWithMessage:
                strongSelf.isSignedIn ? @"Couldn't refresh recommendations"
                                        : @"Couldn't refresh trending"];
            [strongSelf.tableView reloadData];
        } else {
            [strongSelf showRetryState];
        }

        if (strongSelf.pendingForceRefresh) {
            strongSelf.pendingForceRefresh = NO;
            [strongSelf refreshFeedForce:YES];
        }
    }];
}

- (void)loadPublicFallback {
    // The engine had no cached rows. Render public trending rather than an
    // empty page, and keep the failure visible with a Retry banner.
    [self loadPublicFeed];
}

- (void)applySections:(NSArray *)sections allowShortRows:(BOOL)allowShortRows {
    NSArray *visible = [self visibleSectionsFromSections:sections
                                          allowShortRows:allowShortRows];
    self.sections = visible;
    [self.skeletonView removeFromSuperview];
    self.skeletonView = nil;
    self.retryView.hidden = YES;

    if (visible.count == 0) {
        [self showRetryState];
        return;
    }

    self.tableView.hidden = NO;
    [self.tableView reloadData];
    [self updateBannerDisplay];
}

- (NSArray *)visibleSectionsFromSections:(NSArray *)sections
                           allowShortRows:(BOOL)allowShortRows {
    if (![sections isKindOfClass:[NSArray class]]) {
        return @[];
    }

    BOOL signedIn = [self isSignedIn];
    MRPreferencesStore *preferences = self.preferences;
    NSMutableArray *visible = [NSMutableArray array];

    for (MRFeedSection *section in (NSArray *)sections) {
        if (![section isKindOfClass:[MRFeedSection class]]) {
            continue;
        }

        if (section.kind == MRFeedSectionKindHero) {
            if (signedIn && section.source == MRFeedSourceConnect) {
                continue;
            }
            [visible addObject:section];
            continue;
        }

        NSMutableArray *items = [NSMutableArray array];
        for (MRMediaItem *item in section.items) {
            if (![item isKindOfClass:[MRMediaItem class]]) {
                continue;
            }
            if (signedIn && preferences != nil &&
                [preferences isHiddenType:item.type simklID:item.simklID]) {
                continue;
            }
            [items addObject:item];
        }

        if (section.source == MRFeedSourceEmptyState) {
            MRFeedSection *copy = [MRFeedSection rowSectionWithSource:section.source
                                                                title:section.title
                                                                items:items];
            copy.subtitle = section.subtitle;
            [visible addObject:copy];
            continue;
        }

        NSUInteger minimum = allowShortRows ? 1 : 3;
        if (section.source == MRFeedSourceContinueWatching) {
            minimum = 1;
        }
        if (items.count < minimum) {
            continue;
        }

        MRFeedSection *copy = [MRFeedSection rowSectionWithSource:section.source
                                                            title:section.title
                                                            items:items];
        copy.subtitle = section.subtitle;
        [visible addObject:copy];
    }

    return visible;
}

- (void)showSkeleton {
    self.tableView.hidden = YES;
    self.retryView.hidden = YES;
    [self hideRefreshBanner];
    if (self.skeletonView == nil) {
        self.skeletonView =
            [[MRForYouSkeletonView alloc] initWithFrame:self.view.bounds];
        self.skeletonView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.skeletonView];
    }
    self.skeletonView.hidden = NO;
}

- (void)hideSkeleton {
    self.skeletonView.hidden = YES;
}

- (void)showRetryState {
    [self hideSkeleton];
    [self hideRefreshBanner];
    [self.refreshControl endRefreshing];
    self.tableView.hidden = YES;
    self.retryView.hidden = NO;
    [self layoutRetryView];
}

- (NSString *)quotaLimitMessage {
    MRQuotaTracker *quota = self.environment.quotaTracker;
    if (quota == nil || quota.remaining != 0) {
        return nil;
    }

    NSString *message = @"Daily limit reached";
    if (quota.limit >= 0) {
        message = [message stringByAppendingFormat:@" · 0 of %ld left", (long)quota.limit];
    }
    if (quota.resetAt != nil) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterNoStyle];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
        message = [message stringByAppendingFormat:@" · resets %@",
                   [formatter stringFromDate:quota.resetAt]];
    }
    return message;
}

- (void)showRefreshBannerWithMessage:(NSString *)message {
    self.refreshBannerMessage = message;
    [self updateBannerDisplay];
}

- (void)hideRefreshBanner {
    self.refreshBannerMessage = nil;
    [self updateBannerDisplay];
}

- (void)updateBannerDisplay {
    NSString *quotaMessage = [self quotaLimitMessage];
    NSString *message = quotaMessage != nil ? quotaMessage : self.refreshBannerMessage;
    if (message.length == 0 || self.sections.count == 0) {
        [self.bannerView hide];
        if (self.tableView.tableHeaderView == self.bannerView) {
            self.tableView.tableHeaderView = nil;
        }
        return;
    }

    [self.bannerView showMessage:message
                          style:quotaMessage != nil ? MRBannerStyleError
                                                    : MRBannerStyleWarning
                     retryTitle:quotaMessage != nil ? nil : @"Retry"];
    self.bannerView.frame = CGRectMake(0.0, 0.0,
                                       CGRectGetWidth(self.tableView.bounds),
                                       [MRBannerView height]);
    self.tableView.tableHeaderView = self.bannerView;
}

- (void)refreshPulled:(UIRefreshControl *)sender {
    [self refreshFeedForce:YES];
}

#pragma mark - Actions

- (void)openDetailForItem:(MRMediaItem *)item {
    if (item == nil || self.navigationController == nil) {
        return;
    }

    MRLibraryStore *store = self.libraryStore;
    MRMediaItem *known = [store itemForType:item.type simklID:item.simklID];
    MRMediaItem *target = known != nil ? known : item;
    MRPreferencesStore *preferences = self.isSignedIn ? self.preferences : nil;

    MRDetailViewController *detail =
        [[MRDetailViewController alloc] initWithItem:target
                                           apiClient:self.apiClient
                                        libraryStore:store
                                          imageCache:self.imageCache
                                              outbox:self.environment.outbox
                                        writeService:self.environment.writeService
                                         preferences:preferences];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)showConnect {
    MRSimklAuth *auth = self.auth;
    if (auth == nil) {
        return;
    }
    MRConnectViewController *connect =
        [[MRConnectViewController alloc] initWithAuth:auth];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:connect];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [MRAppearance styleNavigationBar:navigation.navigationBar];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)openGenrePicker {
    id<MRRecommendationDataProviding> provider = self.recommendationEngine.dataProvider;
    if (provider == nil) {
        provider = self.apiClient;
    }
    MRPreferencesStore *preferences = self.preferences;
    if (provider == nil || preferences == nil) {
        return;
    }

    MRGenrePickerViewController *picker =
        [[MRGenrePickerViewController alloc] initWithDataProvider:provider
                                                     preferences:preferences];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:picker];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [MRAppearance styleNavigationBar:navigation.navigationBar];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showActionsForItem:(MRMediaItem *)item
                   section:(MRFeedSection *)section
                sourceView:(UIView *)sourceView {
    if (item == nil) {
        return;
    }

    BOOL signedIn = self.isSignedIn && self.preferences != nil;
    NSMutableArray *identifiers = [NSMutableArray array];
    if (signedIn) {
        [identifiers addObject:MRForYouActionNotInterested];
    }
    [identifiers addObject:MRForYouActionWhyThis];
    [identifiers addObject:MRForYouActionOpenOnSimkl];

    self.actionItem = item;
    self.actionSection = section;
    self.actionSourceView = sourceView;
    self.actionIdentifiers = identifiers;

    UIActionSheet *sheet =
        [[UIActionSheet alloc] initWithTitle:item.title
                                   delegate:self
                          cancelButtonTitle:nil
                     destructiveButtonTitle:nil
                          otherButtonTitles:nil];
    for (NSString *identifier in identifiers) {
        if ([identifier isEqualToString:MRForYouActionNotInterested]) {
            [sheet addButtonWithTitle:@"Not Interested"];
        } else if ([identifier isEqualToString:MRForYouActionWhyThis]) {
            [sheet addButtonWithTitle:@"Why this?"];
        } else if ([identifier isEqualToString:MRForYouActionOpenOnSimkl]) {
            [sheet addButtonWithTitle:@"Open on Simkl"];
        }
    }
    [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = sheet.numberOfButtons - 1;
    sheet.tag = MRForYouActionSheetTag;

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && sourceView != nil) {
        CGRect anchor = [sourceView convertRect:sourceView.bounds toView:self.view];
        [sheet showFromRect:anchor inView:self.view animated:YES];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet
    clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != MRForYouActionSheetTag) {
        return;
    }
    if (buttonIndex < 0 || (NSUInteger)buttonIndex >= self.actionIdentifiers.count) {
        return;
    }

    NSString *identifier =
        [self.actionIdentifiers objectAtIndex:(NSUInteger)buttonIndex];
    MRMediaItem *item = self.actionItem;
    MRFeedSection *section = self.actionSection;

    if ([identifier isEqualToString:MRForYouActionNotInterested]) {
        [self hideItemFromForYou:item];
    } else if ([identifier isEqualToString:MRForYouActionWhyThis]) {
        NSString *reason = section.subtitle.length > 0
            ? section.subtitle
            : section.title;
        if (reason.length == 0) {
            reason = @"This title is popular on Simkl this week.";
        }
        UIAlertView *alert = [[UIAlertView alloc]
            initWithTitle:item.title.length > 0 ? item.title : @"Why this?"
                  message:reason
                 delegate:nil
        cancelButtonTitle:@"OK"
        otherButtonTitles:nil];
        [alert show];
    } else if ([identifier isEqualToString:MRForYouActionOpenOnSimkl]) {
        [self openItemOnSimkl:item];
    }
}

- (void)hideItemFromForYou:(MRMediaItem *)item {
    if (item == nil || self.preferences == nil) {
        return;
    }

    self.suppressPreferencesRefresh = YES;
    NSError *error = nil;
    BOOL hidden = [self.preferences hideTitle:item error:&error];
    self.suppressPreferencesRefresh = NO;
    if (!hidden) {
        NSString *message = @"This title couldn't be hidden.";
        if ([error.domain isEqualToString:MRPreferencesStoreErrorDomain] &&
            error.code == MRPreferencesStoreErrorHiddenTitleLimit) {
            message = @"You can hide up to 200 titles.";
        }
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Couldn't Hide"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    [self updatePreferencesSignature];
    [MRToastView showMessage:@"Hidden from For You" inView:self.view];

    NSMutableArray *kept = [NSMutableArray array];
    for (MRFeedSection *section in self.sections) {
        BOOL heroWasHidden = NO;
        if (section.kind == MRFeedSectionKindHero) {
            for (MRMediaItem *heroItem in section.items) {
                if (heroItem.type == item.type &&
                    heroItem.simklID == item.simklID) {
                    heroWasHidden = YES;
                    break;
                }
            }
        }
        if (heroWasHidden) {
            continue;
        }
        if (section.kind == MRFeedSectionKindRow) {
            NSMutableArray *items = [NSMutableArray array];
            for (MRMediaItem *candidate in section.items) {
                if (candidate.type == item.type &&
                    candidate.simklID == item.simklID) {
                    continue;
                }
                [items addObject:candidate];
            }
            MRFeedSection *copy =
                [MRFeedSection rowSectionWithSource:section.source
                                              title:section.title
                                              items:items];
            copy.subtitle = section.subtitle;
            [kept addObject:copy];
        } else {
            [kept addObject:section];
        }
    }

    self.sections = [self visibleSectionsFromSections:kept allowShortRows:NO];
    if (self.sections.count == 0) {
        MRFeedSection *empty =
            [MRFeedSection rowSectionWithSource:MRFeedSourceEmptyState
                                          title:@"Find something on Simkl"
                                          items:@[]];
        empty.subtitle = @"Search Simkl for something new.";
        self.sections = @[ empty ];
    }
    [self.tableView reloadData];

    [self refreshFeedForce:YES];
}

- (void)openItemOnSimkl:(MRMediaItem *)item {
    if (item.simklID <= 0) {
        return;
    }
    NSString *string = [MRURLBuilder simklWebURLForType:item.type
                                               simklID:item.simklID
                                                   slug:item.slug];
    NSURL *URL = [NSURL URLWithString:string];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)switchToSearch {
    if (self.tabBarController != nil) {
        self.tabBarController.selectedIndex = 2;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < 0 ||
        (NSUInteger)indexPath.section >= self.sections.count) {
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:nil];
    }

    MRFeedSection *section =
        [self.sections objectAtIndex:(NSUInteger)indexPath.section];

    if (section.kind == MRFeedSectionKindHero) {
        static NSString *heroIdentifier = @"MRForYouHeroCell";
        MRForYouHeroCell *cell = (MRForYouHeroCell *)
            [tableView dequeueReusableCellWithIdentifier:heroIdentifier];
        if (cell == nil) {
            cell = [[MRForYouHeroCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:heroIdentifier];
        }

        __weak MRForYouViewController *weakSelf = self;
        void (^handler)(void) = nil;
        NSString *buttonTitle = nil;
        MRMediaItem *heroItem =
            section.items.count > 0 ? [section.items objectAtIndex:0] : nil;
        if (section.source == MRFeedSourceConnect) {
            buttonTitle = @"Sign In";
            handler = ^{ [weakSelf showConnect]; };
        } else if (section.source == MRFeedSourceGenrePicker) {
            buttonTitle = @"Pick Genres";
            handler = ^{ [weakSelf openGenrePicker]; };
        } else if (heroItem != nil) {
            buttonTitle = @"Details";
            handler = ^{ [weakSelf openDetailForItem:heroItem]; };
        }

        [cell configureWithTitle:section.title
                        subtitle:section.subtitle
                     buttonTitle:buttonTitle
                         handler:handler];
        return cell;
    }

    if (section.source == MRFeedSourceEmptyState) {
        static NSString *emptyIdentifier = @"MRForYouEmptyCell";
        MRForYouEmptyCell *cell = (MRForYouEmptyCell *)
            [tableView dequeueReusableCellWithIdentifier:emptyIdentifier];
        if (cell == nil) {
            cell = [[MRForYouEmptyCell alloc] initWithStyle:UITableViewCellStyleDefault
                                            reuseIdentifier:emptyIdentifier];
        }
        __weak MRForYouViewController *weakSelf = self;
        [cell configureWithTitle:section.title
                        subtitle:section.subtitle
                     tapHandler:^{ [weakSelf switchToSearch]; }];
        return cell;
    }

    static NSString *rowIdentifier = @"MRForYouRowCell";
    MRForYouRowCell *cell = (MRForYouRowCell *)
        [tableView dequeueReusableCellWithIdentifier:rowIdentifier];
    if (cell == nil) {
        cell = [[MRForYouRowCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:rowIdentifier];
    }

    __weak MRForYouViewController *weakSelf = self;
    [cell configureWithImageCache:self.imageCache
                            items:section.items
                           source:section.source
                       tapHandler:^(MRMediaItem *item) {
        [weakSelf openDetailForItem:item];
    }
                  longPressHandler:^(MRMediaItem *item, UIView *sourceView) {
        [weakSelf showActionsForItem:item section:section sourceView:sourceView];
    }];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < 0 ||
        (NSUInteger)indexPath.section >= self.sections.count) {
        return 0.0;
    }

    MRFeedSection *section =
        [self.sections objectAtIndex:(NSUInteger)indexPath.section];
    MRDeviceClass device = MRForYouDeviceClass();
    if (section.kind == MRFeedSectionKindHero) {
        CGFloat heroInset = [MRLayout heroSideInsetForDeviceClass:device];
        CGFloat heroHeight =
            [MRLayout heroHeightForDeviceClass:device
                                   orientation:[MRLayout orientationForSize:tableView.bounds.size]
                               availableHeight:MRForYouAvailableHeight()];
        return heroHeight + heroInset * 2.0;
    }
    if (section.source == MRFeedSourceEmptyState) {
        return 160.0;
    }
    return [MRLayout posterRowHeightForDeviceClass:device];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section < 0 || (NSUInteger)section >= self.sections.count) {
        return 0.0;
    }
    MRFeedSection *feedSection =
        [self.sections objectAtIndex:(NSUInteger)section];
    if (feedSection.kind == MRFeedSectionKindHero ||
        feedSection.source == MRFeedSourceEmptyState) {
        return 0.0;
    }
    return [MRLayout rowHeaderHeightForDeviceClass:MRForYouDeviceClass()];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section < 0 || (NSUInteger)section >= self.sections.count) {
        return nil;
    }
    MRFeedSection *feedSection =
        [self.sections objectAtIndex:(NSUInteger)section];
    if (feedSection.kind == MRFeedSectionKindHero ||
        feedSection.source == MRFeedSourceEmptyState) {
        return nil;
    }

    BOOL showsBadge = feedSection.source == MRFeedSourceTrending ||
                      feedSection.source == MRFeedSourcePublicTrending;
    return [[MRRowHeaderView alloc] initWithTitle:feedSection.title
                                   showsSimklBadge:showsBadge];
}

@end
