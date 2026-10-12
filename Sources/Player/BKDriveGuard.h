#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BKDriveGuardDidChangeNotification;

/// Decides from GPS speed whether the car is moving.
/// Driving after > 10 km/h for 3 s, standing after < 3 km/h for 5 s.
@interface BKDriveGuard : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL driving;
@property (nonatomic, readonly) BOOL locationAvailable;
@property (nonatomic, readonly) double lastSpeedKmh;   // -1 when unknown
- (void)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
