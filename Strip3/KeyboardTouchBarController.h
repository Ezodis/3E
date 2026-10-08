#import <AppKit/AppKit.h>
#import "KeyboardConfiguration.h"

/// Touch Bar delegate exposing three distinct, customizable keyboard items.
@interface KeyboardTouchBarController : NSObject <NSTouchBarDelegate>
@property(nonatomic, readonly) NSTouchBar *touchBar;
- (void)reloadKeyboardConfigurations;
@end
