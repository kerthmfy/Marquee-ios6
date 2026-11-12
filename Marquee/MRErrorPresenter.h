//
//  MRErrorPresenter.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRBannerStyle.h"

// Pure mapping from MRError kinds to banner copy, colour, and whether a manual
// Retry makes sense. Cancelled requests deliberately produce no banner.
@interface MRErrorPresenter : NSObject

+ (NSString *)messageForError:(NSError *)error resetDate:(NSDate *)resetDate;
+ (MRBannerStyle)styleForError:(NSError *)error;
+ (BOOL)showsRetryForError:(NSError *)error;

@end
