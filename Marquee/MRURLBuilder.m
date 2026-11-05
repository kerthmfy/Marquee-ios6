//
//  MRURLBuilder.m
//  Marquee
//

#import "MRURLBuilder.h"
#import "MRConfig.h"

static NSString *MRURLPathWithoutLeadingSlash(NSString *path) {
    if (![path isKindOfClass:[NSString class]]) {
        return @"";
    }
    NSUInteger index = 0;
    while (index < path.length && [path characterAtIndex:index] == '/') {
        index += 1;
    }
    return [path substringFromIndex:index];
}

// Strict query encoding: only RFC 3986 unreserved characters survive.
static NSString *MRURLQueryEncode(id value) {
    NSString *string = nil;
    if ([value isKindOfClass:[NSString class]]) {
        string = value;
    } else if (value != nil && value != (id)[NSNull null]) {
        string = [value description];
    } else {
        string = @"";
    }

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *encoded = [NSMutableString stringWithCapacity:data.length];
    for (NSUInteger index = 0; index < data.length; index += 1) {
        unsigned char byte = bytes[index];
        BOOL unreserved = ((byte >= 'A' && byte <= 'Z') ||
                           (byte >= 'a' && byte <= 'z') ||
                           (byte >= '0' && byte <= '9') ||
                           byte == '-' || byte == '.' || byte == '_' || byte == '~');
        if (unreserved) {
            [encoded appendFormat:@"%c", byte];
        } else {
            [encoded appendFormat:@"%%%02X", (unsigned int)byte];
        }
    }
    return encoded;
}

static NSString *MRURLQueryValue(id value) {
    return MRURLQueryEncode(value);
}

static BOOL MRURLIsCommonQueryKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) {
        return NO;
    }
    return ([key isEqualToString:@"client_id"] ||
            [key isEqualToString:@"app-name"] ||
            [key isEqualToString:@"app-version"]);
}

static NSString *MRURLWithBaseAndQuery(NSString *base, NSString *path, NSDictionary *query) {
    NSMutableArray *pairs = [NSMutableArray array];
    [pairs addObject:[NSString stringWithFormat:@"client_id=%@", MRURLQueryValue(MR_SIMKL_CLIENT_ID)]];
    [pairs addObject:[NSString stringWithFormat:@"app-name=%@", MRURLQueryValue(MR_APP_NAME)]];
    [pairs addObject:[NSString stringWithFormat:@"app-version=%@", MRURLQueryValue(MR_APP_VERSION)]];

    NSMutableArray *keys = [NSMutableArray array];
    for (id key in query) {
        if ([key isKindOfClass:[NSString class]]) {
            [keys addObject:key];
        }
    }
    [keys sortUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        if (MRURLIsCommonQueryKey(key)) {
            continue;
        }
        id value = [query objectForKey:key];
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                          MRURLQueryEncode(key), MRURLQueryValue(value)]];
    }

    NSString *normalized = MRURLPathWithoutLeadingSlash(path);
    NSString *url = normalized.length > 0
        ? [base stringByAppendingFormat:@"/%@", normalized]
        : base;
    if (pairs.count > 0) {
        url = [url stringByAppendingFormat:@"?%@", [pairs componentsJoinedByString:@"&"]];
    }
    return url;
}

static NSString *MRImageProxyURL(NSString *sourceURL) {
    return [NSString stringWithFormat:@"https://wsrv.nl/?url=%@&output=jpg&q=90", sourceURL];
}

@implementation MRURLBuilder

+ (NSString *)formEncodedStringForParameters:(NSDictionary *)parameters {
    NSMutableArray *keys = [NSMutableArray array];
    for (id key in parameters) {
        if ([key isKindOfClass:[NSString class]]) {
            [keys addObject:key];
        }
    }
    [keys sortUsingSelector:@selector(compare:)];

    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in keys) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                          MRURLQueryEncode(key),
                          MRURLQueryValue([parameters objectForKey:key])]];
    }
    return [pairs componentsJoinedByString:@"&"];
}

+ (NSString *)apiURLForPath:(NSString *)path query:(NSDictionary *)query {
    return MRURLWithBaseAndQuery(MR_API_BASE, path, query);
}

+ (NSString *)dataURLForPath:(NSString *)path query:(NSDictionary *)query {
    return MRURLWithBaseAndQuery(MR_DATA_BASE, path, query);
}

+ (NSString *)searchURLWithQuery:(NSString *)query page:(NSUInteger)page {
    NSDictionary *parameters = @{
        @"q": query ?: @"",
        @"extended": @"full",
        @"limit": @30,
        @"page": @(page)
    };
    return [self apiURLForPath:@"search/all" query:parameters];
}

+ (NSString *)posterURLForPath:(NSString *)path size:(NSString *)size {
    NSString *source = [NSString stringWithFormat:@"https://simkl.in/posters/%@%@.webp",
                        MRURLPathWithoutLeadingSlash(path), size ?: @""];
    return MRImageProxyURL(source);
}

+ (NSString *)fanartURLForPath:(NSString *)path size:(NSString *)size {
    NSString *source = [NSString stringWithFormat:@"https://simkl.in/fanart/%@%@.webp",
                        MRURLPathWithoutLeadingSlash(path), size ?: @""];
    return MRImageProxyURL(source);
}

+ (NSString *)posterPlaceholderURL {
    return MRImageProxyURL(@"https://simkl.in/posters/poster_no_pic_c.png");
}

+ (NSString *)avatarURLForPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        return nil;
    }
    if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"]) {
        return path;
    }

    NSString *normalized = MRURLPathWithoutLeadingSlash(path);
    if (normalized.length == 0) {
        return nil;
    }
    if ([normalized hasPrefix:@"avatars/"]) {
        return [@"https://simkl.in/" stringByAppendingString:normalized];
    }
    return [NSString stringWithFormat:@"https://simkl.in/avatars/%@", normalized];
}

+ (NSString *)simklWebURLForType:(MRMediaType)type simklID:(NSInteger)simklID slug:(NSString *)slug {
    NSString *url = [NSString stringWithFormat:@"https://simkl.com/%@/%ld",
                     MRMediaTypeAPIPath(type), (long)simklID];
    if ([slug isKindOfClass:[NSString class]] && slug.length > 0) {
        url = [url stringByAppendingFormat:@"/%@", MRURLQueryEncode(slug)];
    }
    return url;
}

@end
