//
//  MRDiagnostics.m
//  Marquee
//

#import "MRDiagnostics.h"
#import "MRDate.h"
#import "MRError.h"
#import "MRHTTPRequest.h"
#import "MRHTTPResponse.h"
#import "MRJSON.h"

static const NSUInteger MRDiagnosticsMaximumRecords = 50;
static NSString *const MRDiagnosticsFileName = @"diagnostics.json";

static NSArray *MRDiagnosticsSensitiveMarkers(void) {
    return @[ @"access_token", @"refresh_token", @"device_code",
              @"authorization", @"bearer " ];
}

static BOOL MRDiagnosticsStringContainsSensitiveText(NSString *string) {
    if (string.length == 0) {
        return NO;
    }
    NSString *lowercase = [string lowercaseString];
    for (NSString *marker in MRDiagnosticsSensitiveMarkers()) {
        if ([lowercase rangeOfString:marker].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSString *MRDiagnosticsSanitizedMessage(NSString *message) {
    if (message.length == 0) {
        return nil;
    }
    if (MRDiagnosticsStringContainsSensitiveText(message)) {
        return @"Request failed. Sensitive details omitted.";
    }
    return message;
}

static NSString *MRDiagnosticsPathFromURLString(NSString *URLString) {
    if (![URLString isKindOfClass:[NSString class]] || URLString.length == 0) {
        return nil;
    }

    NSURL *URL = [NSURL URLWithString:URLString];
    NSString *path = [URL path];
    if (path.length > 0) {
        return MRDiagnosticsStringContainsSensitiveText(path) ? @"/[redacted]" : path;
    }

    // Fallback for strings NSURL cannot parse. Strip the fragment and query,
    // then the scheme and host, leaving only the path.
    NSString *remainder = URLString;
    NSRange fragment = [remainder rangeOfString:@"#"];
    if (fragment.location != NSNotFound) {
        remainder = [remainder substringToIndex:fragment.location];
    }
    NSRange query = [remainder rangeOfString:@"?"];
    if (query.location != NSNotFound) {
        remainder = [remainder substringToIndex:query.location];
    }
    NSRange scheme = [remainder rangeOfString:@"://"];
    if (scheme.location != NSNotFound) {
        remainder = [remainder substringFromIndex:scheme.location + scheme.length];
        NSRange slash = [remainder rangeOfString:@"/"];
        if (slash.location != NSNotFound) {
            remainder = [remainder substringFromIndex:slash.location];
        } else {
            remainder = @"/";
        }
    }
    if (remainder.length == 0) {
        return nil;
    }
    return MRDiagnosticsStringContainsSensitiveText(remainder) ? @"/[redacted]" : remainder;
}

static NSDictionary *MRDiagnosticsSanitizedRecord(NSDictionary *raw) {
    if (![raw isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSMutableDictionary *record = [NSMutableDictionary dictionary];

    id timestamp = [raw objectForKey:@"timestamp"];
    if ([timestamp isKindOfClass:[NSString class]] && [(NSString *)timestamp length] > 0 &&
        [MRDate dateFromISOString:(NSString *)timestamp] != nil) {
        [record setObject:timestamp forKey:@"timestamp"];
    } else {
        return nil;
    }

    id method = [raw objectForKey:@"method"];
    if ([method isKindOfClass:[NSString class]]) {
        [record setObject:method forKey:@"method"];
    }

    id path = [raw objectForKey:@"path"];
    if ([path isKindOfClass:[NSString class]] && [(NSString *)path length] > 0) {
        [record setObject:MRDiagnosticsStringContainsSensitiveText(path) ? @"/[redacted]" : path
                   forKey:@"path"];
    }

    id status = [raw objectForKey:@"status"];
    if ([status isKindOfClass:[NSNumber class]]) {
        [record setObject:status forKey:@"status"];
    }

    id code = [raw objectForKey:@"code"];
    if ([code isKindOfClass:[NSString class]] && [(NSString *)code length] > 0 &&
        !MRDiagnosticsStringContainsSensitiveText(code)) {
        [record setObject:code forKey:@"code"];
    }

    id message = [raw objectForKey:@"message"];
    if ([message isKindOfClass:[NSString class]]) {
        NSString *sanitized = MRDiagnosticsSanitizedMessage(message);
        if (sanitized.length > 0) {
            [record setObject:sanitized forKey:@"message"];
        }
    }

    return record;
}

@interface MRDiagnostics ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSMutableArray *mutableRecords;
@end

@implementation MRDiagnostics

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _mutableRecords = [NSMutableArray array];
        [self load];
    }
    return self;
}

- (NSString *)storagePath {
    if (self.directory.length == 0) {
        return nil;
    }
    return [self.directory stringByAppendingPathComponent:MRDiagnosticsFileName];
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
    if (![object isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id raw in (NSArray *)object) {
        NSDictionary *record = MRDiagnosticsSanitizedRecord(raw);
        if (record != nil) {
            [self.mutableRecords addObject:record];
        }
        if (self.mutableRecords.count >= MRDiagnosticsMaximumRecords) {
            break;
        }
    }
}

- (BOOL)ensureDirectory {
    if (self.directory.length == 0) {
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([manager fileExistsAtPath:self.directory isDirectory:&isDirectory] && isDirectory) {
        return YES;
    }
    return [manager createDirectoryAtPath:self.directory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:NULL];
}

- (void)save {
    NSString *path = [self storagePath];
    if (path == nil || ![self ensureDirectory]) {
        return;
    }
    NSData *data = [MRJSON dataFromObject:self.mutableRecords error:NULL];
    if (data != nil) {
        [data writeToFile:path atomically:YES];
    }
}

- (NSArray *)records {
    @synchronized(self) {
        return [self.mutableRecords copy];
    }
}

- (void)recordError:(NSError *)error
            request:(MRHTTPRequest *)request
           response:(MRHTTPResponse *)response {
    @synchronized(self) {
        NSMutableDictionary *record = [NSMutableDictionary dictionary];

        NSString *timestamp = [MRDate isoStringFromDate:[NSDate date]];
        if (timestamp.length > 0) {
            [record setObject:timestamp forKey:@"timestamp"];
        }

        NSString *method = request.method;
        [record setObject:(method.length > 0 ? method : @"") forKey:@"method"];

        NSString *path = MRDiagnosticsPathFromURLString(request.URL);
        if (path.length > 0) {
            [record setObject:path forKey:@"path"];
        }

        [record setObject:@(response != nil ? response.statusCode : 0) forKey:@"status"];

        id code = [error.userInfo objectForKey:MRErrorCodeKey];
        if ([code isKindOfClass:[NSString class]] && [(NSString *)code length] > 0 &&
            !MRDiagnosticsStringContainsSensitiveText((NSString *)code)) {
            [record setObject:code forKey:@"code"];
        }

        NSString *message = MRDiagnosticsSanitizedMessage([error localizedDescription]);
        if (message.length > 0) {
            [record setObject:message forKey:@"message"];
        }

        [self.mutableRecords insertObject:record atIndex:0];
        while (self.mutableRecords.count > MRDiagnosticsMaximumRecords) {
            [self.mutableRecords removeLastObject];
        }
        [self save];
    }
}

@end
