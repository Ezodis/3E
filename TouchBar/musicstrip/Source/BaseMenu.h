// The base app remains usable when macOS cannot load the optional Touch Bar APIs.
#import "../../../Shared/PhoneControl/MacHost/PhoneBarMenu.h"
static NSMenu *StripBaseMenu(id target,BOOL gestures) {
    NSMenu *menu=[NSMenu new];
    if(gestures) {
        NSMenuItem *touchTab=[[NSMenuItem alloc] initWithTitle:@"Touch Tab" action:NSSelectorFromString(@"toggleBaseTouchTab:") keyEquivalent:@""];
        touchTab.identifier=@"local.musicstrip.touchTabToggle";touchTab.target=target;[menu addItem:touchTab];
    }
    [menu addItem:ThreeEPhoneBarMenu(target)];
    NSMenuItem *touchBar=[[NSMenuItem alloc] initWithTitle:@"Touch Bar unavailable on this Mac" action:nil keyEquivalent:@""];
    touchBar.enabled=NO;[menu addItem:touchBar];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *updates=[[NSMenuItem alloc] initWithTitle:@"Downloads and updates…" action:NSSelectorFromString(@"baseUpdates:") keyEquivalent:@""];
    updates.target=target;[menu addItem:updates];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit 3£" action:NSSelectorFromString(@"quitBase:") keyEquivalent:@""];
    quit.target=target;[menu addItem:quit];return menu;
}
