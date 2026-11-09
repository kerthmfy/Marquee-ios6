//
//  MRAppearance.m
//  Marquee
//
//  The drawing behaviour follows Matinee's MTAppearance: iOS 6 store chrome,
//  a brushed charcoal tab bar, and bordered white cards on pinstripe paper.
//

#import "MRAppearance.h"
#import "MRLayout.h"
#import "MRTabBarChromeView.h"

#import <math.h>

static const CGFloat MRTabBarHeight = 49.0;
static const CGFloat MRNavigationBarHeight = 44.0;
static const CGFloat MRSideInset = 8.0;
static const CGFloat MRTabIconSide = 30.0;

static const NSInteger MRCardBackgroundTag = 0x4D524344; // 'MRCD'

static UIColor *MRColor(CGFloat red, CGFloat green, CGFloat blue)
{
    return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}

static UIImage *MRVerticalGradientImage(NSArray *colors, CGFloat height, CGFloat highlightAlpha)
{
    CGSize size = CGSizeMake(1.0, height);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *color in colors) {
        [cgColors addObject:(__bridge id)color.CGColor];
    }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)cgColors,
                                                        NULL);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, height),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    if (highlightAlpha > 0.0) {
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithWhite:1.0 alpha:highlightAlpha].CGColor);
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, 1.0, 1.0));
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithWhite:1.0 alpha:highlightAlpha * 0.18].CGColor);
        CGContextFillRect(ctx, CGRectMake(0.0, 1.0, 1.0, 1.0));
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static void MRDrawGradientGlyph(CGContextRef ctx, UIBezierPath *path, BOOL stroked,
                                CGFloat lineWidth, NSArray *colors, CGFloat height)
{
    CGContextSaveGState(ctx);
    if (stroked) {
        CGContextSetLineWidth(ctx, lineWidth);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextAddPath(ctx, path.CGPath);
        CGContextReplacePathWithStrokedPath(ctx);
        CGContextClip(ctx);
    } else {
        [path addClip];
    }

    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *color in colors) {
        [cgColors addObject:(__bridge id)color.CGColor];
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)cgColors,
                                                        NULL);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, height),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);
}

static UIBezierPath *MRStarPath(CGFloat centerX, CGFloat centerY,
                                CGFloat outerRadius, CGFloat innerRadius)
{
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i < 10; i++) {
        CGFloat angle = -M_PI_2 + (CGFloat)i * M_PI / 5.0;
        CGFloat radius = (i % 2 == 0) ? outerRadius : innerRadius;
        CGPoint point = CGPointMake(centerX + cos(angle) * radius,
                                    centerY + sin(angle) * radius);
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

static UIImage *MRBarButtonImage(CGFloat width, BOOL back, BOOL highlighted)
{
    CGSize size = CGSizeMake(width, 30.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    UIBezierPath *path = nil;
    if (back) {
        path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(8.5, 0.5)];
        [path addLineToPoint:CGPointMake(width - 0.5, 0.5)];
        [path addLineToPoint:CGPointMake(width - 0.5, 29.5)];
        [path addLineToPoint:CGPointMake(8.5, 29.5)];
        [path addLineToPoint:CGPointMake(0.5, 15.0)];
        [path closePath];
    } else {
        path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, width - 1.0, 29.0)
                                          cornerRadius:5.0];
    }

    CGContextSaveGState(ctx);
    [path addClip];

    NSArray *colors = highlighted
        ? @[
            (__bridge id)MRColor(77, 107, 143).CGColor,
            (__bridge id)MRColor(59, 89, 120).CGColor
          ]
        : @[
            (__bridge id)MRColor(138, 166, 199).CGColor,
            (__bridge id)MRColor(89, 122, 163).CGColor,
            (__bridge id)MRColor(71, 107, 145).CGColor,
            (__bridge id)MRColor(56, 89, 125).CGColor
          ];
    CGFloat normalLocations[] = { 0.0, 0.49, 0.50, 1.0 };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)colors,
                                                        highlighted ? NULL : normalLocations);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, 30.0),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithWhite:1.0 alpha:0.28].CGColor);
    CGContextFillRect(ctx, CGRectMake(3.0, 1.5, width - 6.0, 1.0));
    CGContextRestoreGState(ctx);

    CGContextSetStrokeColorWithColor(ctx, MRColor(33, 56, 79).CGColor);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextAddPath(ctx, path.CGPath);
    CGContextStrokePath(ctx);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Card background

