#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// German on-screen keyboard for the car display (CarPlay offers no system keyboard here).
@interface BKKeyboardView : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) void (^onText)(NSString *text);
@property (nonatomic, copy, nullable) void (^onSubmit)(NSString *text);
@end

NS_ASSUME_NONNULL_END
