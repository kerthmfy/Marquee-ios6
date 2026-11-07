//
//  MRAPIClient.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRSyncEngine.h"

@class MRResponseCache;
@class MRQuotaTracker;
@class MRDiagnostics;
@protocol MRHTTPClient;
@protocol MRTokenProviding;
@protocol MRClock;

// Public, unauthenticated Simkl reads plus the authenticated sync reads.
// Public responses are cached on disk for 24 hours and revalidated with
// If-Modified-Since. Authenticated reads attach the bearer token, always send
// language=en (where applicable), and never touch the public response cache.
@interface MRAPIClient : NSObject <MRSyncDataProviding>

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

- (id<MRHTTPTask>)fetchActivitiesWithCompletion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchAllItemsForType:(MRMediaType)type
                               status:(MRWatchStatus)status
                             dateFrom:(NSString *)dateFrom
                              idsOnly:(BOOL)idsOnly
                         nextWatchInfo:(BOOL)nextWatchInfo
                            completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchRatingsForType:(MRMediaType)type
                             dateFrom:(NSString *)dateFrom
                           completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchUserSettingsWithCompletion:(void (^)(NSDictionary *json, NSError *error))completion;

@end
