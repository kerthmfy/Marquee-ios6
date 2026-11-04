//
//  MRDate.m
//  Marquee
//

#import "MRDate.h"

@implementation MRDate

+ (NSDateFormatter *)formatterWithFractionalSeconds:(BOOL)fractional {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [formatter setDateFormat:(fractional
                             ? @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                             : @"yyyy-MM-dd'T'HH:mm:ss'Z'")];
    return formatter;
}

+ (NSDate *)dateFromISOString:(NSString *)string {
    if (![string isKindOfClass:[NSString class]] || string.length == 0) {
        return nil;
    }

    NSDate *date = [[self formatterWithFractionalSeconds:YES] dateFromString:string];
    if (date == nil) {
        date = [[self formatterWithFractionalSeconds:NO] dateFromString:string];
    }
    return date;
}

+ (NSString *)isoStringFromDate:(NSDate *)date {
    if (date == nil) {
        return nil;
    }
    return [[self formatterWithFractionalSeconds:NO] stringFromDate:date];
}

@end
