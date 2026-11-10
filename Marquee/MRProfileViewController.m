//
//  MRProfileViewController.m
//  Marquee
//

#import "MRProfileViewController.h"

#import "MRAPIClient.h"
#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRConnectViewController.h"
#import "MRGenrePickerViewController.h"
#import "MRHiddenTitlesViewController.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MRPlaceholderView.h"
#import "MRPreferencesStore.h"
#import "MRProfileStats.h"
#import "MRRecommendationDataProviding.h"
#import "MRRecommendationEngine.h"
#import "MRSimklAuth.h"
#import "MRStorage.h"
#import "MRSyncEngine.h"
#import "MRToastView.h"
#import "MRURLBuilder.h"
#import "MRUserProfile.h"

static NSString *const MRProfileConnectedAppsURL =
    @"https://simkl.com/settings/apps/";

static const NSInteger MRProfileAlertSignOut = 18001;
static const NSInteger MRProfileAlertRemoveData = 18002;
static const NSInteger MRProfileAlertReset = 18003;

typedef NS_ENUM(NSInteger, MRProfileSection) {
    MRProfileSectionHeader = 0,
    MRProfileSectionStats,
    MRProfileSectionSync,
    MRProfileSectionForYou,
    MRProfileSectionAbout,
    MRProfileSectionSignOut,
    MRProfileSectionRemoveData
};

static MRDeviceClass MRProfileDeviceClass(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
}

static CGFloat MRProfileSideInset(void) {
    return MRProfileDeviceClass() == MRDeviceClassTablet ? 16.0 : 8.0;
}

static NSString *MRProfileAccountTypeText(MRUserProfile *profile) {
    NSString *type = [[profile.accountType lowercaseString] copy];
    if ([type isEqualToString:@"pro"]) {
        return @"PRO account";
    }
    if ([type isEqualToString:@"vip"]) {
        return @"VIP account";
    }
    if ([type isEqualToString:@"free"]) {
        return @"Free account";
    }
    return type.length > 0 ? [type capitalizedString] : @"Simkl account";
}

static NSString *MRProfileInitials(NSString *name) {
    NSArray *parts = [name componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *initials = [NSMutableString string];
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        [initials appendString:[[part substringToIndex:1] uppercaseString]];
        if (initials.length == 2) {
            break;
        }
    }
    if (initials.length == 0) {
        return @"S";
    }
    return initials;
}

static NSString *MRProfileJoinedText(NSDate *date) {
    if (date == nil) {
        return nil;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM yyyy"];
    return [NSString stringWithFormat:@"Joined %@", [formatter stringFromDate:date]];
}

static NSString *MRProfileVersionText(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [info objectForKey:@"CFBundleShortVersionString"];
    NSString *build = [info objectForKey:@"CFBundleVersion"];
    if (version.length == 0) {
        version = @"1.0";
    }
    if (build.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", version, build];
    }
    return version;
}

#pragma mark - Header cell

@interface MRProfileHeaderCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *avatarBackground;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *initialsLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *accountLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *bioLabel;

@property (nonatomic, strong) UILabel *connectTitleLabel;
@property (nonatomic, strong) UILabel *connectSubtitleLabel;
@property (nonatomic, strong) UIButton *connectButton;

@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) id avatarToken;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) void (^connectHandler)(void);

+ (CGFloat)heightForProfile:(MRUserProfile *)profile signedIn:(BOOL)signedIn;

- (void)configureSignedInWithProfile:(MRUserProfile *)profile
                          imageCache:(MRImageCache *)imageCache;
- (void)configureSignedOut;
- (void)cancelAvatarLoad;

@end

@implementation MRProfileHeaderCell

