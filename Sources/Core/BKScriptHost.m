#import "BKScriptHost.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import "BKExtractorUpdater.h"
#import "BKLog.h"

NSErrorDomain const BKScriptErrorDomain = @"BKScriptErrorDomain";
NSString *const BKScriptErrorCodeKey = @"BKCode";

static const NSTimeInterval kCallTimeout = 60;

static NSError *BKErrorFromJS(JSValue *value) {
    NSString *message = nil;
    NSString *code = @"JS_ERROR";
    if (value && !value.isUndefined && !value.isNull) {
        JSValue *msg = [value valueForProperty:@"message"];
        JSValue *c = [value valueForProperty:@"code"];
        message = (msg && !msg.isUndefined) ? [msg toString] : [value toString];
        if (c && !c.isUndefined && !c.isNull) code = [c toString];
    }
    return [NSError errorWithDomain:BKScriptErrorDomain code:1 userInfo:@{
        NSLocalizedDescriptionKey: message.length ? message : @"Unbekannter Fehler im Extractor.",
        BKScriptErrorCodeKey: code,
    }];
}

@interface BKScriptHost ()
@property (nonatomic, readwrite, copy) NSString *extractorVersion;
@property (nonatomic, readwrite, copy) NSString *extractorSource;
@end

@implementation BKScriptHost {
    dispatch_queue_t _queue;
    JSVirtualMachine *_vm;
    JSValue *_api;            // touched on _queue only
    NSURLSession *_session;
}

+ (instancetype)shared {
    static BKScriptHost *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [BKScriptHost new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("de.benzsw.bordkino.js", DISPATCH_QUEUE_SERIAL);
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.HTTPShouldSetCookies = NO;
        cfg.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        cfg.timeoutIntervalForRequest = 15;
        cfg.timeoutIntervalForResource = 30;
        cfg.waitsForConnectivity = NO;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _extractorVersion = @"–";
        _extractorSource = @"–";
        dispatch_async(_queue, ^{ [self loadScript]; });
    }
    return self;
}

#pragma mark Script loading (on _queue)

+ (JSContext *)newContextWithVM:(JSVirtualMachine *)vm {
    JSContext *ctx = vm ? [[JSContext alloc] initWithVirtualMachine:vm] : [JSContext new];
    ctx.name = @"Bordkino Extractor";
    ctx.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        BKLogf(@"JS-Ausnahme: %@", [exception toString]);
        context.exception = exception;
    };
    return ctx;
}

+ (nullable JSValue *)evaluateExtractor:(NSString *)source inContext:(JSContext *)ctx {
    [ctx evaluateScript:source withSourceURL:[NSURL URLWithString:@"bordkino://extractor.js"]];
    if (ctx.exception) return nil;
    JSValue *x = ctx[@"BordkinoExtractor"];
    if (!x || x.isUndefined || ![x hasProperty:@"create"]) return nil;
    return x;
}

+ (NSString *)validatedVersionOfScript:(NSString *)source {
    JSContext *ctx = [self newContextWithVM:nil];
    JSValue *x = [self evaluateExtractor:source inContext:ctx];
    if (!x) return nil;
    [ctx evaluateScript:@"var __stubHost = { fetch: function () { return Promise.reject(new Error('offline')); }, log: function () {} };"];
    JSValue *api = [x invokeMethod:@"create" withArguments:@[ctx[@"__stubHost"]]];
    if (ctx.exception || ![[api invokeMethod:@"selfTest" withArguments:@[]] toBool]) return nil;
    return [x[@"version"] toString];
}

- (void)loadScript {
    NSString *bundledPath = [[NSBundle mainBundle] pathForResource:@"extractor" ofType:@"js"];
    NSString *bundled = bundledPath ? [NSString stringWithContentsOfFile:bundledPath encoding:NSUTF8StringEncoding error:nil] : nil;
    NSString *installedPath = [BKExtractorUpdater installedScriptPath];
    NSString *installed = [[NSFileManager defaultManager] fileExistsAtPath:installedPath]
        ? [NSString stringWithContentsOfFile:installedPath encoding:NSUTF8StringEncoding error:nil] : nil;

    NSString *bundledVersion = bundled ? [BKScriptHost validatedVersionOfScript:bundled] : nil;
    NSString *installedVersion = installed ? [BKScriptHost validatedVersionOfScript:installed] : nil;

    NSString *source = bundled;
    NSString *origin = @"eingebaut";
    if (installedVersion && (!bundledVersion || [self compare:installedVersion with:bundledVersion] > 0)) {
        source = installed;
        origin = @"aktualisiert";
    } else if (installed && !installedVersion) {
        BKLogf(@"Aktualisierter Extractor fällt im Selbsttest durch – nutze eingebaute Fassung");
    }
    if (!source) {
        BKLogf(@"extractor.js fehlt im App-Bündel");
        _api = nil;
        return;
    }

    _vm = [JSVirtualMachine new];
    JSContext *ctx = [BKScriptHost newContextWithVM:_vm];
    JSValue *x = [BKScriptHost evaluateExtractor:source inContext:ctx];
    if (!x) {
        BKLogf(@"extractor.js lässt sich nicht laden");
        _api = nil;
        return;
    }
    JSValue *host = [JSValue valueWithNewObjectInContext:ctx];
    __weak BKScriptHost *weakSelf = self;
    host[@"fetch"] = ^JSValue *(JSValue *request) {
        return [weakSelf promiseForRequest:request context:[JSContext currentContext]];
    };
    host[@"log"] = ^(JSValue *text) {
        BKLogf(@"%@", [text toString]);
    };
    _api = [x invokeMethod:@"create" withArguments:@[host]];
    NSString *version = [x[@"version"] toString];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.extractorVersion = version;
        self.extractorSource = origin;
    });
    BKLogf(@"Extractor %@ geladen (%@)", version, origin);
}

