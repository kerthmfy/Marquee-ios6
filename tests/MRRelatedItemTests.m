//
//  MRRelatedItemTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRMediaItem.h"

static void MRRunRelatedItemParsing(void) {
    NSDictionary *detail = MRFixture(@"movie-detail");
    NSDictionary *mini = detail[@"users_recommendations"][0];

    MRMediaItem *item = [MRMediaItem itemWithRelatedDictionary:mini];
    MRAssertEqualIntegers(250824, item.simklID, @"related ids.simkl");
    MRAssertEqualIntegers(MRMediaTypeMovie, item.type, @"related type movie");
    MRAssertEqualObjects(@"Arrival", item.title, @"related title");
    MRAssertEqualIntegers(2016, item.year, @"related year");
    MRAssertEqualObjects(@"23/23b2c3d4e5f6a7b8", item.poster, @"related poster");
    MRAssertEqualObjects(@"arrival", item.slug, @"related slug");
    MRAssertEqualObjects(@"", item.fanart, @"missing fanart becomes empty");
    MRAssertEqualIntegers(0, (NSInteger)item.externalIDs.count,
                          @"simkl and slug are not external IDs");
}

static void MRRunRelatedCollectionParsing(void) {
    NSDictionary *detail = MRFixture(@"movie-detail");

    NSArray *similar = [MRMediaItem itemsWithRelatedDictionaries:detail[@"similar"]];
    MRAssertEqualIntegers(1, (NSInteger)similar.count, @"similar collection");
    MRMediaItem *prestige = similar[0];
    MRAssertEqualObjects(@"The Prestige", prestige.title, @"similar title");
    MRAssertEqualIntegers(2006, prestige.year, @"similar year");

    NSArray *missing = [MRMediaItem itemsWithRelatedDictionaries:detail[@"not-there"]];
    MRAssertEqualIntegers(0, (NSInteger)missing.count,
                          @"a missing similar key yields an empty array");

    NSArray *invalid = [MRMediaItem itemsWithRelatedDictionaries:
                        @[ @"junk", @{}, @{ @"title": @"No IDs" } ]];
    MRAssertEqualIntegers(0, (NSInteger)invalid.count,
                          @"invalid or id-less related entries are skipped");
}

static void MRRunDetailMerge(void) {
    NSDictionary *sync = MRFixture(@"sync-movies")[@"movies"][0];
    MRMediaItem *snapshot = [MRMediaItem itemWithSyncDictionary:sync
                                                           type:MRMediaTypeMovie];
    snapshot.userRating = 8;
    snapshot.watchStatus = MRWatchStatusCompleted;

    MRMediaItem *merged =
        [snapshot itemByMergingDetailDictionary:MRFixture(@"movie-detail")];
    MRAssertEqualObjects(@"Interstellar", merged.title, @"merge keeps the title");
    MRAssertEqualIntegers(250822, merged.simklID, @"merge keeps the Simkl ID");
    MRAssertEqualIntegers(3, (NSInteger)merged.genres.count, @"merge fills genres");
    MRAssertEqualObjects(@{ @"rating": @8.6, @"votes": @4218 },
                         merged.ratings[@"simkl"], @"merge fills ratings");
    MRAssertEqualObjects(@"tt0816692", merged.externalIDs[@"imdb"],
                         @"merge extends external IDs");
    MRAssertEqualIntegers(MRWatchStatusCompleted, merged.watchStatus,
                          @"merge preserves the watch status");
    MRAssertEqualIntegers(8, merged.userRating, @"merge preserves the user rating");
    MRAssertTrue(merged.detailFetchedAt != nil, @"merge stamps the fetch time");
}

void MRRunRelatedItemTests(void) {
    MRRunRelatedItemParsing();
    MRRunRelatedCollectionParsing();
    MRRunDetailMerge();
}
