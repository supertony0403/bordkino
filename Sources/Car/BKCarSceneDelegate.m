#import "BKCarSceneDelegate.h"
#import "BKCarRootViewController.h"
#import "BKCarState.h"
#import "BKDriveGuard.h"
#import "BKLibrary.h"
#import "BKLog.h"

@implementation BKCarSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIScreen *screen = windowScene.screen;
    BKLogf(@"Stark-Szene verbunden: %.0f×%.0f pt @%.0fx", screen.bounds.size.width, screen.bounds.size.height, screen.scale);
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.tintColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    self.window.rootViewController = [BKCarRootViewController new];
    [self.window makeKeyAndVisible];
    [BKCarState shared].carWindow = self.window;
    [BKCarState shared].connected = YES;
    [[BKDriveGuard shared] start];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [[BKLibrary shared] reload];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    BKLogf(@"Stark-Szene getrennt");
    [BKCarState shared].connected = NO;
    [[BKDriveGuard shared] stop];
    self.window = nil;
}

@end
