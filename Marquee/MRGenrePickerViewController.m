//
//  MRGenrePickerViewController.m
//  Marquee
//

#import "MRGenrePickerViewController.h"

#import "MRAppearance.h"
#import "MRGenreChoice.h"
#import "MRLayout.h"
#import "MRPlaceholderView.h"
#import "MRPreferencesStore.h"
#import "MRRecommendationDataProviding.h"

static const NSInteger MRGenrePickerMaximumSelections = 5;
static const NSInteger MRGenrePickerTypeCount = 3;

@interface MRGenrePickerViewController ()

@property (nonatomic, strong) id<MRRecommendationDataProviding> dataProvider;
@property (nonatomic, strong) MRPreferencesStore *preferences;
@property (nonatomic, strong) NSMutableArray *selectedChoices;
@property (nonatomic, strong) NSMutableDictionary *choicesByType;
@property (nonatomic, copy) NSArray *visibleTypes;
@property (nonatomic, assign) NSInteger pendingIndexes;
@property (nonatomic, assign) NSInteger failedIndexes;
@property (nonatomic, assign, getter=isLoadingGenres) BOOL loadingGenres;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *loadingLabel;
@property (nonatomic, strong) MRPlaceholderView *failureView;

@end

@implementation MRGenrePickerViewController

- (instancetype)initWithDataProvider:(id<MRRecommendationDataProviding>)dataProvider
                         preferences:(MRPreferencesStore *)preferences {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _dataProvider = dataProvider;
        _preferences = preferences;
        _choicesByType = [NSMutableDictionary dictionary];
        _visibleTypes = @[];
        NSArray *existing = preferences.manualGenres;
        _selectedChoices = [NSMutableArray arrayWithArray:
                            [existing isKindOfClass:[NSArray class]] ? existing : @[]];
    }
    return self;
}

- (id)init {
    return [self initWithDataProvider:nil preferences:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Favorite Genres";
    self.view.backgroundColor = [MRAppearance groupBackground];

    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [MRAppearance groupBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [MRAppearance sep];
    self.tableView.rowHeight = 44.0;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithCustomView:[MRAppearance barButtonWithTitle:@"Cancel"
                                                       back:NO
                                                     target:self
                                                     action:@selector(cancelTapped:)]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithCustomView:[MRAppearance barButtonWithTitle:@"Done"
                                                       back:NO
                                                     target:self
                                                     action:@selector(doneTapped:)]];

    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.loadingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.loadingLabel.backgroundColor = [UIColor clearColor];
    self.loadingLabel.font = [MRAppearance bodyFont];
    self.loadingLabel.textColor = [MRAppearance muted];
    self.loadingLabel.textAlignment = NSTextAlignmentCenter;
    self.loadingLabel.text = @"Loading genres…";
    [self.view addSubview:self.loadingLabel];

    MRPlaceholderView *failure =
        [[MRPlaceholderView alloc] initWithMessage:@"Genres couldn't be loaded."
                                       actionTitle:@"Retry"];
    __weak MRGenrePickerViewController *weakSelf = self;
    failure.actionHandler = ^{
        [weakSelf loadGenres];
    };
    failure.hidden = YES;
    [self.view addSubview:failure];
    self.failureView = failure;

    [self loadGenres];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    self.spinner.center = CGPointMake(width / 2.0, height / 2.0 - 24.0);
    self.loadingLabel.frame = CGRectMake(16.0,
                                         CGRectGetMaxY(self.spinner.frame) + 8.0,
                                         width - 32.0,
                                         20.0);

    CGFloat cardWidth = MIN(width - 24.0,
        [MRLayout modalContentMaxWidthForDeviceClass:
         [MRLayout deviceClassForIdiom:[[UIDevice currentDevice] userInterfaceIdiom]]]);
    self.failureView.frame = CGRectMake(floor((width - cardWidth) / 2.0),
                                        floor((height - 160.0) / 2.0),
                                        cardWidth,
                                        160.0);
}

#pragma mark - Loading

- (void)loadGenres {
    if (self.isLoadingGenres) {
        return;
    }

    self.loadingGenres = YES;
    self.failedIndexes = 0;
    self.pendingIndexes = 0;
    [self.choicesByType removeAllObjects];
    self.visibleTypes = @[];
    self.failureView.hidden = YES;
    self.tableView.hidden = YES;
    [self.spinner startAnimating];
    self.loadingLabel.hidden = NO;

    if (self.dataProvider == nil) {
        self.loadingGenres = NO;
        [self showFailure];
        return;
    }

    for (NSInteger type = MRMediaTypeMovie; type <= MRMediaTypeAnime; type++) {
        self.pendingIndexes += 1;
        __weak MRGenrePickerViewController *weakSelf = self;
        [self.dataProvider fetchGenreIndexForType:(MRMediaType)type
                                       completion:^(NSArray *json, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handleIndex:json error:error type:(MRMediaType)type];
            });
        }];
    }
}

