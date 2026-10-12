#import "BKVideoListViewController.h"
#import "BKPlayer.h"
#import "BKPlayerViewController.h"
#import "BKCarState.h"
#import "BKLibrary.h"
#import "BKImageLoader.h"

void BKPresentPhonePlayer(UIViewController *from) {
    UIViewController *top = from.view.window.rootViewController ?: from;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:BKPlayerViewController.class]) return;
    BKPlayerViewController *player = [BKPlayerViewController new];
    player.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak BKPlayerViewController *weakPlayer = player;
    player.onClose = ^{ [weakPlayer dismissViewControllerAnimated:YES completion:nil]; };
    [top presentViewController:player animated:YES completion:nil];
}

void BKToast(UIViewController *from, NSString *message) {
    UIView *host = from.view.window ?: from.view;
    UILabel *label = [UILabel new];
    label.text = [NSString stringWithFormat:@"  %@  ", message];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.blackColor;
    label.backgroundColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:0.95];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.layer.cornerRadius = 12;
    label.clipsToBounds = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [label.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-70],
        [label.widthAnchor constraintLessThanOrEqualToAnchor:host.widthAnchor constant:-40],
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    [UIView animateWithDuration:0.3 delay:2.2 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL f) { [label removeFromSuperview]; }];
}

void BKPlayFromPhone(UIViewController *from, BKVideo *video) {
    [[BKPlayer shared] playVideo:video];
    if ([BKCarState shared].connected) BKToast(from, @"Läuft auf dem CarPlay-Display");
    else BKPresentPhonePlayer(from);
}

void BKPlayInputFromPhone(UIViewController *from, NSString *input) {
    [[BKPlayer shared] playInput:input];
    if ([BKCarState shared].connected) BKToast(from, @"Läuft auf dem CarPlay-Display");
    else BKPresentPhonePlayer(from);
}

@interface BKVideoCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *detail;
@end

@implementation BKVideoCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 6;
        _thumb.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        _title = [UILabel new];
        _title.numberOfLines = 2;
        _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _detail = [UILabel new];
        _detail.numberOfLines = 2;
        _detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _detail.textColor = UIColor.secondaryLabelColor;
        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _detail]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 4;
        for (UIView *v in @[_thumb, texts]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_thumb.topAnchor constraintEqualToAnchor:m.topAnchor],
            [_thumb.bottomAnchor constraintLessThanOrEqualToAnchor:m.bottomAnchor],
            [_thumb.widthAnchor constraintEqualToConstant:128],
            [_thumb.heightAnchor constraintEqualToConstant:72],
            [texts.leadingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:12],
            [texts.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [texts.centerYAnchor constraintEqualToAnchor:_thumb.centerYAnchor],
        ]];
    }
    return self;
}
@end

@implementation BKVideoListViewController {
    NSMutableArray<BKVideo *> *_items;
    NSString *_next;
    BOOL _loading;
    NSUInteger _generation;
    NSString *_error;
}

- (instancetype)initWithTitle:(NSString *)title loader:(BKVideoListLoader)loader {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = title;
        _loader = [loader copy];
        _items = [NSMutableArray new];
        _emptyText = @"Keine Videos.";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:BKVideoCell.class forCellReuseIdentifier:@"video"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:BKLibraryDidChangeNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)libraryChanged {
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)setLoader:(BKVideoListLoader)loader {
    _loader = [loader copy];
}

- (void)reload {
    _generation++;
    [_items removeAllObjects];
    _next = nil;
    _error = nil;
    _loading = NO;
    [self.tableView reloadData];
    [self loadPage:nil];
}

- (void)loadPage:(NSString *)continuation {
    if (!self.loader || _loading) {
        [self.refreshControl endRefreshing];
        [self updateBackground];
        return;
    }
    _loading = YES;
    [self updateBackground];
    NSUInteger generation = _generation;
    __weak BKVideoListViewController *weakSelf = self;
    self.loader(continuation, ^(NSArray<BKVideo *> *items, NSString *next, NSError *error) {
        BKVideoListViewController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_generation) return;
        strongSelf->_loading = NO;
        [strongSelf.refreshControl endRefreshing];
        if (error) {
            strongSelf->_error = error.localizedDescription;
        } else {
            NSMutableSet *known = [NSMutableSet setWithArray:[strongSelf->_items valueForKey:@"identifier"]];
            for (BKVideo *v in items) {
                if (![known containsObject:v.identifier]) {
                    [known addObject:v.identifier];
                    [strongSelf->_items addObject:v];
                }
            }
            strongSelf->_next = items.count ? next : nil;
        }
        [strongSelf.tableView reloadData];
        [strongSelf updateBackground];
    });
}

- (void)updateBackground {
    if (_items.count) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [UILabel new];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.textColor = UIColor.secondaryLabelColor;
    label.text = _loading ? @"Lädt …" : (_error ?: self.emptyText);
    self.tableView.backgroundView = label;
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BKVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"video" forIndexPath:indexPath];
    BKVideo *v = _items[indexPath.row];
    BOOL fav = [[BKLibrary shared] isFavorite:v];
    cell.title.text = fav ? [@"★ " stringByAppendingString:v.title] : v.title;
    NSMutableArray *parts = [NSMutableArray new];
    if (v.channel.length) [parts addObject:v.channel];
    if (v.durationText.length) [parts addObject:v.durationText];
    if (v.subtitle.length) [parts addObject:v.subtitle];
    cell.detail.text = [parts componentsJoinedByString:@" · "];
    [BKImageLoader loadURL:v.thumbnailURL into:cell.thumb];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_next && !_loading && indexPath.row >= (NSInteger)_items.count - 3) [self loadPage:_next];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BKPlayFromPhone(self, _items[indexPath.row]);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    BKVideo *v = _items[indexPath.row];
    BOOL fav = [[BKLibrary shared] isFavorite:v];
    UIContextualAction *favorite = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:fav ? @"Entfernen" : @"Merken" handler:^(UIContextualAction *a, UIView *s, void (^done)(BOOL)) {
            [[BKLibrary shared] toggleFavorite:v];
            done(YES);
        }];
    favorite.backgroundColor = fav ? UIColor.systemRedColor : [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    NSMutableArray *actions = [NSMutableArray arrayWithObject:favorite];
    if (v.channelId.length) {
        UIContextualAction *channel = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
            title:@"Kanal merken" handler:^(UIContextualAction *a, UIView *s, void (^done)(BOOL)) {
                [[BKLibrary shared] addChannel:[BKChannel channelWithDictionary:@{ @"channelId": v.channelId, @"title": v.channel ?: @"" }]];
                BKToast(self, [NSString stringWithFormat:@"Kanal „%@“ gemerkt", v.channel]);
                done(YES);
            }];
        channel.backgroundColor = UIColor.systemIndigoColor;
        [actions addObject:channel];
    }
    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

@end
