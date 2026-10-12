#import <UIKit/UIKit.h>
#import "BKVideoSurface.h"

NS_ASSUME_NONNULL_BEGIN

/// Picture + drive-lock cover + loading/error status. No touch controls,
/// so it also works as the CPWindow root of the template variant.
@interface BKVideoViewController : UIViewController
@property (nonatomic, readonly) BKVideoSurface *surface;
/// Shown when nothing is playing (template variant hint).
@property (nonatomic, copy, nullable) NSString *idleText;
@end

NS_ASSUME_NONNULL_END
