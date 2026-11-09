//
//  MRDetailActions.m
//  Marquee
//

#import "MRDetailActions.h"

#import "MRError.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRWriteResult.h"
#import "MRWriteService.h"

@interface MRDetailActions ()
@property (nonatomic, strong) MRLibraryStore *libraryStore;
@property (nonatomic, strong) MROutbox *outbox;
@property (nonatomic, strong) MRWriteService *writeService;
@end

@implementation MRDetailActions

- (instancetype)initWithLibraryStore:(MRLibraryStore *)libraryStore
                              outbox:(MROutbox *)outbox
                        writeService:(MRWriteService *)writeService {
    self = [super init];
    if (self) {
        _libraryStore = libraryStore;
        _outbox = outbox;
        _writeService = writeService;
    }
    return self;
}

#pragma mark - Primary action table

+ (MRDetailPrimaryAction)primaryActionForItem:(MRMediaItem *)item {
    if (item == nil) {
        return MRDetailPrimaryActionChangeStatus;
    }

    switch (item.watchStatus) {
        case MRWatchStatusNone:
            return MRDetailPrimaryActionAddToWatchlist;
        case MRWatchStatusPlanToWatch:
            return item.type == MRMediaTypeMovie
                ? MRDetailPrimaryActionMarkWatched
                : MRDetailPrimaryActionStartWatching;
        case MRWatchStatusWatching:
            if (item.type == MRMediaTypeMovie) {
                return MRDetailPrimaryActionMarkWatched;
            }
            if (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) {
                return MRDetailPrimaryActionMarkNextEpisode;
            }
            return MRDetailPrimaryActionMarkAllWatched;
        case MRWatchStatusCompleted:
            return MRDetailPrimaryActionChangeStatus;
        case MRWatchStatusHold:
        case MRWatchStatusDropped:
            return item.type == MRMediaTypeMovie
                ? MRDetailPrimaryActionChangeStatus
                : MRDetailPrimaryActionMoveToWatching;
        default:
            return MRDetailPrimaryActionChangeStatus;
    }
}

+ (NSString *)titleForPrimaryAction:(MRDetailPrimaryAction)action
                               item:(MRMediaItem *)item {
    switch (action) {
        case MRDetailPrimaryActionAddToWatchlist:
            return @"Add to Watchlist";
        case MRDetailPrimaryActionMarkWatched:
            return @"Mark Watched";
        case MRDetailPrimaryActionStartWatching:
            return @"Start Watching";
        case MRDetailPrimaryActionMarkNextEpisode:
            if (item.nextEpisodeSeason > 0 && item.nextEpisodeNumber > 0) {
                return [NSString stringWithFormat:@"Mark S%ldE%ld Watched",
                        (long)item.nextEpisodeSeason, (long)item.nextEpisodeNumber];
            }
            return @"Mark Next Episode Watched";
        case MRDetailPrimaryActionMarkAllWatched:
            return @"Mark All Watched";
        case MRDetailPrimaryActionChangeStatus:
            return @"Change Status";
        case MRDetailPrimaryActionMoveToWatching:
            return @"Move to Watching";
        default:
            return @"Change Status";
    }
}

+ (NSArray *)validStatusesForType:(MRMediaType)type {
    if (type == MRMediaTypeMovie) {
        return @[ @(MRWatchStatusPlanToWatch), @(MRWatchStatusCompleted),
                  @(MRWatchStatusDropped) ];
    }
    return @[ @(MRWatchStatusWatching), @(MRWatchStatusPlanToWatch),
              @(MRWatchStatusCompleted), @(MRWatchStatusHold),
              @(MRWatchStatusDropped) ];
}

+ (BOOL)isStatus:(MRWatchStatus)status validForType:(MRMediaType)type {
    for (NSNumber *number in [self validStatusesForType:type]) {
        if ([number integerValue] == (NSInteger)status) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Actions

- (MRMediaItem *)storedItemForItem:(MRMediaItem *)item {
    if (item == nil || item.simklID <= 0) {
        return nil;
    }
    return [self.libraryStore itemForType:item.type simklID:item.simklID];
}

- (NSError *)invalidActionError {
    return [MRError errorWithKind:MRErrorKindClientRejected];
}

- (MROutboxEntry *)setWatchStatus:(MRWatchStatus)status
                          forItem:(MRMediaItem *)item
                            error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (item == nil || item.simklID <= 0) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }
    if (status == MRWatchStatusNone ||
        ![MRDetailActions isStatus:status validForType:item.type]) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }

    MRMediaItem *stored = [self storedItemForItem:item];
    MRWatchStatus previous = stored != nil ? stored.watchStatus : item.watchStatus;
    MROutboxEntry *entry =
        [MROutboxEntry statusEntryWithItem:item
                                    status:status
                            previousStatus:previous];

    if (stored != nil) {
        [self.libraryStore applyResolvedStatus:status
                                   forItemType:item.type
                                       simklID:item.simklID
                                         error:NULL];
    }

    NSError *saveError = nil;
    if (![self.outbox enqueueEntry:entry error:&saveError]) {
        if (stored != nil && previous != MRWatchStatusNone) {
            [self.libraryStore applyResolvedStatus:previous
                                       forItemType:item.type
                                           simklID:item.simklID
                                             error:NULL];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return nil;
    }
    return entry;
}

