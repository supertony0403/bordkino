#import "BKChannelsViewController.h"
#import "BKVideoListViewController.h"
#import "BKLibrary.h"
#import "BKYouTube.h"

@implementation BKChannelsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Kanäle";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addChannel)];
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
    } else {
        UILabel *label = [UILabel new];
        label.text = @"Noch keine Kanäle.\nTippe auf + und gib einen Kanal-Link oder @Namen ein – oder merke ihn im Player.";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.secondaryLabelColor;
        self.tableView.backgroundView = label;
    }
}

- (void)addChannel {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kanal hinzufügen"
        message:@"Link, @Name oder Kanal-ID (UC…)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"@tagesschau";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hinzufügen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *input = weakAlert.textFields.firstObject.text ?: @"";
        [[BKYouTube shared] resolveChannel:input completion:^(BKChannel *channel, NSError *error) {
            if (channel) {
                [[BKLibrary shared] addChannel:channel];
                BKToast(self, [NSString stringWithFormat:@"„%@“ hinzugefügt", channel.title]);
            } else {
                BKToast(self, error.localizedDescription ?: @"Kanal nicht gefunden");
            }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [BKLibrary shared].channels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel" forIndexPath:indexPath];
    BKChannel *channel = [BKLibrary shared].channels[indexPath.row];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = channel.title;
    content.image = [UIImage systemImageNamed:@"person.crop.circle"];
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BKChannel *channel = [BKLibrary shared].channels[indexPath.row];
    NSString *channelId = channel.channelId;
    BKVideoListViewController *feed = [[BKVideoListViewController alloc] initWithTitle:channel.title loader:^(NSString *continuation, BKVideoListCompletion done) {
        if (continuation) { done(@[], nil, nil); return; }
        [[BKYouTube shared] channelFeed:channelId completion:^(NSArray<BKVideo *> *items, NSError *error) { done(items, nil, error); }];
    }];
    [self.navigationController pushViewController:feed animated:YES];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    BKChannel *channel = [BKLibrary shared].channels[indexPath.row];
    [[BKLibrary shared] removeChannelWithId:channel.channelId];
}

@end
