#import "KeyboardTouchBarController.h"
#import "KeyboardTouchBarView.h"
#import "AbletonRecordControl.h"
#import "AbletonAccessibility.h"
#import <objc/message.h>

static NSString *const Keyboard1ID=@"com.strip3.keyboard.1";
static NSString *const Keyboard2ID=@"com.strip3.keyboard.2";
static NSString *const Keyboard3ID=@"com.strip3.keyboard.3";
static NSString *const RecordID=@"com.strip3.ableton.record";
static NSArray<NSString *> *RecordOptionIDs(void) { return @[@"arrangement",@"session",@"punch-in",@"punch-out",@"overdub",@"count-in"]; }

@implementation KeyboardTouchBarController {
    NSTouchBar *_touchBar;
    Strip3MidiOutput *_midiOutput;
    NSArray<NSString *> *_keyboardIDs;
}
- (instancetype)init {
    if((self=[super init])) {
        _keyboardIDs=@[Keyboard1ID,Keyboard2ID,Keyboard3ID,RecordID]; _midiOutput=[Strip3MidiOutput new];
        _touchBar=[NSTouchBar new]; _touchBar.delegate=self; _touchBar.customizationIdentifier=@"com.strip3.keyboard-layout";
        _touchBar.defaultItemIdentifiers=@[RecordID,Keyboard1ID,Keyboard2ID,Keyboard3ID]; _touchBar.customizationAllowedItemIdentifiers=_keyboardIDs;
    }
    return self;
}
- (NSTouchBar *)touchBar { return _touchBar; }
- (void)reloadKeyboardConfigurations { _touchBar.defaultItemIdentifiers=@[RecordID,Keyboard1ID,Keyboard2ID,Keyboard3ID]; }
- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if([RecordOptionIDs() containsObject:identifier]) {
        NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        NSButton *button=[NSButton buttonWithTitle:identifier target:self action:@selector(recordOption:)]; button.identifier=identifier; button.bezelStyle=NSBezelStyleRounded; button.bordered=NO; item.view=button; item.customizationLabel=identifier; return item;
    }
    if([identifier isEqualToString:RecordID]) {
        NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        AbletonRecordControl *control=[[AbletonRecordControl alloc] initWithFrame:NSMakeRect(0,0,55,30)]; control.abletonActive=Strip3AbletonIsRunning(); __weak AbletonRecordControl *weakControl=control;
        control.action=^(NSString *action){
            if([action isEqualToString:@"record-on"]) { if(Strip3AbletonSetRecord(YES)) weakControl.recording=YES; }
            else if([action isEqualToString:@"record-off"]) { if(Strip3AbletonSetRecord(NO)) weakControl.recording=NO; }
            else if([action isEqualToString:@"toggle"]) { if(Strip3AbletonToggleRecord()) weakControl.recording=!weakControl.recording; }
            else if([action isEqualToString:@"options"]) [self showRecordOptions];
        }; item.view=control; item.customizationLabel=@"Ableton Record"; return item;
    }
    NSUInteger index=[_keyboardIDs indexOfObject:identifier]; if(index==NSNotFound || index>=3) return nil;
    NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    KeyboardTouchBarView *view=[[KeyboardTouchBarView alloc] initWithFrame:NSMakeRect(0,0,NSWidth(NSScreen.mainScreen.frame)/3.0,30)];
    view.midiOutput=_midiOutput; view.configuration=[[KeyboardConfigurationStore sharedStore] configurationAtIndex:index]; item.view=view; item.customizationLabel=view.configuration.name;
    return item;
}
- (void)showRecordOptions {
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=self; bar.customizationIdentifier=@"com.strip3.ableton.record-options"; bar.defaultItemIdentifiers=RecordOptionIDs(); bar.customizationAllowedItemIdentifiers=RecordOptionIDs();
    SEL present=NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"); if([NSTouchBar respondsToSelector:present]) ((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,present,bar,0,@"com.strip3.ableton.options");
}
- (void)recordOption:(NSButton *)sender { Strip3AbletonPerformOption(sender.identifier); SEL dismiss=NSSelectorFromString(@"dismissSystemModalTouchBar:"); if([NSTouchBar respondsToSelector:dismiss]) ((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,dismiss,sender.window.touchBar); }
@end
