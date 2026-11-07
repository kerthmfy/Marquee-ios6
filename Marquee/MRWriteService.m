//
//  MRWriteService.m
//  Marquee
//

#import "MRWriteService.h"

#import "MRAPIClient.h"
#import "MRClock.h"
#import "MRError.h"
#import "MRLibraryStore.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRWriteResult.h"

static const NSTimeInterval MRWriteSpacingSeconds = 1.1;
static const NSUInteger MRWriteBatchLimit = 20;
static const NSInteger MRWriteBurstMaximumAttempts = 3;
static const NSInteger MRWriteLockMaximumAttempts = 4;
static const NSInteger MRWriteServerMaximumAttempts = 6;

#pragma mark - Response helpers

static NSInteger MRWriteIntegerValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value integerValue];
    }
    return 0;
}

static NSInteger MRWriteItemID(id object) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        id ids = [dictionary objectForKey:@"ids"];
        if ([ids isKindOfClass:[NSDictionary class]]) {
            NSInteger simklID = MRWriteIntegerValue([ids objectForKey:@"simkl"]);
            if (simklID <= 0) {
                simklID = MRWriteIntegerValue([ids objectForKey:@"simkl_id"]);
            }
            if (simklID > 0) {
                return simklID;
            }
        }
        NSInteger simklID = MRWriteIntegerValue([dictionary objectForKey:@"simkl"]);
        if (simklID <= 0) {
            simklID = MRWriteIntegerValue([dictionary objectForKey:@"simkl_id"]);
        }
        return simklID;
    }
    return MRWriteIntegerValue(object);
}

// not_found and deleted are dictionaries of type key to a flat array of IDs
// (numbers, numeric strings, or objects carrying ids.simkl).
static void MRWriteCollectListedIDs(id object, NSMutableSet *identifiers) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (id key in dictionary) {
            MRWriteCollectListedIDs([dictionary objectForKey:key], identifiers);
        }
        return;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        for (id element in (NSArray *)object) {
            NSInteger simklID = MRWriteItemID(element);
            if (simklID > 0) {
                [identifiers addObject:@(simklID)];
            }
        }
        return;
    }
    NSInteger simklID = MRWriteItemID(object);
    if (simklID > 0) {
        [identifiers addObject:@(simklID)];
    }
}

