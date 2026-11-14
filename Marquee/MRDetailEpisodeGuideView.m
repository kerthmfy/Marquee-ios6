//
//  MRDetailEpisodeGuideView.m
//  Marquee
//

#import "MRDetailEpisodeGuideView.h"

#import <QuartzCore/QuartzCore.h>

#import "MRAppearance.h"
#import "MRImageCache.h"
#import "MREpisode.h"
#import "MRLayout.h"
#import "MRPosterImageView.h"
#import "MRURLBuilder.h"

typedef NS_ENUM(NSInteger, MRDetailEpisodeGuideState) {
    MRDetailEpisodeGuideStateLoading,
    MRDetailEpisodeGuideStateContent,
    MRDetailEpisodeGuideStateError,
    MRDetailEpisodeGuideStateEmpty
};

static const NSInteger MRDetailEpisodePageSize = 12;

static BOOL MRGuideIsTablet(void) {
    return [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]] ==
        MRDeviceClassTablet;
}

static CGFloat MRGuidePadding(void) { return MRGuideIsTablet() ? 16.0 : 12.0; }
static CGFloat MRGuideStillWidth(void) { return MRGuideIsTablet() ? 116.0 : 88.0; }
static CGFloat MRGuideStillHeight(void) { return MRGuideIsTablet() ? 65.0 : 50.0; }
static CGFloat MRGuideStillGap(void) { return MRGuideIsTablet() ? 12.0 : 10.0; }
static CGFloat MRGuideChipHeight(void) { return MRGuideIsTablet() ? 32.0 : 26.0; }
static CGFloat MRGuideShowMoreHeight(void) { return MRGuideIsTablet() ? 42.0 : 38.0; }

static UIFont *MRGuideTitleFont(void) {
    return MRGuideIsTablet() ? [UIFont boldSystemFontOfSize:14.0]
                             : [UIFont boldSystemFontOfSize:12.0];
}

static UIFont *MRGuideFactsFont(void) {
    return MRGuideIsTablet() ? [UIFont systemFontOfSize:11.0]
                             : [UIFont systemFontOfSize:10.0];
}

static UIFont *MRGuideSummaryFont(void) {
    return MRGuideIsTablet() ? [UIFont systemFontOfSize:12.0]
                             : [UIFont systemFontOfSize:11.0];
}

static UIFont *MRGuideChipFont(void) {
    return MRGuideIsTablet() ? [UIFont boldSystemFontOfSize:13.0]
                             : [MRAppearance chipFont];
}

static NSString *MRGuideSeasonTitle(NSInteger season) {
    return season == 0 ? @"Specials"
                       : [NSString stringWithFormat:@"Season %ld", (long)season];
}

static NSString *MRGuideAirDateText(NSDate *date) {
    if (date == nil) {
        return nil;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [formatter setDateFormat:@"d MMM yyyy"];
    return [formatter stringFromDate:date];
}

static CGFloat MRGuideTextHeight(NSString *text, UIFont *font, CGFloat width,
                                 NSInteger maxLines) {
    if (text.length == 0 || width <= 0.0) {
        return 0.0;
    }
    CGSize size = [text sizeWithFont:font
                   constrainedToSize:CGSizeMake(width, 10000.0)
                       lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = ceil(size.height);
    if (maxLines > 0) {
        height = MIN(height, ceil(font.lineHeight) * maxLines);
    }
    return height;
}

#pragma mark - Episode row

@interface MRDetailEpisodeRowView : UIView

@property (nonatomic, strong) MRPosterImageView *stillView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *factsLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIView *separator;

+ (CGFloat)heightForEpisode:(MREpisode *)episode width:(CGFloat)width;
- (void)configureWithEpisode:(MREpisode *)episode imageCache:(MRImageCache *)imageCache;

@end

@implementation MRDetailEpisodeRowView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _stillView = [[MRPosterImageView alloc] initWithImageCache:nil];
        _stillView.contentMode = UIViewContentModeScaleAspectFill;
        [MRAppearance stylePosterThumbnailView:_stillView];
        [self addSubview:_stillView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.textColor = [MRAppearance ink];
        _titleLabel.font = MRGuideTitleFont();
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _factsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _factsLabel.backgroundColor = [UIColor clearColor];
        _factsLabel.textColor = [MRAppearance muted];
        _factsLabel.font = MRGuideFactsFont();
        _factsLabel.numberOfLines = 1;
        _factsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_factsLabel];

        _summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _summaryLabel.backgroundColor = [UIColor clearColor];
        _summaryLabel.textColor = [MRAppearance muted];
        _summaryLabel.font = MRGuideSummaryFont();
        _summaryLabel.numberOfLines = 3;
        _summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_summaryLabel];

        _separator = [[UIView alloc] initWithFrame:CGRectZero];
        _separator.backgroundColor = [MRAppearance sep];
        [self addSubview:_separator];
    }
    return self;
}

