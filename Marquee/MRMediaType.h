//
//  MRMediaType.h
//  Marquee
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MRMediaType) {
    MRMediaTypeMovie = 0,
    MRMediaTypeShow,
    MRMediaTypeAnime
};

// Sync keys are the plural object keys used by /sync/all-items and
// /sync/ratings: "movies", "shows", and "anime".
MRMediaType MRMediaTypeFromSyncKey(NSString *key);

// Search keys are the endpoint_type values returned by /search/all:
// "movies", "tv", and "anime".
MRMediaType MRMediaTypeFromSearchKey(NSString *key);

// The public detail endpoint path segment: "movies", "tv", or "anime".
NSString *MRMediaTypeAPIPath(MRMediaType type);
NSString *MRMediaTypeDisplayName(MRMediaType type);
