//
//  MRPosterImageView.m
//  Marquee
//

#import "MRPosterImageView.h"
#import "MRImageCache.h"
#import "MRURLBuilder.h"

@interface MRPosterImageView ()
@property (nonatomic, strong) MRImageCache *imageCache;
@end

static UIImage *MRPosterPlaceholderImage(void) {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGSize size = CGSizeMake(200.0, 300.0);
        UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
        CGContextRef context = UIGraphicsGetCurrentContext();

        [[UIColor colorWithWhite:0.91 alpha:1.0] setFill];
        CGContextFillRect(context, CGRectMake(0.0, 0.0, size.width, size.height));

        CGRect frame = CGRectMake(50.0, 110.0, 100.0, 80.0);
        [[UIColor colorWithWhite:0.62 alpha:1.0] setStroke];
        CGContextSetLineWidth(context, 4.0);
        CGContextStrokeRect(context, frame);

        [[UIColor colorWithWhite:0.72 alpha:1.0] setFill];
        for (NSUInteger index = 0; index < 5; index += 1) {
            CGFloat x = frame.origin.x + 8.0 + (CGFloat)index * 18.0;
            CGContextFillRect(context, CGRectMake(x, frame.origin.y + 6.0, 8.0, 6.0));
            CGContextFillRect(context,
                              CGRectMake(x, CGRectGetMaxY(frame) - 12.0, 8.0, 6.0));
        }

        [[UIColor colorWithWhite:0.84 alpha:1.0] setFill];
        CGContextFillRect(context,
                          CGRectMake(frame.origin.x + 10.0,
                                     frame.origin.y + 16.0,
                                     80.0,
                                     48.0));

        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return image;
}

@implementation MRPosterImageView {
    NSUInteger _generation;
    NSString *_currentURL;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _generation = 0;
        self.backgroundColor = [UIColor colorWithWhite:0.91 alpha:1.0];
        self.contentMode = UIViewContentModeScaleAspectFill;
        self.clipsToBounds = YES;
        self.image = MRPosterPlaceholderImage();
    }
    return self;
}

- (instancetype)initWithImageCache:(MRImageCache *)imageCache {
    self = [self initWithFrame:CGRectZero];
    if (self) {
        _imageCache = imageCache;
    }
    return self;
}

- (void)setImagePath:(NSString *)path size:(NSString *)size {
    if (path.length == 0) {
        [self setImageURL:nil];
        return;
    }
    NSString *URL = [MRURLBuilder posterURLForPath:path size:size];
    [self setImageURL:URL];
}

- (void)setImageURL:(NSString *)URL {
    _generation += 1;
    NSUInteger token = _generation;

    if (_currentURL.length > 0) {
        [_imageCache cancelLoadForURL:_currentURL];
    }
    _currentURL = [URL copy];

    if (URL.length == 0 || _imageCache == nil) {
        self.image = MRPosterPlaceholderImage();
        return;
    }

    UIImage *cached = [_imageCache cachedImageForURL:URL];
    if (cached != nil) {
        self.image = cached;
        return;
    }

    self.image = MRPosterPlaceholderImage();

    __weak MRPosterImageView *weakSelf = self;
    [_imageCache loadImageForURL:URL completion:^(UIImage *image, NSError *error) {
        MRPosterImageView *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (strongSelf->_generation != token ||
            ![strongSelf->_currentURL isEqualToString:URL]) {
            return;
        }
        strongSelf.image = image != nil ? image : MRPosterPlaceholderImage();
    }];
}

- (void)cancelLoading {
    _generation += 1;
    NSString *URL = _currentURL;
    _currentURL = nil;
    if (URL.length > 0) {
        [_imageCache cancelLoadForURL:URL];
    }
    self.image = MRPosterPlaceholderImage();
}

@end
