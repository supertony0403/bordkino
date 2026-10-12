#import "BKLog.h"

static const NSUInteger kMaxLines = 500;
static const unsigned long long kMaxFileBytes = 512 * 1024;

NSString *BKDataDirectory(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        dir = [support stringByAppendingPathComponent:@"Bordkino"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

@implementation BKLog

static NSMutableArray<NSString *> *sLines;
static dispatch_queue_t sQueue;
static NSDateFormatter *sFormatter;

+ (void)initialize {
    if (self != BKLog.class) return;
    sLines = [NSMutableArray new];
    sQueue = dispatch_queue_create("de.benzsw.bordkino.log", DISPATCH_QUEUE_SERIAL);
    sFormatter = [NSDateFormatter new];
    sFormatter.dateFormat = @"dd.MM. HH:mm:ss";
}

+ (NSString *)logFilePath {
    return [BKDataDirectory() stringByAppendingPathComponent:@"bordkino.log"];
}

+ (void)append:(NSString *)message {
    NSLog(@"[Bordkino] %@", message);
    NSString *line = [NSString stringWithFormat:@"%@ %@", [sFormatter stringFromDate:[NSDate date]], message];
    dispatch_async(sQueue, ^{
        [sLines addObject:line];
        if (sLines.count > kMaxLines) {
            [sLines removeObjectsInRange:NSMakeRange(0, sLines.count - kMaxLines)];
        }
        NSString *path = [self logFilePath];
        NSFileManager *fm = [NSFileManager defaultManager];
        unsigned long long size = [[fm attributesOfItemAtPath:path error:nil] fileSize];
        if (![fm fileExistsAtPath:path] || size > kMaxFileBytes) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    });
}

+ (NSArray<NSString *> *)recentLines {
    __block NSArray *copy;
    dispatch_sync(sQueue, ^{ copy = [sLines copy]; });
    return copy;
}

@end

void BKLogf(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [BKLog append:message];
}
