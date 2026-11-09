//
//  MRStarRatingView.m
//  Marquee
//

#import "MRStarRatingView.h"

#import <math.h>

#import "MRAppearance.h"

@interface MRStarRatingView ()
@property (nonatomic, assign) NSInteger trackingRating;
@end

static UIBezierPath *MRStarRatingPath(CGPoint center, CGFloat outerRadius,
                                      CGFloat innerRadius) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSInteger index = 0; index < 10; index += 1) {
        CGFloat angle = -M_PI_2 + (CGFloat)index * M_PI / 5.0;
        CGFloat radius = (index % 2 == 0) ? outerRadius : innerRadius;
        CGPoint point = CGPointMake(center.x + cos(angle) * radius,
                                    center.y + sin(angle) * radius);
        if (index == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

@implementation MRStarRatingView

+ (CGFloat)preferredHeight {
    return 32.0;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Rating";
        _rating = 0;
        [self updateAccessibilityValue];
    }
    return self;
}

- (void)setRating:(NSInteger)rating {
    if (rating < 0) {
        rating = 0;
    }
    if (rating > 10) {
        rating = 10;
    }
    if (_rating == rating) {
        return;
    }
    _rating = rating;
    [self updateAccessibilityValue];
    [self setNeedsDisplay];
}

- (void)updateAccessibilityValue {
    self.accessibilityValue = self.rating > 0
        ? [NSString stringWithFormat:@"%ld of 10", (long)self.rating]
        : @"Not rated";
}

- (void)drawRect:(CGRect)rect {
    CGRect bounds = self.bounds;
    CGFloat slot = CGRectGetWidth(bounds) / 10.0;
    CGFloat side = MIN(slot - 2.0, CGRectGetHeight(bounds) - 4.0);
    if (side < 6.0) {
        return;
    }

    CGFloat outer = side / 2.0;
    CGFloat inner = outer * 0.44;
    CGFloat centerY = CGRectGetMidY(bounds);
    NSInteger shownRating = self.trackingRating > 0 ? self.trackingRating
                                                    : self.rating;
    for (NSInteger index = 0; index < 10; index += 1) {
        CGFloat centerX = slot * (CGFloat)index + slot / 2.0;
        UIBezierPath *star = MRStarRatingPath(CGPointMake(centerX, centerY),
                                              outer, inner);
        UIColor *color = index < shownRating ? [MRAppearance starColor]
                                             : [MRAppearance starEmpty];
        [color setFill];
        [star fill];
    }
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (!hidden) {
        [self setNeedsDisplay];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsDisplay];
}

- (NSInteger)ratingForTouch:(UITouch *)touch {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0.0) {
        return self.rating;
    }
    CGPoint point = [touch locationInView:self];
    NSInteger index = (NSInteger)floor(point.x / (width / 10.0)) + 1;
    if (index < 1) {
        index = 1;
    }
    if (index > 10) {
        index = 10;
    }
    return index;
}

- (void)setTrackingRating:(NSInteger)trackingRating {
    _trackingRating = trackingRating;
    [self setNeedsDisplay];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super beginTrackingWithTouch:touch withEvent:event];
    self.trackingRating = [self ratingForTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super continueTrackingWithTouch:touch withEvent:event];
    self.trackingRating = [self ratingForTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    NSInteger rating = touch != nil ? [self ratingForTouch:touch] : self.trackingRating;
    self.trackingRating = 0;
    if (rating < 1) {
        return;
    }

    self.rating = rating;
    if (self.ratingHandler != nil) {
        self.ratingHandler(rating);
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [super cancelTrackingWithEvent:event];
    self.trackingRating = 0;
}

@end
