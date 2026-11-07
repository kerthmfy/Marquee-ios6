//
//  MRUserProfile.m
//  Marquee
//

#import "MRUserProfile.h"
#import "MRDate.h"
#import "MRURLBuilder.h"

static NSDictionary *MRProfileDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : @{};
}

static NSString *MRProfileString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return @"";
}

static NSString *MRProfileNullableString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return nil;
}

static NSInteger MRProfileInteger(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value integerValue];
    }
    return 0;
}

static NSDate *MRProfileDate(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [MRDate dateFromISOString:(NSString *)value];
}

@implementation MRUserProfile

- (id)init {
    self = [super init];
    if (self) {
        _name = @"";
        _accountType = @"";
        _timezone = @"";
        _location = @"";
        _bio = @"";
    }
    return self;
}

+ (instancetype)profileWithSettingsDictionary:(NSDictionary *)dictionary {
    MRUserProfile *profile = [[self alloc] init];
    NSDictionary *settings = MRProfileDictionary(dictionary);
    NSDictionary *user = MRProfileDictionary([settings objectForKey:@"user"]);
    NSDictionary *account = MRProfileDictionary([settings objectForKey:@"account"]);

    profile.accountID = MRProfileInteger([account objectForKey:@"id"]);
    profile.name = MRProfileString([user objectForKey:@"name"]);
    profile.avatarURL = [MRURLBuilder avatarURLForPath:MRProfileNullableString([user objectForKey:@"avatar"])];
    profile.joinedAt = MRProfileDate([user objectForKey:@"joined_at"]);
    profile.location = MRProfileString([user objectForKey:@"loc"]);
    profile.bio = MRProfileString([user objectForKey:@"bio"]);
    profile.accountType = MRProfileString([account objectForKey:@"type"]);
    profile.timezone = MRProfileString([account objectForKey:@"timezone"]);
    return profile;
}

+ (instancetype)profileWithDictionaryRepresentation:(NSDictionary *)dictionary {
    MRUserProfile *profile = [[self alloc] init];
    NSDictionary *entry = MRProfileDictionary(dictionary);

    profile.accountID = MRProfileInteger([entry objectForKey:@"accountID"]);
    profile.name = MRProfileString([entry objectForKey:@"name"]);
    profile.avatarURL = MRProfileNullableString([entry objectForKey:@"avatarURL"]);
    profile.joinedAt = MRProfileDate([entry objectForKey:@"joinedAt"]);
    profile.location = MRProfileString([entry objectForKey:@"location"]);
    profile.bio = MRProfileString([entry objectForKey:@"bio"]);
    profile.accountType = MRProfileString([entry objectForKey:@"accountType"]);
    profile.timezone = MRProfileString([entry objectForKey:@"timezone"]);
    return profile;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setObject:@(self.accountID) forKey:@"accountID"];
    [dictionary setObject:self.name ?: @"" forKey:@"name"];
    [dictionary setObject:self.location ?: @"" forKey:@"location"];
    [dictionary setObject:self.bio ?: @"" forKey:@"bio"];
    [dictionary setObject:self.accountType ?: @"" forKey:@"accountType"];
    [dictionary setObject:self.timezone ?: @"" forKey:@"timezone"];
    if (self.avatarURL.length > 0) {
        [dictionary setObject:self.avatarURL forKey:@"avatarURL"];
    }
    if (self.joinedAt != nil) {
        [dictionary setObject:[MRDate isoStringFromDate:self.joinedAt] forKey:@"joinedAt"];
    }
    return dictionary;
}

@end
