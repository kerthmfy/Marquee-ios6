//
//  MRErrorPresenterTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRError.h"
#import "MRErrorPresenter.h"

static void MRRunOfflinePresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindOffline];
    MRAssertEqualObjects(@"Simkl is unreachable. Check your connection.",
                         [MRErrorPresenter messageForError:error resetDate:nil],
                         @"offline uses the connection message");
    MRAssertEqualIntegers(MRBannerStyleWarning,
                          [MRErrorPresenter styleForError:error],
                          @"offline is an amber warning");
    MRAssertTrue([MRErrorPresenter showsRetryForError:error],
                 @"offline offers Retry");
}

static void MRRunDailyLimitPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindDailyLimit];
    NSDate *reset = [NSDate dateWithTimeIntervalSinceNow:6.0 * 3600.0 +
                      12.0 * 60.0 + 30.0];
    NSString *message = [MRErrorPresenter messageForError:error resetDate:reset];
    MRAssertTrue([message rangeOfString:@"Daily limit reached"].location != NSNotFound,
                 @"daily limit names the limit");
    MRAssertTrue([message rangeOfString:@"6h 12m"].location != NSNotFound,
                 @"daily limit includes the reset interval");
    MRAssertEqualIntegers(MRBannerStyleError,
                          [MRErrorPresenter styleForError:error],
                          @"daily limit is red");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:error],
                 @"daily limit does not offer a useless Retry");

    NSString *withoutDate = [MRErrorPresenter messageForError:error resetDate:nil];
    MRAssertTrue([withoutDate rangeOfString:@"Daily limit reached"].location != NSNotFound,
                 @"daily limit still names the limit without a reset date");
    MRAssertTrue([withoutDate rangeOfString:@"6h"].location == NSNotFound,
                 @"a missing reset date invents no countdown");
}

static void MRRunWriteLockedPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindWriteLocked];
    MRAssertEqualObjects(@"Simkl is still saving your last change",
                         [MRErrorPresenter messageForError:error resetDate:nil],
                         @"write lock uses the short automatic-retry copy");
    MRAssertEqualIntegers(MRBannerStylePending,
                          [MRErrorPresenter styleForError:error],
                          @"write lock is blue-gray, not red");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:error],
                 @"write lock retries automatically without a Retry button");
}

static void MRRunAuthExpiredPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindAuthExpired];
    MRAssertEqualObjects(@"Session expired. Reconnect to sync.",
                         [MRErrorPresenter messageForError:error resetDate:nil],
                         @"auth expiry asks the user to reconnect");
    MRAssertEqualIntegers(MRBannerStyleError,
                          [MRErrorPresenter styleForError:error],
                          @"auth expiry is red");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:error],
                 @"auth expiry needs reconnect, not a request retry");
}

static void MRRunClientRejectedPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindClientRejected];
    NSString *message = [MRErrorPresenter messageForError:error resetDate:nil];
    MRAssertTrue([message rangeOfString:@"configuration"].location != NSNotFound ||
                 [message rangeOfString:@"Configuration"].location != NSNotFound,
                 @"client rejection names the configuration problem");
    MRAssertTrue([message rangeOfString:@"Diagnostics"].location != NSNotFound,
                 @"client rejection points to Diagnostics");
    MRAssertEqualIntegers(MRBannerStyleError,
                          [MRErrorPresenter styleForError:error],
                          @"client rejection is red");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:error],
                 @"client rejection is not retryable");
}

static void MRRunServerPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindServer];
    NSString *message = [MRErrorPresenter messageForError:error resetDate:nil];
    MRAssertTrue([message rangeOfString:@"Simkl is having trouble"].location != NSNotFound,
                 @"server errors use the trouble copy");
    MRAssertEqualIntegers(MRBannerStyleWarning,
                          [MRErrorPresenter styleForError:error],
                          @"server errors are amber");
    MRAssertTrue([MRErrorPresenter showsRetryForError:error],
                 @"server errors offer Retry");
}

static void MRRunBurstPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindRateLimitedBurst];
    MRAssertEqualObjects([MRError messageForKind:MRErrorKindRateLimitedBurst],
                         [MRErrorPresenter messageForError:error resetDate:nil],
                         @"burst limiting keeps the short-wait message");
    MRAssertEqualIntegers(MRBannerStyleWarning,
                          [MRErrorPresenter styleForError:error],
                          @"burst limiting is amber");
    MRAssertTrue([MRErrorPresenter showsRetryForError:error],
                 @"burst limiting offers Retry");
}

static void MRRunCancelledPresentationTest(void) {
    NSError *error = [MRError errorWithKind:MRErrorKindCancelled];
    MRAssertTrue([MRErrorPresenter messageForError:error resetDate:nil] == nil,
                 @"a cancelled request shows no error");
    MRAssertEqualIntegers(MRBannerStyleNeutral,
                          [MRErrorPresenter styleForError:error],
                          @"cancelled uses the neutral style");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:error],
                 @"cancelled has no Retry");
}

static void MRRunOtherErrorsPresentationTest(void) {
    NSError *notFound = [MRError errorWithKind:MRErrorKindNotFound];
    MRAssertEqualObjects([MRError messageForKind:MRErrorKindNotFound],
                         [MRErrorPresenter messageForError:notFound resetDate:nil],
                         @"not found keeps its title-specific copy");
    MRAssertEqualIntegers(MRBannerStyleError,
                          [MRErrorPresenter styleForError:notFound],
                          @"not found is red");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:notFound],
                 @"not found is not retryable");

    NSError *tooLarge = [MRError errorWithKind:MRErrorKindTooLarge];
    MRAssertEqualObjects([MRError messageForKind:MRErrorKindTooLarge],
                         [MRErrorPresenter messageForError:tooLarge resetDate:nil],
                         @"too large keeps the split message");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:tooLarge],
                 @"too large retries by splitting, not a Retry button");

    NSError *parse = [MRError errorWithKind:MRErrorKindParse];
    MRAssertEqualObjects([MRError messageForKind:MRErrorKindParse],
                         [MRErrorPresenter messageForError:parse resetDate:nil],
                         @"parse errors keep the read-failure copy");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:parse],
                 @"parse errors are not retryable");

    NSError *unknown = [MRError errorWithKind:MRErrorKindUnknown];
    MRAssertTrue([MRErrorPresenter messageForError:unknown resetDate:nil] != nil,
                 @"unknown errors still show a message");
    MRAssertEqualIntegers(MRBannerStyleWarning,
                          [MRErrorPresenter styleForError:unknown],
                          @"unknown errors are amber");
}

static void MRRunNilErrorPresentationTest(void) {
    MRAssertTrue([MRErrorPresenter messageForError:nil resetDate:nil] == nil,
                 @"a nil error shows nothing");
    MRAssertEqualIntegers(MRBannerStyleNeutral,
                          [MRErrorPresenter styleForError:nil],
                          @"a nil error uses the neutral style");
    MRAssertTrue(![MRErrorPresenter showsRetryForError:nil],
                 @"a nil error has no Retry");
}

void MRRunErrorPresenterTests(void) {
    MRRunOfflinePresentationTest();
    MRRunDailyLimitPresentationTest();
    MRRunWriteLockedPresentationTest();
    MRRunAuthExpiredPresentationTest();
    MRRunClientRejectedPresentationTest();
    MRRunServerPresentationTest();
    MRRunBurstPresentationTest();
    MRRunCancelledPresentationTest();
    MRRunOtherErrorsPresentationTest();
    MRRunNilErrorPresentationTest();
}