static NSString *MRWriteStatusString(id object) {
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dictionary = (NSDictionary *)object;
    id value = [dictionary objectForKey:@"to"];
    if (![value isKindOfClass:[NSString class]]) {
        value = [dictionary objectForKey:@"status"];
    }
    id response = [dictionary objectForKey:@"response"];
    if (![value isKindOfClass:[NSString class]] &&
        [response isKindOfClass:[NSDictionary class]]) {
        value = [response objectForKey:@"status"];
        if (![value isKindOfClass:[NSString class]]) {
            value = [response objectForKey:@"to"];
        }
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static void MRWriteCollectResolvedStatuses(id object,
                                           NSMutableDictionary *statuses) {
    if ([object isKindOfClass:[NSArray class]]) {
        for (id element in (NSArray *)object) {
            MRWriteCollectResolvedStatuses(element, statuses);
        }
        return;
    }
    if (![object isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSDictionary *dictionary = (NSDictionary *)object;
    NSInteger simklID = MRWriteItemID(dictionary);
    if (simklID > 0) {
        NSString *statusString = MRWriteStatusString(dictionary);
        MRWatchStatus status = MRWatchStatusFromKey(statusString);
        if (status != MRWatchStatusNone) {
            [statuses setObject:@(status) forKey:@(simklID)];
        }
    }

    for (id key in dictionary) {
        if ([key isEqual:@"ids"]) {
            continue;
        }
        id value = [dictionary objectForKey:key];
        if ([value isKindOfClass:[NSArray class]] ||
            [value isKindOfClass:[NSDictionary class]]) {
            MRWriteCollectResolvedStatuses(value, statuses);
        }
    }
}

#pragma mark - Service

@interface MRWriteService ()
@property (nonatomic, strong) MRAPIClient *apiClient;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, strong) NSDate *lastPostAt;
@end

@implementation MRWriteService

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                           outbox:(MROutbox *)outbox
                     libraryStore:(MRLibraryStore *)libraryStore
                            clock:(id<MRClock>)clock {
    self = [super init];
    if (self) {
        _apiClient = apiClient;
        _outbox = outbox;
        _libraryStore = libraryStore;
        _clock = clock != nil ? clock : [[MRSystemClock alloc] init];
    }
    return self;
}

#pragma mark - MRWriteSending

- (void)sendEntries:(NSArray<MROutboxEntry *> *)entries
         completion:(void (^)(MRWriteResult *result))completion {
    NSArray *requested = entries;
    if (requested.count == 0) {
        requested = [self.outbox nextBatchWithLimit:MRWriteBatchLimit];
    }

    NSMutableArray *pending = [NSMutableArray array];
    MROutboxEntryKind batchKind = (MROutboxEntryKind)-1;
    for (MROutboxEntry *entry in requested) {
        if (![entry isKindOfClass:[MROutboxEntry class]]) {
            continue;
        }
        if (pending.count >= MRWriteBatchLimit) {
            break;
        }
        if (batchKind == (MROutboxEntryKind)-1) {
            batchKind = entry.kind;
        } else if (entry.kind != batchKind) {
            break;
        }
        if ([self.outbox containsEntryWithID:entry.entryID]) {
            [pending addObject:entry];
        }
    }

    if (pending.count == 0) {
        [self finishWithResult:[self emptyResult] completion:completion];
        return;
    }

    [self sendBatch:pending completion:completion];
}

#pragma mark - Sending

- (MRWriteResult *)emptyResult {
    return [[MRWriteResult alloc] init];
}

- (void)finishWithResult:(MRWriteResult *)result
              completion:(void (^)(MRWriteResult *result))completion {
    if (completion != nil) {
        completion(result);
    }
}

- (void)waitForSpacingThen:(void (^)(void))block {
    if (block == nil) {
        return;
    }
    NSDate *lastPostAt = self.lastPostAt;
    if (lastPostAt == nil) {
        block();
        return;
    }

    NSTimeInterval elapsed = [[self.clock now] timeIntervalSinceDate:lastPostAt];
    NSTimeInterval remaining = MRWriteSpacingSeconds - elapsed;
    if (remaining <= 0.0) {
        block();
        return;
    }
    [self.clock after:remaining perform:block];
}

- (void)sendBatch:(NSArray *)entries
       completion:(void (^)(MRWriteResult *result))completion {
    [self waitForSpacingThen:^{
        NSMutableArray *pending = [NSMutableArray array];
        for (MROutboxEntry *entry in entries) {
            if ([self.outbox containsEntryWithID:entry.entryID]) {
                [pending addObject:entry];
            }
        }
        if (pending.count == 0) {
            [self finishWithResult:[self emptyResult] completion:completion];
            return;
        }

        NSError *saveError = nil;
        if (![self.outbox save:&saveError]) {
            MRWriteResult *result = [self emptyResult];
            result.error = saveError;
            [self finishWithResult:result completion:completion];
            return;
        }

        self.lastPostAt = [self.clock now];
        [self postEntries:pending
               completion:^(NSDictionary *json, NSError *error) {
            if (error != nil) {
                [self handleFailureForEntries:pending
                                        error:error
                                   completion:completion];
            } else {
                [self handleSuccessForEntries:pending
                                          json:json
                                    completion:completion];
            }
        }];
    }];
}

- (void)postEntries:(NSArray *)entries
         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    MROutboxEntry *first = entries.firstObject;
    switch (first.kind) {
        case MROutboxEntryKindStatus:
            [self.apiClient postStatusEntries:entries completion:completion];
            break;
        case MROutboxEntryKindHistoryWhole:
        case MROutboxEntryKindHistoryEpisode:
            [self.apiClient postHistoryEntries:entries completion:completion];
            break;
        case MROutboxEntryKindRating:
            [self.apiClient postRatingEntries:entries completion:completion];
            break;
        case MROutboxEntryKindRatingRemove:
            [self.apiClient postRatingRemovalEntries:entries completion:completion];
            break;
        case MROutboxEntryKindRemove:
            [self.apiClient postRemoveEntries:entries completion:completion];
            break;
        default: {
            NSError *error = [MRError errorWithKind:MRErrorKindClientRejected];
            if (completion != nil) {
                completion(nil, error);
            }
            break;
        }
    }
}

#pragma mark - Failure handling

- (NSInteger)maximumAttemptsForErrorKind:(MRErrorKind)kind {
    switch (kind) {
        case MRErrorKindRateLimitedBurst:
            return MRWriteBurstMaximumAttempts;
        case MRErrorKindWriteLocked:
            return MRWriteLockMaximumAttempts;
        case MRErrorKindServer:
            return MRWriteServerMaximumAttempts;
        default:
            return 0;
    }
}

- (NSTimeInterval)retryDelayForErrorKind:(MRErrorKind)kind
                                attempts:(NSInteger)attempts {
    if (kind == MRErrorKindRateLimitedBurst) {
        return 1.0;
    }
    if (kind == MRErrorKindWriteLocked) {
        if (attempts <= 1) {
            return 2.0;
        }
        if (attempts == 2) {
            return 4.0;
        }
        return 8.0;
    }
    if (kind == MRErrorKindServer) {
        NSInteger shift = (NSInteger)MIN(MAX(attempts - 1, 0), 4);
        return (NSTimeInterval)(1 << shift);
    }
    return 0.0;
}

- (void)handleFailureForEntries:(NSArray *)entries
                          error:(NSError *)error
                     completion:(void (^)(MRWriteResult *result))completion {
    MRErrorKind kind = [MRError kindForError:error];

    if (kind == MRErrorKindNotFound) {
        [self.outbox removeEntries:entries error:NULL];
        MRWriteResult *result = [self emptyResult];
        result.permanentlyFailedEntries = entries;
        result.error = error;
        [self finishWithResult:result completion:completion];
        return;
    }

    NSInteger maximumAttempts = [self maximumAttemptsForErrorKind:kind];
    if (maximumAttempts > 0) {
        NSInteger attempts = 0;
        for (MROutboxEntry *entry in entries) {
            entry.attempts += 1;
            attempts = MAX(attempts, entry.attempts);
        }
        [self.outbox save:NULL];

        if (attempts < maximumAttempts) {
            NSTimeInterval delay = [self retryDelayForErrorKind:kind
                                                       attempts:attempts];
            [self.clock after:delay perform:^{
                [self sendBatch:entries completion:completion];
            }];
            return;
        }
    }

    MRWriteResult *result = [self emptyResult];
    result.error = error;
    [self finishWithResult:result completion:completion];
}

#pragma mark - Success handling

- (void)handleSuccessForEntries:(NSArray *)entries
                           json:(NSDictionary *)json
                     completion:(void (^)(MRWriteResult *result))completion {
    NSDictionary *response =
        [json isKindOfClass:[NSDictionary class]] ? json : @{};

    NSMutableSet *notFoundIDs = [NSMutableSet set];
    MRWriteCollectListedIDs([response objectForKey:@"not_found"], notFoundIDs);

    NSMutableSet *deletedIDs = [NSMutableSet set];
    MRWriteCollectListedIDs([response objectForKey:@"deleted"], deletedIDs);

    NSMutableDictionary *resolvedByID = [NSMutableDictionary dictionary];
    MRWriteCollectResolvedStatuses([response objectForKey:@"added"], resolvedByID);

    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *permanentlyFailed = [NSMutableArray array];
    NSMutableDictionary *resolvedStatuses = [NSMutableDictionary dictionary];

    for (MROutboxEntry *entry in entries) {
        if ([notFoundIDs containsObject:@(entry.simklID)]) {
            [permanentlyFailed addObject:entry];
            continue;
        }

        [succeeded addObject:entry];

        NSNumber *resolvedNumber = [resolvedByID objectForKey:@(entry.simklID)];
        MRWatchStatus resolvedStatus = resolvedNumber != nil
            ? (MRWatchStatus)[resolvedNumber integerValue] : MRWatchStatusNone;
        if (resolvedStatus != MRWatchStatusNone && entry.entryID.length > 0) {
            [resolvedStatuses setObject:@(resolvedStatus) forKey:entry.entryID];
        }

        switch (entry.kind) {
            case MROutboxEntryKindStatus:
            case MROutboxEntryKindHistoryWhole: {
                MRWatchStatus status = resolvedStatus != MRWatchStatusNone
                    ? resolvedStatus : entry.status;
                if (status != MRWatchStatusNone) {
                    [self.libraryStore applyResolvedStatus:status
                                               forItemType:entry.type
                                                   simklID:entry.simklID
                                                     error:NULL];
                }
                break;
            }
            case MROutboxEntryKindHistoryEpisode:
                if (resolvedStatus != MRWatchStatusNone) {
                    [self.libraryStore applyResolvedStatus:resolvedStatus
                                               forItemType:entry.type
                                                   simklID:entry.simklID
                                                     error:NULL];
                }
                break;
            case MROutboxEntryKindRating:
                [self.libraryStore applyUserRating:entry.rating
                                       forItemType:entry.type
                                           simklID:entry.simklID
                                             error:NULL];
                break;
            case MROutboxEntryKindRatingRemove:
                [self.libraryStore applyUserRating:0
                                       forItemType:entry.type
                                           simklID:entry.simklID
                                             error:NULL];
                break;
            case MROutboxEntryKindRemove:
                if ([deletedIDs containsObject:@(entry.simklID)]) {
                    [self.libraryStore removeItemForType:entry.type
                                                 simklID:entry.simklID
                                                   error:NULL];
                }
                break;
            default:
                break;
        }
    }

    NSMutableArray *toRemove = [NSMutableArray arrayWithArray:succeeded];
    [toRemove addObjectsFromArray:permanentlyFailed];
    [self.outbox removeEntries:toRemove error:NULL];

    MRWriteResult *result = [self emptyResult];
    result.succeededEntries = succeeded;
    result.permanentlyFailedEntries = permanentlyFailed;
    result.resolvedStatuses = resolvedStatuses;
    [self finishWithResult:result completion:completion];
}

@end
