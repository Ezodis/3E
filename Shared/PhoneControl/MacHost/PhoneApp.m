// SPDX-License-Identifier: MIT
#import "PhoneControlMac.h"
#import "../../Brand/ThreeEBrand.h"
#import "PhoneBarMenu.h"
@interface PhoneAppDelegate:NSObject<NSApplicationDelegate>
@property ThreeEPhoneController *phone;
@property NSStatusItem *item;
@end
@implementation PhoneAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.phone=[ThreeEPhoneController new];
    self.phone.media=^(int action){
        int key=action==1?20:action==2?19:16;
        for(int state=0;state<2;state++){
            NSEvent *e=[NSEvent otherEventWithType:NSEventTypeSystemDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:8 data1:(key<<16)|((state?0xB:0xA)<<8) data2:-1];
            if(e.CGEvent)CGEventPost(kCGHIDEventTap,e.CGEvent);
        }
    };
    self.item=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];self.item.button.image=ThreeEBrandMenuImage();self.item.button.title=@"";self.item.button.toolTip=@"3£ Phone Bar";
    NSMenu *menu=[NSMenu new];
    [menu addItem:ThreeEPhoneBarMenu(self)];
    for(NSArray *row in @[@[@"Quit Phone Bar",@"quit:"]]){
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:row[0] action:NSSelectorFromString(row[1]) keyEquivalent:@""];item.target=self;[menu addItem:item];
    }
    self.item.menu=menu;
}
- (void)openPhone:(id)sender{[self.phone show];}
- (void)copyPhone:(id)sender{[self.phone copyLink:sender];}
- (void)stopPhone:(id)sender{[self.phone stop];}
- (void)quit:(id)sender{[NSApp terminate:nil];}
- (void)applicationWillTerminate:(NSNotification *)notification{[self.phone stop];}
@end
int main(int argc,const char **argv){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;PhoneAppDelegate *delegate=[PhoneAppDelegate new];app.delegate=delegate;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];[app run];}return 0;}
