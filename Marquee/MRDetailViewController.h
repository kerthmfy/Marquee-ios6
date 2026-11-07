//
//  MRDetailViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAPIClient;
@class MRImageCache;
@class MRLibraryStore;
@class MRMediaItem;

// A read-only detail screen built from a library, search, or trending item. It
// renders the snapshot immediately, then merges the public detail record for
// overview, info rows, related titles, and fanart. Task 12 adds the write
// actions.
@interface MRDetailViewController : UIViewController

- (instancetype)initWithItem:(MRMediaItem *)item
                   apiClient:(MRAPIClient *)apiClient
                libraryStore:(MRLibraryStore *)libraryStore
                  imageCache:(MRImageCache *)imageCache;

@end