@interface MRCardBackgroundView : UIView
@property (nonatomic, assign) BOOL first;
@property (nonatomic, assign) BOOL last;
@end

static UIBezierPath *MRCardShapePath(CGRect rect, BOOL first, BOOL last)
{
    CGFloat radius = 9.0;

    if (first && last) {
        return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    }

    UIBezierPath *path = [UIBezierPath bezierPath];
    if (first) {
        [path moveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + radius)];
        [path addArcWithCenter:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMinY(rect) + radius)
                        radius:radius
                    startAngle:M_PI
                      endAngle:1.5 * M_PI
                     clockwise:YES];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMinY(rect))];
        [path addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMinY(rect) + radius)
                        radius:radius
                    startAngle:1.5 * M_PI
                      endAngle:0.0
                     clockwise:YES];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))];
        [path closePath];
    } else if (last) {
        [path moveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - radius)];
        [path addArcWithCenter:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMaxY(rect) - radius)
                        radius:radius
                    startAngle:M_PI
                      endAngle:0.5 * M_PI
                     clockwise:NO];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMaxY(rect))];
        [path addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMaxY(rect) - radius)
                        radius:radius
                    startAngle:0.5 * M_PI
                      endAngle:0.0
                     clockwise:NO];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))];
        [path closePath];
    } else {
        path = [UIBezierPath bezierPathWithRect:rect];
    }
    return path;
}

static UIBezierPath *MRCardOutlinePath(CGRect rect, BOOL first, BOOL last)
{
    CGFloat radius = 9.0;

    if (first && last) {
        return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    }

    UIBezierPath *path = [UIBezierPath bezierPath];
    if (first) {
        [path moveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + radius)];
        [path addArcWithCenter:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMinY(rect) + radius)
                        radius:radius
                    startAngle:M_PI
                      endAngle:1.5 * M_PI
                     clockwise:YES];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMinY(rect))];
        [path addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMinY(rect) + radius)
                        radius:radius
                    startAngle:1.5 * M_PI
                      endAngle:0.0
                     clockwise:YES];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))];
    } else if (last) {
        [path moveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - radius)];
        [path addArcWithCenter:CGPointMake(CGRectGetMinX(rect) + radius, CGRectGetMaxY(rect) - radius)
                        radius:radius
                    startAngle:M_PI
                      endAngle:0.5 * M_PI
                     clockwise:NO];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMaxY(rect))];
        [path addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - radius, CGRectGetMaxY(rect) - radius)
                        radius:radius
                    startAngle:0.5 * M_PI
                      endAngle:0.0
                     clockwise:NO];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))];
    } else {
        [path moveToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))];
        [path moveToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))];
        [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))];
    }
    return path;
}

@implementation MRCardBackgroundView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void)setFirst:(BOOL)first
{
    _first = first;
    [self setNeedsDisplay];
}

- (void)setLast:(BOOL)last
{
    _last = last;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        return;
    }

    CGRect card = CGRectMake(MRSideInset, 0.0,
                             CGRectGetWidth(self.bounds) - MRSideInset * 2.0,
                             CGRectGetHeight(self.bounds));
    CGFloat scale = self.contentScaleFactor;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGFloat hairline = 1.0 / scale;

    UIBezierPath *shape = MRCardShapePath(card, self.first, self.last);
    CGContextSaveGState(ctx);
    [shape addClip];
    [[UIColor whiteColor] setFill];
    CGContextFillRect(ctx, card);
    CGContextRestoreGState(ctx);

    UIBezierPath *outline = MRCardOutlinePath(card, self.first, self.last);
    [MRColor(166, 173, 181) setStroke];
    outline.lineWidth = hairline;
    [outline stroke];

    if (!self.last) {
        CGContextSetFillColorWithColor(ctx, MRColor(213, 216, 220).CGColor);
        CGContextFillRect(ctx, CGRectMake(CGRectGetMinX(card),
                                          CGRectGetMaxY(self.bounds) - hairline,
                                          CGRectGetWidth(card),
                                          hairline));
    }

    if (self.first) {
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithWhite:1.0 alpha:0.65].CGColor);
        CGContextFillRect(ctx, CGRectMake(CGRectGetMinX(card) + 1.0,
                                          CGRectGetMinY(card) + 1.0,
                                          CGRectGetWidth(card) - 2.0,
                                          hairline));
    }
}

@end

#pragma mark - Section head

@interface MRSectionHeaderView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, assign) BOOL pinstripe;
- (id)initWithTitle:(NSString *)title pinstripe:(BOOL)pinstripe;
@end

