//
//  MRStatusPillView.h
//  Marquee
//

#import <UIKit/UIKit.h>
#import "MRWatchStatus.h"

// The compact status badge shown on a Library row. It draws a tinted capsule
// in the status colour; MRWatchStatusNone hides the view.
@interface MRStatusPillView : UIView

// Zero for MRWatchStatusNone.
+ (CGSize)sizeForStatus:(MRWatchStatus)status;

@property (nonatomic, assign, readonly) MRWatchStatus watchStatus;

- (void)setWatchStatus:(MRWatchStatus)status;

@end