+ (CGFloat)heightForProfile:(MRUserProfile *)profile signedIn:(BOOL)signedIn {
    if (!signedIn) {
        return 140.0;
    }
    BOOL hasBio = profile.bio.length > 0;
    return hasBio ? 124.0 : 92.0;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_cardView first:YES last:YES];
        [self.contentView addSubview:_cardView];

        _avatarBackground = [[UIView alloc] initWithFrame:CGRectZero];
        _avatarBackground.backgroundColor = [MRAppearance link];
        _avatarBackground.layer.cornerRadius = 28.0;
        _avatarBackground.layer.masksToBounds = YES;
        [_cardView addSubview:_avatarBackground];

        _avatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.clipsToBounds = YES;
        _avatarView.layer.cornerRadius = 28.0;
        [_avatarBackground addSubview:_avatarView];

        _initialsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _initialsLabel.backgroundColor = [UIColor clearColor];
        _initialsLabel.font = [UIFont boldSystemFontOfSize:22.0];
        _initialsLabel.textColor = [UIColor whiteColor];
        _initialsLabel.textAlignment = NSTextAlignmentCenter;
        [_avatarBackground addSubview:_initialsLabel];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:18.0];
        _nameLabel.textColor = [MRAppearance ink];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_nameLabel];

        _accountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _accountLabel.backgroundColor = [UIColor clearColor];
        _accountLabel.font = [MRAppearance bodyFont];
        _accountLabel.textColor = [MRAppearance muted];
        _accountLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_accountLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = [MRAppearance smallFont];
        _detailLabel.textColor = [MRAppearance muted];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_detailLabel];

        _bioLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bioLabel.backgroundColor = [UIColor clearColor];
        _bioLabel.font = [MRAppearance bodyFont];
        _bioLabel.textColor = [MRAppearance ink];
        _bioLabel.numberOfLines = 2;
        _bioLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_bioLabel];

        _connectTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _connectTitleLabel.backgroundColor = [UIColor clearColor];
        _connectTitleLabel.font = [UIFont boldSystemFontOfSize:18.0];
        _connectTitleLabel.textColor = [MRAppearance ink];
        _connectTitleLabel.text = @"Connect Simkl";
        [_cardView addSubview:_connectTitleLabel];

        _connectSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _connectSubtitleLabel.backgroundColor = [UIColor clearColor];
        _connectSubtitleLabel.font = [MRAppearance bodyFont];
        _connectSubtitleLabel.textColor = [MRAppearance muted];
        _connectSubtitleLabel.numberOfLines = 2;
        _connectSubtitleLabel.text = @"Track what you watch and get a personalized For You feed.";
        [_cardView addSubview:_connectSubtitleLabel];

        _connectButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_connectButton setBackgroundImage:[MRAppearance actionButtonImage]
                                  forState:UIControlStateNormal];
        [_connectButton setBackgroundImage:[MRAppearance actionButtonImage]
                                  forState:UIControlStateHighlighted];
        _connectButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [_connectButton setTitleColor:[UIColor whiteColor]
                             forState:UIControlStateNormal];
        [_connectButton setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                                   forState:UIControlStateNormal];
        _connectButton.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        [_connectButton setTitle:@"Connect Simkl" forState:UIControlStateNormal];
        [_connectButton addTarget:self
                           action:@selector(connectTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_connectButton];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self cancelAvatarLoad];
}

- (void)dealloc {
    [self cancelAvatarLoad];
}

- (void)cancelAvatarLoad {
    if (self.avatarToken != nil) {
        [self.imageCache cancelLoad:self.avatarToken];
        self.avatarToken = nil;
    }
    self.avatarURL = nil;
}

- (void)setSignedInViewsHidden:(BOOL)hidden {
    self.avatarBackground.hidden = hidden;
    self.nameLabel.hidden = hidden;
    self.accountLabel.hidden = hidden;
    self.detailLabel.hidden = hidden;
    self.bioLabel.hidden = hidden;
    self.connectTitleLabel.hidden = !hidden;
    self.connectSubtitleLabel.hidden = !hidden;
    self.connectButton.hidden = !hidden;
}

