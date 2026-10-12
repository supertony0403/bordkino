#import "BKPhoneSceneDelegate.h"

@implementation BKPhoneSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    UIViewController *vc = [UIViewController new];
    UILabel *label = [UILabel new];
    label.text = @"Bordkino";
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = vc.view.bounds;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:label];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
}

@end
