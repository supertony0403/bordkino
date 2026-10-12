#import <Foundation/Foundation.h>
#import "BKModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const BKLibraryDidChangeNotification;

typedef NS_ENUM(NSInteger, BKRenderer) {
    BKRendererLayer = 0,   // AVPlayerLayer
    BKRendererPump = 1,    // AVPlayerItemVideoOutput -> layer.contents
};

/// Persistent user data shared by both app variants (library.json in BKDataDirectory()).
/// Main thread only.
@interface BKLibrary : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<BKVideo *> *history;
@property (nonatomic, readonly) NSArray<BKVideo *> *favorites;
@property (nonatomic, readonly) NSArray<BKChannel *> *channels;

/// Re-reads library.json (the other app variant may have changed it).
- (void)reload;

- (void)addToHistory:(BKVideo *)video;
- (void)clearHistory;
- (BOOL)isFavorite:(BKVideo *)video;
- (void)toggleFavorite:(BKVideo *)video;
- (void)addChannel:(BKChannel *)channel;
- (void)removeChannelWithId:(NSString *)channelId;

- (NSTimeInterval)positionForVideo:(BKVideo *)video;
- (void)setPosition:(NSTimeInterval)position forVideo:(BKVideo *)video;

// Settings
@property (nonatomic) BOOL driveLockEnabled;     // default YES
@property (nonatomic) BKRenderer renderer;        // default BKRendererLayer
@property (nonatomic) NSInteger maxResolution;    // 0 = auto, 720, 480
@property (nonatomic) BOOL keepPhoneAwake;        // default NO
@end

NS_ASSUME_NONNULL_END
