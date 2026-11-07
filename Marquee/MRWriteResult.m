//
//  MRWriteResult.m
//  Marquee
//

#import "MRWriteResult.h"

@implementation MRWriteResult

- (id)init {
    self = [super init];
    if (self) {
        _succeededEntries = @[];
        _permanentlyFailedEntries = @[];
        _resolvedStatuses = @{};
    }
    return self;
}

@end
