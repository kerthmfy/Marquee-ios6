//
//  MRJSON.m
//  Marquee
//

#import "MRJSON.h"

NSString *const MRJSONErrorDomain = @"MRJSONErrorDomain";

@implementation MRJSON

+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: description };
    return [NSError errorWithDomain:MRJSONErrorDomain code:code userInfo:userInfo];
}

+ (id)objectFromData:(NSData *)data error:(NSError **)error {
    if (data == nil || data.length == 0) {
        if (error != NULL) {
            *error = [self errorWithCode:1 description:@"No JSON data"];
        }
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data
                                           options:NSJSONReadingAllowFragments
                                             error:error];
}

+ (NSData *)dataFromObject:(id)object error:(NSError **)error {
    if (object == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:2 description:@"No JSON object"];
        }
        return nil;
    }
    if (![NSJSONSerialization isValidJSONObject:object]) {
        if (error != NULL) {
            *error = [self errorWithCode:3 description:@"Object is not valid JSON"];
        }
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
}

@end
