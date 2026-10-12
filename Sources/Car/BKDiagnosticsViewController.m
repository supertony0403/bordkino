#import "BKDiagnosticsViewController.h"
#import <WebKit/WebKit.h>
#import "BKPlayer.h"
#import "BKLibrary.h"
#import "BKCarState.h"
#import "BKDriveGuard.h"
#import "BKScriptHost.h"
#import "BKVideoListViewController.h"
#import "BKLog.h"

/// Colour bars – if these show up in the car, UIKit rendering on the CarPlay screen works.
@interface BKTestPatternView : UIView
@end

@implementation BKTestPatternView
- (void)drawRect:(CGRect)rect {
    NSArray *colors = @[UIColor.whiteColor, UIColor.yellowColor, UIColor.cyanColor, UIColor.greenColor,
                        UIColor.magentaColor, UIColor.redColor, UIColor.blueColor, UIColor.blackColor];
    CGFloat w = self.bounds.size.width / colors.count;
    for (NSUInteger i = 0; i < colors.count; i++) {
        [colors[i] setFill];
        UIRectFill(CGRectMake(i * w, 0, ceil(w), self.bounds.size.height * 0.75));
    }
    for (NSUInteger i = 0; i < 16; i++) {
        [[UIColor colorWithWhite:i / 15.0 alpha:1] setFill];
        CGFloat gw = self.bounds.size.width / 16;
        UIRectFill(CGRectMake(i * gw, self.bounds.size.height * 0.75, ceil(gw), self.bounds.size.height * 0.25));
    }
    NSString *text = [NSString stringWithFormat:@"Testbild – UIKit zeichnet hier (%.0f×%.0f @%.0fx). Antippen zum Schließen.",
                      self.bounds.size.width, self.bounds.size.height, self.window.screen.scale];
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: UIColor.whiteColor,
                             NSBackgroundColorAttributeName: [UIColor colorWithWhite:0 alpha:0.7] };
    [text drawInRect:CGRectInset(CGRectMake(0, self.bounds.size.height * 0.35, self.bounds.size.width, 80), 20, 0) withAttributes:attrs];
}
@end

@interface BKOverlayViewController : UIViewController
@property (nonatomic, strong) UIView *content;
@end

@implementation BKOverlayViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.content.frame = self.view.bounds;
    self.content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.content];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeClose];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [close.widthAnchor constraintEqualToConstant:56],
        [close.heightAnchor constraintEqualToConstant:56],
    ]];
    if ([self.content isKindOfClass:BKTestPatternView.class]) {
        [self.content addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];
    }
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation BKDiagnosticsViewController {
    UILabel *_info;
    UITextView *_log;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Diagnose";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:1];

    _info = [UILabel new];
    _info.numberOfLines = 0;
    _info.textColor = UIColor.whiteColor;
    _info.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];

    NSArray *buttons = @[
        [self action:@"Testbild" symbol:@"rectangle.split.3x1" selector:@selector(showPattern)],
        [self action:@"Testvideo A" symbol:@"play.rectangle" selector:@selector(testVideoA)],
        [self action:@"Testvideo B" symbol:@"play.rectangle.fill" selector:@selector(testVideoB)],
        [self action:@"Web-Modus" symbol:@"globe" selector:@selector(showWeb)],
        [self action:@"Protokoll" symbol:@"arrow.clockwise" selector:@selector(refresh)],
    ];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;

    _log = [UITextView new];
    _log.editable = NO;
    _log.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    _log.textColor = UIColor.lightGrayColor;
    _log.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _log.layer.cornerRadius = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_info, row, _log]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [row.heightAnchor constraintEqualToConstant:72],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (UIButton *)action:(NSString *)title symbol:(NSString *)symbol selector:(SEL)selector {
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.image = [UIImage systemImageNamed:symbol];
    config.imagePlacement = NSDirectionalRectEdgeTop;
    config.imagePadding = 4;
    config.title = title;
    config.baseBackgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    config.baseForegroundColor = UIColor.whiteColor;
    UIButton *b = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refresh {
    UIScreen *screen = self.view.window.screen ?: UIScreen.mainScreen;
    BKDriveGuard *guard = [BKDriveGuard shared];
    BKLibrary *library = [BKLibrary shared];
    _info.text = [NSString stringWithFormat:
        @"%@ · iOS %@\nBildschirm %.0f×%.0f @%.0fx · CarPlay %@\nRenderer %@ · Fahrsperre %@ (%@)\nYouTube-Modul %@ (%@) · Client %@",
        [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"], UIDevice.currentDevice.systemVersion,
        screen.bounds.size.width, screen.bounds.size.height, screen.scale, [BKCarState shared].connected ? @"verbunden" : @"getrennt",
        library.renderer == BKRendererPump ? @"B (Metal)" : @"A (AVPlayerLayer)",
        library.driveLockEnabled ? @"an" : @"aus",
        guard.locationAvailable ? (guard.lastSpeedKmh >= 0 ? [NSString stringWithFormat:@"%.0f km/h", guard.lastSpeedKmh] : @"kein Tempo") : @"kein Standort",
        [BKScriptHost shared].extractorVersion, [BKScriptHost shared].extractorSource, [BKPlayer shared].activeClient ?: @"–"];
    NSArray *lines = [BKLog recentLines];
    NSArray *tail = lines.count > 80 ? [lines subarrayWithRange:NSMakeRange(lines.count - 80, 80)] : lines;
    _log.text = [[tail reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n"];
}

- (void)presentOverlay:(UIView *)content {
    BKOverlayViewController *overlay = [BKOverlayViewController new];
    overlay.content = content;
    overlay.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:overlay animated:YES completion:nil];
}

- (void)showPattern {
    BKLogf(@"Diagnose: Testbild");
    [self presentOverlay:[BKTestPatternView new]];
}

- (void)playTestVideoWithRenderer:(BKRenderer)renderer {
    [BKLibrary shared].renderer = renderer;
    BKLogf(@"Diagnose: Testvideo mit Renderer %@", renderer == BKRendererPump ? @"B" : @"A");
    [[BKPlayer shared] playVideo:[BKVideo videoWithDirectURL:[NSURL URLWithString:BKTestStreamURL] title:@"Apple-Testvideo (BipBop)"]];
    // In the car the root view controller shows the player itself.
    if (self.view.window != [BKCarState shared].carWindow) BKPresentPhonePlayer(self);
}

- (void)testVideoA { [self playTestVideoWithRenderer:BKRendererLayer]; }
- (void)testVideoB { [self playTestVideoWithRenderer:BKRendererPump]; }

- (void)showWeb {
    BKLogf(@"Diagnose: Web-Modus (WKWebView)");
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    web.allowsBackForwardNavigationGestures = YES;
    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://m.youtube.com"]]];
    [self presentOverlay:web];
}

@end
