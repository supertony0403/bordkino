#import "BKLibrary.h"
#import "BKLog.h"

NSNotificationName const BKLibraryDidChangeNotification = @"BKLibraryDidChangeNotification";

static const NSUInteger kMaxHistory = 50;
static const NSUInteger kMaxPositions = 200;

@implementation BKLibrary {
    NSMutableArray<BKVideo *> *_history;
    NSMutableArray<BKVideo *> *_favorites;
    NSMutableArray<BKChannel *> *_channels;
    NSMutableDictionary<NSString *, NSArray *> *_positions;   // id -> @[position, savedAt]
    NSMutableDictionary<NSString *, id> *_settings;
}

+ (instancetype)shared {
    static BKLibrary *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKLibrary new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reload];
    }
    return self;
}

- (NSString *)path {
    return [BKDataDirectory() stringByAppendingPathComponent:@"library.json"];
}

- (void)reload {
    NSDictionary *root = nil;
    NSData *data = [NSData dataWithContentsOfFile:[self path]];
    if (data) {
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:NSDictionary.class]) root = parsed;
        else BKLogf(@"library.json unlesbar – starte leer");
    }
    _history = [[BKVideo videosFromArray:root[@"history"]] mutableCopy];
    _favorites = [[BKVideo videosFromArray:root[@"favorites"]] mutableCopy];
    _channels = [NSMutableArray new];
    for (id item in ([root[@"channels"] isKindOfClass:NSArray.class] ? root[@"channels"] : @[])) {
        BKChannel *c = [BKChannel channelWithDictionary:item];
        if (c) [_channels addObject:c];
    }
    _positions = [([root[@"positions"] isKindOfClass:NSDictionary.class] ? root[@"positions"] : @{}) mutableCopy];
    NSMutableDictionary *settings = [@{ @"driveLock": @YES, @"renderer": @(BKRendererLayer), @"maxResolution": @0, @"keepPhoneAwake": @NO } mutableCopy];
    if ([root[@"settings"] isKindOfClass:NSDictionary.class]) [settings addEntriesFromDictionary:root[@"settings"]];
    _settings = settings;
    [[NSNotificationCenter defaultCenter] postNotificationName:BKLibraryDidChangeNotification object:self];
}

- (void)save {
    NSMutableArray *channels = [NSMutableArray new];
    for (BKChannel *c in _channels) [channels addObject:c.dictionaryRepresentation];
    NSDictionary *root = @{
        @"history": [_history valueForKey:@"dictionaryRepresentation"],
        @"favorites": [_favorites valueForKey:@"dictionaryRepresentation"],
        @"channels": channels,
        @"positions": _positions,
        @"settings": _settings,
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || ![data writeToFile:[self path] options:NSDataWritingAtomic error:&error]) {
        BKLogf(@"library.json nicht gespeichert: %@", error.localizedDescription);
    }
}

- (void)changed {
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:BKLibraryDidChangeNotification object:self];
}

- (NSArray<BKVideo *> *)history { return [_history copy]; }
- (NSArray<BKVideo *> *)favorites { return [_favorites copy]; }
- (NSArray<BKChannel *> *)channels { return [_channels copy]; }

- (void)addToHistory:(BKVideo *)video {
    if (!video.identifier.length) return;
    [_history removeObject:video];
    [_history insertObject:[video copy] atIndex:0];
    if (_history.count > kMaxHistory) [_history removeObjectsInRange:NSMakeRange(kMaxHistory, _history.count - kMaxHistory)];
    [self changed];
}

- (void)clearHistory {
    [_history removeAllObjects];
    [self changed];
}

- (BOOL)isFavorite:(BKVideo *)video {
    return [_favorites containsObject:video];
}

- (void)toggleFavorite:(BKVideo *)video {
    if (!video.identifier.length) return;
    if ([_favorites containsObject:video]) [_favorites removeObject:video];
    else [_favorites insertObject:[video copy] atIndex:0];
    [self changed];
}

- (void)addChannel:(BKChannel *)channel {
    for (BKChannel *c in _channels) {
        if ([c.channelId isEqualToString:channel.channelId]) return;
    }
    [_channels addObject:channel];
    [_channels sortUsingComparator:^NSComparisonResult(BKChannel *a, BKChannel *b) {
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    [self changed];
}

- (void)removeChannelWithId:(NSString *)channelId {
    NSIndexSet *hits = [_channels indexesOfObjectsPassingTest:^BOOL(BKChannel *c, NSUInteger i, BOOL *stop) {
        return [c.channelId isEqualToString:channelId];
    }];
    if (!hits.count) return;
    [_channels removeObjectsAtIndexes:hits];
    [self changed];
}

- (NSTimeInterval)positionForVideo:(BKVideo *)video {
    NSArray *entry = _positions[video.identifier];
    return [entry isKindOfClass:NSArray.class] && entry.count == 2 ? [entry[0] doubleValue] : 0;
}

- (void)setPosition:(NSTimeInterval)position forVideo:(BKVideo *)video {
    if (!video.identifier.length || video.isLive) return;
    if (position < 1) [_positions removeObjectForKey:video.identifier];
    else _positions[video.identifier] = @[@(position), @([NSDate date].timeIntervalSince1970)];
    if (_positions.count > kMaxPositions) {
        NSArray *keys = [_positions keysSortedByValueUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            return [a[1] compare:b[1]];
        }];
        [_positions removeObjectsForKeys:[keys subarrayWithRange:NSMakeRange(0, _positions.count - kMaxPositions)]];
    }
    [self save];   // no notification: positions change every few seconds
}

#pragma mark Settings

- (BOOL)driveLockEnabled { return [_settings[@"driveLock"] boolValue]; }
- (void)setDriveLockEnabled:(BOOL)v { _settings[@"driveLock"] = @(v); [self changed]; }
- (BKRenderer)renderer { return [_settings[@"renderer"] integerValue] == BKRendererPump ? BKRendererPump : BKRendererLayer; }
- (void)setRenderer:(BKRenderer)v { _settings[@"renderer"] = @(v); [self changed]; }
- (NSInteger)maxResolution { return [_settings[@"maxResolution"] integerValue]; }
- (void)setMaxResolution:(NSInteger)v { _settings[@"maxResolution"] = @(v); [self changed]; }
- (BOOL)keepPhoneAwake { return [_settings[@"keepPhoneAwake"] boolValue]; }
- (void)setKeepPhoneAwake:(BOOL)v { _settings[@"keepPhoneAwake"] = @(v); [self changed]; }

@end
