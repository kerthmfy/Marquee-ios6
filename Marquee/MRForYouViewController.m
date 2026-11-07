//
//  MRForYouViewController.m
//  Marquee
//

#import "MRForYouViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAPIClient.h"
#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRConnectViewController.h"
#import "MRDetailViewController.h"
#import "MRError.h"
#import "MRFeedSection.h"
#import "MRHeroView.h"
#import "MRHTTPClient.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPlaceholderView.h"
#import "MRPosterCardView.h"
#import "MRPublicFeedBuilder.h"
#import "MRRowHeaderView.h"
#import "MRSimklAuth.h"
#import "MRSyncEngine.h"

static MRDeviceClass MRForYouDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static CGFloat MRForYouAvailableHeight(void) {
    CGRect screen = [[UIScreen mainScreen] bounds];
    return MAX(CGRectGetWidth(screen), CGRectGetHeight(screen));
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

    self.heroBlock.frame = CGRectMake(heroInset, heroInset,
                                      width - heroInset * 2.0, heroHeight);

    CGFloat y = heroInset + heroHeight + 18.0;
    NSUInteger cardIndex = 0;
    for (NSUInteger row = 0; row < self.headerBlocks.count; row++) {
        UIView *header = [self.headerBlocks objectAtIndex:row];
        header.frame = CGRectMake(rowInset, y, 140.0, 11.0);
        y += 11.0 + 12.0;

        for (NSInteger column = 0; column < 3; column++) {
            UIView *card = [self.cardBlocks objectAtIndex:cardIndex];
            card.frame = CGRectMake(rowInset + (CGFloat)column * (cardWidth + cardGap),
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

- (void)layoutSubviews {
    [super layoutSubviews];
    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat inset = [MRLayout heroSideInsetForDeviceClass:device];
    self.heroView.frame = CGRectMake(inset,
                                     inset,
                                     CGRectGetWidth(self.contentView.bounds) - inset * 2.0,
                                     CGRectGetHeight(self.contentView.bounds) - inset * 2.0);
}

@end

@interface MRForYouRowCell : UITableViewCell
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *cards;
@property (nonatomic, strong) MRImageCache *imageCache;
- (void)configureWithImageCache:(MRImageCache *)imageCache
                          items:(NSArray *)items
                     tapHandler:(void (^)(MRMediaItem *item))tapHandler;
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
                     tapHandler:(void (^)(MRMediaItem *item))tapHandler {
    self.imageCache = imageCache;

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
        [card setItem:item];
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

#pragma mark - Controller

@interface MRForYouViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) MRAppEnvironment *environment;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, copy) NSArray *publicSections;
@property (nonatomic, assign, getter=isLoadingFeed) BOOL loadingFeed;
@property (nonatomic, strong) id<MRHTTPTask> trendingTask;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *bannerView;
@property (nonatomic, strong) MRForYouSkeletonView *skeletonView;
@property (nonatomic, strong) MRPlaceholderView *retryView;
@property (nonatomic, strong) UIView *statusHeaderView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@end

@implementation MRForYouViewController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment {
    self = [super init];
    if (self) {
        _environment = environment;
        _sections = @[];
        _publicSections = @[];
    }
    return self;
}

- (id)init {
    return [self initWithEnvironment:nil];
}

- (MRAPIClient *)apiClient {
    return self.environment.apiClient;
}

- (MRImageCache *)imageCache {
    return self.environment.imageCache;
}

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
    self.skeletonView.hidden = YES;
    [self.view addSubview:self.skeletonView];

    MRPlaceholderView *retry =
        [[MRPlaceholderView alloc] initWithMessage:@"Couldn't load Simkl trending."
                                        actionTitle:@"Retry"];
    CGFloat retryWidth = MIN(CGRectGetWidth(self.view.bounds),
        [MRLayout contentMaxWidthForDeviceClass:MRForYouDeviceClass()]);
    retry.frame = CGRectMake((CGRectGetWidth(self.view.bounds) - retryWidth) / 2.0,
                             (CGRectGetHeight(self.view.bounds) - 180.0) / 2.0,
                             retryWidth,
                             180.0);
    retry.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    retry.hidden = YES;
    __weak MRForYouViewController *weakSelf = self;
    retry.actionHandler = ^{
        [weakSelf loadFeed];
    };
    [self.view addSubview:retry];
    self.retryView = retry;

    [self buildBanner];
    [self buildStatusHeader];

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

    [self updateStatusHeader];
    [self loadFeed];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) {
        return;
    }

    [self layoutStatusHeader];
    if (width == self.lastLayoutWidth) {
        return;
    }

    self.lastLayoutWidth = width;
    [self layoutRetryView];
    [self.tableView reloadData];
}

- (void)layoutRetryView {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat contentWidth = MIN(width,
        [MRLayout contentMaxWidthForDeviceClass:MRForYouDeviceClass()]);
    self.retryView.frame = CGRectMake((width - contentWidth) / 2.0,
                                      (CGRectGetHeight(self.view.bounds) - 180.0) / 2.0,
                                      contentWidth,
                                      180.0);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    id<MRHTTPTask> task = self.trendingTask;
    self.trendingTask = nil;
    [task cancel];
}

- (void)authDidChange:(NSNotification *)notification {
    [self rebuildVisibleSections];
    [self updateStatusHeader];
    [self.tableView reloadData];
}

- (void)libraryDidChange:(NSNotification *)notification {
    [self updateStatusHeader];
}

- (void)syncStatusDidChange:(NSNotification *)notification {
    [self updateStatusHeader];
}

- (void)rebuildVisibleSections {
    if (!self.environment.auth.isSignedIn) {
        self.sections = self.publicSections;
        return;
    }

    NSMutableArray *visible = [NSMutableArray array];
    for (MRFeedSection *section in self.publicSections) {
        if (section.kind != MRFeedSectionKindHero) {
            [visible addObject:section];
        }
    }
    self.sections = visible;
}

- (void)buildStatusHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = [UIColor clearColor];
    header.opaque = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.font = [MRAppearance smallFont];
    label.textColor = [MRAppearance muted];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [header addSubview:label];

    self.statusHeaderView = header;
    self.statusLabel = label;
}

