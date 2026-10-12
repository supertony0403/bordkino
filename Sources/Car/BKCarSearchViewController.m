#import "BKCarSearchViewController.h"
#import "BKCarGridViewController.h"
#import "BKKeyboardView.h"
#import "BKYouTube.h"

@implementation BKCarSearchViewController {
    UILabel *_queryLabel;
    UIButton *_keyboardToggle;
    BKKeyboardView *_keyboard;
    BKCarGridViewController *_results;
    NSLayoutConstraint *_keyboardHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Suche";
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:1];

    _queryLabel = [UILabel new];
    _queryLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    _queryLabel.textColor = UIColor.whiteColor;
    _queryLabel.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    _queryLabel.layer.cornerRadius = 10;
    _queryLabel.clipsToBounds = YES;
    _queryLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _keyboardToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    [_keyboardToggle setImage:[UIImage systemImageNamed:@"keyboard" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28]] forState:UIControlStateNormal];
    _keyboardToggle.accessibilityLabel = @"Tastatur";
    [_keyboardToggle addTarget:self action:@selector(toggleKeyboard) forControlEvents:UIControlEventTouchUpInside];
    _keyboardToggle.translatesAutoresizingMaskIntoConstraints = NO;

    _results = [[BKCarGridViewController alloc] initWithLoader:nil emptyText:@"Tippe einen Suchbegriff."];
    [self addChildViewController:_results];
    _results.view.translatesAutoresizingMaskIntoConstraints = NO;

    _keyboard = [BKKeyboardView new];
    _keyboard.translatesAutoresizingMaskIntoConstraints = NO;
    __weak BKCarSearchViewController *weakSelf = self;
    _keyboard.onText = ^(NSString *text) { [weakSelf showQuery:text]; };
    _keyboard.onSubmit = ^(NSString *text) { [weakSelf search:text]; };

    for (UIView *v in @[_queryLabel, _keyboardToggle, _results.view, _keyboard]) [self.view addSubview:v];
    [_results didMoveToParentViewController:self];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    _keyboardHeight = [_keyboard.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.55];
    [NSLayoutConstraint activateConstraints:@[
        [_queryLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_queryLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_queryLabel.heightAnchor constraintEqualToConstant:52],
        [_keyboardToggle.leadingAnchor constraintEqualToAnchor:_queryLabel.trailingAnchor constant:8],
        [_keyboardToggle.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [_keyboardToggle.centerYAnchor constraintEqualToAnchor:_queryLabel.centerYAnchor],
        [_keyboardToggle.widthAnchor constraintEqualToConstant:64],
        [_keyboardToggle.heightAnchor constraintEqualToConstant:52],
        [_results.view.topAnchor constraintEqualToAnchor:_queryLabel.bottomAnchor constant:6],
        [_results.view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_results.view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_results.view.bottomAnchor constraintEqualToAnchor:_keyboard.topAnchor],
        [_keyboard.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_keyboard.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_keyboard.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        _keyboardHeight,
    ]];
    [self showQuery:@""];
}

- (void)showQuery:(NSString *)text {
    _queryLabel.text = [NSString stringWithFormat:@"  🔍 %@▏", text];
}

- (void)setKeyboardVisible:(BOOL)visible {
    _keyboardHeight.active = NO;
    _keyboardHeight = [_keyboard.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:visible ? 0.55 : 0.0];
    _keyboardHeight.active = YES;
    _keyboard.hidden = !visible;
    [UIView animateWithDuration:0.2 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)toggleKeyboard {
    [self setKeyboardVisible:_keyboard.hidden];
}

- (void)search:(NSString *)query {
    [self setKeyboardVisible:NO];
    _results.emptyText = [NSString stringWithFormat:@"Keine Treffer für „%@“.", query];
    _results.loader = ^(NSString *continuation, BKVideoListCompletion done) {
        [[BKYouTube shared] search:query continuation:continuation completion:done];
    };
    [_results reload];
}

@end
