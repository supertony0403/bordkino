#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Root of the Stark car UI: sidebar + content, player overlay on top.
@interface BKCarRootViewController : UIViewController
- (void)showPlayer;
@end

/// Large car-friendly button with symbol and caption.
UIButton *BKCarButton(NSString *symbol, NSString *title, CGFloat pointSize);

NS_ASSUME_NONNULL_END
