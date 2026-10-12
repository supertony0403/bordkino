#import "BKPlayer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
#import "BKYouTube.h"
#import "BKLibrary.h"
#import "BKCarState.h"
#import "BKImageLoader.h"
#import "BKLog.h"

NSNotificationName const BKPlayerStateDidChangeNotification = @"BKPlayerStateDidChangeNotification";
NSNotificationName const BKPlayerDidStartVideoNotification = @"BKPlayerDidStartVideoNotification";

static void *kItemStatusContext = &kItemStatusContext;
static void *kTimeControlContext = &kTimeControlContext;
static const NSTimeInterval kStartTimeout = 15;
static const NSTimeInterval kResumeMargin = 30;

static BOOL BKIsYouTubeHost(NSString *host) {
    host = host.lowercaseString;
    return [host isEqualToString:@"youtu.be"] || [host isEqualToString:@"youtube.com"] || [host hasSuffix:@".youtube.com"];
}

@interface BKPlayer ()
@property (nonatomic, readwrite) BKPlayerState state;
@property (nonatomic, readwrite, nullable) BKVideo *currentVideo;
@property (nonatomic, readwrite, nullable) NSString *errorMessage;
@property (nonatomic, readwrite, nullable) NSString *activeClient;
@end

@implementation BKPlayer {
    AVPlayer *_player;
    AVPlayerItem *_observedItem;
    NSMutableArray<NSString *> *_triedClients;
    NSUInteger _generation;
    NSTimer *_startTimer;
    id _timeObserver;
    NSTimeInterval _pendingResume;
    NSTimeInterval _lastSavedAt;
    NSString *_lastPlaybackError;
    UIImage *_artwork;
    BOOL _phoneDimmed;
    CGFloat _savedBrightness;
}

+ (instancetype)shared {
    static BKPlayer *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKPlayer new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _player = [AVPlayer new];
        _player.allowsExternalPlayback = NO;
        _triedClients = [NSMutableArray new];
        [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:kTimeControlContext];
        __weak BKPlayer *weakSelf = self;
        _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf tick];
        }];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(itemDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        [nc addObserver:self selector:@selector(itemFailedToEnd:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
        [nc addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
        [nc addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [nc addObserver:self selector:@selector(settingsChanged:) name:BKLibraryDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(carStateChanged:) name:BKCarStateDidChangeNotification object:nil];
        [self setupRemoteCommands];
    }
    return self;
}

- (AVPlayer *)player { return _player; }

#pragma mark Starting playback

- (void)playInput:(NSString *)input {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:text];
    NSString *scheme = url.scheme.lowercaseString;
    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && url.host.length && !BKIsYouTubeHost(url.host)) {
        [self playVideo:[BKVideo videoWithDirectURL:url title:nil]];
        return;
    }
    BKVideo *placeholder = [BKVideo new];
    placeholder.videoId = text;            // the extractor parses links and IDs
    placeholder.title = @"YouTube-Video";
    [self playVideo:placeholder];
}

- (void)playVideo:(BKVideo *)video {
    [self savePositionForce:YES];
    _generation++;
    [_triedClients removeAllObjects];
    _lastPlaybackError = nil;
    _artwork = nil;
    self.currentVideo = video;
    self.errorMessage = nil;
    self.activeClient = nil;
    [self cancelStartTimer];
    [self replaceItem:nil];
    [self setState:BKPlayerStateLoading];
    [[NSNotificationCenter defaultCenter] postNotificationName:BKPlayerDidStartVideoNotification object:self];
    BKLogf(@"Starte „%@“ (%@)", video.title, video.identifier);
    if (video.directURL) {
        BKStream *stream = [BKStream new];
        stream.url = video.directURL;
        stream.kind = @"direct";
        stream.client = @"direct";
        stream.userAgent = @"";
        stream.video = video;
        [_triedClients addObject:@"direct"];
        [self startStream:stream];
    } else {
        [self resolveCurrent];
    }
}

- (void)retry {
    if (self.currentVideo) [self playVideo:self.currentVideo];
}

- (void)resolveCurrent {
    NSUInteger generation = _generation;
    NSString *input = self.currentVideo.videoId;
    [[BKYouTube shared] resolve:input exclude:[_triedClients copy] completion:^(BKStream *stream, NSError *error) {
        if (generation != self->_generation) return;
        if (!stream) {
            NSString *reason = error.localizedDescription ?: @"Unbekannter Fehler.";
            if (self->_lastPlaybackError) reason = [NSString stringWithFormat:@"Wiedergabe fehlgeschlagen: %@", self->_lastPlaybackError];
            [self failWith:reason];
            return;
        }
        [self->_triedClients addObject:stream.client];
        // The extractor knows the real ID and fresher metadata; keep a thumbnail we already had.
        BKVideo *merged = stream.video;
        if (!merged.thumbnailURL) merged.thumbnailURL = self.currentVideo.thumbnailURL;
        if (!merged.subtitle.length) merged.subtitle = self.currentVideo.subtitle;
        self.currentVideo = merged;
        [self startStream:stream];
    }];
}

- (void)startStream:(BKStream *)stream {
    self.activeClient = stream.client;
    BKLogf(@"Stream %@/%@ für %@", stream.client, stream.kind, stream.video.identifier);
    [[BKLibrary shared] addToHistory:self.currentVideo];
    NSDictionary *options = stream.userAgent.length ? @{ @"AVURLAssetHTTPHeaderFieldsKey": @{ @"User-Agent": stream.userAgent } } : nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:stream.url options:options];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    [self applyMaxResolutionToItem:item];
    NSTimeInterval saved = [[BKLibrary shared] positionForVideo:self.currentVideo];
    NSInteger length = self.currentVideo.durationSeconds;
    _pendingResume = (saved > kResumeMargin && (length == 0 || saved < length - kResumeMargin)) ? saved : 0;
    [self activateAudioSession];
    [self replaceItem:item];
    [_player play];
    [self loadArtwork];
    [self updateNowPlaying];
    [self armStartTimer];
}

