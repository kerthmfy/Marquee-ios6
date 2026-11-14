//
//  MRDetailPosterPanelView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;
@class MRMediaItem;

// The Letterboxd-style detail card: portrait poster plus compact key facts.
@interface MRDetailPosterPanelView : UIView

- (void)configureWithItem:(MRMediaItem *)item imageCache:(MRImageCache *)imageCache;

// Returns 0 when the item has no poster and no facts worth showing.
- (CGFloat)heightForWidth:(CGFloat)width;

@end
