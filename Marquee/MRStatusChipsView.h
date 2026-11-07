//
//  MRStatusChipsView.h
//  Marquee
//

#import <UIKit/UIKit.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

// The horizontally scrolling status filter row on the Library tab. Chips stay
// on one line; the row scrolls instead of wrapping. Movies hide Watching and
// Hold because Simkl has no such buckets for them.
@interface MRStatusChipsView : UIView

@property (nonatomic, copy) void (^selectionHandler)(MRWatchStatus status);
@property (nonatomic, assign, readonly) MRWatchStatus selectedStatus;

// counts uses the MRWatchStatusKey names. Returns the selected status after
// any movie-only normalization (All when a hidden chip was selected).
- (MRWatchStatus)configureWithCounts:(NSDictionary *)counts
                               total:(NSInteger)total
                             forType:(MRMediaType)type;

// Programmatic selection. Never calls selectionHandler.
- (void)selectStatus:(MRWatchStatus)status;

@end
