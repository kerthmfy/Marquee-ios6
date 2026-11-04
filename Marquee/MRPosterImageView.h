//
//  MRPosterImageView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;

// A cached poster view. While a poster is loading, or when it fails, the view
// shows a light gray field with a film-frame glyph drawn in code. A per-view
// load token prevents a reused cell from displaying a stale image and cancels
// only this view's request when another view shares the same URL.
@interface MRPosterImageView : UIImageView

- (instancetype)initWithImageCache:(MRImageCache *)imageCache;
- (void)setImagePath:(NSString *)path size:(NSString *)size;
- (void)setImageURL:(NSString *)URL;
- (void)cancelLoading;

@end
