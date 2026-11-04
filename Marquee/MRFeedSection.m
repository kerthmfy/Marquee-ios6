//
//  MRFeedSection.m
//  Marquee
//

#import "MRFeedSection.h"

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

@end
