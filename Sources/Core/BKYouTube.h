#import <Foundation/Foundation.h>
#import "BKModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Typed facade over the JS extractor. Completions run on the main queue.
@interface BKYouTube : NSObject
+ (instancetype)shared;
- (void)search:(NSString *)query
  continuation:(nullable NSString *)continuation
    completion:(void (^)(NSArray<BKVideo *> *items, NSString * _Nullable next, NSError * _Nullable error))completion;
- (void)resolve:(NSString *)input
        exclude:(nullable NSArray<NSString *> *)exclude
     completion:(void (^)(BKStream * _Nullable stream, NSError * _Nullable error))completion;
- (void)channelFeed:(NSString *)channelId completion:(void (^)(NSArray<BKVideo *> *items, NSError * _Nullable error))completion;
- (void)resolveChannel:(NSString *)input completion:(void (^)(BKChannel * _Nullable channel, NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