- (NSInteger)compare:(NSString *)a with:(NSString *)b {
    NSArray *pa = [a componentsSeparatedByString:@"."];
    NSArray *pb = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0;
        NSInteger y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x < y ? -1 : 1;
    }
    return 0;
}

- (void)reload {
    dispatch_async(_queue, ^{ [self loadScript]; });
}

#pragma mark host.fetch (on _queue)

- (JSValue *)promiseForRequest:(JSValue *)request context:(JSContext *)ctx {
    NSDictionary *r = [request toDictionary];
    NSString *urlString = [r[@"url"] isKindOfClass:NSString.class] ? r[@"url"] : @"";
    NSURL *url = [NSURL URLWithString:urlString];
    dispatch_queue_t queue = _queue;
    NSURLSession *session = _session;
    return [JSValue valueWithNewPromiseInContext:ctx fromExecutor:^(JSValue *resolve, JSValue *reject) {
        if (!url || !url.scheme.length) {
            [reject callWithArguments:@[[JSValue valueWithNewErrorFromMessage:@"Ungültige URL" inContext:ctx]]];
            return;
        }
        NSMutableURLRequest *mr = [NSMutableURLRequest requestWithURL:url];
        mr.HTTPMethod = [r[@"method"] isKindOfClass:NSString.class] ? r[@"method"] : @"GET";
        NSDictionary *headers = [r[@"headers"] isKindOfClass:NSDictionary.class] ? r[@"headers"] : @{};
        [headers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [mr setValue:[value description] forHTTPHeaderField:[key description]];
        }];
        if ([r[@"body"] isKindOfClass:NSString.class]) {
            mr.HTTPBody = [r[@"body"] dataUsingEncoding:NSUTF8StringEncoding];
        }
        [[session dataTaskWithRequest:mr completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(queue, ^{
                if (error) {
                    [reject callWithArguments:@[[JSValue valueWithNewErrorFromMessage:error.localizedDescription inContext:ctx]]];
                    return;
                }
                NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                NSString *body = data.length ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                                ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding]) : @"";
                [resolve callWithArguments:@[@{
                    @"status": @(http ? http.statusCode : 0),
                    @"body": body ?: @"",
                    @"url": response.URL.absoluteString ?: urlString,
                }]];
            });
        }] resume];
    }];
}

#pragma mark Calls

- (void)call:(NSString *)method arguments:(NSArray *)arguments completion:(void (^)(id, NSError *))completion {
    dispatch_async(_queue, ^{
        __block BOOL finished = NO;
        void (^finish)(id, NSError *) = ^(id result, NSError *error) {
            // Always on _queue, so `finished` needs no lock.
            if (finished) return;
            finished = YES;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result, error); });
        };
        JSValue *api = self->_api;
        if (!api) {
            finish(nil, [NSError errorWithDomain:BKScriptErrorDomain code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"YouTube-Modul nicht geladen (siehe Protokoll).", BKScriptErrorCodeKey: @"NOT_LOADED" }]);
            return;
        }
        JSContext *ctx = api.context;
        JSValue *promise = [api invokeMethod:method withArguments:arguments];
        if (ctx.exception) {
            NSError *e = BKErrorFromJS(ctx.exception);
            ctx.exception = nil;
            finish(nil, e);
            return;
        }
        if (!promise || promise.isUndefined || ![promise hasProperty:@"then"]) {
            finish(nil, [NSError errorWithDomain:BKScriptErrorDomain code:3 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Extractor kennt „%@“ nicht.", method], BKScriptErrorCodeKey: @"NO_METHOD" }]);
            return;
        }
        id onFulfilled = ^(JSValue *value) { finish([value toObject], nil); };
        id onRejected = ^(JSValue *reason) { finish(nil, BKErrorFromJS(reason)); };
        [promise invokeMethod:@"then" withArguments:@[onFulfilled, onRejected]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCallTimeout * NSEC_PER_SEC)), self->_queue, ^{
            finish(nil, [NSError errorWithDomain:BKScriptErrorDomain code:4 userInfo:@{
                NSLocalizedDescriptionKey: @"Zeitüberschreitung beim Laden von YouTube.", BKScriptErrorCodeKey: @"TIMEOUT" }]);
        });
    });
}

@end
