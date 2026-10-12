#import "BKTemplateSceneDelegate.h"
#import "BKVideoViewController.h"
#import "BKPlayer.h"
#import "BKLibrary.h"
#import "BKYouTube.h"
#import "BKImageLoader.h"
#import "BKCarState.h"
#import "BKDriveGuard.h"
#import "BKLog.h"

static const NSUInteger kMaxSearchResults = 12;
static const NSTimeInterval kSearchDebounce = 0.6;

/// Navigation-app variant: CarPlay templates for input, video in the CPWindow.
@interface BKTemplateSceneDelegate () <CPMapTemplateDelegate, CPSearchTemplateDelegate>
@end

@implementation BKTemplateSceneDelegate {
    CPInterfaceController *_interface;
    CPWindow *_window;
    CPMapTemplate *_map;
    CPMapButton *_playButton;
    NSUInteger _searchGeneration;
}

#pragma mark Scene lifecycle

- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene
    didConnectInterfaceController:(CPInterfaceController *)interfaceController
                         toWindow:(CPWindow *)window {
    BKLogf(@"Navi-Szene verbunden: %.0f×%.0f pt @%.0fx", window.bounds.size.width, window.bounds.size.height, window.screen.scale);
    _interface = interfaceController;
    _window = window;
    BKVideoViewController *video = [BKVideoViewController new];
    video.idleText = @"Bordkino Navi\nOben „Suche“ oder „Listen“ antippen.";
    window.rootViewController = video;

    _map = [CPMapTemplate new];
    _map.mapDelegate = self;
    _map.automaticallyHidesNavigationBar = NO;
    _map.mapButtons = [self makeMapButtons];
    __weak BKTemplateSceneDelegate *weakSelf = self;
    _map.leadingNavigationBarButtons = @[[[CPBarButton alloc] initWithTitle:@"Suche" handler:^(CPBarButton *b) { [weakSelf showSearch]; }]];
    _map.trailingNavigationBarButtons = @[[[CPBarButton alloc] initWithTitle:@"Listen" handler:^(CPBarButton *b) { [weakSelf showLists]; }]];
    [interfaceController setRootTemplate:_map animated:NO completion:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged) name:BKPlayerStateDidChangeNotification object:nil];
    [BKCarState shared].carWindow = window;
    [BKCarState shared].connected = YES;
    [[BKDriveGuard shared] start];
    [self playerChanged];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)scene
 didDisconnectInterfaceController:(CPInterfaceController *)interfaceController
                       fromWindow:(CPWindow *)window {
    BKLogf(@"Navi-Szene getrennt");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [BKCarState shared].connected = NO;
    [[BKDriveGuard shared] stop];
    _interface = nil;
    _window = nil;
    _map = nil;
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [[BKLibrary shared] reload];
}

#pragma mark Map buttons

- (UIImage *)symbol:(NSString *)name {
    return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold]];
}

- (NSArray<CPMapButton *> *)makeMapButtons {
    CPMapButton *back = [[CPMapButton alloc] initWithHandler:^(CPMapButton *b) { [[BKPlayer shared] seekBy:-10]; }];
    back.image = [self symbol:@"gobackward.10"];
    _playButton = [[CPMapButton alloc] initWithHandler:^(CPMapButton *b) { [[BKPlayer shared] togglePlayPause]; }];
    _playButton.image = [self symbol:@"play.fill"];
    CPMapButton *forward = [[CPMapButton alloc] initWithHandler:^(CPMapButton *b) { [[BKPlayer shared] seekBy:30]; }];
    forward.image = [self symbol:@"goforward.30"];
    CPMapButton *stop = [[CPMapButton alloc] initWithHandler:^(CPMapButton *b) { [[BKPlayer shared] stop]; }];
    stop.image = [self symbol:@"stop.fill"];
    return @[back, _playButton, forward, stop];
}

- (void)playerChanged {
    BKPlayerState state = [BKPlayer shared].state;
    BOOL playing = state == BKPlayerStatePlaying || state == BKPlayerStateLoading;
    _playButton.image = [self symbol:playing ? @"pause.fill" : @"play.fill"];
    BOOL active = [BKPlayer shared].currentVideo != nil;
    for (CPMapButton *button in _map.mapButtons) button.hidden = !active;
}

#pragma mark List items

- (CPListItem *)itemForVideo:(BKVideo *)video {
    NSMutableArray *parts = [NSMutableArray new];
    if (video.channel.length) [parts addObject:video.channel];
    if (video.durationText.length) [parts addObject:video.durationText];
    CPListItem *item = [[CPListItem alloc] initWithText:video.title detailText:[parts componentsJoinedByString:@" · "]
                                                  image:[UIImage systemImageNamed:@"play.rectangle.fill"]];
    item.userInfo = video;
    __weak CPListItem *weakItem = item;
    [BKImageLoader loadURL:video.thumbnailURL completion:^(UIImage *image) {
        if (image) [weakItem setImage:image];
    }];
    __weak BKTemplateSceneDelegate *weakSelf = self;
    item.handler = ^(id<CPSelectableListItem> selected, dispatch_block_t completion) {
        [weakSelf play:video];
        completion();
    };
    return item;
}

