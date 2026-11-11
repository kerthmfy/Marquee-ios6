//
//  MRSearchViewController.m
//  Marquee
//

#import "MRSearchViewController.h"

#import "MRAPIClient.h"
#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRBannerView.h"
#import "MRConnectViewController.h"
#import "MRDetailViewController.h"
#import "MRError.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MRPlaceholderView.h"
#import "MRPosterImageView.h"
#import "MRPreferencesStore.h"
#import "MRSearchPagination.h"
#import "MRSimklAuth.h"
#import "MRToastView.h"
#import "MRWriteService.h"

static const NSTimeInterval MRSearchDebounceInterval = 0.5;
static const NSTimeInterval MRSearchCacheMaxAge = 10.0 * 60.0;
static const NSUInteger MRSearchSuggestionLimit = 3;

typedef NS_ENUM(NSInteger, MRSearchContentState) {
    MRSearchContentStateSignedOut = 0,
    MRSearchContentStateIdle,
    MRSearchContentStateSearching,
    MRSearchContentStateResults,
    MRSearchContentStateNoMatches,
    MRSearchContentStateError
};

static MRDeviceClass MRSearchDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static CGFloat MRSearchSideInset(void) {
    return [MRLayout rowSideInsetForDeviceClass:MRSearchDeviceClass()];
}

static NSString *MRSearchCommunityRating(NSDictionary *ratings) {
    if (![ratings isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id entry = [ratings objectForKey:@"simkl"];
    if ([entry isKindOfClass:[NSDictionary class]]) {
        entry = [(NSDictionary *)entry objectForKey:@"rating"];
    }
    double rating = [entry respondsToSelector:@selector(doubleValue)]
        ? [entry doubleValue] : 0.0;
    if (rating <= 0.0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%.1f", rating];
}

#pragma mark - Result cell

@interface MRSearchResultCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *ratingLabel;
@property (nonatomic, strong) UILabel *chevronLabel;

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache;
- (void)cancelLoading;

@end

@implementation MRSearchResultCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_cardView first:YES last:YES];
        [self.contentView addSubview:_cardView];

        _posterView = [[MRPosterImageView alloc] initWithImageCache:nil];
        _posterView.layer.cornerRadius = 3.0;
        _posterView.layer.masksToBounds = YES;
        [_cardView addSubview:_posterView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance cardTitleFont];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.font = [MRAppearance smallFont];
        _metaLabel.textColor = [MRAppearance muted];
        _metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_metaLabel];

        _ratingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _ratingLabel.backgroundColor = [UIColor clearColor];
        _ratingLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _ratingLabel.textColor = [MRAppearance starColor];
        _ratingLabel.textAlignment = NSTextAlignmentRight;
        [_cardView addSubview:_ratingLabel];

        _chevronLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevronLabel.backgroundColor = [UIColor clearColor];
        _chevronLabel.font = [UIFont boldSystemFontOfSize:22.0];
        _chevronLabel.textColor = [MRAppearance muted];
        _chevronLabel.textAlignment = NSTextAlignmentRight;
        _chevronLabel.text = @"›";
        [_cardView addSubview:_chevronLabel];
    }
    return self;
}

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache {
    [self.posterView setImageCache:imageCache];
    [self.posterView setImagePath:item.poster size:@"_cm"];

    self.titleLabel.text = item.title.length > 0 ? item.title : @"Untitled";

    NSString *typeName = MRMediaTypeDisplayName(item.type);
    if (item.year > 0) {
        self.metaLabel.text = [NSString stringWithFormat:@"%ld · %@",
                               (long)item.year, typeName];
    } else {
        self.metaLabel.text = typeName;
    }

    NSString *rating = MRSearchCommunityRating(item.ratings);
    if (rating.length > 0) {
        self.ratingLabel.text = [NSString stringWithFormat:@"★ %@", rating];
        self.ratingLabel.hidden = NO;
    } else {
        self.ratingLabel.text = @"";
        self.ratingLabel.hidden = YES;
    }

    [self setNeedsLayout];
}

- (void)cancelLoading {
    [self.posterView cancelLoading];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self cancelLoading];
}

