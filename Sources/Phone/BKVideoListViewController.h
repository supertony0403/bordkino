#import <UIKit/UIKit.h>
#import "BKModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^BKVideoListCompletion)(NSArray<BKVideo *> *items, NSString * _Nullable next, NSError * _Nullable error);
/// Loads a page. `continuation` is nil for the first page.
typedef void (^BKVideoListLoader)(NSString * _Nullable continuation, BKVideoListCompletion done);

/// Plays on the car screen when CarPlay is connected, otherwise full screen on the phone.
void BKPlayFromPhone(UIViewController *from, BKVideo *video);
void BKPlayInputFromPhone(UIViewController *from, NSString *input);
void BKPresentPhonePlayer(UIViewController *from);
/// Short, self-dismissing message.
void BKToast(UIViewController *from, NSString *message);

@interface BKVideoListViewController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title loader:(nullable BKVideoListLoader)loader;
@property (nonatomic, copy, nullable) BKVideoListLoader loader;
@property (nonatomic, copy) NSString *emptyText;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
