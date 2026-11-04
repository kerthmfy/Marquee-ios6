//
//  MRTokenProviding.h
//  Marquee
//

#import <Foundation/Foundation.h>

@protocol MRTokenProviding <NSObject>
- (void)validAccessTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion;
@end
