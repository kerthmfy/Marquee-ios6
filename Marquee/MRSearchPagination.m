//
//  MRSearchPagination.m
//  Marquee
//

#import "MRSearchPagination.h"

static const NSUInteger MRSearchResultsPerPage = 30;
static const NSUInteger MRSearchMaximumPage = 5;

@implementation MRSearchPagination

+ (BOOL)shouldSearchForQuery:(NSString *)query {
    if (![query isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *trimmed =
        [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length >= 3;
}

+ (BOOL)canLoadMoreForPage:(NSUInteger)page resultCount:(NSUInteger)resultCount {
    return page >= 1 && page < MRSearchMaximumPage &&
           resultCount == MRSearchResultsPerPage;
}

+ (NSUInteger)nextPageForPage:(NSUInteger)page {
    if (page < 1) {
        return 1;
    }
    if (page >= MRSearchMaximumPage) {
        return MRSearchMaximumPage;
    }
    return page + 1;
}

@end