- (void)updateStatusHeader {
    NSString *text = nil;
    if (self.environment.auth.isSignedIn) {
        MRSyncEngine *engine = self.environment.syncEngine;
        MRLibraryStore *store = self.environment.libraryStore;
        if (engine.isSyncing) {
            text = @"Syncing…";
        } else if (engine.lastSyncError != nil) {
            text = @"Sync failed — showing saved library.";
        } else if (store != nil) {
            text = [NSString stringWithFormat:@"Synced %lu items",
                    (unsigned long)store.items.count];
        } else {
            text = @"Sync failed — showing saved library.";
        }
    }

    self.statusLabel.text = text;
    self.tableView.tableHeaderView =
        text.length > 0 ? self.statusHeaderView : nil;
    [self layoutStatusHeader];
}

- (void)layoutStatusHeader {
    if (self.statusHeaderView == nil || self.tableView == nil) {
        return;
    }

    MRDeviceClass device = MRForYouDeviceClass();
    CGFloat tableWidth = CGRectGetWidth(self.tableView.bounds);
    CGFloat contentWidth = MIN(tableWidth,
        [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat height = [MRLayout rowHeaderHeightForDeviceClass:device];

    self.statusHeaderView.frame = CGRectMake(0.0, 0.0, tableWidth, height);
    self.statusLabel.frame = CGRectMake((tableWidth - contentWidth) / 2.0 + inset,
                                        0.0,
                                        MAX(contentWidth - inset * 2.0, 0.0),
                                        height);
}

- (void)buildBanner {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat rowInset = [MRLayout rowSideInsetForDeviceClass:MRForYouDeviceClass()];
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 32.0)];
    banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    banner.backgroundColor = [UIColor colorWithRed:247.0 / 255.0
                                             green:230.0 / 255.0
                                              blue:188.0 / 255.0
                                             alpha:1.0];
    banner.hidden = YES;
    [self.view addSubview:banner];
    self.bannerView = banner;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(rowInset, 0.0,
                                                               width - rowInset * 2.0 - 60.0,
                                                               32.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:11.0];
    label.textColor = [UIColor colorWithRed:104.0 / 255.0
                                      green:74.0 / 255.0
                                       blue:8.0 / 255.0
                                      alpha:1.0];
    label.text = @"Couldn't refresh. Showing the last trending feed.";
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [banner addSubview:label];

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeCustom];
    retry.frame = CGRectMake(width - rowInset - 60.0, 4.0, 60.0, 24.0);
    retry.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    retry.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    [retry setTitle:@"Retry" forState:UIControlStateNormal];
    [retry setTitleColor:[UIColor colorWithRed:104.0 / 255.0
                                         green:74.0 / 255.0
                                          blue:8.0 / 255.0
                                         alpha:1.0]
                forState:UIControlStateNormal];
    [retry addTarget:self
              action:@selector(bannerRetryTapped:)
    forControlEvents:UIControlEventTouchUpInside];
    [banner addSubview:retry];
}

#pragma mark - Loading

