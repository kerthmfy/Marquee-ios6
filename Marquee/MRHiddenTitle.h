//
//  MRHiddenTitle.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"

@class MRMediaItem;

// A local "not interested" entry. It carries enough metadata to render in the
// Profile hidden-titles list without a network call.
@interface MRHiddenTitle : NSObject

@property (nonatomic, assign) MRMediaType type;
@property (nonatomic, assign) NSInteger simklID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger year;
@property (nonatomic, copy) NSString *poster;

+ (instancetype)hiddenTitleWithItem:(MRMediaItem *)item;

- (BOOL)matchesType:(MRMediaType)type simklID:(NSInteger)simklID;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)hiddenTitleWithDictionaryRepresentation:(NSDictionary *)dictionary;

@end
