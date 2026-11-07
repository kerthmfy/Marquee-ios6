//
//  MROutboxTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRMediaItem.h"
#import "MROutbox.h"
#import "MROutboxEntry.h"
#import "MRStorage.h"

static NSString *MROutboxTestDirectory(void) {
    NSString *directory =
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"MarqueeOutboxTests-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

static void MROutboxRemoveDirectory(NSString *directory) {
    if (directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    }
}

static MRMediaItem *MROutboxItem(MRMediaType type, NSInteger simklID, NSString *title) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.type = type;
    item.simklID = simklID;
    item.slug = [title lowercaseString];
    item.title = title;
    item.year = 2022;
    item.externalIDs = @{ @"imdb": [NSString stringWithFormat:@"tt%ld", (long)simklID] };
    return item;
}

static MROutboxEntry *MROutboxStatusEntry(MRMediaItem *item, MRWatchStatus status) {
    return [MROutboxEntry statusEntryWithItem:item
                                       status:status
                               previousStatus:item.watchStatus];
}

static void MRRunStatusCoalescing(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeShow, 123, @"The Bear");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:MROutboxStatusEntry(item, MRWatchStatusWatching)
                                error:&error],
                 @"enqueue first status");
    MRAssertTrue([outbox enqueueEntry:MROutboxStatusEntry(item, MRWatchStatusCompleted)
                                error:&error],
                 @"enqueue replacement status");

    MRAssertEqualIntegers(1, (NSInteger)outbox.entries.count,
                          @"a newer status replaces the older status");
    MROutboxEntry *entry = outbox.entries.firstObject;
    MRAssertEqualIntegers(MROutboxEntryKindStatus, entry.kind, @"coalesced kind");
    MRAssertEqualIntegers(MRWatchStatusCompleted, entry.status,
                          @"coalesced status is the newer value");
    MRAssertEqualIntegers(123, entry.simklID, @"coalesced item id");
    MROutboxRemoveDirectory(directory);
}

static void MRRunRatingCoalescing(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeMovie, 789, @"Arrival");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry ratingEntryWithItem:item
                                              rating:8
                                      previousRating:0]
                                error:&error],
                 @"enqueue rating 8");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry ratingEntryWithItem:item
                                              rating:9
                                      previousRating:8]
                                error:&error],
                 @"enqueue rating 9");

    MRAssertEqualIntegers(1, (NSInteger)outbox.entries.count,
                          @"a newer rating replaces the older rating");
    MROutboxEntry *entry = outbox.entries.firstObject;
    MRAssertEqualIntegers(MROutboxEntryKindRating, entry.kind, @"rating kind");
    MRAssertEqualIntegers(9, entry.rating, @"rating is the newer value");
    MROutboxRemoveDirectory(directory);
}

static void MRRunRemoveCancelsPendingWrites(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeShow, 123, @"The Bear");
    MRMediaItem *other = MROutboxItem(MRMediaTypeShow, 456, @"Severance");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:MROutboxStatusEntry(item, MRWatchStatusWatching)
                                error:&error], @"enqueue status");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyWholeEntryWithItem:item
                                                    status:MRWatchStatusCompleted]
                                error:&error], @"enqueue whole history");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry ratingEntryWithItem:item
                                              rating:8
                                      previousRating:0]
                                error:&error], @"enqueue rating");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry ratingEntryWithItem:other
                                              rating:7
                                      previousRating:0]
                                error:&error], @"enqueue other item rating");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry removeEntryWithItem:item
                                      previousStatus:MRWatchStatusWatching
                                      previousRating:8]
                                error:&error], @"enqueue remove");

    MRAssertEqualIntegers(2, (NSInteger)outbox.entries.count,
                          @"remove cancels every pending write for its item");
    MROutboxEntry *first = outbox.entries.firstObject;
    MROutboxEntry *second = outbox.entries.lastObject;
    MRAssertEqualIntegers(456, first.simklID, @"unrelated item survives");
    MRAssertEqualIntegers(123, second.simklID, @"remove is queued");
    MRAssertEqualIntegers(MROutboxEntryKindRemove, second.kind, @"remove kind");
    MROutboxRemoveDirectory(directory);
}

static void MRRunWholeHistoryCancelsStatus(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeShow, 123, @"The Bear");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:MROutboxStatusEntry(item, MRWatchStatusWatching)
                                error:&error], @"enqueue status");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry ratingEntryWithItem:item
                                              rating:8
                                      previousRating:0]
                                error:&error], @"enqueue rating");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyWholeEntryWithItem:item
                                                    status:MRWatchStatusCompleted]
                                error:&error], @"enqueue whole history");

    MRAssertEqualIntegers(2, (NSInteger)outbox.entries.count,
                          @"whole history cancels only the pending status");
    MROutboxEntry *first = outbox.entries.firstObject;
    MROutboxEntry *second = outbox.entries.lastObject;
    MRAssertEqualIntegers(MROutboxEntryKindRating, first.kind,
                          @"rating remains queued");
    MRAssertEqualIntegers(MROutboxEntryKindHistoryWhole, second.kind,
                          @"whole history remains queued");
    MROutboxRemoveDirectory(directory);
}

static void MRRunDuplicateEpisodeDropped(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeShow, 123, @"The Bear");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:item season:2 episode:5]
                                error:&error], @"enqueue first episode");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:item season:2 episode:5]
                                error:&error], @"enqueue duplicate episode");
    MRAssertEqualIntegers(1, (NSInteger)outbox.entries.count,
                          @"a duplicate history episode is dropped");

    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:item season:2 episode:6]
                                error:&error], @"enqueue next episode");
    MRAssertEqualIntegers(2, (NSInteger)outbox.entries.count,
                          @"a different episode is kept");
    MROutboxRemoveDirectory(directory);
}