- (void)dealloc {
    [self cancelLoading];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRSearchDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat inset = MRSearchSideInset();
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat maxContent = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat cardX = (width - maxContent) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, maxContent - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 4.0, cardWidth, height - 8.0);
    CGFloat cardHeight = CGRectGetHeight(self.cardView.bounds);

    CGFloat posterWidth = tablet ? 60.0 : 42.0;
    CGFloat posterHeight = tablet ? 90.0 : 62.0;
    CGFloat padding = tablet ? 10.0 : 8.0;
    self.posterView.frame = CGRectMake(padding, padding, posterWidth, posterHeight);

    self.titleLabel.font = tablet ? [UIFont boldSystemFontOfSize:17.0]
                                  : [MRAppearance cardTitleFont];
    self.metaLabel.font = tablet ? [UIFont systemFontOfSize:13.0]
                                 : [MRAppearance smallFont];

    CGFloat chevronWidth = 18.0;
    CGFloat ratingWidth = 54.0;
    CGFloat textX = padding + posterWidth + 10.0;
    CGFloat textRight = cardWidth - chevronWidth - padding - ratingWidth;
    CGFloat textWidth = MAX(20.0, textRight - textX);

    if (tablet) {
        self.titleLabel.frame = CGRectMake(textX, 11.0, textWidth, 22.0);
        self.metaLabel.frame = CGRectMake(textX, 36.0, textWidth, 16.0);
    } else {
        self.titleLabel.frame = CGRectMake(textX, 8.0, textWidth, 18.0);
        self.metaLabel.frame = CGRectMake(textX, 27.0, textWidth, 14.0);
    }

    self.ratingLabel.frame = CGRectMake(cardWidth - chevronWidth - padding - ratingWidth,
                                        (cardHeight - 18.0) / 2.0,
                                        ratingWidth, 18.0);
    self.chevronLabel.frame = CGRectMake(cardWidth - chevronWidth - padding + 2.0,
                                         (cardHeight - 24.0) / 2.0,
                                         chevronWidth, 24.0);
}

@end

#pragma mark - Text cell

@interface MRSearchTextCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *chevronLabel;

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               showsChevron:(BOOL)showsChevron;

@end

@implementation MRSearchTextCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_cardView first:YES last:YES];
        [self.contentView addSubview:_cardView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [MRAppearance cardTitleFont];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [MRAppearance smallFont];
        _subtitleLabel.textColor = [MRAppearance muted];
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_subtitleLabel];

        _chevronLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevronLabel.backgroundColor = [UIColor clearColor];
        _chevronLabel.font = [UIFont boldSystemFontOfSize:20.0];
        _chevronLabel.textColor = [MRAppearance muted];
        _chevronLabel.textAlignment = NSTextAlignmentRight;
        _chevronLabel.text = @"›";
        [_cardView addSubview:_chevronLabel];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               showsChevron:(BOOL)showsChevron {
    self.titleLabel.text = title != nil ? title : @"";
    self.subtitleLabel.text = subtitle != nil ? subtitle : @"";
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.chevronLabel.hidden = !showsChevron;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRSearchDeviceClass();
    CGFloat inset = MRSearchSideInset();
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat maxContent = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat cardX = (width - maxContent) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, maxContent - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 2.0, cardWidth, height - 4.0);
    CGFloat cardHeight = CGRectGetHeight(self.cardView.bounds);

    CGFloat chevronWidth = self.chevronLabel.hidden ? 0.0 : 26.0;
    CGFloat textX = 14.0;
    CGFloat textWidth = MAX(20.0, cardWidth - textX - chevronWidth - 14.0);
    if (self.subtitleLabel.hidden) {
        self.titleLabel.frame = CGRectMake(textX, (cardHeight - 20.0) / 2.0,
                                           textWidth, 20.0);
        self.subtitleLabel.frame = CGRectZero;
    } else {
        self.titleLabel.frame = CGRectMake(textX, 10.0, textWidth, 19.0);
        self.subtitleLabel.frame = CGRectMake(textX, 29.0, textWidth, 15.0);
    }
    self.chevronLabel.frame = CGRectMake(cardWidth - chevronWidth - 8.0,
                                         (cardHeight - 22.0) / 2.0,
                                         chevronWidth, 22.0);
}

@end

#pragma mark - Load more cell

@interface MRSearchLoadMoreCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

- (void)configureLoading:(BOOL)loading;

@end

@implementation MRSearchLoadMoreCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_cardView first:YES last:YES];
        [self.contentView addSubview:_cardView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        _titleLabel.textColor = [MRAppearance link];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.text = @"Load More";
        [_cardView addSubview:_titleLabel];

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        [_cardView addSubview:_spinner];
    }
    return self;
}

- (void)configureLoading:(BOOL)loading {
    self.titleLabel.hidden = loading;
    if (loading) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat inset = MRSearchSideInset();
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat maxContent = MIN(width,
        [MRLayout contentMaxWidthForDeviceClass:MRSearchDeviceClass()]);
    CGFloat cardX = (width - maxContent) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, maxContent - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 2.0, cardWidth, height - 4.0);
    self.titleLabel.frame = self.cardView.bounds;
    self.spinner.center = CGPointMake(CGRectGetMidX(self.cardView.bounds),
                                      CGRectGetMidY(self.cardView.bounds));
}

