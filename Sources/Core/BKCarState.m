#import "BKCarState.h"
#import "BKLog.h"

NSNotificationName const BKCarStateDidChangeNotification = @"BKCarStateDidChangeNotification";

@implementation BKCarState

+ (instancetype)shared {
    static BKCarState *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKCarState new]; });
    return instance;
}

- (void)setConnected:(BOOL)connected {
    if (_connected == connected) return;
    _connected = connected;
    BKLogf(@"CarPlay %@", connected ? @"verbunden" : @"getrennt");
    [[NSNotificationCenter defaultCenter] postNotificationName:BKCarStateDidChangeNotification object:self];
}

@end
