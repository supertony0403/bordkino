#import "BKSettingsViewController.h"
#import "BKLibrary.h"
#import "BKDriveGuard.h"
#import "BKCarState.h"
#import "BKScriptHost.h"
#import "BKExtractorUpdater.h"
#import "BKPlayer.h"
#import "BKLogViewController.h"
#import "BKVideoListViewController.h"

typedef NS_ENUM(NSInteger, BKSection) { BKSectionPlayback, BKSectionCar, BKSectionModule, BKSectionDiagnostics, BKSectionCount };

static NSString *BKVariantName(void) {
#if BK_VARIANT_NAVI
    return @"Bordkino Navi (CarPlay-Vorlagen)";
#else
    return @"Bordkino (Touch-Oberfläche)";
#endif
}

@implementation BKSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Einstellungen";
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[BKLibraryDidChangeNotification, BKDriveGuardDidChangeNotification, BKCarStateDidChangeNotification]) {
        [nc addObserver:self.tableView selector:@selector(reloadData) name:name object:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)dealloc {
    if (self.isViewLoaded) [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return BKSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case BKSectionPlayback: return 5;
        case BKSectionCar: return 2;
        case BKSectionModule: return 2;
        case BKSectionDiagnostics: return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Wiedergabe", @"CarPlay", @"YouTube-Modul", @"Diagnose"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case BKSectionPlayback:
            return @"Fahrsperre: Ab etwa 10 km/h wird nur das Bild ausgeblendet, der Ton läuft weiter. Videos während der Fahrt anzusehen ist nach § 23 Abs. 1a StVO verboten.\n\nBleibt das Bild im Auto schwarz, Renderer auf „B“ stellen.";
        case BKSectionModule:
            return @"Das Modul wird täglich aus dem GitHub-Repo nachgeladen, wenn YouTube etwas ändert – ohne neue App-Version.";
    }
    return nil;
}

- (UITableViewCell *)cellWithText:(NSString *)text detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = text;
    cell.detailTextLabel.text = detail;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)switchCell:(NSString *)text on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [self cellWithText:text detail:nil];
    UISwitch *toggle = [UISwitch new];
    toggle.on = on;
    toggle.onTintColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)segmentCell:(NSString *)text items:(NSArray *)items selected:(NSInteger)selected action:(SEL)action {
    UITableViewCell *cell = [self cellWithText:text detail:nil];
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:items];
    segment.selectedSegmentIndex = selected;
    [segment addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [segment sizeToFit];
    cell.accessoryView = segment;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BKLibrary *library = [BKLibrary shared];
    switch (indexPath.section) {
        case BKSectionPlayback:
            switch (indexPath.row) {
                case 0: return [self switchCell:@"Fahrsperre" on:library.driveLockEnabled action:@selector(driveLockChanged:)];
                case 1: {
                    BKDriveGuard *guard = [BKDriveGuard shared];
                    NSString *detail = guard.locationAvailable
                        ? (guard.lastSpeedKmh >= 0 ? [NSString stringWithFormat:@"aktiv · %.0f km/h", guard.lastSpeedKmh] : @"erlaubt")
                        : @"fehlt – antippen";
                    UITableViewCell *cell = [self cellWithText:@"Standortzugriff" detail:detail];
                    if (!guard.locationAvailable) {
                        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                        cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    }
                    return cell;
                }
                case 2: {
                    NSInteger idx = library.maxResolution == 720 ? 1 : (library.maxResolution == 480 ? 2 : 0);
                    return [self segmentCell:@"Qualität" items:@[@"Auto", @"720p", @"480p"] selected:idx action:@selector(qualityChanged:)];
                }
                case 3: return [self segmentCell:@"Renderer" items:@[@"A", @"B"] selected:library.renderer action:@selector(rendererChanged:)];
                case 4: return [self switchCell:@"Handy wach & dunkel" on:library.keepPhoneAwake action:@selector(keepAwakeChanged:)];
            }
            break;
        case BKSectionCar:
            if (indexPath.row == 0) return [self cellWithText:@"Status" detail:[BKCarState shared].connected ? @"verbunden" : @"nicht verbunden"];
            return [self cellWithText:@"Diese App" detail:BKVariantName()];
        case BKSectionModule:
            if (indexPath.row == 0) {
                BKScriptHost *host = [BKScriptHost shared];
                return [self cellWithText:@"Version" detail:[NSString stringWithFormat:@"%@ (%@)", host.extractorVersion, host.extractorSource]];
            } else {
                UITableViewCell *cell = [self cellWithText:@"Jetzt aktualisieren" detail:nil];
                cell.textLabel.textColor = self.view.tintColor;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                return cell;
            }
        case BKSectionDiagnostics: {
            UITableViewCell *cell = [self cellWithText:indexPath.row == 0 ? @"Protokoll anzeigen" : @"Testvideo am Handy (Apple)" detail:nil];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = indexPath.row == 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
            return cell;
        }
    }
    return [self cellWithText:@"" detail:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == BKSectionPlayback && indexPath.row == 1 && ![BKDriveGuard shared].locationAvailable) {
        [[BKDriveGuard shared] start];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    } else if (indexPath.section == BKSectionModule && indexPath.row == 1) {
        [BKExtractorUpdater checkForUpdateForce:YES completion:^(BOOL updated, NSString *message) {
            BKToast(self, message);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
        }];
    } else if (indexPath.section == BKSectionDiagnostics && indexPath.row == 0) {
        [self.navigationController pushViewController:[BKLogViewController new] animated:YES];
    } else if (indexPath.section == BKSectionDiagnostics && indexPath.row == 1) {
        [[BKPlayer shared] playVideo:[BKVideo videoWithDirectURL:[NSURL URLWithString:BKTestStreamURL] title:@"Apple-Testvideo (BipBop)"]];
        BKPresentPhonePlayer(self);
    }
}

#pragma mark Actions

- (void)driveLockChanged:(UISwitch *)sender { [BKLibrary shared].driveLockEnabled = sender.on; }
- (void)keepAwakeChanged:(UISwitch *)sender { [BKLibrary shared].keepPhoneAwake = sender.on; }
- (void)rendererChanged:(UISegmentedControl *)sender { [BKLibrary shared].renderer = sender.selectedSegmentIndex == 1 ? BKRendererPump : BKRendererLayer; }
- (void)qualityChanged:(UISegmentedControl *)sender {
    [BKLibrary shared].maxResolution = sender.selectedSegmentIndex == 1 ? 720 : (sender.selectedSegmentIndex == 2 ? 480 : 0);
}

@end
