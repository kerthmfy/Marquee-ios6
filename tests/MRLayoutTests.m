//
//  MRLayoutTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRLayout.h"

void MRRunMRLayoutTests(void) {
    MRAssertEqualIntegers(MRDeviceClassPhone,
                          [MRLayout deviceClassForIdiom:0], @"phone idiom");
    MRAssertEqualIntegers(MRDeviceClassTablet,
                          [MRLayout deviceClassForIdiom:1], @"pad idiom");
    MRAssertEqualIntegers(MRDeviceClassPhone,
                          [MRLayout deviceClassForIdiom:2], @"unknown idiom is phone");

    MRAssertEqualIntegers(MRLayoutOrientationPortrait,
        [MRLayout orientationForSize:CGSizeMake(320.0, 480.0)], @"320x480 portrait");
    MRAssertEqualIntegers(MRLayoutOrientationLandscape,
        [MRLayout orientationForSize:CGSizeMake(480.0, 320.0)], @"480x320 landscape");
    MRAssertEqualIntegers(MRLayoutOrientationPortrait,
        [MRLayout orientationForSize:CGSizeMake(768.0, 1024.0)], @"768x1024 portrait");
    MRAssertEqualIntegers(MRLayoutOrientationLandscape,
        [MRLayout orientationForSize:CGSizeMake(1024.0, 768.0)], @"1024x768 landscape");

    MRAssertTrue([MRLayout heroSideInsetForDeviceClass:MRDeviceClassPhone] == 8.0,
                 @"phone hero inset is 8");
    MRAssertTrue([MRLayout rowSideInsetForDeviceClass:MRDeviceClassPhone] == 12.0,
                 @"phone row inset is 12");
    MRAssertTrue([MRLayout posterCardWidthForDeviceClass:MRDeviceClassPhone] == 100.0,
                 @"phone card width is 100");
    MRAssertTrue([MRLayout posterCardImageHeightForDeviceClass:MRDeviceClassPhone] == 150.0,
                 @"phone poster height is 150");
    MRAssertTrue([MRLayout posterCardHeightForDeviceClass:MRDeviceClassPhone] == 210.0,
                 @"phone card height is 210");
    MRAssertTrue([MRLayout posterCardGapForDeviceClass:MRDeviceClassPhone] == 8.0,
                 @"phone card gap is 8");
    MRAssertTrue([MRLayout posterRowHeightForDeviceClass:MRDeviceClassPhone] == 210.0,
                 @"phone row height is 210");
    MRAssertTrue([MRLayout rowHeaderHeightForDeviceClass:MRDeviceClassPhone] == 32.0,
                 @"phone row header is 32");
    MRAssertTrue([MRLayout contentMaxWidthForDeviceClass:MRDeviceClassPhone] == 320.0,
                 @"phone content width is 320");
    MRAssertTrue([MRLayout modalContentMaxWidthForDeviceClass:MRDeviceClassPhone] == 320.0,
                 @"phone modal width is 320");

    MRAssertTrue([MRLayout heroSideInsetForDeviceClass:MRDeviceClassTablet] == 16.0,
                 @"pad hero inset is 16");
    MRAssertTrue([MRLayout rowSideInsetForDeviceClass:MRDeviceClassTablet] == 16.0,
                 @"pad row inset is 16");
    MRAssertTrue([MRLayout posterCardWidthForDeviceClass:MRDeviceClassTablet] == 150.0,
                 @"pad card width is 150");
    MRAssertTrue([MRLayout posterCardImageHeightForDeviceClass:MRDeviceClassTablet] == 225.0,
                 @"pad poster height is 225");
    MRAssertTrue([MRLayout posterCardHeightForDeviceClass:MRDeviceClassTablet] == 315.0,
                 @"pad card height is 315");
    MRAssertTrue([MRLayout posterCardGapForDeviceClass:MRDeviceClassTablet] == 12.0,
                 @"pad card gap is 12");
    MRAssertTrue([MRLayout posterRowHeightForDeviceClass:MRDeviceClassTablet] == 315.0,
                 @"pad row height is 315");
    MRAssertTrue([MRLayout rowHeaderHeightForDeviceClass:MRDeviceClassTablet] == 40.0,
                 @"pad row header is 40");
    MRAssertTrue([MRLayout contentMaxWidthForDeviceClass:MRDeviceClassTablet] == 720.0,
                 @"pad content width is 720");
    MRAssertTrue([MRLayout modalContentMaxWidthForDeviceClass:MRDeviceClassTablet] == 540.0,
                 @"pad modal width is 540");

    MRAssertTrue([MRLayout heroHeightForDeviceClass:MRDeviceClassPhone
                                        orientation:MRLayoutOrientationPortrait
                                    availableHeight:480.0] == 180.0,
                 @"3.5-inch hero is 180");
    MRAssertTrue([MRLayout heroHeightForDeviceClass:MRDeviceClassPhone
                                        orientation:MRLayoutOrientationPortrait
                                    availableHeight:568.0] == 200.0,
                 @"4-inch hero is 200");
    MRAssertTrue([MRLayout heroHeightForDeviceClass:MRDeviceClassTablet
                                        orientation:MRLayoutOrientationPortrait
                                    availableHeight:1024.0] == 300.0,
                 @"pad portrait hero is 300");
    MRAssertTrue([MRLayout heroHeightForDeviceClass:MRDeviceClassTablet
                                        orientation:MRLayoutOrientationLandscape
                                    availableHeight:768.0] == 260.0,
                 @"pad landscape hero is 260");

    MRAssertTrue([MRLayout tabBarSelectionWidthForWidth:320.0 itemCount:4] == 80.0,
                 @"phone tab selection is 80");
    MRAssertTrue([MRLayout tabBarSelectionWidthForWidth:768.0 itemCount:4] == 192.0,
                 @"pad portrait tab selection is 192");
    MRAssertTrue([MRLayout tabBarSelectionWidthForWidth:1024.0 itemCount:4] == 256.0,
                 @"pad landscape tab selection is 256");
    MRAssertTrue([MRLayout tabBarSelectionWidthForWidth:320.0 itemCount:5] == 64.0,
                 @"selection follows item count");
    MRAssertTrue([MRLayout tabBarSelectionWidthForWidth:320.0 itemCount:0] == 0.0,
                 @"zero items yields no selection");
}
