#import "BKExtractorUpdater.h"
#import "BKScriptHost.h"
#import "BKLog.h"

static NSString *const kUpdateURL = @"https://raw.githubusercontent.com/supertony0403/bordkino/main/js/extractor.js";
static NSString *const kLastCheckKey = @"BKExtractorLastCheck";
static const NSTimeInterval kCheckInterval = 24 * 3600;

@implementation BKExtractorUpdater

+ (NSString *)installedScriptPath {
    return [BKDataDirectory() stringByAppendingPathComponent:@"extractor.js"];
}

+ (NSInteger)compare:(NSString *)a with:(NSString *)b {
    NSArray *pa = [a componentsSeparatedByString:@"."], *pb = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0, y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x < y ? -1 : 1;
    }
    return 0;
}

+ (void)checkForUpdateForce:(BOOL)force completion:(void (^)(BOOL, NSString *))completion {
    void (^done)(BOOL, NSString *) = ^(BOOL updated, NSString *message) {
        BKLogf(@"Extractor-Update: %@", message);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(updated, message); });
    };
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDate *last = [defaults objectForKey:kLastCheckKey];
    if (!force && last && -[last timeIntervalSinceNow] < kCheckInterval) {
        if (completion) completion(NO, @"Kürzlich geprüft.");
        return;
    }
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:kUpdateURL]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (error || status != 200 || !data.length) {
            done(NO, error ? error.localizedDescription : [NSString stringWithFormat:@"Download fehlgeschlagen (HTTP %ld).", (long)status]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [defaults setObject:[NSDate date] forKey:kLastCheckKey]; });
        NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *version = source ? [BKScriptHost validatedVersionOfScript:source] : nil;
        if (!version) {
            done(NO, @"Neue Fassung besteht den Selbsttest nicht – nicht übernommen.");
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *current = [BKScriptHost shared].extractorVersion;
            if ([self compare:version with:current] <= 0) {
                done(NO, [NSString stringWithFormat:@"Aktuell (%@).", current]);
                return;
            }
            NSError *writeError = nil;
            if (![data writeToFile:[self installedScriptPath] options:NSDataWritingAtomic error:&writeError]) {
                done(NO, writeError.localizedDescription);
                return;
            }
            [[BKScriptHost shared] reload];
            done(YES, [NSString stringWithFormat:@"Aktualisiert auf %@.", version]);
        });
    }] resume];
}

@end
