#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A playable item: a YouTube video (videoId) or a direct media link (directURL).
@interface BKVideo : NSObject <NSCopying>
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *channel;
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic, copy) NSString *durationText;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy, nullable) NSURL *thumbnailURL;
@property (nonatomic) NSInteger durationSeconds;
@property (nonatomic) BOOL isLive;
@property (nonatomic, copy, nullable) NSURL *directURL;

+ (nullable instancetype)videoWithDictionary:(NSDictionary *)dictionary;
+ (instancetype)videoWithDirectURL:(NSURL *)url title:(nullable NSString *)title;
+ (NSArray<BKVideo *> *)videosFromArray:(nullable NSArray *)array;
- (NSDictionary *)dictionaryRepresentation;
/// Stable key for history/favorites/positions.
- (NSString *)identifier;
@end

@interface BKStream : NSObject
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSString *kind;       // "hls" | "progressive" | "direct"
@property (nonatomic, copy) NSString *client;     // extractor client name, "direct" for links
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, strong) BKVideo *video;
+ (nullable instancetype)streamWithDictionary:(NSDictionary *)dictionary;
@end

@interface BKChannel : NSObject
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic, copy) NSString *title;
+ (nullable instancetype)channelWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
@end

NS_ASSUME_NONNULL_END
