//
//  MRSearchPagination.h
//  Marquee
//

#import <Foundation/Foundation.h>

// The pure rules behind the Search tab: when to search, when a full page
// offers more, and the five-page cap that protects the daily quota.
@interface MRSearchPagination : NSObject

// Trims whitespace and requires at least three characters.
+ (BOOL)shouldSearchForQuery:(NSString *)query;

// YES only for pages 1-4 that returned exactly 30 results.
+ (BOOL)canLoadMoreForPage:(NSUInteger)page resultCount:(NSUInteger)resultCount;

// Returns page + 1, never beyond the fifth page.
+ (NSUInteger)nextPageForPage:(NSUInteger)page;

@end
