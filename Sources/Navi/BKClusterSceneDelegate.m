#import "BKClusterSceneDelegate.h"
#import "BKVideoSurface.h"
#import "BKPlayer.h"
#import "BKDriveGuard.h"
#import "BKLibrary.h"
#import "BKLog.h"

static const NSTimeInterval kRecheckInterval = 1;

/// Video for the driver display. Fail-safe: black unless BKDriveGuard confirms standstill;
/// this lock does not depend on the user-facing drive-lock setting.
@interface BKClusterViewController : UIViewController
@end

@implementation BKClusterViewController {
    BKVideoSurface *_surface;
    UILabel *_label;
    NSTimer *_timer;
    BOOL _lastVisible;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _surface = [[BKVideoSurface alloc] initWithFrame:self.view.bounds];
    _surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _surface.hidden = YES;
    [self.view addSubview:_surface];
    _label = [UILabel new];
    _label.text = @"Bordkino · Bild nur im Stand";
    _label.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    _label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.frame = self.view.bounds;
    _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_label];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(update) name:BKDriveGuardDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(update) name:BKPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(update) name:BKLibraryDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak BKClusterViewController *weakSelf = self;
    // Staleness of the GPS reading changes without a notification, so poll.
    _timer = [NSTimer scheduledTimerWithTimeInterval:kRecheckInterval repeats:YES block:^(NSTimer *t) { [weakSelf update]; }];
    [self update];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)update {
    BOOL hasVideo = [BKPlayer shared].currentVideo != nil;
    BOOL visible = hasVideo && [[BKDriveGuard shared] confirmedStationary];
    if (visible != _lastVisible) {
        _lastVisible = visible;
        BKLogf(@"Fahrerdisplay: Bild %@", visible ? @"an (Stillstand bestätigt)" : @"aus");
    }
    _surface.renderer = [BKLibrary shared].renderer;
    _surface.fill = [BKLibrary shared].videoFill;
    _surface.player = visible ? [BKPlayer shared].player : nil;
    _surface.hidden = !visible;
    _label.hidden = visible || !hasVideo;
}

@end

@implementation BKClusterSceneDelegate {
    CPInstrumentClusterController *_controller;
    UIWindow *_window;
}

- (void)templateApplicationInstrumentClusterScene:(CPTemplateApplicationInstrumentClusterScene *)scene
           didConnectInstrumentClusterController:(CPInstrumentClusterController *)controller {
    BKLogf(@"Fahrerdisplay-Szene verbunden");
    _controller = controller;
    controller.delegate = self;
    controller.inactiveDescriptionVariants = @[@"Bordkino"];
    [[BKDriveGuard shared] start];
}

- (void)templateApplicationInstrumentClusterScene:(CPTemplateApplicationInstrumentClusterScene *)scene
        didDisconnectInstrumentClusterController:(CPInstrumentClusterController *)controller {
    BKLogf(@"Fahrerdisplay-Szene getrennt");
    controller.delegate = nil;
    _controller = nil;
    _window = nil;
}

- (void)contentStyleDidChange:(UIUserInterfaceStyle)contentStyle {
}

- (void)instrumentClusterControllerDidConnectWindow:(UIWindow *)window {
    BKLogf(@"Fahrerdisplay-Fenster: %.0f×%.0f pt @%.0fx", window.bounds.size.width, window.bounds.size.height, window.screen.scale);
    _window = window;
    window.rootViewController = [BKClusterViewController new];
}

- (void)instrumentClusterControllerDidDisconnectWindow:(UIWindow *)window {
    BKLogf(@"Fahrerdisplay-Fenster getrennt");
    window.rootViewController = nil;
    _window = nil;
}

- (void)instrumentClusterControllerDidZoomIn:(CPInstrumentClusterController *)controller {}
- (void)instrumentClusterControllerDidZoomOut:(CPInstrumentClusterController *)controller {}

@end
