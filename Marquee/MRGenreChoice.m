//
//  MRGenreChoice.m
//  Marquee
//

#import "MRGenreChoice.h"

@implementation MRGenreChoice

+ (instancetype)choiceWithType:(MRMediaType)type
                          name:(NSString *)name
                          slug:(NSString *)slug {
    MRGenreChoice *choice = [[self alloc] init];
    choice.type = type;
    choice.name = name != nil ? name : @"";
    choice.slug = slug != nil ? slug : @"";
    return choice;
}

+ (BOOL)isAllowedGenreSlug:(NSString *)slug {
    if (![slug isKindOfClass:[NSString class]] || slug.length == 0) {
        return NO;
    }
    NSString *lowercase = [slug lowercaseString];
    return ![lowercase isEqualToString:@"erotica"] &&
           ![lowercase isEqualToString:@"hentai"] &&
           ![lowercase isEqualToString:@"video-game-play"];
}

+ (NSArray *)allowedGenresFromIndex:(NSArray *)index type:(MRMediaType)type {
    if (![index isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *choices = [NSMutableArray array];
    for (id entry in (NSArray *)index) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [entry objectForKey:@"name"];
        NSString *slug = [entry objectForKey:@"slug"];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            continue;
        }
        if (![self isAllowedGenreSlug:slug]) {
            continue;
        }
        [choices addObject:[self choiceWithType:type name:name slug:slug]];
    }
    return choices;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"type": @(self.type),
        @"name": self.name != nil ? self.name : @"",
        @"slug": self.slug != nil ? self.slug : @""
    };
}

+ (instancetype)choiceWithDictionaryRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *name = [dictionary objectForKey:@"name"];
    NSString *slug = [dictionary objectForKey:@"slug"];
    if (![name isKindOfClass:[NSString class]] || name.length == 0 ||
        ![slug isKindOfClass:[NSString class]] || slug.length == 0) {
        return nil;
    }
    MRMediaType mediaType = MRMediaTypeMovie;
    id typeValue = [dictionary objectForKey:@"type"];
    if ([typeValue isKindOfClass:[NSNumber class]]) {
        NSInteger value = [typeValue integerValue];
        if (value == MRMediaTypeShow || value == MRMediaTypeAnime) {
            mediaType = (MRMediaType)value;
        }
    } else if ([typeValue isKindOfClass:[NSString class]]) {
        if ([typeValue isEqualToString:@"shows"] || [typeValue isEqualToString:@"tv"]) {
            mediaType = MRMediaTypeShow;
        } else if ([typeValue isEqualToString:@"anime"]) {
            mediaType = MRMediaTypeAnime;
        }
    }
    return [self choiceWithType:mediaType name:name slug:slug];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[MRGenreChoice class]]) {
        return NO;
    }
    MRGenreChoice *other = (MRGenreChoice *)object;
    return self.type == other.type &&
           [self.slug caseInsensitiveCompare:other.slug] == NSOrderedSame;
}

- (NSUInteger)hash {
    return (NSUInteger)self.type ^ (NSUInteger)self.slug.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MRGenreChoice %ld %@/%@>",
            (long)self.type, self.name, self.slug];
}

@end
