//
//  MRMakeAssets.m
//  Marquee
//
//  Generates the temporary app icons and launch images with AppKit.
//  Usage: MRMakeAssets <output-directory>
//

#import <Cocoa/Cocoa.h>

static NSColor *MRCharcoal(void)
{
    return [NSColor colorWithCalibratedRed:30.0 / 255.0
                                     green:30.0 / 255.0
                                      blue:32.0 / 255.0
                                     alpha:1.0];
}

static NSColor *MRBlue(void)
{
    return [NSColor colorWithCalibratedRed:41.0 / 255.0
                                     green:89.0 / 255.0
                                      blue:143.0 / 255.0
                                     alpha:1.0];
}

static NSBitmapImageRep *MRBitmap(NSUInteger width, NSUInteger height)
{
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:width
                                                   pixelsHigh:height
                                                bitsPerSample:8
                                              samplesPerPixel:4
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:NSCalibratedRGBColorSpace
                                                  bytesPerRow:0
                                                 bitsPerPixel:0];
}

static BOOL MRWritePNG(NSBitmapImageRep *bitmap, NSString *path)
{
    NSData *data = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!data) {
        return NO;
    }
    return [data writeToFile:path atomically:YES];
}

static BOOL MRDrawIcon(NSUInteger size, NSString *path)
{
    NSBitmapImageRep *bitmap = MRBitmap(size, size);
    if (!bitmap) {
        return NO;
    }

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [context setShouldAntialias:YES];
    [context setImageInterpolation:NSImageInterpolationHigh];

    [MRCharcoal() setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, (CGFloat)size, (CGFloat)size));

    NSFont *font = [NSFont boldSystemFontOfSize:(CGFloat)size * 0.62];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSString *letter = @"M";
    NSSize textSize = [letter sizeWithAttributes:attributes];
    [letter drawAtPoint:NSMakePoint(((CGFloat)size - textSize.width) / 2.0,
                                    ((CGFloat)size - textSize.height) / 2.0 + (CGFloat)size * 0.08)
         withAttributes:attributes];

    CGFloat ruleWidth = (CGFloat)size * 0.46;
    CGFloat ruleHeight = MAX(1.0, round((CGFloat)size * 0.035));
    [MRBlue() setFill];
    NSRectFill(NSMakeRect(((CGFloat)size - ruleWidth) / 2.0,
                          (CGFloat)size * 0.24,
                          ruleWidth,
                          ruleHeight));

    [NSGraphicsContext restoreGraphicsState];
    return MRWritePNG(bitmap, path);
}

static BOOL MRDrawLaunchImage(NSUInteger width, NSUInteger height, NSString *path)
{
    NSBitmapImageRep *bitmap = MRBitmap(width, height);
    if (!bitmap) {
        return NO;
    }

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [context setShouldAntialias:YES];
    [context setImageInterpolation:NSImageInterpolationHigh];

    [MRCharcoal() setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height));

    CGFloat pointWidth = (CGFloat)width / 2.0;
    NSFont *font = [NSFont systemFontOfSize:round(34.0 * pointWidth / 320.0)];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSString *name = @"Marquee";
    NSSize textSize = [name sizeWithAttributes:attributes];
    [name drawAtPoint:NSMakePoint(((CGFloat)width - textSize.width) / 2.0,
                                  ((CGFloat)height - textSize.height) / 2.0)
       withAttributes:attributes];

    [NSGraphicsContext restoreGraphicsState];
    return MRWritePNG(bitmap, path);
}

static BOOL MRWriteAsset(NSString *directory, NSString *name,
                         NSUInteger width, NSUInteger height, BOOL icon)
{
    NSString *path = [directory stringByAppendingPathComponent:name];
    BOOL ok = icon ? MRDrawIcon(width, path)
                   : MRDrawLaunchImage(width, height, path);
    if (!ok) {
        fprintf(stderr, "MRMakeAssets: failed to write %s\n", [path UTF8String]);
        return NO;
    }
    printf("wrote %s (%lux%lu)\n", [name UTF8String],
           (unsigned long)width, (unsigned long)height);
    return YES;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: %s <output-directory>\n", argv[0]);
            return 2;
        }

        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            fprintf(stderr, "MRMakeAssets: cannot create %s: %s\n",
                    [directory UTF8String], [[error description] UTF8String]);
            return 1;
        }

        BOOL ok = YES;

        // iPhone app icons
        ok = MRWriteAsset(directory, @"Icon.png", 57, 57, YES) && ok;
        ok = MRWriteAsset(directory, @"Icon@2x.png", 114, 114, YES) && ok;
        ok = MRWriteAsset(directory, @"Icon-72.png", 72, 72, YES) && ok;
        ok = MRWriteAsset(directory, @"Icon-72@2x.png", 144, 144, YES) && ok;

        // Launch images
        ok = MRWriteAsset(directory, @"Default.png", 320, 480, NO) && ok;
        ok = MRWriteAsset(directory, @"Default@2x.png", 640, 960, NO) && ok;
        ok = MRWriteAsset(directory, @"Default-568h@2x.png", 640, 1136, NO) && ok;

        return ok ? 0 : 1;
    }
}