+ (CGFloat)heightForEpisode:(MREpisode *)episode width:(CGFloat)width {
    CGFloat pad = MRGuidePadding();
    CGFloat textWidth = width - pad * 2.0 - MRGuideStillWidth() - MRGuideStillGap();
    textWidth = MAX(0.0, textWidth);

    NSString *title = [self titleTextForEpisode:episode];
    NSString *facts = [self factsTextForEpisode:episode];
    CGFloat titleHeight = ceil(MRGuideTitleFont().lineHeight);
    CGFloat factsHeight = facts.length > 0 ? ceil(MRGuideFactsFont().lineHeight) : 0.0;
    CGFloat summaryHeight = MRGuideTextHeight(episode.summary, MRGuideSummaryFont(),
                                               textWidth, 3);
    (void)title;

    CGFloat body = titleHeight;
    if (factsHeight > 0.0) {
        body += 2.0 + factsHeight;
    }
    if (summaryHeight > 0.0) {
        body += 4.0 + summaryHeight;
    }
    CGFloat rowHeight = MAX(MRGuideStillHeight(), body) +
        (MRGuideIsTablet() ? 24.0 : 20.0);
    return ceil(rowHeight);
}

+ (NSString *)titleTextForEpisode:(MREpisode *)episode {
    NSString *title = episode.title;
    NSString *defaultTitle = [NSString stringWithFormat:@"Episode %ld", (long)episode.number];
    if (title.length == 0 || [title isEqualToString:defaultTitle]) {
        return [episode codeText];
    }
    return [NSString stringWithFormat:@"%@ · %@", [episode codeText], title];
}

+ (NSString *)factsTextForEpisode:(MREpisode *)episode {
    NSMutableArray *facts = [NSMutableArray array];
    if (episode.runtime > 0) {
        [facts addObject:[NSString stringWithFormat:@"%ld min", (long)episode.runtime]];
    }
    NSString *date = MRGuideAirDateText(episode.airDate);
    if (date.length > 0) {
        [facts addObject:episode.aired ? date : [NSString stringWithFormat:@"Upcoming · %@", date]];
    }
    return [facts componentsJoinedByString:@" · "];
}

- (void)configureWithEpisode:(MREpisode *)episode imageCache:(MRImageCache *)imageCache {
    [self.stillView setImageCache:imageCache];
    if (episode.imagePath.length > 0) {
        [self.stillView setImageURL:
            [MRURLBuilder episodeURLForPath:episode.imagePath size:@"_m"]];
    } else {
        [self.stillView setImageURL:nil];
    }

    self.titleLabel.text = [[self class] titleTextForEpisode:episode];
    self.factsLabel.text = [[self class] factsTextForEpisode:episode];
    self.summaryLabel.text = episode.summary;
    self.summaryLabel.hidden = episode.summary.length == 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat pad = MRGuidePadding();
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat stillWidth = MRGuideStillWidth();
    CGFloat stillHeight = MRGuideStillHeight();
    CGFloat textX = pad + stillWidth + MRGuideStillGap();
    CGFloat textWidth = MAX(0.0, width - textX - pad);
    CGFloat top = MRGuideIsTablet() ? 12.0 : 10.0;

    self.stillView.frame = CGRectMake(pad, top, stillWidth, stillHeight);

    CGFloat y = top;
    CGFloat titleHeight = ceil(MRGuideTitleFont().lineHeight);
    self.titleLabel.frame = CGRectMake(textX, y, textWidth, titleHeight);
    y += titleHeight;

    if (self.factsLabel.text.length > 0) {
        y += 2.0;
        self.factsLabel.frame = CGRectMake(textX, y, textWidth,
                                           ceil(MRGuideFactsFont().lineHeight));
        y += ceil(MRGuideFactsFont().lineHeight);
    } else {
        self.factsLabel.frame = CGRectZero;
    }

    if (self.summaryLabel.text.length > 0) {
        y += 4.0;
        CGFloat summaryHeight = MRGuideTextHeight(self.summaryLabel.text,
                                                  MRGuideSummaryFont(), textWidth, 3);
        self.summaryLabel.frame = CGRectMake(textX, y, textWidth, summaryHeight);
    } else {
        self.summaryLabel.frame = CGRectZero;
    }

    CGFloat height = CGRectGetHeight(self.bounds);
    self.separator.frame = CGRectMake(pad, height - 0.5, width - pad * 2.0, 0.5);
}

