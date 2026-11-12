//
//  MRBannerStyle.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Shared banner styles. Kept Foundation-only so the pure error presenter can
// be unit-tested without UIKit.
typedef NS_ENUM(NSInteger, MRBannerStyle) {
    MRBannerStyleNeutral = 0,
    MRBannerStylePending,
    MRBannerStyleWarning,
    MRBannerStyleError
};
