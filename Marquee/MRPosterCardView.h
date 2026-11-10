//
//  MRPosterCardView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;
@class MRMediaItem;

// A 100x150 poster card with a two-line title and a one-line metadata label,
// used by the horizontal For You rows. Cards are 100x210 including the text so
// row cells can lay them out at 210 pt tall.
@interface MRPosterCardView : UIView

- (instancetype)initWithImageCache:(MRImageCache *)imageCache;
- (void)setItem:(MRMediaItem *)item;
// Overrides the one-line metadata label (for Continue Watching progress).
- (void)setMetaText:(NSString *)metaText;
// 0 hides the progress bar; values in (0, 1] draw it across the poster.
- (void)setProgress:(CGFloat)progress;
- (void)cancelLoading;

// Called when the card is tapped. Task 11 uses this for detail navigation.
@property (nonatomic, copy) void (^tapHandler)(MRMediaItem *item);
@property (nonatomic, copy) void (^longPressHandler)(MRMediaItem *item);

@end
