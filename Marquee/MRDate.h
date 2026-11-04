//
//  MRDate.h
//  Marquee
//

#import <Foundation/Foundation.h>

@interface MRDate : NSObject

// Parses Simkl's ISO-8601 timestamps, with or without fractional seconds.
// Returns nil for nil/empty input or malformed strings.
+ (NSDate *)dateFromISOString:(NSString *)string;

// Formats a date as a whole-second UTC ISO-8601 string.
+ (NSString *)isoStringFromDate:(NSDate *)date;

@end
