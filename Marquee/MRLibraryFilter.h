//
//  MRLibraryFilter.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRMediaType.h"
#import "MRWatchStatus.h"

// MRMediaType has no All case. Pass this value as the type to include every
// media type; pass MRWatchStatusNone as the status to include every status.
extern const MRMediaType MRLibraryFilterAllTypes;

// The pure filtering and ordering rules behind the Library tab. The controller
// supplies the snapshot; this class never reads a store or the network.
@interface MRLibraryFilter : NSObject

// Preserves the store's order. A movie can never match Watching or Hold
// because its stored status is one of Plan, Completed, or Dropped.
+ (NSArray *)items:(NSArray *)items type:(MRMediaType)type status:(MRWatchStatus)status;

// Last watched descending, then added date descending, then title. Items with
// no date sort after items that have one.
+ (NSArray *)sortedItems:(NSArray *)items;

@end
