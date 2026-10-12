#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared data directory of both app variants: ~/Library/Application Support/Bordkino
NSString *BKDataDirectory(void);

/// Logs to NSLog, an in-memory ring buffer (500 lines) and bordkino.log.
void BKLogf(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

@interface BKLog : NSObject
+ (NSArray<NSString *> *)recentLines;
+ (NSString *)logFilePath;
@end

NS_ASSUME_NONNULL_END
