//
//  MRSyncEngine.m
//  Marquee
//

#import "MRSyncEngine.h"
#import "MRClock.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRStorage.h"

NSString *const MRSyncStatusDidChangeNotification = @"MRSyncStatusDidChangeNotification";

static void MRSyncDeliverOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        block();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), block);
}

static NSString *MRSyncTypeKey(MRMediaType type) {
    switch (type) {
        case MRMediaTypeShow:
            return @"shows";
        case MRMediaTypeAnime:
            return @"anime";
        case MRMediaTypeMovie:
        default:
            return @"movies";
    }
}

static NSArray *MRSyncStatusesForType(MRMediaType type) {
    // Movies do not have watching or hold buckets.
    if (type == MRMediaTypeMovie) {
        return @[ @(MRWatchStatusPlanToWatch), @(MRWatchStatusCompleted),
                  @(MRWatchStatusDropped) ];
    }
    return @[ @(MRWatchStatusWatching), @(MRWatchStatusPlanToWatch),
              @(MRWatchStatusCompleted), @(MRWatchStatusHold),
              @(MRWatchStatusDropped) ];
}

@interface MRSyncEngine ()
@property (nonatomic, strong) id<MRSyncDataProviding> dataProvider;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, assign, readwrite, getter=isSyncing) BOOL syncing;
@property (nonatomic, strong, readwrite) NSDate *lastSyncAt;
@property (nonatomic, strong, readwrite) NSDate *lastSyncAttemptAt;
@property (nonatomic, strong, readwrite) NSError *lastSyncError;
- (void)finishCancelled;
- (void)deliverCompletionsWithError:(NSError *)error;
@end

@implementation MRSyncEngine {
    NSMutableArray *_completionBlocks;
    NSMutableArray *_items;
    NSMutableSet *_itemIdentifiers;
    NSDictionary *_activities;
    id<MRHTTPTask> _currentTask;
    BOOL _finished;
    BOOL _cancelled;
}

- (instancetype)initWithDataProvider:(id<MRSyncDataProviding>)dataProvider
                        libraryStore:(MRLibraryStore *)libraryStore
                             storage:(MRStorage *)storage
                               clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _dataProvider = dataProvider;
        _libraryStore = libraryStore;
        _storage = storage;
        _clock = clock;
        _lastSyncAt = libraryStore.lastSyncAt;
        _completionBlocks = [NSMutableArray array];
    }
    return self;
}

#pragma mark - State

- (void)postStatusChange {
    MRSyncDeliverOnMain(^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MRSyncStatusDidChangeNotification
                          object:self];
    });
}

- (void)addCompletion:(void (^)(NSError *error))completion {
    if (completion != nil) {
        [_completionBlocks addObject:[completion copy]];
    }
}

#pragma mark - Public

- (void)syncWithCompletion:(void (^)(NSError *error))completion {
    MRSyncDeliverOnMain(^{
        if (self.isSyncing) {
            [self addCompletion:completion];
            return;
        }

        self.syncing = YES;
        self.lastSyncError = nil;
        self.lastSyncAttemptAt = [self.clock now];
        _finished = NO;
        _cancelled = NO;
        _activities = nil;
        _items = [NSMutableArray array];
        _itemIdentifiers = [NSMutableSet set];
        [_completionBlocks removeAllObjects];
        [self addCompletion:completion];
        [self postStatusChange];
        [self fetchActivities];
    });
}

- (void)cancel {
    MRSyncDeliverOnMain(^{
        if (!self.isSyncing) {
            return;
        }
        _cancelled = YES;
        id<MRHTTPTask> task = _currentTask;
        _currentTask = nil;
        [task cancel];
        [self finishCancelled];
    });
}

- (void)forceFullSyncWithCompletion:(void (^)(NSError *error))completion {
    MRSyncDeliverOnMain(^{
        if (self.isSyncing) {
            [self cancel];
        }
        // library.json and state.json are rebuilt from the network. Pending
        // writes live in outbox.json and are deliberately left alone.
        [self.storage removeFileNamed:@"library" error:NULL];
        [self.storage removeFileNamed:@"state" error:NULL];
        [self syncWithCompletion:completion];
    });
}

#pragma mark - Phase 1

- (void)fetchActivities {
    if (_finished || _cancelled) {
        return;
    }
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchActivitiesWithCompletion:
                    ^(NSDictionary *json, NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            [strongSelf finishWithError:error];
            return;
        }
        if (![json isKindOfClass:[NSDictionary class]]) {
            [strongSelf finishWithError:[MRError errorWithKind:MRErrorKindParse]];
            return;
        }
        strongSelf->_activities = [json copy];
        [strongSelf fetchType:MRMediaTypeShow
                nextWatchInfo:YES
                   completion:^(NSError *typeError) {
            if (typeError != nil) {
                [strongSelf finishWithError:typeError];
                return;
            }
            [strongSelf fetchType:MRMediaTypeMovie
                    nextWatchInfo:NO
                       completion:^(NSError *movieError) {
                if (movieError != nil) {
                    [strongSelf finishWithError:movieError];
                    return;
                }
                [strongSelf fetchType:MRMediaTypeAnime
                        nextWatchInfo:YES
                           completion:^(NSError *animeError) {
                    if (animeError != nil) {
                        [strongSelf finishWithError:animeError];
                        return;
                    }
                    [strongSelf finishSuccessfully];
                }];
            }];
        }];
    }];
}