static void MRRunFIFOAcrossItems(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:
                  MROutboxStatusEntry(MROutboxItem(MRMediaTypeMovie, 300, @"Third"),
                                      MRWatchStatusCompleted)
                                error:&error], @"enqueue third");
    MRAssertTrue([outbox enqueueEntry:
                  MROutboxStatusEntry(MROutboxItem(MRMediaTypeShow, 100, @"First"),
                                      MRWatchStatusWatching)
                                error:&error], @"enqueue first");
    MRAssertTrue([outbox enqueueEntry:
                  MROutboxStatusEntry(MROutboxItem(MRMediaTypeAnime, 200, @"Second"),
                                      MRWatchStatusPlanToWatch)
                                error:&error], @"enqueue second");

    NSArray *batch = [outbox nextBatchWithLimit:20];
    MRAssertEqualIntegers(3, (NSInteger)batch.count, @"all entries in one batch");
    MRAssertEqualIntegers(300, [[batch objectAtIndex:0] simklID], @"FIFO position 0");
    MRAssertEqualIntegers(100, [[batch objectAtIndex:1] simklID], @"FIFO position 1");
    MRAssertEqualIntegers(200, [[batch objectAtIndex:2] simklID], @"FIFO position 2");
    MROutboxRemoveDirectory(directory);
}

static void MRRunBatchLimit(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];

    NSError *error = nil;
    for (NSInteger index = 0; index < 25; index += 1) {
        MRMediaItem *item = MROutboxItem(MRMediaTypeShow, 1000 + index, @"Batch");
        MRAssertTrue([outbox enqueueEntry:
                      [MROutboxEntry historyEpisodeEntryWithItem:item season:1 episode:1]
                                    error:&error], @"enqueue batch item");
    }

    NSArray *batch = [outbox nextBatchWithLimit:50];
    MRAssertEqualIntegers(20, (NSInteger)batch.count,
                          @"a batch contains at most 20 entries");
    MRAssertEqualIntegers(1000, [[batch objectAtIndex:0] simklID],
                          @"batch starts at the FIFO head");
    MRAssertEqualIntegers(1019, [[batch objectAtIndex:19] simklID],
                          @"batch takes consecutive entries");
    MROutboxRemoveDirectory(directory);
}

static void MRRunBatchStopsAtRepeatedItem(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *a = MROutboxItem(MRMediaTypeShow, 100, @"A");
    MRMediaItem *b = MROutboxItem(MRMediaTypeShow, 200, @"B");
    MRMediaItem *c = MROutboxItem(MRMediaTypeShow, 300, @"C");

    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:a season:1 episode:1]
                                error:&error], @"enqueue A1");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:b season:1 episode:1]
                                error:&error], @"enqueue B1");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:a season:1 episode:2]
                                error:&error], @"enqueue A2");
    MRAssertTrue([outbox enqueueEntry:
                  [MROutboxEntry historyEpisodeEntryWithItem:c season:1 episode:1]
                                error:&error], @"enqueue C1");

    NSArray *batch = [outbox nextBatchWithLimit:20];
    MRAssertEqualIntegers(2, (NSInteger)batch.count,
                          @"batch stops before a repeated item");
    MRAssertEqualIntegers(100, [[batch objectAtIndex:0] simklID],
                          @"repeated item batch starts with A");
    MRAssertEqualIntegers(200, [[batch objectAtIndex:1] simklID],
                          @"repeated item batch ends with B");
    MROutboxRemoveDirectory(directory);
}

static void MRRunPersistenceRoundTrip(void) {
    NSString *directory = MROutboxTestDirectory();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:directory accountID:12345];
    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    MRMediaItem *item = MROutboxItem(MRMediaTypeAnime, 555, @"Frieren");

    MROutboxEntry *entry =
        [MROutboxEntry historyEpisodeEntryWithItem:item season:3 episode:7];
    entry.attempts = 2;
    NSError *error = nil;
    MRAssertTrue([outbox enqueueEntry:entry error:&error], @"enqueue persisted entry");

    MROutbox *loaded = [[MROutbox alloc] initWithStorage:storage];
    NSError *loadError = nil;
    MRAssertTrue([loaded load:&loadError], @"load the persisted outbox");
    MRAssertEqualIntegers(1, (NSInteger)loaded.entries.count, @"one persisted entry");

    MROutboxEntry *restored = loaded.entries.firstObject;
    MRAssertEqualObjects(entry.entryID, restored.entryID, @"entry id round-trips");
    MRAssertEqualIntegers(MROutboxEntryKindHistoryEpisode, restored.kind,
                          @"entry kind round-trips");
    MRAssertEqualIntegers(MRMediaTypeAnime, restored.type, @"entry type round-trips");
    MRAssertEqualIntegers(555, restored.simklID, @"entry id round-trips");
    MRAssertEqualObjects(@"Frieren", restored.title, @"entry title round-trips");
    MRAssertEqualIntegers(3, restored.season, @"entry season round-trips");
    MRAssertEqualIntegers(7, restored.episode, @"entry episode round-trips");
    MRAssertEqualIntegers(2, restored.attempts, @"entry attempts round-trip");
    MROutboxRemoveDirectory(directory);
}

void MRRunOutboxTests(void) {
    MRRunStatusCoalescing();
    MRRunRatingCoalescing();
    MRRunRemoveCancelsPendingWrites();
    MRRunWholeHistoryCancelsStatus();
    MRRunDuplicateEpisodeDropped();
    MRRunFIFOAcrossItems();
    MRRunBatchLimit();
    MRRunBatchStopsAtRepeatedItem();
    MRRunPersistenceRoundTrip();
}
