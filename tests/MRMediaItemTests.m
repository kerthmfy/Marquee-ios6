//
//  MRMediaItemTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDate.h"
#import "MRJSON.h"
#import "MRMediaItem.h"
#import "MRMediaType.h"
#import "MRWatchStatus.h"

void MRRunMediaItemTests(void) {
    NSDictionary *show = MRFixture(@"sync-shows")[@"shows"][0];
    MRMediaItem *item = [MRMediaItem itemWithSyncDictionary:show type:MRMediaTypeShow];
    MRAssertEqualIntegers(item.simklID, 3407, @"sync show id");
    MRAssertEqualObjects(item.title, @"Futurama", @"sync show title");
    MRAssertEqualIntegers(item.watchStatus, MRWatchStatusWatching, @"sync status");
    MRAssertEqualIntegers(item.nextEpisodeSeason, 8, @"next season");
    MRAssertEqualIntegers(item.nextEpisodeNumber, 3, @"next episode");
    MRAssertEqualObjects(item.genres, @[], @"missing genres defaults empty");

    NSDictionary *search = ((NSArray *)MRFixture(@"search"))[0];
    MRMediaItem *movie = [MRMediaItem itemWithSearchDictionary:search];
    MRAssertEqualIntegers(movie.simklID, 342994, @"search simkl_id");
    MRAssertEqualIntegers(movie.type, MRMediaTypeMovie, @"search type");
    MRAssertEqualObjects(movie.title, @"John Wick", @"search title");

    MRMediaItem *roundTrip = [MRMediaItem itemWithDictionaryRepresentation:
                              [movie dictionaryRepresentation]];
    MRAssertEqualIntegers(roundTrip.simklID, movie.simklID, @"round-trip id");
    MRAssertEqualObjects(roundTrip.title, movie.title, @"round-trip title");

    // Simkl key helpers shared by later tasks.
    MRAssertEqualIntegers(MRMediaTypeFromSyncKey(@"shows"), MRMediaTypeShow, @"sync key shows");
    MRAssertEqualIntegers(MRMediaTypeFromSyncKey(@"movies"), MRMediaTypeMovie, @"sync key movies");
    MRAssertEqualIntegers(MRMediaTypeFromSyncKey(@"anime"), MRMediaTypeAnime, @"sync key anime");
    MRAssertEqualIntegers(MRMediaTypeFromSearchKey(@"tv"), MRMediaTypeShow, @"search key tv");
    MRAssertEqualObjects(MRMediaTypeAPIPath(MRMediaTypeMovie), @"movies", @"api path movie");
    MRAssertEqualObjects(MRMediaTypeAPIPath(MRMediaTypeShow), @"tv", @"api path show");
    MRAssertEqualObjects(MRMediaTypeAPIPath(MRMediaTypeAnime), @"anime", @"api path anime");
    MRAssertEqualObjects(MRMediaTypeDisplayName(MRMediaTypeShow), @"TV Show", @"display name show");

    MRAssertEqualIntegers(MRWatchStatusFromKey(@"watching"), MRWatchStatusWatching, @"status watching");
    MRAssertEqualIntegers(MRWatchStatusFromKey(@"plantowatch"), MRWatchStatusPlanToWatch, @"status plan");
    MRAssertEqualIntegers(MRWatchStatusFromKey(@"completed"), MRWatchStatusCompleted, @"status completed");
    MRAssertEqualIntegers(MRWatchStatusFromKey(@"hold"), MRWatchStatusHold, @"status hold");
    MRAssertEqualIntegers(MRWatchStatusFromKey(@"dropped"), MRWatchStatusDropped, @"status dropped");
    MRAssertEqualObjects(MRWatchStatusKey(MRWatchStatusPlanToWatch), @"plantowatch", @"status key plan");
    MRAssertEqualObjects(MRWatchStatusDisplayName(MRWatchStatusPlanToWatch), @"Plan to Watch", @"status display plan");
    MRAssertEqualIntegers(MRWatchStatusFromKey((NSString *)[NSNull null]),
                          MRWatchStatusNone, @"null status key");
    MRAssertEqualIntegers(MRMediaTypeFromSyncKey((NSString *)[NSNull null]),
                          MRMediaTypeMovie, @"null media key");
    MRAssertEqualObjects(item.identifier, @"1:3407", @"identifier format");

    // The other sync buckets use the same entry shape.
    MRMediaItem *syncMovie = [MRMediaItem itemWithSyncDictionary:
                              MRFixture(@"sync-movies")[@"movies"][0]
                                                          type:MRMediaTypeMovie];
    MRAssertEqualIntegers(syncMovie.simklID, 250822, @"sync movie id");
    MRAssertEqualIntegers(syncMovie.watchStatus, MRWatchStatusCompleted, @"sync movie status");

    MRMediaItem *anime = [MRMediaItem itemWithSyncDictionary:
                          MRFixture(@"sync-anime")[@"anime"][0]
                                                      type:MRMediaTypeAnime];
    MRAssertEqualIntegers(anime.simklID, 516897, @"sync anime id");
    MRAssertEqualIntegers(anime.type, MRMediaTypeAnime, @"sync anime type");

    // Trending items carry ids.simkl_id rather than ids.simkl.
    MRMediaItem *trending = [MRMediaItem itemWithTrendingDictionary:
                             MRFixture(@"trending-week")[@"tv"][0]
                                                          type:MRMediaTypeShow];
    MRAssertEqualIntegers(trending.simklID, 1515418, @"trending simkl_id");
    MRAssertEqualObjects(trending.title, @"The Bear", @"trending title");
    MRAssertEqualIntegers(trending.type, MRMediaTypeShow, @"trending type");

    // Detail objects use ids.simkl and include ratings, genres, and external IDs.
    MRMediaItem *detail = [MRMediaItem itemWithDetailDictionary:
                           MRFixture(@"movie-detail") type:MRMediaTypeMovie];
    MRAssertEqualIntegers(detail.simklID, 250822, @"detail simkl id");
    MRAssertEqualObjects(detail.slug, @"interstellar", @"detail slug");
    MRAssertEqualIntegers(detail.genres.count, 3, @"detail genres");
    MRAssertEqualObjects(detail.externalIDs[@"imdb"], @"tt0816692", @"detail imdb id");
    MRAssertEqualObjects(detail.ratings[@"simkl"][@"rating"], @8.6, @"detail simkl rating");

    // Null and missing fields normalize instead of crashing or inventing data.
    NSDictionary *sparse = @{
        @"status": [NSNull null],
        @"user_rating": [NSNull null],
        @"last_watched_at": [NSNull null],
        @"show": @{
            @"ids": @{ @"simkl_id": @99 }
        }
    };
    MRMediaItem *empty = [MRMediaItem itemWithSyncDictionary:sparse type:MRMediaTypeShow];
    MRAssertEqualIntegers(empty.simklID, 99, @"ids.simkl_id fallback");
    MRAssertEqualObjects(empty.title, @"", @"missing title defaults empty");
    MRAssertEqualIntegers(empty.year, 0, @"missing year defaults zero");
    MRAssertEqualIntegers(empty.userRating, 0, @"null rating defaults zero");
    MRAssertEqualIntegers(empty.watchStatus, MRWatchStatusNone, @"null status defaults none");
    MRAssertTrue(empty.lastWatchedAt == nil, @"null timestamp defaults nil");
    MRAssertEqualIntegers(empty.nextEpisodeSeason, 0, @"missing next info season");
    MRAssertEqualIntegers(empty.nextEpisodeNumber, 0, @"missing next info episode");
    MRAssertTrue(empty.nextEpisodeTitle == nil, @"missing next info title");
    MRAssertTrue(empty.nextEpisodeDate == nil, @"missing next info date");

    MRMediaItem *copy = [detail copy];
    MRAssertEqualObjects(copy.title, detail.title, @"copy title");
    MRAssertEqualObjects(copy.externalIDs, detail.externalIDs, @"copy external ids");

    // The representation must be JSON-serializable for the snapshot store.
    NSError *error = nil;
    NSData *jsonData = [MRJSON dataFromObject:[detail dictionaryRepresentation]
                                       error:&error];
    MRAssertTrue(jsonData != nil, @"representation is JSON-serializable");
    NSDictionary *jsonObject = [MRJSON objectFromData:jsonData error:&error];
    MRAssertTrue(jsonObject != nil, @"representation parses back");
    MRMediaItem *jsonRoundTrip = [MRMediaItem itemWithDictionaryRepresentation:jsonObject];
    MRAssertEqualObjects(jsonRoundTrip.genres, detail.genres, @"round-trip genres");
    MRAssertEqualObjects(jsonRoundTrip.externalIDs, detail.externalIDs,
                         @"round-trip external ids");

    // Sync timestamps and next-episode metadata also survive a round trip.
    MRMediaItem *showRoundTrip = [MRMediaItem itemWithDictionaryRepresentation:
                                  [item dictionaryRepresentation]];
    MRAssertEqualIntegers(showRoundTrip.nextEpisodeSeason, 8, @"round-trip next season");
    MRAssertEqualObjects([MRDate isoStringFromDate:showRoundTrip.nextEpisodeDate],
                         @"2010-08-19T00:00:00Z", @"round-trip next episode date");
}
