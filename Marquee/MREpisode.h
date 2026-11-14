//
//  MREpisode.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

// A normalized entry from Simkl's /tv/episodes or /anime/episodes response.
@interface MREpisode : NSObject

@property (nonatomic, assign) NSInteger season;
@property (nonatomic, assign) NSInteger number;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, assign) NSInteger runtime;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, strong) NSDate *airDate;
@property (nonatomic, assign, getter=isSpecial) BOOL special;
@property (nonatomic, assign) BOOL aired;

// Shows without a season field default to season 1. Specials keep season 0 and
// are flagged so the guide can list them after the regular seasons.
+ (instancetype)episodeWithDictionary:(NSDictionary *)dictionary
                                 type:(MRMediaType)type;
+ (NSArray *)episodesWithDictionaries:(NSArray *)dictionaries
                                 type:(MRMediaType)type;

// "S1E2", "E2", or "Special 3".
- (NSString *)codeText;

@end