@implementation MRSectionHeaderView

- (id)initWithTitle:(NSString *)title pinstripe:(BOOL)pinstripe
{
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    self = [super initWithFrame:CGRectMake(0.0, 0.0,
        [MRLayout contentMaxWidthForDeviceClass:device], 32.0)];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _pinstripe = pinstripe;
        self.backgroundColor = pinstripe
            ? [UIColor colorWithPatternImage:[MRAppearance pinstripeImage]]
            : [UIColor clearColor];
        self.opaque = NO;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.text = [title uppercaseString];
        if (pinstripe) {
            _titleLabel.font = [MRAppearance groupTitleFont];
            _titleLabel.textColor = MRColor(77, 87, 99);
            _titleLabel.shadowColor = [UIColor colorWithWhite:1.0 alpha:0.72];
            _titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        } else {
            _titleLabel.font = [MRAppearance rowHeaderFont];
            _titleLabel.textColor = [MRAppearance muted];
        }
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    MRDeviceClass device =
        [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]];
    CGFloat inset = [MRLayout rowSideInsetForDeviceClass:device];
    self.titleLabel.frame = CGRectMake(inset, 9.0,
                                       CGRectGetWidth(self.bounds) - inset * 2.0, 17.0);
}

- (void)drawRect:(CGRect)rect
{
    if (self.pinstripe) {
        return;
    }

    CGFloat scale = self.contentScaleFactor;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[MRAppearance sep] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0,
                                      CGRectGetHeight(self.bounds) - 1.0 / scale,
                                      CGRectGetWidth(self.bounds),
                                      1.0 / scale));
}

@end

#pragma mark - Appearance

@implementation MRAppearance

+ (UIColor *)paper           { return MRColor(244, 245, 247); }
+ (UIColor *)groupBackground { return MRColor(200, 204, 210); }
+ (UIColor *)sep             { return MRColor(201, 204, 209); }
+ (UIColor *)ink             { return MRColor(33, 33, 38); }
+ (UIColor *)muted           { return MRColor(122, 122, 128); }
+ (UIColor *)placeholder     { return MRColor(231, 233, 237); }
+ (UIColor *)link            { return MRColor(41, 89, 143); }
+ (UIColor *)navigationTint  { return MRColor(41, 71, 107); }
+ (UIColor *)green           { return MRColor(0, 199, 83); }
+ (UIColor *)starEmpty       { return MRColor(209, 214, 219); }
+ (UIColor *)starColor        { return MRColor(191, 146, 22); }

+ (UIColor *)watchingColor   { return MRColor(45, 125, 210); }
+ (UIColor *)planColor       { return MRColor(138, 143, 152); }
+ (UIColor *)completedColor  { return MRColor(31, 157, 85); }
+ (UIColor *)holdColor       { return MRColor(201, 138, 27); }
+ (UIColor *)droppedColor    { return MRColor(192, 57, 43); }
+ (UIColor *)bannerNeutralColor { return MRColor(92, 99, 108); }
+ (UIColor *)bannerPendingColor { return MRColor(84, 103, 128); }
+ (UIColor *)bannerWarningColor { return MRColor(191, 128, 24); }
+ (UIColor *)bannerErrorColor   { return MRColor(176, 46, 36); }
+ (UIColor *)toastColor         { return MRColor(34, 36, 40); }

+ (UIColor *)statusColorForWatchStatus:(MRWatchStatus)status
{
    switch (status) {
        case MRWatchStatusWatching:    return [self watchingColor];
        case MRWatchStatusPlanToWatch: return [self planColor];
        case MRWatchStatusCompleted:   return [self completedColor];
        case MRWatchStatusHold:        return [self holdColor];
        case MRWatchStatusDropped:     return [self droppedColor];
        case MRWatchStatusNone:
        default:                       return [self muted];
    }
}

+ (UIFont *)titleFont           { return [UIFont boldSystemFontOfSize:16.0]; }
+ (UIFont *)bodyFont            { return [UIFont systemFontOfSize:13.0]; }
+ (UIFont *)smallFont           { return [UIFont systemFontOfSize:11.0]; }
+ (UIFont *)groupTitleFont      { return [UIFont boldSystemFontOfSize:11.0]; }
+ (UIFont *)rowHeaderFont       { return [UIFont boldSystemFontOfSize:13.0]; }
+ (UIFont *)cardTitleFont       { return [UIFont boldSystemFontOfSize:14.0]; }
+ (UIFont *)chipFont            { return [UIFont boldSystemFontOfSize:11.0]; }
+ (UIFont *)pillFont            { return [UIFont boldSystemFontOfSize:9.0]; }
+ (UIFont *)navigationTitleFont { return [UIFont boldSystemFontOfSize:17.0]; }
+ (UIFont *)tabTitleFont        { return [UIFont boldSystemFontOfSize:10.0]; }

