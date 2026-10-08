#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface TestStatus : NSObject
@property NSMenu *menu;
@end
@implementation TestStatus
@end
@interface TestDelegate : NSObject <NSApplicationDelegate>
@property TestStatus *theItem;
@end
@implementation TestDelegate
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    TestDelegate *delegate=[TestDelegate new]; delegate.theItem=[TestStatus new]; delegate.theItem.menu=[NSMenu new]; NSApp.delegate=delegate;
    NSCAssert(StripCombinedRelease(),@"Run with STRIP_COMBINED_TOUCHTAB=1");
    CleanMenu(delegate.theItem.menu);
    NSCAssert(delegate.theItem.menu.numberOfItems==1,@"Add one gesture toggle to the existing menu, not another icon");
    NSMenuItem *toggle=delegate.theItem.menu.itemArray.firstObject;
    NSCAssert(toggle.target==MusicStripMidiBridge.class && toggle.action==@selector(toggleTouchTab:),@"Use the existing parent/helper pipe action");
    combinedGestureState=@"on"; CleanMenu(delegate.theItem.menu);
    NSCAssert(toggle.state==NSControlStateValueOn && [toggle.title isEqual:@"TouchTab Gestures"],@"Reflect actual enabled runtime state");
    combinedGestureState=@"off"; CleanMenu(delegate.theItem.menu);
    NSCAssert(toggle.state==NSControlStateValueOff && delegate.theItem.menu.numberOfItems==1,@"Disabling never duplicates the menu item");
    puts("Passed combined gesture toggle target, runtime feedback and duplicate-free menu refresh. No tray icon or keyboard events created.");
} return 0; }
