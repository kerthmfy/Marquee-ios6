//
//  MRLibraryViewController.m
//  Marquee
//

#import "MRLibraryViewController.h"

#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRBannerView.h"
#import "MRConnectViewController.h"
#import "MRDetailViewController.h"
#import "MRError.h"
#import "MRErrorPresenter.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryFilter.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPlaceholderView.h"
#import "MRPosterImageView.h"
#import "MRQuotaTracker.h"
#import "MRSimklAuth.h"
#import "MRStatusChipsView.h"
#import "MRStatusPillView.h"
#import "MRSyncEngine.h"

typedef NS_ENUM(NSInteger, MRLibraryContentState) {
    MRLibraryContentStateConnect = 0,
    MRLibraryContentStateLoading,
    MRLibraryContentStateSyncFailed,
    MRLibraryContentStateEmptyLibrary,
    MRLibraryContentStateEmptyFilter,
    MRLibraryContentStateRows
};

static const CGFloat MRLibraryStateRowHeight = 200.0;

static MRDeviceClass MRLibraryDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static CGFloat MRLibraryCardSideInset(MRDeviceClass device) {
    return device == MRDeviceClassTablet ? 16.0 : 8.0;
}

#pragma mark - Item cell

@interface MRLibraryItemCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) MRStatusPillView *pillView;
@property (nonatomic, strong) UILabel *ratingLabel;
@property (nonatomic, strong) UILabel *nextLabel;
@property (nonatomic, strong) UILabel *chevronLabel;

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache;
- (void)cancelLoading;
+ (CGFloat)heightForDeviceClass:(MRDeviceClass)device;

@end

@implementation MRLibraryItemCell

+ (CGFloat)heightForDeviceClass:(MRDeviceClass)device {
    return device == MRDeviceClassTablet ? 118.0 : 84.0;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.backgroundColor = [UIColor clearColor];
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

        _pillView = [[MRStatusPillView alloc] initWithFrame:CGRectZero];
        [_cardView addSubview:_pillView];

        _ratingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _ratingLabel.backgroundColor = [UIColor clearColor];
        _ratingLabel.font = [UIFont boldSystemFontOfSize:11.0];
        _ratingLabel.textColor = [MRAppearance starColor];
        [_cardView addSubview:_ratingLabel];

        _nextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nextLabel.backgroundColor = [UIColor clearColor];
        _nextLabel.font = [MRAppearance smallFont];
        _nextLabel.textColor = [MRAppearance muted];
        _nextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_nextLabel];

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

    [self.pillView setWatchStatus:item.watchStatus];

    if (item.userRating > 0) {
        self.ratingLabel.text = [NSString stringWithFormat:@"★ %ld", (long)item.userRating];
        self.ratingLabel.hidden = NO;
    } else {
        self.ratingLabel.text = @"";
        self.ratingLabel.hidden = YES;
    }

    NSString *next = nil;
    if (item.watchStatus == MRWatchStatusWatching) {
        next = [self nextEpisodeTextForItem:item];
    }
    self.nextLabel.text = next != nil ? next : @"";
    self.nextLabel.hidden = next == nil;

    [self setNeedsLayout];
}

