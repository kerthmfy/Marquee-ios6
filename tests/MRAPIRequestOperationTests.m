//
//  MRAPIRequestOperationTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRError.h"
#import "MRAPIRequestOperation.h"

static NSString *MRWriteTemporaryFile(NSData *data) {
    NSString *name = [NSString stringWithFormat:@"marquee-test-%@.txt",
                      [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [data writeToFile:path atomically:YES];
    return path;
}

static void MRRemoveTemporaryFile(NSString *path) {
    if (path != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static void MRRunFileURLTest(void) {
    NSString *payload = @"marquee file payload\n";
    NSData *expectedData = [payload dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = MRWriteTemporaryFile(expectedData);
    NSString *URL = [[NSURL fileURLWithPath:path] absoluteString];

    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:URL method:@"GET"];

    __block NSUInteger completionCount = 0;
    __block MRHTTPResponse *received = nil;
    __block BOOL deliveredOnMainThread = NO;

    MRAPIRequestOperation *operation =
        [[MRAPIRequestOperation alloc] initWithRequest:request
                                            completion:^(MRHTTPResponse *response) {
            completionCount += 1;
            received = response;
            deliveredOnMainThread = [NSThread isMainThread];
        }];

    [operation start];

    MRAssertTrue(operation.isFinished, @"file url operation finishes synchronously");
    MRAssertTrue(MRRunUntil(^BOOL { return completionCount > 0; }, 5.0),
                 @"file url completion delivered");
    MRAssertEqualIntegers(1, (NSInteger)completionCount,
                          @"file url completion invoked exactly once");
    MRAssertTrue(deliveredOnMainThread, @"file url completion on main thread");
    MRAssertTrue(received != nil, @"file url response present");
    MRAssertEqualIntegers(0, received.statusCode, @"file url status code");
    MRAssertTrue(received.transportError == nil, @"file url has no transport error");
    MRAssertEqualObjects(expectedData, received.data, @"file url returns exact bytes");

    MRRemoveTemporaryFile(path);
}

static void MRCancelBeforeStartTest(void) {
    NSString *payload = @"cancel before start\n";
    NSString *path = MRWriteTemporaryFile([payload dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *URL = [[NSURL fileURLWithPath:path] absoluteString];

    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:URL method:@"GET"];

    __block NSUInteger completionCount = 0;
    __block MRHTTPResponse *received = nil;

    MRAPIRequestOperation *operation =
        [[MRAPIRequestOperation alloc] initWithRequest:request
                                            completion:^(MRHTTPResponse *response) {
            completionCount += 1;
            received = response;
        }];

    [operation cancel];
    [operation start];

    MRAssertTrue(operation.isFinished, @"cancelled operation is finished");
    MRAssertTrue(MRRunUntil(^BOOL { return completionCount > 0; }, 5.0),
                 @"cancelled completion delivered");
    MRAssertEqualIntegers(1, (NSInteger)completionCount,
                          @"cancelled completion invoked exactly once");
    MRAssertTrue(received != nil, @"cancelled response present");
    MRAssertTrue(received.transportError != nil, @"cancelled response has transport error");
    MRAssertEqualIntegers(NSURLErrorCancelled, received.transportError.code,
                          @"cancelled transport error code");
    MRAssertEqualIntegers(MRErrorKindCancelled, [MRError kindForError:received.transportError],
                          @"cancelled error kind");

    MRRemoveTemporaryFile(path);
}

static void MRBadURLTest(void) {
    MRHTTPRequest *request = [[MRHTTPRequest alloc] initWithURL:@"" method:@"GET"];

    __block NSUInteger completionCount = 0;
    __block MRHTTPResponse *received = nil;

    MRAPIRequestOperation *operation =
        [[MRAPIRequestOperation alloc] initWithRequest:request
                                            completion:^(MRHTTPResponse *response) {
            completionCount += 1;
            received = response;
        }];

    [operation start];

    MRAssertTrue(operation.isFinished, @"empty url operation finishes instead of hanging");
    MRAssertTrue(operation.response != nil, @"empty url response present");
    MRAssertTrue(operation.response.transportError != nil,
                 @"empty url response has transport error");
    MRAssertTrue(MRRunUntil(^BOOL { return completionCount > 0; }, 5.0),
                 @"empty url completion delivered");
    MRAssertEqualIntegers(1, (NSInteger)completionCount,
                          @"empty url completion invoked exactly once");
    MRAssertTrue(received.transportError != nil, @"empty url delivered transport error");
}

void MRRunAPIRequestOperationTests(void) {
    MRAssertEqualIntegers(1, [MRAPIRequestOperation apiQueue].maxConcurrentOperationCount,
                          @"api queue serializes requests");
    MRAssertEqualIntegers(2, [MRAPIRequestOperation catalogQueue].maxConcurrentOperationCount,
                          @"catalog queue allows two requests");

    MRRunFileURLTest();
    MRCancelBeforeStartTest();
    MRBadURLTest();
}
