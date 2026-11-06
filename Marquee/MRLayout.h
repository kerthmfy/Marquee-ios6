//
//  MRLayout.h
//  Marquee
//
//  Universal metrics for the iPhone and iPad layouts. Foundation and
//  CoreGraphics only: callers pass the idiom, bounds, orientation, and
//  available height. This file must never import UIKit or read UIDevice or
//  UIScreen so the macOS test harness can exercise every value.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, MRDeviceClass) {
    MRDeviceClassPhone = 0,
    MRDeviceClassTablet
};

typedef NS_ENUM(NSInteger, MRLayoutOrientation) {
    MRLayoutOrientationPortrait = 0,
    MRLayoutOrientationLandscape
};

@interface MRLayout : NSObject

+ (MRDeviceClass)deviceClassForIdiom:(NSInteger)idiom;
+ (MRLayoutOrientation)orientationForSize:(CGSize)size;
+ (CGFloat)heroSideInsetForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)rowSideInsetForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardImageHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterCardGapForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)posterRowHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)heroHeightForDeviceClass:(MRDeviceClass)deviceClass
                         orientation:(MRLayoutOrientation)orientation
                     availableHeight:(CGFloat)availableHeight;
+ (CGFloat)rowHeaderHeightForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)contentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)modalContentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass;
+ (CGFloat)tabBarSelectionWidthForWidth:(CGFloat)width itemCount:(NSInteger)count;

@end