- (NSString *)nextEpisodeTextForItem:(MRMediaItem *)item {
    if (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) {
        NSString *code = [NSString stringWithFormat:@"S%ldE%ld",
                          (long)item.nextEpisodeSeason,
                          (long)item.nextEpisodeNumber];
        if (item.nextEpisodeTitle.length > 0) {
            code = [code stringByAppendingFormat:@" · %@", item.nextEpisodeTitle];
        }
        return [@"Next: " stringByAppendingString:code];
    }
    if (item.nextToWatch.length > 0) {
        return [@"Next: " stringByAppendingString:item.nextToWatch];
    }
    return nil;
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

    MRDeviceClass device = MRLibraryDeviceClass();
    BOOL tablet = device == MRDeviceClassTablet;
    CGFloat side = MRLibraryCardSideInset(device);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);

    self.cardView.frame = CGRectMake(side, 4.0,
                                     width - side * 2.0,
                                     height - 8.0);
    CGFloat cardWidth = CGRectGetWidth(self.cardView.bounds);
    CGFloat cardHeight = CGRectGetHeight(self.cardView.bounds);

    CGFloat posterWidth = tablet ? 60.0 : 42.0;
    CGFloat posterHeight = tablet ? 90.0 : 62.0;
    CGFloat padding = tablet ? 10.0 : 8.0;
    self.posterView.frame = CGRectMake(padding, padding,
                                       posterWidth, posterHeight);

    self.titleLabel.font = tablet ? [UIFont boldSystemFontOfSize:17.0]
                                  : [MRAppearance cardTitleFont];
    self.metaLabel.font = tablet ? [UIFont systemFontOfSize:13.0]
                                 : [MRAppearance smallFont];
    self.nextLabel.font = tablet ? [UIFont systemFontOfSize:12.0]
                                 : [MRAppearance smallFont];

    CGFloat textX = padding + posterWidth + 10.0;
    CGFloat chevronWidth = 18.0;
    CGFloat textWidth = MAX(20.0, cardWidth - textX - chevronWidth - 10.0);

    if (tablet) {
        self.titleLabel.frame = CGRectMake(textX, 9.0, textWidth, 22.0);
        self.metaLabel.frame = CGRectMake(textX, 33.0, textWidth, 16.0);
    } else {
        self.titleLabel.frame = CGRectMake(textX, 5.0, textWidth, 18.0);
        self.metaLabel.frame = CGRectMake(textX, 22.0, textWidth, 14.0);
    }

    CGSize pillSize = [MRStatusPillView sizeForStatus:self.pillView.watchStatus];
    CGFloat pillY = tablet ? 57.0 : 40.0;
    self.pillView.frame = CGRectMake(textX, pillY, pillSize.width, pillSize.height);

    CGFloat ratingX = pillSize.width > 0.0 ? textX + pillSize.width + 8.0 : textX;
    self.ratingLabel.frame = CGRectMake(ratingX, pillY - 1.0,
                                        MAX(28.0, textWidth - ratingX + textX),
                                        pillSize.height + 2.0);

    CGFloat nextY = tablet ? 80.0 : 57.0;
    self.nextLabel.frame = CGRectMake(textX, nextY,
                                      MAX(20.0, textWidth), 16.0);

    self.chevronLabel.frame = CGRectMake(cardWidth - chevronWidth - 6.0,
                                        (cardHeight - 24.0) / 2.0,
                                        chevronWidth, 24.0);
}

@end

#pragma mark - State cell

@interface MRLibraryStateCell : UITableViewCell
@property (nonatomic, strong) MRPlaceholderView *cardView;
- (void)configureWithMessage:(NSString *)message
                 actionTitle:(NSString *)actionTitle
                     loading:(BOOL)loading
                     handler:(void (^)(void))handler;
@end

@implementation MRLibraryStateCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)configureWithMessage:(NSString *)message
                 actionTitle:(NSString *)actionTitle
                     loading:(BOOL)loading
                     handler:(void (^)(void))handler {
    [self.cardView removeFromSuperview];

    MRPlaceholderView *card =
        [[MRPlaceholderView alloc] initWithMessage:message actionTitle:actionTitle];
    card.actionHandler = handler;
    card.loading = loading;
    [self.contentView addSubview:card];
    self.cardView = card;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device = MRLibraryDeviceClass();
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat inset = MRLibraryCardSideInset(device);
    CGFloat cardWidth = MIN(width - inset * 2.0,
                            [MRLayout contentMaxWidthForDeviceClass:device]);
    self.cardView.frame = CGRectMake(floor((width - cardWidth) / 2.0), 16.0,
                                     cardWidth, 160.0);
}

@end

#pragma mark - Controller

@interface MRLibraryViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) MRAppEnvironment *environment;
@property (nonatomic, strong) MRLibraryStore *explicitLibraryStore;
@property (nonatomic, strong) MRImageCache *explicitImageCache;

@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) MRStatusChipsView *chipsView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *footerView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) UIView *syncTitleView;
@property (nonatomic, strong) UIActivityIndicatorView *syncSpinner;
@property (nonatomic, strong) MRBannerView *quotaBannerView;

