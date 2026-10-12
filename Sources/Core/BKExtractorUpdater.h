#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Fetches a newer js/extractor.js from the GitHub repository so YouTube
/// changes can be followed without rebuilding the app.
@interface BKExtractorUpdater : NSObject
+ (NSString *)installedScriptPath;
/// Checks at most once per 24 h unless `force` is set. Completion on main queue.
+ (void)checkForUpdateForce:(BOOL)force completion:(nullable void (^)(BOOL updated, NSString *message))completion;
@end

NS_ASSUME_NONNULL_END
