//
//  MRDetailViewController.h
//  Marquee
//

#import <UIKit/UIKit.h>

@class MRAPIClient;
@class MRImageCache;
@class MRLibraryStore;
@class MRMediaItem;
@class MROutbox;
@class MRWriteService;

// A detail screen built from a library, search, or trending item. It renders
// the snapshot immediately, then merges the public detail record for overview,
// info rows, related titles, and fanart. When an outbox and write service are
// supplied it also offers tracking actions, optimistic local updates, and
// outbox reconciliation.
@interface MRDetailViewController : UIViewController

- (instancetype)initWithItem:(MRMediaItem *)item
                   apiClient:(MRAPIClient *)apiClient
                libraryStore:(MRLibraryStore *)libraryStore
                  imageCache:(MRImageCache *)imageCache
                      outbox:(MROutbox *)outbox
                writeService:(MRWriteService *)writeService;

- (instancetype)initWithItem:(MRMediaItem *)item
                   apiClient:(MRAPIClient *)apiClient
                libraryStore:(MRLibraryStore *)libraryStore
                  imageCache:(MRImageCache *)imageCache;

@end