- (void)configureSignedInWithProfile:(MRUserProfile *)profile
                          imageCache:(MRImageCache *)imageCache {
    [self cancelAvatarLoad];
    self.imageCache = imageCache;
    [self setSignedInViewsHidden:NO];

    NSString *name = profile.name.length > 0 ? profile.name : @"Simkl User";
    self.nameLabel.text = name;
    self.initialsLabel.text = MRProfileInitials(name);
    self.initialsLabel.hidden = NO;
    self.avatarView.image = nil;

    self.accountLabel.text = MRProfileAccountTypeText(profile);

    NSString *joined = MRProfileJoinedText(profile.joinedAt);
    NSString *location = profile.location;
    if (joined.length > 0 && location.length > 0) {
        self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", joined, location];
    } else if (joined.length > 0) {
        self.detailLabel.text = joined;
    } else if (location.length > 0) {
        self.detailLabel.text = location;
    } else {
        self.detailLabel.text = @"";
    }

    self.bioLabel.text = profile.bio.length > 0 ? profile.bio : @"";
    self.bioLabel.hidden = profile.bio.length == 0;

    NSString *avatarURL = [MRURLBuilder avatarURLForPath:profile.avatarURL];
    if (avatarURL.length == 0 || imageCache == nil) {
        return;
    }

    self.avatarURL = avatarURL;
    UIImage *cached = [imageCache cachedImageForURL:avatarURL];
    if (cached != nil) {
        self.avatarView.image = cached;
        self.initialsLabel.hidden = YES;
        return;
    }

    __weak MRProfileHeaderCell *weakSelf = self;
    self.avatarToken = [imageCache loadImageForURL:avatarURL
                                        completion:^(UIImage *image, NSError *error) {
        MRProfileHeaderCell *strongSelf = weakSelf;
        if (strongSelf == nil ||
            ![strongSelf.avatarURL isEqualToString:avatarURL] ||
            image == nil) {
            return;
        }
        strongSelf.avatarView.image = image;
        strongSelf.initialsLabel.hidden = YES;
    }];
}

- (void)configureSignedOut {
    [self cancelAvatarLoad];
    [self setSignedInViewsHidden:YES];
    self.connectButton.hidden = NO;
}

- (void)connectTapped:(id)sender {
    if (self.connectHandler != nil) {
        self.connectHandler();
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat inset = MRProfileSideInset();
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:MRProfileDeviceClass()]);
    CGFloat cardX = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    CGFloat cardHeight = MAX(0.0, CGRectGetHeight(self.bounds) - 8.0);
    self.cardView.frame = CGRectMake(cardX, 4.0, cardWidth, cardHeight);

    self.avatarBackground.frame = CGRectMake(16.0, 16.0, 56.0, 56.0);
    self.avatarView.frame = self.avatarBackground.bounds;
    self.initialsLabel.frame = self.avatarBackground.bounds;

    CGFloat textX = 84.0;
    CGFloat textWidth = MAX(0.0, cardWidth - textX - 16.0);
    self.nameLabel.frame = CGRectMake(textX, 13.0, textWidth, 23.0);
    self.accountLabel.frame = CGRectMake(textX, 35.0, textWidth, 17.0);
    self.detailLabel.frame = CGRectMake(textX, 52.0, textWidth, 16.0);
    self.bioLabel.frame = CGRectMake(16.0, 78.0, cardWidth - 32.0, 34.0);

    self.connectTitleLabel.frame = CGRectMake(16.0, 16.0, cardWidth - 32.0, 23.0);
    self.connectSubtitleLabel.frame = CGRectMake(16.0, 42.0, cardWidth - 32.0, 36.0);
    self.connectButton.frame = CGRectMake(16.0, 86.0, 160.0, 36.0);
}

@end

#pragma mark - Stats cell

@interface MRProfileStatsCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) NSArray *valueLabels;
@property (nonatomic, strong) NSArray *captionLabels;

- (void)configureWithStats:(MRProfileStats *)stats;

@end

