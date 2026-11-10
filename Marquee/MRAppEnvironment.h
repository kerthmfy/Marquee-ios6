//
//  MRAppEnvironment.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRAPIClient;
@class MRImageCache;
@class MRPreferencesStore;
@class MRRecommendationEngine;
@class MRSimklAuth;
@class MRStorage;
@class MRLibraryStore;
@class MRSyncEngine;
@class MROutbox;
@class MRWriteService;

// App-wide composition root. The API client, image cache, and auth service
// exist at launch. Storage, the library store, the sync engine, the write
// queue, and accountID are filled in after auth and /users/settings identify
// the account. The mutable environment lets the window appear without waiting
// for bootstrap.
@interface MRAppEnvironment : NSObject

@property (nonatomic, strong) MRAPIClient *apiClient;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) MRSimklAuth *auth;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRSyncEngine *syncEngine;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRWriteService *writeService;
@property (nonatomic, strong) MRPreferencesStore *preferences;
@property (nonatomic, strong) MRRecommendationEngine *recommendationEngine;
@property (nonatomic, assign) NSInteger accountID;

@end