- (NSArray<CPListItem *> *)itemsForVideos:(NSArray<BKVideo *> *)videos limit:(NSUInteger)limit {
    NSMutableArray *items = [NSMutableArray new];
    for (BKVideo *video in videos) {
        if (items.count >= limit) break;
        [items addObject:[self itemForVideo:video]];
    }
    return items;
}

- (void)play:(BKVideo *)video {
    [[BKPlayer shared] playVideo:video];
    [_interface popToRootTemplateAnimated:YES completion:nil];
}

#pragma mark Lists

- (NSUInteger)listLimit {
    return MAX((NSUInteger)6, MIN((NSUInteger)CPListTemplate.maximumItemCount, (NSUInteger)24));
}

- (void)showLists {
    BKLibrary *library = [BKLibrary shared];
    NSUInteger limit = [self listLimit] / 2;
    NSMutableArray<CPListSection *> *sections = [NSMutableArray new];
    if (library.favorites.count) {
        [sections addObject:[[CPListSection alloc] initWithItems:[self itemsForVideos:library.favorites limit:limit] header:@"Merkliste" sectionIndexTitle:nil]];
    }
    if (library.history.count) {
        [sections addObject:[[CPListSection alloc] initWithItems:[self itemsForVideos:library.history limit:limit] header:@"Zuletzt gesehen" sectionIndexTitle:nil]];
    }
    NSMutableArray *channelItems = [NSMutableArray new];
    __weak BKTemplateSceneDelegate *weakSelf = self;
    for (BKChannel *channel in library.channels) {
        CPListItem *item = [[CPListItem alloc] initWithText:channel.title detailText:nil image:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        item.accessoryType = CPListItemAccessoryTypeDisclosureIndicator;
        item.handler = ^(id<CPSelectableListItem> selected, dispatch_block_t completion) {
            [weakSelf showChannel:channel completion:completion];
        };
        [channelItems addObject:item];
    }
    if (channelItems.count) {
        [sections addObject:[[CPListSection alloc] initWithItems:channelItems header:@"Kanäle" sectionIndexTitle:nil]];
    }
    CPListTemplate *list = [[CPListTemplate alloc] initWithTitle:@"Bordkino" sections:sections];
    list.emptyViewTitleVariants = @[@"Noch leer"];
    list.emptyViewSubtitleVariants = @[@"Suche ein Video oder merke es dir am Handy."];
    [_interface pushTemplate:list animated:YES completion:nil];
}

- (void)showChannel:(BKChannel *)channel completion:(dispatch_block_t)completion {
    __weak BKTemplateSceneDelegate *weakSelf = self;
    [[BKYouTube shared] channelFeed:channel.channelId completion:^(NSArray<BKVideo *> *videos, NSError *error) {
        BKTemplateSceneDelegate *strongSelf = weakSelf;
        completion();
        if (!strongSelf) return;
        NSArray *items = [strongSelf itemsForVideos:videos limit:[strongSelf listLimit]];
        CPListTemplate *list = [[CPListTemplate alloc] initWithTitle:channel.title
                                                           sections:@[[[CPListSection alloc] initWithItems:items]]];
        list.emptyViewTitleVariants = @[error ? @"Fehler" : @"Keine Videos"];
        if (error) list.emptyViewSubtitleVariants = @[error.localizedDescription];
        [strongSelf->_interface pushTemplate:list animated:YES completion:nil];
    }];
}

#pragma mark Search

- (void)showSearch {
    CPSearchTemplate *search = [CPSearchTemplate new];
    search.delegate = self;
    [_interface pushTemplate:search animated:YES completion:nil];
}

- (void)searchTemplate:(CPSearchTemplate *)searchTemplate updatedSearchText:(NSString *)searchText
     completionHandler:(void (^)(NSArray<CPListItem *> *))completionHandler {
    NSUInteger generation = ++_searchGeneration;
    NSString *query = [searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (query.length < 3) {
        completionHandler(@[]);
        return;
    }
    __weak BKTemplateSceneDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSearchDebounce * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BKTemplateSceneDelegate *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_searchGeneration) {
            completionHandler(@[]);   // superseded by newer typing
            return;
        }
        [[BKYouTube shared] search:query continuation:nil completion:^(NSArray<BKVideo *> *videos, NSString *next, NSError *error) {
            if (error) BKLogf(@"Navi-Suche: %@", error.localizedDescription);
            completionHandler([weakSelf itemsForVideos:videos limit:kMaxSearchResults] ?: @[]);
        }];
    });
}

- (void)searchTemplate:(CPSearchTemplate *)searchTemplate selectedResult:(CPListItem *)item completionHandler:(void (^)(void))completionHandler {
    if ([item.userInfo isKindOfClass:BKVideo.class]) [self play:item.userInfo];
    completionHandler();
}

- (void)searchTemplateSearchButtonPressed:(CPSearchTemplate *)searchTemplate {
    // Results are already shown while typing.
}

@end
