//
//  MREpisodeTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRDate.h"
#import "MREpisode.h"
#import "MRMediaType.h"

void MRRunEpisodeTests(void) {
    NSDictionary *tvDictionary = @{
        @"season": @1,
        @"episode": @2,
        @"title": @"Winter Is Coming",
        @"description": @"Lord Ned Stark is troubled by disturbing reports.",
        @"runtime": @61,
        @"img": @"31/318121421ca3e9c34",
        @"date": @"2011-04-17T21:00:00-04:00",
        @"aired": @YES,
        @"type": @"episode"
    };
    MREpisode *tv = [MREpisode episodeWithDictionary:tvDictionary type:MRMediaTypeShow];
    MRAssertEqualIntegers(tv.season, 1, @"episode season");
    MRAssertEqualIntegers(tv.number, 2, @"episode number");
    MRAssertEqualObjects(tv.title, @"Winter Is Coming", @"episode title");
    MRAssertEqualObjects(tv.summary,
                         @"Lord Ned Stark is troubled by disturbing reports.",
                         @"episode summary");
    MRAssertEqualIntegers(tv.runtime, 61, @"episode runtime");
    MRAssertEqualObjects(tv.imagePath, @"31/318121421ca3e9c34", @"episode image");
    MRAssertTrue(tv.aired, @"episode aired flag");
    MRAssertTrue(!tv.special, @"regular episode is not special");
    MRAssertEqualObjects([MRDate isoStringFromDate:tv.airDate],
                         @"2011-04-17T00:00:00Z",
                         @"offset air date keeps its calendar day");
    MRAssertEqualObjects([tv codeText], @"S1E2", @"season episode code");

    NSDictionary *animeDictionary = @{
        @"episode": @1,
        @"title": @"Episode 1",
        @"description": [NSNull null],
        @"runtime": @25,
        @"img": [NSNull null],
        @"date": @"2023-09-29T23:00:00+09:00"
    };
    MREpisode *anime = [MREpisode episodeWithDictionary:animeDictionary
                                                  type:MRMediaTypeAnime];
    MRAssertEqualIntegers(anime.season, 1, @"anime missing season defaults to one");
    MRAssertEqualObjects(anime.summary, @"", @"null summary defaults empty");
    MRAssertTrue(anime.imagePath == nil, @"null image defaults nil");
    MRAssertTrue(anime.aired, @"missing aired flag defaults yes");
    MRAssertEqualObjects([anime codeText], @"S1E1", @"anime episode code");

    NSArray *unsorted = @[
        @{ @"season": @0, @"episode": @3, @"title": @"Reunion",
           @"type": @"special", @"date": @"2021-04-16T21:00:00-04:00" },
        @{ @"season": @2, @"episode": @1, @"title": @"The North Remembers" },
        @{ @"season": @1, @"episode": @10, @"title": @"Fire and Blood" },
        @{ @"season": @1, @"episode": @2, @"title": @"The Kingsroad" }
    ];
    NSArray *sorted = [MREpisode episodesWithDictionaries:unsorted type:MRMediaTypeShow];
    MRAssertEqualIntegers(sorted.count, 4, @"all valid episodes kept");
    MRAssertEqualObjects([(MREpisode *)sorted[0] codeText], @"S1E2", @"season one sorts first");
    MRAssertEqualObjects([(MREpisode *)sorted[1] codeText], @"S1E10", @"episode numbers sort numerically");
    MRAssertEqualObjects([(MREpisode *)sorted[2] codeText], @"S2E1", @"later seasons sort after");
    MRAssertEqualObjects([(MREpisode *)sorted[3] codeText], @"Special 3", @"specials sort last");
    MRAssertTrue([(MREpisode *)sorted[3] isSpecial], @"season zero is special");

    NSArray *invalid = @[
        [NSNull null],
        @{ @"season": @1 },
        @{ @"season": @1, @"episode": @0 },
        @{ @"season": @1, @"episode": @"not a number" }
    ];
    MRAssertEqualIntegers([MREpisode episodesWithDictionaries:invalid
                                                         type:MRMediaTypeShow].count,
                          0, @"invalid episodes skipped");

    MREpisode *noDate = [MREpisode episodeWithDictionary:@{ @"episode": @4 }
                                                   type:MRMediaTypeShow];
    MRAssertTrue(noDate.airDate == nil, @"malformed date defaults nil");
    MRAssertEqualObjects([noDate codeText], @"S1E4", @"missing season still displays");
}
