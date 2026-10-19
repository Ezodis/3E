// The base app remains usable when macOS cannot load the optional Touch Bar APIs.
#import "../../../Shared/PhoneControl/MacHost/PhoneBarMenu.h"
static NSMenu *StripBaseMenu(id target,BOOL gestures) {
    NSMenu *menu=[NSMenu new];
    [menu addItem:ThreeEPhoneBarMenu(target)];
    if(gestures) {
        NSMenuItem *touchTab=[[NSMenuItem alloc] initWithTitle:@"Touch Tab" action:NSSelectorFromString(@"toggleBaseTouchTab:") keyEquivalent:@""];
        touchTab.identifier=@"local.musicstrip.touchTabToggle";touchTab.target=target;[menu addItem:touchTab];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *touchBar=[[NSMenuItem alloc] initWithTitle:@"Touch Bar unavailable on this Mac" action:nil keyEquivalent:@""];
    touchBar.enabled=NO;[menu addItem:touchBar];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *automatic=[[NSMenuItem alloc] initWithTitle:@"Automatically Install Updates" action:NSSelectorFromString(@"toggleBaseAutomaticUpdates:") keyEquivalent:@""];
    automatic.target=target; automatic.state=StripAutomaticUpdatesEnabled()?NSControlStateValueOn:NSControlStateValueOff; [menu addItem:automatic];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *restart=[[NSMenuItem alloc] initWithTitle:@"Restart" action:NSSelectorFromString(@"restartBase:") keyEquivalent:@""];
    restart.target=target;[menu addItem:restart];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit 3£" action:NSSelectorFromString(@"quitBase:") keyEquivalent:@""];
    quit.target=target;[menu addItem:quit];return menu;
}
