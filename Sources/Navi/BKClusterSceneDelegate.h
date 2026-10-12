#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>

/// Instrument cluster (driver display) scene of the navigation variant.
/// Shows the current video only while the car is confirmed to stand still.
@interface BKClusterSceneDelegate : UIResponder <CPTemplateApplicationInstrumentClusterSceneDelegate, CPInstrumentClusterControllerDelegate>
@end