@property (nonatomic, assign) MRMediaType selectedType;
@property (nonatomic, assign) MRWatchStatus selectedStatus;
@property (nonatomic, copy) NSArray *visibleItems;
@property (nonatomic, assign) MRLibraryContentState contentState;
@property (nonatomic, assign) NSInteger pendingCount;

@end

@implementation MRLibraryViewController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment {
    self = [super init];
    if (self) {
        _environment = environment;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithLibraryStore:(MRLibraryStore *)libraryStore
                          imageCache:(MRImageCache *)imageCache {
    self = [super init];
    if (self) {
        _explicitLibraryStore = libraryStore;
        _explicitImageCache = imageCache;
        [self commonInit];
    }
    return self;
}

- (id)init {
    return [self initWithEnvironment:nil];
}

- (void)commonInit {
    _selectedType = MRLibraryFilterAllTypes;
    _selectedStatus = MRWatchStatusNone;
    _visibleItems = @[];
    _contentState = MRLibraryContentStateConnect;
    _pendingCount = 0;
}

- (MRLibraryStore *)libraryStore {
    if (self.environment != nil) {
        return self.environment.libraryStore;
    }
    return self.explicitLibraryStore;
}

- (MRImageCache *)imageCache {
    if (self.environment != nil) {
        return self.environment.imageCache;
    }
    return self.explicitImageCache;
}

- (MRSyncEngine *)syncEngine {
    return self.environment.syncEngine;
}

- (BOOL)isSignedIn {
    if (self.environment != nil) {
        if (self.environment.auth != nil) {
            return self.environment.auth.isSignedIn;
        }
        return self.environment.libraryStore != nil;
    }
    return self.explicitLibraryStore != nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Library";
    self.view.backgroundColor = [MRAppearance groupBackground];

    UISegmentedControl *typeControl =
        [[UISegmentedControl alloc] initWithItems:@[ @"All", @"Movies", @"TV", @"Anime" ]];
    typeControl.segmentedControlStyle = UISegmentedControlStylePlain;
    typeControl.selectedSegmentIndex = 0;
    [typeControl addTarget:self
                    action:@selector(typeChanged:)
          forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:typeControl];
    self.typeControl = typeControl;

    MRStatusChipsView *chips = [[MRStatusChipsView alloc] initWithFrame:CGRectZero];
    __weak MRLibraryViewController *weakSelf = self;
    chips.selectionHandler = ^(MRWatchStatus status) {
        MRLibraryViewController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.selectedStatus == status) {
            return;
        }
        strongSelf.selectedStatus = status;
        [strongSelf reloadFromStore];
    };
    [self.view addSubview:chips];
    self.chipsView = chips;

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                          style:UITableViewStylePlain];
    tableView.backgroundColor = [MRAppearance groupBackground];
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:tableView];
    self.tableView = tableView;

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self
                action:@selector(refreshPulled:)
      forControlEvents:UIControlEventValueChanged];
    [tableView addSubview:refresh];
    self.refreshControl = refresh;

    MRBannerView *quotaBanner = [[MRBannerView alloc] initWithFrame:CGRectZero];
    self.quotaBannerView = quotaBanner;

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 44.0)];
    footer.backgroundColor = [UIColor clearColor];
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    footerLabel.backgroundColor = [UIColor clearColor];
    footerLabel.font = [MRAppearance smallFont];
    footerLabel.textColor = [MRAppearance muted];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [footer addSubview:footerLabel];
    self.footerView = footer;
    self.footerLabel = footerLabel;

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
               selector:@selector(quotaDidChange:)
                   name:MRQuotaDidChangeNotification
                 object:nil];

    [self updateQuotaBanner];
    [self reloadFromStore];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    if (width <= 0.0) {
        return;
    }

    [self layoutContentWidth:width height:height];
    [self layoutFooter];
    [self layoutQuotaBanner];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout

