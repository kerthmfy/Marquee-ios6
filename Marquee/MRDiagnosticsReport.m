//
//  MRDiagnosticsReport.m
//  Marquee
//

#import "MRDiagnosticsReport.h"

static NSString *const MRDiagnosticsReportRedaction = @"[redacted]";

static NSArray *MRReportSensitiveMarkers(void) {
    return @[ @"access_token", @"refresh_token", @"device_code",
              @"authorization", @"bearer " ];
}

static BOOL MRReportContainsSensitiveText(NSString *string) {
    if (string.length == 0) {
        return NO;
    }
    NSString *lowercase = [string lowercaseString];
    for (NSString *marker in MRReportSensitiveMarkers()) {
        if ([lowercase rangeOfString:marker].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSString *MRReportSanitizedString(NSString *string) {
    if (string.length == 0) {
        return nil;
    }
    if (MRReportContainsSensitiveText(string)) {
        return MRDiagnosticsReportRedaction;
    }
    return string;
}

static NSString *MRReportString(id value) {
    if (value == nil || value == [NSNull null]) {
        return nil;
    }
    NSString *string = nil;
    if ([value isKindOfClass:[NSString class]]) {
        string = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        string = [(NSNumber *)value stringValue];
    } else if ([value isKindOfClass:[NSDate class]]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
        string = [formatter stringFromDate:(NSDate *)value];
    } else {
        string = [value description];
    }
    return MRReportSanitizedString(string);
}

static NSInteger MRReportInteger(id value, NSInteger fallback) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value integerValue];
    }
    return fallback;
}

static NSString *MRReportByteCount(unsigned long long bytes) {
    if (bytes >= 1024ULL * 1024ULL) {
        double megabytes = (double)bytes / (1024.0 * 1024.0);
        return [NSString stringWithFormat:@"%.1f MB", megabytes];
    }
    if (bytes >= 1024ULL) {
        double kilobytes = (double)bytes / 1024.0;
        return [NSString stringWithFormat:@"%.0f KB", kilobytes];
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

static void MRReportAppendLine(NSMutableArray *lines, NSString *label, NSString *value) {
    if (value.length == 0) {
        return;
    }
    [lines addObject:[NSString stringWithFormat:@"%@: %@", label, value]];
}

static NSString *MRReportErrorLine(NSDictionary *error) {
    if (![error isKindOfClass:[NSDictionary class]]) {
        return MRReportSanitizedString([error description]);
    }

    NSString *timestamp = MRReportString([error objectForKey:@"timestamp"]);
    NSString *method = MRReportString([error objectForKey:@"method"]);
    NSString *path = MRReportString([error objectForKey:@"path"]);
    NSString *status = MRReportString([error objectForKey:@"status"]);
    NSString *code = MRReportString([error objectForKey:@"code"]);
    NSString *message = MRReportString([error objectForKey:@"message"]);

    NSMutableString *line = [NSMutableString stringWithString:@"  "];
    if (timestamp.length > 0) {
        [line appendFormat:@"%@ ", timestamp];
    }
    if (method.length > 0) {
        [line appendFormat:@"%@ ", method];
    }
    if (path.length > 0) {
        [line appendString:path];
    }
    if (status.length > 0) {
        [line appendFormat:@" -> %@", status];
    }
    if (code.length > 0) {
        [line appendFormat:@" (%@)", code];
    }
    if (message.length > 0) {
        [line appendFormat:@" %@", message];
    }
    return line;
}

@implementation MRDiagnosticsReport

+ (NSString *)reportWithFields:(NSDictionary *)fields {
    NSDictionary *values = [fields isKindOfClass:[NSDictionary class]] ? fields : @{};
    NSMutableArray *lines = [NSMutableArray arrayWithObject:@"Marquee Diagnostics"];

    NSString *version = MRReportString([values objectForKey:@"appVersion"]);
    NSString *build = MRReportString([values objectForKey:@"build"]);
    if (version.length > 0 && build.length > 0) {
        MRReportAppendLine(lines, @"App", [NSString stringWithFormat:@"%@ (%@)", version, build]);
    } else {
        MRReportAppendLine(lines, @"App", version.length > 0 ? version : build);
    }

    MRReportAppendLine(lines, @"iOS", MRReportString([values objectForKey:@"osVersion"]));
    MRReportAppendLine(lines, @"Device", MRReportString([values objectForKey:@"deviceModel"]));

    NSString *accountName = MRReportString([values objectForKey:@"accountName"]);
    NSInteger accountID = MRReportInteger([values objectForKey:@"accountID"], 0);
    if (accountName.length > 0 && accountID > 0) {
        MRReportAppendLine(lines, @"Account",
                           [NSString stringWithFormat:@"%@ (#%ld)",
                            accountName, (long)accountID]);
    } else if (accountName.length > 0) {
        MRReportAppendLine(lines, @"Account", accountName);
    } else if (accountID > 0) {
        MRReportAppendLine(lines, @"Account",
                           [NSString stringWithFormat:@"#%ld", (long)accountID]);
    }

    MRReportAppendLine(lines, @"Last sync attempt",
                       MRReportString([values objectForKey:@"lastSyncAttempt"]));
    MRReportAppendLine(lines, @"Last sync result",
                       MRReportString([values objectForKey:@"lastSyncResult"]));

    id pending = [values objectForKey:@"pendingCount"];
    if (pending != nil) {
        MRReportAppendLine(lines, @"Pending writes",
                           [NSString stringWithFormat:@"%ld",
                            (long)MRReportInteger(pending, 0)]);
    }

    id requests = [values objectForKey:@"requestsToday"];
    if (requests != nil) {
        MRReportAppendLine(lines, @"Today's requests",
                           [NSString stringWithFormat:@"%ld",
                            (long)MRReportInteger(requests, 0)]);
    }

    NSInteger limit = MRReportInteger([values objectForKey:@"quotaLimit"], -1);
    NSInteger remaining = MRReportInteger([values objectForKey:@"quotaRemaining"], -1);
    if (limit >= 0) {
        MRReportAppendLine(lines, @"Quota limit",
                           [NSString stringWithFormat:@"%ld", (long)limit]);
    }
    if (remaining >= 0) {
        MRReportAppendLine(lines, @"Quota remaining",
                           [NSString stringWithFormat:@"%ld", (long)remaining]);
    }
    MRReportAppendLine(lines, @"Quota reset",
                       MRReportString([values objectForKey:@"quotaResetAt"]));

    id cacheBytesValue = [values objectForKey:@"cacheBytes"];
    if (cacheBytesValue != nil) {
        unsigned long long cacheBytes = 0;
        if ([cacheBytesValue isKindOfClass:[NSNumber class]]) {
            cacheBytes = [(NSNumber *)cacheBytesValue unsignedLongLongValue];
        } else {
            cacheBytes = (unsigned long long)MRReportInteger(cacheBytesValue, 0);
        }
        MRReportAppendLine(lines, @"Cache", MRReportByteCount(cacheBytes));
    }

    id errors = [values objectForKey:@"errors"];
    if ([errors isKindOfClass:[NSArray class]] && [(NSArray *)errors count] > 0) {
        [lines addObject:@"Recent errors:"];
        NSUInteger count = 0;
        for (id error in (NSArray *)errors) {
            if (count >= 20) {
                break;
            }
            NSString *line = MRReportErrorLine(error);
            if (line.length > 0) {
                [lines addObject:line];
            }
            count += 1;
        }
    }

    return [lines componentsJoinedByString:@"\n"];
}

@end
