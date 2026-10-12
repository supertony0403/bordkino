#import "BKVideoSurface.h"
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "BKLog.h"

static void *kCurrentItemContext = &kCurrentItemContext;

/// Breaks the CADisplayLink -> target retain cycle.
@interface BKWeakProxy : NSObject
@property (nonatomic, weak) id target;
@end

@implementation BKWeakProxy
- (void)tick:(CADisplayLink *)link {
    [self.target performSelector:@selector(tick:) withObject:link];
}
@end

@implementation BKVideoSurface {
    AVPlayerLayer *_playerLayer;
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    CIContext *_ciContext;
    AVPlayerItemVideoOutput *_output;
    AVPlayerItem *_outputItem;
    CADisplayLink *_link;
    CIImage *_lastFrame;
    CGColorSpaceRef _colorSpace;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.blackColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        _playerLayer = [AVPlayerLayer new];
        _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [self.layer addSublayer:_playerLayer];
        _colorSpace = CGColorSpaceCreateDeviceRGB();
        _device = MTLCreateSystemDefaultDevice();
        if (_device) {
            _commandQueue = [_device newCommandQueue];
            _ciContext = [CIContext contextWithMTLDevice:_device options:@{ kCIContextWorkingColorSpace: [NSNull null] }];
            _metalLayer = [CAMetalLayer new];
            _metalLayer.device = _device;
            _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            _metalLayer.framebufferOnly = NO;   // CIContext writes into the drawable
            _metalLayer.backgroundColor = UIColor.blackColor.CGColor;
            _metalLayer.hidden = YES;
            [self.layer addSublayer:_metalLayer];
        } else {
            BKLogf(@"Kein Metal-Gerät – Renderer B nicht verfügbar");
        }
    }
    return self;
}

- (void)dealloc {
    [self stopPump];
    [self detachOutput];
    if (_player) [_player removeObserver:self forKeyPath:@"currentItem" context:kCurrentItemContext];
    if (_colorSpace) CGColorSpaceRelease(_colorSpace);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _playerLayer.frame = self.bounds;
    _metalLayer.frame = self.bounds;
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    _metalLayer.contentsScale = scale;
    _metalLayer.drawableSize = CGSizeMake(MAX(1, self.bounds.size.width * scale), MAX(1, self.bounds.size.height * scale));
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self apply];
}

#pragma mark Configuration

- (void)setPlayer:(AVPlayer *)player {
    if (_player == player) return;
    if (_player) [_player removeObserver:self forKeyPath:@"currentItem" context:kCurrentItemContext];
    _player = player;
    if (_player) [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew context:kCurrentItemContext];
    [self apply];
}

- (void)setRenderer:(BKRenderer)renderer {
    if (_renderer == renderer) return;
    _renderer = renderer;
    _pumpedFrames = 0;
    BKLogf(@"Renderer %@ aktiv", renderer == BKRendererPump ? @"B (Bildpumpe/Metal)" : @"A (AVPlayerLayer)");
    [self apply];
}

- (void)setFill:(BKVideoFill)fill {
    if (_fill == fill) return;
    _fill = fill;
    _playerLayer.videoGravity = fill == BKVideoFillZoom ? AVLayerVideoGravityResizeAspectFill
                              : fill == BKVideoFillStretch ? AVLayerVideoGravityResize : AVLayerVideoGravityResizeAspect;
    [self draw];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kCurrentItemContext) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self apply]; });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)apply {
    BOOL pump = self.renderer == BKRendererPump && _metalLayer != nil;
    _playerLayer.player = pump ? nil : self.player;
    _playerLayer.hidden = pump;
    _metalLayer.hidden = !pump;
    if (pump && self.window && self.player) {
        [self attachOutputToItem:self.player.currentItem];
        [self startPump];
    } else {
        [self stopPump];
        [self detachOutput];
    }
}

#pragma mark Renderer B

- (void)attachOutputToItem:(AVPlayerItem *)item {
    if (item == _outputItem) return;
    [self detachOutput];
    if (!item) return;
    NSDictionary *attributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
    [item addOutput:_output];
    _outputItem = item;
    _lastFrame = nil;
}

- (void)detachOutput {
    if (_outputItem && _output) [_outputItem removeOutput:_output];
    _output = nil;
    _outputItem = nil;
    _lastFrame = nil;
}

- (void)startPump {
    UIScreen *screen = self.window.screen;
    if (_link && _link.isPaused == NO) return;
    [self stopPump];
    BKWeakProxy *proxy = [BKWeakProxy new];
    proxy.target = self;
    // The display link must come from the screen this view is on (car or phone).
    _link = screen ? [screen displayLinkWithTarget:proxy selector:@selector(tick:)]
                   : [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    _link.preferredFramesPerSecond = 30;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopPump {
    [_link invalidate];
    _link = nil;
}

- (void)tick:(CADisplayLink *)link {
    if (!_output || !_ciContext) return;
    CMTime itemTime = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if ([_output hasNewPixelBufferForItemTime:itemTime]) {
        CVPixelBufferRef buffer = [_output copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
        if (buffer) {
            _lastFrame = [CIImage imageWithCVPixelBuffer:buffer];
            CVPixelBufferRelease(buffer);
            [self draw];
        }
    }
}

- (void)draw {
    CIImage *frame = _lastFrame;
    if (!frame) return;
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;
    CGSize target = _metalLayer.drawableSize;
    CGRect extent = frame.extent;
    if (extent.size.width < 1 || extent.size.height < 1) return;
    CGFloat sx = target.width / extent.size.width, sy = target.height / extent.size.height;
    if (self.fill == BKVideoFillFit) sx = sy = MIN(sx, sy);
    else if (self.fill == BKVideoFillZoom) sx = sy = MAX(sx, sy);
    CGFloat dx = (target.width - extent.size.width * sx) / 2.0;
    CGFloat dy = (target.height - extent.size.height * sy) / 2.0;
    CIImage *scaled = [frame imageByApplyingTransform:CGAffineTransformMake(sx, 0, 0, sy, dx - extent.origin.x * sx, dy - extent.origin.y * sy)];
    CGRect bounds = CGRectMake(0, 0, target.width, target.height);
    CIImage *black = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0]] imageByCroppingToRect:bounds];
    CIImage *composed = [scaled imageByCompositingOverImage:black];
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    [_ciContext render:composed toMTLTexture:drawable.texture commandBuffer:commandBuffer bounds:bounds colorSpace:_colorSpace];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    _pumpedFrames++;
}

@end
