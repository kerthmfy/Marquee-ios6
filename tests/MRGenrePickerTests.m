//
//  MRGenrePickerTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRFeedSection.h"
#import "MRGenreChoice.h"
#import "MRLibraryStore.h"
#import "MRMediaItem.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"
#import "MRRecommendationEngine.h"
#import "MRResponseCache.h"
#import "MRStorage.h"

#pragma mark - Stub provider

@interface MRGenreStubProvider : NSObject <MRRecommendationDataProviding>
@property (nonatomic, strong) NSMutableDictionary *genreFiles;
@property (nonatomic, strong) NSDictionary *seedDetail;
@property (nonatomic, strong) NSDictionary *trending;
@end

@implementation MRGenreStubProvider

- (id)init {
    self = [super init];
    if (self) {
        _genreFiles = [NSMutableDictionary dictionary];
        _trending = @{};
    }
    return self;
}

- (NSString *)keyForType:(MRMediaType)type slug:(NSString *)slug {
    return [NSString stringWithFormat:@"%ld:%@", (long)type, slug];
}

- (void)setGenreFile:(NSArray *)items type:(MRMediaType)type slug:(NSString *)slug {
    [self.genreFiles setObject:(items != nil ? items : @[])
                        forKey:[self keyForType:type slug:slug]];
}

