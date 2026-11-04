//
//  MRHeroView.h
//  Marquee
//

#import <UIKit/UIKit.h>

// The full-width hero card: a dark gradient with white text and a blue action
// button. Used by the Connect Simkl card and, later, by recommendation heroes.
@interface MRHeroView : UIView

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
               buttonTitle:(NSString *)buttonTitle;

@property (nonatomic, copy) void (^actionHandler)(void);

@end
