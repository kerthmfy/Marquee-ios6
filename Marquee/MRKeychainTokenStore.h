//
//  MRKeychainTokenStore.h
//  Marquee
//

#import <Foundation/Foundation.h>
#import "MRTokenStore.h"

// Stores the Simkl token session as five generic-password items under
// com.marquee.app.simkl.
@interface MRKeychainTokenStore : NSObject <MRTokenStore>
@end
