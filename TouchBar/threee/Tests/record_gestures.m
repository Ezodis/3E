#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface TestRecordController : StripRecordController
@property NSMutableArray *commands;
@property NSInteger holds;
@property NSMutableArray *menus;
@property NSMutableArray<NSNumber *> *tempoTargets;
@property BOOL surfaceMode;
@property NSMutableArray<NSDictionary *> *payloads;
@end
@implementation TestRecordController
- (instancetype)init { if((self=[super init])) { self.commands=[NSMutableArray new]; self.menus=[NSMutableArray new]; self.tempoTargets=[NSMutableArray new]; self.payloads=[NSMutableArray new]; } return self; }
- (void)setTempoFromDrag:(double)tempo { [self.tempoTargets addObject:@(tempo)]; }
- (void)send:(NSString *)action { [self.commands addObject:action]; }
- (void)send:(NSString *)action payload:(NSDictionary *)payload { [self.commands addObject:action]; [self.payloads addObject:payload]; }
- (NSArray<NSNumber *> *)selectedTrackIndicesForSwipe { return @[@0,@1]; }
- (void)showOptions { self.holds++; }
- (void)showMenu:(NSString *)name { [self.menus addObject:name]; }
- (BOOL)isControlSurfaceMode { return self.surfaceMode; }
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSCAssert([RecordTrackNameFromAXTitle(@"20-Bandøledu, Armed") isEqual:@"20-Bandøledu"],@"Armed accessibility labels match their stable Live track names");
        TestRecordController *controller=[TestRecordController new];
        StripRecordButton *button=controller.button;
        button.frame=NSMakeRect(0,0,32,30);
        MidiNavigationButton *navigation=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        NSButton *close=[NSButton buttonWithTitle:@"X" target:nil action:nil];
        NSView *joined=JoinCloseNavigation(close,navigation,0,9);
        button.standaloneRecord=YES;
        NSCAssert(joined.subviews.count==2 && joined.bounds.size.width==76,@"Navigation joins the unchanged close slot");
        [navigation beginAt:NSMakePoint(22,15) identity:nil]; [navigation fireHold];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        NSCAssert(navigation.held && controller.holds==0,@"Holding preset navigation no longer opens Control Surface or Record options");
        [navigation finishAt:NSMakePoint(22,15)];
        NSCAssert(close.frame.size.width==32 && navigation.frame.size.width==44 && navigation.frame.origin.x==32,@"The X position is unchanged; navigation is immediately beside it");
        CGFloat firstHue=navigation.presetHue;
        joined=JoinCloseNavigation(close,navigation,1,9);
        NSCAssert(navigation.presetHue!=firstHue,@"Changing MIDI preset must change its gradient color");
        NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,100) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed=NO;
        [host.contentView addSubview:joined];
        [joined.leadingAnchor constraintEqualToAnchor:host.contentView.leadingAnchor].active=YES;
        [joined.topAnchor constraintEqualToAnchor:host.contentView.topAnchor].active=YES;
        [host setContentSize:NSMakeSize(600,150)];
        [host.contentView layoutSubtreeIfNeeded];
        NSCAssert(NSEqualSizes(joined.bounds.size,NSMakeSize(76,30)),@"The native layout must not stretch the joined container");
        NSCAssert(NSEqualSizes(close.bounds.size,NSMakeSize(32,30)) && NSEqualSizes(navigation.bounds.size,NSMakeSize(44,30)),@"The X and navigation retain their fixed sizes after host resizing");
        ApplyRecordLight(button,YES,@{@"record":@NO,@"armed":@YES});
        NSCAssert(!button.recordLit && !button.bezelColor && [button.contentTintColor isEqual:NSColor.whiteColor],@"An armed track must not make the Record control red");
        ApplyRecordLight(button,YES,@{@"record":@YES,@"armed":@NO});
        NSCAssert(button.recordLit && [button.bezelColor isEqual:NSColor.systemRedColor],@"Live Record-on must make Record red");
        ApplyRecordLight(button,NO,@{@"record":@YES,@"armed":@YES});
        NSCAssert(!button.recordLit,@"A disconnected/stale Live state cannot keep Record red");
        NSCAssert(button.recordController==controller && [controller.item isKindOfClass:NSCustomTouchBarItem.class] && controller.item.view==button && controller.optionsTouchBar.itemIdentifiers.count==3 && !controller.options[@"play"] && !controller.options[@"stop"] && !controller.options[@"tap-tempo"],@"Outer Record must be a plain custom item so AppKit cannot consume its gestures for a native popover");
        NSCAssert(controller.performanceMenus[@"loop"].popoverTouchBar.itemIdentifiers.count==8 && controller.performanceMenus[@"tempo"].popoverTouchBar.itemIdentifiers.count==4 && controller.performanceMenus[@"more"].popoverTouchBar.itemIdentifiers.count==7,@"Loop, tempo and recording options must all be reachable from the hold panel");
        controller.state=@{@"performance":@1,@"tempo":@128.5,@"playing":@YES,@"loop":@YES,@"beats_per_bar":@3,@"loop_length":@12,@"record":@NO,@"armed":@YES};
        [controller refreshButtonsConnected:YES];
        NSCAssert([controller.options[@"tempo"].title isEqual:@"128.5 BPM"] && [controller.options[@"loop"].title isEqual:@"4 bar"] && controller.options[@"tempo"].enabled,@"The panel must show real tempo and time-signature-aware loop length");
        controller.state=@{@"loop":@NO}; [controller refreshButtonsConnected:YES];
        NSCAssert(!controller.options[@"tempo"].enabled && !controller.options[@"tempo-up"].enabled && controller.options[@"loop"].enabled && [controller.options[@"tempo"].title isEqual:@"— BPM"],@"An old script must never expose apparently working new actions or invent a BPM");
        StripPerformanceButton *loop=(StripPerformanceButton *)controller.options[@"loop"];
        controller.state=@{@"loop":@YES,@"punch-in":@YES,@"punch-out":@NO}; [controller refreshButtonsConnected:YES];
        NSCAssert(loop.loopActive && loop.punchInActive && !loop.punchOutActive,@"Loop and both Punch cues reflect independent acknowledged Live states");
        [controller refreshButtonsConnected:NO];
        NSCAssert(!loop.loopActive && !loop.punchInActive && !loop.punchOutActive,@"Disconnected state clears all Loop/Punch cues");
        loop.enabled=YES; [loop beginAt:NSMakePoint(22,15) identity:nil]; [loop finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.commands isEqual:@[@"loop"]]),@"Loop tap must toggle the real loop");
        [controller.commands removeAllObjects];
        [loop beginAt:NSMakePoint(22,15) identity:nil]; [loop fireHold]; [loop fireHold];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        [loop finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.menus isEqual:@[@"loop"]]) && !controller.commands.count,@"Loop hold opens lengths once and release must not toggle Loop");
        for(NSNumber *direction in @[@(-1),@1]) {
            NSPoint start=NSMakePoint(direction.intValue>0 ? 10 : 50,15),end=NSMakePoint(direction.intValue>0 ? 50 : 10,15);
            [loop beginAt:start identity:nil]; [loop moveAt:end]; [loop finishAt:end];
        }
        NSCAssert(([controller.commands isEqual:@[@"punch-in",@"punch-out"]]),@"Combined loop swipes toggle Punch In and Punch Out without also toggling Loop");
        [controller.commands removeAllObjects];
        StripPerformanceButton *tempo=(StripPerformanceButton *)controller.options[@"tempo"];
        controller.state=@{@"tempo":@120.5};
        tempo.enabled=YES; [tempo beginAt:NSMakePoint(10,15) identity:nil]; [tempo moveAt:NSMakePoint(40,15)]; [tempo finishAt:NSMakePoint(40,15)];
        NSCAssert(!controller.commands.count && controller.tempoTargets.lastObject.doubleValue==128.5,@"BPM swipe uses full distance (30 points becomes 8 BPM), not a single step");
        [tempo beginAt:NSMakePoint(50,15) identity:nil];
        [tempo moveAt:NSMakePoint(10,15)];
        NSCAssert(controller.tempoTargets.lastObject.doubleValue==110.5,@"A longer left drag subtracts the proportional amount");
        [tempo moveAt:NSMakePoint(58,15)]; [tempo finishAt:NSMakePoint(58,15)];
        NSCAssert(controller.tempoTargets.lastObject.doubleValue==122.5 && !controller.commands.count,@"Reversing direction uses the same original tempo and never fires Tap Tempo on release");
        [controller.commands removeAllObjects];
        [tempo beginAt:NSMakePoint(22,15) identity:nil]; [tempo finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.commands isEqual:@[@"tap-tempo"]]) && ([controller.menus isEqual:@[@"loop"]]),@"BPM tap must issue Tap Tempo, never open the tempo menu");
        [controller.commands removeAllObjects];
        [tempo beginAt:NSMakePoint(22,15) identity:nil]; [tempo fireHold];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]]; [tempo finishAt:NSMakePoint(22,15)];
        NSCAssert(([controller.menus isEqual:@[@"loop",@"tempo"]]) && !controller.commands.count,@"BPM hold preserves optional fine/coarse controls without a Tap Tempo on release");
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
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.30]];
        event.phase=NSTouchPhaseEnded; [button touchesEndedWithEvent:(NSEvent *)event];
        NSCAssert(controller.holds==1 && controller.commands.count==0,@"Hold opens options once, release never starts recording");
        event.phase=NSTouchPhaseBegan; [button touchesBeganWithEvent:(NSEvent *)event];
        [button touchesCancelledWithEvent:(NSEvent *)event]; [button fireHold];
        event.phase=NSTouchPhaseEnded; [button touchesEndedWithEvent:(NSEvent *)event];
        NSCAssert(controller.commands.count==0,@"Cancelled touches do nothing");
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(35,15)]; [button finishAt:NSMakePoint(35,15)];
        NSArray<NSNumber *> *selectedIndices=controller.payloads.lastObject[@"track_indices"];
        NSCAssert([controller.commands isEqual:@[@"arm-on"]] && selectedIndices.count==2 && selectedIndices[0].integerValue==0 && selectedIndices[1].integerValue==1,@"Normal-mode right swipe targets every selected armable track");
        [controller.commands removeAllObjects];
        [controller.payloads removeAllObjects];
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(9,15)]; [button finishAt:NSMakePoint(9,15)];
        selectedIndices=controller.payloads.lastObject[@"track_indices"];
        NSCAssert([controller.commands isEqual:@[@"arm-off"]] && selectedIndices.count==2 && selectedIndices[0].integerValue==0 && selectedIndices[1].integerValue==1,@"Normal-mode left swipe disarms every selected armable track");
        [controller.commands removeAllObjects];
        controller.surfaceMode=YES;
        [controller.payloads removeAllObjects];
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(35,15)]; [button finishAt:NSMakePoint(35,15)];
        selectedIndices=controller.payloads.lastObject[@"track_indices"];
        NSCAssert([controller.commands isEqual:@[@"arm-exclusive"]] && selectedIndices.count==2 && selectedIndices[0].integerValue==0 && selectedIndices[1].integerValue==1,@"Control Surface right swipe exclusively arms every selected track");
        [controller.commands removeAllObjects];
        [controller.payloads removeAllObjects];
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(13,15)]; [button finishAt:NSMakePoint(13,15)];
        NSCAssert([controller.commands isEqual:@[@"arm-all-toggle"]],@"Control Surface left swipe toggles all armable tracks");
        [controller.commands removeAllObjects];
        [button beginAt:NSMakePoint(22,15) identity:nil]; [button moveAt:NSMakePoint(23,25)];
        [button fireHold]; [button finishAt:NSMakePoint(23,25)];
        NSCAssert(controller.commands.count==0,@"Vertical motion is not a tap or horizontal swipe");
        puts("Passed performance menu structure/state/capability gating, Loop hold without release toggle, BPM tap/swipe, fixed joined layout, recording-only red, and normal/Control Surface Record swipe directions; no Live commands sent.");
    }
    return 0;
}
