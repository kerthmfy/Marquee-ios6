//
//  MRError.h
//  Marquee
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MRErrorKind) {
    MRErrorKindUnknown = 0,
    MRErrorKindOffline,
    MRErrorKindAuthExpired,
    MRErrorKindClientRejected,
    MRErrorKindRateLimitedBurst,
    MRErrorKindDailyLimit,
    MRErrorKindWriteLocked,
    MRErrorKindNotFound,
    MRErrorKindTooLarge,
    MRErrorKindServer,
    MRErrorKindParse,
    MRErrorKindCancelled
};

extern NSString *const MRErrorDomain;

// NSError userInfo keys. The kind is also stored as the error code.
extern NSString *const MRErrorKindKey;
extern NSString *const MRErrorStatusCodeKey;
extern NSString *const MRErrorCodeKey;
extern NSString *const MRErrorRetryAfterKey;

// Maps Simkl HTTP responses and NSURLConnection failures onto MRErrorKind.
@interface MRError : NSObject

+ (MRErrorKind)kindForStatusCode:(NSInteger)statusCode
                            body:(NSData *)body
                         headers:(NSDictionary *)headers;
+ (MRErrorKind)kindForTransportError:(NSError *)transportError;

+ (NSError *)errorForStatusCode:(NSInteger)statusCode
                           body:(NSData *)body
                        headers:(NSDictionary *)headers
                 transportError:(NSError *)transportError;
+ (NSError *)errorForStatusCode:(NSInteger)statusCode
                           body:(NSData *)body
                        headers:(NSDictionary *)headers;

+ (NSError *)errorWithKind:(MRErrorKind)kind;
+ (NSError *)errorWithKind:(MRErrorKind)kind retryAfter:(NSTimeInterval)retryAfter;
+ (MRErrorKind)kindForError:(NSError *)error;
+ (NSString *)messageForKind:(MRErrorKind)kind;

@end
