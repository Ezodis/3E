#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/message.h>

@interface NSTouchBarItem (SystemTray)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static pid_t AbletonPID(void) {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
        if ([app.bundleIdentifier isEqualToString:@"com.ableton.live"]) return app.processIdentifier;
    return 0;
}

static BOOL ActOnAbleton(NSString *needle, NSNumber *value, BOOL press) {
    pid_t pid=AbletonPID(); if(!pid || !AXIsProcessTrusted()) return NO;
    AXUIElementRef app=AXUIElementCreateApplication(pid); if(!app) return NO;
    NSMutableArray *queue=[NSMutableArray arrayWithObject:(__bridge id)app]; BOOL acted=NO;
    while(queue.count && !acted) {
        AXUIElementRef node=(__bridge AXUIElementRef)queue.firstObject; [queue removeObjectAtIndex:0];
        for(NSString *key in @[(__bridge NSString *)kAXTitleAttribute,(__bridge NSString *)kAXDescriptionAttribute,(__bridge NSString *)kAXRoleDescriptionAttribute]) {
            CFTypeRef raw=NULL;
            if(AXUIElementCopyAttributeValue(node,(__bridge CFStringRef)key,&raw)==kAXErrorSuccess && raw && CFGetTypeID(raw)==CFStringGetTypeID()) {
                if([(__bridge NSString *)raw localizedCaseInsensitiveContainsString:needle]) {
                    if(press && AXUIElementPerformAction(node,kAXPressAction)==kAXErrorSuccess) acted=YES;
                    else if(value && AXUIElementSetAttributeValue(node,kAXValueAttribute,(__bridge CFTypeRef)value)==kAXErrorSuccess) acted=YES;
                }
            }
            if(raw) CFRelease(raw); if(acted) break;
        }
        CFTypeRef children=NULL;
        if(!acted && AXUIElementCopyAttributeValue(node,kAXChildrenAttribute,&children)==kAXErrorSuccess && children && CFGetTypeID(children)==CFArrayGetTypeID()) for(id child in (__bridge NSArray *)children) [queue addObject:child];
        if(children) CFRelease(children);
    }
    CFRelease(app); return acted;
}

@interface RecordView : NSView
@property (copy) void (^action)(NSString *);
@property BOOL tracking, held, recording;
@property CGFloat startX;
@property NSTimer *timer;
@end

@implementation RecordView
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame])) { self.wantsLayer=YES; self.layer.cornerRadius=5; [self setAccessibilityElement:YES]; [self setAccessibilityRole:NSAccessibilityButtonRole]; [self setAccessibilityLabel:@"Ableton Record"]; } return self; }
- (void)drawRect:(NSRect)rect { [[(self.recording ? NSColor.systemRedColor : [NSColor colorWithCalibratedRed:.45 green:.06 blue:.06 alpha:1]) colorWithAlphaComponent:.95] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5] fill]; [[NSColor.whiteColor colorWithAlphaComponent:.95] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((NSWidth(self.bounds)-12)/2,9,12,12)] fill]; }
- (void)fireHold { if(self.tracking&&!self.held){ self.held=YES; if(self.action)self.action(@"options"); } }
- (void)mouseDown:(NSEvent *)event { self.tracking=YES; self.held=NO; self.startX=[self convertPoint:event.locationInWindow fromView:nil].x; __weak RecordView *w=self; self.timer=[NSTimer scheduledTimerWithTimeInterval:.6 repeats:NO block:^(NSTimer *t){[w fireHold];}]; }
- (void)mouseDragged:(NSEvent *)event { CGFloat x=[self convertPoint:event.locationInWindow fromView:nil].x; if(fabs(x-self.startX)>12){[self.timer invalidate];self.timer=nil;} }
- (void)mouseUp:(NSEvent *)event { CGFloat x=[self convertPoint:event.locationInWindow fromView:nil].x; [self.timer invalidate];self.timer=nil; BOOL hold=self.held, swipe=fabs(x-self.startX)>=12; self.tracking=NO;self.held=NO; if(hold)return; if(self.action)self.action(swipe?(x>self.startX?@"arm-on":@"arm-off"):@"toggle"); }
- (BOOL)accessibilityPerformPress { if(self.action)self.action(@"toggle"); return YES; }
@end

@interface Delegate : NSObject <NSApplicationDelegate>
@property NSCustomTouchBarItem *item;
@property RecordView *view;
@property NSTouchBar *optionsBar;
@end

@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.view=[[RecordView alloc] initWithFrame:NSMakeRect(0,0,42,30)];
    __weak Delegate *w=self;
    self.view.action=^(NSString *action){
        if([action isEqualToString:@"options"]) { [w showOptions]; return; }
        if([action isEqualToString:@"toggle"]) { if(ActOnAbleton(@"Record",nil,YES)) w.view.recording=!w.view.recording; }
        else if([action isEqualToString:@"arm-on"]) w.view.recording=ActOnAbleton(@"Arm",@YES,YES)||ActOnAbleton(@"Record",@YES,YES);
        else if([action isEqualToString:@"arm-off"]) w.view.recording=!ActOnAbleton(@"Arm",@NO,NO);
        [w.view setNeedsDisplay:YES];
    };
    self.item=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.ableton.record.test"];
    self.item.customizationLabel=@"Ableton Record (test)"; self.item.view=self.view;
    [NSTouchBarItem addSystemTrayItem:self.item];
}
- (void)showOptions {
    NSArray *ids=@[@"Arrangement Record",@"Session Record",@"Punch In",@"Punch Out",@"Overdub",@"Count In"];
    self.optionsBar=[NSTouchBar new]; self.optionsBar.defaultItemIdentifiers=ids; self.optionsBar.customizationAllowedItemIdentifiers=ids; self.optionsBar.delegate=(id)self;
    SEL present=NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"); if([NSTouchBar respondsToSelector:present])((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,present,self.optionsBar,0,@"local.musicstrip.ableton.record.options.test");
}
- (NSTouchBarItem *)touchBar:(NSTouchBar *)bar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier { NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc]initWithIdentifier:identifier]; NSButton *button=[NSButton buttonWithTitle:identifier target:self action:@selector(option:)]; button.bezelStyle=NSBezelStyleRounded; item.view=button; return item; }
- (void)option:(NSButton *)button { ActOnAbleton(button.title,@YES,YES); SEL dismiss=NSSelectorFromString(@"dismissSystemModalTouchBar:"); if([NSTouchBar respondsToSelector:dismiss])((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,dismiss,button.window.touchBar); }
- (void)applicationWillTerminate:(NSNotification *)note { [self.view.timer invalidate]; if(self.item&&[NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)])[NSTouchBarItem removeSystemTrayItem:self.item]; }
@end

int main(int argc,const char **argv){ @autoreleasepool { NSApplication *app=NSApplication.sharedApplication; app.activationPolicy=NSApplicationActivationPolicyAccessory; Delegate *d=[Delegate new]; app.delegate=d; [app run]; } return 0; }