@end

#pragma mark - State cell

@interface MRSearchStateCell : UITableViewCell

@property (nonatomic, strong) MRPlaceholderView *placeholder;

- (void)configureWithMessage:(NSString *)message
                 actionTitle:(NSString *)actionTitle
                     loading:(BOOL)loading
                     handler:(void (^)(void))handler;

@end

@implementation MRSearchStateCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _placeholder = [[MRPlaceholderView alloc] initWithMessage:@""
                                                      actionTitle:nil];
        [self.contentView addSubview:_placeholder];
    }
    return self;
}

- (void)configureWithMessage:(NSString *)message
                 actionTitle:(NSString *)actionTitle
                     loading:(BOOL)loading
                     handler:(void (^)(void))handler {
    MRPlaceholderView *placeholder =
        [[MRPlaceholderView alloc] initWithMessage:message actionTitle:actionTitle];
    [self.placeholder removeFromSuperview];
    self.placeholder = placeholder;
    self.placeholder.actionHandler = handler;
    self.placeholder.loading = loading;
    [self.contentView addSubview:self.placeholder];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat inset = MRSearchSideInset();
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat maxContent = MIN(width,
        [MRLayout contentMaxWidthForDeviceClass:MRSearchDeviceClass()]);
    CGFloat cardWidth = MAX(0.0, maxContent - inset * 2.0);
    self.placeholder.frame = CGRectMake((width - cardWidth) / 2.0,
                                        4.0,
                                        cardWidth,
                                        MAX(0.0, height - 8.0));
}

@end

#pragma mark - Controller

@interface MRSearchViewController () <UISearchBarDelegate, UITableViewDataSource,
                                      UITableViewDelegate>

@property (nonatomic, strong) MRAPIClient *explicitAPIClient;
@property (nonatomic, strong) MRPreferencesStore *explicitPreferences;
@property (nonatomic, strong) MRImageCache *explicitImageCache;

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) MRBannerView *bannerView;
@property (nonatomic, strong) MRPlaceholderView *connectView;
@property (nonatomic, strong) UIButton *footerButton;
@property (nonatomic, strong) UIImageView *footerBadge;

@property (nonatomic, copy) NSArray *recentSearches;
@property (nonatomic, copy) NSArray *suggestions;
@property (nonatomic, copy) NSArray *results;
@property (nonatomic, copy) NSString *activeQuery;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) MRSearchContentState state;
@property (nonatomic, assign) NSUInteger page;
@property (nonatomic, assign) BOOL canLoadMore;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL bannerVisible;
@property (nonatomic, assign) BOOL trendingRequested;
@property (nonatomic, assign) BOOL lastSignedIn;

@property (nonatomic, strong) NSTimer *debounceTimer;
@property (nonatomic, strong) id<MRHTTPTask> searchTask;
@property (nonatomic, strong) id<MRHTTPTask> trendingTask;
@property (nonatomic, strong) NSMutableDictionary *resultCache;

@end

@implementation MRSearchViewController

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                       preferences:(MRPreferencesStore *)preferences
                        imageCache:(MRImageCache *)imageCache {
    self = [super init];
    if (self) {
        _explicitAPIClient = apiClient;
        _explicitPreferences = preferences;
        _explicitImageCache = imageCache;
        _recentSearches = @[];
        _suggestions = @[];
        _results = @[];
        _resultCache = [NSMutableDictionary dictionary];
        _state = MRSearchContentStateIdle;
    }
    return self;
}

