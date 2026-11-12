//
//  MROutbox.m
//  Marquee
//

#import "MROutbox.h"

#import "MRError.h"
#import "MROutboxEntry.h"
#import "MRStorage.h"

static const NSInteger MROutboxSchema = 1;
static const NSUInteger MROutboxMaximumBatch = 20;

@interface MROutbox ()
@property (nonatomic, strong) MRStorage *storage;
@property (nonatomic, strong) NSMutableArray *mutableEntries;
@end

@implementation MROutbox

- (instancetype)initWithStorage:(MRStorage *)storage {
    self = [super init];
    if (self) {
        _storage = storage;
        _mutableEntries = [NSMutableArray array];
    }
    return self;
}

- (id)init {
    return [self initWithStorage:nil];
}

- (NSArray *)entries {
    @synchronized(self) {
        return [self.mutableEntries copy];
    }
}

- (NSUInteger)pendingCount {
    return self.entries.count;
}

- (NSError *)storageUnavailableError {
    return [NSError errorWithDomain:@"MROutboxErrorDomain"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey:
                                           @"The write queue is unavailable." }];
}

- (BOOL)load:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (self.storage == nil) {
        if (error != NULL) {
            *error = [self storageUnavailableError];
        }
        return NO;
    }

    NSError *readError = nil;
    id object = [self.storage readJSONNamed:@"outbox.json" error:&readError];
    if (object == nil) {
        if (readError != nil) {
            if (error != NULL) {
                *error = readError;
            }
            return NO;
        }
        @synchronized(self) {
            [self.mutableEntries removeAllObjects];
        }
        return YES;
    }

    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MROutboxErrorDomain"
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"The write queue is corrupt." }];
        }
        return NO;
    }

    NSDictionary *dictionary = (NSDictionary *)object;
    NSInteger schema = [[dictionary objectForKey:@"schema"] integerValue];
    NSInteger accountID = [[dictionary objectForKey:@"accountID"] integerValue];
    if (schema != MROutboxSchema ||
        (accountID != 0 && accountID != self.storage.accountID)) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MROutboxErrorDomain"
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"The write queue belongs to another account." }];
        }
        return NO;
    }

    NSArray *savedEntries = [dictionary objectForKey:@"entries"];
    if (![savedEntries isKindOfClass:[NSArray class]]) {
        savedEntries = @[];
    }

    NSMutableArray *loaded = [NSMutableArray array];
    for (id entryObject in savedEntries) {
        MROutboxEntry *entry =
            [[MROutboxEntry alloc] initWithDictionaryRepresentation:entryObject];
        if (entry != nil && [self entryIsValid:entry]) {
            [loaded addObject:entry];
        }
    }

    @synchronized(self) {
        [self.mutableEntries setArray:loaded];
    }
    return YES;
}

- (BOOL)save:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (self.storage == nil) {
        if (error != NULL) {
            *error = [self storageUnavailableError];
        }
        return NO;
    }

    NSMutableArray *savedEntries = [NSMutableArray array];
    for (MROutboxEntry *entry in self.entries) {
        [savedEntries addObject:[entry dictionaryRepresentation]];
    }

    NSDictionary *document = @{
        @"schema": @(MROutboxSchema),
        @"accountID": @(self.storage.accountID),
        @"entries": savedEntries
    };
    return [self.storage writeJSON:document named:@"outbox.json" error:error];
}

- (BOOL)entryIsValid:(MROutboxEntry *)entry {
    if (entry == nil || entry.simklID <= 0) {
        return NO;
    }
    switch (entry.kind) {
        case MROutboxEntryKindStatus:
            return entry.status != MRWatchStatusNone;
        case MROutboxEntryKindHistoryWhole:
        case MROutboxEntryKindRemove:
            return YES;
        case MROutboxEntryKindHistoryEpisode:
            return entry.season > 0 && entry.episode > 0;
        case MROutboxEntryKindRating:
            return entry.rating >= 1 && entry.rating <= 10;
        case MROutboxEntryKindRatingRemove:
            return YES;
        default:
            return NO;
    }
}

