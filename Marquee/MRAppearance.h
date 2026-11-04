//
//  MRAppearance.h
//  Marquee
//
//  Colours, type, and chrome shared by every screen. iOS 6 only.
//

#import <UIKit/UIKit.h>
#import "MRWatchStatus.h"

@interface MRAppearance : NSObject

// Colour tokens
+ (UIColor *)paper;
+ (UIColor *)groupBackground;
+ (UIColor *)sep;
+ (UIColor *)ink;
+ (UIColor *)muted;
+ (UIColor *)placeholder;
+ (UIColor *)link;
+ (UIColor *)navigationTint;
+ (UIColor *)green;
+ (UIColor *)starEmpty;
+ (UIColor *)watchingColor;
+ (UIColor *)planColor;
+ (UIColor *)completedColor;
+ (UIColor *)holdColor;
+ (UIColor *)droppedColor;
+ (UIColor *)statusColorForWatchStatus:(MRWatchStatus)status;

// System type, no custom fonts
+ (UIFont *)titleFont;       // bold 16, screen titles
+ (UIFont *)bodyFont;        // 13
+ (UIFont *)smallFont;       // 11
+ (UIFont *)groupTitleFont;   // bold 11, uppercase grouped headers
+ (UIFont *)rowHeaderFont;    // bold 13, uppercase For You row headers
+ (UIFont *)navigationTitleFont;
+ (UIFont *)tabTitleFont;

// Chrome images
+ (UIImage *)navigationBarImage;
+ (UIImage *)tabBarImage;
+ (UIImage *)tabSelectionImage;
+ (UIImage *)pinstripeImage;
+ (UIImage *)actionButtonImage;
+ (UIImage *)dangerButtonImage;

// 0 = For You, 1 = Library, 2 = Search, 3 = Profile.
+ (UIImage *)tabIcon:(NSInteger)index selected:(BOOL)selected;

+ (void)styleNavigationBar:(UINavigationBar *)bar;
+ (void)styleTabBar:(UITabBar *)tabBar;
+ (void)styleTabBarItem:(UITabBarItem *)item index:(NSInteger)index;

// Attaches the bordered white card background behind the view's content.
+ (void)styleCardView:(UIView *)view first:(BOOL)first last:(BOOL)last;

// 32 pt section headers. The plain style is the lighter For You row head;
// the grouped style is the pinstripe settings head.
+ (UIView *)sectionHeaderViewWithTitle:(NSString *)title;
+ (UIView *)groupSectionHeaderViewWithTitle:(NSString *)title;

// The shaped iOS 6 navigation button. The back variant has the pointed cap.
+ (UIButton *)barButtonWithTitle:(NSString *)title
                            back:(BOOL)back
                          target:(id)target
                          action:(SEL)action;

@end
