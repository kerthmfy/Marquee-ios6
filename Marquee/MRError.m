//
//  MRError.m
//  Marquee
//

#import "MRError.h"

NSString *const MRErrorDomain = @"MRErrorDomain";
NSString *const MRErrorKindKey = @"MRErrorKind";
NSString *const MRErrorStatusCodeKey = @"MRErrorStatusCode";
NSString *const MRErrorCodeKey = @"MRErrorCode";
NSString *const MRErrorRetryAfterKey = @"MRErrorRetryAfter";

static NSString *MRSimklErrorCode(NSData *body) {
    if (body.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    id value = [(NSDictionary *)object objectForKey:@"error"];
    if (![value isKindOfClass:[NSString class]]) {
        value = [(NSDictionary *)object objectForKey:@"code"];
    }
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return nil;
}

static NSString *MRHeaderValue(NSDictionary *headers, NSString *name) {
    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] &&
            [(NSString *)key caseInsensitiveCompare:name] == NSOrderedSame) {
            id value = [headers objectForKey:key];
            return [value isKindOfClass:[NSString class]] ? value : [value description];
        }
    }
    return nil;
}

static NSNumber *MRRetryAfterSeconds(NSDictionary *headers) {
    NSString *value = MRHeaderValue(headers, @"Retry-After");
    if (value.length == 0) {
        return nil;
    }

    NSScanner *scanner = [NSScanner scannerWithString:value];
    double seconds = 0;
    if (![scanner scanDouble:&seconds] || !scanner.isAtEnd) {
        return nil;
    }
    if (seconds < 0) {
        seconds = 0;
    }
    return @(seconds);
}

@implementation MRError

+ (MRErrorKind)kindForStatusCode:(NSInteger)statusCode
                            body:(NSData *)body
                         headers:(NSDictionary *)headers {
    NSString *code = MRSimklErrorCode(body);

    if (statusCode == 401) {
        if ([code isEqualToString:@"invalid_client"]) {
            return MRErrorKindClientRejected;
        }
        return MRErrorKindAuthExpired;
    }
    if (statusCode == 412) {
        return MRErrorKindClientRejected;
    }
    if (statusCode == 429) {
        if ([code isEqualToString:@"user_limit_exceeded"]) {
            return MRErrorKindDailyLimit;
        }
        return MRErrorKindRateLimitedBurst;
    }
    if (statusCode == 400) {
        // Simkl uses an uppercase RATE_LIMIT code for the short write lock.
        if ([code isEqualToString:@"RATE_LIMIT"]) {
            return MRErrorKindWriteLocked;
        }
        if ([code isEqualToString:@"max_items"]) {
            return MRErrorKindTooLarge;
        }
        if ([code isEqualToString:@"id_err"] || [code isEqualToString:@"not_found"]) {
            return MRErrorKindNotFound;
        }
        return MRErrorKindUnknown;
    }
    if (statusCode == 404) {
        return MRErrorKindNotFound;
    }
    if (statusCode >= 500 && statusCode <= 599) {
        return MRErrorKindServer;
    }
    return MRErrorKindUnknown;
}

+ (MRErrorKind)kindForTransportError:(NSError *)transportError {
    if (![transportError.domain isEqualToString:NSURLErrorDomain]) {
        return MRErrorKindUnknown;
    }
    switch (transportError.code) {
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotFindHost:
        case NSURLErrorTimedOut:
        case NSURLErrorNetworkConnectionLost:
            return MRErrorKindOffline;
        case NSURLErrorCancelled:
            return MRErrorKindCancelled;
        default:
            return MRErrorKindUnknown;
    }
}

+ (NSError *)errorForStatusCode:(NSInteger)statusCode
                           body:(NSData *)body
                        headers:(NSDictionary *)headers
                 transportError:(NSError *)transportError {
    MRErrorKind kind = MRErrorKindUnknown;
    if (transportError != nil) {
        kind = [self kindForTransportError:transportError];
    } else {
        kind = [self kindForStatusCode:statusCode body:body headers:headers];
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = [self messageForKind:kind];
    userInfo[MRErrorKindKey] = @(kind);
    if (statusCode > 0) {
        userInfo[MRErrorStatusCodeKey] = @(statusCode);
    }
    NSString *code = MRSimklErrorCode(body);
    if (code != nil) {
        userInfo[MRErrorCodeKey] = code;
    }
    NSNumber *retryAfter = MRRetryAfterSeconds(headers);
    if (retryAfter != nil) {
        userInfo[MRErrorRetryAfterKey] = retryAfter;
    }
    if (transportError != nil) {
        userInfo[NSUnderlyingErrorKey] = transportError;
    }

    return [NSError errorWithDomain:MRErrorDomain code:kind userInfo:userInfo];
}

+ (NSError *)errorForStatusCode:(NSInteger)statusCode
                           body:(NSData *)body
                        headers:(NSDictionary *)headers {
    return [self errorForStatusCode:statusCode body:body headers:headers transportError:nil];
}

+ (NSError *)errorWithKind:(MRErrorKind)kind {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = [self messageForKind:kind];
    userInfo[MRErrorKindKey] = @(kind);
    return [NSError errorWithDomain:MRErrorDomain code:kind userInfo:userInfo];
}

+ (NSError *)errorWithKind:(MRErrorKind)kind retryAfter:(NSTimeInterval)retryAfter {
    NSError *error = [self errorWithKind:kind];
    if (retryAfter < 0) {
        retryAfter = 0;
    }
    NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
    userInfo[MRErrorRetryAfterKey] = @(retryAfter);
    return [NSError errorWithDomain:MRErrorDomain code:kind userInfo:userInfo];
}

+ (MRErrorKind)kindForError:(NSError *)error {
    if (error == nil) {
        return MRErrorKindUnknown;
    }
    NSNumber *kind = [error.userInfo objectForKey:MRErrorKindKey];
    if ([kind isKindOfClass:[NSNumber class]]) {
        return (MRErrorKind)[kind integerValue];
    }
    if ([error.domain isEqualToString:MRErrorDomain]) {
        return (MRErrorKind)error.code;
    }
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        return [self kindForTransportError:error];
    }
    return MRErrorKindUnknown;
}

+ (NSString *)messageForKind:(MRErrorKind)kind {
    switch (kind) {
        case MRErrorKindOffline:
            return @"Simkl is unreachable. Check your connection.";
        case MRErrorKindAuthExpired:
            return @"Your Simkl sign-in expired. Sign in again.";
        case MRErrorKindClientRejected:
            return @"Marquee could not identify itself to Simkl. Check the app configuration.";
        case MRErrorKindRateLimitedBurst:
            return @"Simkl is busy. Try again in a moment.";
        case MRErrorKindDailyLimit:
            return @"You reached Simkl's daily request limit. Try again later.";
        case MRErrorKindWriteLocked:
            return @"Simkl is finishing another update. Try again shortly.";
        case MRErrorKindNotFound:
            return @"Simkl could not find that title.";
        case MRErrorKindTooLarge:
            return @"Your library is too large for one sync";
        case MRErrorKindServer:
            return @"Simkl is having trouble right now. Try again later.";
        case MRErrorKindParse:
            return @"Marquee could not read the response from Simkl.";
        case MRErrorKindCancelled:
            return @"The Simkl request was cancelled.";
        case MRErrorKindUnknown:
        default:
            return @"Something went wrong talking to Simkl.";
    }
}

@end
