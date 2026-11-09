//
//  MRDetailActions.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

@class MRLibraryStore;
@class MRMediaItem;
@class MROutbox;
@class MROutboxEntry;
@class MRWriteResult;
@class MRWriteService;

typedef NS_ENUM(NSInteger, MRDetailPrimaryAction) {
    MRDetailPrimaryActionAddToWatchlist = 0,
    MRDetailPrimaryActionMarkWatched,
    MRDetailPrimaryActionStartWatching,
    MRDetailPrimaryActionMarkNextEpisode,
    MRDetailPrimaryActionMarkAllWatched,
    MRDetailPrimaryActionChangeStatus,
    MRDetailPrimaryActionMoveToWatching
};

// Foundation-only action layer behind the detail screen. Every mutation updates
// the local library optimistically, enqueues and saves an outbox entry, and
// returns that entry. The caller flushes the outbox with the write service, which
// owns retries and server-resolved reconciliation. Remove never deletes the
// local item until Simkl confirms the deletion.
@interface MRDetailActions : NSObject

- (instancetype)initWithLibraryStore:(MRLibraryStore *)libraryStore
                              outbox:(MROutbox *)outbox
                        writeService:(MRWriteService *)writeService;

+ (MRDetailPrimaryAction)primaryActionForItem:(MRMediaItem *)item;
+ (NSString *)titleForPrimaryAction:(MRDetailPrimaryAction)action
                               item:(MRMediaItem *)item;
+ (NSArray *)validStatusesForType:(MRMediaType)type;
+ (BOOL)isStatus:(MRWatchStatus)status validForType:(MRMediaType)type;

// Queues a status write. The previous status is recorded for the future undo
// path. Returns nil with an error when the status is invalid for the type or the
// queue cannot be persisted; the optimistic change is reverted in the latter case.
- (MROutboxEntry *)setWatchStatus:(MRWatchStatus)status
                          forItem:(MRMediaItem *)item
                            error:(NSError **)error;

// Queues a whole-history write that marks the item completed.
- (MROutboxEntry *)markWatchedForItem:(MRMediaItem *)item error:(NSError **)error;

// Queues one episode-history write. Callers should use the next-to-watch values
// exactly as sync returned them.
- (MROutboxEntry *)markEpisodeForItem:(MRMediaItem *)item
                               season:(NSInteger)season
                              episode:(NSInteger)episode
                                error:(NSError **)error;

- (MROutboxEntry *)setRating:(NSInteger)rating
                     forItem:(MRMediaItem *)item
                       error:(NSError **)error;
- (MROutboxEntry *)clearRatingForItem:(MRMediaItem *)item error:(NSError **)error;
- (MROutboxEntry *)removeFromLibraryForItem:(MRMediaItem *)item error:(NSError **)error;

// Performs the primary action for the item's current state. Change Status
// returns nil with no error because it needs the controller's action sheet.
- (MROutboxEntry *)performPrimaryActionForItem:(MRMediaItem *)item
                                         error:(NSError **)error;

// Drains batches until the outbox is empty, a batch fails, or no progress is
// possible. The result aggregates every batch in the flush.
- (void)flushWithCompletion:(void (^)(MRWriteResult *result))completion;

@end