- (void)layoutContentWidth:(CGFloat)width height:(CGFloat)height {
    MRDeviceClass device = MRLibraryDeviceClass();
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat maxContent = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat x = (width - maxContent) / 2.0 + inset;
    CGFloat controlWidth = MAX(0.0, maxContent - inset * 2.0);

    BOOL filtersVisible = !self.typeControl.hidden;
    CGFloat top = 8.0;
    self.typeControl.frame = CGRectMake(x, top, controlWidth, 32.0);

    CGFloat chipsHeight = device == MRDeviceClassTablet ? 44.0 : 38.0;
    self.chipsView.frame = CGRectMake(x, top + 32.0 + 8.0, controlWidth, chipsHeight);

    CGFloat headerBottom = filtersVisible ? top + 32.0 + 8.0 + chipsHeight + 8.0 : 0.0;
    self.tableView.frame = CGRectMake(0.0, headerBottom, width,
                                      MAX(0.0, height - headerBottom));
}

- (void)layoutFooter {
    if (self.tableView.tableFooterView == nil) {
        return;
    }

    MRDeviceClass device = MRLibraryDeviceClass();
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    CGFloat maxContent = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGRect footerFrame = self.footerView.frame;
    footerFrame.size = CGSizeMake(width, 44.0);
    self.footerView.frame = footerFrame;
    self.footerLabel.frame = CGRectMake((width - maxContent) / 2.0 + inset, 12.0,
                                        MAX(0.0, maxContent - inset * 2.0), 20.0);
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

- (void)quotaDidChange:(NSNotification *)notification {
    [self updateQuotaBanner];
}

- (void)updateQuotaBanner {
    if (!self.isSignedIn) {
        [self hideQuotaBanner];
        return;
    }

    MRQuotaTracker *quota = self.environment.quotaTracker;
    NSError *syncError = self.syncEngine.lastSyncError;
    if (syncError != nil &&
        [MRError kindForError:syncError] == MRErrorKindCancelled) {
        syncError = nil;
    }

    NSString *message = nil;
    MRBannerStyle style = MRBannerStyleWarning;
    NSString *retryTitle = nil;
    if (quota != nil && quota.remaining == 0) {
        message = [self quotaLimitMessage];
        style = MRBannerStyleError;
    } else if (syncError != nil) {
        message = [MRErrorPresenter messageForError:syncError
                                          resetDate:quota.resetAt];
        style = [MRErrorPresenter styleForError:syncError];
        if ([MRErrorPresenter showsRetryForError:syncError]) {
            retryTitle = @"Retry";
        }
    }
    if (message.length == 0) {
        [self hideQuotaBanner];
        return;
    }

    __weak MRLibraryViewController *weakSelf = self;
    self.quotaBannerView.retryHandler = ^{
        [weakSelf refreshPulled:weakSelf.refreshControl];
    };
    [self.quotaBannerView showMessage:message
                                style:style
                           retryTitle:retryTitle];
    [self layoutQuotaBanner];
    self.tableView.tableHeaderView = self.quotaBannerView;
}

- (void)hideQuotaBanner {
    [self.quotaBannerView hide];
    if (self.tableView.tableHeaderView == self.quotaBannerView) {
        self.tableView.tableHeaderView = nil;
    }
}

- (void)layoutQuotaBanner {
    if (self.tableView.tableHeaderView != self.quotaBannerView) {
        return;
    }
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    self.quotaBannerView.frame = CGRectMake(0.0, 0.0, width,
                                            [MRBannerView height]);
    self.tableView.tableHeaderView = self.quotaBannerView;
}

#pragma mark - Store and filters

- (void)authDidChange:(NSNotification *)notification {
    [self reloadFromStore];
}

- (void)libraryDidChange:(NSNotification *)notification {
    [self reloadFromStore];
}

- (void)syncStatusDidChange:(NSNotification *)notification {
    if (!self.syncEngine.isSyncing && self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
    [self reloadFromStore];
}

- (void)typeChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 1:
            self.selectedType = MRMediaTypeMovie;
            break;
        case 2:
            self.selectedType = MRMediaTypeShow;
            break;
        case 3:
            self.selectedType = MRMediaTypeAnime;
            break;
        case 0:
        default:
            self.selectedType = MRLibraryFilterAllTypes;
            break;
    }
    [self reloadFromStore];
}