- (NSError *)invalidEntryError {
    return [NSError errorWithDomain:@"MROutboxErrorDomain"
                               code:4
                           userInfo:@{ NSLocalizedDescriptionKey:
                                           @"That change can't be queued." }];
}

- (BOOL)enqueueEntry:(MROutboxEntry *)entry error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (![self entryIsValid:entry]) {
        if (error != NULL) {
            *error = [self invalidEntryError];
        }
        return NO;
    }

    NSArray *previous = self.entries;
    @synchronized(self) {
        NSMutableArray *entries = self.mutableEntries;
        NSUInteger existingIndex = NSNotFound;

        if (entry.kind == MROutboxEntryKindStatus) {
            for (NSUInteger index = 0; index < entries.count; index += 1) {
                MROutboxEntry *candidate = entries[index];
                if (candidate.kind == MROutboxEntryKindStatus &&
                    [candidate targetsSameItemAsEntry:entry]) {
                    existingIndex = index;
                    break;
                }
            }
            if (existingIndex != NSNotFound) {
                [entries replaceObjectAtIndex:existingIndex withObject:entry];
                NSUInteger index = existingIndex + 1;
                while (index < entries.count) {
                    MROutboxEntry *candidate = entries[index];
                    if (candidate.kind == MROutboxEntryKindStatus &&
                        [candidate targetsSameItemAsEntry:entry]) {
                        [entries removeObjectAtIndex:index];
                    } else {
                        index += 1;
                    }
                }
            } else {
                [entries addObject:entry];
            }
        } else if (entry.kind == MROutboxEntryKindRating) {
            [self removeEntriesOfKind:MROutboxEntryKindRatingRemove
                          matchingItem:entry
                            fromEntries:entries];
            for (NSUInteger index = 0; index < entries.count; index += 1) {
                MROutboxEntry *candidate = entries[index];
                if (candidate.kind == MROutboxEntryKindRating &&
                    [candidate targetsSameItemAsEntry:entry]) {
                    existingIndex = index;
                    break;
                }
            }
            if (existingIndex != NSNotFound) {
                [entries replaceObjectAtIndex:existingIndex withObject:entry];
                NSUInteger index = existingIndex + 1;
                while (index < entries.count) {
                    MROutboxEntry *candidate = entries[index];
                    if (candidate.kind == MROutboxEntryKindRating &&
                        [candidate targetsSameItemAsEntry:entry]) {
                        [entries removeObjectAtIndex:index];
                    } else {
                        index += 1;
                    }
                }
            } else {
                [entries addObject:entry];
            }
        } else if (entry.kind == MROutboxEntryKindRatingRemove) {
            [self removeEntriesOfKind:MROutboxEntryKindRating
                          matchingItem:entry
                            fromEntries:entries];
            for (NSUInteger index = 0; index < entries.count; index += 1) {
                MROutboxEntry *candidate = entries[index];
                if (candidate.kind == MROutboxEntryKindRatingRemove &&
                    [candidate targetsSameItemAsEntry:entry]) {
                    existingIndex = index;
                    break;
                }
            }
            if (existingIndex != NSNotFound) {
                [entries replaceObjectAtIndex:existingIndex withObject:entry];
                NSUInteger index = existingIndex + 1;
                while (index < entries.count) {
                    MROutboxEntry *candidate = entries[index];
                    if (candidate.kind == MROutboxEntryKindRatingRemove &&
                        [candidate targetsSameItemAsEntry:entry]) {
                        [entries removeObjectAtIndex:index];
                    } else {
                        index += 1;
                    }
                }
            } else {
                [entries addObject:entry];
            }
        } else if (entry.kind == MROutboxEntryKindHistoryEpisode) {
            BOOL duplicate = NO;
            for (MROutboxEntry *candidate in entries) {
                if (candidate.kind == MROutboxEntryKindHistoryEpisode &&
                    [candidate targetsSameItemAsEntry:entry] &&
                    candidate.season == entry.season &&
                    candidate.episode == entry.episode) {
                    duplicate = YES;
                    break;
                }
            }
            if (!duplicate) {
                [entries addObject:entry];
            }
        } else if (entry.kind == MROutboxEntryKindHistoryWhole) {
            [self removeEntriesOfKind:MROutboxEntryKindStatus
                          matchingItem:entry
                            fromEntries:entries];
            [self removeEntriesOfKind:MROutboxEntryKindHistoryWhole
                          matchingItem:entry
                            fromEntries:entries];
            [entries addObject:entry];
        } else if (entry.kind == MROutboxEntryKindRemove) {
            NSUInteger index = 0;
            while (index < entries.count) {
                MROutboxEntry *candidate = entries[index];
                if ([candidate targetsSameItemAsEntry:entry]) {
                    [entries removeObjectAtIndex:index];
                } else {
                    index += 1;
                }
            }
            [entries addObject:entry];
        }
    }

    NSError *saveError = nil;
    if (![self save:&saveError]) {
        @synchronized(self) {
            [self.mutableEntries setArray:previous];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return NO;
    }
    return YES;
}

