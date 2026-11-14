//
//  MRHiddenTitlesViewController.m
//  Marquee
//

#import "MRHiddenTitlesViewController.h"

#import "MRAppearance.h"
#import "MRHiddenTitle.h"
#import "MRImageCache.h"
#import "MRLayout.h"
#import "MRPlaceholderView.h"
#import "MRPosterImageView.h"
#import "MRPreferencesStore.h"
#import "MRToastView.h"

static CGFloat MRHiddenTitleRowHeight = 68.0;

#pragma mark - Cell

@interface MRHiddenTitleCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) MRPosterImageView *posterView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *unhideButton;

- (void)configureWithTitle:(MRHiddenTitle *)title
                imageCache:(MRImageCache *)imageCache
                 tapTarget:(id)target
                    action:(SEL)action;
- (void)cancelLoading;

@end

@implementation MRHiddenTitleCell

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
        [MRAppearance stylePosterThumbnailView:_posterView];
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

        _unhideButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _unhideButton.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        [_unhideButton setTitleColor:[MRAppearance navigationTint]
                            forState:UIControlStateNormal];
        [_unhideButton setTitleColor:[MRAppearance muted]
                            forState:UIControlStateHighlighted];
        [_unhideButton setTitle:@"Unhide" forState:UIControlStateNormal];
        [_cardView addSubview:_unhideButton];
    }
    return self;
}

- (void)configureWithTitle:(MRHiddenTitle *)title
                imageCache:(MRImageCache *)imageCache
                 tapTarget:(id)target
                    action:(SEL)action {
    [self.posterView setImageCache:imageCache];
    [self.posterView setImagePath:title.poster size:@"_cm"];

    self.titleLabel.text = title.title.length > 0 ? title.title : @"Untitled";

    NSMutableArray *parts = [NSMutableArray array];
    NSString *typeName = MRMediaTypeDisplayName(title.type);
    if (typeName.length > 0) {
        [parts addObject:typeName];
    }
    if (title.year > 0) {
        [parts addObject:[NSString stringWithFormat:@"%ld", (long)title.year]];
    }
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];

    [self.unhideButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.unhideButton addTarget:target
                          action:action
                forControlEvents:UIControlEventTouchUpInside];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat inset = device == MRDeviceClassTablet ? 16.0 : 8.0;
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat contentWidth = MIN(width, [MRLayout contentMaxWidthForDeviceClass:device]);
    CGFloat cardX = (width - contentWidth) / 2.0 + inset;
    CGFloat cardWidth = MAX(0.0, contentWidth - inset * 2.0);
    CGFloat cardHeight = MRHiddenTitleRowHeight - 8.0;
    self.cardView.frame = CGRectMake(cardX, 4.0, cardWidth, cardHeight);

    CGFloat posterWidth = 36.0;
    CGFloat posterHeight = 50.0;
    self.posterView.frame = CGRectMake(12.0, 9.0, posterWidth, posterHeight);

    CGFloat buttonWidth = 64.0;
    CGFloat buttonHeight = 30.0;
    CGFloat textX = CGRectGetMaxX(self.posterView.frame) + 10.0;
    CGFloat textWidth = MAX(0.0, cardWidth - textX - buttonWidth - 20.0);
    self.titleLabel.frame = CGRectMake(textX, 14.0, textWidth, 19.0);
    self.metaLabel.frame = CGRectMake(textX, 34.0, textWidth, 16.0);
    self.unhideButton.frame = CGRectMake(cardWidth - buttonWidth - 12.0,
                                         (cardHeight - buttonHeight) / 2.0,
                                         buttonWidth,
                                         buttonHeight);
}

- (void)cancelLoading {
    [self.posterView cancelLoading];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.posterView cancelLoading];
}

- (void)dealloc {
    [self.posterView cancelLoading];
}

@end

#pragma mark - Controller

@interface MRHiddenTitlesViewController ()

@property (nonatomic, strong) MRPreferencesStore *preferences;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) MRPlaceholderView *emptyView;

@end

@implementation MRHiddenTitlesViewController

- (instancetype)initWithPreferences:(MRPreferencesStore *)preferences
                         imageCache:(MRImageCache *)imageCache {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _preferences = preferences;
        _imageCache = imageCache;
    }
    return self;
}

- (id)init {
    return [self initWithPreferences:nil imageCache:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Hidden Titles";
    self.view.backgroundColor = [MRAppearance groupBackground];
    self.tableView.backgroundColor = [MRAppearance groupBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = MRHiddenTitleRowHeight;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    MRPlaceholderView *empty =
        [[MRPlaceholderView alloc] initWithMessage:@"No hidden titles.\nLong-press a card in For You to hide it."
                                       actionTitle:nil];
    empty.frame = CGRectMake(0.0, 0.0, 280.0, 140.0);
    self.emptyView = empty;
    [self updateEmptyState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.emptyView.frame = CGRectMake(0.0, 0.0, 280.0, 140.0);
}

- (NSArray *)hiddenTitles {
    NSArray *titles = self.preferences.hiddenTitles;
    return [titles isKindOfClass:[NSArray class]] ? titles : @[];
}

- (void)updateEmptyState {
    BOOL empty = self.hiddenTitles.count == 0;
    self.tableView.backgroundView = empty ? self.emptyView : nil;
    self.tableView.separatorStyle = empty
        ? UITableViewCellSeparatorStyleNone
        : UITableViewCellSeparatorStyleNone;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.hiddenTitles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MRHiddenTitleCell";
    MRHiddenTitleCell *cell = (MRHiddenTitleCell *)
        [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[MRHiddenTitleCell alloc] initWithStyle:UITableViewCellStyleDefault
                                        reuseIdentifier:identifier];
    }

    MRHiddenTitle *hidden = [self.hiddenTitles objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithTitle:hidden
                  imageCache:self.imageCache
                   tapTarget:self
                      action:@selector(unhideTapped:)];
    return cell;
}

- (void)unhideTapped:(UIButton *)sender {
    UIView *cellView = sender;
    while (cellView != nil && ![cellView isKindOfClass:[UITableViewCell class]]) {
        cellView = cellView.superview;
    }
    if (cellView == nil) {
        return;
    }

    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)cellView];
    if (indexPath == nil ||
        indexPath.row < 0 ||
        (NSUInteger)indexPath.row >= self.hiddenTitles.count) {
        return;
    }

    MRHiddenTitle *hidden = [self.hiddenTitles objectAtIndex:(NSUInteger)indexPath.row];
    NSError *error = nil;
    BOOL unhidden = [self.preferences unhideTitleForType:hidden.type
                                                 simklID:hidden.simklID
                                                   error:&error];
    if (!unhidden) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Couldn't Unhide"
                                                        message:@"This title couldn't be restored."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    [self.tableView reloadData];
    [self updateEmptyState];
    [MRToastView showMessage:@"Restored to For You" inView:self.view];
}

@end
