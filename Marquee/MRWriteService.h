//
//  MRWriteService.h
//  Marquee
//

#import <Foundation/Foundation.h>

@class MRAPIClient;
@class MRLibraryStore;
@class MROutbox;
@class MROutboxEntry;
@class MRWriteResult;
@protocol MRClock;

@protocol MRWriteSending <NSObject>
- (void)sendEntries:(NSArray<MROutboxEntry *> *)entries
         completion:(void (^)(MRWriteResult *result))completion;
@end

// Sends batches from the persistent outbox. The service owns write ordering
// (1.1 seconds between POSTs), retry policy, outbox removal, and local library
// reconciliation. Callers enqueue and save an entry first, update the UI
// optimistically, then hand the pending entries to this service.
@interface MRWriteService : NSObject <MRWriteSending>

- (instancetype)initWithAPIClient:(MRAPIClient *)apiClient
                           outbox:(MROutbox *)outbox
                     libraryStore:(MRLibraryStore *)libraryStore
                            clock:(id<MRClock>)clock;

@end