+ (UIImage *)navigationBarImage
{
    static UIImage *image = nil;
    if (!image) {
        image = MRVerticalGradientImage(@[
            MRColor(107, 143, 179),
            MRColor(92, 128, 166),
            MRColor(71, 107, 145),
            MRColor(58, 92, 128)
        ], MRNavigationBarHeight, 0.40);
    }
    return image;
}

+ (UIImage *)tabBarImageForWidth:(CGFloat)width
{
    if (width <= 0.0) {
        return nil;
    }

    CGSize size = CGSizeMake(width, MRTabBarHeight);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    NSArray *colors = @[
        (__bridge id)MRColor(84, 84, 87).CGColor,
        (__bridge id)MRColor(50, 50, 53).CGColor,
        (__bridge id)MRColor(29, 29, 32).CGColor
    ];
    CGFloat locations[] = { 0.0, 0.52, 1.0 };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)colors,
                                                        locations);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, MRTabBarHeight),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    // iOS 6 store bars had a hard dark top edge and a one-pixel inner
    // highlight instead of a soft floating edge.
    [[UIColor colorWithWhite:0.0 alpha:0.88] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 0.0, width, 1.0));
    [[UIColor colorWithWhite:1.0 alpha:0.10] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 1.0, width, 1.0));

    // Faint brushed-metal columns keep the bar from reading as flat black.
    for (NSUInteger x = 0; x < (NSUInteger)width; x += 2) {
        CGFloat alpha = (x % 4 == 0) ? 0.020 : 0.010;
        [[UIColor colorWithWhite:1.0 alpha:alpha] setFill];
        CGContextFillRect(ctx, CGRectMake((CGFloat)x, 2.0, 1.0,
                                          MRTabBarHeight - 2.0));
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)tabSelectionImageForWidth:(CGFloat)width itemCount:(NSInteger)count
{
    // The iOS 6 Music bar lifts the selected item with a lighter charcoal
    // panel. Its width follows the current bar width and item count.
    CGFloat selectionWidth =
        [MRLayout tabBarSelectionWidthForWidth:width itemCount:count];
    if (selectionWidth <= 0.0) {
        return nil;
    }

    CGSize size = CGSizeMake(selectionWidth, MRTabBarHeight);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    NSArray *colors = @[
        (__bridge id)MRColor(104, 104, 108).CGColor,
        (__bridge id)MRColor(62, 62, 66).CGColor,
        (__bridge id)MRColor(38, 38, 42).CGColor
    ];
    CGFloat locations[] = { 0.0, 0.55, 1.0 };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                        (__bridge CFArrayRef)colors,
                                                        locations);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0.0, 0.0),
                                CGPointMake(0.0, MRTabBarHeight),
                                0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    [[UIColor colorWithWhite:0.0 alpha:0.78] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 0.0, selectionWidth, 1.0));
    [[UIColor colorWithWhite:1.0 alpha:0.18] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 1.0, selectionWidth, 1.0));
    [[UIColor colorWithWhite:0.0 alpha:0.55] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, MRTabBarHeight - 1.0, selectionWidth, 1.0));
    [[UIColor colorWithWhite:0.0 alpha:0.72] setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 0.0, 1.0, MRTabBarHeight));
    CGContextFillRect(ctx, CGRectMake(selectionWidth - 1.0, 0.0, 1.0, MRTabBarHeight));

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)pinstripeImage
{
    static UIImage *image = nil;
    if (!image) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 1.0), YES, 0.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        [[self groupBackground] setFill];
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, 4.0, 1.0));
        [[UIColor colorWithWhite:1.0 alpha:0.34] setFill];
        CGContextFillRect(ctx, CGRectMake(0.0, 0.0, 1.0, 1.0));
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return image;
}

