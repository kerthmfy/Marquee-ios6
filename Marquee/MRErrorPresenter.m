//
//  MRErrorPresenter.m
//  Marquee
//

#import "MRErrorPresenter.h"
#import "MRError.h"

@implementation MRErrorPresenter

+ (NSString *)resetCountdownForDate:(NSDate *)resetDate {
    if (resetDate == nil) {
        return @"Daily limit reached; try again after midnight ET.";
    }
    NSTimeInterval interval = [resetDate timeIntervalSinceNow];
    if (interval <= 0.0) {
        return @"Daily limit reached; try again shortly.";
    }
    NSInteger totalMinutes = (NSInteger)floor(interval / 60.0);
    NSInteger hours = totalMinutes / 60;
    NSInteger minutes = totalMinutes % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:
            @"Daily limit reached; resets in %ldh %ldm", (long)hours, (long)minutes];
    }
    return [NSString stringWithFormat:
        @"Daily limit reached; resets in %ldm", (long)minutes];
}

+ (NSString *)messageForError:(NSError *)error resetDate:(NSDate *)resetDate {
    if (error == nil) {
        return nil;
    }
    switch ([MRError kindForError:error]) {
        case MRErrorKindCancelled:
            return nil;
        case MRErrorKindOffline:
            return @"Simkl is unreachable. Check your connection.";
        case MRErrorKindAuthExpired:
            return @"Session expired. Reconnect to sync.";
        case MRErrorKindClientRejected:
            return @"Marquee couldn't identify itself to Simkl. Check Diagnostics for configuration.";
        case MRErrorKindRateLimitedBurst:
            return @"Simkl is busy. Try again in a moment.";
        case MRErrorKindDailyLimit:
            return [self resetCountdownForDate:resetDate];
        case MRErrorKindWriteLocked:
            return @"Simkl is still saving your last change";
        case MRErrorKindServer:
            return @"Simkl is having trouble right now. Try again later.";
        case MRErrorKindNotFound:
        case MRErrorKindTooLarge:
        case MRErrorKindParse:
        case MRErrorKindUnknown:
        default:
            return [MRError messageForKind:[MRError kindForError:error]];
    }
}

+ (MRBannerStyle)styleForError:(NSError *)error {
    if (error == nil) {
        return MRBannerStyleNeutral;
    }
    switch ([MRError kindForError:error]) {
        case MRErrorKindOffline:
        case MRErrorKindRateLimitedBurst:
        case MRErrorKindServer:
        case MRErrorKindUnknown:
            return MRBannerStyleWarning;
        case MRErrorKindWriteLocked:
            return MRBannerStylePending;
        case MRErrorKindAuthExpired:
        case MRErrorKindClientRejected:
        case MRErrorKindDailyLimit:
        case MRErrorKindNotFound:
        case MRErrorKindTooLarge:
        case MRErrorKindParse:
            return MRBannerStyleError;
        case MRErrorKindCancelled:
        default:
            return MRBannerStyleNeutral;
    }
}

+ (BOOL)showsRetryForError:(NSError *)error {
    if (error == nil) {
        return NO;
    }
    switch ([MRError kindForError:error]) {
        case MRErrorKindOffline:
        case MRErrorKindRateLimitedBurst:
        case MRErrorKindServer:
        case MRErrorKindUnknown:
            return YES;
        default:
            return NO;
    }
}

@end
