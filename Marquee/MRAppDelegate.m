#import "MRAppDelegate.h"

#import "MRAPIClient.h"
#import "MRAPIRequestOperation.h"
#import "MRAppEnvironment.h"
#import "MRClock.h"
#import "MRDiagnostics.h"
#import "MRImageCache.h"
#import "MRKeychainTokenStore.h"
#import "MRLibraryStore.h"
#import "MROutbox.h"
#import "MRPreferencesStore.h"
#import "MRQuotaTracker.h"
#import "MRRecommendationEngine.h"
#import "MRResponseCache.h"
#import "MRRootTabBarController.h"
#import "MRSimklAuth.h"
#import "MRStorage.h"
#import "MRSyncEngine.h"
#import "MRTokenSession.h"
#import "MRUserProfile.h"
#import "MRWriteResult.h"
#import "MRWriteService.h"

@interface MRAppDelegate ()
@property (nonatomic, strong) id<MRClock> clock;
@property (nonatomic, strong) MRDiagnostics *diagnostics;
@property (nonatomic, strong) MRResponseCache *responseCache;
@property (nonatomic, strong) NSString *quotaDirectory;
@end

@implementation MRAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.environment = [self makeEnvironment];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.rootTabBarController =
        [[MRRootTabBarController alloc] initWithEnvironment:self.environment];
    self.window.rootViewController = self.rootTabBarController;
    [self.window makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authDidChange:)
                                                 name:MRAuthDidChangeNotification
                                               object:self.environment.auth];

    [self bootstrapAccount];
    return YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Composition root

- (MRAppEnvironment *)makeEnvironment
{
    NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                              NSUserDomainMask,
                                                              YES);
    NSString *caches = cachePaths.count > 0
        ? [cachePaths objectAtIndex:0]
        : NSTemporaryDirectory();
    NSString *base = [caches stringByAppendingPathComponent:@"Marquee"];
    [MRStorage excludeFromBackupAtPath:base];

    self.diagnostics = [[MRDiagnostics alloc]
        initWithDirectory:[base stringByAppendingPathComponent:@"Diagnostics"]];
    self.responseCache = [[MRResponseCache alloc]
        initWithDirectory:[base stringByAppendingPathComponent:@"Responses"]];
    self.quotaDirectory = [base stringByAppendingPathComponent:@"Quota"];

    MRSystemClock *clock = [[MRSystemClock alloc] init];
    self.clock = clock;

    MRSimklAuth *auth = [[MRSimklAuth alloc]
        initWithHTTPClient:[MRAPIRequestOperation sharedClient]
                tokenStore:[[MRKeychainTokenStore alloc] init]
               diagnostics:self.diagnostics
                     clock:clock];

    MRQuotaTracker *quota = [[MRQuotaTracker alloc] initWithDirectory:self.quotaDirectory
                                                            accountID:0];
    MRAPIClient *client = [[MRAPIClient alloc]
        initWithHTTPClient:[MRAPIRequestOperation sharedClient]
             tokenProvider:auth
             responseCache:self.responseCache
              quotaTracker:quota
               diagnostics:self.diagnostics
                     clock:clock];

    MRAppEnvironment *environment = [[MRAppEnvironment alloc] init];
    environment.apiClient = client;
    environment.imageCache = [[MRImageCache alloc] init];
    environment.auth = auth;
    environment.diagnostics = self.diagnostics;
    environment.quotaTracker = quota;
    environment.responseCache = self.responseCache;
    return environment;
}

- (MRAPIClient *)authenticatedClientForAccountID:(NSInteger)accountID
{
    MRQuotaTracker *quota = [[MRQuotaTracker alloc] initWithDirectory:self.quotaDirectory
                                                            accountID:accountID];
    self.environment.quotaTracker = quota;
    return [[MRAPIClient alloc] initWithHTTPClient:[MRAPIRequestOperation sharedClient]
                                     tokenProvider:self.environment.auth
                                     responseCache:self.responseCache
                                      quotaTracker:quota
                                       diagnostics:self.diagnostics
                                             clock:self.clock];
}

#pragma mark - Account bootstrap

- (void)bootstrapAccount
{
    __weak MRAppDelegate *weakSelf = self;
    [self.environment.auth restoreWithCompletion:^(MRTokenSession *session, NSError *error) {
        MRAppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf resolveAccountForSession:session refreshProfile:YES];
    }];
}

