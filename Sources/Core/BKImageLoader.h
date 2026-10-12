#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BKImageLoader : NSObject
/// Loads into an image view; stale loads (cell reuse) are ignored.
+ (void)loadURL:(nullable NSURL *)url into:(UIImageView *)imageView;
+ (void)loadURL:(nullable NSURL *)url completion:(void (^)(UIImage * _Nullable image))completion;
@end

NS_ASSUME_NONNULL_END
