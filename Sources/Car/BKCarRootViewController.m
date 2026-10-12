#import "BKCarRootViewController.h"
#import "BKCarGridViewController.h"
#import "BKCarSearchViewController.h"
#import "BKCarChannelsViewController.h"
#import "BKDiagnosticsViewController.h"
#import "BKPlayerViewController.h"
#import "BKPlayer.h"
#import "BKLibrary.h"

UIButton *BKCarButton(NSString *symbol, NSString *title, CGFloat pointSize) {
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold]];
    config.imagePlacement = NSDirectionalRectEdgeTop;
    config.imagePadding = 4;
    config.baseForegroundColor = UIColor.whiteColor;
    if (title.length) {
        config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] }];
    }
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.accessibilityLabel = title;
    return button;
}

@implementation BKCarRootViewController {
    UIStackView *_sidebar;
    NSArray<UIButton *> *_tabs;
    UIView *_content;
    NSArray<UIViewController *> *_sections;
    UIViewController *_current;
    BKPlayerViewController *_player;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:1];

    BKCarGridViewController *start = [[BKCarGridViewController alloc] initWithLoader:^(NSString *continuation, BKVideoListCompletion done) {
        done([BKLibrary shared].history, nil, nil);
    } emptyText:@"Noch nichts angesehen.\nTippe links auf „Suche“."];
    start.title = @"Zuletzt gesehen";
    start.reloadsOnLibraryChange = YES;
    BKCarGridViewController *favorites = [[BKCarGridViewController alloc] initWithLoader:^(NSString *continuation, BKVideoListCompletion done) {
        done([BKLibrary shared].favorites, nil, nil);
    } emptyText:@"Noch nichts gemerkt.\nIm Player auf ☆ tippen."];
    favorites.title = @"Merkliste";
    favorites.reloadsOnLibraryChange = YES;

    _sections = @[
        [self navigationWith:start],
        [self navigationWith:[BKCarSearchViewController new]],
        [self navigationWith:favorites],
        [self navigationWith:[BKCarChannelsViewController new]],
        [self navigationWith:[BKDiagnosticsViewController new]],
    ];
    NSArray *symbols = @[@"house.fill", @"magnifyingglass", @"star.fill", @"person.2.fill", @"wrench.and.screwdriver.fill"];
    NSArray *titles = @[@"Start", @"Suche", @"Merkliste", @"Kanäle", @"Diagnose"];
    NSMutableArray *tabs = [NSMutableArray new];
    for (NSUInteger i = 0; i < symbols.count; i++) {
        UIButton *b = BKCarButton(symbols[i], titles[i], 26);
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
        [tabs addObject:b];
    }
    _tabs = tabs;
    _sidebar = [[UIStackView alloc] initWithArrangedSubviews:tabs];
    _sidebar.axis = UILayoutConstraintAxisVertical;
    _sidebar.distribution = UIStackViewDistributionFillEqually;
    _sidebar.spacing = 4;
    _sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_sidebar];

    _content = [UIView new];
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_content];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_sidebar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:4],
        [_sidebar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:4],
        [_sidebar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4],
        [_sidebar.widthAnchor constraintEqualToConstant:92],
        [_content.leadingAnchor constraintEqualToAnchor:_sidebar.trailingAnchor constant:4],
        [_content.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_content.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_content.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    [self selectSection:0];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoStarted) name:BKPlayerDidStartVideoNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Something may already be playing (started on the phone before connecting).
    if ([BKPlayer shared].currentVideo) [self showPlayer];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UINavigationController *)navigationWith:(UIViewController *)root {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.prefersLargeTitles = NO;
    nav.navigationBar.titleTextAttributes = @{ NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightBold] };
    return nav;
}

- (void)tabTapped:(UIButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (_sections[index] == _current) {
        [(UINavigationController *)_current popToRootViewControllerAnimated:YES];
        return;
    }
    [self selectSection:index];
}

- (void)selectSection:(NSUInteger)index {
    if (_current) {
        [_current willMoveToParentViewController:nil];
        [_current.view removeFromSuperview];
        [_current removeFromParentViewController];
    }
    _current = _sections[index];
    [self addChildViewController:_current];
    _current.view.frame = _content.bounds;
    _current.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_content addSubview:_current.view];
    [_current didMoveToParentViewController:self];
    for (UIButton *b in _tabs) {
        UIButtonConfiguration *config = b.configuration;
        config.baseForegroundColor = (NSUInteger)b.tag == index ? self.view.tintColor : UIColor.lightGrayColor;
        b.configuration = config;
    }
}

- (void)videoStarted {
    [self showPlayer];
}

- (void)showPlayer {
    if (_player) return;
    _player = [BKPlayerViewController new];
    _player.carStyle = YES;
    __weak BKCarRootViewController *weakSelf = self;
    _player.onClose = ^{ [weakSelf hidePlayer]; };
    [self addChildViewController:_player];
    _player.view.frame = self.view.bounds;
    _player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _player.view.alpha = 0;
    [self.view addSubview:_player.view];
    [_player didMoveToParentViewController:self];
    [UIView animateWithDuration:0.25 animations:^{ self->_player.view.alpha = 1; }];
}

- (void)hidePlayer {
    BKPlayerViewController *player = _player;
    _player = nil;
    [player willMoveToParentViewController:nil];
    [UIView animateWithDuration:0.2 animations:^{ player.view.alpha = 0; } completion:^(BOOL finished) {
        [player.view removeFromSuperview];
        [player removeFromParentViewController];
    }];
}

@end
