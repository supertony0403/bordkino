#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "BKLibrary.h"

NS_ASSUME_NONNULL_BEGIN

/// Shows the player's picture. Renderer A uses AVPlayerLayer; renderer B pulls
/// frames via AVPlayerItemVideoOutput and draws them with Metal inside this
/// process – the fallback if A stays black on the CarPlay display.
@interface BKVideoSurface : UIView
@property (nonatomic) BKRenderer renderer;
@property (nonatomic, strong, nullable) AVPlayer *player;
/// Frames drawn by renderer B since the last reset (diagnostics).
@property (nonatomic, readonly) NSUInteger pumpedFrames;
@end

NS_ASSUME_NONNULL_END
