//
//  MRGenrePickerViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRPreferencesStore;
@protocol MRRecommendationDataProviding;

// The modal genre picker. Loads the three public genre indexes, groups them by
// media type, filters forbidden slugs through MRGenreChoice, and enforces five
// total selections. Selections are held locally until Done, which saves them
// atomically through MRPreferencesStore. The caller wraps this controller in a
// navigation controller.
@interface MRGenrePickerViewController : UITableViewController

- (instancetype)initWithDataProvider:(id<MRRecommendationDataProviding>)dataProvider
                         preferences:(MRPreferencesStore *)preferences;

@end