- (id)init {
    return [self initWithAPIClient:nil preferences:nil imageCache:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Search";
    self.view.backgroundColor = [MRAppearance groupBackground];

    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    searchBar.delegate = self;
    searchBar.placeholder = @"Movies, TV, anime";
    searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    searchBar.showsCancelButton = NO;
    [self.view addSubview:searchBar];
    self.searchBar = searchBar;

    MRBannerView *banner = [[MRBannerView alloc] initWithFrame:CGRectZero];
    banner.hidden = YES;
    [self.view addSubview:banner];
    self.bannerView = banner;

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                          style:UITableViewStylePlain];
    tableView.backgroundColor = [MRAppearance groupBackground];
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.dataSource = self;
    tableView.delegate = self;
    [self.view addSubview:tableView];
    self.tableView = tableView;

    MRPlaceholderView *connect =
        [[MRPlaceholderView alloc] initWithMessage:
            @"Connect Simkl to search movies, TV, and anime."
                                       actionTitle:@"Connect Simkl"];
    __weak MRSearchViewController *weakSelf = self;
    connect.actionHandler = ^{ [weakSelf showConnect]; };
    connect.hidden = YES;
    [self.view addSubview:connect];
    self.connectView = connect;

    [self buildFooter];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(authDidChange:)
                   name:MRAuthDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(preferencesDidChange:)
                   name:MRPreferencesDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(libraryDidChange:)
                   name:MRLibraryDidChangeNotification
                 object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_debounceTimer invalidate];
    [_searchTask cancel];
    [_trendingTask cancel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadForCurrentSession];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);

    if (![self isSignedIn]) {
        self.searchBar.hidden = YES;
        self.tableView.hidden = YES;
        self.bannerView.hidden = YES;
        CGFloat connectWidth = MIN(300.0, MAX(0.0, width - 32.0));
        self.connectView.frame = CGRectMake((width - connectWidth) / 2.0,
                                            (height - 160.0) / 2.0,
                                            connectWidth, 160.0);
        return;
    }

    CGFloat top = 0.0;
    self.searchBar.hidden = NO;
    self.tableView.hidden = NO;
    self.connectView.hidden = YES;
    self.searchBar.frame = CGRectMake(0.0, top, width, 44.0);
    top += 44.0;
    if (self.bannerVisible) {
        self.bannerView.frame = CGRectMake(0.0, top, width, [MRBannerView height]);
        top += [MRBannerView height];
    }
    self.tableView.frame = CGRectMake(0.0, top, width, MAX(0.0, height - top));
    [self layoutFooter];
}

#pragma mark - Dependencies

- (MRAPIClient *)apiClient {
    return self.environment.apiClient != nil ? self.environment.apiClient
                                             : self.explicitAPIClient;
}

- (MRPreferencesStore *)preferences {
    return self.environment.preferences != nil ? self.environment.preferences
                                               : self.explicitPreferences;
}

- (MRImageCache *)imageCache {
    return self.environment.imageCache != nil ? self.environment.imageCache
                                              : self.explicitImageCache;
}

- (MRSimklAuth *)auth {
    return self.environment.auth;
}

- (BOOL)isSignedIn {
    MRSimklAuth *auth = self.auth;
    if (auth != nil) {
        return auth.isSignedIn;
    }
    return self.preferences != nil;
}

#pragma mark - Session state

- (void)reloadForCurrentSession {
    BOOL signedIn = [self isSignedIn];
    if (!signedIn) {
        [self cancelPendingWork];
        self.state = MRSearchContentStateSignedOut;
        self.lastSignedIn = NO;
        self.connectView.hidden = NO;
        [self hideBanner];
        [self.tableView reloadData];
        [self.view setNeedsLayout];
        return;
    }

    self.searchBar.hidden = NO;
    self.tableView.hidden = NO;
    self.connectView.hidden = YES;
    if (!self.lastSignedIn) {
        self.lastSignedIn = YES;
        self.searchBar.text = @"";
        self.results = @[];
        self.suggestions = @[];
        self.trendingRequested = NO;
    }

    self.recentSearches = [self currentRecentSearches];
    if (self.searchBar.text.length == 0 ||
        ![MRSearchPagination shouldSearchForQuery:self.searchBar.text]) {
        [self showIdleState];
    }
    [self.view setNeedsLayout];
}

- (NSArray *)currentRecentSearches {
    NSArray *history = self.preferences.searchHistory;
    return [history isKindOfClass:[NSArray class]] ? history : @[];
}

- (void)showIdleState {
    self.state = MRSearchContentStateIdle;
    self.activeQuery = nil;
    self.results = @[];
    self.page = 0;
    self.canLoadMore = NO;
    self.loadingMore = NO;
    self.errorMessage = nil;
    self.recentSearches = [self currentRecentSearches];
    [self hideBanner];
    [self.tableView reloadData];
    [self.view setNeedsLayout];
    if (self.recentSearches.count == 0) {
        [self fetchTrendingSuggestionsIfNeeded];
    }
}

- (void)cancelPendingWork {
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    [self.searchTask cancel];
    self.searchTask = nil;
    self.loadingMore = NO;
}

#pragma mark - Search requests

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    [self.searchTask cancel];
    self.searchTask = nil;
    self.loadingMore = NO;
    [self hideBanner];

    NSString *trimmed =
        [searchText stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (![MRSearchPagination shouldSearchForQuery:searchText]) {
        [self showIdleState];
        return;
    }

    self.activeQuery = trimmed;
    self.debounceTimer =
        [NSTimer scheduledTimerWithTimeInterval:MRSearchDebounceInterval
                                         target:self
                                       selector:@selector(debounceTimerFired:)
                                       userInfo:nil
                                        repeats:NO];
}

