//
//  MRWriteResult.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MROutboxEntry;

// The outcome of one write batch. succeededEntries and permanentlyFailedEntries
// are disjoint. resolvedStatuses maps an entry ID to the MRWatchStatus Simkl
// actually applied, which may differ from the requested status.
@interface MRWriteResult : NSObject

@property (nonatomic, copy) NSArray *succeededEntries;
@property (nonatomic, copy) NSArray *permanentlyFailedEntries;
@property (nonatomic, copy) NSDictionary *resolvedStatuses;
@property (nonatomic, strong) NSError *error;

@end
