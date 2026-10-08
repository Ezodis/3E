#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    NSMenu *menu=[NSMenu new];
    NSMenuItem *custom=[[NSMenuItem alloc] initWithTitle:@"Customize Controls..." action:NSSelectorFromString(@"customizeControls:") keyEquivalent:@""];
    [menu addItem:custom]; CleanMenu(menu);
    NSCAssert([menu.itemArray containsObject:custom],@"Retain the original controls menu item and action");
    NSView *form=[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,100)];
    NSTextField *type=[NSTextField labelWithString:@"Type:"]; type.frame=NSMakeRect(0,60,60,24); [form addSubview:type];
    NSPopUpButton *gesture=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(65,60,150,24)]; [gesture addItemsWithTitles:@[@"Glissando",@"No Glissando",@"Pitchbend"]]; [gesture selectItemAtIndex:2]; [form addSubview:gesture];
    NSPopUpButton *channel=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(65,20,150,24)]; for(int i=1;i<=16;i++) [channel addItemWithTitle:[@(i) stringValue]]; [channel selectItemAtIndex:6]; [form addSubview:channel];
    NSTextField *cc=[NSTextField textFieldWithString:@"74"]; cc.frame=NSMakeRect(230,20,80,24); [form addSubview:cc];
    NSCAssert(HidePianoGestureSetting(form) && gesture.hidden && type.hidden,@"Hide piano Type dropdown and its own label");
    NSCAssert(!channel.hidden && channel.indexOfSelectedItem==6 && !cc.hidden && [cc.stringValue isEqual:@"74"],@"Retain channel and all other native settings unchanged");
    NSCAssert(gesture.indexOfSelectedItem==2,@"Removing the dropdown must not change the piano's gesture mode");
    puts("Passed restored Customize Controls menu, gesture-only removal and unchanged MIDI channel/other fields.");
} return 0; }