@implementation MRProfileStatsCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        [MRAppearance styleCardView:_cardView first:YES last:YES];
        [self.contentView addSubview:_cardView];

        NSMutableArray *values = [NSMutableArray array];
        NSMutableArray *captions = [NSMutableArray array];
        NSArray *captionsText = @[ @"Movies", @"TV", @"Anime",
                                   @"Episodes", @"Ratings", @"Watchlist" ];
        for (NSString *caption in captionsText) {
            UILabel *value = [[UILabel alloc] initWithFrame:CGRectZero];
            value.backgroundColor = [UIColor clearColor];
            value.font = [UIFont boldSystemFontOfSize:19.0];
            value.textColor = [MRAppearance ink];
            value.textAlignment = NSTextAlignmentCenter;
            value.text = @"0";
            [_cardView addSubview:value];
            [values addObject:value];

            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.backgroundColor = [UIColor clearColor];
            label.font = [MRAppearance smallFont];
            label.textColor = [MRAppearance muted];
            label.textAlignment = NSTextAlignmentCenter;
            label.text = caption;
            [_cardView addSubview:label];
            [captions addObject:label];
        }
        _valueLabels = values;
        _captionLabels = captions;
    }
    return self;
}

- (void)configureWithStats:(MRProfileStats *)stats {
    NSArray *values = @[
        [NSNumber numberWithInteger:stats.movieCount],
        [NSNumber numberWithInteger:stats.showCount],
        [NSNumber numberWithInteger:stats.animeCount],
        [NSNumber numberWithInteger:stats.episodesWatched],
        [NSNumber numberWithInteger:stats.ratingsCount],
        [NSNumber numberWithInteger:stats.watchlistCount]
    ];
    for (NSUInteger index = 0; index < self.valueLabels.count; index++) {
        UILabel *label = [self.valueLabels objectAtIndex:index];
        label.text = [NSString stringWithFormat:@"%ld",
                      (long)[[values objectAtIndex:index] integerValue]];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat inset = MRProfileSideInset();
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:MRProfileDeviceClass()]);
    CGFloat cardX = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 4.0, cardWidth, 108.0);

    CGFloat columnWidth = cardWidth / 3.0;
    for (NSUInteger index = 0; index < self.valueLabels.count; index++) {
        NSUInteger row = index / 3;
        NSUInteger column = index % 3;
        CGFloat x = (CGFloat)column * columnWidth;
        UILabel *value = [self.valueLabels objectAtIndex:index];
        UILabel *caption = [self.captionLabels objectAtIndex:index];
        value.frame = CGRectMake(x, 12.0 + (CGFloat)row * 46.0, columnWidth, 24.0);
        caption.frame = CGRectMake(x, 36.0 + (CGFloat)row * 46.0, columnWidth, 14.0);
    }
}

@end

#pragma mark - Sync cell

@interface MRProfileSyncCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *chevronLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

- (void)configureWithSyncEngine:(MRSyncEngine *)engine pendingCount:(NSUInteger)pendingCount;

@end

@implementation MRProfileSyncCell

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
        _titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.text = @"Sync Now";
        [_cardView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = [MRAppearance smallFont];
        _detailLabel.textColor = [MRAppearance muted];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_detailLabel];

        _chevronLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevronLabel.backgroundColor = [UIColor clearColor];
        _chevronLabel.font = [UIFont boldSystemFontOfSize:22.0];
        _chevronLabel.textColor = [MRAppearance muted];
        _chevronLabel.textAlignment = NSTextAlignmentRight;
        _chevronLabel.text = @"›";
        [_cardView addSubview:_chevronLabel];

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        [_cardView addSubview:_spinner];
    }
    return self;
}

