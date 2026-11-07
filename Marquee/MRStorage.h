//
//  MRStorage.h
//  Marquee
//

#import <Foundation/Foundation.h>

extern NSString *const MRStorageErrorDomain;

// File-backed JSON storage for one account directory. The directory is created
// lazily on the first write. Reads of a missing file return nil and leave the
// error untouched; corrupt or unreadable files return nil and set an error.
@interface MRStorage : NSObject

@property (nonatomic, readonly) NSInteger accountID;
@property (nonatomic, readonly) NSString *accountDirectory;

// rootDirectory is the Marquee parent directory. The account directory is
// rootDirectory/Accounts/<accountID>.
- (instancetype)initWithRootDirectory:(NSString *)rootDirectory
                            accountID:(NSInteger)accountID;

// Application Support/Marquee/Accounts/<accountID>.
- (instancetype)initWithAccountID:(NSInteger)accountID;

- (id)readJSONNamed:(NSString *)name error:(NSError **)error;
- (BOOL)writeJSON:(id)json named:(NSString *)name error:(NSError **)error;
- (BOOL)removeFileNamed:(NSString *)name error:(NSError **)error;

// Marks a directory as excluded from iCloud/iTunes backup. Used for the
// disposable Caches/Marquee tree. Missing directories are created first.
+ (BOOL)excludeFromBackupAtPath:(NSString *)path;

@end
