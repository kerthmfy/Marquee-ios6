//
//  MRQuotaTracker.m
//  Marquee
//

#import "MRQuotaTracker.h"
#import "MRDate.h"
#import "MRJSON.h"

#import <dispatch/dispatch.h>

NSString *const MRQuotaDidChangeNotification = @"MRQuotaDidChangeNotification";

static NSString *MRQuotaTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        if (value != nil) {
            value = [value description];
        } else {
            return nil;
        }
    }
    return [(NSString *)value stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *MRQuotaHeaderValue(NSDictionary *headers, NSString *name) {
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] &&
            [(NSString *)key caseInsensitiveCompare:name] == NSOrderedSame) {
            return MRQuotaTrimmedString([headers objectForKey:key]);
        }
    }
    return nil;
}

static BOOL MRQuotaParseInteger(NSString *string, NSInteger *outValue) {
    if (string.length == 0 || outValue == NULL) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:string];
    NSInteger value = 0;
    if (![scanner scanInteger:&value] || !scanner.isAtEnd) {
        return NO;
    }
    if (value < 0) {
        return NO;
    }
    *outValue = value;
    return YES;
}

// Retry-After is either delta-seconds or an HTTP date. Only the numeric form is
// interpretable without a date parser in this API context, and the brief
// requires that it never be treated as an absolute timestamp.
static BOOL MRQuotaParseSeconds(NSString *string, NSTimeInterval *outValue) {
    if (string.length == 0 || outValue == NULL) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:string];
    double seconds = 0.0;
    if (![scanner scanDouble:&seconds] || !scanner.isAtEnd) {
        return NO;
    }
    if (seconds < 0.0) {
        seconds = 0.0;
    }
    *outValue = seconds;
    return YES;
}

@interface MRQuotaTracker ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, assign) NSInteger accountID;
@property (nonatomic, assign) NSInteger limit;
@property (nonatomic, assign) NSInteger remaining;
@property (nonatomic, strong) NSDate *resetAt;
@end

@implementation MRQuotaTracker

- (instancetype)initWithDirectory:(NSString *)directory accountID:(NSInteger)accountID {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _accountID = accountID;
        _limit = -1;
        _remaining = -1;
        _resetAt = nil;
        [self load];
    }
    return self;
}

- (NSString *)storagePath {
    if (self.directory.length == 0) {
        return nil;
    }
    NSString *name = [NSString stringWithFormat:@"quota-%ld.json", (long)self.accountID];
    return [self.directory stringByAppendingPathComponent:name];
}

- (void)load {
    NSString *path = [self storagePath];
    if (path == nil) {
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return;
    }

    id object = [MRJSON objectFromData:data error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *stored = (NSDictionary *)object;

    id storedAccountID = [stored objectForKey:@"accountID"];
    if (![storedAccountID isKindOfClass:[NSNumber class]] ||
        [storedAccountID integerValue] != self.accountID) {
        return;
    }

    id limitValue = [stored objectForKey:@"limit"];
    if ([limitValue isKindOfClass:[NSNumber class]] && [limitValue integerValue] >= 0) {
        self.limit = [limitValue integerValue];
    }
    id remainingValue = [stored objectForKey:@"remaining"];
    if ([remainingValue isKindOfClass:[NSNumber class]] && [remainingValue integerValue] >= 0) {
        self.remaining = [remainingValue integerValue];
    }
    id resetValue = [stored objectForKey:@"resetAt"];
    if ([resetValue isKindOfClass:[NSString class]]) {
        self.resetAt = [MRDate dateFromISOString:(NSString *)resetValue];
    }
}

- (void)save {
    NSString *path = [self storagePath];
    if (path == nil) {
        return;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:self.directory isDirectory:&isDirectory] || !isDirectory) {
        [manager createDirectoryAtPath:self.directory
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
    }

    NSMutableDictionary *stored = [NSMutableDictionary dictionary];
    [stored setObject:@1 forKey:@"schema"];
    [stored setObject:@(self.accountID) forKey:@"accountID"];
    [stored setObject:@(self.limit) forKey:@"limit"];
    [stored setObject:@(self.remaining) forKey:@"remaining"];
    if (self.resetAt != nil) {
        NSString *resetString = [MRDate isoStringFromDate:self.resetAt];
        if (resetString.length > 0) {
            [stored setObject:resetString forKey:@"resetAt"];
        }
    }

    NSData *data = [MRJSON dataFromObject:stored error:NULL];
    if (data != nil) {
        [data writeToFile:path atomically:YES];
    }
}

- (void)postChangeNotification {
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MRQuotaDidChangeNotification
                                                            object:self];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MRQuotaDidChangeNotification
                                                            object:self];
    });
}

- (void)updateFromHeaders:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]]) {
        return;
    }

    // Concurrent callers may arrive from background queues. The whole
    // read-modify-persist-notify sequence must be atomic so state cannot
    // interleave and an unchanged update cannot post a second notification.
    @synchronized(self) {
        NSInteger newLimit = self.limit;
        NSInteger newRemaining = self.remaining;
        NSDate *newResetAt = self.resetAt;
        BOOL changed = NO;

        NSInteger parsed = 0;
        if (MRQuotaParseInteger(MRQuotaHeaderValue(headers, @"X-RateLimit-Limit"), &parsed)) {
            if (parsed != newLimit) {
                changed = YES;
            }
            newLimit = parsed;
        }
        if (MRQuotaParseInteger(MRQuotaHeaderValue(headers, @"X-RateLimit-Remaining"), &parsed)) {
            if (parsed != newRemaining) {
                changed = YES;
            }
            newRemaining = parsed;
        }

        NSTimeInterval seconds = 0.0;
        if (MRQuotaParseSeconds(MRQuotaHeaderValue(headers, @"Retry-After"), &seconds)) {
            NSDate *reset = [NSDate dateWithTimeIntervalSinceNow:seconds];
            if (newResetAt == nil || ![newResetAt isEqualToDate:reset]) {
                changed = YES;
            }
            newResetAt = reset;
        }

        if (!changed) {
            return;
        }

        self.limit = newLimit;
        self.remaining = newRemaining;
        self.resetAt = newResetAt;
        [self save];
        [self postChangeNotification];
    }
}

@end
