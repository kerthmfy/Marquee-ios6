//
//  MRJSON.h
//  Marquee
//

#import <Foundation/Foundation.h>

extern NSString *const MRJSONErrorDomain;

@interface MRJSON : NSObject

+ (id)objectFromData:(NSData *)data error:(NSError **)error;
+ (NSData *)dataFromObject:(id)object error:(NSError **)error;

@end
