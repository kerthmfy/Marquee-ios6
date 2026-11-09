//
//  MRTasteProfile.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

// A deterministic snapshot of the library's genre, type, and seed preferences.
// Built from the local library plus manual genre choices; no network access.
@interface MRTasteProfile : NSObject

+ (instancetype)profileWithItems:(NSArray *)items
                    manualGenres:(NSArray *)manualGenres
                             now:(NSDate *)now;

// Normalized 0…1 genre weight (raw weights may be negative for dropped items).
- (double)weightForGenre:(NSString *)genre;
- (double)weightForType:(MRMediaType)type;

// Raw signal weights, exposed for diagnostics and tests.
- (double)rawWeightForGenre:(NSString *)genre;
- (double)rawWeightForType:(MRMediaType)type;

// The top five normalized genre names with a weight above 0.1.
- (NSArray *)favoriteGenres;

// Up to three seed items, preferring one per type and ratings of 7 or higher.
- (NSArray *)seedItems;

@end
