//
//  MRStatusPillView.m
//  Marquee
//

#import "MRStatusPillView.h"
#import "MRAppearance.h"

@interface MRStatusPillView ()
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) MRWatchStatus watchStatus;
@end

@implementation MRStatusPillView

+ (NSString *)titleForStatus:(MRWatchStatus)status {
    switch (status) {
        case MRWatchStatusWatching:
            return @"Watching";
        case MRWatchStatusPlanToWatch:
            return @"Plan";
        case MRWatchStatusCompleted:
            return @"Completed";
        case MRWatchStatusHold:
            return @"Hold";
        case MRWatchStatusDropped:
            return @"Dropped";
        case MRWatchStatusNone:
        default:
            return @"";
    }
}

+ (CGSize)sizeForStatus:(MRWatchStatus)status {
    NSString *title = [self titleForStatus:status];
    if (title.length == 0) {
        return CGSizeZero;
    }
    CGSize text = [title sizeWithFont:[MRAppearance pillFont]];
    return CGSizeMake(ceil(text.width) + 12.0, 16.0);
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.font = [MRAppearance pillFont];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_label];

        _watchStatus = MRWatchStatusNone;
        self.hidden = YES;
    }
    return self;
}

- (void)setWatchStatus:(MRWatchStatus)status {
    _watchStatus = status;
    NSString *title = [[self class] titleForStatus:status];
    self.label.text = title;
    self.label.textColor = [MRAppearance statusColorForWatchStatus:status];
    self.hidden = title.length == 0;
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.label.frame = CGRectInset(self.bounds, 5.0, 1.0);
}

- (void)drawRect:(CGRect)rect {
    if (self.watchStatus == MRWatchStatusNone) {
        return;
    }

    UIColor *color = [MRAppearance statusColorForWatchStatus:self.watchStatus];
    CGRect bounds = CGRectInset(self.bounds, 0.5, 0.5);
    CGFloat radius = CGRectGetHeight(bounds) / 2.0;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                    cornerRadius:radius];

    [[color colorWithAlphaComponent:0.14] setFill];
    [path fill];
    [[color colorWithAlphaComponent:0.42] setStroke];
    path.lineWidth = 1.0;
    [path stroke];
}

@end
