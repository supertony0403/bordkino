#import "BKLibraryViewController.h"
#import "BKVideoListViewController.h"
#import "BKLibrary.h"

@implementation BKLibraryViewController {
    BKVideoListViewController *_list;
    UISegmentedControl *_segment;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Bibliothek";
    _segment = [[UISegmentedControl alloc] initWithItems:@[@"Merkliste", @"Verlauf"]];
    _segment.selectedSegmentIndex = 0;
    [_segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _segment;

    __weak BKLibraryViewController *weakSelf = self;
    _list = [[BKVideoListViewController alloc] initWithTitle:@"Bibliothek" loader:^(NSString *continuation, BKVideoListCompletion done) {
        BKLibraryViewController *strongSelf = weakSelf;
        BOOL history = strongSelf && strongSelf->_segment.selectedSegmentIndex == 1;
        done(history ? [BKLibrary shared].history : [BKLibrary shared].favorites, nil, nil);
    }];
    [self addChildViewController:_list];
    _list.view.frame = self.view.bounds;
    _list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_list.view];
    [_list didMoveToParentViewController:self];
    [self segmentChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:BKLibraryDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)libraryChanged {
    [_list reload];
}

- (void)segmentChanged {
    BOOL history = _segment.selectedSegmentIndex == 1;
    _list.emptyText = history ? @"Noch nichts angesehen." : @"Noch nichts gemerkt.\nWische in einer Liste nach links und tippe „Merken“.";
    self.navigationItem.rightBarButtonItem = history
        ? [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)]
        : nil;
    [_list reload];
}

- (void)clearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Verlauf löschen?" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Löschen" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[BKLibrary shared] clearHistory];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