- (void)configureWithSyncEngine:(MRSyncEngine *)engine pendingCount:(NSUInteger)pendingCount {
    NSDate *lastSync = engine.lastSyncAt;

    NSString *lastText = nil;
    if (lastSync != nil) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterNoStyle];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
        lastText = [NSString stringWithFormat:@"Last synced %@",
                    [formatter stringFromDate:lastSync]];
    }

    NSString *state = nil;
    if (engine.isSyncing) {
        state = @"Syncing…";
    } else if (engine.lastSyncError != nil) {
        state = @"Offline";
    } else if (pendingCount > 0) {
        state = [NSString stringWithFormat:@"%lu pending",
                 (unsigned long)pendingCount];
    } else {
        state = @"Up to date";
    }

    if (lastText.length > 0) {
        self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", state, lastText];
    } else {
        self.detailLabel.text = state;
    }

    if (engine.isSyncing) {
        [self.spinner startAnimating];
        self.chevronLabel.hidden = YES;
    } else {
        [self.spinner stopAnimating];
        self.chevronLabel.hidden = NO;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat inset = MRProfileSideInset();
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:MRProfileDeviceClass()]);
    CGFloat cardX = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 4.0, cardWidth, 60.0);

    self.titleLabel.frame = CGRectMake(16.0, 11.0, cardWidth - 60.0, 19.0);
    self.detailLabel.frame = CGRectMake(16.0, 32.0, cardWidth - 60.0, 16.0);
    self.chevronLabel.frame = CGRectMake(cardWidth - 34.0, 18.0, 22.0, 24.0);
    self.spinner.frame = CGRectMake(cardWidth - 36.0, 20.0, 20.0, 20.0);
}

@end

#pragma mark - Action cell

@interface MRProfileActionCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *chevronLabel;

- (void)configureWithTitle:(NSString *)title
                    detail:(NSString *)detail
               destructive:(BOOL)destructive
                  showsMore:(BOOL)showsMore;

@end

@implementation MRProfileActionCell

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
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = [MRAppearance smallFont];
        _detailLabel.textColor = [MRAppearance muted];
        _detailLabel.textAlignment = NSTextAlignmentRight;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_cardView addSubview:_detailLabel];

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
                    detail:(NSString *)detail
               destructive:(BOOL)destructive
                  showsMore:(BOOL)showsMore {
    self.titleLabel.text = title != nil ? title : @"";
    self.titleLabel.textColor = destructive ? [MRAppearance droppedColor]
                                            : [MRAppearance ink];
    self.detailLabel.text = detail != nil ? detail : @"";
    self.detailLabel.hidden = detail.length == 0;
    self.chevronLabel.hidden = !showsMore;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat inset = MRProfileSideInset();
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:MRProfileDeviceClass()]);
    CGFloat cardX = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    self.cardView.frame = CGRectMake(cardX, 2.0, cardWidth, 44.0);

    CGFloat chevronWidth = self.chevronLabel.hidden ? 0.0 : 26.0;
    BOOL showsDetail = !self.detailLabel.hidden;
    CGFloat detailWidth = 0.0;
    if (showsDetail) {
        CGSize detailSize = [self.detailLabel.text sizeWithFont:self.detailLabel.font];
        detailWidth = MIN(180.0, ceil(detailSize.width) + 4.0);
    }
    self.titleLabel.frame = CGRectMake(16.0, 12.0,
                                       MAX(0.0, cardWidth - 32.0 - chevronWidth - detailWidth),
                                       20.0);
    self.detailLabel.frame = CGRectMake(cardWidth - 16.0 - chevronWidth - detailWidth,
                                        13.0,
                                        detailWidth,
                                        18.0);
    self.chevronLabel.frame = CGRectMake(cardWidth - 30.0, 10.0, 20.0, 24.0);
}

@end

#pragma mark - Controller

@interface MRProfileViewController () <UITableViewDataSource, UITableViewDelegate,
                                       UIAlertViewDelegate>

@property (nonatomic, strong) MRAppEnvironment *environment;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, assign) BOOL lastSignedIn;

@end