+ (UIImage *)tabIcon:(NSInteger)index selected:(BOOL)selected
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(MRTabIconSide, MRTabIconSide), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    NSArray *colors = selected
        ? @[ MRColor(36, 191, 255), MRColor(0, 107, 209) ]
        : @[ MRColor(204, 204, 209), MRColor(117, 117, 125) ];

    if (index == 0) {
        UIBezierPath *star = MRStarPath(12.5, 17.0, 9.0, 3.9);
        MRDrawGradientGlyph(ctx, star, NO, 0.0, colors, MRTabIconSide);

        UIBezierPath *sparkle = MRStarPath(24.0, 6.5, 3.3, 1.0);
        MRDrawGradientGlyph(ctx, sparkle, NO, 0.0, colors, MRTabIconSide);
    } else if (index == 1) {
        UIBezierPath *backCard =
            [UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.0, 4.5, 14.0, 18.0)
                                       cornerRadius:2.5];
        MRDrawGradientGlyph(ctx, backCard, YES, 1.6, colors, MRTabIconSide);

        UIBezierPath *middleCard =
            [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6.5, 7.5, 14.0, 18.0)
                                       cornerRadius:2.5];
        MRDrawGradientGlyph(ctx, middleCard, YES, 1.6, colors, MRTabIconSide);

        UIBezierPath *frontCard =
            [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.0, 10.5, 14.0, 18.0)
                                       cornerRadius:2.5];
        MRDrawGradientGlyph(ctx, frontCard, NO, 0.0, colors, MRTabIconSide);
    } else if (index == 2) {
        UIBezierPath *glass =
            [UIBezierPath bezierPathWithOvalInRect:CGRectMake(5.5, 5.5, 15.0, 15.0)];
        [glass moveToPoint:CGPointMake(19.0, 19.0)];
        [glass addLineToPoint:CGPointMake(25.5, 25.5)];
        MRDrawGradientGlyph(ctx, glass, YES, 2.6, colors, MRTabIconSide);
    } else {
        UIBezierPath *person =
            [UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.5, 4.0, 9.0, 9.0)];
        [person moveToPoint:CGPointMake(5.0, 26.0)];
        [person addCurveToPoint:CGPointMake(25.0, 26.0)
                controlPoint1:CGPointMake(5.4, 16.0)
                controlPoint2:CGPointMake(24.6, 16.0)];
        [person closePath];
        MRDrawGradientGlyph(ctx, person, NO, 0.0, colors, MRTabIconSide);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)actionButtonImage
{
    static UIImage *image = nil;
    if (!image) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(24.0, 38.0), NO, 0.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGRect rect = CGRectMake(0.5, 0.5, 23.0, 37.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6.0];

        CGContextSaveGState(ctx);
        [path addClip];
        NSArray *colors = @[
            (__bridge id)MRColor(112, 156, 204).CGColor,
            (__bridge id)MRColor(51, 97, 140).CGColor
        ];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                            (__bridge CFArrayRef)colors,
                                                            NULL);
        CGContextDrawLinearGradient(ctx, gradient,
                                    CGPointMake(0.0, 0.0),
                                    CGPointMake(0.0, 38.0),
                                    0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextRestoreGState(ctx);

        CGContextSetStrokeColorWithColor(ctx, MRColor(36, 61, 89).CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextAddPath(ctx, path.CGPath);
        CGContextStrokePath(ctx);

        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        image = [image resizableImageWithCapInsets:UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0)];
    }
    return image;
}

+ (UIImage *)dangerButtonImage
{
    static UIImage *image = nil;
    if (!image) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(24.0, 38.0), NO, 0.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGRect rect = CGRectMake(0.5, 0.5, 23.0, 37.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6.0];

        CGContextSaveGState(ctx);
        [path addClip];
        NSArray *colors = @[
            (__bridge id)MRColor(194, 79, 69).CGColor,
            (__bridge id)MRColor(153, 48, 41).CGColor
        ];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                            (__bridge CFArrayRef)colors,
                                                            NULL);
        CGContextDrawLinearGradient(ctx, gradient,
                                    CGPointMake(0.0, 0.0),
                                    CGPointMake(0.0, 38.0),
                                    0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        CGContextRestoreGState(ctx);

        CGContextSetStrokeColorWithColor(ctx, MRColor(97, 26, 20).CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextAddPath(ctx, path.CGPath);
        CGContextStrokePath(ctx);

        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        image = [image resizableImageWithCapInsets:UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0)];
    }
    return image;
}

+ (void)styleNavigationBar:(UINavigationBar *)bar
{
    if (!bar) {
        return;
    }

    [bar setBackgroundImage:[self navigationBarImage]
              forBarMetrics:UIBarMetricsDefault];

    NSDictionary *attributes = @{
        UITextAttributeTextColor: [UIColor whiteColor],
        UITextAttributeTextShadowColor: [UIColor colorWithWhite:0.0 alpha:0.55],
        UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetMake(0.0, -1.0)],
        UITextAttributeFont: [self navigationTitleFont]
    };
    [bar setTitleTextAttributes:attributes];
}