- (void)replaceItem:(nullable AVPlayerItem *)item {
    if (_observedItem) {
        [_observedItem removeObserver:self forKeyPath:@"status" context:kItemStatusContext];
        _observedItem = nil;
    }
    if (item) {
        [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kItemStatusContext];
        _observedItem = item;
    }
    [_player replaceCurrentItemWithPlayerItem:item];
}

- (void)applyMaxResolutionToItem:(AVPlayerItem *)item {
    NSInteger max = [BKLibrary shared].maxResolution;
    item.preferredMaximumResolution = max == 720 ? CGSizeMake(1280, 720) : (max == 480 ? CGSizeMake(854, 480) : CGSizeZero);
}

#pragma mark Failure handling

- (void)armStartTimer {
    [self cancelStartTimer];
    NSUInteger generation = _generation;
    __weak BKPlayer *weakSelf = self;
    _startTimer = [NSTimer scheduledTimerWithTimeInterval:kStartTimeout repeats:NO block:^(NSTimer *timer) {
        BKPlayer *strongSelf = weakSelf;
        if (strongSelf && generation == strongSelf->_generation && strongSelf.state == BKPlayerStateLoading) {
            [strongSelf playbackFailed:@"Stream startet nicht (Zeitüberschreitung)."];
        }
    }];
}

- (void)cancelStartTimer {
    [_startTimer invalidate];
    _startTimer = nil;
}

- (void)playbackFailed:(NSString *)reason {
    [self cancelStartTimer];
    _lastPlaybackError = reason;
    BKLogf(@"Wiedergabe über %@ fehlgeschlagen: %@", self.activeClient ?: @"?", reason);
    if (self.currentVideo.directURL || [_triedClients containsObject:@"direct"]) {
        [self failWith:reason];
        return;
    }
    [self replaceItem:nil];
    [self setState:BKPlayerStateLoading];
    [self resolveCurrent];   // tries the next client (exclude = tried ones)
}

- (void)failWith:(NSString *)reason {
    [self cancelStartTimer];
    BKLogf(@"Abbruch: %@", reason);
    self.errorMessage = reason;
    [self setState:BKPlayerStateFailed];
}

