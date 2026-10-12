#import "BKImageLoader.h"
#import <objc/runtime.h>

static const void *kPendingURLKey = &kPendingURLKey;

@implementation BKImageLoader

+ (NSCache<NSURL *, UIImage *> *)cache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 300;
    });
    return cache;
}

+ (void)loadURL:(NSURL *)url completion:(void (^)(UIImage *))completion {
    if (!url) { completion(nil); return; }
    UIImage *cached = [[self cache] objectForKey:url];
    if (cached) { completion(cached); return; }
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (image && image.size.width > 640) {
            CGSize target = CGSizeMake(640, round(640 * image.size.height / image.size.width));
            image = [image imageByPreparingThumbnailOfSize:target] ?: image;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) [[self cache] setObject:image forKey:url];
            completion(image);
        });
    }] resume];
}

+ (void)loadURL:(NSURL *)url into:(UIImageView *)imageView {
    objc_setAssociatedObject(imageView, kPendingURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImage *cached = url ? [[self cache] objectForKey:url] : nil;
    imageView.image = cached;
    if (cached || !url) return;
    __weak UIImageView *weakView = imageView;
    [self loadURL:url completion:^(UIImage *image) {
        UIImageView *view = weakView;
        if (view && [objc_getAssociatedObject(view, kPendingURLKey) isEqual:url]) view.image = image;
    }];
}

@end
