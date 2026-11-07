//
//  MRStatusChipsView.m
//  Marquee
//

#import "MRStatusChipsView.h"
#import "MRAppearance.h"
#import "MRLayout.h"
#import "MRLibraryFilter.h"

static const CGFloat MRChipHeightPhone = 26.0;
static const CGFloat MRChipHeightTablet = 32.0;

#pragma mark - Chip button

@interface MRStatusChipButton : UIControl
@property (nonatomic, copy) NSString *chipTitle;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign, getter=isChosen) BOOL chosen;
- (CGSize)preferredSize;
@end

@implementation MRStatusChipButton {
    UILabel *_label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByClipping;
        _label.font = [MRAppearance chipFont];
        [self addSubview:_label];
        [self updateLabel];
    }
    return self;
}

- (UIFont *)font {
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    if (device == MRDeviceClassTablet) {
        return [UIFont boldSystemFontOfSize:13.0];
    }
    return [MRAppearance chipFont];
}

- (void)setChipTitle:(NSString *)chipTitle {
    _chipTitle = [chipTitle copy];
    [self updateLabel];
}

- (void)setCount:(NSInteger)count {
    _count = count;
    [self updateLabel];
}

- (void)updateLabel {
    NSString *title = self.chipTitle != nil ? self.chipTitle : @"";
    _label.text = [NSString stringWithFormat:@"%@ %ld", title, (long)self.count];
    _label.font = [self font];
    _label.textColor = self.chosen ? [UIColor whiteColor] : [MRAppearance ink];
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self updateLabel];
    [self setNeedsDisplay];
}

- (CGSize)preferredSize {
    UIFont *font = [self font];
    CGSize text = [_label.text sizeWithFont:font];
    CGFloat height = [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]] ==
        MRDeviceClassTablet ? MRChipHeightTablet : MRChipHeightPhone;
    return CGSizeMake(ceil(text.width) + 22.0, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self->_label.frame = CGRectInset(self.bounds, 10.0, 0.0);
}

- (void)drawRect:(CGRect)rect {
    CGRect bounds = CGRectInset(self.bounds, 0.5, 0.5);
    CGFloat radius = CGRectGetHeight(bounds) / 2.0;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                    cornerRadius:radius];

    if (self.chosen) {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context);
        [path addClip];

        NSArray *colors = @[
            (__bridge id)[UIColor colorWithRed:100.0 / 255.0
                                        green:150.0 / 255.0
                                         blue:214.0 / 255.0
                                        alpha:1.0].CGColor,
            (__bridge id)[UIColor colorWithRed:40.0 / 255.0
                                        green:79.0 / 255.0
                                         blue:130.0 / 255.0
                                        alpha:1.0].CGColor
        ];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient =
            CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
        CGContextDrawLinearGradient(context, gradient,
                                    CGPointMake(0.0, CGRectGetMinY(bounds)),
                                    CGPointMake(0.0, CGRectGetMaxY(bounds)),
                                    0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextRestoreGState(context);
    } else {
        [[UIColor whiteColor] setFill];
        [path fill];
        [[MRAppearance sep] setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    }
}

@end

#pragma mark - Chips row

@interface MRStatusChipsView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, copy) NSArray *chips;
@property (nonatomic, copy) NSArray *statuses;
@property (nonatomic, assign) MRMediaType mediaType;
@property (nonatomic, assign) MRWatchStatus selectedStatus;
@end

@implementation MRStatusChipsView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;

        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.alwaysBounceHorizontal = YES;
        _scrollView.scrollsToTop = NO;
        _scrollView.delegate = self;
        [self addSubview:_scrollView];

        NSMutableArray *chips = [NSMutableArray array];
        NSArray *statuses = @[
            @(MRWatchStatusNone), @(MRWatchStatusWatching),
            @(MRWatchStatusPlanToWatch), @(MRWatchStatusCompleted),
            @(MRWatchStatusHold), @(MRWatchStatusDropped)
        ];
        NSArray *titles = @[ @"All", @"Watching", @"Plan", @"Completed", @"Hold", @"Dropped" ];
        for (NSUInteger index = 0; index < statuses.count; index++) {
            MRStatusChipButton *chip =
                [[MRStatusChipButton alloc] initWithFrame:CGRectZero];
            chip.tag = (NSInteger)index;
            chip.chipTitle = [titles objectAtIndex:index];
            chip.count = 0;
            chip.chosen = index == 0;
            [chip addTarget:self
                     action:@selector(chipTapped:)
           forControlEvents:UIControlEventTouchUpInside];
            [_scrollView addSubview:chip];
            [chips addObject:chip];
        }
        _chips = chips;
        _statuses = statuses;
        _selectedStatus = MRWatchStatusNone;
        _mediaType = MRLibraryFilterAllTypes;
    }
    return self;
}