- (void)handleIndex:(NSArray *)json
              error:(NSError *)error
               type:(MRMediaType)type {
    self.pendingIndexes -= 1;

    if (error == nil && [json isKindOfClass:[NSArray class]]) {
        NSArray *choices = [MRGenreChoice allowedGenresFromIndex:json type:type];
        [self.choicesByType setObject:choices forKey:[NSNumber numberWithInteger:type]];
    } else {
        self.failedIndexes += 1;
    }

    if (self.pendingIndexes > 0) {
        return;
    }

    self.loadingGenres = NO;
    NSUInteger choiceCount = 0;
    for (NSArray *choices in [self.choicesByType allValues]) {
        choiceCount += choices.count;
    }
    if (self.failedIndexes >= MRGenrePickerTypeCount || choiceCount == 0) {
        [self showFailure];
        return;
    }

    NSMutableArray *types = [NSMutableArray array];
    for (NSInteger value = MRMediaTypeMovie; value <= MRMediaTypeAnime; value++) {
        NSArray *choices = [self.choicesByType objectForKey:
                            [NSNumber numberWithInteger:value]];
        if (choices.count > 0) {
            [types addObject:[NSNumber numberWithInteger:value]];
        }
    }
    self.visibleTypes = types;

    [self.spinner stopAnimating];
    self.loadingLabel.hidden = YES;
    self.failureView.hidden = YES;
    self.tableView.hidden = NO;
    [self.tableView reloadData];
}

- (void)showFailure {
    [self.spinner stopAnimating];
    self.loadingLabel.hidden = YES;
    self.tableView.hidden = YES;
    self.failureView.hidden = NO;
}

#pragma mark - Saving

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped:(id)sender {
    if (self.preferences == nil) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    NSError *error = nil;
    if (![self.preferences setManualGenres:self.selectedChoices error:&error]) {
        NSString *message = @"Your selections couldn't be saved.";
        if ([error.domain isEqualToString:MRPreferencesStoreErrorDomain] &&
            error.code == MRPreferencesStoreErrorManualGenreLimit) {
            message = @"You can pick up to five genres.";
        }
        [self showAlertWithTitle:@"Couldn't Save" message:message];
        return;
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark - Choices

- (NSArray *)choicesForType:(MRMediaType)type {
    NSArray *choices = [self.choicesByType objectForKey:
                        [NSNumber numberWithInteger:type]];
    return [choices isKindOfClass:[NSArray class]] ? choices : @[];
}

- (MRGenreChoice *)choiceAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < 0 ||
        (NSUInteger)indexPath.section >= self.visibleTypes.count) {
        return nil;
    }
    MRMediaType type = (MRMediaType)
        [[self.visibleTypes objectAtIndex:(NSUInteger)indexPath.section] integerValue];
    NSArray *choices = [self choicesForType:type];
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= choices.count) {
        return nil;
    }
    return [choices objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)titleForType:(MRMediaType)type {
    switch (type) {
        case MRMediaTypeMovie:
            return @"Movies";
        case MRMediaTypeShow:
            return @"TV";
        case MRMediaTypeAnime:
            return @"Anime";
        default:
            return @"";
    }
}

- (void)removeChoice:(MRGenreChoice *)choice {
    [self.selectedChoices removeObject:choice];
}

- (void)toggleChoice:(MRGenreChoice *)choice {
    if (choice == nil) {
        return;
    }
    if ([self.selectedChoices containsObject:choice]) {
        [self removeChoice:choice];
        [self.tableView reloadData];
        return;
    }

    if (self.selectedChoices.count >= (NSUInteger)MRGenrePickerMaximumSelections) {
        [self showAlertWithTitle:@"Genre Limit"
                         message:@"You can pick up to five genres. Deselect one before adding another."];
        return;
    }

    [self.selectedChoices addObject:choice];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.visibleTypes.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || (NSUInteger)section >= self.visibleTypes.count) {
        return 0;
    }
    MRMediaType type = (MRMediaType)
        [[self.visibleTypes objectAtIndex:(NSUInteger)section] integerValue];
    return (NSInteger)[self choicesForType:type].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < 0 || (NSUInteger)section >= self.visibleTypes.count) {
        return nil;
    }
    MRMediaType type = (MRMediaType)
        [[self.visibleTypes objectAtIndex:(NSUInteger)section] integerValue];
    return [self titleForType:type];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != (NSInteger)self.visibleTypes.count - 1) {
        return nil;
    }
    return [NSString stringWithFormat:@"%lu of %ld selected",
            (unsigned long)self.selectedChoices.count,
            (long)MRGenrePickerMaximumSelections];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MRGenrePickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        cell.textLabel.font = [MRAppearance bodyFont];
        cell.textLabel.textColor = [MRAppearance ink];
        cell.backgroundColor = [UIColor whiteColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }

    MRGenreChoice *choice = [self choiceAtIndexPath:indexPath];
    cell.textLabel.text = choice.name != nil ? choice.name : @"";
    cell.accessoryType = [self.selectedChoices containsObject:choice]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self toggleChoice:[self choiceAtIndexPath:indexPath]];
}

@end
