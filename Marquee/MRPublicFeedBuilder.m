//
//  MRPublicFeedBuilder.m
//  Marquee
//

#import "MRPublicFeedBuilder.h"

#import "MRFeedSection.h"
#import "MRMediaItem.h"
#import "MRMediaType.h"

static const NSUInteger MRPublicFeedRowLimit = 12;

static NSString *const MRPublicFeedCombinedTitle = @"Simkl Trending This Week";
static NSString *const MRPublicFeedMovieTitle = @"Trending Movies on Simkl";
static NSString *const MRPublicFeedTVTitle = @"Trending TV on Simkl";
static NSString *const MRPublicFeedAnimeTitle = @"Trending Anime on Simkl";
static NSString *const MRPublicFeedHeroTitle = @"Connect Simkl";
static NSString *const MRPublicFeedHeroSubtitle =
    @"Sign in to sync your library and make For You personal.";

static NSArray *MRPublicFeedItems(id entries, MRMediaType type) {
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id entry in (NSArray *)entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        MRMediaItem *item = [MRMediaItem itemWithTrendingDictionary:entry type:type];
        if (item.title.length == 0 || item.simklID <= 0) {
            continue;
        }
        if ([seen containsObject:item.identifier]) {
            continue;
        }
        [seen addObject:item.identifier];
        [items addObject:item];
    }
    return items;
}

static void MRPublicFeedAppendRow(NSMutableArray *sections,
                                  NSString *title,
                                  NSArray *items) {
    if (items.count == 0) {
        return;
    }
    [sections addObject:[MRFeedSection rowSectionWithSource:MRFeedSourcePublicTrending
                                                       title:title
                                                       items:items]];
}

@implementation MRPublicFeedBuilder

+ (NSArray *)signedOutSectionsWithTrending:(NSDictionary *)trending {
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[MRFeedSection heroSectionWithSource:MRFeedSourceConnect
                                                       title:MRPublicFeedHeroTitle
                                                    subtitle:MRPublicFeedHeroSubtitle]];

    NSDictionary *payload = [trending isKindOfClass:[NSDictionary class]] ? trending : @{};
    NSArray *movies = MRPublicFeedItems(payload[@"movies"], MRMediaTypeMovie);
    NSArray *shows = MRPublicFeedItems(payload[@"tv"], MRMediaTypeShow);
    NSArray *anime = MRPublicFeedItems(payload[@"anime"], MRMediaTypeAnime);

    NSArray *lists = @[ movies, shows, anime ];
    NSMutableSet *usedIdentifiers = [NSMutableSet set];

    NSMutableArray *combined = [NSMutableArray array];
    NSUInteger index = 0;
    BOOL advanced = YES;
    while (combined.count < MRPublicFeedRowLimit && advanced) {
        advanced = NO;
        for (NSArray *list in lists) {
            if (index >= list.count) {
                continue;
            }
            MRMediaItem *item = [list objectAtIndex:index];
            if (![usedIdentifiers containsObject:item.identifier]) {
                [usedIdentifiers addObject:item.identifier];
                [combined addObject:item];
            }
            advanced = YES;
            if (combined.count >= MRPublicFeedRowLimit) {
                break;
            }
        }
        index += 1;
    }

    MRPublicFeedAppendRow(sections, MRPublicFeedCombinedTitle, combined);

    NSArray *typeTitles = @[ MRPublicFeedMovieTitle,
                             MRPublicFeedTVTitle,
                             MRPublicFeedAnimeTitle ];
    for (NSUInteger typeIndex = 0; typeIndex < lists.count; typeIndex++) {
        NSArray *list = [lists objectAtIndex:typeIndex];
        NSMutableArray *remaining = [NSMutableArray array];
        for (MRMediaItem *item in list) {
            if (remaining.count >= MRPublicFeedRowLimit) {
                break;
            }
            if ([usedIdentifiers containsObject:item.identifier]) {
                continue;
            }
            [usedIdentifiers addObject:item.identifier];
            [remaining addObject:item];
        }
        MRPublicFeedAppendRow(sections, [typeTitles objectAtIndex:typeIndex], remaining);
    }

    return sections;
}

@end
