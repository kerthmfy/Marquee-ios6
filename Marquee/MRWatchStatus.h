//
//  MRWatchStatus.h
//  Marquee
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MRWatchStatus) {
    MRWatchStatusNone = 0,
    MRWatchStatusWatching,
    MRWatchStatusPlanToWatch,
    MRWatchStatusCompleted,
    MRWatchStatusHold,
    MRWatchStatusDropped
};
