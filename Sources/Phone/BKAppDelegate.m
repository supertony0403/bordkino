#import "BKAppDelegate.h"
#import "BKScriptHost.h"
#import "BKLog.h"

@implementation BKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    BKLogf(@"%@ %@ startet auf iOS %@", [NSBundle mainBundle].bundleIdentifier, version, UIDevice.currentDevice.systemVersion);
    [BKScriptHost shared];   // loads the extractor early
    return YES;
}

/// Logs every scene role (diagnostics for the car) and tolerates a CarPlay role
/// name that differs from the one in Info.plist on newer iOS versions.
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSString *role = session.role;
    BKLogf(@"Neue Szene mit Rolle %@", role);
    NSDictionary *manifest = [NSBundle mainBundle].infoDictionary[@"UIApplicationSceneManifest"][@"UISceneConfigurations"];
    NSDictionary *entry = [manifest[role] isKindOfClass:NSArray.class] ? [manifest[role] firstObject] : nil;
    if (entry[@"UISceneConfigurationName"]) {
        return [[UISceneConfiguration alloc] initWithName:entry[@"UISceneConfigurationName"] sessionRole:role];
    }
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:nil sessionRole:role];
#if BK_VARIANT_STARK
    if ([role.lowercaseString containsString:@"car"]) {
        BKLogf(@"Unbekannte CarPlay-Rolle – hänge Stark-Delegate an");
        config.sceneClass = UIWindowScene.class;
        config.delegateClass = NSClassFromString(@"BKCarSceneDelegate");
    }
#endif
    return config;
}

@end
