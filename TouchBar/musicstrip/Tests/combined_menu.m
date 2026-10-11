#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface TestStatus : NSObject
@property NSMenu *menu;
@end
@implementation TestStatus
@end
@interface TestDelegate : NSObject <NSApplicationDelegate>
@property TestStatus *theItem;
@property BOOL editTouchBar;
@property BOOL editCCs;
@property BOOL touchbarShown;
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
    NSCAssert(toggle.state==NSControlStateValueOn && [toggle.title isEqual:@"Touch Tab"],@"Reflect actual enabled runtime state without changing the label");
    combinedGestureState=@"off"; CleanMenu(delegate.theItem.menu);
    NSCAssert(toggle.state==NSControlStateValueOff && delegate.theItem.menu.numberOfItems==1,@"Disabling never duplicates the menu item");
    combinedGestureState=@"permission"; CleanMenu(delegate.theItem.menu);
    NSCAssert([toggle.title isEqual:@"Touch Tab"] && toggle.toolTip.length>0,@"Permission explanation belongs in tooltip, not the toggle label");
    NSMenuItem *hide=[[NSMenuItem alloc] initWithTitle:@"Hide 3£" action:nil keyEquivalent:@""];
    [delegate.theItem.menu addItem:hide]; CleanMenu(delegate.theItem.menu); CleanMenu(delegate.theItem.menu);
    NSCAssert([hide.title isEqual:@"Touch Bar Midi"] && hide.target==MusicStripMidiBridge.class && hide.action==@selector(toggleMidi:),@"Use a stable checked MIDI toggle");
    delegate.touchbarShown=YES;
    NSCAssert([MusicStripMidiBridge validateMenuItem:hide] && hide.state==NSControlStateValueOn,@"Visible MIDI is checked");
    delegate.touchbarShown=NO;
    NSCAssert([MusicStripMidiBridge validateMenuItem:hide] && hide.state==NSControlStateValueOff,@"Hidden MIDI is unchecked");
    NSMenuItem *version=[[NSMenuItem alloc] initWithTitle:@"3£ (v. 3.0.11)" action:nil keyEquivalent:@""];
    [delegate.theItem.menu insertItem:version atIndex:0]; CleanMenu(delegate.theItem.menu); CleanMenu(delegate.theItem.menu);
    NSCAssert(delegate.theItem.menu.itemArray[1]==toggle && delegate.theItem.menu.itemArray[2]==hide,@"Touch Tab is the first action, followed by MIDI, without duplicates");
    combinedGestureState=@"on";
    NSCAssert([MusicStripMidiBridge validateMenuItem:toggle] && toggle.state==NSControlStateValueOn,@"Menu validation retains the actual running checkmark");
    NSMenuItem *surface=[[NSMenuItem alloc] initWithTitle:@"Control Surface Mode" action:NSSelectorFromString(@"changeMode:") keyEquivalent:@""];
    surface.target=delegate; [delegate.theItem.menu addItem:surface]; CleanMenu(delegate.theItem.menu);
    NSCAssert(surface.target==MusicStripMidiBridge.class && surface.action==@selector(toggleSurfaceMode:),@"Menu must bypass the vendor's separate surface bar");
    NSCAssert([MusicStripMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOff,@"Hidden MIDI does not claim the surface is active");
    recordController=[StripRecordController alloc]; recordController.activeMenuBar=[NSTouchBar new];
    NSCAssert([MusicStripMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOn,@"Menu follows the actual Record-hold bar");
    recordController.activeMenuBar=nil;
    NSCAssert([MusicStripMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOff,@"Returning from Record-hold clears the check");
    delegate.editCCs=YES; NSCAssert(![MusicStripMidiBridge validateMenuItem:surface],@"Do not interrupt control editing"); recordController=nil;
    puts("Passed combined gesture toggle target, runtime feedback and duplicate-free menu refresh. No tray icon or keyboard events created.");
} return 0; }
