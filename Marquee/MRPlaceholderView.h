//
//  MRPlaceholderView.h
//  Marquee
//

#import <UIKit/UIKit.h>

// A white card with a centered message and an optional action button. When
// loading is YES a spinner replaces the button.
@interface MRPlaceholderView : UIView

- (instancetype)initWithMessage:(NSString *)message actionTitle:(NSString *)actionTitle;

@property (nonatomic, copy) void (^actionHandler)(void);
@property (nonatomic, assign) BOOL loading;

@end
