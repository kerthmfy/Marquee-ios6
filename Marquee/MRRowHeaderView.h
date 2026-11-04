//
//  MRRowHeaderView.h
//  Marquee
//

#import <UIKit/UIKit.h>

// A 32 pt For You row header: uppercase 13 pt bold muted title at a 12 pt left
// inset, an optional 16 pt Simkl badge, and a 1 px hairline below.
@interface MRRowHeaderView : UIView

- (instancetype)initWithTitle:(NSString *)title showsSimklBadge:(BOOL)showsSimklBadge;

@end
