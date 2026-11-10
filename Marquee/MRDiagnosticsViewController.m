//
//  MRDiagnosticsViewController.m
//  Marquee
//

#import "MRDiagnosticsViewController.h"

#import <sys/utsname.h>

#import "MRAppEnvironment.h"
#import "MRAppearance.h"
#import "MRDiagnostics.h"
#import "MRDiagnosticsReport.h"
#import "MRImageCache.h"
#import "MRLibraryStore.h"
#import "MROutbox.h"
#import "MRQuotaTracker.h"
#import "MRResponseCache.h"
#import "MRSimklAuth.h"
#import "MRStorage.h"
#import "MRSyncEngine.h"
#import "MRToastView.h"
#import "MRTokenSession.h"
#import "MRUserProfile.h"

static const NSInteger MRDiagnosticsAlertForceSync = 19001;

typedef NS_ENUM(NSInteger, MRDiagnosticsSection) {
    MRDiagnosticsSectionDevice = 0,
    MRDiagnosticsSectionAccount,
    MRDiagnosticsSectionCache,
    MRDiagnosticsSectionErrors,
    MRDiagnosticsSectionActions
};

static NSString *MRDiagnosticsHardwareModel(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        return [NSString stringWithUTF8String:systemInfo.machine];
    }
    return [[UIDevice currentDevice] model];
}

