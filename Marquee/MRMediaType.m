//
//  MRMediaType.m
//  Marquee
//

#import "MRMediaType.h"

MRMediaType MRMediaTypeFromSyncKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) {
        return MRMediaTypeMovie;
    }
    NSString *normalized = [key lowercaseString];
    if ([normalized isEqualToString:@"shows"] || [normalized isEqualToString:@"show"]) {
        return MRMediaTypeShow;
    }
    if ([normalized isEqualToString:@"anime"]) {
        return MRMediaTypeAnime;
    }
    return MRMediaTypeMovie;
}

MRMediaType MRMediaTypeFromSearchKey(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) {
        return MRMediaTypeMovie;
    }
    NSString *normalized = [key lowercaseString];
    if ([normalized isEqualToString:@"tv"] || [normalized isEqualToString:@"shows"] ||
        [normalized isEqualToString:@"show"]) {
        return MRMediaTypeShow;
    }
    if ([normalized isEqualToString:@"anime"]) {
        return MRMediaTypeAnime;
    }
    return MRMediaTypeMovie;
}

NSString *MRMediaTypeAPIPath(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"tv";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movies";
    }
}

NSString *MRMediaTypeDisplayName(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"TV Show";
        case MRMediaTypeAnime:
            return @"Anime";
        case MRMediaTypeMovie:
        default:
            return @"Movie";
    }
}
