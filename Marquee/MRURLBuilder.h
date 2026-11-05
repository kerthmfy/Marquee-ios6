//
//  MRURLBuilder.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

// Builds every URL Marquee sends to Simkl. Query strings have a deterministic
// order so cache keys and diagnostics stay stable.
@interface MRURLBuilder : NSObject

// Encodes parameters for an application/x-www-form-urlencoded body. Keys are
// sorted so request bodies stay deterministic.
+ (NSString *)formEncodedStringForParameters:(NSDictionary *)parameters;

+ (NSString *)apiURLForPath:(NSString *)path query:(NSDictionary *)query;
+ (NSString *)dataURLForPath:(NSString *)path query:(NSDictionary *)query;
+ (NSString *)searchURLWithQuery:(NSString *)query page:(NSUInteger)page;
+ (NSString *)posterURLForPath:(NSString *)path size:(NSString *)size;
+ (NSString *)fanartURLForPath:(NSString *)path size:(NSString *)size;
+ (NSString *)posterPlaceholderURL;
+ (NSString *)avatarURLForPath:(NSString *)path;
+ (NSString *)simklWebURLForType:(MRMediaType)type simklID:(NSInteger)simklID slug:(NSString *)slug;

@end
