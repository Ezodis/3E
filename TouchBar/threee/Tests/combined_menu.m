#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
#import "../Source/BaseMenu.h"
#import "status_brand.m"
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
@property BOOL controlSurfadeMode;
@property NSMutableArray *allUserTouchbars;
@property NSTouchBar *mainTouchBar;
@property NSInteger userTouchbarNumber;
@end
@implementation TestDelegate
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    TestStatusBrand();
    TestDelegate *delegate=[TestDelegate new]; delegate.theItem=[TestStatus new]; delegate.theItem.menu=[NSMenu new]; NSApp.delegate=delegate;
    // Consolidation is stable on cold relaunch and count changes; unrelated
    // keyboard presets keep their own persistent bar identities.
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    NSArray *keys=@[DJEnabledKey,PresetCountPreference,@"ThreeEDJUnifiedSetV1"];
    NSMutableDictionary *prior=[NSMutableDictionary new];for(NSString *key in keys) if([prefs objectForKey:key]) prior[key]=[prefs objectForKey:key];
    NSMutableArray *raw=[NSMutableArray new];
    for(NSArray *ids in @[@[@"piano-original"],@[DJMixerID],@[DJPadsID],@[@"piano-personal"],@[@"other-personal"]]) { NSTouchBar *bar=[NSTouchBar new];bar.defaultItemIdentifiers=ids;bar.customizationAllowedItemIdentifiers=@[NativePianoID,DJPadsID];[raw addObject:bar]; }
    @try {
        [prefs setBool:YES forKey:DJEnabledKey];[prefs setInteger:4 forKey:PresetCountPreference];[prefs removeObjectForKey:@"ThreeEDJUnifiedSetV1"];
        delegate.allUserTouchbars=raw.mutableCopy;controlPresetCatalog=nil;InitializePresetCatalog();
        NSCAssert(([delegate.allUserTouchbars isEqual:@[raw[0],raw[1],raw[3]]]) && [prefs integerForKey:PresetCountPreference]==3,@"Only the generated pad bar leaves active navigation");
        delegate.allUserTouchbars=raw.mutableCopy;controlPresetCatalog=nil;InitializePresetCatalog();
        NSCAssert(([delegate.allUserTouchbars isEqual:@[raw[0],raw[1],raw[3]]]),@"Cold relaunch must not hide the personal preset or decrement count twice");
        ExtendPianoPalette(delegate);
        NSCAssert([delegate.allUserTouchbars[1] customizationAllowedItemIdentifiers].count>0 && ![[delegate.allUserTouchbars[1] customizationAllowedItemIdentifiers] containsObject:DJPadsID],@"Only the unified DJ tile remains in customization");
        StripPresetCountEditor *editor=[StripPresetCountEditor new];editor.stepper=[NSStepper new];editor.stepper.integerValue=4;editor.label=[NSTextField labelWithString:@""];[editor changeCount:nil];
        NSCAssert(delegate.allUserTouchbars.count==4 && delegate.allUserTouchbars.lastObject==raw[4],@"Changing preset count must not resurrect the retired generated bar");
    } @finally {
        for(NSString *key in keys) { if(prior[key]) [prefs setObject:prior[key] forKey:key];else [prefs removeObjectForKey:key]; }
        controlPresetCatalog=nil;delegate.allUserTouchbars=nil;
    }
    NSCAssert(StripCombinedRelease(),@"Build with -DSTRIP_TEST_EDITION_COMBINED=1");
    CleanMenu(delegate.theItem.menu);
    NSCAssert(delegate.theItem.menu.numberOfItems==15,@"Add gesture, App, Phone Bar, DJ setup, downloads, automatic-update and Restart controls to the existing menu");
    NSMenuItem *restart=delegate.theItem.menu.itemArray.lastObject;
    NSCAssert([restart.identifier isEqual:@"local.musicstrip.restart"] && [restart.title isEqual:@"Restart"] && restart.target==ThreeEMidiBridge.class && restart.action==@selector(restartAll:),@"Restart (update check + relaunch) is in the full menu, like Windows");
    NSMenuItem *phone=nil;
    for(NSMenuItem *item in delegate.theItem.menu.itemArray)if([item.identifier isEqual:@"local.musicstrip.phone"])phone=item;
    NSCAssert(phone!=nil,@"Phone Bar control is present");
    NSCAssert([phone.identifier isEqual:@"local.musicstrip.phone"] && [phone.title isEqual:@"Phone Bar"] && phone.view!=nil,@"Phone Bar is a bundled module in the existing menu");
    NSMenu *base=StripBaseMenu(delegate,YES);
    NSCAssert([base.itemArray[0].identifier isEqual:@"local.musicstrip.phone"] && [base.itemArray[1].identifier isEqual:@"local.musicstrip.touchTabToggle"],@"Base menu places Phone Bar before Touch Tab without Touch Bar interfaces");
    NSCAssert(!base.itemArray[2].enabled,@"Only the unavailable Touch Bar module is disabled");
    NSMenuItem *toggle=nil;
    for(NSMenuItem *item in delegate.theItem.menu.itemArray)if([item.identifier isEqual:@"local.musicstrip.touchTabToggle"])toggle=item;
    NSCAssert(toggle.target==ThreeEMidiBridge.class && toggle.action==@selector(toggleTouchTab:),@"Use the existing parent/helper pipe action");
    combinedGestureState=@"on"; CleanMenu(delegate.theItem.menu);
    NSCAssert(toggle.state==NSControlStateValueOn && [toggle.title isEqual:@"Touch Tab"],@"Reflect actual enabled runtime state without changing the label");
    combinedGestureState=@"off"; CleanMenu(delegate.theItem.menu);
    NSCAssert(toggle.state==NSControlStateValueOff && delegate.theItem.menu.numberOfItems==15,@"Disabling never duplicates the menu items");
    combinedGestureState=@"permission"; CleanMenu(delegate.theItem.menu);
    NSCAssert([toggle.title isEqual:@"Touch Tab"] && toggle.toolTip.length>0,@"Permission explanation belongs in tooltip, not the toggle label");
    NSMenuItem *hide=[[NSMenuItem alloc] initWithTitle:@"Hide 3£" action:nil keyEquivalent:@""];
    [delegate.theItem.menu addItem:hide]; CleanMenu(delegate.theItem.menu); CleanMenu(delegate.theItem.menu);
    NSCAssert([hide.title isEqual:@"Touch Bar Midi"] && hide.target==ThreeEMidiBridge.class && hide.action==@selector(toggleMidi:),@"Use a stable checked MIDI toggle");
    delegate.touchbarShown=YES;
    NSCAssert([ThreeEMidiBridge validateMenuItem:hide] && hide.state==NSControlStateValueOn,@"Visible MIDI is checked");
    delegate.touchbarShown=NO;
    NSCAssert([ThreeEMidiBridge validateMenuItem:hide] && hide.state==NSControlStateValueOff,@"Hidden MIDI is unchecked");
    NSMenuItem *version=[[NSMenuItem alloc] initWithTitle:@"3£ (v. 3.0.11)" action:nil keyEquivalent:@""];
    [delegate.theItem.menu insertItem:version atIndex:0]; CleanMenu(delegate.theItem.menu); CleanMenu(delegate.theItem.menu);
    NSMenuItem *apps=nil;
    for(NSMenuItem *item in delegate.theItem.menu.itemArray)if([item.identifier isEqual:@"local.musicstrip.appsToggle"])apps=item;
    NSCAssert(delegate.theItem.menu.itemArray[0]==version && delegate.theItem.menu.itemArray[1]==phone && delegate.theItem.menu.itemArray[2]==toggle && [delegate.theItem.menu.itemArray[3] isSeparatorItem] && delegate.theItem.menu.itemArray[4]==apps && delegate.theItem.menu.itemArray[5]==hide && hide.action==@selector(toggleMidi:),@"Phone Bar precedes Touch Tab and the existing rows remain in stable order without duplicates");
    NSCAssert(apps.target==ThreeEMidiBridge.class && apps.action==@selector(toggleApps:),@"App menu uses the existing main-process pipe");
    appsMenuVisible=YES; [ThreeEMidiBridge validateMenuItem:apps]; NSCAssert(apps.state==NSControlStateValueOn,@"Visible apps are checked");
    appsMenuVisible=NO; [ThreeEMidiBridge validateMenuItem:apps]; NSCAssert(apps.state==NSControlStateValueOff,@"Hidden apps are unchecked");
    combinedGestureState=@"on";
    NSCAssert([ThreeEMidiBridge validateMenuItem:toggle] && toggle.state==NSControlStateValueOn,@"Menu validation retains the actual running checkmark");
    NSMenuItem *surface=[[NSMenuItem alloc] initWithTitle:@"Control Surface Mode" action:NSSelectorFromString(@"changeMode:") keyEquivalent:@""];
    surface.target=delegate; [delegate.theItem.menu addItem:surface]; CleanMenu(delegate.theItem.menu);
    NSCAssert(surface.target==ThreeEMidiBridge.class && surface.action==@selector(toggleSurfaceMode:),@"Menu must bypass the vendor's separate surface bar");
    NSCAssert([ThreeEMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOff,@"Hidden MIDI does not claim the surface is active");
    recordController=[StripRecordController alloc]; recordController.activeMenuBar=[NSTouchBar new];
    NSCAssert([ThreeEMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOn,@"Menu follows the actual Record-hold bar");
    recordController.activeMenuBar=nil;
    NSCAssert([ThreeEMidiBridge validateMenuItem:surface] && surface.state==NSControlStateValueOff,@"Returning from Record-hold clears the check");
    delegate.editCCs=YES; NSCAssert(![ThreeEMidiBridge validateMenuItem:surface],@"Do not interrupt control editing"); recordController=nil;
    NSMenuItem *reset=[[NSMenuItem alloc] initWithTitle:@"Reset Touch Bar" action:nil keyEquivalent:@""];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit" action:nil keyEquivalent:@""];
    [delegate.theItem.menu addItem:quit]; [delegate.theItem.menu addItem:reset]; CleanMenu(delegate.theItem.menu); CleanMenu(delegate.theItem.menu);
    NSArray<NSMenuItem *> *rows=delegate.theItem.menu.itemArray; NSUInteger n=rows.count;
    NSCAssert(rows[n-3]==reset && [rows[n-2].identifier isEqual:@"local.musicstrip.restart"] && rows[n-1]==quit,@"Restart sits between Reset Touch Bar and Quit");
    NSUInteger restarts=0; for(NSMenuItem *row in rows) if([row.identifier isEqual:@"local.musicstrip.restart"]) restarts++;
    NSCAssert(restarts==1,@"Restart is never duplicated");
    for(NSString *action in @[@"install:",@"setup:",@"restore:"]) {
        NSUInteger count=0;
        for(NSMenuItem *row in rows) if(row.target==ThreeEDJActions.class && row.action==NSSelectorFromString(action)) count++;
        NSCAssert(count==1,@"Each DJ action survives menu refresh exactly once");
    }
    puts("Passed combined gesture toggle target, runtime feedback and duplicate-free menu refresh. No tray icon or keyboard events created.");
} return 0; }
