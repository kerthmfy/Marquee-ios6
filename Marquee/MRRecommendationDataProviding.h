//
//  MRRecommendationDataProviding.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

@protocol MRHTTPTask;

// The public reads the recommendation engine needs. MRAPIClient conforms; tests
// provide a stub that returns nil tasks.
@protocol MRRecommendationDataProviding <NSObject>
- (id<MRHTTPTask>)fetchTrendingWeekWithCompletion:(void (^)(NSDictionary *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchGenreIndexForType:(MRMediaType)type completion:(void (^)(NSArray *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchGenre:(NSString *)slug forType:(MRMediaType)type completion:(void (^)(NSArray *json, NSError *error))completion;
- (id<MRHTTPTask>)fetchDetailForType:(MRMediaType)type simklID:(NSInteger)simklID completion:(void (^)(NSDictionary *json, NSError *error))completion;
@end
