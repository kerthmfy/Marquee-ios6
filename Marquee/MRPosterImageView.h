//
//  MRPosterImageView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;

// A cached poster view. While a poster is loading, or when it fails, the view
// shows a light gray field with a film-frame glyph drawn in code. A generation
// token prevents a reused cell from displaying a stale image.
@interface MRPosterImageView : UIImageView

- (instancetype)initWithImageCache:(MRImageCache *)imageCache;
- (void)setImagePath:(NSString *)path size:(NSString *)size;
- (void)setImageURL:(NSString *)URL;
- (void)cancelLoading;

@end
