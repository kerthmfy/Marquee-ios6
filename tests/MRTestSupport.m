//
//  MRTestSupport.m
//  Marquee tests
//

#import "MRTestSupport.h"
#import "MRTokenSession.h"

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

@implementation MRFakeClock {
    NSMutableArray *_scheduled;
    NSDate *_now;
    NSUInteger _sequence;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _now = [NSDate dateWithTimeIntervalSince1970:1793774400.0]; // fixed, no wall clock
        _scheduled = [NSMutableArray array];
        _sequence = 0;
    }
    return self;
}

- (NSDate *)now {
    @synchronized(self) {
        return _now;
    }
}

- (void)after:(NSTimeInterval)delay perform:(void (^)(void))block {
    if (block == nil) {
        return;
    }
    if (delay < 0.0) {
        delay = 0.0;
    }
    @synchronized(self) {
        NSDictionary *entry = @{
            @"fireDate": [_now dateByAddingTimeInterval:delay],
            @"sequence": @(_sequence),
            @"block": [block copy]
        };
        _sequence += 1;
        [_scheduled addObject:entry];
    }
}

- (void)advanceBy:(NSTimeInterval)seconds {
    if (seconds < 0.0) {
        seconds = 0.0;
    }

    @synchronized(self) {
        _now = [_now dateByAddingTimeInterval:seconds];
    }

    NSUInteger guard = 0;
    while (guard < 100000) {
        guard += 1;

        NSDictionary *due = nil;
        @synchronized(self) {
            for (NSDictionary *entry in _scheduled) {
                NSDate *fireDate = [entry objectForKey:@"fireDate"];
                if ([fireDate compare:_now] != NSOrderedDescending) {
                    if (due == nil ||
                        [fireDate compare:[due objectForKey:@"fireDate"]] == NSOrderedAscending ||
                        ([fireDate compare:[due objectForKey:@"fireDate"]] == NSOrderedSame &&
                         [[entry objectForKey:@"sequence"] unsignedIntegerValue] <
                         [[due objectForKey:@"sequence"] unsignedIntegerValue])) {
                        due = entry;
                    }
                }
            }
            if (due != nil) {
                [_scheduled removeObject:due];
            }
        }

        if (due == nil) {
            break;
        }

        @autoreleasepool {
            void (^block)(void) = [due objectForKey:@"block"];
            if (block != nil) {
                block();
            }
        }
    }
}

@end

@implementation MRMemoryTokenStore {
    MRTokenSession *_storedSession;
}

- (MRTokenSession *)session {
    @synchronized(self) {
        return _storedSession;
    }
}

- (MRTokenSession *)loadSession:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    return self.session;
}

- (BOOL)saveSession:(MRTokenSession *)session error:(NSError **)error {
    if (self.failSave) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MRMemoryTokenStore"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"Could not securely store your session" }];
        }
        return NO;
    }
    @synchronized(self) {
        _storedSession = session;
    }
    if (error != NULL) {
        *error = nil;
    }
    return YES;
}

- (BOOL)clearSession:(NSError **)error {
    @synchronized(self) {
        _storedSession = nil;
    }
    if (error != NULL) {
        *error = nil;
    }
    return YES;
}

@end

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