- (void)fetchType:(MRMediaType)type
    nextWatchInfo:(BOOL)nextWatchInfo
       completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:MRWatchStatusNone
                                                  dateFrom:nil
                                                   idsOnly:NO
                                              nextWatchInfo:nextWatchInfo
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil && [MRError kindForError:error] == MRErrorKindTooLarge) {
            [strongSelf fetchBucketsForType:type
                             nextWatchInfo:nextWatchInfo
                                completion:completion];
            return;
        }
        if (error != nil) {
            completion(error);
            return;
        }
        NSError *parseError = nil;
        NSArray *items = [strongSelf itemsFromJSON:json type:type error:&parseError];
        if (items == nil) {
            completion(parseError);
            return;
        }
        [strongSelf appendItems:items];
        completion(nil);
    }];
}

- (void)fetchBucketsForType:(MRMediaType)type
              nextWatchInfo:(BOOL)nextWatchInfo
                 completion:(void (^)(NSError *error))completion {
    NSArray *statuses = MRSyncStatusesForType(type);
    [self fetchBucketAtIndex:0
                        type:type
                    statuses:statuses
               nextWatchInfo:nextWatchInfo
                  completion:completion];
}

- (void)fetchBucketAtIndex:(NSUInteger)index
                      type:(MRMediaType)type
                  statuses:(NSArray *)statuses
             nextWatchInfo:(BOOL)nextWatchInfo
                completion:(void (^)(NSError *error))completion {
    if (_finished || _cancelled) {
        return;
    }
    if (index >= statuses.count) {
        completion(nil);
        return;
    }

    MRWatchStatus status = (MRWatchStatus)[[statuses objectAtIndex:index] integerValue];
    __weak MRSyncEngine *weakSelf = self;
    _currentTask = [self.dataProvider fetchAllItemsForType:type
                                                    status:status
                                                  dateFrom:nil
                                                   idsOnly:NO
                                              nextWatchInfo:nextWatchInfo
                                                 completion:^(NSDictionary *json,
                                                              NSError *error) {
        MRSyncEngine *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_finished) {
            return;
        }
        strongSelf->_currentTask = nil;
        if (error != nil) {
            if ([MRError kindForError:error] == MRErrorKindTooLarge) {
                completion([MRError errorWithKind:MRErrorKindTooLarge]);
            } else {
                completion(error);
            }
            return;
        }
        NSError *parseError = nil;
        NSArray *items = [strongSelf itemsFromJSON:json type:type error:&parseError];
        if (items == nil) {
            completion(parseError);
            return;
        }
        [strongSelf appendItems:items];
        [strongSelf fetchBucketAtIndex:index + 1
                                   type:type
                               statuses:statuses
                          nextWatchInfo:nextWatchInfo
                             completion:completion];
    }];
}

- (NSArray *)itemsFromJSON:(NSDictionary *)json
                      type:(MRMediaType)type
                     error:(NSError **)error {
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return nil;
    }

    id entries = [json objectForKey:MRSyncTypeKey(type)];
    if (entries == nil ||
        (![entries isKindOfClass:[NSArray class]] && entries != [NSNull null])) {
        if (error != NULL) {
            *error = [MRError errorWithKind:MRErrorKindParse];
        }
        return nil;
    }
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        MRMediaItem *item = [MRMediaItem itemWithSyncDictionary:entry type:type];
        if (item.simklID <= 0) {
            continue;
        }
        [items addObject:item];
    }
    return items;
}

- (void)appendItems:(NSArray *)items {
    for (MRMediaItem *item in items) {
        NSString *identifier = [item identifier];
        if ([_itemIdentifiers containsObject:identifier]) {
            continue;
        }
        [_itemIdentifiers addObject:identifier];
        [_items addObject:item];
    }
}

- (void)finishSuccessfully {
    if (_finished) {
        return;
    }
    NSError *saveError = nil;
    BOOL saved = [self.libraryStore replaceWithItems:_items
                                          activities:_activities
                                             profile:self.libraryStore.profile
                                               error:&saveError];
    if (!saved) {
        [self finishWithError:saveError != nil
                                 ? saveError
                                 : [MRError errorWithKind:MRErrorKindUnknown]];
        return;
    }

    self.lastSyncAt = [self.clock now];
    self.lastSyncError = nil;
    [self finishWithError:nil];
}

- (void)finishCancelled {
    if (_finished) {
        return;
    }
    _finished = YES;
    _currentTask = nil;
    self.lastSyncError = nil;
    self.syncing = NO;
    [self postStatusChange];
    [self deliverCompletionsWithError:[MRError errorWithKind:MRErrorKindCancelled]];
}

- (void)finishWithError:(NSError *)error {
    if (_finished) {
        return;
    }
    _finished = YES;
    _currentTask = nil;
    self.lastSyncError = error;
    self.syncing = NO;
    [self postStatusChange];
    [self deliverCompletionsWithError:error];
}

- (void)deliverCompletionsWithError:(NSError *)error {
    NSArray *blocks = [_completionBlocks copy];
    [_completionBlocks removeAllObjects];
    for (void (^completion)(NSError *) in blocks) {
        MRSyncDeliverOnMain(^{
            completion(error);
        });
    }
}

@end
