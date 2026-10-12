#import "BKPlayerViewController.h"
#import "BKVideoViewController.h"
#import "BKPlayer.h"
#import "BKLibrary.h"
#import "BKYouTube.h"
#import "BKLog.h"

static NSString *BKFormatTime(NSTimeInterval t) {
    NSInteger s = (NSInteger)MAX(0, t);
    return s >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(s / 3600), (long)(s % 3600 / 60), (long)(s % 60)]
                     : [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

@implementation BKPlayerViewController {
    BKVideoViewController *_video;
    UIView *_controls;
    UILabel *_titleLabel;
    UILabel *_timeLabel;
    UISlider *_slider;
    UIButton *_playButton;
    UIButton *_favoriteButton;
    UIButton *_rendererButton;
    UIButton *_retryButton;
    NSTimer *_clock;
    NSTimer *_hideTimer;
    BOOL _scrubbing;
}

- (CGFloat)iconSize { return self.carStyle ? 40 : 28; }

- (UIButton *)buttonWithSymbol:(NSString *)name action:(SEL)action label:(NSString *)label {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:[self iconSize] weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:name withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    b.accessibilityLabel = label;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintGreaterThanOrEqualToConstant:self.carStyle ? 72 : 52].active = YES;
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:self.carStyle ? 72 : 52].active = YES;
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _video = [BKVideoViewController new];
    [self addChildViewController:_video];
    _video.view.frame = self.view.bounds;
    _video.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_video.view];
    [_video didMoveToParentViewController:self];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    [self.view addGestureRecognizer:tap];

    _controls = [UIView new];
    _controls.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _controls.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_controls];

    UIButton *close = [self buttonWithSymbol:@"xmark" action:@selector(close) label:@"Schließen"];
    _favoriteButton = [self buttonWithSymbol:@"star" action:@selector(toggleFavorite) label:@"Merken"];
    UIButton *channel = [self buttonWithSymbol:@"person.crop.circle.badge.plus" action:@selector(followChannel) label:@"Kanal merken"];
    _titleLabel = [UILabel new];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.numberOfLines = 2;
    _titleLabel.font = [UIFont systemFontOfSize:self.carStyle ? 24 : 17 weight:UIFontWeightSemibold];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[close, _titleLabel, channel, _favoriteButton]];
    top.spacing = 12;
    top.alignment = UIStackViewAlignmentCenter;

    UIButton *back = [self buttonWithSymbol:@"gobackward.10" action:@selector(back10) label:@"10 Sekunden zurück"];
    _playButton = [self buttonWithSymbol:@"pause.fill" action:@selector(playPause) label:@"Wiedergabe/Pause"];
    UIButton *fwd = [self buttonWithSymbol:@"goforward.30" action:@selector(forward30) label:@"30 Sekunden vor"];
    _retryButton = [self buttonWithSymbol:@"arrow.clockwise" action:@selector(retry) label:@"Nochmal versuchen"];
    UIStackView *transport = [[UIStackView alloc] initWithArrangedSubviews:@[back, _playButton, fwd, _retryButton]];
    transport.spacing = self.carStyle ? 40 : 28;
    transport.alignment = UIStackViewAlignmentCenter;

    _slider = [UISlider new];
    _slider.minimumTrackTintColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    [_slider addTarget:self action:@selector(scrubStart) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _timeLabel = [UILabel new];
    _timeLabel.textColor = UIColor.whiteColor;
    _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:self.carStyle ? 20 : 14 weight:UIFontWeightMedium];
    [_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _rendererButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _rendererButton.titleLabel.font = [UIFont systemFontOfSize:self.carStyle ? 18 : 13 weight:UIFontWeightBold];
    _rendererButton.tintColor = UIColor.whiteColor;
    _rendererButton.accessibilityLabel = @"Renderer wechseln";
    [_rendererButton addTarget:self action:@selector(switchRenderer) forControlEvents:UIControlEventTouchUpInside];
    [_rendererButton.widthAnchor constraintGreaterThanOrEqualToConstant:self.carStyle ? 64 : 44].active = YES;
    UIStackView *progress = [[UIStackView alloc] initWithArrangedSubviews:@[_slider, _timeLabel, _rendererButton]];
    progress.spacing = 12;
    progress.alignment = UIStackViewAlignmentCenter;

    for (UIView *v in @[top, transport, progress]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [_controls addSubview:v];
    }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    CGFloat pad = self.carStyle ? 20 : 12;
    [NSLayoutConstraint activateConstraints:@[
        [_controls.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_controls.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [top.topAnchor constraintEqualToAnchor:safe.topAnchor constant:pad],
        [top.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [top.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],
        [transport.centerXAnchor constraintEqualToAnchor:_controls.centerXAnchor],
        [transport.centerYAnchor constraintEqualToAnchor:_controls.centerYAnchor],
        [progress.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad * 1.5],
        [progress.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],
        [progress.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-pad],
    ]];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refresh) name:BKPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:BKLibraryDidChangeNotification object:nil];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak BKPlayerViewController *weakSelf = self;
    _clock = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf updateTime]; }];
    [self showControls];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_clock invalidate];
    _clock = nil;
    [_hideTimer invalidate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

#pragma mark Refresh

- (void)refresh {
    BKPlayer *player = [BKPlayer shared];
    BKVideo *video = player.currentVideo;
    _titleLabel.text = video.title;
    BOOL playing = player.state == BKPlayerStatePlaying || player.state == BKPlayerStateLoading;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:[self iconSize] * 1.3 weight:UIImageSymbolWeightBold];
    [_playButton setImage:[UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    _retryButton.hidden = player.state != BKPlayerStateFailed;
    BOOL fav = video && [[BKLibrary shared] isFavorite:video];
    UIImageSymbolConfiguration *small = [UIImageSymbolConfiguration configurationWithPointSize:[self iconSize] weight:UIImageSymbolWeightSemibold];
    [_favoriteButton setImage:[UIImage systemImageNamed:fav ? @"star.fill" : @"star" withConfiguration:small] forState:UIControlStateNormal];
    _favoriteButton.tintColor = fav ? [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1] : UIColor.whiteColor;
    [_rendererButton setTitle:[BKLibrary shared].renderer == BKRendererPump ? @"B" : @"A" forState:UIControlStateNormal];
    if (player.state == BKPlayerStateFailed || player.state == BKPlayerStatePaused) [self showControls];
    [self updateTime];
}

- (void)updateTime {
    if (_scrubbing) return;
    BKPlayer *player = [BKPlayer shared];
    NSTimeInterval t = [player currentTime], d = [player duration];
    BOOL live = player.currentVideo.isLive || d <= 0;
    _slider.hidden = live;
    if (!live) {
        _slider.maximumValue = d;
        _slider.value = t;
    }
    _timeLabel.text = live ? (player.currentVideo.isLive ? @"LIVE" : BKFormatTime(t)) : [NSString stringWithFormat:@"%@ / %@", BKFormatTime(t), BKFormatTime(d)];
}

#pragma mark Controls visibility

- (void)toggleControls {
    if (_controls.alpha > 0.5) [self hideControls];
    else [self showControls];
}

- (void)showControls {
    [UIView animateWithDuration:0.2 animations:^{ self->_controls.alpha = 1; }];
    [self scheduleHide];
}

- (void)hideControls {
    if ([BKPlayer shared].state != BKPlayerStatePlaying) return;
    [UIView animateWithDuration:0.3 animations:^{ self->_controls.alpha = 0; }];
}

- (void)scheduleHide {
    [_hideTimer invalidate];
    __weak BKPlayerViewController *weakSelf = self;
    _hideTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(NSTimer *t) { [weakSelf hideControls]; }];
}

#pragma mark Actions

- (void)close {
    [[BKPlayer shared] stop];
    if (self.onClose) self.onClose();
}

- (void)playPause { [[BKPlayer shared] togglePlayPause]; [self scheduleHide]; }
- (void)back10 { [[BKPlayer shared] seekBy:-10]; [self scheduleHide]; }
- (void)forward30 { [[BKPlayer shared] seekBy:30]; [self scheduleHide]; }
- (void)retry { [[BKPlayer shared] retry]; }

- (void)toggleFavorite {
    BKVideo *video = [BKPlayer shared].currentVideo;
    if (video) [[BKLibrary shared] toggleFavorite:video];
    [self scheduleHide];
}

- (void)followChannel {
    BKVideo *video = [BKPlayer shared].currentVideo;
    if (!video.channelId.length) return;
    BKChannel *channel = [BKChannel channelWithDictionary:@{ @"channelId": video.channelId, @"title": video.channel ?: @"" }];
    [[BKLibrary shared] addChannel:channel];
    BKLogf(@"Kanal gemerkt: %@", channel.title);
    _titleLabel.text = [NSString stringWithFormat:@"Kanal „%@“ gemerkt", channel.title];
    [self scheduleHide];
}

- (void)switchRenderer {
    BKLibrary *library = [BKLibrary shared];
    library.renderer = library.renderer == BKRendererPump ? BKRendererLayer : BKRendererPump;
    [self scheduleHide];
}

- (void)scrubStart {
    _scrubbing = YES;
    [_hideTimer invalidate];
}

- (void)scrubEnd {
    _scrubbing = NO;
    [[BKPlayer shared] seekTo:_slider.value];
    [self scheduleHide];
}

@end
