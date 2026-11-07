//
//  MRUserProfile.h
//  Marquee
//

#import <Foundation/Foundation.h>

// The normalized subset of /users/settings that the app displays and caches.
// Account type is informational only; features are never gated on it.
@interface MRUserProfile : NSObject

@property (nonatomic, assign) NSInteger accountID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, strong) NSDate *joinedAt;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *accountType;
@property (nonatomic, copy) NSString *timezone;

// Normalizes the { "user": {...}, "account": {...} } settings shape.
+ (instancetype)profileWithSettingsDictionary:(NSDictionary *)dictionary;

// Round-trips -dictionaryRepresentation.
+ (instancetype)profileWithDictionaryRepresentation:(NSDictionary *)dictionary;

- (NSDictionary *)dictionaryRepresentation;

@end