+ (void)styleTabBarItem:(UITabBarItem *)item index:(NSInteger)index
{
    if (!item) {
        return;
    }

    UIImage *normal = [self tabIcon:index selected:NO];
    UIImage *selected = [self tabIcon:index selected:YES];
    [item setFinishedSelectedImage:selected withFinishedUnselectedImage:normal];

    NSDictionary *ordinary = @{
        UITextAttributeTextColor: MRColor(190, 190, 195),
        UITextAttributeTextShadowColor: [UIColor colorWithWhite:0.0 alpha:0.80],
        UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetMake(0.0, -1.0)],
        UITextAttributeFont: [self tabTitleFont]
    };
    NSDictionary *active = @{
        UITextAttributeTextColor: [UIColor whiteColor],
        UITextAttributeTextShadowColor: [UIColor colorWithWhite:0.0 alpha:0.80],
        UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetMake(0.0, -1.0)],
        UITextAttributeFont: [self tabTitleFont]
    };
    [item setTitleTextAttributes:ordinary forState:UIControlStateNormal];
    [item setTitleTextAttributes:active forState:UIControlStateSelected];
}

+ (void)styleTabBar:(UITabBar *)tabBar
{
    if (!tabBar) {
        return;
    }

    CGFloat width = CGRectGetWidth(tabBar.bounds);
    UIImage *barImage = [self tabBarImageForWidth:width];
    if (barImage != nil) {
        [tabBar setBackgroundImage:barImage];
    }
    UIImage *selectionImage =
        [self tabSelectionImageForWidth:width itemCount:(NSInteger)tabBar.items.count];
    if (selectionImage != nil) {
        tabBar.selectionIndicatorImage = selectionImage;
    }

    NSArray *items = tabBar.items;
    for (NSUInteger i = 0; i < items.count; i++) {
        [self styleTabBarItem:[items objectAtIndex:i] index:(NSInteger)i];
    }

    MRTabBarChromeView *chrome = nil;
    for (UIView *view in tabBar.subviews) {
        if ([view isKindOfClass:[MRTabBarChromeView class]]) {
            chrome = (MRTabBarChromeView *)view;
            break;
        }
    }
    if (!chrome) {
        chrome = [[MRTabBarChromeView alloc] initWithFrame:tabBar.bounds];
        [tabBar addSubview:chrome];
    }
    chrome.frame = tabBar.bounds;
    [chrome setNeedsDisplay];
}

+ (void)styleCardView:(UIView *)view first:(BOOL)first last:(BOOL)last
{
    if (!view) {
        return;
    }

    MRCardBackgroundView *background = nil;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[MRCardBackgroundView class]]) {
            background = (MRCardBackgroundView *)subview;
            break;
        }
    }
    if (!background) {
        background = [[MRCardBackgroundView alloc] initWithFrame:view.bounds];
        background.tag = MRCardBackgroundTag;
        [view insertSubview:background atIndex:0];
    }

    background.frame = view.bounds;
    background.first = first;
    background.last = last;
    [background setNeedsDisplay];
    view.backgroundColor = [UIColor clearColor];
}

+ (UIView *)sectionHeaderViewWithTitle:(NSString *)title
{
    return [[MRSectionHeaderView alloc] initWithTitle:title pinstripe:NO];
}

+ (UIView *)groupSectionHeaderViewWithTitle:(NSString *)title
{
    return [[MRSectionHeaderView alloc] initWithTitle:title pinstripe:YES];
}

+ (UIButton *)barButtonWithTitle:(NSString *)title
                            back:(BOOL)back
                          target:(id)target
                          action:(SEL)action
{
    UIFont *font = [UIFont boldSystemFontOfSize:12.0];
    CGSize textSize = [title sizeWithFont:font];
    CGFloat width = ceil(textSize.width) + (back ? 31.0 : 20.0);
    width = MAX(width, 44.0);
    width = MIN(width, 104.0);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0.0, 0.0, width, 30.0);
    [button setBackgroundImage:MRBarButtonImage(width, back, NO)
                      forState:UIControlStateNormal];
    [button setBackgroundImage:MRBarButtonImage(width, back, YES)
                      forState:UIControlStateHighlighted];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = font;
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, back ? 14.0 : 0.0, 0.0, 0.0);
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.55]
                       forState:UIControlStateNormal];
    button.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@end
