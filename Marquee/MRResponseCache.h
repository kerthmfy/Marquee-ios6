//
//  MRResponseCache.h
//  Marquee
//

#import <Foundation/Foundation.h>

// Disk-backed cache for parsed JSON responses. The directory is injectable so
// tests and production can use different locations.
@interface MRResponseCache : NSObject

@property (nonatomic, copy, readonly) NSString *directory;

- (instancetype)initWithDirectory:(NSString *)directory;

// Returns the stored body when the entry exists, matches the URL, and is no
// older than maxAge seconds. Returns nil otherwise.
- (id)cachedBodyForURL:(NSString *)url maxAge:(NSTimeInterval)maxAge;
- (NSString *)lastModifiedForURL:(NSString *)url;
- (NSDate *)fetchedAtForURL:(NSString *)url;

- (void)storeBody:(id)body forURL:(NSString *)url lastModified:(NSString *)lastModified;

// Bytes in cache-owned files only. Other files in the directory are ignored.
- (unsigned long long)diskUsageBytes;

@end
