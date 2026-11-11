//
//  MRSyncEngine.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRHTTPClient.h"
#import "MRMediaType.h"
#import "MRWatchStatus.h"

@class MRLibraryStore;
@class MROutbox;
@class MRStorage;
@protocol MRClock;

// Posted on the main thread when isSyncing, lastSyncAt, or lastSyncError
// changes. The notification object is the engine.
extern NSString *const MRSyncStatusDidChangeNotification;

// The authenticated reads the sync engine needs. MRAPIClient conforms to this
// protocol; tests provide a stub that returns nil tasks.
@protocol MRSyncDataProviding <NSObject>
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

// Phase 1 initial sync: activities, then shows, movies, and anime sequentially.
// The library is replaced only when every pull succeeds. Never runs two syncs
// at once; a second request joins the in-flight sync.
@interface MRSyncEngine : NSObject

@property (nonatomic, readonly, getter=isSyncing) BOOL syncing;
@property (nonatomic, strong, readonly) NSDate *lastSyncAt;
@property (nonatomic, strong, readonly) NSDate *lastSyncAttemptAt;
@property (nonatomic, strong, readonly) NSError *lastSyncError;
@property (nonatomic, readonly) NSUInteger pendingCount;

- (instancetype)initWithDataProvider:(id<MRSyncDataProviding>)dataProvider
                        libraryStore:(MRLibraryStore *)libraryStore
                             storage:(MRStorage *)storage
                               clock:(id<MRClock>)clock;

// Set once the account's outbox exists. pendingCount mirrors its queue length.
- (void)setOutbox:(MROutbox *)outbox;

- (void)syncWithCompletion:(void (^)(NSError *error))completion;

// Foreground/launch trigger. Automatic syncs are coalesced to one attempt per
// 15 minutes. A manual syncWithCompletion: is never throttled.
- (void)noteForegroundAtDate:(NSDate *)date;

- (void)cancel;

// Wipes the saved snapshot and runs phase 1 again. The outbox is never touched.
// An in-flight sync is cancelled first; its waiters receive Cancelled while this
// request receives the new sync's result.
- (void)forceFullSyncWithCompletion:(void (^)(NSError *error))completion;

@end
