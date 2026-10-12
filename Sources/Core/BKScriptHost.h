#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const BKScriptErrorDomain;
/// userInfo key holding the extractor's error code string (e.g. "ALL_CLIENTS_FAILED").
extern NSString *const BKScriptErrorCodeKey;

/// Runs js/extractor.js in a JavaScriptCore context and bridges `host.fetch`
/// to NSURLSession. All JS work happens on one private serial queue.
@interface BKScriptHost : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, copy) NSString *extractorVersion;
@property (nonatomic, readonly, copy) NSString *extractorSource;   // "eingebaut" | "aktualisiert"
/// Calls api[method](...arguments). The JS function must return a Promise.
/// The completion runs on the main queue.
- (void)call:(NSString *)method arguments:(NSArray *)arguments completion:(void (^)(id _Nullable result, NSError * _Nullable error))completion;
/// Reloads the script (after an update was installed).
- (void)reload;
/// Evaluates a script in a throwaway context; returns its version if it loads and passes selfTest.
+ (nullable NSString *)validatedVersionOfScript:(NSString *)source;
@end

NS_ASSUME_NONNULL_END
