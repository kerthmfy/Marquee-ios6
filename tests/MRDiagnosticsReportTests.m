//
//  MRDiagnosticsReportTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDiagnosticsReport.h"

void MRRunDiagnosticsReportTests(void) {
    // A complete report contains every supplied field.
    {
        NSDictionary *fields = @{
            @"appVersion": @"1.0",
            @"build": @"42",
            @"osVersion": @"6.1.3",
            @"deviceModel": @"iPhone4,1",
            @"accountName": @"Kerth Yadao",
            @"accountID": @(12345),
            @"lastSyncAttempt": @"2026-11-10 12:00",
            @"lastSyncResult": @"Success",
            @"pendingCount": @3,
            @"requestsToday": @17,
            @"quotaLimit": @1000,
            @"quotaRemaining": @997,
            @"quotaResetAt": @"2026-11-11 00:00",
            @"cacheBytes": @(2048),
            @"errors": @[
                @{ @"timestamp": @"2026-11-10T12:01:00Z",
                   @"method": @"GET",
                   @"path": @"/sync/all-items",
                   @"status": @500,
                   @"code": @"server_error",
                   @"message": @"The server returned an error." }
            ]
        };
        NSString *report = [MRDiagnosticsReport reportWithFields:fields];

        MRAssertTrue([report rangeOfString:@"1.0"].location != NSNotFound,
                     @"the report includes the app version");
        MRAssertTrue([report rangeOfString:@"42"].location != NSNotFound,
                     @"the report includes the build");
        MRAssertTrue([report rangeOfString:@"6.1.3"].location != NSNotFound,
                     @"the report includes the iOS version");
        MRAssertTrue([report rangeOfString:@"iPhone4,1"].location != NSNotFound,
                     @"the report includes the device model");
        MRAssertTrue([report rangeOfString:@"Kerth Yadao"].location != NSNotFound,
                     @"the report includes the account name");
        MRAssertTrue([report rangeOfString:@"12345"].location != NSNotFound,
                     @"the report includes the account ID");
        MRAssertTrue([report rangeOfString:@"2026-11-10 12:00"].location != NSNotFound,
                     @"the report includes the last sync attempt");
        MRAssertTrue([report rangeOfString:@"Success"].location != NSNotFound,
                     @"the report includes the last sync result");
        MRAssertTrue([report rangeOfString:@"3"].location != NSNotFound,
                     @"the report includes the pending outbox count");
        MRAssertTrue([report rangeOfString:@"17"].location != NSNotFound,
                     @"the report includes today's request count");
        MRAssertTrue([report rangeOfString:@"1000"].location != NSNotFound,
                     @"the report includes the quota limit");
        MRAssertTrue([report rangeOfString:@"997"].location != NSNotFound,
                     @"the report includes the remaining quota");
        MRAssertTrue([report rangeOfString:@"2 KB"].location != NSNotFound ||
                     [report rangeOfString:@"2,048"].location != NSNotFound,
                     @"the report includes the cache size");
        MRAssertTrue([report rangeOfString:@"/sync/all-items"].location != NSNotFound,
                     @"the report includes recent API error paths");
        MRAssertTrue([report rangeOfString:@"server_error"].location != NSNotFound,
                     @"the report includes recent API error codes");
    }

    // Missing quota headers never invent a remaining count.
    {
        NSDictionary *fields = @{
            @"appVersion": @"1.0",
            @"quotaLimit": @(-1),
            @"quotaRemaining": @(-1)
        };
        NSString *report = [MRDiagnosticsReport reportWithFields:fields];
        MRAssertTrue([report rangeOfString:@"Quota remaining"].location == NSNotFound,
                     @"an unknown remaining count is omitted");
        MRAssertTrue([report rangeOfString:@"-1"].location == NSNotFound,
                     @"unknown quota values are not printed");
    }

    // Sensitive material never survives into the copied report.
    {
        NSDictionary *fields = @{
            @"appVersion": @"1.0",
            @"lastSyncResult": @"Authorization: Bearer super-secret-token",
            @"errors": @[
                @{ @"timestamp": @"2026-11-10T12:01:00Z",
                   @"method": @"GET",
                   @"path": @"/sync/all-items",
                   @"status": @401,
                   @"message": @"access_token=secret-device-code" }
            ]
        };
        NSString *report = [MRDiagnosticsReport reportWithFields:fields];
        MRAssertTrue([report rangeOfString:@"super-secret-token"].location == NSNotFound,
                     @"access tokens are never copied");
        MRAssertTrue([report rangeOfString:@"secret-device-code"].location == NSNotFound,
                     @"device codes are never copied");
        MRAssertTrue([report rangeOfString:@"[redacted]"].location != NSNotFound,
                     @"sensitive values are replaced with a redaction marker");
    }

    // An empty field set still produces a usable report.
    {
        NSString *report = [MRDiagnosticsReport reportWithFields:@{}];
        MRAssertTrue(report.length > 0, @"a report is always produced");
        MRAssertTrue([report rangeOfString:@"Marquee Diagnostics"].location != NSNotFound,
                     @"the report is labelled for support");
    }
}