- (MRWatchStatus)configureWithCounts:(NSDictionary *)counts
                               total:(NSInteger)total
                             forType:(MRMediaType)type {
    self.mediaType = type;
    NSDictionary *payload = [counts isKindOfClass:[NSDictionary class]] ? counts : @{};

    for (NSUInteger index = 0; index < self.chips.count; index++) {
        MRStatusChipButton *chip = [self.chips objectAtIndex:index];
        MRWatchStatus status =
            (MRWatchStatus)[[self.statuses objectAtIndex:index] integerValue];
        BOOL movieHidden = (type == MRMediaTypeMovie &&
                            (status == MRWatchStatusWatching ||
                             status == MRWatchStatusHold));
        chip.hidden = movieHidden;

        NSInteger count = total;
        if (status != MRWatchStatusNone) {
            count = [[payload objectForKey:MRWatchStatusKey(status)] integerValue];
        }
        chip.count = count;
    }

    if (type == MRMediaTypeMovie &&
        (self.selectedStatus == MRWatchStatusWatching ||
         self.selectedStatus == MRWatchStatusHold)) {
        self.selectedStatus = MRWatchStatusNone;
    }
    [self updateChosenChips];
    [self setNeedsLayout];
    return self.selectedStatus;
}

- (void)selectStatus:(MRWatchStatus)status {
    if (self.mediaType == MRMediaTypeMovie &&
        (status == MRWatchStatusWatching || status == MRWatchStatusHold)) {
        status = MRWatchStatusNone;
    }
    if (status != MRWatchStatusNone &&
        status != MRWatchStatusWatching &&
        status != MRWatchStatusPlanToWatch &&
        status != MRWatchStatusCompleted &&
        status != MRWatchStatusHold &&
        status != MRWatchStatusDropped) {
        status = MRWatchStatusNone;
    }
    if (status == self.selectedStatus) {
        return;
    }
    self.selectedStatus = status;
    [self updateChosenChips];
}

- (void)updateChosenChips {
    for (NSUInteger index = 0; index < self.chips.count; index++) {
        MRStatusChipButton *chip = [self.chips objectAtIndex:index];
        MRWatchStatus status =
            (MRWatchStatus)[[self.statuses objectAtIndex:index] integerValue];
        chip.chosen = status == self.selectedStatus;
    }
}

- (void)chipTapped:(MRStatusChipButton *)sender {
    if (sender.hidden) {
        return;
    }
    MRWatchStatus status =
        (MRWatchStatus)[[self.statuses objectAtIndex:(NSUInteger)sender.tag] integerValue];
    [self selectStatus:status];
    if (self.selectionHandler != nil) {
        self.selectionHandler(self.selectedStatus);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.bounds;

    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat sideInset = device == MRDeviceClassTablet ? 16.0 : 12.0;
    CGFloat gap = device == MRDeviceClassTablet ? 10.0 : 8.0;
    CGFloat height = CGRectGetHeight(self.bounds);

    CGFloat x = sideInset;
    for (MRStatusChipButton *chip in self.chips) {
        if (chip.hidden) {
            continue;
        }
        CGSize size = [chip preferredSize];
        chip.frame = CGRectMake(x, floor((height - size.height) / 2.0),
                                size.width, size.height);
        x += size.width + gap;
    }

    CGFloat contentWidth = x - gap + sideInset;
    if (contentWidth < CGRectGetWidth(self.bounds)) {
        contentWidth = CGRectGetWidth(self.bounds);
    }
    self.scrollView.contentSize = CGSizeMake(contentWidth, height);
}

@end
