#import "BKLogViewController.h"
#import "BKLog.h"

@implementation BKLogViewController {
    UITextView *_text;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Protokoll";
    _text = [[UITextView alloc] initWithFrame:self.view.bounds];
    _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _text.editable = NO;
    _text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.view addSubview:_text];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)],
    ];
    [self refresh];
}

- (void)refresh {
    NSArray *lines = [BKLog recentLines];
    _text.text = lines.count ? [lines componentsJoinedByString:@"\n"] : @"(leer)";
    [_text scrollRangeToVisible:NSMakeRange(_text.text.length, 0)];
}

- (void)share {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[_text.text ?: @""] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:share animated:YES completion:nil];
}

@end
