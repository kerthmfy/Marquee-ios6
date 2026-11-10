//
//  MRHiddenTitlesViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRImageCache;
@class MRPreferencesStore;

// The local "Not Interested" list. Each row can be restored, which makes the
// title eligible for the next For You generation.
@interface MRHiddenTitlesViewController : UITableViewController

- (instancetype)initWithPreferences:(MRPreferencesStore *)preferences
                         imageCache:(MRImageCache *)imageCache;

@end
