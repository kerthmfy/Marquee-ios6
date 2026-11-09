//
//  MRFeedSection.m
//  Marquee
//

#import "MRFeedSection.h"
#import "MRMediaItem.h"

@implementation MRFeedSection

- (id)init {
    self = [super init];
    if (self) {
        _title = @"";
        _subtitle = @"";
        _items = @[];
    }
    return self;
}

+ (instancetype)heroSectionWithSource:(MRFeedSource)source
                                title:(NSString *)title
                             subtitle:(NSString *)subtitle {
    MRFeedSection *section = [[self alloc] init];
    section.kind = MRFeedSectionKindHero;
    section.source = source;
    section.title = title != nil ? title : @"";
    section.subtitle = subtitle != nil ? subtitle : @"";
    return section;
}

+ (instancetype)rowSectionWithSource:(MRFeedSource)source
                               title:(NSString *)title
                               items:(NSArray *)items {
    MRFeedSection *section = [[self alloc] init];
    section.kind = MRFeedSectionKindRow;
    section.source = source;
    section.title = title != nil ? title : @"";
    section.items = items != nil ? items : @[];
    return section;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *items = [NSMutableArray array];
    for (MRMediaItem *item in self.items) {
        if ([item isKindOfClass:[MRMediaItem class]]) {
            [items addObject:[item dictionaryRepresentation]];
        }
    }
    return @{
        @"kind": @(self.kind),
        @"source": @(self.source),
        @"title": self.title != nil ? self.title : @"",
        @"subtitle": self.subtitle != nil ? self.subtitle : @"",
        @"items": items
    };
}

+ (instancetype)sectionWithDictionaryRepresentation:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSNumber *kind = [dictionary objectForKey:@"kind"];
    NSNumber *source = [dictionary objectForKey:@"source"];
    NSString *title = [dictionary objectForKey:@"title"];
    NSString *subtitle = [dictionary objectForKey:@"subtitle"];
    if (![kind isKindOfClass:[NSNumber class]] ||
        ![source isKindOfClass:[NSNumber class]]) {
        return nil;
    }

    MRFeedSection *section = [[self alloc] init];
    section.kind = (MRFeedSectionKind)[kind integerValue];
    section.source = (MRFeedSource)[source integerValue];
    section.title = [title isKindOfClass:[NSString class]] ? title : @"";
    section.subtitle = [subtitle isKindOfClass:[NSString class]] ? subtitle : @"";

    NSMutableArray *items = [NSMutableArray array];
    id storedItems = [dictionary objectForKey:@"items"];
    if ([storedItems isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)storedItems) {
            MRMediaItem *item = [MRMediaItem itemWithDictionaryRepresentation:entry];
            if (item != nil && item.simklID > 0) {
                [items addObject:item];
            }
        }
    }
    section.items = items;
    return section;
}

@end