- (void)prepareForReuse {
    [self.stillView cancelLoading];
}

@end

#pragma mark - Guide

@interface MRDetailEpisodeGuideView ()

@property (nonatomic, assign) MRDetailEpisodeGuideState state;
@property (nonatomic, copy) NSArray *episodes;
@property (nonatomic, copy) NSArray *seasonNumbers;
@property (nonatomic, assign) NSInteger selectedSeason;
@property (nonatomic, assign) NSInteger visibleCount;

@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIScrollView *seasonScrollView;
@property (nonatomic, copy) NSArray *seasonChips;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, copy) NSArray *rowViews;
@property (nonatomic, strong) UIButton *showMoreButton;

@end

@implementation MRDetailEpisodeGuideView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [MRAppearance styleCardView:self first:YES last:YES];
        self.state = MRDetailEpisodeGuideStateEmpty;
        self.episodes = @[];
        self.seasonNumbers = @[];
        self.rowViews = @[];
        self.seasonChips = @[];

        _headerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _headerLabel.backgroundColor = [UIColor clearColor];
        _headerLabel.font = [MRAppearance groupTitleFont];
        _headerLabel.textColor = [MRAppearance muted];
        _headerLabel.text = @"EPISODE GUIDE";
        [self addSubview:_headerLabel];

        _countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _countLabel.backgroundColor = [UIColor clearColor];
        _countLabel.font = MRGuideFactsFont();
        _countLabel.textColor = [MRAppearance muted];
        _countLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:_countLabel];

        _seasonScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _seasonScrollView.backgroundColor = [UIColor clearColor];
        _seasonScrollView.showsHorizontalScrollIndicator = NO;
        _seasonScrollView.showsVerticalScrollIndicator = NO;
        _seasonScrollView.alwaysBounceHorizontal = YES;
        _seasonScrollView.scrollsToTop = NO;
        [self addSubview:_seasonScrollView];

        _spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _stateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _stateLabel.backgroundColor = [UIColor clearColor];
        _stateLabel.font = MRGuideFactsFont();
        _stateLabel.textColor = [MRAppearance muted];
        _stateLabel.numberOfLines = 1;
        _stateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_stateLabel];

        _retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _retryButton.backgroundColor = [UIColor clearColor];
        _retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:MRGuideIsTablet() ? 12.0 : 11.0];
        [_retryButton setTitle:@"Retry" forState:UIControlStateNormal];
        [_retryButton setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
        [_retryButton addTarget:self
                         action:@selector(retryTapped:)
               forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_retryButton];

        _showMoreButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _showMoreButton.backgroundColor = [UIColor clearColor];
        _showMoreButton.titleLabel.font = [UIFont boldSystemFontOfSize:MRGuideIsTablet() ? 12.0 : 11.0];
        [_showMoreButton setTitle:@"Show more episodes" forState:UIControlStateNormal];
        [_showMoreButton setTitleColor:[MRAppearance link] forState:UIControlStateNormal];
        [_showMoreButton addTarget:self
                            action:@selector(showMoreTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_showMoreButton];
    }
    return self;
}

- (void)showLoading {
    self.state = MRDetailEpisodeGuideStateLoading;
    self.episodes = @[];
    self.seasonNumbers = @[];
    self.selectedSeason = 0;
    self.visibleCount = 0;
    [self rebuildSeasonChips];
    [self rebuildRows];
    [self.spinner startAnimating];
    self.stateLabel.text = @"Loading episodes…";
    self.retryButton.hidden = YES;
    [self setNeedsLayout];
    [self notifyLayoutChanged];
}

- (void)showEpisodes:(NSArray *)episodes {
    NSMutableArray *valid = [NSMutableArray array];
    for (id episode in episodes) {
        if ([episode isKindOfClass:[MREpisode class]]) {
            [valid addObject:episode];
        }
    }
    self.episodes = valid;
    self.state = valid.count > 0 ? MRDetailEpisodeGuideStateContent
                                 : MRDetailEpisodeGuideStateEmpty;
    [self.spinner stopAnimating];
    self.stateLabel.text = @"";

    NSMutableArray *seasons = [NSMutableArray array];
    for (MREpisode *episode in self.episodes) {
        NSNumber *season = @(episode.season);
        if (![seasons containsObject:season]) {
            [seasons addObject:season];
        }
    }
    self.seasonNumbers = seasons;
    self.selectedSeason = seasons.count > 0
        ? [(NSNumber *)seasons[0] integerValue]
        : 0;
    self.visibleCount = MRDetailEpisodePageSize;
    [self rebuildSeasonChips];
    [self rebuildRows];
    [self updateCountText];
    [self setNeedsLayout];
    [self notifyLayoutChanged];
}

