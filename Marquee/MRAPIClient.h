//
//  MRAPIClient.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

@class MRResponseCache;
@class MRQuotaTracker;
@class MRDiagnostics;
@protocol MRHTTPClient;
@protocol MRHTTPTask;
@protocol MRTokenProviding;
@protocol MRClock;

// Public, unauthenticated Simkl reads. These calls never ask for a token and
// never attach an Authorization header. Trending, genre, and detail responses
// are cached on disk for 24 hours and revalidated with If-Modified-Since.
@interface MRAPIClient : NSObject

- (instancetype)initWithHTTPClient:(id<MRHTTPClient>)httpClient
                     tokenProvider:(id<MRTokenProviding>)tokenProvider
                     responseCache:(MRResponseCache *)responseCache
                      quotaTracker:(MRQuotaTracker *)quotaTracker
                       diagnostics:(MRDiagnostics *)diagnostics
                             clock:(id<MRClock>)clock;

- (id<MRHTTPTask>)fetchTrendingWeekWithCompletion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchGenreIndexForType:(MRMediaType)type completion:(void (^)(NSArray *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchGenre:(NSString *)slug forType:(MRMediaType)type completion:(void (^)(NSArray *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchDetailForType:(MRMediaType)type simklID:(NSInteger)simklID completion:(void (^)(NSDictionary *json, NSError *error))completion;

@end