- (void)removeEntriesOfKind:(MROutboxEntryKind)kind
               matchingItem:(MROutboxEntry *)entry
                fromEntries:(NSMutableArray *)entries {
    NSUInteger index = 0;
    while (index < entries.count) {
        MROutboxEntry *candidate = entries[index];
        if (candidate.kind == kind && [candidate targetsSameItemAsEntry:entry]) {
            [entries removeObjectAtIndex:index];
        } else {
            index += 1;
        }
    }
}

- (BOOL)removeEntry:(MROutboxEntry *)entry error:(NSError **)error {
    if (entry == nil) {
        if (error != NULL) {
            *error = nil;
        }
        return YES;
    }
    return [self removeEntries:@[ entry ] error:error];
}

- (BOOL)removeEntries:(NSArray *)entries error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (entries.count == 0) {
        return YES;
    }

    NSMutableSet *identifiers = [NSMutableSet set];
    for (MROutboxEntry *entry in entries) {
        if (entry.entryID.length > 0) {
            [identifiers addObject:entry.entryID];
        }
    }
    if (identifiers.count == 0) {
        return YES;
    }

    NSArray *previous = self.entries;
    @synchronized(self) {
        NSUInteger index = 0;
        while (index < self.mutableEntries.count) {
            MROutboxEntry *candidate = self.mutableEntries[index];
            if (candidate.entryID != nil &&
                [identifiers containsObject:candidate.entryID]) {
                [self.mutableEntries removeObjectAtIndex:index];
            } else {
                index += 1;
            }
        }
    }

    NSError *saveError = nil;
    if (![self save:&saveError]) {
        @synchronized(self) {
            [self.mutableEntries setArray:previous];
        }
        if (error != NULL) {
            *error = saveError;
        }
        return NO;
    }
    return YES;
}

- (NSArray *)nextBatchWithLimit:(NSUInteger)limit {
    if (limit == 0) {
        return @[];
    }
    NSUInteger maximum = MIN(limit, MROutboxMaximumBatch);
    NSArray *entries = self.entries;
    if (entries.count == 0) {
        return @[];
    }

    MROutboxEntry *first = [entries objectAtIndex:0];
    NSMutableArray *batch = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (MROutboxEntry *entry in entries) {
        if (batch.count >= maximum) {
            break;
        }
        if (entry.kind != first.kind) {
            break;
        }
        NSString *identifier = [entry itemIdentifier];
        if ([identifiers containsObject:identifier]) {
            break;
        }
        [identifiers addObject:identifier];
        [batch addObject:entry];
    }
    return batch;
}

- (BOOL)containsEntryWithID:(NSString *)entryID {
    if (entryID.length == 0) {
        return NO;
    }
    for (MROutboxEntry *entry in self.entries) {
        if ([entry.entryID isEqualToString:entryID]) {
            return YES;
        }
    }
    return NO;
}

@end