- (void)loadFeed {
    if (self.isLoadingFeed) {
        return;
    }
    if (self.apiClient == nil) {
        [self handleLoadError:[MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    self.loadingFeed = YES;
    self.bannerView.hidden = YES;

    if (self.sections.count == 0) {
        self.tableView.hidden = YES;
        self.retryView.hidden = YES;
        self.skeletonView.hidden = NO;
    }

    __weak MRForYouViewController *weakSelf = self;
    self.trendingTask = [self.apiClient fetchTrendingWeekWithCompletion:
                         ^(NSDictionary *json, NSError *error) {
        MRForYouViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.loadingFeed = NO;
        strongSelf.trendingTask = nil;
        [strongSelf.refreshControl endRefreshing];

        if (error != nil) {
            [strongSelf handleLoadError:error];
            return;
        }

        strongSelf.publicSections =
            [MRPublicFeedBuilder signedOutSectionsWithTrending:json];
        [strongSelf rebuildVisibleSections];
        strongSelf.skeletonView.hidden = YES;
        strongSelf.retryView.hidden = YES;
        strongSelf.tableView.hidden = NO;
        [strongSelf.tableView reloadData];
    }];
}

- (void)handleLoadError:(NSError *)error {
    self.loadingFeed = NO;
    self.skeletonView.hidden = YES;
    [self.refreshControl endRefreshing];

    if (self.sections.count == 0) {
        self.tableView.hidden = YES;
        self.bannerView.hidden = YES;
        self.retryView.hidden = NO;
    } else {
        self.tableView.hidden = NO;
        self.retryView.hidden = YES;
        self.bannerView.hidden = NO;
    }
}

- (void)refreshPulled:(UIRefreshControl *)sender {
    [self loadFeed];
}

- (void)bannerRetryTapped:(UIButton *)sender {
    [self loadFeed];
}

- (void)openDetailForItem:(MRMediaItem *)item {
    if (item == nil || self.navigationController == nil) {
        return;
    }

    MRLibraryStore *store = self.environment.libraryStore;
    MRMediaItem *known = [store itemForType:item.type simklID:item.simklID];
    MRMediaItem *target = known != nil ? known : item;

    MRDetailViewController *detail =
        [[MRDetailViewController alloc] initWithItem:target
                                           apiClient:self.environment.apiClient
                                        libraryStore:store
                                          imageCache:self.imageCache];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)showConnect {
    MRSimklAuth *auth = self.environment.auth;
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MRFeedSection *section = [self.sections objectAtIndex:(NSUInteger)indexPath.section];

    if (section.kind == MRFeedSectionKindHero) {
        static NSString *heroIdentifier = @"MRForYouHeroCell";
        MRForYouHeroCell *cell = (MRForYouHeroCell *)
            [tableView dequeueReusableCellWithIdentifier:heroIdentifier];
        if (cell == nil) {
            cell = [[MRForYouHeroCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:heroIdentifier];
        }
        __weak MRForYouViewController *weakSelf = self;
        cell.heroView.actionHandler = ^{
            [weakSelf showConnect];
        };
        [cell.heroView configureWithTitle:section.title
                                 subtitle:section.subtitle
                              buttonTitle:@"Sign In"];
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
                       tapHandler:^(MRMediaItem *item) {
        [weakSelf openDetailForItem:item];
    }];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    MRFeedSection *section = [self.sections objectAtIndex:(NSUInteger)indexPath.section];
    MRDeviceClass device = MRForYouDeviceClass();
    if (section.kind == MRFeedSectionKindHero) {
        CGFloat heroInset = [MRLayout heroSideInsetForDeviceClass:device];
        CGFloat heroHeight =
            [MRLayout heroHeightForDeviceClass:device
                                   orientation:[MRLayout orientationForSize:tableView.bounds.size]
                               availableHeight:MRForYouAvailableHeight()];
        return heroHeight + heroInset * 2.0;
    }
    return [MRLayout posterRowHeightForDeviceClass:device];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    MRFeedSection *feedSection = [self.sections objectAtIndex:(NSUInteger)section];
    if (feedSection.kind == MRFeedSectionKindHero) {
        return 0.0;
    }
    return [MRLayout rowHeaderHeightForDeviceClass:MRForYouDeviceClass()];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MRFeedSection *feedSection = [self.sections objectAtIndex:(NSUInteger)section];
    if (feedSection.kind == MRFeedSectionKindHero) {
        return nil;
    }
    BOOL showsBadge = feedSection.source == MRFeedSourcePublicTrending;
    return [[MRRowHeaderView alloc] initWithTitle:feedSection.title
                                   showsSimklBadge:showsBadge];
}

@end