- (void)reloadFromStore {
    MRLibraryStore *store = self.libraryStore;

    if (!self.isSignedIn) {
        self.contentState = MRLibraryContentStateConnect;
        self.visibleItems = @[];
    } else if (store == nil) {
        self.contentState = MRLibraryContentStateLoading;
        self.visibleItems = @[];
    } else {
        if (self.selectedType == MRMediaTypeMovie &&
            (self.selectedStatus == MRWatchStatusWatching ||
             self.selectedStatus == MRWatchStatusHold)) {
            self.selectedStatus = MRWatchStatusNone;
        }

        NSArray *filtered = [MRLibraryFilter items:store.items
                                             type:self.selectedType
                                           status:self.selectedStatus];
        self.visibleItems = [MRLibraryFilter sortedItems:filtered];

        NSError *syncError = self.syncEngine.lastSyncError;
        BOOL syncFailed = (syncError != nil &&
                           [MRError kindForError:syncError] != MRErrorKindCancelled);
        if (store.items.count == 0 && store.lastFullSyncAt == nil &&
            self.syncEngine.isSyncing) {
            self.contentState = MRLibraryContentStateLoading;
        } else if (store.items.count == 0 && store.lastFullSyncAt == nil && syncFailed) {
            self.contentState = MRLibraryContentStateSyncFailed;
        } else if (store.items.count == 0) {
            self.contentState = MRLibraryContentStateEmptyLibrary;
        } else if (self.visibleItems.count == 0) {
            self.contentState = MRLibraryContentStateEmptyFilter;
        } else {
            self.contentState = MRLibraryContentStateRows;
        }
    }

    [self updateFilterControlsWithStore:store];
    [self updateFooter];
    [self updateSyncIndicator];
    [self updateQuotaBanner];
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)updateFilterControlsWithStore:(MRLibraryStore *)store {
    switch (self.selectedType) {
        case MRMediaTypeMovie:
            self.typeControl.selectedSegmentIndex = 1;
            break;
        case MRMediaTypeShow:
            self.typeControl.selectedSegmentIndex = 2;
            break;
        case MRMediaTypeAnime:
            self.typeControl.selectedSegmentIndex = 3;
            break;
        default:
            self.typeControl.selectedSegmentIndex = 0;
            break;
    }

    BOOL filtersVisible = (self.contentState == MRLibraryContentStateRows ||
                           self.contentState == MRLibraryContentStateEmptyFilter);
    self.typeControl.hidden = !filtersVisible;
    self.chipsView.hidden = !filtersVisible;

    if (!filtersVisible || store == nil) {
        return;
    }

    NSInteger total = (NSInteger)[MRLibraryFilter items:store.items
                                                   type:self.selectedType
                                                 status:MRWatchStatusNone].count;
    MRWatchStatus effective =
        [self.chipsView configureWithCounts:[self countsForType:self.selectedType
                                                          store:store]
                                      total:total
                                    forType:self.selectedType];
    if (effective != self.selectedStatus) {
        self.selectedStatus = effective;
    }
}

- (NSDictionary *)countsForType:(MRMediaType)type store:(MRLibraryStore *)store {
    if (type != MRLibraryFilterAllTypes) {
        return [store countsByStatusForType:type];
    }

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSArray *types = @[ @(MRMediaTypeMovie), @(MRMediaTypeShow), @(MRMediaTypeAnime) ];
    for (NSNumber *typeNumber in types) {
        NSDictionary *part =
            [store countsByStatusForType:(MRMediaType)[typeNumber integerValue]];
        for (NSString *key in part) {
            NSInteger current = [[counts objectForKey:key] integerValue];
            [counts setObject:@(current + [[part objectForKey:key] integerValue])
                       forKey:key];
        }
    }
    return counts;
}

#pragma mark - Refresh

- (void)refreshPulled:(UIRefreshControl *)sender {
    MRSyncEngine *engine = self.syncEngine;
    if (engine == nil || !self.isSignedIn) {
        [sender endRefreshing];
        return;
    }

    __weak MRLibraryViewController *weakSelf = self;
    [engine syncWithCompletion:^(NSError *error) {
        MRLibraryViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf.refreshControl endRefreshing];
        [strongSelf reloadFromStore];
    }];
    [self updateSyncIndicator];
    [self updateFooter];
}