#pragma mark Transport

- (void)play {
    if (!_player.currentItem) {
        if (self.state == BKPlayerStateFailed) [self retry];
        return;
    }
    [self activateAudioSession];
    [_player play];
}

- (void)pause {
    [_player pause];
    [self savePositionForce:YES];
}

- (void)togglePlayPause {
    if (_player.timeControlStatus == AVPlayerTimeControlStatusPaused) [self play];
    else [self pause];
}

- (void)seekBy:(NSTimeInterval)delta {
    [self seekTo:[self currentTime] + delta];
}

- (void)seekTo:(NSTimeInterval)seconds {
    if (!_player.currentItem) return;
    NSTimeInterval duration = [self duration];
    if (duration > 0) seconds = MIN(seconds, duration - 1);
    seconds = MAX(0, seconds);
    CMTime tolerance = CMTimeMakeWithSeconds(1, 600);
    [_player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:tolerance toleranceAfter:tolerance completionHandler:^(BOOL finished) {
        [self updateNowPlaying];
    }];
}

- (void)stop {
    [self savePositionForce:YES];
    _generation++;
    [self cancelStartTimer];
    [_player pause];
    [self replaceItem:nil];
    self.currentVideo = nil;
    self.errorMessage = nil;
    self.activeClient = nil;
    [self setState:BKPlayerStateIdle];
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (NSTimeInterval)currentTime {
    NSTimeInterval t = CMTimeGetSeconds(_player.currentTime);
    return isfinite(t) ? t : 0;
}

- (NSTimeInterval)duration {
    CMTime d = _player.currentItem.duration;
    if (CMTIME_IS_INDEFINITE(d) || !CMTIME_IS_NUMERIC(d)) return 0;
    NSTimeInterval s = CMTimeGetSeconds(d);
    return isfinite(s) ? s : 0;
}

#pragma mark State

- (void)setState:(BKPlayerState)state {
    if (_state == state && state != BKPlayerStateFailed) return;
    _state = state;
    [self updateNowPlaying];
    [self updatePhoneDimming];
    [[NSNotificationCenter defaultCenter] postNotificationName:BKPlayerStateDidChangeNotification object:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kItemStatusContext) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self itemStatusChanged:object]; });
    } else if (context == kTimeControlContext) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self timeControlChanged]; });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)itemStatusChanged:(AVPlayerItem *)item {
    if (item != _player.currentItem) return;
    if (item.status == AVPlayerItemStatusFailed) {
        [self playbackFailed:item.error.localizedDescription ?: @"AVPlayer meldet einen Fehler."];
    } else if (item.status == AVPlayerItemStatusReadyToPlay && _pendingResume > 0) {
        NSTimeInterval resume = _pendingResume;
        _pendingResume = 0;
        BKLogf(@"Setze bei %.0f s fort", resume);
        [self seekTo:resume];
    }
}

- (void)timeControlChanged {
    if (!_player.currentItem) return;
    switch (_player.timeControlStatus) {
        case AVPlayerTimeControlStatusPlaying:
            [self cancelStartTimer];
            [self setState:BKPlayerStatePlaying];
            break;
        case AVPlayerTimeControlStatusPaused:
            if (self.state != BKPlayerStateLoading && self.state != BKPlayerStateFailed) [self setState:BKPlayerStatePaused];
            break;
        case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
            if (self.state == BKPlayerStatePlaying) [self setState:BKPlayerStateLoading];
            break;
    }
}

- (void)itemDidEnd:(NSNotification *)note {
    if (note.object != _player.currentItem) return;
    [[BKLibrary shared] setPosition:0 forVideo:self.currentVideo];
    [self setState:BKPlayerStatePaused];
}

- (void)itemFailedToEnd:(NSNotification *)note {
    if (note.object != _player.currentItem) return;
    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self playbackFailed:error.localizedDescription ?: @"Wiedergabe abgebrochen."];
}

- (void)tick {
    [self savePositionForce:NO];
    [self updateNowPlaying];
}

