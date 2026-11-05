//
//  MRConnectViewController.m
//  Marquee
//

#import "MRConnectViewController.h"

#import "MRAppearance.h"
#import "MRDeviceCode.h"
#import "MRError.h"
#import "MRSimklAuth.h"
#import "MRTokenSession.h"

@interface MRConnectViewController ()
@property (nonatomic, strong) MRSimklAuth *auth;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *instructionLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *codeCopyButton;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *verificationURL;
@property (nonatomic, copy) NSString *userCode;
@property (nonatomic, assign, getter=isPolling) BOOL polling;
@property (nonatomic, assign, getter=isRetryingProfile) BOOL retryingProfile;
@property (nonatomic, assign, getter=isFinishing) BOOL finishing;
@end

@implementation MRConnectViewController

- (instancetype)initWithAuth:(MRSimklAuth *)auth {
    self = [super init];
    if (self) {
        _auth = auth;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Connect Simkl";
    self.view.backgroundColor = [MRAppearance groupBackground];
    [MRAppearance styleNavigationBar:self.navigationController.navigationBar];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithCustomView:
            [MRAppearance barButtonWithTitle:@"Cancel"
                                       back:NO
                                     target:self
                                     action:@selector(cancelTapped:)]];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    scrollView.backgroundColor = [MRAppearance groupBackground];
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    self.codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.codeLabel.backgroundColor = [UIColor clearColor];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:34.0];
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.textColor = [MRAppearance ink];
    self.codeLabel.adjustsFontSizeToFitWidth = YES;
    self.codeLabel.minimumScaleFactor = 0.5;
    self.codeLabel.lineBreakMode = NSLineBreakByClipping;
    [scrollView addSubview:self.codeLabel];

    self.instructionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.instructionLabel.backgroundColor = [UIColor clearColor];
    self.instructionLabel.font = [UIFont systemFontOfSize:13.0];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.textColor = [MRAppearance muted];
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.text = @"Approve Marquee on SimKL, then come back here.";
    [scrollView addSubview:self.instructionLabel];

    self.openButton = [self actionButtonWithTitle:@"Open simkl.com/pin"
                                           action:@selector(openTapped:)];
    [scrollView addSubview:self.openButton];

    self.codeCopyButton = [self actionButtonWithTitle:@"Copy Code"
                                           action:@selector(copyTapped:)];
    [scrollView addSubview:self.codeCopyButton];

    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [scrollView addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.font = [UIFont systemFontOfSize:13.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [MRAppearance muted];
    self.statusLabel.numberOfLines = 0;
    [scrollView addSubview:self.statusLabel];

    self.retryButton = [self actionButtonWithTitle:@"Try Again"
                                            action:@selector(retryTapped:)];
    self.retryButton.hidden = YES;
    [scrollView addSubview:self.retryButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [self showCodeControls:NO];
    [self startDeviceFlow];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat margin = 24.0;
    CGFloat contentWidth = width - margin * 2.0;
    CGFloat y = 24.0;

    self.codeLabel.frame = CGRectMake(margin, y, contentWidth, 48.0);
    y += 48.0 + 8.0;
    self.instructionLabel.frame = CGRectMake(margin, y, contentWidth, 36.0);
    y += 36.0 + 20.0;
    self.openButton.frame = CGRectMake(margin, y, contentWidth, 42.0);
    y += 42.0 + 10.0;
    self.codeCopyButton.frame = CGRectMake(margin, y, contentWidth, 42.0);
    y += 42.0 + 20.0;

    self.spinner.frame = CGRectMake((width - 20.0) / 2.0, y, 20.0, 20.0);
    y += 20.0 + 10.0;
    self.statusLabel.frame = CGRectMake(margin, y, contentWidth, 44.0);
    y += 44.0 + 12.0;
    self.retryButton.frame = CGRectMake(margin, y, contentWidth, 42.0);
    y += 42.0 + 24.0;

    self.scrollView.contentSize = CGSizeMake(width, y);
}

- (UIButton *)actionButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setBackgroundImage:[MRAppearance actionButtonImage]
                      forState:UIControlStateNormal];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.45]
                       forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    button.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)showCodeControls:(BOOL)show {
    self.codeLabel.hidden = !show;
    self.instructionLabel.hidden = !show;
    self.openButton.hidden = !show;
    self.codeCopyButton.hidden = !show;
}

#pragma mark - Flow

- (void)startDeviceFlow {
    self.finishing = NO;
    self.retryingProfile = NO;
    self.polling = NO;
    self.userCode = nil;
    self.verificationURL = nil;
    self.codeLabel.text = @"";
    [self showCodeControls:NO];
    self.retryButton.hidden = YES;
    self.statusLabel.text = @"Requesting a code...";
    [self.spinner startAnimating];

    __weak MRConnectViewController *weakSelf = self;
    [self.auth beginDeviceFlowWithCompletion:^(MRDeviceCode *code, NSError *error) {
        MRConnectViewController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.isFinishing) {
            return;
        }
        if (code == nil) {
            [strongSelf showFailure:error retryTitle:@"Try Again"];
            return;
        }

        strongSelf.userCode = code.userCode;
        strongSelf.verificationURL = code.verificationURIComplete.length > 0
            ? code.verificationURIComplete
            : code.verificationURI;
        strongSelf.codeLabel.text = code.userCode;
        [strongSelf showCodeControls:YES];
        strongSelf.statusLabel.text = @"Waiting for approval...";
        strongSelf.retryButton.hidden = YES;
        [strongSelf.spinner startAnimating];
        strongSelf.polling = YES;
        [strongSelf poll];
    }];
}

