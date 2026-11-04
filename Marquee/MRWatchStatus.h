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

// Simkl status keys: "watching", "plantowatch", "completed", "hold", "dropped".
MRWatchStatus MRWatchStatusFromKey(NSString *key);
NSString *MRWatchStatusKey(MRWatchStatus status);
NSString *MRWatchStatusDisplayName(MRWatchStatus status);
