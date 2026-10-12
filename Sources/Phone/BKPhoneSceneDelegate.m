#import "BKPhoneSceneDelegate.h"
#import "BKSearchViewController.h"
#import "BKLibraryViewController.h"
#import "BKChannelsViewController.h"
#import "BKSettingsViewController.h"
#import "BKVideoListViewController.h"
#import "BKLibrary.h"
#import "BKExtractorUpdater.h"
#import "BKLog.h"

UIColor *BKAccentColor(void) {
    return [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
}

@implementation BKPhoneSceneDelegate

- (UINavigationController *)tab:(UIViewController *)root title:(NSString *)title symbol:(NSString *)symbol {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:symbol] tag:0];
    return nav;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.tintColor = BKAccentColor();
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[
        [self tab:[BKSearchViewController new] title:@"Suche" symbol:@"magnifyingglass"],
        [self tab:[BKLibraryViewController new] title:@"Bibliothek" symbol:@"star"],
        [self tab:[BKChannelsViewController new] title:@"Kanäle" symbol:@"person.2"],
        [self tab:[BKSettingsViewController new] title:@"Einstellungen" symbol:@"gearshape"],
    ];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    if (connectionOptions.URLContexts.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleURLContexts:connectionOptions.URLContexts]; });
    }
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [[BKLibrary shared] reload];   // the other app variant may have changed it
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [BKExtractorUpdater checkForUpdateForce:NO completion:nil];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    [self handleURLContexts:URLContexts];
}

/// bordkino://play?v=VIDEO_ID  or  bordkino://play?url=<percent-encoded link>
- (void)handleURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
    NSURL *url = contexts.anyObject.URL;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (![components.host isEqualToString:@"play"]) return;
    NSString *input = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if (([item.name isEqualToString:@"v"] || [item.name isEqualToString:@"url"]) && item.value.length) input = item.value;
    }
    if (!input) return;
    BKLogf(@"Über URL-Schema: %@", input);
    UIViewController *root = self.window.rootViewController;
    BKPlayInputFromPhone(root, input);
}

@end
