//
//  main.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"

void MRRunMediaItemTests(void);
void MRRunDateTests(void);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MRTestBeginSuite(@"media item");
        MRRunMediaItemTests();

        MRTestBeginSuite(@"date");
        MRRunDateTests();

        NSUInteger failures = MRTestFailureCount();
        if (failures == 0) {
            printf("All tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%lu assertion(s) failed.\n", (unsigned long)failures);
        return 1;
    }
}