- (MROutboxEntry *)markWatchedForItem:(MRMediaItem *)item error:(NSError **)error {
    return [self enqueueHistoryEntryForItem:item
                                      season:0
                                     episode:0
                                      status:MRWatchStatusCompleted
                                       error:error];
}

- (MROutboxEntry *)markEpisodeForItem:(MRMediaItem *)item
                               season:(NSInteger)season
                              episode:(NSInteger)episode
                                error:(NSError **)error {
    return [self enqueueHistoryEntryForItem:item
                                      season:season
                                     episode:episode
                                      status:MRWatchStatusNone
                                       error:error];
}

- (MROutboxEntry *)enqueueHistoryEntryForItem:(MRMediaItem *)item
                                       season:(NSInteger)season
                                      episode:(NSInteger)episode
                                       status:(MRWatchStatus)status
                                        error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (item == nil || item.simklID <= 0) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }

    MROutboxEntry *entry = nil;
    if (season > 0 && episode > 0) {
        entry = [MROutboxEntry historyEpisodeEntryWithItem:item
                                                    season:season
                                                   episode:episode];
    } else {
        entry = [MROutboxEntry historyWholeEntryWithItem:item
                                                  status:status != MRWatchStatusNone
                                                      ? status : MRWatchStatusCompleted];
    }

    MRMediaItem *stored = [self storedItemForItem:item];
    MRWatchStatus previous = stored != nil ? stored.watchStatus : item.watchStatus;
    if (stored != nil && status != MRWatchStatusNone && previous != status) {
        [self.libraryStore applyResolvedStatus:status
                                   forItemType:item.type
                                       simklID:item.simklID
                                         error:NULL];
    }

    NSError *saveError = nil;
    if (![self.outbox enqueueEntry:entry error:&saveError]) {
        if (stored != nil && status != MRWatchStatusNone && previous != status &&
            previous != MRWatchStatusNone) {
            [self.libraryStore applyResolvedStatus:previous
                                       forItemType:item.type
                                           simklID:item.simklID
                                             error:NULL];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return nil;
    }
    return entry;
}

- (MROutboxEntry *)setRating:(NSInteger)rating
                     forItem:(MRMediaItem *)item
                       error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (item == nil || item.simklID <= 0 || rating < 1 || rating > 10) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }

    MRMediaItem *stored = [self storedItemForItem:item];
    NSInteger previous = stored != nil ? stored.userRating : item.userRating;
    MROutboxEntry *entry = [MROutboxEntry ratingEntryWithItem:item
                                                       rating:rating
                                               previousRating:previous];

    if (stored != nil) {
        [self.libraryStore applyUserRating:rating
                               forItemType:item.type
                                   simklID:item.simklID
                                     error:NULL];
    }

    NSError *saveError = nil;
    if (![self.outbox enqueueEntry:entry error:&saveError]) {
        if (stored != nil) {
            [self.libraryStore applyUserRating:previous
                                   forItemType:item.type
                                       simklID:item.simklID
                                         error:NULL];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return nil;
    }
    return entry;
}

- (MROutboxEntry *)clearRatingForItem:(MRMediaItem *)item error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (item == nil || item.simklID <= 0) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }

    MRMediaItem *stored = [self storedItemForItem:item];
    NSInteger previous = stored != nil ? stored.userRating : item.userRating;
    MROutboxEntry *entry =
        [MROutboxEntry ratingRemoveEntryWithItem:item previousRating:previous];

    if (stored != nil) {
        [self.libraryStore applyUserRating:0
                               forItemType:item.type
                                   simklID:item.simklID
                                     error:NULL];
    }

    NSError *saveError = nil;
    if (![self.outbox enqueueEntry:entry error:&saveError]) {
        if (stored != nil) {
            [self.libraryStore applyUserRating:previous
                                   forItemType:item.type
                                       simklID:item.simklID
                                         error:NULL];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return nil;
    }
    return entry;
}

