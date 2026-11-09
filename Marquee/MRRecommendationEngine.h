//
//  MRRecommendationEngine.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRFeedSection.h"
#import "MRMediaType.h"

@class MRLibraryStore;
@class MRMediaItem;
@class MRPreferencesStore;
@class MRResponseCache;
@class MRStorage;
@class MRTasteProfile;
@protocol MRClock;
@protocol MRRecommendationDataProviding;

// One normalized candidate plus the weight of the source that produced it.
// Proxy genres are inherited from a seed when the source does not carry genres.
@interface MRRecommendationCandidate : NSObject

@property (nonatomic, strong) MRMediaItem *item;
@property (nonatomic, assign) double baseScore;
@property (nonatomic, assign) MRFeedSource source;
@property (nonatomic, copy) NSArray *proxyGenres;

+ (instancetype)candidateWithItem:(MRMediaItem *)item
                        baseScore:(double)baseScore
                           source:(MRFeedSource)source
                      proxyGenres:(NSArray *)proxyGenres;

@end

@interface MRRecommendationEngine : NSObject

- (instancetype)initWithDataProvider:(id<MRRecommendationDataProviding>)provider
                        libraryStore:(MRLibraryStore *)libraryStore
                         preferences:(MRPreferencesStore *)preferences
                              storage:(MRStorage *)storage
                       responseCache:(MRResponseCache *)responseCache
                               clock:(id<MRClock>)clock;

- (void)generateWithCompletion:(void (^)(NSArray *sections, NSError *error))completion;
- (NSArray *)cachedSections;
- (void)invalidateCache;

// Candidate normalization and scoring seams, shared with the row builder.
- (NSArray *)candidatesFromSeedDetail:(NSDictionary *)detail
                                 seed:(MRMediaItem *)seed;
- (NSArray *)candidatesFromItems:(NSArray *)items
                            type:(MRMediaType)type
                          source:(MRFeedSource)source;
- (NSArray *)eligibleCandidates:(NSArray *)candidates;
+ (double)scoreForCandidate:(MRRecommendationCandidate *)candidate
                    profile:(MRTasteProfile *)profile
                currentYear:(NSInteger)currentYear;
+ (NSArray *)sortedCandidates:(NSArray *)candidates
                      profile:(MRTasteProfile *)profile
                  currentYear:(NSInteger)currentYear;

@end
