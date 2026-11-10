//
//  MRDiagnostics.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRHTTPRequest;
@class MRHTTPResponse;

// A persisted 50-entry ring buffer of API failures. Records contain only the
// timestamp, method, path (without query), status, Simkl error code, and a
// short message. Headers, query strings, request bodies, tokens, device codes,
// and authorization values are never stored.
@interface MRDiagnostics : NSObject

- (instancetype)initWithDirectory:(NSString *)directory;

// Newest records first.
- (NSArray *)records;

// Newest records first, capped at limit.
- (NSArray *)recentRecords:(NSUInteger)limit;

- (void)recordError:(NSError *)error
            request:(MRHTTPRequest *)request
           response:(MRHTTPResponse *)response;

@end
