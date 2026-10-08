#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface TestRecordController : StripRecordController
@property NSMutableArray *commands;
@property NSInteger holds;
@property NSMutableArray *menus;
@end
@implementation TestRecordController
- (instancetype)init { if((self=[super init])) { self.commands=[NSMutableArray new]; self.menus=[NSMutableArray new]; } return self; }
- (void)send:(NSString *)action { [self.commands addObject:action]; }
- (void)showOptions { self.holds++; }
- (void)showMenu:(NSString *)name { [self.menus addObject:name]; }
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestRecordController *controller=[TestRecordController new];
        StripRecordButton *button=controller.button;
        MidiNavigationButton *navigation=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        JoinRecordNavigation(controller,navigation,0,9);
        NSView *joined=controller.item.collapsedRepresentation;
        NSCAssert(joined.subviews.count==2 && joined.bounds.size.width==88,@"One joined control must contain two equal gesture regions");
        NSCAssert(button.frame.size.width==44 && navigation.frame.size.width==44 && navigation.frame.origin.x==44,@"Joined buttons must be equal-sized and gapless");
        CGFloat firstHue=navigation.presetHue;
        JoinRecordNavigation(controller,navigation,1,9);
        NSCAssert(navigation.presetHue!=firstHue,@"Changing MIDI preset must change its gradient color");
        joined=controller.item.collapsedRepresentation;
        NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,100) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed=NO;
        [host.contentView addSubview:joined];
        [joined.leadingAnchor constraintEqualToAnchor:host.contentView.leadingAnchor].active=YES;
        [joined.topAnchor constraintEqualToAnchor:host.contentView.topAnchor].active=YES;
        [host setContentSize:NSMakeSize(600,150)];
        [host.contentView layoutSubtreeIfNeeded];
        NSCAssert(NSEqualSizes(joined.bounds.size,NSMakeSize(88,30)),@"The native layout must not stretch the joined container");
        NSCAssert(NSEqualSizes(button.bounds.size,NSMakeSize(44,30)) && NSEqualSizes(navigation.bounds.size,NSMakeSize(44,30)),@"Both gesture regions must remain 44 by 30 after host resizing");
        ApplyRecordLight(button,YES,@{@"record":@NO,@"armed":@YES});
        NSCAssert(!button.recordLit && !button.bezelColor && [button.contentTintColor isEqual:NSColor.whiteColor],@"An armed track must not make the Record control red");
        ApplyRecordLight(button,YES,@{@"record":@YES,@"armed":@NO});
        NSCAssert(button.recordLit && [button.bezelColor isEqual:NSColor.systemRedColor],@"Live Record-on must make Record red");
        ApplyRecordLight(button,NO,@{@"record":@YES,@"armed":@YES});
        NSCAssert(!button.recordLit,@"A disconnected/stale Live state cannot keep Record red");
        NSCAssert(button.recordController==controller && controller.item.popoverTouchBar.itemIdentifiers.count==9,@"Joining must retain live command routing and the full transport panel");
        NSCAssert(controller.performanceMenus[@"loop"].popoverTouchBar.itemIdentifiers.count==8 && controller.performanceMenus[@"tempo"].popoverTouchBar.itemIdentifiers.count==4 && controller.performanceMenus[@"more"].popoverTouchBar.itemIdentifiers.count==7,@"Loop, tempo and recording options must all be reachable from the hold panel");
        controller.state=@{@"performance":@1,@"tempo":@128.5,@"playing":@YES,@"loop":@YES,@"beats_per_bar":@3,@"loop_length":@12,@"record":@NO,@"armed":@YES};
        [controller refreshButtonsConnected:YES];
        NSCAssert([controller.options[@"tempo"].title isEqual:@"128.5 BPM"] && [controller.options[@"loop"].title isEqual:@"4 bar"] && controller.options[@"play"].enabled,@"The panel must show real tempo, time-signature-aware loop length and playing state");
        controller.state=@{@"loop":@NO}; [controller refreshButtonsConnected:YES];
        NSCAssert(!controller.options[@"play"].enabled && !controller.options[@"tempo-up"].enabled && controller.options[@"loop"].enabled && [controller.options[@"tempo"].title isEqual:@"— BPM"],@"An old script must never expose apparently working new actions or invent a BPM");
        StripPerformanceButton *loop=(StripPerformanceButton *)controller.options[@"loop"];
        loop.enabled=YES; [loop beginAt:NSMakePoint(22,15) identity:nil]; [loop finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.commands isEqual:@[@"loop"]]),@"Loop tap must toggle the real loop");
        [controller.commands removeAllObjects];
        [loop beginAt:NSMakePoint(22,15) identity:nil]; [loop fireHold]; [loop fireHold];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        [loop finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.menus isEqual:@[@"loop"]]) && !controller.commands.count,@"Loop hold opens lengths once and release must not toggle Loop");
        StripPerformanceButton *tempo=(StripPerformanceButton *)controller.options[@"tempo"];
        tempo.enabled=YES; [tempo beginAt:NSMakePoint(10,15) identity:nil]; [tempo moveAt:NSMakePoint(40,15)]; [tempo finishAt:NSMakePoint(40,15)];
        NSCAssert(([controller.commands isEqual:@[@"tempo-up"]]),@"BPM swipe must issue one coarse tempo step, not open its menu");
        [controller.commands removeAllObjects];
        [tempo beginAt:NSMakePoint(22,15) identity:nil]; [tempo finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.menus isEqual:@[@"loop",@"tempo"]]),@"BPM tap must open fine/coarse tempo controls");
        tempo.enabled=NO; [tempo beginAt:NSMakePoint(10,15) identity:nil]; [tempo moveAt:NSMakePoint(40,15)]; [tempo finishAt:NSMakePoint(40,15)];
        NSCAssert(!controller.commands.count,@"Disabled performance controls cannot send Live commands");
        NSImage *preview=[[NSImage alloc] initWithSize:NSMakeSize(264,60)];
        [preview lockFocus];
        for(NSInteger i=0;i<3;i++) {
            [NSGraphicsContext saveGraphicsState];
            NSAffineTransform *position=[NSAffineTransform transform]; [position translateXBy:i*88 yBy:0]; [position concat];
            button.recordLit=i!=0; [button drawRect:button.bounds];
            NSAffineTransform *right=[NSAffineTransform transform]; [right translateXBy:44 yBy:0]; [right concat];
            navigation.presetHue=fmod(.58+i/9.0,1); [navigation drawRect:navigation.bounds];
            [NSGraphicsContext restoreGraphicsState];
        }
        [preview unlockFocus];
        NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:preview.TIFFRepresentation];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3pounds-record-navigation-preview.png" atomically:YES];
        PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
        PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch;
        for(NSString *action in @[@"record",@"arm-on",@"arm-off"]) {
            touch.point=NSMakePoint(22,15); event.phase=NSTouchPhaseBegan;
            [button touchesBeganWithEvent:(NSEvent *)event];
            touch.point=NSMakePoint([action isEqual:@"arm-on"] ? 50 : [action isEqual:@"arm-off"] ? -5 : 22,15);
            event.phase=NSTouchPhaseMoved; [button touchesMovedWithEvent:(NSEvent *)event];
            event.phase=NSTouchPhaseEnded; [button touchesEndedWithEvent:(NSEvent *)event];
        }
        NSCAssert(([controller.commands isEqual:@[@"record",@"arm-on",@"arm-off"]]),@"Physical touch events map to one correct command each");
        [controller.commands removeAllObjects];
        touch.point=NSMakePoint(22,15); event.phase=NSTouchPhaseBegan;
        [button touchesBeganWithEvent:(NSEvent *)event]; [button fireHold]; [button fireHold];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        event.phase=NSTouchPhaseEnded; [button touchesEndedWithEvent:(NSEvent *)event];
        NSCAssert(controller.holds==1 && controller.commands.count==0,@"Hold opens options once, release never starts recording");
        event.phase=NSTouchPhaseBegan; [button touchesBeganWithEvent:(NSEvent *)event];
        [button touchesCancelledWithEvent:(NSEvent *)event]; [button fireHold];
        event.phase=NSTouchPhaseEnded; [button touchesEndedWithEvent:(NSEvent *)event];
        NSCAssert(controller.commands.count==0,@"Cancelled touches do nothing");
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(23,25)];
        [button fireHold]; [button finishAt:NSMakePoint(23,25)];
        NSCAssert(controller.commands.count==0,@"Vertical motion is not a tap or horizontal swipe");
        puts("Passed performance menu structure/state/capability gating, Loop hold without release toggle, BPM tap/swipe, fixed joined layout, recording-only red and original Record gestures; no Live commands sent.");
    }
    return 0;
}
