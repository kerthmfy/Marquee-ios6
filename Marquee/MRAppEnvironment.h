//
//  MRAppEnvironment.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRAPIClient;
@class MRImageCache;
@class MRSimklAuth;
@class MRStorage;
@class MRLibraryStore;
@class MRSyncEngine;

// App-wide composition root. The API client, image cache, and auth service
// exist at launch. Storage, the library store, the sync engine, and accountID
// are filled in after auth and /users/settings identify the account. The
// mutable environment lets the window appear without waiting for bootstrap.
@interface MRAppEnvironment : NSObject

@property (nonatomic, strong) MRAPIClient *apiClient;
@property (nonatomic, strong) MRImageCache *imageCache;
@property (nonatomic, strong) MRSimklAuth *auth;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRSyncEngine *syncEngine;
@property (nonatomic, assign) NSInteger accountID;

@end
