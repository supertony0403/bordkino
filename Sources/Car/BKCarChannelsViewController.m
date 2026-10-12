#import "BKCarChannelsViewController.h"
#import "BKCarGridViewController.h"
#import "BKLibrary.h"
#import "BKYouTube.h"

@implementation BKCarChannelsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Kanäle";
    self.tableView.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:1];
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"channel"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:BKLibraryDidChangeNotification object:nil];
    [self libraryChanged];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)libraryChanged {
    [self.tableView reloadData];
    if ([BKLibrary shared].channels.count) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [UILabel new];
    label.text = @"Noch keine Kanäle.\nIm Player auf das Personen-Symbol tippen\noder am Handy unter „Kanäle“ hinzufügen.";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.lightGrayColor;
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    self.tableView.backgroundView = label;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [BKLibrary shared].channels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel" forIndexPath:indexPath];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = [BKLibrary shared].channels[indexPath.row].title;
    content.textProperties.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    content.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    cell.contentConfiguration = content;
    cell.backgroundColor = UIColor.clearColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BKChannel *channel = [BKLibrary shared].channels[indexPath.row];
    NSString *channelId = channel.channelId;
    BKCarGridViewController *feed = [[BKCarGridViewController alloc] initWithLoader:^(NSString *continuation, BKVideoListCompletion done) {
        if (continuation) { done(@[], nil, nil); return; }
        [[BKYouTube shared] channelFeed:channelId completion:^(NSArray<BKVideo *> *items, NSError *error) { done(items, nil, error); }];
    } emptyText:@"Keine Videos."];
    feed.title = channel.title;
    [self.navigationController pushViewController:feed animated:YES];
}

@end