// Resolves the account without blocking the window. A session whose account ID
// is still unknown fetches /users/settings once; a failed call never creates an
// account directory.
- (void)resolveAccountForSession:(MRTokenSession *)session
                  refreshProfile:(BOOL)refreshProfile
{
    if (session == nil) {
        [self postLibraryChangeForStore:nil];
        return;
    }
    if (session.accountID > 0) {
        [self configureAccountID:session.accountID];
        if (refreshProfile) {
            [self refreshProfile];
        }
        return;
    }

    __weak MRAppDelegate *weakSelf = self;
    [self.environment.apiClient fetchUserSettingsWithCompletion:
     ^(NSDictionary *json, NSError *settingsError) {
        MRAppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        MRUserProfile *profile = [MRUserProfile profileWithSettingsDictionary:json];
        if (settingsError != nil || profile.accountID <= 0) {
            [strongSelf postLibraryChangeForStore:nil];
            return;
        }
        [strongSelf configureAccountID:profile.accountID];
        [strongSelf.environment.libraryStore updateProfile:profile error:NULL];
    }];
}

- (void)configureAccountID:(NSInteger)accountID
{
    if (accountID <= 0) {
        return;
    }
    if (self.environment.accountID == accountID &&
        self.environment.libraryStore != nil) {
        return;
    }

    [self.environment.syncEngine cancel];
    self.environment.accountID = accountID;
    self.environment.apiClient = [self authenticatedClientForAccountID:accountID];

    MRStorage *storage = [[MRStorage alloc] initWithAccountID:accountID];
    self.environment.storage = storage;

    MRLibraryStore *store = [[MRLibraryStore alloc] initWithStorage:storage];
    NSError *loadError = nil;
    BOOL loaded = [store load:&loadError];
    self.environment.libraryStore = store;

    MRPreferencesStore *preferences = [[MRPreferencesStore alloc] initWithStorage:storage];
    [preferences load:NULL];
    self.environment.preferences = preferences;
    self.environment.recommendationEngine =
        [[MRRecommendationEngine alloc] initWithDataProvider:self.environment.apiClient
                                               libraryStore:store
                                                preferences:preferences
                                                     storage:storage
                                              responseCache:self.responseCache
                                                      clock:self.clock];

    MRSyncEngine *engine = [[MRSyncEngine alloc] initWithDataProvider:self.environment.apiClient
                                                         libraryStore:store
                                                              storage:storage
                                                                clock:self.clock];
    self.environment.syncEngine = engine;

    MROutbox *outbox = [[MROutbox alloc] initWithStorage:storage];
    [outbox load:NULL];
    self.environment.outbox = outbox;
    [engine setOutbox:outbox];
    self.environment.writeService =
        [[MRWriteService alloc] initWithAPIClient:self.environment.apiClient
                                          outbox:outbox
                                     libraryStore:store
                                           clock:self.clock];

    if (!loaded && self.environment.auth.isSignedIn) {
        [engine syncWithCompletion:^(NSError *error) {
            // The For You header observes MRSyncStatusDidChangeNotification.
        }];
    }
    [self flushOutbox];
    [self postLibraryChangeForStore:store];
}

// Drains persisted writes in the background. Transient failures leave the
// entries queued; the detail screen and the next launch will try again.
- (void)flushOutbox {
    MROutbox *outbox = self.environment.outbox;
    MRWriteService *service = self.environment.writeService;
    if (outbox.pendingCount == 0 || service == nil) {
        return;
    }

    __weak MRAppDelegate *weakSelf = self;
    [service sendEntries:@[] completion:^(MRWriteResult *result) {
        MRAppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        BOOL progressed =
            result.succeededEntries.count + result.permanentlyFailedEntries.count > 0;
        BOOL stoppedOnTransient = result.error != nil &&
            result.permanentlyFailedEntries.count == 0;
        if (!stoppedOnTransient && progressed &&
            strongSelf.environment.outbox.pendingCount > 0) {
            [strongSelf flushOutbox];
            return;
        }
        if (progressed && strongSelf.environment.outbox.pendingCount == 0) {
            [strongSelf.environment.syncEngine noteOutboxDrainedAtDate:nil];
        }
    }];
}

- (void)refreshProfile
{
    __weak MRAppDelegate *weakSelf = self;
    [self.environment.apiClient fetchUserSettingsWithCompletion:
     ^(NSDictionary *json, NSError *error) {
        MRAppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) {
            return;
        }
        MRUserProfile *profile = [MRUserProfile profileWithSettingsDictionary:json];
        if (profile.accountID > 0 && strongSelf.environment.libraryStore != nil) {
            [strongSelf.environment.libraryStore updateProfile:profile error:NULL];
        }
    }];
}

- (void)authDidChange:(NSNotification *)notification
{
    MRTokenSession *session = self.environment.auth.session;
    if (session == nil || !self.environment.auth.isSignedIn) {
        [self.environment.syncEngine cancel];
        [self postLibraryChangeForStore:self.environment.libraryStore];
        return;
    }
    if (session.accountID <= 0) {
        [self resolveAccountForSession:session refreshProfile:YES];
        return;
    }
    if (self.environment.accountID != session.accountID ||
        self.environment.libraryStore == nil) {
        [self resolveAccountForSession:session refreshProfile:YES];
    }
}

- (void)postLibraryChangeForStore:(MRLibraryStore *)store
{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MRLibraryDidChangeNotification
                      object:store];
}

@end
