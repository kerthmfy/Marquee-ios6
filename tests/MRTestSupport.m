//
//  MRTestSupport.m
//  Marquee tests
//

#import "MRTestSupport.h"

static NSUInteger MRFailureCount = 0;
static NSString *MRCurrentSuite = @"";

static NSString *MRDescribeObject(id object) {
    if (object == nil) {
        return @"(nil)";
    }
    return [object description];
}

static void MRRecordFailure(NSString *message, NSString *detail) {
    MRFailureCount += 1;
    if (detail.length > 0) {
        fprintf(stderr, "FAIL [%s] %s: %s\n",
                [MRCurrentSuite UTF8String],
                [message UTF8String],
                [detail UTF8String]);
    } else {
        fprintf(stderr, "FAIL [%s] %s\n",
                [MRCurrentSuite UTF8String],
                [message UTF8String]);
    }
}

void MRTestBeginSuite(NSString *name) {
    MRCurrentSuite = [name copy] ?: @"";
}

NSUInteger MRTestFailureCount(void) {
    return MRFailureCount;
}

void MRAssertTrue(BOOL condition, NSString *message) {
    if (!condition) {
        MRRecordFailure(message, @"expected true");
    }
}

void MRAssertEqualObjects(id expected, id actual, NSString *message) {
    BOOL equal = (expected == actual);
    if (!equal) {
        equal = (expected != nil && actual != nil && [expected isEqual:actual]);
    }
    if (!equal) {
        NSString *detail = [NSString stringWithFormat:@"expected %@, got %@",
                            MRDescribeObject(expected), MRDescribeObject(actual)];
        MRRecordFailure(message, detail);
    }
}

void MRAssertEqualIntegers(NSInteger expected, NSInteger actual, NSString *message) {
    if (expected != actual) {
        NSString *detail = [NSString stringWithFormat:@"expected %ld, got %ld",
                            (long)expected, (long)actual];
        MRRecordFailure(message, detail);
    }
}

BOOL MRRunUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    if (condition == nil) {
        return YES;
    }
    if (condition()) {
        return YES;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        if (condition()) {
            return YES;
        }
    }
    return condition();
}

NSDictionary *MRFixture(NSString *name) {
    NSString *file = name;
    if (![[file pathExtension] isEqualToString:@"json"]) {
        file = [file stringByAppendingPathExtension:@"json"];
    }
    NSString *path = [@"tests/fixtures" stringByAppendingPathComponent:file];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        MRRecordFailure([NSString stringWithFormat:@"fixture %@", name],
                        [NSString stringWithFormat:@"could not read %@", path]);
        return nil;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (object == nil) {
        MRRecordFailure([NSString stringWithFormat:@"fixture %@", name],
                        [error localizedDescription]);
        return nil;
    }
    return (NSDictionary *)object;
}
