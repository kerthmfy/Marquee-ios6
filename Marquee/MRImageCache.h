//
//  MRImageCache.h
//  Marquee
//

#import <UIKit/UIKit.h>
#import "MRHTTPClient.h"

// Two-level poster cache: an NSCache of decoded images and a bounded JPEG disk
// cache. Loads are decoded and downloaded on a four-operation queue; callers
// always receive completions on the main queue.
@interface MRImageCache : NSObject

- (instancetype)init;
- (instancetype)initWithDirectory:(NSString *)directory
                      httpClient:(id<MRHTTPClient>)httpClient;

- (UIImage *)cachedImageForURL:(NSString *)URL;
- (void)loadImageForURL:(NSString *)URL
             completion:(void (^)(UIImage *image, NSError *error))completion;
- (void)cancelLoadForURL:(NSString *)URL;
- (void)clearMemoryCache;
- (void)clearDiskCache;

@property (nonatomic, readonly) unsigned long long diskUsageBytes;

@end
