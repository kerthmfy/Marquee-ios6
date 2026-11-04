//
//  MRHTTPRequest.h
//  Marquee
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MRHTTPQueueKind) {
    MRHTTPQueueKindAPI = 0,
    MRHTTPQueueKindCatalog
};

// A transport-level request. Parsing and error mapping happen above this type.
@interface MRHTTPRequest : NSObject <NSCopying>

@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) MRHTTPQueueKind queueKind;

- (instancetype)initWithURL:(NSString *)URL method:(NSString *)method;

@end
