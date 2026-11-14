//
//  MRDetailEpisodeGuideView.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;

// A read-only, season-selectable episode guide for shows and anime.
@interface MRDetailEpisodeGuideView : UIView

@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, copy) void (^retryHandler)(void);
@property (nonatomic, copy) void (^layoutChangedHandler)(void);

- (void)showLoading;
- (void)showEpisodes:(NSArray *)episodes;
- (void)showError;

// Returns 0 while the guide has no content to show.
- (CGFloat)heightForWidth:(CGFloat)width;

@end
