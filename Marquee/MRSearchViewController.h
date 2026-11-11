//
//  MRSearchViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAPIClient;
@class MRAppEnvironment;
@class MRImageCache;
@class MRPreferencesStore;

// The authenticated mixed-type search tab. Searches debounce, cache results in
// memory for ten minutes, and load further pages only on tap up to five pages.
// Signed out it shows a Connect Simkl card instead of the search bar.
@interface MRSearchViewController : UIViewController

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                       preferences:(MRPreferencesStore *)preferences
                        imageCache:(MRImageCache *)imageCache;

// Optional composition root. When set, auth, library, outbox, write service,
// and preferences are read live so the tab follows sign-in and sign-out.
@property (nonatomic, strong) MRAppEnvironment *environment;

@end
