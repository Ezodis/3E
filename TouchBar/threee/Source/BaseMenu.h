// The base app remains usable when macOS cannot load the optional Touch Bar APIs.
#import "../../../Shared/PhoneControl/MacHost/PhoneBarMenu.h"
static NSMenu *StripBaseMenu(id target,BOOL gestures) {
    NSMenu *menu=[NSMenu new];
    NSMenuItem *phone=ThreeEPhoneBarMenu(target);
    if(!StripHasModule(@"phone")) { phone.title=@"Phone Bar — Install…"; phone.state=NSControlStateValueOff; }
    [menu addItem:phone];
    if(YES) {
        NSMenuItem *touchTab=[[NSMenuItem alloc] initWithTitle:StripHasModule(@"touchtab")?@"Touch Tab":@"Touch Tab — Install…" action:NSSelectorFromString(@"toggleBaseTouchTab:") keyEquivalent:@""];
        touchTab.identifier=@"local.musicstrip.touchTabToggle";touchTab.target=target;[menu addItem:touchTab];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *touchBar=[[NSMenuItem alloc] initWithTitle:StripHasModule(@"touchbar")?@"Touch Bar unavailable on this Mac":@"Touch Bar — Install…" action:StripHasModule(@"touchbar")?nil:NSSelectorFromString(@"installBaseTouchBar:") keyEquivalent:@""];
    touchBar.target=target; touchBar.enabled=!StripHasModule(@"touchbar");[menu addItem:touchBar];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *automatic=[[NSMenuItem alloc] initWithTitle:@"Automatically Install Updates" action:NSSelectorFromString(@"toggleBaseAutomaticUpdates:") keyEquivalent:@""];
    automatic.target=target; automatic.state=StripAutomaticUpdatesEnabled()?NSControlStateValueOn:NSControlStateValueOff; [menu addItem:automatic];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:StripModuleSettingsMenu()];
    NSMenuItem *restart=[[NSMenuItem alloc] initWithTitle:@"Restart" action:NSSelectorFromString(@"restartBase:") keyEquivalent:@""];
    restart.target=target;[menu addItem:restart];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit 3£" action:NSSelectorFromString(@"quitBase:") keyEquivalent:@""];
    quit.target=target;[menu addItem:quit];return menu;
}
