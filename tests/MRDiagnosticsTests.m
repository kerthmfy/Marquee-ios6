//
//  MRDiagnosticsTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDiagnostics.h"
#import "MRError.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"
#import "MRDate.h"

static NSString *MRCreateDiagnosticsDirectory(void) {
    NSString *name = [NSString stringWithFormat:@"marquee-diagnostics-%@",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return path;
}

static void MRRemoveDiagnosticsDirectory(NSString *path) {
    if (path != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static NSString *MRDiagnosticsFileContents(NSString *directory) {
    NSString *path = [directory stringByAppendingPathComponent:@"diagnostics.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
}

static void MRAssertDoesNotContain(NSString *haystack, NSString *needle, NSString *message) {
    if (haystack == nil) {
        MRAssertTrue(NO, message);
        return;
    }
    NSRange range = [haystack rangeOfString:needle
                                    options:NSCaseInsensitiveSearch];
    MRAssertTrue(range.location == NSNotFound, message);
}

static void MRRunDiagnosticsRedactionTest(void) {
    NSString *directory = MRCreateDiagnosticsDirectory();
    MRDiagnostics *diagnostics = [[MRDiagnostics alloc] initWithDirectory:directory];

    MRHTTPRequest *request =
        [[MRHTTPRequest alloc] initWithURL:
            @"https://api.simkl.com/sync/all-items?access_token=ACCESS-SECRET&client_id=public"
                                    method:@"POST"];
    request.headers = @{ @"Authorization": @"Bearer AUTH-SECRET",
                         @"X-Device-Code": @"DEVICE-SECRET" };
    request.body = [@"refresh_token=REFRESH-SECRET&device_code=DEVICE-SECRET"
                    dataUsingEncoding:NSUTF8StringEncoding];

    MRHTTPResponse *response =
        [MRHTTPResponse responseWithStatusCode:429
                                       headers:@{ @"Authorization": @"Bearer AUTH-SECRET",
                                                  @"X-RateLimit-Remaining": @"0" }
                                          data:[@"{\"error\":\"user_limit_exceeded\","
                                                 "\"access_token\":\"ACCESS-SECRET\"}"
                                                dataUsingEncoding:NSUTF8StringEncoding]
                                transportError:nil];

    NSError *error = [NSError errorWithDomain:MRErrorDomain
                                         code:MRErrorKindDailyLimit
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"You reached Simkl's daily request limit. Try again later.",
                                                 MRErrorCodeKey: @"user_limit_exceeded" }];

    [diagnostics recordError:error request:request response:response];

    NSArray *records = [diagnostics records];
    MRAssertEqualIntegers(1, (NSInteger)records.count, @"one diagnostic record saved");

    NSDictionary *record = records.count > 0 ? [records objectAtIndex:0] : nil;
    MRAssertEqualObjects(@"POST", [record objectForKey:@"method"],
                         @"record keeps the HTTP method");
    MRAssertEqualObjects(@"/sync/all-items", [record objectForKey:@"path"],
                         @"record keeps the path without the query");
    MRAssertEqualObjects(@429, [record objectForKey:@"status"],
                         @"record keeps the status code");
    MRAssertEqualObjects(@"user_limit_exceeded", [record objectForKey:@"code"],
                         @"record keeps the Simkl error code");
    MRAssertEqualObjects(@"You reached Simkl's daily request limit. Try again later.",
                         [record objectForKey:@"message"],
                         @"record keeps the localized message");
    MRAssertTrue([MRDate dateFromISOString:[record objectForKey:@"timestamp"]] != nil,
                 @"record timestamp is an ISO-8601 string");

    NSString *serialized = [records description];
    MRAssertDoesNotContain(serialized, @"access_token", @"records never contain access_token");
    MRAssertDoesNotContain(serialized, @"refresh_token", @"records never contain refresh_token");
    MRAssertDoesNotContain(serialized, @"device_code", @"records never contain device_code");
    MRAssertDoesNotContain(serialized, @"Authorization", @"records never contain an Authorization header");
    MRAssertDoesNotContain(serialized, @"ACCESS-SECRET", @"records never contain access token values");
    MRAssertDoesNotContain(serialized, @"REFRESH-SECRET", @"records never contain refresh token values");
    MRAssertDoesNotContain(serialized, @"DEVICE-SECRET", @"records never contain device code values");
    MRAssertDoesNotContain(serialized, @"client_id", @"records never contain query parameters");

    NSString *persisted = MRDiagnosticsFileContents(directory);
    MRAssertTrue(persisted.length > 0, @"diagnostics.json is written");
    MRAssertDoesNotContain(persisted, @"access_token", @"persisted data never contains access_token");
    MRAssertDoesNotContain(persisted, @"refresh_token", @"persisted data never contains refresh_token");
    MRAssertDoesNotContain(persisted, @"device_code", @"persisted data never contains device_code");
    MRAssertDoesNotContain(persisted, @"Authorization", @"persisted data never contains Authorization");
    MRAssertDoesNotContain(persisted, @"AUTH-SECRET", @"persisted data never contains auth values");

    MRRemoveDiagnosticsDirectory(directory);
}

static void MRRunDiagnosticsRingBufferTest(void) {
    NSString *directory = MRCreateDiagnosticsDirectory();
    MRDiagnostics *diagnostics = [[MRDiagnostics alloc] initWithDirectory:directory];

    for (NSInteger index = 1; index <= 51; index++) {
        NSString *path = [NSString stringWithFormat:@"/item/%ld", (long)index];
        NSString *URL = [NSString stringWithFormat:@"https://api.simkl.com%@?client_id=marquee",
                         path];
        MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:URL method:@"GET"];
        MRHTTPResponse *response = [MRHTTPResponse responseWithStatusCode:500
                                                                 headers:nil
                                                                    data:nil
                                                          transportError:nil];
        NSError *error = [NSError errorWithDomain:MRErrorDomain
                                             code:MRErrorKindServer
                                         userInfo:@{ NSLocalizedDescriptionKey:
                                                         @"Simkl is having trouble right now. Try again later.",
                                                     MRErrorCodeKey:
                                                         [NSString stringWithFormat:@"code-%ld",
                                                          (long)index] }];
        [diagnostics recordError:error request:request response:response];
    }

    NSArray *records = [diagnostics records];
    MRAssertEqualIntegers(50, (NSInteger)records.count, @"ring buffer keeps 50 entries");

    NSDictionary *newest = records.count > 0 ? [records objectAtIndex:0] : nil;
    NSDictionary *oldest = records.count > 0 ? [records lastObject] : nil;
    MRAssertEqualObjects(@"/item/51", [newest objectForKey:@"path"],
                         @"newest record is first");
    MRAssertEqualObjects(@"code-51", [newest objectForKey:@"code"],
                         @"newest record keeps its code");
    MRAssertEqualObjects(@"/item/2", [oldest objectForKey:@"path"],
                         @"oldest retained record is second-oldest");

    MRDiagnostics *reloaded = [[MRDiagnostics alloc] initWithDirectory:directory];
    NSArray *reloadedRecords = [reloaded records];
    MRAssertEqualIntegers(50, (NSInteger)reloadedRecords.count,
                          @"persisted ring buffer reloads 50 entries");
    MRAssertEqualObjects(@"/item/51",
                         [[reloadedRecords objectAtIndex:0] objectForKey:@"path"],
                         @"persisted records stay newest-first");

    MRRemoveDiagnosticsDirectory(directory);
}

static void MRRunDiagnosticsNoErrorCodeTest(void) {
    NSString *directory = MRCreateDiagnosticsDirectory();
    MRDiagnostics *diagnostics = [[MRDiagnostics alloc] initWithDirectory:directory];

    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:@"https://api.simkl.com/ping"
                                                         method:@"GET"];
    MRHTTPResponse *response = [MRHTTPResponse responseWithStatusCode:204
                                                             headers:nil
                                                                data:nil
                                                      transportError:nil];
    NSError *error = [NSError errorWithDomain:MRErrorDomain
                                         code:MRErrorKindUnknown
                                     userInfo:@{ NSLocalizedDescriptionKey: @"No content" }];

    [diagnostics recordError:error request:request response:response];

    NSDictionary *record = [[diagnostics records] objectAtIndex:0];
    MRAssertTrue([record objectForKey:@"code"] == nil,
                 @"missing Simkl error code is omitted");
    MRAssertEqualObjects(@"/ping", [record objectForKey:@"path"],
                         @"record path works without a query string");

    MRRemoveDiagnosticsDirectory(directory);
}

void MRRunDiagnosticsTests(void) {
    MRRunDiagnosticsRedactionTest();
    MRRunDiagnosticsRingBufferTest();
    MRRunDiagnosticsNoErrorCodeTest();
}
