//
//  MROutbox.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRStorage;
@class MROutboxEntry;

// Persistent FIFO write queue. Entries are saved atomically before they are
// sent. A generation mismatch in library.json/state.json never affects this
// file. Coalescing follows the design's per-item rules.
@interface MROutbox : NSObject

@property (nonatomic, strong, readonly) MRStorage *storage;
@property (nonatomic, copy, readonly) NSArray *entries;
@property (nonatomic, readonly) NSUInteger pendingCount;

- (instancetype)initWithStorage:(MRStorage *)storage;

// A missing outbox file loads as an empty queue. A corrupt file, an unknown
// schema, or an account mismatch returns NO and leaves the queue empty.
- (BOOL)load:(NSError **)error;

// Writes the current queue atomically. Called before every POST and after
// successful or permanently-failed entries are removed.
- (BOOL)save:(NSError **)error;

- (BOOL)enqueueEntry:(MROutboxEntry *)entry error:(NSError **)error;
- (BOOL)removeEntry:(MROutboxEntry *)entry error:(NSError **)error;
- (BOOL)removeEntries:(NSArray *)entries error:(NSError **)error;

// The first contiguous run of same-kind entries targeting different items,
// capped at 20. The returned entries stay in the outbox until the caller
// removes them after the server responds.
- (NSArray *)nextBatchWithLimit:(NSUInteger)limit;

- (BOOL)containsEntryWithID:(NSString *)entryID;

@end
