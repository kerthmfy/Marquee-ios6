//
//  MRForYouViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAppEnvironment;
@class MRImageCache;
@class MRLibraryStore;
@class MRPreferencesStore;
@class MRRecommendationEngine;

// The personalized first tab. Signed in, it renders the recommendation
// engine's hero and rows; signed out, it falls back to the public trending
// feed with a Connect hero.
@interface MRForYouViewController : UIViewController

- (instancetype)initWithRecommendationEngine:(MRRecommendationEngine *)engine
                                 preferences:(MRPreferencesStore *)preferences
                                libraryStore:(MRLibraryStore *)libraryStore
                                  imageCache:(MRImageCache *)imageCache;

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment;

@end
