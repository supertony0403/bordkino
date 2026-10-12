#import "BKDriveGuard.h"
#import <CoreLocation/CoreLocation.h>
#import "BKLog.h"

NSNotificationName const BKDriveGuardDidChangeNotification = @"BKDriveGuardDidChangeNotification";

static const double kDrivingKmh = 10;
static const double kStandingKmh = 3;
static const NSTimeInterval kDrivingAfter = 3;
static const NSTimeInterval kStandingAfter = 5;

@interface BKDriveGuard () <CLLocationManagerDelegate>
@property (nonatomic, readwrite) BOOL driving;
@property (nonatomic, readwrite) BOOL locationAvailable;
@property (nonatomic, readwrite) double lastSpeedKmh;
@end

@implementation BKDriveGuard {
    CLLocationManager *_manager;
    NSDate *_aboveSince;
    NSDate *_belowSince;
    BOOL _running;
}

+ (instancetype)shared {
    static BKDriveGuard *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKDriveGuard new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lastSpeedKmh = -1;
    }
    return self;
}

- (void)start {
    if (!_manager) {
        _manager = [CLLocationManager new];
        _manager.delegate = self;
        _manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        _manager.activityType = CLActivityTypeAutomotiveNavigation;
        _manager.pausesLocationUpdatesAutomatically = NO;
    }
    _running = YES;
    if (_manager.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
        [_manager requestWhenInUseAuthorization];
    }
    [self updateAvailability];
    [_manager startUpdatingLocation];
}

- (void)stop {
    _running = NO;
    [_manager stopUpdatingLocation];
    _aboveSince = _belowSince = nil;
    self.lastSpeedKmh = -1;
    [self setDrivingNotify:NO];
}

- (void)updateAvailability {
    CLAuthorizationStatus status = _manager.authorizationStatus;
    self.locationAvailable = status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways;
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    [self updateAvailability];
    BKLogf(@"Standortzugriff: %@", self.locationAvailable ? @"ja" : @"nein");
    if (self.locationAvailable && _running) [manager startUpdatingLocation];
    [[NSNotificationCenter defaultCenter] postNotificationName:BKDriveGuardDidChangeNotification object:self];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    BKLogf(@"Standortfehler: %@", error.localizedDescription);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (!location || location.speed < 0) return;   // invalid speed: keep state
    double kmh = location.speed * 3.6;
    self.lastSpeedKmh = kmh;
    NSDate *now = location.timestamp ?: [NSDate date];
    if (kmh > kDrivingKmh) {
        _belowSince = nil;
        if (!_aboveSince) _aboveSince = now;
        if (!self.driving && [now timeIntervalSinceDate:_aboveSince] >= kDrivingAfter) [self setDrivingNotify:YES];
    } else if (kmh < kStandingKmh) {
        _aboveSince = nil;
        if (!_belowSince) _belowSince = now;
        if (self.driving && [now timeIntervalSinceDate:_belowSince] >= kStandingAfter) [self setDrivingNotify:NO];
    } else {
        _aboveSince = _belowSince = nil;   // hysteresis band: keep current state
    }
}

- (void)setDrivingNotify:(BOOL)driving {
    if (self.driving == driving) return;
    self.driving = driving;
    BKLogf(@"Fahrsperre: %@", driving ? @"Fahrt erkannt" : @"Stillstand");
    [[NSNotificationCenter defaultCenter] postNotificationName:BKDriveGuardDidChangeNotification object:self];
}

@end