static NSString *MRDiagnosticsDateString(NSDate *date) {
    if (date == nil) {
        return @"Never";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d, h:mm a"];
    return [formatter stringFromDate:date];
}

static NSString *MRDiagnosticsByteString(unsigned long long bytes) {
    if (bytes >= 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f MB",
                (double)bytes / (1024.0 * 1024.0)];
    }
    if (bytes >= 1024ULL) {
        return [NSString stringWithFormat:@"%.0f KB",
                (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

@interface MRDiagnosticsViewController () <UITableViewDataSource, UITableViewDelegate,
                                         UIAlertViewDelegate>

@property (nonatomic, strong) MRAppEnvironment *environment;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *errorRecords;
@property (nonatomic, assign, getter=isForcingSync) BOOL forcingSync;

@end

@implementation MRDiagnosticsViewController

- (instancetype)initWithEnvironment:(MRAppEnvironment *)environment {
    self = [super init];
    if (self) {
        _environment = environment;
        _errorRecords = @[];
    }
    return self;
}

- (id)init {
    return [self initWithEnvironment:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Diagnostics";
    self.view.backgroundColor = [MRAppearance groupBackground];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(copyTapped:)];

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                          style:UITableViewStyleGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.backgroundColor = [MRAppearance groupBackground];
    [self.view addSubview:tableView];
    self.tableView = tableView;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(dataDidChange:)
                   name:MRSyncStatusDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(dataDidChange:)
                   name:MRQuotaDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(dataDidChange:)
                   name:MRLibraryDidChangeNotification
                 object:nil];

    [self reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dataDidChange:(NSNotification *)notification {
    [self reloadData];
}

- (void)reloadData {
    self.errorRecords = [self.environment.diagnostics recentRecords:20];
    [self.tableView reloadData];
}

#pragma mark - Values

- (MRUserProfile *)profile {
    return self.environment.libraryStore.profile;
}

- (NSInteger)accountID {
    NSInteger accountID = self.profile.accountID;
    if (accountID <= 0) {
        accountID = self.environment.auth.session.accountID;
    }
    return accountID;
}

- (NSDictionary *)reportFields {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    MRUserProfile *profile = self.profile;
    MRSyncEngine *sync = self.environment.syncEngine;
    MRQuotaTracker *quota = self.environment.quotaTracker;
    MROutbox *outbox = self.environment.outbox;

    NSString *syncResult = @"Never synced";
    if (sync.lastSyncError != nil) {
        syncResult = [NSString stringWithFormat:@"Failed: %@",
                      [sync.lastSyncError localizedDescription]];
    } else if (sync.lastSyncAt != nil) {
        syncResult = @"Success";
    }

    unsigned long long cacheBytes =
        self.environment.imageCache.diskUsageBytes +
        [self.environment.responseCache diskUsageBytes];

    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    [fields setObject:([info objectForKey:@"CFBundleShortVersionString"] != nil
                       ? [info objectForKey:@"CFBundleShortVersionString"] : @"1.0")
               forKey:@"appVersion"];
    [fields setObject:([info objectForKey:@"CFBundleVersion"] != nil
                       ? [info objectForKey:@"CFBundleVersion"] : @"1")
               forKey:@"build"];
    [fields setObject:[[UIDevice currentDevice] systemVersion] forKey:@"osVersion"];
    [fields setObject:MRDiagnosticsHardwareModel() forKey:@"deviceModel"];
    if (profile.name.length > 0) {
        [fields setObject:profile.name forKey:@"accountName"];
    } else {
        [fields setObject:@"Signed in" forKey:@"accountName"];
    }
    [fields setObject:@([self accountID]) forKey:@"accountID"];
    [fields setObject:MRDiagnosticsDateString(sync.lastSyncAttemptAt)
               forKey:@"lastSyncAttempt"];
    [fields setObject:syncResult forKey:@"lastSyncResult"];
    [fields setObject:@(outbox.pendingCount) forKey:@"pendingCount"];
    [fields setObject:@(quota.requestsToday) forKey:@"requestsToday"];
    [fields setObject:@(quota.limit) forKey:@"quotaLimit"];
    [fields setObject:@(quota.remaining) forKey:@"quotaRemaining"];
    if (quota.resetAt != nil) {
        [fields setObject:MRDiagnosticsDateString(quota.resetAt) forKey:@"quotaResetAt"];
    }
    [fields setObject:@(cacheBytes) forKey:@"cacheBytes"];
    [fields setObject:self.errorRecords forKey:@"errors"];
    return fields;
}

- (NSString *)reportText {
    return [MRDiagnosticsReport reportWithFields:[self reportFields]];
}

- (NSString *)quotaText {
    MRQuotaTracker *quota = self.environment.quotaTracker;
    if (quota.limit < 0 && quota.remaining < 0) {
        return @"Unknown";
    }
    if (quota.limit >= 0 && quota.remaining >= 0) {
        return [NSString stringWithFormat:@"%ld of %ld left",
                (long)quota.remaining, (long)quota.limit];
    }
    if (quota.remaining >= 0) {
        return [NSString stringWithFormat:@"%ld left", (long)quota.remaining];
    }
    return [NSString stringWithFormat:@"Limit %ld", (long)quota.limit];
}

#pragma mark - Actions

- (void)copyTapped:(id)sender {
    [UIPasteboard generalPasteboard].string = [self reportText];
    [MRToastView showMessage:@"Diagnostics copied" inView:self.view];
}

- (void)clearImageCache {
    [self.environment.imageCache clearMemoryCache];
    [self.environment.imageCache clearDiskCache];
    [self reloadData];
    [MRToastView showMessage:@"Image cache cleared" inView:self.view];
}

- (void)confirmForceFullSync {
    UIAlertView *alert = [[UIAlertView alloc]
        initWithTitle:@"Force Full Sync"
              message:@"The saved library snapshot is deleted and downloaded again. Pending writes are kept."
             delegate:self
    cancelButtonTitle:@"Cancel"
    otherButtonTitles:@"Sync", nil];
    alert.tag = MRDiagnosticsAlertForceSync;
    [alert show];
}

- (void)forceFullSync {
    MRSyncEngine *engine = self.environment.syncEngine;
    if (engine == nil || self.isForcingSync) {
        return;
    }

    self.forcingSync = YES;
    [self.tableView reloadData];
    __weak MRDiagnosticsViewController *weakSelf = self;
    [engine forceFullSyncWithCompletion:^(NSError *error) {
        MRDiagnosticsViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.forcingSync = NO;
        [strongSelf reloadData];
        [MRToastView showMessage:(error != nil ? @"Full sync failed" : @"Full sync complete")
                          inView:strongSelf.view];
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == MRDiagnosticsAlertForceSync && buttonIndex == 1) {
        [self forceFullSync];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MRDiagnosticsSectionDevice:
            return 3;
        case MRDiagnosticsSectionAccount:
            return 6;
        case MRDiagnosticsSectionCache:
            return 2;
        case MRDiagnosticsSectionErrors:
            return MAX((NSInteger)1, (NSInteger)self.errorRecords.count);
        case MRDiagnosticsSectionActions:
            return 3;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case MRDiagnosticsSectionDevice:
            return @"Device";
        case MRDiagnosticsSectionAccount:
            return @"Account & Sync";
        case MRDiagnosticsSectionCache:
            return @"Caches";
        case MRDiagnosticsSectionErrors:
            return @"Recent API Errors";
        case MRDiagnosticsSectionActions:
            return @"Actions";
    }
    return nil;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title
                                 detail:(NSString *)detail
                              tableView:(UITableView *)tableView {
    static NSString *identifier = @"MRDiagnosticsValueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:identifier];
    }
    cell.textLabel.text = title;
    cell.textLabel.font = [MRAppearance bodyFont];
    cell.textLabel.textColor = [MRAppearance ink];
    cell.detailTextLabel.text = detail != nil ? detail : @"";
    cell.detailTextLabel.font = [MRAppearance smallFont];
    cell.detailTextLabel.textColor = [MRAppearance muted];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == MRDiagnosticsSectionErrors) {
        if (self.errorRecords.count == 0) {
            return [self valueCellWithTitle:@"No recent errors"
                                     detail:nil
                                  tableView:tableView];
        }

        static NSString *identifier = @"MRDiagnosticsErrorCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:identifier];
        }

        NSDictionary *record =
            [self.errorRecords objectAtIndex:(NSUInteger)indexPath.row];
        NSString *method = [record objectForKey:@"method"];
        NSString *path = [record objectForKey:@"path"];
        NSNumber *status = [record objectForKey:@"status"];
        NSString *code = [record objectForKey:@"code"];
        NSString *message = [record objectForKey:@"message"];

        NSMutableString *title = [NSMutableString string];
        if (method.length > 0) {
            [title appendFormat:@"%@ ", method];
        }
        if (path.length > 0) {
            [title appendString:path];
        }
        if (status != nil) {
            [title appendFormat:@" → %@", status];
        }
        if (code.length > 0) {
            [title appendFormat:@" (%@)", code];
        }
        cell.textLabel.text = title;
        cell.textLabel.font = [MRAppearance bodyFont];
        cell.textLabel.textColor = [MRAppearance ink];
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        NSString *timestamp = [record objectForKey:@"timestamp"];
        NSString *detail = message.length > 0 ? message : timestamp;
        cell.detailTextLabel.text = detail;
        cell.detailTextLabel.font = [MRAppearance smallFont];
        cell.detailTextLabel.textColor = [MRAppearance muted];
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == MRDiagnosticsSectionActions) {
        static NSString *identifier = @"MRDiagnosticsActionCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:identifier];
        }
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [MRAppearance link];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Copy Diagnostics";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Clear Image Cache";
        } else {
            cell.textLabel.text = self.isForcingSync ? @"Syncing…" : @"Force Full Sync";
            cell.textLabel.textColor = [MRAppearance droppedColor];
        }
        return cell;
    }

    UITableViewCell *cell = nil;
    if (indexPath.section == MRDiagnosticsSectionDevice) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        if (indexPath.row == 0) {
            NSString *version = [info objectForKey:@"CFBundleShortVersionString"];
            NSString *build = [info objectForKey:@"CFBundleVersion"];
            NSString *detail = version.length > 0 ? version : @"1.0";
            if (build.length > 0) {
                detail = [detail stringByAppendingFormat:@" (%@)", build];
            }
            cell = [self valueCellWithTitle:@"App" detail:detail tableView:tableView];
        } else if (indexPath.row == 1) {
            cell = [self valueCellWithTitle:@"iOS"
                                     detail:[[UIDevice currentDevice] systemVersion]
                                  tableView:tableView];
        } else {
            cell = [self valueCellWithTitle:@"Device"
                                     detail:MRDiagnosticsHardwareModel()
                                  tableView:tableView];
        }
        return cell;
    }

    if (indexPath.section == MRDiagnosticsSectionCache) {
        if (indexPath.row == 0) {
            cell = [self valueCellWithTitle:@"Image cache"
                                     detail:MRDiagnosticsByteString(
                                         self.environment.imageCache.diskUsageBytes)
                                  tableView:tableView];
        } else {
            cell = [self valueCellWithTitle:@"Response cache"
                                     detail:MRDiagnosticsByteString(
                                         [self.environment.responseCache diskUsageBytes])
                                  tableView:tableView];
        }
        return cell;
    }

    MRUserProfile *profile = self.profile;
    MRSyncEngine *sync = self.environment.syncEngine;
    MRQuotaTracker *quota = self.environment.quotaTracker;
    if (indexPath.row == 0) {
        NSString *account = profile.name.length > 0 ? profile.name : @"Signed in";
        NSInteger accountID = [self accountID];
        if (accountID > 0) {
            account = [account stringByAppendingFormat:@" (#%ld)", (long)accountID];
        }
        cell = [self valueCellWithTitle:@"Account" detail:account tableView:tableView];
    } else if (indexPath.row == 1) {
        NSString *result = @"Never synced";
        if (sync.lastSyncError != nil) {
            result = @"Failed";
        } else if (sync.lastSyncAt != nil) {
            result = [NSString stringWithFormat:@"Synced %@",
                      MRDiagnosticsDateString(sync.lastSyncAt)];
        }
        cell = [self valueCellWithTitle:@"Last sync" detail:result tableView:tableView];
    } else if (indexPath.row == 2) {
        cell = [self valueCellWithTitle:@"Pending writes"
                                 detail:[NSString stringWithFormat:@"%lu",
                                         (unsigned long)self.environment.outbox.pendingCount]
                              tableView:tableView];
    } else if (indexPath.row == 3) {
        cell = [self valueCellWithTitle:@"Today's requests"
                                 detail:[NSString stringWithFormat:@"%ld",
                                         (long)quota.requestsToday]
                              tableView:tableView];
    } else if (indexPath.row == 4) {
        cell = [self valueCellWithTitle:@"Daily requests"
                                 detail:[self quotaText]
                              tableView:tableView];
    } else {
        cell = [self valueCellWithTitle:@"Quota resets"
                                 detail:(quota.resetAt != nil
                                         ? MRDiagnosticsDateString(quota.resetAt)
                                         : @"Unknown")
                              tableView:tableView];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section != MRDiagnosticsSectionActions) {
        return;
    }
    if (indexPath.row == 0) {
        [self copyTapped:nil];
    } else if (indexPath.row == 1) {
        [self clearImageCache];
    } else {
        [self confirmForceFullSync];
    }
}

@end