- (void)showError {
    self.state = MRDetailEpisodeGuideStateError;
    self.episodes = @[];
    self.seasonNumbers = @[];
    self.selectedSeason = 0;
    self.visibleCount = 0;
    [self rebuildSeasonChips];
    [self rebuildRows];
    [self.spinner stopAnimating];
    self.stateLabel.text = @"Episodes unavailable";
    self.retryButton.hidden = NO;
    [self setNeedsLayout];
    [self notifyLayoutChanged];
}

- (CGFloat)heightForWidth:(CGFloat)width {
    if (width <= 0.0 || self.state == MRDetailEpisodeGuideStateEmpty) {
        return 0.0;
    }
    if (self.state == MRDetailEpisodeGuideStateLoading ||
        self.state == MRDetailEpisodeGuideStateError) {
        return 64.0;
    }

    CGFloat y = 10.0 + 16.0;
    if (self.seasonNumbers.count > 1) {
        y += 6.0 + MRGuideChipHeight();
    }
    y += 8.0;

    NSArray *visible = [self visibleEpisodes];
    for (MREpisode *episode in visible) {
        y += [MRDetailEpisodeRowView heightForEpisode:episode width:width];
    }
    if ([self showsMoreButton]) {
        y += MRGuideShowMoreHeight();
    }
    return ceil(y + 4.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    BOOL tablet = MRGuideIsTablet();
    CGFloat pad = MRGuidePadding();
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat contentWidth = MAX(0.0, width - pad * 2.0);

    self.headerLabel.frame = CGRectMake(pad, 10.0, MAX(0.0, contentWidth - 110.0), 16.0);
    self.countLabel.frame = CGRectMake(width - pad - 110.0, 10.0, 110.0, 16.0);

    BOOL hasContent = self.state == MRDetailEpisodeGuideStateContent;
    BOOL hasSeasons = hasContent && self.seasonNumbers.count > 1;
    self.seasonScrollView.hidden = !hasSeasons;

    if (hasSeasons) {
        self.seasonScrollView.frame = CGRectMake(pad, 32.0, contentWidth,
                                                 MRGuideChipHeight());
        [self layoutSeasonChips];
    } else {
        self.seasonScrollView.frame = CGRectZero;
    }

    BOOL loading = self.state == MRDetailEpisodeGuideStateLoading;
    BOOL error = self.state == MRDetailEpisodeGuideStateError;
    self.spinner.hidden = !loading;
    self.stateLabel.hidden = !(loading || error);
    self.retryButton.hidden = !error;

    if (loading) {
        self.spinner.frame = CGRectMake(pad, 36.0, 20.0, 20.0);
        self.stateLabel.frame = CGRectMake(pad + 28.0, 38.0,
                                           MAX(0.0, contentWidth - 28.0), 16.0);
    } else if (error) {
        self.spinner.frame = CGRectZero;
        self.stateLabel.frame = CGRectMake(pad, 38.0,
                                           MAX(0.0, contentWidth - 60.0), 16.0);
        self.retryButton.frame = CGRectMake(width - pad - 54.0, 34.0, 54.0, 24.0);
    } else {
        self.spinner.frame = CGRectZero;
        self.stateLabel.frame = CGRectZero;
    }

    CGFloat y = 34.0;
    if (hasSeasons) {
        y = 32.0 + MRGuideChipHeight() + 8.0;
    }
    NSArray *visible = hasContent ? [self visibleEpisodes] : @[];
    for (NSUInteger index = 0; index < self.rowViews.count; index++) {
        MRDetailEpisodeRowView *row = [self.rowViews objectAtIndex:index];
        if (index >= visible.count) {
            row.hidden = YES;
            row.frame = CGRectZero;
            continue;
        }
        MREpisode *episode = [visible objectAtIndex:index];
        CGFloat rowHeight = [MRDetailEpisodeRowView heightForEpisode:episode width:width];
        row.hidden = NO;
        row.frame = CGRectMake(0.0, y, width, rowHeight);
        [row setNeedsLayout];
        y += rowHeight;
    }

    if ([self showsMoreButton]) {
        self.showMoreButton.hidden = NO;
        self.showMoreButton.frame = CGRectMake(0.0, y, width, MRGuideShowMoreHeight());
    } else {
        self.showMoreButton.hidden = YES;
        self.showMoreButton.frame = CGRectZero;
    }

    self.countLabel.hidden = !hasContent;
    (void)tablet;
}

#pragma mark - Content helpers

- (NSArray *)seasonEpisodes {
    NSMutableArray *episodes = [NSMutableArray array];
    for (MREpisode *episode in self.episodes) {
        if (episode.season == self.selectedSeason) {
            [episodes addObject:episode];
        }
    }
    return episodes;
}

- (NSArray *)visibleEpisodes {
    NSArray *episodes = [self seasonEpisodes];
    NSUInteger count = (NSUInteger)MAX(0, self.visibleCount);
    if (count > episodes.count) {
        count = episodes.count;
    }
    return [episodes subarrayWithRange:NSMakeRange(0, count)];
}

- (BOOL)showsMoreButton {
    return self.visibleCount < [self seasonEpisodes].count;
}

- (void)updateCountText {
    NSInteger count = (NSInteger)[self seasonEpisodes].count;
    self.countLabel.text = [NSString stringWithFormat:@"%ld episode%@",
                            (long)count, count == 1 ? @"" : @"s"];
}

- (void)rebuildRows {
    for (MRDetailEpisodeRowView *row in self.rowViews) {
        [row prepareForReuse];
        [row removeFromSuperview];
    }

    NSMutableArray *rows = [NSMutableArray array];
    for (MREpisode *episode in [self visibleEpisodes]) {
        MRDetailEpisodeRowView *row =
            [[MRDetailEpisodeRowView alloc] initWithFrame:CGRectZero];
        [row configureWithEpisode:episode imageCache:self.imageCache];
        [self addSubview:row];
        [rows addObject:row];
    }
    self.rowViews = rows;
    [self setNeedsLayout];
}

- (void)rebuildSeasonChips {
    for (UIButton *chip in self.seasonChips) {
        [chip removeFromSuperview];
    }

    NSMutableArray *chips = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.seasonNumbers.count; index++) {
        NSInteger season = [(NSNumber *)self.seasonNumbers[index] integerValue];
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = (NSInteger)index;
        chip.titleLabel.font = MRGuideChipFont();
        [chip setTitle:MRGuideSeasonTitle(season) forState:UIControlStateNormal];
        [chip addTarget:self
                 action:@selector(seasonChipTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        chip.layer.cornerRadius = MRGuideChipHeight() / 2.0;
        chip.layer.borderWidth = 0.5;
        [self.seasonScrollView addSubview:chip];
        [chips addObject:chip];
    }
    self.seasonChips = chips;
    [self updateSeasonChipSelection];
}

- (void)updateSeasonChipSelection {
    for (UIButton *chip in self.seasonChips) {
        NSInteger season = [(NSNumber *)self.seasonNumbers[(NSUInteger)chip.tag] integerValue];
        BOOL chosen = season == self.selectedSeason;
        chip.backgroundColor = chosen ? [MRAppearance link] : [UIColor whiteColor];
        chip.layer.borderColor = chosen
            ? [UIColor clearColor].CGColor
            : [MRAppearance sep].CGColor;
        [chip setTitleColor:chosen ? [UIColor whiteColor] : [MRAppearance ink]
                   forState:UIControlStateNormal];
    }
}

- (void)layoutSeasonChips {
    CGFloat x = 0.0;
    for (UIButton *chip in self.seasonChips) {
        CGSize text = [[chip titleForState:UIControlStateNormal]
                       sizeWithFont:chip.titleLabel.font];
        CGFloat chipWidth = MAX(48.0, ceil(text.width) + 22.0);
        chip.frame = CGRectMake(x, 0.0, chipWidth, MRGuideChipHeight());
        x += chipWidth + 6.0;
    }
    self.seasonScrollView.contentSize =
        CGSizeMake(MAX(0.0, x - 6.0), MRGuideChipHeight());
}

- (void)notifyLayoutChanged {
    if (self.layoutChangedHandler != nil) {
        self.layoutChangedHandler();
    }
}

#pragma mark - Actions

- (void)seasonChipTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.seasonNumbers.count) {
        return;
    }
    self.selectedSeason = [(NSNumber *)self.seasonNumbers[(NSUInteger)sender.tag] integerValue];
    self.visibleCount = MRDetailEpisodePageSize;
    [self updateSeasonChipSelection];
    [self rebuildRows];
    [self updateCountText];
    [self setNeedsLayout];
    [self notifyLayoutChanged];
}

- (void)showMoreTapped:(UIButton *)sender {
    self.visibleCount += MRDetailEpisodePageSize;
    [self rebuildRows];
    [self setNeedsLayout];
    [self notifyLayoutChanged];
}

- (void)retryTapped:(UIButton *)sender {
    if (self.retryHandler != nil) {
        self.retryHandler();
    }
}

@end
