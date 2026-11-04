//
//  MRPublicFeedBuilderTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRFeedSection.h"
#import "MRMediaItem.h"
#import "MRMediaType.h"
#import "MRPublicFeedBuilder.h"

static NSDictionary *MRTrendingEntry(NSInteger simklID, NSString *title, NSInteger year) {
    return @{
        @"title": title,
        @"year": [NSNumber numberWithInteger:year],
        @"poster": [NSString stringWithFormat:@"p/%ld", (long)simklID],
        @"ids": @{
            @"simkl_id": [NSNumber numberWithInteger:simklID],
            @"slug": [NSString stringWithFormat:@"slug-%ld", (long)simklID]
        }
    };
}

static NSArray *MRTrendingEntries(NSInteger start, NSInteger count, NSString *prefix) {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        [entries addObject:MRTrendingEntry(start + i,
                                           [NSString stringWithFormat:@"%@ %ld", prefix, (long)i],
                                           2000 + i)];
    }
    return entries;
}

static NSArray *MRBuilderSectionsWithSource(NSArray *sections, MRFeedSource source) {
    NSMutableArray *matches = [NSMutableArray array];
    for (MRFeedSection *section in sections) {
        if (section.source == source) {
            [matches addObject:section];
        }
    }
    return matches;
}

void MRRunPublicFeedBuilderTests(void) {
    // The plan's canonical snippet.
    NSDictionary *trending = MRFixture(@"trending-week");
    NSArray *sections = [MRPublicFeedBuilder signedOutSectionsWithTrending:trending];
    MRAssertTrue(sections.count >= 2, @"has connect hero and trending");
    MRFeedSection *hero = sections[0];
    MRAssertEqualIntegers(hero.kind, MRFeedSectionKindHero, @"hero kind");
    MRAssertEqualIntegers(hero.source, MRFeedSourceConnect, @"connect source");

    MRFeedSection *combined = sections[1];
    MRAssertTrue([combined.title rangeOfString:@"Simkl"].location != NSNotFound, @"Simkl attribution");
    MRAssertTrue([combined.title rangeOfString:@"Trending"].location != NSNotFound, @"Trending attribution");
    MRAssertTrue(combined.items.count > 0, @"combined items");

    NSMutableSet *seen = [NSMutableSet set];
    for (MRFeedSection *section in sections) {
        for (MRMediaItem *item in section.items) {
            MRAssertTrue(![seen containsObject:item.identifier], @"no duplicate items");
            [seen addObject:item.identifier];
        }
    }

    // Exact section metadata.
    MRAssertEqualObjects(hero.title, @"Connect Simkl", @"connect hero title");
    MRAssertEqualIntegers(hero.kind, MRFeedSectionKindHero, @"hero is a hero section");
    MRAssertEqualIntegers(hero.items.count, 0, @"hero has no items");
    MRAssertTrue([hero.subtitle rangeOfString:@"sync"].location != NSNotFound,
                 @"hero subtitle mentions syncing");
    MRAssertTrue([hero.subtitle rangeOfString:@"personal"].location != NSNotFound,
                 @"hero subtitle mentions personalizing");
    MRAssertEqualObjects(combined.title, @"Simkl Trending This Week", @"combined title");
    MRAssertEqualIntegers(combined.kind, MRFeedSectionKindRow, @"combined kind");
    MRAssertEqualIntegers(combined.source, MRFeedSourcePublicTrending, @"combined source");
    MRAssertEqualIntegers(combined.items.count, 3, @"fixture combined items");

    NSArray *typeSections = MRBuilderSectionsWithSource(sections, MRFeedSourcePublicTrending);
    MRAssertEqualIntegers(typeSections.count, 1, @"fixture exhausts its items in the combined row");

    // Missing keys and empty arrays never produce empty rows.
    NSArray *missing = [MRPublicFeedBuilder signedOutSectionsWithTrending:@{}];
    MRAssertEqualIntegers(missing.count, 1, @"empty trending has only the hero");
    MRAssertEqualIntegers(((MRFeedSection *)missing[0]).kind, MRFeedSectionKindHero,
                          @"empty trending hero kind");

    NSArray *empty = [MRPublicFeedBuilder signedOutSectionsWithTrending:
                      @{ @"movies": @[], @"tv": @[], @"anime": @[] }];
    MRAssertEqualIntegers(empty.count, 1, @"empty arrays have only the hero");

    NSArray *onlyMovies = [MRPublicFeedBuilder signedOutSectionsWithTrending:
                           @{ @"movies": MRTrendingEntries(100, 3, @"Movie") }];
    MRAssertEqualIntegers(onlyMovies.count, 2, @"single type makes one combined row");
    MRAssertEqualObjects(((MRFeedSection *)onlyMovies[1]).title,
                         @"Simkl Trending This Week", @"single type combined title");

    // nil trending returns only the hero.
    NSArray *nilSections = [MRPublicFeedBuilder signedOutSectionsWithTrending:nil];
    MRAssertEqualIntegers(nilSections.count, 1, @"nil trending has only the hero");
    MRFeedSection *nilHero = nilSections[0];
    MRAssertEqualIntegers(nilHero.kind, MRFeedSectionKindHero, @"nil hero kind");
    MRAssertEqualIntegers(nilHero.source, MRFeedSourceConnect, @"nil hero source");
    MRAssertEqualObjects(nilHero.items, @[], @"nil hero has empty items");

    // A full week: round-robin combined row, capped type rows, no duplicates.
    NSDictionary *full = @{
        @"movies": MRTrendingEntries(1000, 20, @"Movie"),
        @"tv": MRTrendingEntries(2000, 20, @"Show"),
        @"anime": MRTrendingEntries(3000, 20, @"Anime")
    };
    NSArray *fullSections = [MRPublicFeedBuilder signedOutSectionsWithTrending:full];
    MRAssertEqualIntegers(fullSections.count, 5, @"hero, combined, three type rows");

    NSMutableArray *fullTitles = [NSMutableArray array];
    for (MRFeedSection *section in fullSections) {
        [fullTitles addObject:section.title];
    }
    MRAssertTrue([fullTitles containsObject:@"Trending Movies on Simkl"], @"movie row title");
    MRAssertTrue([fullTitles containsObject:@"Trending TV on Simkl"], @"tv row title");
    MRAssertTrue([fullTitles containsObject:@"Trending Anime on Simkl"], @"anime row title");


    MRFeedSection *fullCombined = fullSections[1];
    MRAssertEqualIntegers(fullCombined.items.count, 12, @"combined row caps at 12");

    NSMutableSet *combinedTypes = [NSMutableSet set];
    for (MRMediaItem *item in fullCombined.items) {
        [combinedTypes addObject:[NSNumber numberWithInteger:item.type]];
    }
    MRAssertTrue([combinedTypes containsObject:[NSNumber numberWithInteger:MRMediaTypeMovie]],
                 @"combined has movies");
    MRAssertTrue([combinedTypes containsObject:[NSNumber numberWithInteger:MRMediaTypeShow]],
                 @"combined has TV");
    MRAssertTrue([combinedTypes containsObject:[NSNumber numberWithInteger:MRMediaTypeAnime]],
                 @"combined has anime");

    // Round robin starts movie, TV, anime.
    MRAssertEqualIntegers(((MRMediaItem *)fullCombined.items[0]).type, MRMediaTypeMovie,
                          @"round robin starts with a movie");
    MRAssertEqualIntegers(((MRMediaItem *)fullCombined.items[1]).type, MRMediaTypeShow,
                          @"round robin then TV");
    MRAssertEqualIntegers(((MRMediaItem *)fullCombined.items[2]).type, MRMediaTypeAnime,
                          @"round robin then anime");

    NSMutableSet *fullSeen = [NSMutableSet set];
    for (MRFeedSection *section in fullSections) {
        for (MRMediaItem *item in section.items) {
            MRAssertTrue(![fullSeen containsObject:item.identifier],
                         @"full feed identifiers are unique");
            [fullSeen addObject:item.identifier];
        }
    }

    for (MRFeedSection *section in fullSections) {
        if (section == fullSections[0]) {
            continue;
        }
        MRAssertEqualIntegers(section.items.count, 12, @"every full-feed row caps at 12");
        MRAssertTrue(section.items.count > 0, @"no empty full-feed rows");
    }

    NSMutableDictionary *typesByTitle = [NSMutableDictionary dictionary];
    for (MRFeedSection *section in fullSections) {
        if (section == fullSections[0]) {
            continue;
        }
        MRMediaItem *first = section.items[0];
        [typesByTitle setObject:[NSNumber numberWithInteger:first.type] forKey:section.title];
    }
    MRAssertEqualIntegers([[typesByTitle objectForKey:@"Trending Movies on Simkl"] integerValue],
                          MRMediaTypeMovie, @"movie row holds movies");
    MRAssertEqualIntegers([[typesByTitle objectForKey:@"Trending TV on Simkl"] integerValue],
                          MRMediaTypeShow, @"tv row holds TV");
    MRAssertEqualIntegers([[typesByTitle objectForKey:@"Trending Anime on Simkl"] integerValue],
                          MRMediaTypeAnime, @"anime row holds anime");

    // Malformed entries are skipped, including fake IDs and blank titles.
    NSDictionary *malformed = @{
        @"movies": @[
            @"not a dictionary",
            [NSNumber numberWithInteger:7],
            @{ @"ids": @{ @"simkl_id": [NSNumber numberWithInteger:11] } },
            @{ @"title": @"Missing ids" },
            @{ @"title": @"Zero id", @"ids": @{ @"simkl_id": [NSNumber numberWithInteger:0] } },
            @{ @"title": [NSNull null], @"ids": @{ @"simkl_id": [NSNumber numberWithInteger:12] } },
            MRTrendingEntry(13, @"Real Movie", 2024)
        ],
        @"tv": @"not an array",
        @"anime": @[ @{ @"title": @"Null ids", @"ids": [NSNull null] },
                     MRTrendingEntry(14, @"Real Anime", 2023) ]
    };
    NSArray *malformedSections = [MRPublicFeedBuilder signedOutSectionsWithTrending:malformed];
    NSMutableArray *malformedTitles = [NSMutableArray array];
    for (MRFeedSection *section in malformedSections) {
        for (MRMediaItem *item in section.items) {
            [malformedTitles addObject:item.title];
        }
    }
    MRAssertEqualIntegers(malformedTitles.count, 2, @"only valid entries survive");
    MRAssertTrue([malformedTitles containsObject:@"Real Movie"], @"valid movie survives");
    MRAssertTrue([malformedTitles containsObject:@"Real Anime"], @"valid anime survives");
    MRAssertTrue(![malformedTitles containsObject:@""], @"no blank titles survive");

    // Duplicate identifiers inside a type list are only kept once.
    NSDictionary *duplicates = @{
        @"tv": @[
            MRTrendingEntry(200, @"Duplicate Show", 2020),
            MRTrendingEntry(200, @"Duplicate Show", 2020),
            MRTrendingEntry(201, @"Other Show", 2021)
        ]
    };
    NSArray *duplicateSections = [MRPublicFeedBuilder signedOutSectionsWithTrending:duplicates];
    MRAssertEqualIntegers(duplicateSections.count, 2, @"duplicate list has one combined row");
    MRAssertEqualIntegers(((MRFeedSection *)duplicateSections[1]).items.count, 2,
                          @"duplicates collapse");
}