- (void)savePositionForce:(BOOL)force {
    BKVideo *video = self.currentVideo;
    if (!video || !_player.currentItem || video.isLive) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!force && now - _lastSavedAt < 10) return;
    NSTimeInterval t = [self currentTime];
    if (t < 1) return;
    _lastSavedAt = now;
    [[BKLibrary shared] setPosition:t forVideo:video];
}

#pragma mark Audio session

- (void)activateAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:&error] ||
        ![session setActive:YES error:&error]) {
        BKLogf(@"Audiositzung: %@", error.localizedDescription);
    }
}

- (void)routeChanged:(NSNotification *)note {
    NSInteger reason = [note.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BKLogf(@"Audioausgang weg (z. B. CarPlay getrennt) – Pause");
            [self pause];
        });
    }
}

- (void)interrupted:(NSNotification *)note {
    NSInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
    NSInteger options = [note.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (type == AVAudioSessionInterruptionTypeEnded && (options & AVAudioSessionInterruptionOptionShouldResume)) {
            [self play];
        }
    });
}

- (void)settingsChanged:(NSNotification *)note {
    if (_player.currentItem) [self applyMaxResolutionToItem:_player.currentItem];
    [self updatePhoneDimming];
}

- (void)carStateChanged:(NSNotification *)note {
    [self updatePhoneDimming];
}

/// Optional: keeps the phone awake but dark while the car shows video.
- (void)updatePhoneDimming {
    BOOL want = [BKLibrary shared].keepPhoneAwake && [BKCarState shared].connected &&
                (self.state == BKPlayerStatePlaying || self.state == BKPlayerStateLoading);
    if (want == _phoneDimmed) return;
    _phoneDimmed = want;
    UIScreen *screen = [UIScreen mainScreen];
    if (want) {
        _savedBrightness = screen.brightness;
        screen.brightness = 0.02;
    } else {
        screen.brightness = _savedBrightness > 0 ? _savedBrightness : 0.5;
    }
    [UIApplication sharedApplication].idleTimerDisabled = want;
}

#pragma mark Now Playing & remote commands

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *rc = [MPRemoteCommandCenter sharedCommandCenter];
    __weak BKPlayer *weakSelf = self;
    [rc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf play]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf pause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf togglePlayPause]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    rc.skipForwardCommand.preferredIntervals = @[@30];
    [rc.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf seekBy:30]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    rc.skipBackwardCommand.preferredIntervals = @[@10];
    [rc.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf seekBy:-10]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    // Steering-wheel arrows usually send next/previous track.
    [rc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf seekBy:30]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf seekBy:-10]; return MPRemoteCommandHandlerStatusSuccess;
    }];
    [rc.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [weakSelf seekTo:((MPChangePlaybackPositionCommandEvent *)e).positionTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

- (void)loadArtwork {
    NSURL *url = self.currentVideo.thumbnailURL;
    NSUInteger generation = _generation;
    [BKImageLoader loadURL:url completion:^(UIImage *image) {
        if (generation != self->_generation || !image) return;
        self->_artwork = image;
        [self updateNowPlaying];
    }];
}

- (void)updateNowPlaying {
    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    BKVideo *video = self.currentVideo;
    if (!video || self.state == BKPlayerStateIdle) {
        center.nowPlayingInfo = nil;
        return;
    }
    NSMutableDictionary *info = [@{
        MPMediaItemPropertyTitle: video.title ?: @"",
        MPMediaItemPropertyArtist: video.channel ?: @"",
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @([self currentTime]),
        MPNowPlayingInfoPropertyPlaybackRate: @(_player.rate),
        MPNowPlayingInfoPropertyMediaType: @(MPNowPlayingInfoMediaTypeVideo),
    } mutableCopy];
    NSTimeInterval duration = [self duration];
    if (duration > 0) info[MPMediaItemPropertyPlaybackDuration] = @(duration);
    if (video.isLive) info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
    UIImage *art = _artwork;
    if (art) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:art.size requestHandler:^UIImage *(CGSize size) {
            return art;
        }];
    }
    center.nowPlayingInfo = info;
}

@end