#pragma mark - Sync chrome

- (void)ensureSyncTitleView {
    if (self.syncTitleView != nil) {
        return;
    }

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 108.0, 24.0)];
    container.backgroundColor = [UIColor clearColor];

    UIActivityIndicatorView *spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
            UIActivityIndicatorViewStyleWhite];
    spinner.frame = CGRectMake(0.0, 2.0, 20.0, 20.0);
    spinner.hidesWhenStopped = YES;
    [container addSubview:spinner];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24.0, 2.0, 84.0, 20.0)];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:14.0];
    label.textColor = [UIColor whiteColor];
    label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    label.shadowOffset = CGSizeMake(0.0, -1.0);
    label.text = @"Syncing…";
    [container addSubview:label];

    self.syncTitleView = container;
    self.syncSpinner = spinner;
}

- (void)updateSyncIndicator {
    if (self.syncEngine.isSyncing) {
        [self ensureSyncTitleView];
        [self.syncSpinner startAnimating];
        self.navigationItem.titleView = self.syncTitleView;
    } else {
        [self.syncSpinner stopAnimating];
        self.navigationItem.titleView = nil;
        self.title = @"Library";
    }
}

#pragma mark - Footer

- (void)setPendingCount:(NSInteger)pendingCount {
    _pendingCount = MAX(0, pendingCount);
    [self updateFooter];
}

- (void)updateFooter {
    MRLibraryStore *store = self.libraryStore;
    if (!self.isSignedIn || store == nil) {
        self.footerLabel.text = @"";
        self.tableView.tableFooterView = nil;
        return;
    }

    self.tableView.tableFooterView = self.footerView;

    NSString *text = nil;
    UIColor *color = [MRAppearance muted];
    MRSyncEngine *engine = self.syncEngine;

    if (self.pendingCount > 0) {
        text = self.pendingCount == 1
            ? @"1 change waiting to sync"
            : [NSString stringWithFormat:@"%ld changes waiting to sync",
               (long)self.pendingCount];
        color = [MRAppearance link];
    } else if (engine.lastSyncError != nil &&
               [MRError kindForError:engine.lastSyncError] != MRErrorKindCancelled) {
        text = @"Offline — showing saved library";
        color = [MRAppearance holdColor];
    } else {
        NSDate *date = engine.lastSyncAt != nil ? engine.lastSyncAt : store.lastSyncAt;
        if (date != nil) {
            text = [self syncedTextForDate:date];
        } else {
            text = @"Waiting for first sync";
        }
    }

    self.footerLabel.text = text;
    self.footerLabel.textColor = color;
    [self layoutFooter];
}

- (NSString *)syncedTextForDate:(NSDate *)date {
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:date];
    if (interval < 0.0) {
        interval = 0.0;
    }
    if (interval < 60.0) {
        return @"Synced just now";
    }
    if (interval < 3600.0) {
        return [NSString stringWithFormat:@"Synced %ldm ago",
                (long)(interval / 60.0)];
    }
    if (interval < 86400.0) {
        return [NSString stringWithFormat:@"Synced %ldh ago",
                (long)(interval / 3600.0)];
    }
    if (interval < 7.0 * 86400.0) {
        return [NSString stringWithFormat:@"Synced %ldd ago",
                (long)(interval / 86400.0)];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d"];
    return [NSString stringWithFormat:@"Synced %@", [formatter stringFromDate:date]];
}

#pragma mark - State actions

