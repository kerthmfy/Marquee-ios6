//
//  MRStorageTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRStorage.h"
#import "MRUserProfile.h"

static NSString *MRStorageTestDirectory(NSString *suffix) {
    NSString *name = [NSString stringWithFormat:@"marquee-storage-%@-%@",
                      suffix, [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

static void MRRemoveTestDirectory(NSString *directory) {
    if (directory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    }
}

static void MRRunStorageRoundTrip(void) {
    NSString *root = MRStorageTestDirectory(@"round-trip");
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:12345];

    MRAssertEqualIntegers(12345, storage.accountID, @"storage keeps the account id");
    MRAssertEqualObjects([root stringByAppendingPathComponent:@"Accounts/12345"],
                         storage.accountDirectory,
                         @"storage uses Accounts/<accountID> under the injected root");

    NSArray *names = @[ @"state.json", @"library.json",
                        @"preferences.json", @"outbox.json" ];
    for (NSString *name in names) {
        NSDictionary *body = @{ @"schema": @1, @"name": name,
                                @"values": @[ @"a", @"b" ] };
        NSError *writeError = nil;
        BOOL wrote = [storage writeJSON:body named:name error:&writeError];
        MRAssertTrue(wrote, [NSString stringWithFormat:@"write %@", name]);
        MRAssertTrue(writeError == nil,
                     [NSString stringWithFormat:@"write %@ has no error", name]);

        NSError *readError = nil;
        id read = [storage readJSONNamed:name error:&readError];
        MRAssertTrue(readError == nil,
                     [NSString stringWithFormat:@"read %@ has no error", name]);
        MRAssertEqualObjects(body, read,
                             [NSString stringWithFormat:@"round-trip %@", name]);

        NSString *path = [storage.accountDirectory stringByAppendingPathComponent:name];
        MRAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path],
                     [NSString stringWithFormat:@"%@ exists on disk", name]);
    }

    NSError *removeError = nil;
    MRAssertTrue([storage removeFileNamed:@"outbox.json" error:&removeError],
                 @"remove outbox");
    MRAssertTrue(removeError == nil, @"remove outbox has no error");
    NSError *missingError = nil;
    MRAssertTrue([storage readJSONNamed:@"outbox.json" error:&missingError] == nil,
                 @"removed file reads as nil");
    MRAssertTrue(missingError == nil, @"missing file reports no error");

    MRRemoveTestDirectory(root);
}

static void MRRunStorageCorruptFile(void) {
    NSString *root = MRStorageTestDirectory(@"corrupt");
    MRStorage *storage = [[MRStorage alloc] initWithRootDirectory:root accountID:7];

    NSDictionary *body = @{ @"schema": @1 };
    NSError *writeError = nil;
    MRAssertTrue([storage writeJSON:body named:@"state.json" error:&writeError],
                 @"corrupt test writes a valid state file");

    NSString *path = [storage.accountDirectory stringByAppendingPathComponent:@"state.json"];
    NSData *garbage = [@"this is not json" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToFile:path atomically:YES];

    NSError *error = nil;
    id value = [storage readJSONNamed:@"state.json" error:&error];
    MRAssertTrue(value == nil, @"corrupt JSON reads as nil");
    MRAssertTrue(error != nil, @"corrupt JSON reports an error");

    MRRemoveTestDirectory(root);
}

static void MRRunStorageBackupExclusion(void) {
    NSString *root = MRStorageTestDirectory(@"backup");
    NSString *cacheDirectory = [root stringByAppendingPathComponent:@"Caches/Marquee"];

    MRAssertTrue([MRStorage excludeFromBackupAtPath:cacheDirectory],
                 @"the cache directory is excluded from backup");

    NSURL *URL = [NSURL fileURLWithPath:cacheDirectory];
    id value = nil;
    NSError *error = nil;
    MRAssertTrue([URL getResourceValue:&value
                                forKey:NSURLIsExcludedFromBackupKey
                                 error:&error],
                 @"the backup exclusion is readable");
    MRAssertTrue([value boolValue], @"the cache directory is marked excluded");

    MRRemoveTestDirectory(root);
}

static void MRRunUserProfileNormalization(void) {
    NSDictionary *settings = @{
        @"user": @{
            @"name": @"kerth",
            @"joined_at": @"2018-01-15T00:00:00Z",
            @"avatar": @"avatars/12345/user_100.jpg",
            @"bio": @"Watches too much television.",
            @"loc": @"Madrid",
            @"age": @28
        },
        @"account": @{
            @"id": @12345,
            @"timezone": @"Europe/Madrid",
            @"type": @"pro"
        }
    };

    MRUserProfile *profile = [MRUserProfile profileWithSettingsDictionary:settings];
    MRAssertEqualIntegers(12345, profile.accountID, @"profile account id");
    MRAssertEqualObjects(@"kerth", profile.name, @"profile name");
    MRAssertEqualObjects(@"Madrid", profile.location, @"profile location");
    MRAssertEqualObjects(@"Watches too much television.", profile.bio, @"profile bio");
    MRAssertEqualObjects(@"pro", profile.accountType, @"profile account type");
    MRAssertEqualObjects(@"Europe/Madrid", profile.timezone, @"profile timezone");
    MRAssertTrue(profile.joinedAt != nil, @"profile joined date parsed");
    MRAssertEqualObjects(@"https://simkl.in/avatars/12345/user_100.jpg",
                         profile.avatarURL,
                         @"profile avatar is normalized to a URL");

    NSDictionary *representation = [profile dictionaryRepresentation];
    MRUserProfile *copy = [MRUserProfile profileWithDictionaryRepresentation:representation];
    MRAssertEqualIntegers(profile.accountID, copy.accountID, @"profile round-trip id");
    MRAssertEqualObjects(profile.name, copy.name, @"profile round-trip name");
    MRAssertEqualObjects(profile.avatarURL, copy.avatarURL,
                         @"profile round-trip avatar");
    MRAssertEqualObjects(profile.location, copy.location,
                         @"profile round-trip location");
    MRAssertEqualObjects(profile.bio, copy.bio, @"profile round-trip bio");
    MRAssertEqualObjects(profile.accountType, copy.accountType,
                         @"profile round-trip account type");
    MRAssertEqualObjects(profile.timezone, copy.timezone,
                         @"profile round-trip timezone");
    MRAssertEqualObjects(profile.joinedAt, copy.joinedAt,
                         @"profile round-trip joined date");

    MRUserProfile *empty = [MRUserProfile profileWithSettingsDictionary:@{}];
    MRAssertEqualIntegers(0, empty.accountID, @"empty settings has account 0");
    MRAssertEqualObjects(@"", empty.name, @"empty settings has an empty name");
    MRAssertEqualObjects(@"", empty.accountType, @"empty settings has no type");
}

void MRRunStorageTests(void) {
    MRRunStorageRoundTrip();
    MRRunStorageCorruptFile();
    MRRunStorageBackupExclusion();
    MRRunUserProfileNormalization();
}
