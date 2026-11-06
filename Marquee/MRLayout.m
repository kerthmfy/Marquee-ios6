//
//  MRLayout.m
//  Marquee
//
//  The single source of truth for universal UI measurements. iPhone values
//  preserve the shipped Task 7 geometry; iPad values enlarge the same chrome
//  for the 768 and 1024 pt widths.
//

#import "MRLayout.h"

@implementation MRLayout

+ (MRDeviceClass)deviceClassForIdiom:(NSInteger)idiom
{
    return idiom == 1 ? MRDeviceClassTablet : MRDeviceClassPhone;
}

+ (MRLayoutOrientation)orientationForSize:(CGSize)size
{
    return size.width > size.height
        ? MRLayoutOrientationLandscape
        : MRLayoutOrientationPortrait;
}

+ (CGFloat)heroSideInsetForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 16.0 : 8.0;
}

+ (CGFloat)rowSideInsetForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 16.0 : 12.0;
}

+ (CGFloat)posterCardWidthForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 150.0 : 100.0;
}

+ (CGFloat)posterCardImageHeightForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 225.0 : 150.0;
}

+ (CGFloat)posterCardHeightForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 315.0 : 210.0;
}

+ (CGFloat)posterCardGapForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 12.0 : 8.0;
}

+ (CGFloat)posterRowHeightForDeviceClass:(MRDeviceClass)deviceClass
{
    return [self posterCardHeightForDeviceClass:deviceClass];
}

+ (CGFloat)heroHeightForDeviceClass:(MRDeviceClass)deviceClass
                        orientation:(MRLayoutOrientation)orientation
                    availableHeight:(CGFloat)availableHeight
{
    if (deviceClass == MRDeviceClassTablet) {
        return orientation == MRLayoutOrientationLandscape ? 260.0 : 300.0;
    }
    return availableHeight < 568.0 ? 180.0 : 200.0;
}

+ (CGFloat)rowHeaderHeightForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 40.0 : 32.0;
}

+ (CGFloat)contentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 720.0 : 320.0;
}

+ (CGFloat)modalContentMaxWidthForDeviceClass:(MRDeviceClass)deviceClass
{
    return deviceClass == MRDeviceClassTablet ? 540.0 : 320.0;
}

+ (CGFloat)tabBarSelectionWidthForWidth:(CGFloat)width itemCount:(NSInteger)count
{
    if (width <= 0.0 || count <= 0) {
        return 0.0;
    }
    return width / (CGFloat)count;
}

@end
