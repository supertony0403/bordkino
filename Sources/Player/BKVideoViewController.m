#import "BKVideoViewController.h"
#import "BKPlayer.h"
#import "BKDriveGuard.h"
#import "BKLibrary.h"

@implementation BKVideoViewController {
    BKVideoSurface *_surface;
    UIView *_driveCover;
    UIActivityIndicatorView *_spinner;
    UILabel *_statusLabel;
}

- (BKVideoSurface *)surface {
    [self loadViewIfNeeded];
    return _surface;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _surface = [[BKVideoSurface alloc] initWithFrame:self.view.bounds];
    _surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_surface];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = UIColor.whiteColor;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];

    _statusLabel = [UILabel new];
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    _driveCover = [UIView new];
    _driveCover.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    _driveCover.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *car = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"car.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:56 weight:UIImageSymbolWeightSemibold]]];
    car.tintColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    UILabel *coverText = [UILabel new];
    coverText.text = @"Fahrt erkannt – Bild pausiert.\nDer Ton läuft weiter.";
    coverText.numberOfLines = 0;
    coverText.textAlignment = NSTextAlignmentCenter;
    coverText.textColor = UIColor.whiteColor;
    coverText.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    UIStackView *coverStack = [[UIStackView alloc] initWithArrangedSubviews:@[car, coverText]];
    coverStack.axis = UILayoutConstraintAxisVertical;
    coverStack.alignment = UIStackViewAlignmentCenter;
    coverStack.spacing = 16;
    coverStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_driveCover addSubview:coverStack];
    [self.view addSubview:_driveCover];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [_statusLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:16],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:32],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-32],
        [_driveCover.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_driveCover.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_driveCover.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_driveCover.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [coverStack.centerXAnchor constraintEqualToAnchor:_driveCover.centerXAnchor],
        [coverStack.centerYAnchor constraintEqualToAnchor:_driveCover.centerYAnchor],
        [coverStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_driveCover.leadingAnchor constant:24],
    ]];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refresh) name:BKPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:BKDriveGuardDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:BKLibraryDidChangeNotification object:nil];
    _surface.player = [BKPlayer shared].player;
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIdleText:(NSString *)idleText {
    _idleText = [idleText copy];
    if (self.isViewLoaded) [self refresh];
}

- (void)refresh {
    BKPlayer *player = [BKPlayer shared];
    BKLibrary *library = [BKLibrary shared];
    _surface.renderer = library.renderer;
    _surface.fill = library.videoFill;
    _driveCover.hidden = !(library.driveLockEnabled && [BKDriveGuard shared].driving && player.currentVideo != nil);

    switch (player.state) {
        case BKPlayerStateLoading:
            [_spinner startAnimating];
            _statusLabel.text = player.currentVideo.title.length ? player.currentVideo.title : @"Lädt …";
            break;
        case BKPlayerStateFailed:
            [_spinner stopAnimating];
            _statusLabel.text = player.errorMessage ?: @"Wiedergabe fehlgeschlagen.";
            break;
        case BKPlayerStateIdle:
            [_spinner stopAnimating];
            _statusLabel.text = self.idleText;
            break;
        default:
            [_spinner stopAnimating];
            _statusLabel.text = nil;
            break;
    }
}

@end
