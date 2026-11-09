//
//  main.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"

void MRRunMediaItemTests(void);
void MRRunDateTests(void);
void MRRunURLBuilderTests(void);
void MRRunErrorTests(void);
void MRRunAPIRequestOperationTests(void);
void MRRunResponseCacheTests(void);
void MRRunQuotaTrackerTests(void);
void MRRunDiagnosticsTests(void);
void MRRunAPIClientPublicTests(void);
void MRRunPublicFeedBuilderTests(void);
void MRRunDeviceFlowTests(void);
void MRRunTokenStoreTests(void);
void MRRunMRLayoutTests(void);
void MRRunStorageTests(void);
void MRRunMRLibraryStoreTests(void);
void MRRunMRSyncInitialTests(void);
void MRRunLibraryFilterTests(void);
void MRRunRelatedItemTests(void);
void MRRunOutboxTests(void);
void MRRunWriteServiceTests(void);
void MRRunWriteReconciliationTests(void);
void MRRunPreferencesStoreTests(void);
void MRRunTasteProfileTests(void);
void MRRunRecommendationCandidateTests(void);
void MRRunRecommendationRowsTests(void);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MRTestBeginSuite(@"media item");
        MRRunMediaItemTests();

        MRTestBeginSuite(@"date");
        MRRunDateTests();

        MRTestBeginSuite(@"url builder");
        MRRunURLBuilderTests();

        MRTestBeginSuite(@"error");
        MRRunErrorTests();

        MRTestBeginSuite(@"api request operation");
        MRRunAPIRequestOperationTests();

        MRTestBeginSuite(@"response cache");
        MRRunResponseCacheTests();

        MRTestBeginSuite(@"quota tracker");
        MRRunQuotaTrackerTests();

        MRTestBeginSuite(@"diagnostics");
        MRRunDiagnosticsTests();

        MRTestBeginSuite(@"api client public");
        MRRunAPIClientPublicTests();

        MRTestBeginSuite(@"public feed builder");
        MRRunPublicFeedBuilderTests();

        MRTestBeginSuite(@"token store");
        MRRunTokenStoreTests();

        MRTestBeginSuite(@"device flow");
        MRRunDeviceFlowTests();

        MRTestBeginSuite(@"layout");
        MRRunMRLayoutTests();

        MRTestBeginSuite(@"storage");
        MRRunStorageTests();

        MRTestBeginSuite(@"library store");
        MRRunMRLibraryStoreTests();

        MRTestBeginSuite(@"sync initial");
        MRRunMRSyncInitialTests();

        MRTestBeginSuite(@"library filter");
        MRRunLibraryFilterTests();

        MRTestBeginSuite(@"related item");
        MRRunRelatedItemTests();

        MRTestBeginSuite(@"outbox");
        MRRunOutboxTests();

        MRTestBeginSuite(@"write service");
        MRRunWriteServiceTests();

        MRTestBeginSuite(@"write reconciliation");
        MRRunWriteReconciliationTests();

        MRTestBeginSuite(@"preferences store");
        MRRunPreferencesStoreTests();

        MRTestBeginSuite(@"taste profile");
        MRRunTasteProfileTests();

        MRTestBeginSuite(@"recommendation candidates");
        MRRunRecommendationCandidateTests();

        MRTestBeginSuite(@"recommendation rows");
        MRRunRecommendationRowsTests();

        NSUInteger failures = MRTestFailureCount();
        if (failures == 0) {
            printf("All tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%lu assertion(s) failed.\n", (unsigned long)failures);
        return 1;
    }
}
