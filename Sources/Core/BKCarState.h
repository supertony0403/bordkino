#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BKCarStateDidChangeNotification;

/// Whether a CarPlay scene of this app is currently connected.
@interface BKCarState : NSObject
+ (instancetype)shared;
@property (nonatomic) BOOL connected;
@property (nonatomic, weak, nullable) UIWindow *carWindow;
@end

NS_ASSUME_NONNULL_END
