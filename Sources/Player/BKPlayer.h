#import <AVFoundation/AVFoundation.h>
#import "BKModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BKPlayerStateDidChangeNotification;
/// Posted when a new item starts loading (UI shows the player).
extern NSNotificationName const BKPlayerDidStartVideoNotification;

typedef NS_ENUM(NSInteger, BKPlayerState) {
    BKPlayerStateIdle,
    BKPlayerStateLoading,
    BKPlayerStatePlaying,
    BKPlayerStatePaused,
    BKPlayerStateFailed,
};

/// The single shared playback engine for phone and car screens.
@interface BKPlayer : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) BKPlayerState state;
@property (nonatomic, readonly, nullable) BKVideo *currentVideo;
@property (nonatomic, readonly, nullable) NSString *errorMessage;
@property (nonatomic, readonly, nullable) NSString *activeClient;

- (void)playVideo:(BKVideo *)video;
/// Accepts a YouTube link/ID or a direct http(s) media link.
- (void)playInput:(NSString *)input;
- (void)togglePlayPause;
- (void)play;
- (void)pause;
- (void)seekBy:(NSTimeInterval)delta;
- (void)seekTo:(NSTimeInterval)seconds;
- (void)stop;
- (void)retry;
- (NSTimeInterval)currentTime;
- (NSTimeInterval)duration;   // 0 when unknown or live
@end

NS_ASSUME_NONNULL_END