- (void)debounceTimerFired:(NSTimer *)timer {
    self.debounceTimer = nil;
    NSString *query =
        [self.searchBar.text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![MRSearchPagination shouldSearchForQuery:query]) {
        [self showIdleState];
        return;
    }
    self.activeQuery = query;
    [self performSearchForQuery:query page:1 append:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;

    NSString *query =
        [searchBar.text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![MRSearchPagination shouldSearchForQuery:query]) {
        return;
    }
    self.activeQuery = query;
    [self performSearchForQuery:query page:1 append:NO];
}

- (void)performSearchForQuery:(NSString *)query page:(NSUInteger)page append:(BOOL)append {
    if (query.length == 0 || page < 1) {
        return;
    }

    NSDictionary *cached = [self cachedPage:page forQuery:query];
    if (cached != nil) {
        [self applySearchItems:[cached objectForKey:@"items"]
                        query:query
                         page:page
                   append:append
                    rawCount:[[cached objectForKey:@"rawCount"] unsignedIntegerValue]];
        return;
    }

    MRAPIClient *client = self.apiClient;
    if (client == nil) {
        [self showError:[MRError errorWithKind:MRErrorKindUnknown]
                  query:query
                 append:append];
        return;
    }

    [self.searchTask cancel];
    self.searchTask = nil;

    if (append) {
        self.loadingMore = YES;
        [self.tableView reloadData];
    } else {
        self.state = MRSearchContentStateSearching;
        self.results = @[];
        self.page = 0;
        self.canLoadMore = NO;
        self.errorMessage = nil;
        [self.tableView reloadData];
    }

    __weak MRSearchViewController *weakSelf = self;
    self.searchTask = [client searchAllWithQuery:query
                                            page:page
                                      completion:^(NSArray *json, NSError *error) {
        MRSearchViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (![strongSelf.activeQuery isEqualToString:query]) {
            return;
        }
        if (error != nil) {
            strongSelf.loadingMore = NO;
            if ([MRError kindForError:error] == MRErrorKindCancelled) {
                return;
            }
            [strongSelf showError:error query:query append:append];
            return;
        }

        NSUInteger rawCount = [json isKindOfClass:[NSArray class]] ? json.count : 0;
        NSArray *items = [strongSelf itemsFromSearchJSON:json];
        [strongSelf cachePage:page
                      forQuery:query
                        items:items
                     rawCount:rawCount];
        [strongSelf applySearchItems:items
                              query:query
                               page:page
                             append:append
                           rawCount:rawCount];
    }];
}

- (NSArray *)itemsFromSearchJSON:(NSArray *)json {
    if (![json isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id entry in (NSArray *)json) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        MRMediaItem *item = [MRMediaItem itemWithSearchDictionary:(NSDictionary *)entry];
        if (item.simklID <= 0 || [seen containsObject:[item identifier]]) {
            continue;
        }
        [seen addObject:[item identifier]];
        [items addObject:item];
    }
    return items;
}

- (void)applySearchItems:(NSArray *)items
                    query:(NSString *)query
                     page:(NSUInteger)page
                   append:(BOOL)append
                 rawCount:(NSUInteger)rawCount {
    NSMutableArray *combined = append
        ? [self.results mutableCopy] : [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (MRMediaItem *item in combined) {
        [seen addObject:[item identifier]];
    }
    for (MRMediaItem *item in items) {
        if ([seen containsObject:[item identifier]]) {
            continue;
        }
        [seen addObject:[item identifier]];
        [combined addObject:item];
    }

    self.results = combined;
    self.page = page;
    self.canLoadMore = [MRSearchPagination canLoadMoreForPage:page
                                                 resultCount:rawCount];
    self.loadingMore = NO;
    self.errorMessage = nil;
    self.state = combined.count > 0 ? MRSearchContentStateResults
                                    : MRSearchContentStateNoMatches;
    [self hideBanner];
    [self recordSearch:query];
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)showError:(NSError *)error query:(NSString *)query append:(BOOL)append {
    MRErrorKind kind = [MRError kindForError:error];
    NSString *message = kind == MRErrorKindOffline
        ? @"Search needs a connection."
        : [MRError messageForKind:kind];
    self.errorMessage = message;
    self.loadingMore = NO;

    if (append && self.results.count > 0) {
        [self showBannerMessage:@"Couldn't load more. Tap Retry." style:MRBannerStyleWarning];
    } else {
        self.state = MRSearchContentStateError;
        self.results = @[];
        self.page = 0;
        self.canLoadMore = NO;
        [self showBannerMessage:message style:MRBannerStyleError];
    }

    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)loadMore {
    if (self.loadingMore || !self.canLoadMore || self.state != MRSearchContentStateResults) {
        return;
    }
    NSUInteger next = [MRSearchPagination nextPageForPage:self.page];
    if (next <= self.page) {
        self.canLoadMore = NO;
        [self.tableView reloadData];
        return;
    }
    [self performSearchForQuery:self.activeQuery page:next append:YES];
}

- (void)retryActiveSearch {
    if (![MRSearchPagination shouldSearchForQuery:self.activeQuery]) {
        [self showIdleState];
        return;
    }
    [self performSearchForQuery:self.activeQuery page:1 append:NO];
}

- (void)recordSearch:(NSString *)query {
    MRPreferencesStore *preferences = self.preferences;
    if (preferences == nil || query.length == 0) {
        return;
    }
    [preferences recordSearch:query error:NULL];
}

#pragma mark - Result cache

- (NSString *)cacheKeyForQuery:(NSString *)query page:(NSUInteger)page {
    return [NSString stringWithFormat:@"%lu|%@",
            (unsigned long)page, [query lowercaseString]];
}

- (NSDictionary *)cachedPage:(NSUInteger)page forQuery:(NSString *)query {
    NSString *key = [self cacheKeyForQuery:query page:page];
    NSDictionary *entry = [self.resultCache objectForKey:key];
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDate *fetchedAt = [entry objectForKey:@"fetchedAt"];
    if (![fetchedAt isKindOfClass:[NSDate class]] ||
        -[fetchedAt timeIntervalSinceNow] > MRSearchCacheMaxAge) {
        [self.resultCache removeObjectForKey:key];
        return nil;
    }
    return entry;
}

- (void)cachePage:(NSUInteger)page
         forQuery:(NSString *)query
            items:(NSArray *)items
         rawCount:(NSUInteger)rawCount {
    if (query.length == 0 || page < 1) {
        return;
    }
    NSString *key = [self cacheKeyForQuery:query page:page];
    [self.resultCache setObject:@{
        @"items": items != nil ? items : @[],
        @"rawCount": @(rawCount),
        @"fetchedAt": [NSDate date]
    } forKey:key];
}

#pragma mark - Trending suggestions

- (void)fetchTrendingSuggestionsIfNeeded {
    if (self.trendingRequested || ![self isSignedIn]) {
        return;
    }
    MRAPIClient *client = self.apiClient;
    if (client == nil) {
        return;
    }

    self.trendingRequested = YES;
    __weak MRSearchViewController *weakSelf = self;
    self.trendingTask = [client fetchTrendingWeekWithCompletion:
        ^(NSDictionary *json, NSError *error) {
        MRSearchViewController *strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) {
            return;
        }
        NSArray *suggestions = [strongSelf suggestionsFromTrending:json];
        strongSelf.suggestions = suggestions;
        if (strongSelf.state == MRSearchContentStateIdle) {
            [strongSelf.tableView reloadData];
        }
    }];
}

- (NSArray *)suggestionsFromTrending:(NSDictionary *)trending {
    if (![trending isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSArray *keys = @[ @"movies", @"tv", @"anime" ];
    NSArray *types = @[ @(MRMediaTypeMovie), @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
    NSMutableArray *suggestions = [NSMutableArray array];
    for (NSUInteger index = 0; index < keys.count; index++) {
        id list = [(NSDictionary *)trending objectForKey:[keys objectAtIndex:index]];
        if (![list isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id entry in (NSArray *)list) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            MRMediaType type = (MRMediaType)[[types objectAtIndex:index] integerValue];
            MRMediaItem *item = [MRMediaItem itemWithTrendingDictionary:entry type:type];
            if (item.simklID <= 0 || item.title.length == 0) {
                continue;
            }
            [suggestions addObject:item];
            break;
        }
        if (suggestions.count >= MRSearchSuggestionLimit) {
            break;
        }
    }
    return suggestions;
}

#pragma mark - Banner and navigation

- (void)showBannerMessage:(NSString *)message style:(MRBannerStyle)style {
    self.bannerVisible = YES;
    __weak MRSearchViewController *weakSelf = self;
    self.bannerView.retryHandler = ^{ [weakSelf retryActiveSearch]; };
    [self.bannerView showMessage:message style:style retryTitle:@"Retry"];
    [self.view setNeedsLayout];
}

- (void)hideBanner {
    self.bannerVisible = NO;
    [self.bannerView hide];
    [self.view setNeedsLayout];
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

- (void)openItem:(MRMediaItem *)item {
    if (item == nil) {
        return;
    }

    MRAppEnvironment *environment = self.environment;
    MRDetailViewController *detail = nil;
    if (environment.libraryStore != nil) {
        detail = [[MRDetailViewController alloc] initWithItem:item
                                                   apiClient:self.apiClient
                                                libraryStore:environment.libraryStore
                                                  imageCache:self.imageCache
                                                      outbox:environment.outbox
                                                writeService:environment.writeService
                                                 preferences:self.preferences];
    } else {
        detail = [[MRDetailViewController alloc] initWithItem:item
                                                   apiClient:self.apiClient
                                                libraryStore:nil
                                                  imageCache:self.imageCache];
    }
    [self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - Footer

- (void)buildFooter {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 48.0)];
    footer.backgroundColor = [UIColor clearColor];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor clearColor];
    button.titleLabel.font = [MRAppearance smallFont];
    [button setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
    [button setTitleColor:[MRAppearance muted] forState:UIControlStateHighlighted];
    [button setTitle:@"Search powered by Simkl" forState:UIControlStateNormal];
    [button addTarget:self
               action:@selector(simklFooterTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:button];
    self.footerButton = button;

    UIImageView *badge = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SimklBadge.png"]];
    badge.backgroundColor = [UIColor clearColor];
    badge.contentMode = UIViewContentModeScaleAspectFit;
    [footer addSubview:badge];
    self.footerBadge = badge;

    self.tableView.tableFooterView = footer;
}

- (void)layoutFooter {
    UIView *footer = self.tableView.tableFooterView;
    if (footer == nil) {
        return;
    }
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGRect footerFrame = footer.frame;
    if (CGRectGetWidth(footerFrame) != width) {
        footerFrame.size.width = width;
        footer.frame = footerFrame;
    }

    CGSize textSize = [@"Search powered by Simkl" sizeWithFont:self.footerButton.titleLabel.font];
    CGFloat badgeSide = 22.0;
    CGFloat gap = 6.0;
    CGFloat totalWidth = textSize.width + gap + badgeSide;
    CGFloat startX = MAX(0.0, (width - totalWidth) / 2.0);
    self.footerButton.frame = CGRectMake(startX, 13.0, textSize.width, 22.0);
    self.footerBadge.frame = CGRectMake(startX + textSize.width + gap, 13.0,
                                        badgeSide, badgeSide);
}

- (void)simklFooterTapped:(id)sender {
    NSURL *URL = [NSURL URLWithString:@"https://simkl.com"];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

#pragma mark - Notifications

- (void)authDidChange:(NSNotification *)notification {
    [self reloadForCurrentSession];
}

- (void)preferencesDidChange:(NSNotification *)notification {
    if (![self isSignedIn] || self.state != MRSearchContentStateIdle) {
        return;
    }
    self.recentSearches = [self currentRecentSearches];
    [self.tableView reloadData];
}

- (void)libraryDidChange:(NSNotification *)notification {
    // Account bootstrap publishes this once storage, preferences, and the
    // signed-in session are all available. It also covers a tab that appeared
    // before the asynchronous session restore finished.
    [self reloadForCurrentSession];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.state == MRSearchContentStateIdle && self.recentSearches.count == 0 &&
        self.suggestions.count > 0) {
        return 2;
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.state) {
        case MRSearchContentStateIdle:
            if (self.recentSearches.count > 0) {
                return (NSInteger)self.recentSearches.count;
            }
            if (section == 0) {
                return 1;
            }
            return (NSInteger)self.suggestions.count;
        case MRSearchContentStateResults:
            return (NSInteger)self.results.count + (self.canLoadMore ? 1 : 0);
        case MRSearchContentStateSearching:
        case MRSearchContentStateNoMatches:
        case MRSearchContentStateError:
            return 1;
        case MRSearchContentStateSignedOut:
            return 0;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.state == MRSearchContentStateIdle) {
        static NSString *identifier = @"MRSearchTextCell";
        MRSearchTextCell *cell = (MRSearchTextCell *)
            [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[MRSearchTextCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:identifier];
        }

        if (self.recentSearches.count > 0) {
            NSString *query = [self.recentSearches objectAtIndex:(NSUInteger)indexPath.row];
            [cell configureWithTitle:query subtitle:nil showsChevron:YES];
            return cell;
        }

        if (indexPath.section == 0) {
            [cell configureWithTitle:@"Try Dune, The Bear, or Frieren"
                            subtitle:@"Search your whole Simkl catalog."
                         showsChevron:NO];
            return cell;
        }

        MRMediaItem *suggestion =
            [self.suggestions objectAtIndex:(NSUInteger)indexPath.row];
        NSString *subtitle = [NSString stringWithFormat:@"%@ · Trending on Simkl",
                              MRMediaTypeDisplayName(suggestion.type)];
        [cell configureWithTitle:suggestion.title subtitle:subtitle showsChevron:YES];
        return cell;
    }

    if (self.state == MRSearchContentStateResults) {
        if ((NSUInteger)indexPath.row < self.results.count) {
            static NSString *identifier = @"MRSearchResultCell";
            MRSearchResultCell *cell = (MRSearchResultCell *)
                [tableView dequeueReusableCellWithIdentifier:identifier];
            if (cell == nil) {
                cell = [[MRSearchResultCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                 reuseIdentifier:identifier];
            }
            [cell configureWithItem:[self.results objectAtIndex:(NSUInteger)indexPath.row]
                         imageCache:self.imageCache];
            return cell;
        }

        static NSString *identifier = @"MRSearchLoadMoreCell";
        MRSearchLoadMoreCell *cell = (MRSearchLoadMoreCell *)
            [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[MRSearchLoadMoreCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:identifier];
        }
        [cell configureLoading:self.loadingMore];
        return cell;
    }

    static NSString *identifier = @"MRSearchStateCell";
    MRSearchStateCell *cell = (MRSearchStateCell *)
        [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[MRSearchStateCell alloc] initWithStyle:UITableViewCellStyleDefault
                                        reuseIdentifier:identifier];
    }

    if (self.state == MRSearchContentStateSearching) {
        [cell configureWithMessage:@"Searching Simkl…"
                      actionTitle:nil
                          loading:YES
                          handler:nil];
    } else if (self.state == MRSearchContentStateNoMatches) {
        [cell configureWithMessage:@"No matches\nCheck the spelling or try an alternate title."
                      actionTitle:nil
                          loading:NO
                          handler:nil];
    } else {
        __weak MRSearchViewController *weakSelf = self;
        [cell configureWithMessage:(self.errorMessage.length > 0
                                    ? self.errorMessage : @"Couldn't finish the search.")
                      actionTitle:@"Retry"
                          loading:NO
                          handler:^{ [weakSelf retryActiveSearch]; }];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (self.state) {
        case MRSearchContentStateResults:
            if ((NSUInteger)indexPath.row >= self.results.count) {
                return 48.0;
            }
            return MRSearchDeviceClass() == MRDeviceClassTablet ? 112.0 : 84.0;
        case MRSearchContentStateSearching:
        case MRSearchContentStateNoMatches:
        case MRSearchContentStateError:
            return 168.0;
        case MRSearchContentStateIdle:
            return MRSearchDeviceClass() == MRDeviceClassTablet ? 58.0 : 50.0;
        case MRSearchContentStateSignedOut:
            return 0.0;
    }
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self titleForSection:section].length > 0 ? 34.0 : 8.0;
}

- (NSString *)titleForSection:(NSInteger)section {
    if (self.state != MRSearchContentStateIdle) {
        return nil;
    }
    if (self.recentSearches.count > 0) {
        return @"Recent Searches";
    }
    if (section == 1 && self.suggestions.count > 0) {
        return @"Trending on Simkl";
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForSection:section];
    if (title.length == 0) {
        return nil;
    }
    return [MRAppearance groupSectionHeaderViewWithTitle:title];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.state == MRSearchContentStateResults) {
        if ((NSUInteger)indexPath.row < self.results.count) {
            [self openItem:[self.results objectAtIndex:(NSUInteger)indexPath.row]];
        } else {
            [self loadMore];
        }
    } else if (self.state == MRSearchContentStateIdle) {
        if (self.recentSearches.count > 0) {
            NSString *query =
                [self.recentSearches objectAtIndex:(NSUInteger)indexPath.row];
            [self searchForSuggestionQuery:query];
        } else if (indexPath.section == 1) {
            MRMediaItem *suggestion =
                [self.suggestions objectAtIndex:(NSUInteger)indexPath.row];
            [self searchForSuggestionQuery:suggestion.title];
        }
    } else if (self.state == MRSearchContentStateError) {
        [self retryActiveSearch];
    }
}

- (void)searchForSuggestionQuery:(NSString *)query {
    if (query.length == 0) {
        return;
    }
    [self.searchBar becomeFirstResponder];
    self.searchBar.text = query;
    [self.debounceTimer invalidate];
    self.debounceTimer = nil;
    [self.searchTask cancel];
    self.searchTask = nil;
    self.activeQuery = query;
    [self performSearchForQuery:query page:1 append:NO];
}

@end
