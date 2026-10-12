#import <UIKit/UIKit.h>
#import "BKVideoListViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Thumbnail grid for the car screen; tapping starts playback.
@interface BKCarGridViewController : UIViewController
- (instancetype)initWithLoader:(nullable BKVideoListLoader)loader emptyText:(NSString *)emptyText;
@property (nonatomic, copy, nullable) BKVideoListLoader loader;
@property (nonatomic, copy) NSString *emptyText;
@property (nonatomic) BOOL reloadsOnLibraryChange;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
