//
//  MRStorage.m
//  Marquee
//

#import "MRStorage.h"
#import "MRJSON.h"

NSString *const MRStorageErrorDomain = @"MRStorageErrorDomain";

typedef NS_ENUM(NSInteger, MRStorageErrorCode) {
    MRStorageErrorUnreadable = 1,
    MRStorageErrorUnwritable = 2,
    MRStorageErrorNotRemovable = 3
};

static NSError *MRStorageError(MRStorageErrorCode code, NSString *description,
                               NSError *underlying) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description.length > 0) {
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
    }
    if (underlying != nil) {
        [userInfo setObject:underlying forKey:NSUnderlyingErrorKey];
    }
    return [NSError errorWithDomain:MRStorageErrorDomain code:code userInfo:userInfo];
}

static NSString *MRDefaultApplicationSupportDirectory(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask,
                                                         YES);
    NSString *support = paths.count > 0
        ? [paths objectAtIndex:0]
        : NSTemporaryDirectory();
    return [support stringByAppendingPathComponent:@"Marquee"];
}

@interface MRStorage ()
@property (nonatomic, assign) NSInteger accountID;
@property (nonatomic, copy) NSString *accountDirectory;
@end

@implementation MRStorage

- (instancetype)initWithRootDirectory:(NSString *)rootDirectory
                            accountID:(NSInteger)accountID {
    self = [super init];
    if (self) {
        _accountID = accountID;
        NSString *root = rootDirectory.length > 0 ? rootDirectory : MRDefaultApplicationSupportDirectory();
        _accountDirectory = [[root stringByAppendingPathComponent:@"Accounts"]
            stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld", (long)accountID]];
    }
    return self;
}

- (instancetype)initWithAccountID:(NSInteger)accountID {
    return [self initWithRootDirectory:MRDefaultApplicationSupportDirectory()
                             accountID:accountID];
}

- (BOOL)ensureAccountDirectory:(NSError **)error {
    if (self.accountDirectory.length == 0) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnwritable,
                                    @"No account storage directory is configured.", nil);
        }
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([manager fileExistsAtPath:self.accountDirectory isDirectory:&isDirectory]) {
        if (isDirectory) {
            return YES;
        }
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnwritable,
                                    @"The account storage path is not a directory.", nil);
        }
        return NO;
    }

    BOOL created = [manager createDirectoryAtPath:self.accountDirectory
                       withIntermediateDirectories:YES
                                        attributes:nil
                                             error:error];
    if (!created && error != NULL && *error == nil) {
        *error = MRStorageError(MRStorageErrorUnwritable,
                                @"Could not create the account storage directory.", nil);
    }
    return created;
}

- (NSString *)pathForName:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    return [self.accountDirectory stringByAppendingPathComponent:name];
}

- (id)readJSONNamed:(NSString *)name error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    NSString *path = [self pathForName:name];
    if (path == nil) {
        return nil;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return nil;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:0
                                            error:&readError];
    if (data == nil) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnreadable,
                                    [NSString stringWithFormat:@"Could not read %@.", name],
                                    readError);
        }
        return nil;
    }

    NSError *parseError = nil;
    id object = [MRJSON objectFromData:data error:&parseError];
    if (object == nil) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnreadable,
                                    [NSString stringWithFormat:@"%@ is not valid JSON.", name],
                                    parseError);
        }
        return nil;
    }
    return object;
}

- (BOOL)writeJSON:(id)json named:(NSString *)name error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    if (![self ensureAccountDirectory:error]) {
        return NO;
    }
    NSString *path = [self pathForName:name];
    if (path == nil) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnwritable,
                                    @"No file name was provided.", nil);
        }
        return NO;
    }

    NSError *serializeError = nil;
    NSData *data = [MRJSON dataFromObject:json error:&serializeError];
    if (data == nil) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnwritable,
                                    [NSString stringWithFormat:@"Could not encode %@.", name],
                                    serializeError);
        }
        return NO;
    }

    NSError *writeError = nil;
    BOOL wrote = [data writeToFile:path
                          options:NSDataWritingAtomic
                            error:&writeError];
    if (!wrote) {
        if (error != NULL) {
            *error = MRStorageError(MRStorageErrorUnwritable,
                                    [NSString stringWithFormat:@"Could not write %@.", name],
                                    writeError);
        }
        return NO;
    }
    return YES;
}

- (BOOL)removeFileNamed:(NSString *)name error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    NSString *path = [self pathForName:name];
    if (path == nil) {
        return YES;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path]) {
        return YES;
    }

    NSError *removeError = nil;
    BOOL removed = [manager removeItemAtPath:path error:&removeError];
    if (!removed && error != NULL) {
        *error = MRStorageError(MRStorageErrorNotRemovable,
                                [NSString stringWithFormat:@"Could not remove %@.", name],
                                removeError);
    }
    return removed;
}

+ (BOOL)excludeFromBackupAtPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:path isDirectory:&isDirectory]) {
        if (![manager createDirectoryAtPath:path
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:NULL]) {
            return NO;
        }
    } else if (!isDirectory) {
        return NO;
    }

    NSURL *URL = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    BOOL excluded = [URL setResourceValue:@YES
                                  forKey:NSURLIsExcludedFromBackupKey
                                   error:&error];
    return excluded && error == nil;
}

@end
