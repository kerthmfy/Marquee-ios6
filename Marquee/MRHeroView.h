//
//  MRHeroView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;

// The full-width hero card: fanart (or a landscape poster) under a dark
// bottom-heavy scrim, with an uppercase eyebrow, title, metadata, reason, and
// blue action button. Without artwork it falls back to the charcoal gradient.
@interface MRHeroView : UIView

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                   eyebrow:(NSString *)eyebrow
                  metadata:(NSString *)metadata
               buttonTitle:(NSString *)buttonTitle;

- (void)setArtworkFanartPath:(NSString *)fanartPath
                  posterPath:(NSString *)posterPath
                  imageCache:(MRImageCache *)imageCache;
- (void)cancelArtwork;

@property (nonatomic, copy) void (^actionHandler)(void);

@end