@implementation MRProfileViewController

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

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Profile";
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

    [self reloadSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isSignedIn != self.lastSignedIn) {
        [self reloadSections];
    } else {
        [self.tableView reloadData];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isSignedIn {
    if (self.environment.auth != nil) {
        return self.environment.auth.isSignedIn;
    }
    return self.environment.libraryStore != nil;
}

- (void)reloadSections {
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NSNumber numberWithInteger:MRProfileSectionHeader]];
    if (self.isSignedIn) {
        [sections addObject:[NSNumber numberWithInteger:MRProfileSectionStats]];
        [sections addObject:[NSNumber numberWithInteger:MRProfileSectionSync]];
        [sections addObject:[NSNumber numberWithInteger:MRProfileSectionForYou]];
    }
    [sections addObject:[NSNumber numberWithInteger:MRProfileSectionAbout]];
    if (self.isSignedIn) {
        [sections addObject:[NSNumber numberWithInteger:MRProfileSectionSignOut]];
        [sections addObject:[NSNumber numberWithInteger:MRProfileSectionRemoveData]];
    }
    self.sections = sections;
    self.lastSignedIn = self.isSignedIn;
    [self.tableView reloadData];
}

- (MRProfileSection)sectionKindAtIndex:(NSInteger)section {
    if (section < 0 || (NSUInteger)section >= self.sections.count) {
        return MRProfileSectionHeader;
    }
    return (MRProfileSection)[[self.sections objectAtIndex:(NSUInteger)section] integerValue];
}

#pragma mark - Notifications

- (void)authDidChange:(NSNotification *)notification {
    [self reloadSections];
}

- (void)libraryDidChange:(NSNotification *)notification {
    if (self.isSignedIn != self.lastSignedIn) {
        [self reloadSections];
        return;
    }
    if (!self.isSignedIn) {
        return;
    }
    [self.tableView reloadData];
}

- (void)syncStatusDidChange:(NSNotification *)notification {
    if (!self.isSignedIn) {
        return;
    }
    [self.tableView reloadData];
}

- (void)preferencesDidChange:(NSNotification *)notification {
    if (!self.isSignedIn) {
        return;
    }
    [self.tableView reloadData];
}

#pragma mark - Actions

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

- (void)syncNow {
    MRSyncEngine *engine = self.environment.syncEngine;
    if (engine == nil || engine.isSyncing) {
        return;
    }

    __weak MRProfileViewController *weakSelf = self;
    [engine syncWithCompletion:^(NSError *error) {
        MRProfileViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf.tableView reloadData];
        if (error != nil) {
            [MRToastView showMessage:@"Sync failed. Try again."
                              inView:strongSelf.view];
        }
    }];
}

- (void)openGenrePicker {
    id<MRRecommendationDataProviding> provider =
        self.environment.recommendationEngine.dataProvider;
    if (provider == nil) {
        provider = self.environment.apiClient;
    }
    MRPreferencesStore *preferences = self.environment.preferences;
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

- (void)openHiddenTitles {
    MRPreferencesStore *preferences = self.environment.preferences;
    if (preferences == nil) {
        return;
    }
    MRHiddenTitlesViewController *hidden =
        [[MRHiddenTitlesViewController alloc] initWithPreferences:preferences
                                                       imageCache:self.environment.imageCache];
    [self.navigationController pushViewController:hidden animated:YES];
}

- (void)confirmResetRecommendations {
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Reset Recommendations"
              message:@"Clear the composed For You feed and build it again from your library."
             delegate:self
    cancelButtonTitle:@"Cancel"
    otherButtonTitles:@"Reset", nil];
    alert.tag = MRProfileAlertReset;
    [alert show];
}

- (void)resetRecommendations {
    [self.environment.recommendationEngine invalidateCache];
    [MRToastView showMessage:@"Recommendations reset" inView:self.view];
}

- (void)openURLString:(NSString *)string {
    NSURL *URL = [NSURL URLWithString:string];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)confirmSignOut {
    NSUInteger pending = self.environment.outbox.pendingCount;
    NSString *message = pending > 0
        ? [NSString stringWithFormat:
           @"%lu pending write%@ will stay on this device for this account and resume the next time you sign in.",
           (unsigned long)pending, pending == 1 ? @"" : @"s"]
        : @"You can sign back in at any time.";
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Sign Out"
              message:message
             delegate:self
    cancelButtonTitle:@"Cancel"
    otherButtonTitles:@"Sign Out", nil];
    alert.tag = MRProfileAlertSignOut;
    [alert show];
}

