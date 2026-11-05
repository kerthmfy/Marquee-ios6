//
//  MRForYouViewController.m
//  Marquee
//

#import "MRForYouViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAPIClient.h"
#import "MRAPIRequestOperation.h"
#import "MRAppearance.h"
#import "MRClock.h"
#import "MRConnectViewController.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRFeedSection.h"
#import "MRHeroView.h"
#import "MRHTTPClient.h"
#import "MRImageCache.h"
#import "MRKeychainTokenStore.h"
#import "MRMediaItem.h"
#import "MRPlaceholderView.h"
#import "MRPosterCardView.h"
#import "MRPublicFeedBuilder.h"
#import "MRResponseCache.h"
#import "MRRowHeaderView.h"
#import "MRSimklAuth.h"
#import "MRTokenSession.h"

static const CGFloat MRForYouRowHeight = 210.0;
static const CGFloat MRForYouCardGap = 8.0;
static const CGFloat MRForYouCardWidth = 100.0;

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
        for (NSInteger row = 0; row < 2; row++) {
            UIView *header = [self blockView];
            header.frame = CGRectMake(12.0, 0.0, 140.0, 11.0);
            [_headerBlocks addObject:header];
            [self addSubview:header];

            for (NSInteger column = 0; column < 3; column++) {
                UIView *card = [self blockView];
                card.frame = CGRectMake(0.0, 0.0, MRForYouCardWidth, 150.0);
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

    CGFloat width = CGRectGetWidth(self.bounds);
    CGRect screen = [[UIScreen mainScreen] bounds];
    CGFloat heroHeight = CGRectGetHeight(screen) < 568.0 ? 180.0 : 200.0;

    self.heroBlock.frame = CGRectMake(8.0, 8.0, width - 16.0, heroHeight);

    CGFloat y = 8.0 + heroHeight + 18.0;
    NSUInteger cardIndex = 0;
    for (NSUInteger row = 0; row < self.headerBlocks.count; row++) {
        UIView *header = [self.headerBlocks objectAtIndex:row];
        header.frame = CGRectMake(12.0, y, 140.0, 11.0);
        y += 11.0 + 12.0;

        for (NSInteger column = 0; column < 3; column++) {
            UIView *card = [self.cardBlocks objectAtIndex:cardIndex];
            card.frame = CGRectMake(12.0 + (CGFloat)column * (MRForYouCardWidth + MRForYouCardGap),
                                    y,
                                    MRForYouCardWidth,
                                    150.0);
            cardIndex += 1;
        }
        y += 150.0 + 18.0;
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
    self.heroView.frame = CGRectMake(8.0,
                                     8.0,
                                     CGRectGetWidth(self.contentView.bounds) - 16.0,
                                     CGRectGetHeight(self.contentView.bounds) - 16.0);
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

    CGFloat x = 12.0;
    for (MRMediaItem *item in items) {
        MRPosterCardView *card =
            [[MRPosterCardView alloc] initWithImageCache:imageCache];
        card.frame = CGRectMake(x, 0.0, MRForYouCardWidth, MRForYouRowHeight);
        card.tapHandler = tapHandler;
        [card setItem:item];
        [self.scrollView addSubview:card];
        [self.cards addObject:card];
        x += MRForYouCardWidth + MRForYouCardGap;
    }

    CGFloat contentWidth = x - MRForYouCardGap + 12.0;
    if (contentWidth < CGRectGetWidth(self.contentView.bounds)) {
        contentWidth = CGRectGetWidth(self.contentView.bounds);
    }
    self.scrollView.contentSize = CGSizeMake(contentWidth, MRForYouRowHeight);
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
@property (nonatomic, strong) MRAPIClient *apiClient;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, assign, getter=isLoadingFeed) BOOL loadingFeed;
@property (nonatomic, strong) id<MRHTTPTask> trendingTask;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *bannerView;
@property (nonatomic, strong) MRForYouSkeletonView *skeletonView;
@property (nonatomic, strong) MRPlaceholderView *retryView;
@property (nonatomic, strong) MRSimklAuth *auth;
@end

@implementation MRForYouViewController

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                       imageCache:(MRImageCache *)imageCache {
    self = [super init];
    if (self) {
        _apiClient = apiClient;
        _imageCache = imageCache;
        _sections = @[];
    }
    return self;
}

- (id)init {
    // Temporary shared services. Task 9 replaces these with app-wide instances.
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                            NSUserDomainMask,
                                                            YES) objectAtIndex:0];
    NSString *base = [caches stringByAppendingPathComponent:@"Marquee"];
    MRDiagnostics *diagnostics = [[MRDiagnostics alloc]
        initWithDirectory:[base stringByAppendingPathComponent:@"Diagnostics"]];
    MRSystemClock *clock = [[MRSystemClock alloc] init];

    MRAPIClient *client = [[MRAPIClient alloc]
        initWithHTTPClient:[MRAPIRequestOperation sharedClient]
             tokenProvider:nil
             responseCache:[[MRResponseCache alloc]
                            initWithDirectory:[base stringByAppendingPathComponent:@"Responses"]]
              quotaTracker:nil
               diagnostics:diagnostics
                     clock:clock];

    self = [self initWithAPIClient:client imageCache:[[MRImageCache alloc] init]];
    if (self) {
        _auth = [[MRSimklAuth alloc] initWithHTTPClient:[MRAPIRequestOperation sharedClient]
                                            tokenStore:[[MRKeychainTokenStore alloc] init]
                                           diagnostics:diagnostics
                                                 clock:clock];
    }
    return self;
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
    retry.frame = CGRectMake(0.0,
                             (CGRectGetHeight(self.view.bounds) - 180.0) / 2.0,
                             CGRectGetWidth(self.view.bounds),
                             180.0);
    retry.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin;
    retry.hidden = YES;
    __weak MRForYouViewController *weakSelf = self;
    retry.actionHandler = ^{
        [weakSelf loadFeed];
    };
    [self.view addSubview:retry];
    self.retryView = retry;

    [self buildBanner];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authDidChange:)
                                                 name:MRAuthDidChangeNotification
                                               object:nil];

    [self loadFeed];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    id<MRHTTPTask> task = self.trendingTask;
    self.trendingTask = nil;
    [task cancel];
}

