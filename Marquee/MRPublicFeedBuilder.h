//
//  MRPublicFeedBuilder.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Composes the signed-out For You feed from the public week_100.json trending
// payload. The result always starts with the Connect Simkl hero. Trending data
// adds a round-robin combined row followed by per-type rows when items remain.
@interface MRPublicFeedBuilder : NSObject

+ (NSArray *)signedOutSectionsWithTrending:(NSDictionary *)trending;

@end