- (void)confirmRemoveLocalData {
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Remove Local Data"
              message:@"This deletes this account's library, preferences, pending writes, cached images, and Keychain token from this device. Your Simkl data is not changed."
             delegate:self
    cancelButtonTitle:@"Cancel"
    otherButtonTitles:@"Remove", nil];
    alert.tag = MRProfileAlertRemoveData;
    [alert show];
}

- (void)removeLocalData {
    MRAppEnvironment *environment = self.environment;
    NSString *directory = environment.storage.accountDirectory;

    [environment.syncEngine cancel];
    [environment.recommendationEngine invalidateCache];
    [environment.imageCache clearMemoryCache];
    [environment.imageCache clearDiskCache];
    [environment.auth signOut];

    if (directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    }

    environment.accountID = 0;
    environment.storage = nil;
    environment.libraryStore = nil;
    environment.preferences = nil;
    environment.recommendationEngine = nil;
    environment.syncEngine = nil;
    environment.outbox = nil;
    environment.writeService = nil;

    [self reloadSections];
    [MRToastView showMessage:@"Local data removed" inView:self.view];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == MRProfileAlertSignOut && buttonIndex == 1) {
        [self.environment.auth signOut];
    } else if (alertView.tag == MRProfileAlertRemoveData && buttonIndex == 1) {
        [self removeLocalData];
    } else if (alertView.tag == MRProfileAlertReset && buttonIndex == 1) {
        [self resetRecommendations];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionKindAtIndex:section]) {
        case MRProfileSectionStats:
        case MRProfileSectionSync:
        case MRProfileSectionSignOut:
        case MRProfileSectionRemoveData:
            return 1;
        case MRProfileSectionHeader:
            return 1;
        case MRProfileSectionForYou:
            return 3;
        case MRProfileSectionAbout:
            return 3;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MRProfileSection kind = [self sectionKindAtIndex:indexPath.section];

    if (kind == MRProfileSectionHeader) {
        static NSString *identifier = @"MRProfileHeaderCell";
        MRProfileHeaderCell *cell = (MRProfileHeaderCell *)
            [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[MRProfileHeaderCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:identifier];
        }
        if (self.isSignedIn) {
            [cell configureSignedInWithProfile:self.environment.libraryStore.profile
                                    imageCache:self.environment.imageCache];
        } else {
            [cell configureSignedOut];
            __weak MRProfileViewController *weakSelf = self;
            cell.connectHandler = ^{ [weakSelf showConnect]; };
        }
        return cell;
    }

    if (kind == MRProfileSectionStats) {
        static NSString *identifier = @"MRProfileStatsCell";
        MRProfileStatsCell *cell = (MRProfileStatsCell *)
            [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[MRProfileStatsCell alloc] initWithStyle:UITableViewCellStyleDefault
                                             reuseIdentifier:identifier];
        }
        MRProfileStats *stats = [MRProfileStats statsWithItems:self.environment.libraryStore.items];
        [cell configureWithStats:stats];
        return cell;
    }

    if (kind == MRProfileSectionSync) {
        static NSString *identifier = @"MRProfileSyncCell";
        MRProfileSyncCell *cell = (MRProfileSyncCell *)
            [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[MRProfileSyncCell alloc] initWithStyle:UITableViewCellStyleDefault
                                            reuseIdentifier:identifier];
        }
        [cell configureWithSyncEngine:self.environment.syncEngine
                         pendingCount:self.environment.outbox.pendingCount];
        return cell;
    }

    static NSString *identifier = @"MRProfileActionCell";
    MRProfileActionCell *cell = (MRProfileActionCell *)
        [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[MRProfileActionCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:identifier];
    }

    if (kind == MRProfileSectionForYou) {
        MRPreferencesStore *preferences = self.environment.preferences;
        if (indexPath.row == 0) {
            NSUInteger count = preferences.manualGenres.count;
            NSString *detail = count > 0
                ? [NSString stringWithFormat:@"%lu of 5", (unsigned long)count]
                : @"None";
            [cell configureWithTitle:@"Favorite Genres"
                             detail:detail
                        destructive:NO
                           showsMore:YES];
        } else if (indexPath.row == 1) {
            NSUInteger count = preferences.hiddenTitles.count;
            NSString *detail = count > 0
                ? [NSString stringWithFormat:@"%lu", (unsigned long)count]
                : @"None";
            [cell configureWithTitle:@"Hidden Titles"
                             detail:detail
                        destructive:NO
                           showsMore:YES];
        } else {
            [cell configureWithTitle:@"Reset Recommendations"
                             detail:nil
                        destructive:NO
                           showsMore:NO];
        }
        return cell;
    }

    if (kind == MRProfileSectionAbout) {
        if (indexPath.row == 0) {
            [cell configureWithTitle:@"View on Simkl"
                             detail:nil
                        destructive:NO
                           showsMore:YES];
        } else if (indexPath.row == 1) {
            [cell configureWithTitle:@"Data from Simkl"
                             detail:@"Simkl"
                        destructive:NO
                           showsMore:NO];
        } else {
            [cell configureWithTitle:@"Version"
                             detail:MRProfileVersionText()
                        destructive:NO
                           showsMore:NO];
        }
        return cell;
    }

    if (kind == MRProfileSectionSignOut) {
        [cell configureWithTitle:@"Sign Out"
                         detail:nil
                    destructive:YES
                       showsMore:NO];
        return cell;
    }

    [cell configureWithTitle:@"Remove Local Data"
                     detail:nil
                destructive:YES
                   showsMore:NO];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self sectionKindAtIndex:indexPath.section]) {
        case MRProfileSectionHeader:
            return [MRProfileHeaderCell heightForProfile:self.environment.libraryStore.profile
                                               signedIn:self.isSignedIn];
        case MRProfileSectionStats:
            return 116.0;
        case MRProfileSectionSync:
            return 68.0;
        case MRProfileSectionSignOut:
        case MRProfileSectionRemoveData:
            return 50.0;
        default:
            return 48.0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self titleForSection:section].length > 0 ? 34.0 : 10.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == (NSInteger)self.sections.count - 1 ? 24.0 : 0.0;
}

