#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "KeyboardTouchBarController.h"

static NSString *const Strip3TrayIdentifier=@"com.strip3.tray";

@interface Strip3AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) NSStatusItem *statusItem;
@property(nonatomic,strong) KeyboardTouchBarController *keyboardController;
@property(nonatomic,strong) NSWindow *mappingWindow;
@end

@implementation Strip3AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.keyboardController=[KeyboardTouchBarController new];
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title=@"Strip3£";
    NSMenu *menu=[NSMenu new];
    [menu addItemWithTitle:@"Show Keyboards" action:@selector(showKeyboards:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Configure Keyboard Mappings…" action:@selector(showMappings:) keyEquivalent:@","];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Strip3£" action:@selector(quit:) keyEquivalent:@"q"];
    self.statusItem.menu=menu;
}
- (void)showKeyboards:(id)sender {
    SEL present=NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    if([NSTouchBar respondsToSelector:present]) ((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,present,self.keyboardController.touchBar,0,Strip3TrayIdentifier);
}
- (void)showMappings:(id)sender {
    if(self.mappingWindow) { [self.mappingWindow makeKeyAndOrderFront:nil]; return; }
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,560,190)];
    NSArray *labels=@[@"Keyboard 1",@"Keyboard 2",@"Keyboard 3"];
    NSArray *keys=@[@"channel",@"baseNote",@"transpose",@"octaves",@"velocity"];
    for(NSUInteger row=0;row<3;row++) {
        KeyboardConfiguration *configuration=[[KeyboardConfigurationStore sharedStore] configurationAtIndex:row];
        NSTextField *name=[[NSTextField alloc] initWithFrame:NSMakeRect(20,145-row*45,110,24)]; name.tag=-1; name.stringValue=labels[row]; name.editable=NO; name.bezeled=NO; name.drawsBackground=NO; [content addSubview:name];
        for(NSUInteger column=0;column<5;column++) {
            NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(140+column*78,145-row*45,70,24)]; field.tag=(NSInteger)(row*10+column); field.identifier=keys[column];
            NSInteger value=column==0?configuration.midiChannel:column==1?configuration.baseNote:column==2?configuration.transpose:column==3?configuration.octaveCount:configuration.velocity; field.stringValue=[NSString stringWithFormat:@"%ld",(long)value]; [content addSubview:field];
        }
    }
    NSArray *headers=@[@"Channel",@"Base",@"Transpose",@"Octaves",@"Velocity"];
    for(NSUInteger i=0;i<headers.count;i++) { NSTextField *header=[[NSTextField alloc] initWithFrame:NSMakeRect(140+i*78,165,70,20)]; header.tag=-1; header.stringValue=headers[i]; header.editable=NO; header.bezeled=NO; header.drawsBackground=NO; [content addSubview:header]; }
    NSButton *save=[[NSButton alloc] initWithFrame:NSMakeRect(440,15,100,28)]; save.title=@"Save"; save.bezelStyle=NSBezelStyleRounded; save.target=self; save.action=@selector(saveMappings:); [content addSubview:save];
    self.mappingWindow=[[NSWindow alloc] initWithContentRect:content.frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO]; self.mappingWindow.title=@"Strip3£ Keyboard Mappings"; self.mappingWindow.contentView=content; [self.mappingWindow center]; [self.mappingWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)saveMappings:(NSButton *)sender {
    NSView *content=sender.superview;
    for(NSUInteger row=0;row<3;row++) { KeyboardConfiguration *configuration=[[[KeyboardConfigurationStore sharedStore] configurationAtIndex:row] copy]; for(NSTextField *field in content.subviews) if([field isKindOfClass:NSTextField.class] && field.tag>=0 && (NSUInteger)(field.tag/10)==row && field.tag%10<5) { NSInteger value=field.integerValue; switch(field.tag%10) { case 0: configuration.midiChannel=value; break; case 1: configuration.baseNote=value; break; case 2: configuration.transpose=value; break; case 3: configuration.octaveCount=value; break; case 4: configuration.velocity=value; break; } } [[KeyboardConfigurationStore sharedStore] setConfiguration:configuration atIndex:row]; }
    [self.mappingWindow close]; self.mappingWindow=nil; [self.keyboardController reloadKeyboardConfigurations];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(int argc,const char *argv[]) { @autoreleasepool { NSApplication *application=NSApplication.sharedApplication; application.activationPolicy=NSApplicationActivationPolicyAccessory; Strip3AppDelegate *delegate=[Strip3AppDelegate new]; application.delegate=delegate; [application run]; } return 0; }
