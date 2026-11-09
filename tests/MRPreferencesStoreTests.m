//
//  MRPreferencesStoreTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRGenreChoice.h"
#import "MRHiddenTitle.h"
#import "MRMediaItem.h"
#import "MRPreferencesStore.h"
#import "MRStorage.h"

static NSString *MRPreferencesTestRoot(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"marquee-preferences-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
}

static MRGenreChoice *MRChoice(NSString *name, NSString *slug) {
    return [MRGenreChoice choiceWithType:MRMediaTypeMovie name:name slug:slug];
}

static MRMediaItem *MRPreferenceItem(NSInteger simklID, MRMediaType type, NSString *title) {
    MRMediaItem *item = [[MRMediaItem alloc] init];
    item.simklID = simklID;
    item.type = type;
    item.title = title;
    item.year = 2020;
    item.poster = @"poster/path";
    return item;
}

void MRRunPreferencesStoreTests(void) {
    NSString *root = MRPreferencesTestRoot();
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:42];
    MRPreferencesStore *store = [[MRPreferencesStore alloc] initWithStorage:storage];

    // Manual genres: five allowed, the sixth returns an error.
    for (NSInteger index = 0; index < 5; index++) {
        NSError *error = nil;
        NSString *name = [NSString stringWithFormat:@"Genre %ld", (long)index];
        BOOL added = [store addManualGenre:MRChoice(name, [name lowercaseString])
                                     error:&error];
        MRAssertTrue(added, @"first five manual genres are accepted");
        MRAssertTrue(error == nil, @"accepted manual genre has no error");
    }
    NSError *limitError = nil;
    BOOL sixth = [store addManualGenre:MRChoice(@"Sixth", @"sixth") error:&limitError];
    MRAssertTrue(!sixth, @"the sixth manual genre is rejected");
    MRAssertTrue(limitError != nil, @"the sixth manual genre returns an error");
    MRAssertEqualIntegers(5, (NSInteger)store.manualGenres.count,
                          @"manual genres stop at five");

    // Hidden titles: cap at 200.
    for (NSInteger index = 0; index < 200; index++) {
        MRMediaItem *item = MRPreferenceItem(1000 + index, MRMediaTypeMovie,
                                             [NSString stringWithFormat:@"Hidden %ld", (long)index]);
        NSError *error = nil;
        BOOL hidden = [store hideTitle:item error:&error];
        MRAssertTrue(hidden, @"hidden titles accept entries up to 200");
        MRAssertTrue(error == nil, @"accepted hidden title has no error");
    }
    NSError *hiddenError = nil;
    BOOL overflow = [store hideTitle:MRPreferenceItem(9999, MRMediaTypeShow, @"Overflow")
                               error:&hiddenError];
    MRAssertTrue(!overflow, @"the 201st hidden title is rejected");
    MRAssertTrue(hiddenError != nil, @"the 201st hidden title returns an error");
    MRAssertEqualIntegers(200, (NSInteger)store.hiddenTitles.count,
                          @"hidden titles stop at 200");
    MRAssertTrue([store isHiddenType:MRMediaTypeMovie simklID:1000],
                 @"a hidden title is found by type and ID");
    MRAssertTrue(![store isHiddenType:MRMediaTypeShow simklID:1000],
                 @"type participates in the hidden lookup");

    // Search history: case-insensitive dedupe, newest first, cap eight.
    [store recordSearch:@"Interstellar" error:NULL];
    [store recordSearch:@"interstellar" error:NULL];
    [store recordSearch:@"  Dune  " error:NULL];
    MRAssertEqualIntegers(2, (NSInteger)store.searchHistory.count,
                          @"search history deduplicates case-insensitively");
    MRAssertEqualObjects(@"Dune", [store.searchHistory objectAtIndex:0],
                         @"the newest search is first");
    for (NSInteger index = 0; index < 10; index++) {
        [store recordSearch:[NSString stringWithFormat:@"Query %ld", (long)index] error:NULL];
    }
    MRAssertEqualIntegers(8, (NSInteger)store.searchHistory.count,
                          @"search history stops at eight");
    MRAssertEqualObjects(@"Query 9", [store.searchHistory objectAtIndex:0],
                         @"newest search survives the cap");

    // Persistence round-trip.
    NSError *saveError = nil;
    BOOL saved = [store save:&saveError];
    MRAssertTrue(saved, @"preferences save");
    MRAssertTrue(saveError == nil, @"preferences save has no error");

    MRPreferencesStore *reloaded =
        [[MRPreferencesStore alloc] initWithStorage:storage];
    NSError *loadError = nil;
    [reloaded load:&loadError];
    MRAssertTrue(loadError == nil, @"preferences load has no error after a save");
    MRAssertEqualIntegers(5, (NSInteger)reloaded.manualGenres.count,
                          @"manual genres persist");
    MRAssertEqualIntegers(200, (NSInteger)reloaded.hiddenTitles.count,
                          @"hidden titles persist");
    MRAssertEqualObjects(@"Query 9", [reloaded.searchHistory objectAtIndex:0],
                         @"search history persists");
    MRAssertTrue([reloaded isHiddenType:MRMediaTypeMovie simklID:1000],
                 @"hidden lookup survives a round-trip");

    // Unhide removes the entry.
    NSError *unhideError = nil;
    BOOL unhidden = [reloaded unhideTitleForType:MRMediaTypeMovie
                                        simklID:1000
                                          error:&unhideError];
    MRAssertTrue(unhidden, @"unhide succeeds");
    MRAssertTrue(![reloaded isHiddenType:MRMediaTypeMovie simklID:1000],
                 @"unhide removes the hidden entry");

    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}