- (void)poll {
    if (!self.isPolling || self.isFinishing) {
        return;
    }
    __weak MRConnectViewController *weakSelf = self;
    [self.auth pollDeviceFlowWithCompletion:^(MRTokenSession *session, NSError *error) {
        MRConnectViewController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.isFinishing) {
            return;
        }
        [strongSelf handlePollSession:session error:error];
    }];
}

- (void)handlePollSession:(MRTokenSession *)session error:(NSError *)error {
    if (session != nil && error == nil) {
        self.polling = NO;
        [self.spinner stopAnimating];
        self.statusLabel.text = session.accountName.length > 0
            ? [NSString stringWithFormat:@"Connected as %@", session.accountName]
            : @"Connected to Simkl";
        [self finishWithSession:session];
        return;
    }

    if (session != nil) {
        self.polling = NO;
        [self.spinner stopAnimating];
        self.statusLabel.text = @"Signed in, but couldn't load your profile";
        self.retryingProfile = YES;
        self.retryButton.hidden = NO;
        [self.retryButton setTitle:@"Retry" forState:UIControlStateNormal];
        return;
    }

    MRErrorKind kind = [MRError kindForError:error];
    if (kind == MRErrorKindCancelled) {
        return;
    }

    self.polling = NO;
    [self.spinner stopAnimating];
    if (kind == MRErrorKindAuthExpired) {
        self.statusLabel.text = @"Code expired";
        [self showFailure:error retryTitle:@"Try Again"];
        self.statusLabel.text = @"Code expired";
    } else if (kind == MRErrorKindClientRejected) {
        self.statusLabel.text =
            @"Marquee could not identify itself to Simkl. Check Diagnostics.";
        self.retryButton.hidden = YES;
    } else {
        [self showFailure:error retryTitle:@"Try Again"];
    }
}

- (void)showFailure:(NSError *)error retryTitle:(NSString *)retryTitle {
    [self.spinner stopAnimating];
    if (error.localizedDescription.length > 0) {
        self.statusLabel.text = error.localizedDescription;
    }
    self.retryButton.hidden = retryTitle.length == 0;
    [self.retryButton setTitle:retryTitle forState:UIControlStateNormal];
}

- (void)retryTapped:(UIButton *)sender {
    if (self.isRetryingProfile) {
        self.retryingProfile = NO;
        self.retryButton.hidden = YES;
        self.statusLabel.text = @"Loading your profile...";
        [self.spinner startAnimating];

        __weak MRConnectViewController *weakSelf = self;
        [self.auth restoreWithCompletion:^(MRTokenSession *session, NSError *error) {
            MRConnectViewController *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.isFinishing) {
                return;
            }
            if (session != nil && error == nil) {
                [strongSelf.spinner stopAnimating];
                strongSelf.statusLabel.text = session.accountName.length > 0
                    ? [NSString stringWithFormat:@"Connected as %@", session.accountName]
                    : @"Connected to Simkl";
                [strongSelf finishWithSession:session];
                return;
            }
            if (session != nil) {
                [strongSelf.spinner stopAnimating];
                strongSelf.statusLabel.text = @"Signed in, but couldn't load your profile";
                strongSelf.retryingProfile = YES;
                strongSelf.retryButton.hidden = NO;
                [strongSelf.retryButton setTitle:@"Retry" forState:UIControlStateNormal];
                return;
            }
            [strongSelf showFailure:error retryTitle:@"Try Again"];
        }];
        return;
    }

    [self startDeviceFlow];
}

- (void)finishWithSession:(MRTokenSession *)session {
    if (self.isFinishing) {
        return;
    }
    self.finishing = YES;
    if (self.completionHandler != nil) {
        self.completionHandler(session);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Actions

- (void)openTapped:(UIButton *)sender {
    NSString *URLString = self.verificationURL;
    if (URLString.length == 0) {
        return;
    }
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL != nil) {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)copyTapped:(UIButton *)sender {
    if (self.userCode.length == 0) {
        return;
    }
    [UIPasteboard generalPasteboard].string = self.userCode;
    self.statusLabel.text = @"Code copied.";
}

- (void)cancelTapped:(id)sender {
    [self.auth cancelDeviceFlow];
    self.polling = NO;
    if (self.completionHandler != nil) {
        self.completionHandler(self.auth.session);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Lifecycle

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (self.isPolling && !self.isFinishing) {
        [self poll];
    }
}

@end