- (id<MRHTTPTask>)fetchTrendingWeekWithCompletion:
    (void (^)(NSDictionary *json, NSError *error))completion {
    if (completion != nil) {
        completion(self.trending != nil ? self.trending : @{}, nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchGenreIndexForType:(MRMediaType)type
                              completion:(void (^)(NSArray *json, NSError *error))completion {
    if (completion != nil) {
        completion(@[], nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchGenre:(NSString *)slug
                     forType:(MRMediaType)type
                  completion:(void (^)(NSArray *json, NSError *error))completion {
    NSArray *items = [self.genreFiles objectForKey:[self keyForType:type slug:slug]];
    if (completion != nil) {
        completion(items != nil ? items : @[], nil);
    }
    return nil;
}

- (id<MRHTTPTask>)fetchDetailForType:(MRMediaType)type
                            simklID:(NSInteger)simklID
                         completion:(void (^)(NSDictionary *json, NSError *error))completion {
    if (completion != nil) {
        if (self.seedDetail != nil) {
            completion(self.seedDetail, nil);
        } else {
            completion(nil, [NSError errorWithDomain:@"MRGenreStub" code:1 userInfo:nil]);
        }
    }
    return nil;
}

@end

#pragma mark - Helpers

static NSString *MRGenreTestRoot(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"marquee-genre-picker-%@",
             [[NSProcessInfo processInfo] globallyUniqueString]]];
}

static NSArray *MRGenreIndex(void) {
    return @[
        @{ @"name": @"Drama", @"slug": @"drama" },
        @{ @"name": @"Erotica", @"slug": @"erotica" },
        @{ @"name": @"Hentai", @"slug": @"hentai" },
        @{ @"name": @"Video Game Play", @"slug": @"video-game-play" },
        @{ @"name": @"Comedy", @"slug": @"comedy" },
        @{ @"name": @"Erotica Upper", @"slug": @"Erotica" },
        @{ @"name": @"Missing Slug" },
        @{ @"name": @"", @"slug": @"empty-name" },
        @"not a dictionary"
    ];
}

static NSArray *MRGenreChoices(void) {
    NSMutableArray *choices = [NSMutableArray array];
    NSArray *names = @[ @"Drama", @"Comedy", @"Action", @"Mystery", @"Romance", @"Sci-Fi" ];
    for (NSString *name in names) {
        [choices addObject:[MRGenreChoice choiceWithType:MRMediaTypeMovie
                                                    name:name
                                                    slug:[name lowercaseString]]];
    }
    return choices;
}

static MRMediaItem *MRGenreSeedItem(void) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = 7001;
    item.slug = @"seed-movie";
    item.type = MRMediaTypeMovie;
    item.title = @"Seed Movie";
    item.year = 2020;
    item.poster = @"poster/path";
    item.genres = @[];
    item.watchStatus = MRWatchStatusCompleted;
    item.userRating = 9;
    item.lastWatchedAt = [NSDate dateWithTimeIntervalSince1970:1793774400.0];
    return item;
}

static NSDictionary *MRGenreRelated(NSInteger simklID, NSString *title) {
    return @{
        @"title": title,
        @"type": @"movie",
        @"year": @2020,
        @"ids": @{
            @"simkl_id": @(simklID),
            @"slug": [title lowercaseString]
        },
        @"poster": @"poster/path",
        @"genres": @[],
        @"ratings": @{ @"simkl": @8.0 },
        @"watched": @1000
    };
}

static NSDictionary *MRGenreFileEntry(NSInteger simklID, NSString *title) {
    return @{
        @"title": title,
        @"year": @2025,
        @"ids": @{
            @"simkl_id": @(simklID),
            @"slug": [title lowercaseString]
        },
        @"poster": @"poster/path",
        @"genres": @[ @"Drama" ],
        @"ratings": @{ @"simkl": @8.0 },
        @"watched": @1000
    };
}

static MRFeedSection *MRGenreSectionWithSource(NSArray *sections, MRFeedSource source) {
    for (MRFeedSection *section in sections) {
        if (section.source == source && section.kind == MRFeedSectionKindRow) {
            return section;
        }
    }
    return nil;
}

static NSArray *MRGenreAllTitles(NSArray *sections) {
    NSMutableArray *titles = [NSMutableArray array];
    for (MRFeedSection *section in sections) {
        for (MRMediaItem *item in section.items) {
            [titles addObject:item.title != nil ? item.title : @""];
        }
    }
    return titles;
}

static NSArray *MRGenreGenerate(MRRecommendationEngine *engine) {
    __block NSArray *result = nil;
    __block BOOL finished = NO;
    [engine generateWithCompletion:^(NSArray *sections, NSError *error) {
        result = sections != nil ? sections : @[];
        finished = YES;
    }];
    BOOL completed = MRRunUntil(^BOOL {
        return finished;
    }, 8.0);
    MRAssertTrue(completed, @"genre feed generation completes");
    return result != nil ? result : @[];
}

static MRRecommendationEngine *MRGenreEngine(MRGenreStubProvider *provider,
                                             MRStorage *storage,
                                             MRLibraryStore *library,
                                             MRPreferencesStore *preferences) {
    return [[MRRecommendationEngine alloc] initWithDataProvider:provider
                                                  libraryStore:library
                                                   preferences:preferences
                                                        storage:storage
                                                 responseCache:[[MRResponseCache alloc] initWithDirectory:nil]
                                                         clock:[[MRFakeClock alloc] init]];
}

#pragma mark - Tests

void MRRunGenrePickerTests(void) {
    // The picker never offers adult genres or the low-signal game-play slug.
    {
        NSArray *genres = [MRGenreChoice allowedGenresFromIndex:MRGenreIndex()
                                                          type:MRMediaTypeAnime];
        MRAssertEqualIntegers(2, (NSInteger)genres.count,
                              @"the picker keeps only allowed genre entries");
        MRGenreChoice *first = [genres objectAtIndex:0];
        MRGenreChoice *second = [genres objectAtIndex:1];
        MRAssertEqualObjects(@"Drama", first.name, @"allowed genres keep index order");
        MRAssertEqualObjects(@"Comedy", second.name, @"allowed genres skip forbidden slugs");
        MRAssertEqualIntegers(MRMediaTypeAnime, first.type,
                              @"allowed genres use the requested type");
        MRAssertTrue(![MRGenreChoice isAllowedGenreSlug:@"erotica"],
                     @"erotica is never offered");
        MRAssertTrue(![MRGenreChoice isAllowedGenreSlug:@"hentai"],
                     @"hentai is never offered");
        MRAssertTrue(![MRGenreChoice isAllowedGenreSlug:@"video-game-play"],
                     @"video-game-play is never offered");
        MRAssertTrue(![MRGenreChoice isAllowedGenreSlug:@"Erotica"],
                     @"forbidden slug matching ignores case");
    }

    // Five selections save and persist per account; the sixth is rejected.
    {
        NSString *root = MRGenreTestRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:11];
        MRPreferencesStore *store = [[MRPreferencesStore alloc] initWithStorage:storage];
        NSArray *choices = MRGenreChoices();
        NSError *saveError = nil;
        BOOL saved = [store setManualGenres:[choices subarrayWithRange:NSMakeRange(0, 5)]
                                      error:&saveError];
        MRAssertTrue(saved, @"the picker saves five selections");
        MRAssertTrue(saveError == nil, @"five selections save without an error");
        MRAssertEqualIntegers(5, (NSInteger)store.manualGenres.count,
                              @"five selections are kept");

        NSError *limitError = nil;
        BOOL rejected = [store setManualGenres:choices error:&limitError];
        MRAssertTrue(!rejected, @"the sixth selection is rejected");
        MRAssertTrue(limitError != nil, @"the sixth selection returns a visible error");
        MRAssertEqualObjects(MRPreferencesStoreErrorDomain, limitError.domain,
                             @"the visible error comes from the preferences store");
        MRAssertEqualIntegers(MRPreferencesStoreErrorManualGenreLimit, limitError.code,
                              @"the visible error is the manual genre limit");
        MRAssertEqualIntegers(5, (NSInteger)store.manualGenres.count,
                              @"a rejected selection leaves the previous five intact");

        MRPreferencesStore *reloaded =
            [[MRPreferencesStore alloc] initWithStorage:storage];
        MRAssertEqualIntegers(5, (NSInteger)reloaded.manualGenres.count,
                              @"selections persist for the same account");
        MRStorage *otherStorage =
            [[MRStorage alloc] initWithRootDirectory:root accountID:22];
        MRPreferencesStore *otherAccount =
            [[MRPreferencesStore alloc] initWithStorage:otherStorage];
        MRAssertEqualIntegers(0, (NSInteger)otherAccount.manualGenres.count,
                              @"another account does not inherit the selections");

        NSError *replaceError = nil;
        BOOL replaced = [reloaded setManualGenres:[choices subarrayWithRange:NSMakeRange(0, 2)]
                                            error:&replaceError];
        MRAssertTrue(replaced, @"the picker can replace the saved selections");
        MRAssertTrue(replaceError == nil, @"replacement has no error");
        MRAssertEqualIntegers(2, (NSInteger)reloaded.manualGenres.count,
                              @"replacement removes deselected genres");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // A saved selection produces a genre row after the next generation.
    {
        NSString *root = MRGenreTestRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:33];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];

        MRGenreStubProvider *provider = [[MRGenreStubProvider alloc] init];
        [provider setGenreFile:@[
            MRGenreFileEntry(8101, @"Drama One"),
            MRGenreFileEntry(8102, @"Drama Two"),
            MRGenreFileEntry(8103, @"Drama Three"),
            MRGenreFileEntry(8104, @"Drama Four")
        ] type:MRMediaTypeMovie slug:@"drama"];

        MRRecommendationEngine *engine = MRGenreEngine(provider, storage, library, preferences);
        NSArray *before = MRGenreGenerate(engine);
        MRAssertTrue(MRGenreSectionWithSource(before, MRFeedSourceGenrePicker) == nil,
                     @"no genre row appears before a selection exists");

        NSError *addError = nil;
        BOOL added = [preferences addManualGenre:
            [MRGenreChoice choiceWithType:MRMediaTypeMovie name:@"Drama" slug:@"drama"]
            error:&addError];
        MRAssertTrue(added, @"the picker selection saves");
        MRAssertTrue(addError == nil, @"the picker selection has no error");
        [engine invalidateCache];

        NSArray *after = MRGenreGenerate(engine);
        MRFeedSection *genre = MRGenreSectionWithSource(after, MRFeedSourceGenrePicker);
        MRAssertTrue(genre != nil, @"the next generation includes the selected genre");
        MRAssertEqualObjects(@"Because You Like Drama", genre.title,
                             @"the genre row names the selected genre");
        MRAssertEqualIntegers(4, (NSInteger)genre.items.count,
                              @"the genre row carries the selected genre file");
        for (MRMediaItem *item in genre.items) {
            MRAssertTrue([item.title hasPrefix:@"Drama"],
                         @"the genre row only contains the selected genre's file");
        }
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    // Hiding removes a candidate; unhiding restores it on the next generation.
    {
        NSString *root = MRGenreTestRoot();
        MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:44];
        MRLibraryStore *library = [[MRLibraryStore alloc] initWithStorage:storage];
        [library load:NULL];
        MRMediaItem *seed = MRGenreSeedItem();
        [library replaceWithItems:@[ seed ] activities:@{} profile:nil error:NULL];
        MRPreferencesStore *preferences =
            [[MRPreferencesStore alloc] initWithStorage:storage];

        MRGenreStubProvider *provider = [[MRGenreStubProvider alloc] init];
        provider.seedDetail = @{
            @"users_recommendations": @[
                MRGenreRelated(9101, @"Hidden Candidate"),
                MRGenreRelated(9102, @"Visible One"),
                MRGenreRelated(9103, @"Visible Two"),
                MRGenreRelated(9104, @"Visible Three"),
                MRGenreRelated(9105, @"Visible Four")
            ]
        };
        MRMediaItem *hiddenItem = [[MRMediaItem alloc] init];
        hiddenItem.simklID = 9101;
        hiddenItem.type = MRMediaTypeMovie;
        hiddenItem.title = @"Hidden Candidate";
        NSError *hideError = nil;
        BOOL hidden = [preferences hideTitle:hiddenItem error:&hideError];
        MRAssertTrue(hidden, @"the picker hides a title");
        MRAssertTrue(hideError == nil, @"hiding a title has no error");

        MRRecommendationEngine *first = MRGenreEngine(provider, storage, library, preferences);
        NSArray *hiddenSections = MRGenreGenerate(first);
        MRAssertTrue(![MRGenreAllTitles(hiddenSections) containsObject:@"Hidden Candidate"],
                     @"a hidden title is absent from the feed");
        MRAssertTrue([MRGenreAllTitles(hiddenSections) containsObject:@"Visible One"],
                     @"visible candidates remain in the feed");

        NSError *unhideError = nil;
        BOOL unhidden = [preferences unhideTitleForType:MRMediaTypeMovie
                                               simklID:9101
                                                 error:&unhideError];
        MRAssertTrue(unhidden, @"the profile can unhide a title");
        MRAssertTrue(unhideError == nil, @"unhiding a title has no error");

        MRRecommendationEngine *second = MRGenreEngine(provider, storage, library, preferences);
        NSArray *restoredSections = MRGenreGenerate(second);
        MRAssertTrue([MRGenreAllTitles(restoredSections) containsObject:@"Hidden Candidate"],
                     @"the next generation restores the unhidden title");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}
