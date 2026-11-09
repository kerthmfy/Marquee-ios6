//
//  MRStarRatingView.h
//  Marquee
//

#import <UIKit/UIKit.h>

// A ten-star rating control. Tapping a star sets that rating; tapping the same
// star again keeps it. Clearing a rating is an explicit, separate action.
@interface MRStarRatingView : UIControl

@property (nonatomic, assign) NSInteger rating;
@property (nonatomic, copy) void (^ratingHandler)(NSInteger rating);

+ (CGFloat)preferredHeight;

@end