- (void)authDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)buildBanner {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 32.0)];
    banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    banner.backgroundColor = [UIColor colorWithRed:247.0 / 255.0
                                             green:230.0 / 255.0
                                              blue:188.0 / 255.0
                                             alpha:1.0];
    banner.hidden = YES;
    [self.view addSubview:banner];
    self.bannerView = banner;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 0.0,
                                                               width - 84.0, 32.0)];
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
    retry.frame = CGRectMake(width - 72.0, 4.0, 60.0, 24.0);
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

        strongSelf.sections =
            [MRPublicFeedBuilder signedOutSectionsWithTrending:json];
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

- (MRSimklAuth *)authForConnect {
    if (self.auth == nil) {
        // Fallback for a controller created through the designated initializer
        // before Task 9 injects the app-wide auth service.
        self.auth = [[MRSimklAuth alloc] initWithHTTPClient:[MRAPIRequestOperation sharedClient]
                                                 tokenStore:[[MRKeychainTokenStore alloc] init]
                                                diagnostics:[[MRDiagnostics alloc] initWithDirectory:nil]
                                                      clock:[[MRSystemClock alloc] init]];
    }
    return self.auth;
}

- (void)showConnect {
    MRConnectViewController *connect =
        [[MRConnectViewController alloc] initWithAuth:[self authForConnect]];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:connect];
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
        BOOL signedIn = self.auth.isSignedIn;
        NSString *title = section.title;
        NSString *subtitle = section.subtitle;
        NSString *buttonTitle = @"Sign In";
        __weak MRForYouViewController *weakSelf = self;
        if (signedIn) {
            NSString *name = self.auth.session.accountName;
            title = name.length > 0
                ? [NSString stringWithFormat:@"Connected as %@", name]
                : @"Connected to Simkl";
            subtitle = @"Your Simkl account is connected.";
            buttonTitle = @"";
            cell.heroView.actionHandler = nil;
        } else {
            cell.heroView.actionHandler = ^{
                [weakSelf showConnect];
            };
        }
        [cell.heroView configureWithTitle:title
                                 subtitle:subtitle
                              buttonTitle:buttonTitle];
        return cell;
    }

    static NSString *rowIdentifier = @"MRForYouRowCell";
    MRForYouRowCell *cell = (MRForYouRowCell *)
        [tableView dequeueReusableCellWithIdentifier:rowIdentifier];
    if (cell == nil) {
        cell = [[MRForYouRowCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:rowIdentifier];
    }
    [cell configureWithImageCache:self.imageCache items:section.items tapHandler:nil];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    MRFeedSection *section = [self.sections objectAtIndex:(NSUInteger)indexPath.section];
    if (section.kind == MRFeedSectionKindHero) {
        CGRect screen = [[UIScreen mainScreen] bounds];
        CGFloat heroHeight = CGRectGetHeight(screen) < 568.0 ? 180.0 : 200.0;
        return heroHeight + 16.0;
    }
    return MRForYouRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    MRFeedSection *feedSection = [self.sections objectAtIndex:(NSUInteger)section];
    return feedSection.kind == MRFeedSectionKindHero ? 0.0 : 32.0;
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
