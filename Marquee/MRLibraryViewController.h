//
//  MRLibraryViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAppEnvironment;
@class MRImageCache;
@class MRLibraryStore;

// The synced Simkl library, filterable by media type and watch status. Rows
// are sorted by last watched, then added date, then title. Refreshing starts
// the sync engine; the view never fetches on scroll.
@interface MRLibraryViewController : UIViewController

// The composition-root path. The store and sync engine can arrive after the
// controller is created, so every reload reads the environment again.
- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment;

// The explicit path from the implementation plan, kept for previews and tests
// that do not build a full environment.
- (instancetype)initWithLibraryStore:(MRLibraryStore *)libraryStore
                          imageCache:(MRImageCache *)imageCache;

// Task 12 wires the persistent outbox's pending count into this footer state.
- (void)setPendingCount:(NSInteger)pendingCount;

@end
