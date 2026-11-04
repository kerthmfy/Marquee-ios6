//
//  MRErrorTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRError.h"

static NSData *MRBody(NSString *json) {
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static void MRAssertKind(NSInteger statusCode, NSString *json, NSString *headerValue,
                         MRErrorKind expected, NSString *message) {
    NSDictionary *headers = nil;
    if (headerValue != nil) {
        headers = @{@"Retry-After": headerValue};
    }
    MRErrorKind kind = [MRError kindForStatusCode:statusCode body:MRBody(json) headers:headers];
    MRAssertEqualIntegers(expected, kind, message);
}

void MRRunErrorTests(void) {
    MRAssertKind(429, @"{\"error\":\"rate_limit\"}", nil,
                 MRErrorKindRateLimitedBurst, @"429 rate_limit");
    MRAssertKind(429, @"{\"error\":\"user_limit_exceeded\"}", nil,
                 MRErrorKindDailyLimit, @"429 user_limit_exceeded");
    MRAssertKind(400, @"{\"error\":\"RATE_LIMIT\"}", nil,
                 MRErrorKindWriteLocked, @"400 RATE_LIMIT");
    MRAssertKind(400, @"{\"error\":\"max_items\"}", nil,
                 MRErrorKindTooLarge, @"400 max_items");
    MRAssertKind(400, @"{\"code\":\"max_items\"}", nil,
                 MRErrorKindTooLarge, @"400 code max_items");
    MRAssertKind(400, @"{\"error\":\"id_err\"}", nil,
                 MRErrorKindNotFound, @"400 id_err");
    MRAssertKind(404, @"{\"error\":\"not_found\"}", nil,
                 MRErrorKindNotFound, @"404 not_found");
    MRAssertKind(401, @"{\"error\":\"user_token_failed\"}", nil,
                 MRErrorKindAuthExpired, @"401 user_token_failed");
    MRAssertKind(401, @"{\"error\":\"invalid_client\"}", nil,
                 MRErrorKindClientRejected, @"401 invalid_client");
    MRAssertKind(412, @"{\"error\":\"client_id_failed\"}", nil,
                 MRErrorKindClientRejected, @"412 client_id_failed");
    MRAssertKind(500, @"", nil, MRErrorKindServer, @"500 server");
    MRAssertKind(502, @"", nil, MRErrorKindServer, @"502 server");
    MRAssertKind(503, @"", nil, MRErrorKindServer, @"503 server");

    NSError *transport = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil];
    MRAssertEqualIntegers(MRErrorKindOffline, [MRError kindForTransportError:transport],
                          @"offline mapping");
    NSError *timeout = [NSError errorWithDomain:NSURLErrorDomain
                                           code:NSURLErrorTimedOut
                                       userInfo:nil];
    MRAssertEqualIntegers(MRErrorKindOffline, [MRError kindForTransportError:timeout],
                          @"timeout offline mapping");
    NSError *cancelled = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorCancelled
                                         userInfo:nil];
    MRAssertEqualIntegers(MRErrorKindCancelled, [MRError kindForTransportError:cancelled],
                          @"cancelled mapping");

    NSDictionary *headers = @{@"retry-after": @"120"};
    NSError *error = [MRError errorForStatusCode:429
                                            body:MRBody(@"{\"error\":\"user_limit_exceeded\"}")
                                         headers:headers
                                  transportError:nil];
    MRAssertEqualObjects(error.domain, MRErrorDomain, @"error domain");
    MRAssertEqualIntegers(MRErrorKindDailyLimit, [MRError kindForError:error],
                          @"error kind round-trip");
    MRAssertEqualObjects(error.userInfo[MRErrorCodeKey], @"user_limit_exceeded",
                         @"error code in user info");
    MRAssertEqualObjects(error.userInfo[MRErrorRetryAfterKey], @120,
                         @"retry-after seconds in user info");
    MRAssertTrue([error.localizedDescription rangeOfString:@"Simkl"].location != NSNotFound,
                 @"error message names Simkl");

    NSError *writeLock = [MRError errorForStatusCode:400
                                                body:MRBody(@"{\"error\":\"RATE_LIMIT\"}")
                                             headers:nil
                                      transportError:nil];
    MRAssertEqualIntegers(MRErrorKindWriteLocked, [MRError kindForError:writeLock],
                          @"write lock round-trip");
    MRAssertEqualObjects(writeLock.userInfo[MRErrorCodeKey], @"RATE_LIMIT",
                         @"write lock code preserved");

    NSError *offline = [MRError errorForStatusCode:0
                                              body:nil
                                           headers:nil
                                    transportError:transport];
    MRAssertEqualIntegers(MRErrorKindOffline, [MRError kindForError:offline],
                          @"transport error response");

    NSError *unknown = [MRError errorWithKind:MRErrorKindParse];
    MRAssertEqualIntegers(MRErrorKindParse, [MRError kindForError:unknown],
                          @"kind-only error");
}
