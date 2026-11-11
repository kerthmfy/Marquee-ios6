//
//  MRAPIClient.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRSyncEngine.h"
#import "MRRecommendationDataProviding.h"

@class MRResponseCache;
@class MRQuotaTracker;
@class MRDiagnostics;
@class MROutboxEntry;
@protocol MRHTTPClient;
@protocol MRTokenProviding;
@protocol MRClock;

// Public, unauthenticated Simkl reads plus the authenticated sync reads and
// writes. Public responses are cached on disk for 24 hours and revalidated with
// If-Modified-Since. Authenticated calls attach the bearer token, always send
// language=en (where applicable), and never touch the public response cache.
// Write POSTs are never retried by this layer; MRWriteService owns write retry
// policy so attempts survive the process.
@interface MRAPIClient : NSObject <MRSyncDataProviding, MRRecommendationDataProviding>

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

// Authenticated mixed-type search. Results carry endpoint_type so callers can
// build MRMediaItem values with +itemWithSearchDictionary:.
- (id<MRHTTPTask>)searchAllWithQuery:(NSString *)query
                                page:(NSUInteger)page
                          completion:(void (^)(NSArray *json, NSError *error))completion;

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

#pragma mark - Authenticated writes

- (id<MRHTTPTask>)postStatusEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)postHistoryEntries:(NSArray<MROutboxEntry *> *)entries
                          completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)postRatingEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)postRatingRemovalEntries:(NSArray<MROutboxEntry *> *)entries
                                completion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)postRemoveEntries:(NSArray<MROutboxEntry *> *)entries
                         completion:(void (^)(NSDictionary *json, NSError *error))completion;

@end