- (void)presentConnect {
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

- (void)switchToSearch {
    UITabBarController *tabs = self.tabBarController;
    if (tabs != nil && tabs.viewControllers.count > 2) {
        tabs.selectedIndex = 2;
    }
}

#pragma mark - Table states

- (NSString *)stateMessage {
    switch (self.contentState) {
        case MRLibraryContentStateConnect:
            return @"Sign in to Simkl to build your library.";
        case MRLibraryContentStateLoading:
            return @"Loading your library…";
        case MRLibraryContentStateSyncFailed:
            return @"Couldn't load your library. Check your connection and try again.";
        case MRLibraryContentStateEmptyLibrary:
            return @"Your Simkl library is empty. Search for a movie, show, or anime to start tracking it.";
        case MRLibraryContentStateEmptyFilter: {
            NSString *noun = @"items";
            if (self.selectedType == MRMediaTypeMovie) {
                noun = @"movies";
            } else if (self.selectedType == MRMediaTypeShow) {
                noun = @"TV shows";
            } else if (self.selectedType == MRMediaTypeAnime) {
                noun = @"anime";
            }
            if (self.selectedStatus == MRWatchStatusNone) {
                return [NSString stringWithFormat:@"No %@ in your library.", noun];
            }
            return [NSString stringWithFormat:@"No %@ marked %@ in your library.",
                    noun, MRWatchStatusDisplayName(self.selectedStatus)];
        }
        case MRLibraryContentStateRows:
        default:
            return @"";
    }
}

- (NSString *)stateActionTitle {
    if (self.contentState == MRLibraryContentStateConnect) {
        return @"Sign In";
    }
    if (self.contentState == MRLibraryContentStateSyncFailed) {
        return @"Retry";
    }
    if (self.contentState == MRLibraryContentStateEmptyLibrary ||
        self.contentState == MRLibraryContentStateEmptyFilter) {
        return @"Search";
    }
    return nil;
}

- (void)handleStateAction {
    if (self.contentState == MRLibraryContentStateConnect) {
        [self presentConnect];
    } else if (self.contentState == MRLibraryContentStateSyncFailed) {
        [self retrySync];
    } else {
        [self switchToSearch];
    }
}

- (void)retrySync {
    MRSyncEngine *engine = self.syncEngine;
    if (engine == nil || self.libraryStore == nil) {
        return;
    }

    __weak MRLibraryViewController *weakSelf = self;
    [engine syncWithCompletion:^(NSError *error) {
        MRLibraryViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf reloadFromStore];
        }
    }];
    [self updateSyncIndicator];
    [self updateFooter];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.contentState == MRLibraryContentStateRows) {
        return (NSInteger)self.visibleItems.count;
    }
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.contentState == MRLibraryContentStateRows &&
        (NSUInteger)indexPath.row < self.visibleItems.count) {
        static NSString *itemIdentifier = @"MRLibraryItemCell";
        MRLibraryItemCell *cell = (MRLibraryItemCell *)
            [tableView dequeueReusableCellWithIdentifier:itemIdentifier];
        if (cell == nil) {
            cell = [[MRLibraryItemCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:itemIdentifier];
        }
        MRMediaItem *item = [self.visibleItems objectAtIndex:(NSUInteger)indexPath.row];
        [cell configureWithItem:item imageCache:self.imageCache];
        return cell;
    }

    static NSString *stateIdentifier = @"MRLibraryStateCell";
    MRLibraryStateCell *cell = (MRLibraryStateCell *)
        [tableView dequeueReusableCellWithIdentifier:stateIdentifier];
    if (cell == nil) {
        cell = [[MRLibraryStateCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:stateIdentifier];
    }

    __weak MRLibraryViewController *weakSelf = self;
    [cell configureWithMessage:[self stateMessage]
                   actionTitle:[self stateActionTitle]
                       loading:self.contentState == MRLibraryContentStateLoading
                       handler:^{
        MRLibraryViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf handleStateAction];
        }
    }];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.contentState == MRLibraryContentStateRows) {
        return [MRLibraryItemCell heightForDeviceClass:MRLibraryDeviceClass()];
    }
    return MRLibraryStateRowHeight;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.contentState != MRLibraryContentStateRows ||
        (NSUInteger)indexPath.row >= self.visibleItems.count ||
        self.navigationController == nil) {
        return;
    }

    MRMediaItem *item = [self.visibleItems objectAtIndex:(NSUInteger)indexPath.row];
    MRDetailViewController *detail =
        [[MRDetailViewController alloc] initWithItem:item
                                           apiClient:self.environment.apiClient
                                        libraryStore:self.libraryStore
                                          imageCache:self.imageCache
                                              outbox:self.environment.outbox
                                        writeService:self.environment.writeService
                                         preferences:self.environment.preferences];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
