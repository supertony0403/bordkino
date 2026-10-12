#import "BKYouTube.h"
#import "BKScriptHost.h"

static NSError *BKUnexpected(void) {
    return [NSError errorWithDomain:BKScriptErrorDomain code:5 userInfo:@{
        NSLocalizedDescriptionKey: @"Unerwartete Antwort des YouTube-Moduls.", BKScriptErrorCodeKey: @"BAD_RESULT" }];
}

@implementation BKYouTube

+ (instancetype)shared {
    static BKYouTube *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKYouTube new]; });
    return instance;
}

- (void)search:(NSString *)query continuation:(NSString *)continuation
    completion:(void (^)(NSArray<BKVideo *> *, NSString *, NSError *))completion {
    [[BKScriptHost shared] call:@"search" arguments:@[query ?: @"", continuation ?: [NSNull null]] completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:NSDictionary.class]) {
            completion(@[], nil, error ?: BKUnexpected());
            return;
        }
        NSString *next = [result[@"continuation"] isKindOfClass:NSString.class] ? result[@"continuation"] : nil;
        completion([BKVideo videosFromArray:result[@"items"]], next, nil);
    }];
}

- (void)resolve:(NSString *)input exclude:(NSArray<NSString *> *)exclude
     completion:(void (^)(BKStream *, NSError *))completion {
    [[BKScriptHost shared] call:@"resolve" arguments:@[input ?: @"", @{ @"exclude": exclude ?: @[] }] completion:^(id result, NSError *error) {
        BKStream *stream = error ? nil : [BKStream streamWithDictionary:result];
        completion(stream, stream ? nil : (error ?: BKUnexpected()));
    }];
}

- (void)channelFeed:(NSString *)channelId completion:(void (^)(NSArray<BKVideo *> *, NSError *))completion {
    [[BKScriptHost shared] call:@"channelFeed" arguments:@[channelId ?: @""] completion:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:NSArray.class]) {
            completion(@[], error ?: BKUnexpected());
            return;
        }
        completion([BKVideo videosFromArray:result], nil);
    }];
}

- (void)resolveChannel:(NSString *)input completion:(void (^)(BKChannel *, NSError *))completion {
    [[BKScriptHost shared] call:@"resolveChannel" arguments:@[input ?: @""] completion:^(id result, NSError *error) {
        BKChannel *channel = error ? nil : [BKChannel channelWithDictionary:result];
        completion(channel, channel ? nil : (error ?: BKUnexpected()));
    }];
}

@end
