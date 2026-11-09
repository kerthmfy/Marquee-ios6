//
//  MRGenreChoice.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

// One manual genre choice. Eligible genres are read from the Simkl genre index;
// adult genres and the low-signal video-game-play slug are never offered.
@interface MRGenreChoice : NSObject

@property (nonatomic, assign) MRMediaType type;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *slug;

+ (instancetype)choiceWithType:(MRMediaType)type
                          name:(NSString *)name
                          slug:(NSString *)slug;

+ (BOOL)isAllowedGenreSlug:(NSString *)slug;

// Filters a genre/index.json array to allowed MRGenreChoice values.
+ (NSArray *)allowedGenresFromIndex:(NSArray *)index type:(MRMediaType)type;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)choiceWithDictionaryRepresentation:(NSDictionary *)dictionary;

@end