- (NSString *)titleForSection:(NSInteger)section {
    switch ([self sectionKindAtIndex:section]) {
        case MRProfileSectionStats:
            return @"Stats";
        case MRProfileSectionSync:
            return @"Sync";
        case MRProfileSectionForYou:
            return @"For You";
        case MRProfileSectionAbout:
            return @"About";
        default:
            return nil;
    }
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

    MRProfileSection kind = [self sectionKindAtIndex:indexPath.section];
    if (kind == MRProfileSectionHeader) {
        if (!self.isSignedIn) {
            [self showConnect];
        }
    } else if (kind == MRProfileSectionSync) {
        [self syncNow];
    } else if (kind == MRProfileSectionForYou) {
        if (indexPath.row == 0) {
            [self openGenrePicker];
        } else if (indexPath.row == 1) {
            [self openHiddenTitles];
        } else {
            [self confirmResetRecommendations];
        }
    } else if (kind == MRProfileSectionAbout) {
        if (indexPath.row == 0) {
            [self openURLString:MRProfileConnectedAppsURL];
        } else if (indexPath.row == 1) {
            [self openURLString:@"https://simkl.com"];
        }
    } else if (kind == MRProfileSectionSignOut) {
        [self confirmSignOut];
    } else if (kind == MRProfileSectionRemoveData) {
        [self confirmRemoveLocalData];
    }
}

@end
