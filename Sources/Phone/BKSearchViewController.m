#import "BKSearchViewController.h"
#import "BKVideoListViewController.h"
#import "BKYouTube.h"
#import "BKLibrary.h"

/// True for things that should be played directly instead of searched.
static BOOL BKLooksLikeLink(NSString *text) {
    NSString *lower = text.lowercaseString;
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower containsString:@"youtu.be/"] || [lower containsString:@"youtube.com/"];
}

@interface BKSearchViewController () <UISearchBarDelegate>
@end

@implementation BKSearchViewController {
    BKVideoListViewController *_list;
    UISearchController *_search;
    NSString *_query;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Suche";
    _list = [[BKVideoListViewController alloc] initWithTitle:@"Suche" loader:nil];
    _list.emptyText = @"Suche nach Videos oder füge einen YouTube-Link ein.\n\nZuletzt gesehen findest du unter „Bibliothek“.";
    [self addChildViewController:_list];
    _list.view.frame = self.view.bounds;
    _list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_list.view];
    [_list didMoveToParentViewController:self];

    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"YouTube durchsuchen oder Link einfügen";
    _search.searchBar.delegate = self;
    _search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.clipboard"]
        style:UIBarButtonItemStylePlain target:self action:@selector(pasteLink)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Link aus der Zwischenablage abspielen";
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *text = [searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return;
    [searchBar resignFirstResponder];
    if (BKLooksLikeLink(text)) {
        BKPlayInputFromPhone(self, text);
        return;
    }
    _query = text;
    NSString *query = text;
    _list.loader = ^(NSString *continuation, BKVideoListCompletion done) {
        [[BKYouTube shared] search:query continuation:continuation completion:done];
    };
    _list.emptyText = [NSString stringWithFormat:@"Keine Treffer für „%@“.", text];
    [_list reload];
}

- (void)pasteLink {
    NSString *text = [UIPasteboard generalPasteboard].string;   // iOS asks for permission here
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length && BKLooksLikeLink(text)) {
        BKPlayInputFromPhone(self, text);
    } else {
        BKToast(self, @"Kein Link in der Zwischenablage");
    }
}

@end
