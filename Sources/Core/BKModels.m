#import "BKModels.h"

static NSString *BKString(id value) {
    return [value isKindOfClass:NSString.class] ? value : ([value respondsToSelector:@selector(stringValue)] ? [value stringValue] : @"");
}

@implementation BKVideo

+ (instancetype)videoWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    BKVideo *v = [BKVideo new];
    v.videoId = BKString(d[@"videoId"]);
    NSString *direct = BKString(d[@"directURL"]);
    if (direct.length) v.directURL = [NSURL URLWithString:direct];
    if (!v.videoId.length && !v.directURL) return nil;
    v.title = BKString(d[@"title"]);
    v.channel = BKString(d[@"channel"]);
    v.channelId = BKString(d[@"channelId"]);
    v.durationText = BKString(d[@"durationText"]);
    v.subtitle = BKString(d[@"subtitle"]);
    v.durationSeconds = [d[@"durationSeconds"] respondsToSelector:@selector(integerValue)] ? [d[@"durationSeconds"] integerValue] : 0;
    v.isLive = [d[@"isLive"] respondsToSelector:@selector(boolValue)] && [d[@"isLive"] boolValue];
    NSString *thumb = BKString(d[@"thumbnail"]);
    if (thumb.length) v.thumbnailURL = [NSURL URLWithString:thumb];
    return v;
}

+ (instancetype)videoWithDirectURL:(NSURL *)url title:(NSString *)title {
    BKVideo *v = [BKVideo new];
    v.videoId = @"";
    v.directURL = url;
    v.title = title.length ? title : (url.lastPathComponent ?: url.absoluteString);
    v.channel = url.host ?: @"";
    v.channelId = @"";
    v.durationText = @"";
    v.subtitle = @"";
    return v;
}

+ (NSArray<BKVideo *> *)videosFromArray:(NSArray *)array {
    NSMutableArray *out = [NSMutableArray new];
    if (![array isKindOfClass:NSArray.class]) return out;
    for (id item in array) {
        BKVideo *v = [BKVideo videoWithDictionary:item];
        if (v) [out addObject:v];
    }
    return out;
}

- (instancetype)init {
    if ((self = [super init])) {
        _videoId = _title = _channel = _channelId = _durationText = _subtitle = @"";
    }
    return self;
}

- (NSString *)identifier {
    return self.videoId.length ? self.videoId : (self.directURL.absoluteString ?: @"");
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [@{
        @"videoId": self.videoId ?: @"",
        @"title": self.title ?: @"",
        @"channel": self.channel ?: @"",
        @"channelId": self.channelId ?: @"",
        @"durationText": self.durationText ?: @"",
        @"subtitle": self.subtitle ?: @"",
        @"durationSeconds": @(self.durationSeconds),
        @"isLive": @(self.isLive),
    } mutableCopy];
    if (self.thumbnailURL) d[@"thumbnail"] = self.thumbnailURL.absoluteString;
    if (self.directURL) d[@"directURL"] = self.directURL.absoluteString;
    return d;
}

- (id)copyWithZone:(NSZone *)zone {
    return [BKVideo videoWithDictionary:[self dictionaryRepresentation]];
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:BKVideo.class] && [[object identifier] isEqualToString:self.identifier];
}

- (NSUInteger)hash {
    return self.identifier.hash;
}

@end

@implementation BKStream

+ (instancetype)streamWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSURL *url = [NSURL URLWithString:BKString(d[@"url"])];
    BKVideo *video = [BKVideo videoWithDictionary:d[@"video"]];
    if (!url || !video) return nil;
    BKStream *s = [BKStream new];
    s.url = url;
    s.kind = BKString(d[@"kind"]);
    s.client = BKString(d[@"client"]);
    s.userAgent = BKString(d[@"userAgent"]);
    s.video = video;
    return s;
}

@end

@implementation BKChannel

+ (instancetype)channelWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSString *cid = BKString(d[@"channelId"]);
    if (!cid.length) return nil;
    BKChannel *c = [BKChannel new];
    c.channelId = cid;
    NSString *title = BKString(d[@"title"]);
    c.title = title.length ? title : cid;
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{ @"channelId": self.channelId ?: @"", @"title": self.title ?: @"" };
}

@end
