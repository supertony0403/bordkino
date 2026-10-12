#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Full-screen player with touch controls (phone and Stark car UI).
@interface BKPlayerViewController : UIViewController
@property (nonatomic) BOOL carStyle;
/// Called after the user closed the player (playback is already stopped).
@property (nonatomic, copy, nullable) dispatch_block_t onClose;
@end

NS_ASSUME_NONNULL_END
