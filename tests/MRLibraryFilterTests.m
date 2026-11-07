//
//  MRLibraryFilterTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDate.h"
#import "MRLibraryFilter.h"
#import "MRMediaItem.h"

static MRMediaItem *MRFilterItem(NSString *title,
                                 MRMediaType type,
                                 MRWatchStatus status,
                                 NSString *lastWatched,
                                 NSString *added) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = (NSInteger)title.hash;
    item.title = title;
    item.type = type;
    item.watchStatus = status;
    item.lastWatchedAt = [MRDate dateFromISOString:lastWatched];
    item.addedToWatchlistAt = [MRDate dateFromISOString:added];
    return item;
}

static void MRRunLibraryTypeAndStatusFilters(void) {
    NSArray *items = @[
        [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-shows")[@"shows"][0]
                                       type:MRMediaTypeShow],
        [MRMediaItem itemWithSyncDictionary:MRFixture(@"sync-movies")[@"movies"][0]
                                       type:MRMediaTypeMovie]
    ];

    NSArray *shows =
        [MRLibraryFilter items:items type:MRMediaTypeShow status:MRWatchStatusNone];
    MRAssertEqualIntegers(1, (NSInteger)shows.count, @"type filter");

    NSArray *watching =
        [MRLibraryFilter items:items type:MRMediaTypeShow status:MRWatchStatusWatching];
    MRAssertEqualIntegers(1, (NSInteger)watching.count, @"status filter");

    NSArray *none =
        [MRLibraryFilter items:items type:MRMediaTypeMovie status:MRWatchStatusWatching];
    MRAssertEqualIntegers(0, (NSInteger)none.count, @"movie never watching");

    NSArray *hold =
        [MRLibraryFilter items:items type:MRMediaTypeMovie status:MRWatchStatusHold];
    MRAssertEqualIntegers(0, (NSInteger)hold.count, @"movie never on hold");

    NSArray *all =
        [MRLibraryFilter items:items type:MRLibraryFilterAllTypes status:MRWatchStatusNone];
    MRAssertEqualIntegers(2, (NSInteger)all.count, @"all types includes every item");

    NSArray *completed =
        [MRLibraryFilter items:items type:MRLibraryFilterAllTypes
                        status:MRWatchStatusCompleted];
    MRAssertEqualIntegers(1, (NSInteger)completed.count,
                          @"all types still respects the status filter");
}

static void MRRunLibrarySortOrder(void) {
    NSArray *items = @[
        MRFilterItem(@"Alpha", MRMediaTypeShow, MRWatchStatusCompleted,
                     @"2026-10-30T12:00:00Z", @"2020-01-01T00:00:00Z"),
        MRFilterItem(@"Bravo", MRMediaTypeMovie, MRWatchStatusCompleted,
                     @"2026-11-01T12:00:00Z", @"2021-01-01T00:00:00Z"),
        MRFilterItem(@"Charlie", MRMediaTypeAnime, MRWatchStatusPlanToWatch,
                     nil, @"2026-10-01T00:00:00Z"),
        MRFilterItem(@"Delta", MRMediaTypeShow, MRWatchStatusPlanToWatch,
                     nil, @"2026-10-02T00:00:00Z"),
        MRFilterItem(@"Echo", MRMediaTypeMovie, MRWatchStatusDropped,
                     nil, nil),
        MRFilterItem(@"Foxtrot", MRMediaTypeShow, MRWatchStatusWatching,
                     nil, nil)
    ];

    NSArray *sorted = [MRLibraryFilter sortedItems:items];
    NSArray *titles = [sorted valueForKey:@"title"];
    NSArray *expected = @[ @"Bravo", @"Alpha", @"Delta", @"Charlie", @"Echo", @"Foxtrot" ];
    MRAssertEqualObjects(expected, titles,
                         @"last watched desc, then added desc, then title");

    NSArray *unchanged = [MRLibraryFilter sortedItems:@[]];
    MRAssertEqualIntegers(0, (NSInteger)unchanged.count, @"an empty library stays empty");
}

void MRRunLibraryFilterTests(void) {
    MRRunLibraryTypeAndStatusFilters();
    MRRunLibrarySortOrder();
}