- (MROutboxEntry *)removeFromLibraryForItem:(MRMediaItem *)item
                                      error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (item == nil || item.simklID <= 0) {
        if (error != NULL) {
            *error = [self invalidActionError];
        }
        return nil;
    }

    MRMediaItem *stored = [self storedItemForItem:item];
    MRWatchStatus previousStatus = stored != nil ? stored.watchStatus : item.watchStatus;
    NSInteger previousRating = stored != nil ? stored.userRating : item.userRating;

    // Remove is deliberately not optimistic: the item stays in the library
    // until Simkl confirms it in the response's "deleted" list.
    MROutboxEntry *entry =
        [MROutboxEntry removeEntryWithItem:item
                            previousStatus:previousStatus
                            previousRating:previousRating];

    NSError *saveError = nil;
    if (![self.outbox enqueueEntry:entry error:&saveError]) {
        if (error != NULL) {
            *error = saveError;
        }
        return nil;
    }
    return entry;
}

- (MROutboxEntry *)performPrimaryActionForItem:(MRMediaItem *)item
                                         error:(NSError **)error {
    MRDetailPrimaryAction action = [MRDetailActions primaryActionForItem:item];
    switch (action) {
        case MRDetailPrimaryActionAddToWatchlist:
            return [self setWatchStatus:MRWatchStatusPlanToWatch
                                forItem:item
                                  error:error];
        case MRDetailPrimaryActionMarkWatched:
        case MRDetailPrimaryActionMarkAllWatched:
            return [self markWatchedForItem:item error:error];
        case MRDetailPrimaryActionStartWatching:
        case MRDetailPrimaryActionMoveToWatching:
            return [self setWatchStatus:MRWatchStatusWatching
                                forItem:item
                                  error:error];
        case MRDetailPrimaryActionMarkNextEpisode:
            return [self markEpisodeForItem:item
                                     season:item.nextEpisodeSeason
                                    episode:item.nextEpisodeNumber
                                      error:error];
        case MRDetailPrimaryActionChangeStatus:
            if (error != NULL) {
                *error = nil;
            }
            return nil;
        default:
            if (error != NULL) {
                *error = [self invalidActionError];
            }
            return nil;
    }
}

#pragma mark - Flush

- (void)flushWithCompletion:(void (^)(MRWriteResult *result))completion {
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];
    NSMutableDictionary *statuses = [NSMutableDictionary dictionary];
    [self drainSucceeded:succeeded
                  failed:failed
                statuses:statuses
                   error:nil
              completion:completion];
}

- (void)drainSucceeded:(NSMutableArray *)succeeded
                failed:(NSMutableArray *)failed
              statuses:(NSMutableDictionary *)statuses
                 error:(NSError *)firstError
            completion:(void (^)(MRWriteResult *result))completion {
    if (self.outbox.pendingCount == 0 || self.writeService == nil) {
        [self finishSucceeded:succeeded
                       failed:failed
                     statuses:statuses
                        error:firstError
                   completion:completion];
        return;
    }

    __weak MRDetailActions *weakSelf = self;
    [self.writeService sendEntries:@[] completion:^(MRWriteResult *batch) {
        MRDetailActions *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (batch == nil) {
            batch = [[MRWriteResult alloc] init];
        }

        if (batch.succeededEntries.count > 0) {
            [succeeded addObjectsFromArray:batch.succeededEntries];
        }
        if (batch.permanentlyFailedEntries.count > 0) {
            [failed addObjectsFromArray:batch.permanentlyFailedEntries];
        }
        if (batch.resolvedStatuses.count > 0) {
            [statuses addEntriesFromDictionary:batch.resolvedStatuses];
        }

        NSError *error = firstError != nil ? firstError : batch.error;
        BOOL progressed =
            batch.succeededEntries.count + batch.permanentlyFailedEntries.count > 0;
        BOOL stoppedOnTransient = batch.error != nil &&
            batch.permanentlyFailedEntries.count == 0;
        if (stoppedOnTransient || !progressed ||
            strongSelf.outbox.pendingCount == 0) {
            [strongSelf finishSucceeded:succeeded
                                 failed:failed
                               statuses:statuses
                                  error:error
                             completion:completion];
            return;
        }

        [strongSelf drainSucceeded:succeeded
                            failed:failed
                          statuses:statuses
                             error:error
                        completion:completion];
    }];
}

- (void)finishSucceeded:(NSArray *)succeeded
                 failed:(NSArray *)failed
               statuses:(NSDictionary *)statuses
                  error:(NSError *)error
             completion:(void (^)(MRWriteResult *result))completion {
    MRWriteResult *result = [[MRWriteResult alloc] init];
    result.succeededEntries = succeeded;
    result.permanentlyFailedEntries = failed;
    result.resolvedStatuses = statuses;
    result.error = error;
    if (completion != nil) {
        completion(result);
    }
}

@end
