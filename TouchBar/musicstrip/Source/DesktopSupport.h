// Hand a launcher hold to Apple's own Touch Bar Spaces picker. This launchd
// notification starts SpacesTouchBarAgent on demand; it does not open the
// on-screen Mission Control overview or synthesize desktop-switch gestures.
#import <notify.h>
static NSString *const NativeSpacesPickerNotification=@"com.apple.SpacesTouchBarAgent.showPopover";
static BOOL NativeSpacesPickerVisible(void) {
    static int token=-1;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSString *name=[NSString stringWithFormat:@"user.uid.%ld.com.apple.services.touchbar.active",(long)getuid()];
        if(notify_register_check(name.UTF8String,&token)!=NOTIFY_STATUS_OK) token=-1;
    });
    uint64_t state=0;
    return token>=0 && notify_get_state(token,&state)==NOTIFY_STATUS_OK && state==1;
}
static void ShowNativeSpacesPicker(void) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:NativeSpacesPickerNotification
        object:nil userInfo:nil deliverImmediately:YES];
}
// Legacy custom picker support remains available for diagnostics only.
// Dock swipe events adapted from Michael Torbert's MIT-licensed
// spaces-manager. See Resources/SpacesManager-LICENSE.txt.
static NSArray<NSDictionary *> *DesktopSpaces(void) {
    static int (*connection)(void);
    static CFArrayRef (*copySpaces)(int);
    static uint64_t (*activeSpace)(int);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *sky=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
        connection=dlsym(sky,"CGSMainConnectionID");
        copySpaces=dlsym(sky,"CGSCopyManagedDisplaySpaces");
        activeSpace=dlsym(sky,"CGSGetActiveSpace");
    });
    if(!connection || !copySpaces) return @[];
    int cid=connection(); uint64_t active=activeSpace ? activeSpace(cid) : 0;
    NSArray *displays=CFBridgingRelease(copySpaces(cid));
    NSDictionary *selected=nil;
    for(NSDictionary *display in displays) for(NSDictionary *space in display[@"Spaces"]) {
        if([space[@"id64"] unsignedLongLongValue]==active || [space[@"ManagedSpaceID"] unsignedLongLongValue]==active) selected=display;
    }
    selected=selected ?: displays.firstObject;
    NSDictionary *current=selected[@"Current Space"];
    uint64_t currentID=[current[@"id64"] ?: current[@"ManagedSpaceID"] unsignedLongLongValue];
    NSMutableArray *result=[NSMutableArray array]; NSInteger desktop=0,fullscreen=0;
    for(NSDictionary *space in selected[@"Spaces"]) {
        uint64_t sid=[space[@"id64"] ?: space[@"ManagedSpaceID"] unsignedLongLongValue];
        BOOL full=[space[@"type"] integerValue]==4 || space[@"TileLayoutManager"]!=nil;
        NSString *title=full ? [NSString stringWithFormat:@"Full Screen %ld",(long)++fullscreen] : [NSString stringWithFormat:@"Desktop %ld",(long)++desktop];
        [result addObject:@{@"id":@(sid),@"active":@(sid==currentID),@"title":title,@"number":@(full ? fullscreen : desktop),@"fullscreen":@(full)}];
    }
    return result;
}
static NSImage *DesktopIcon(NSDictionary *space) {
    return [NSImage imageWithSize:NSMakeSize(24,24) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.whiteColor setStroke];
        NSBezierPath *monitor=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1,5,22,17) xRadius:2 yRadius:2]; monitor.lineWidth=1.5; [monitor stroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(7,2) toPoint:NSMakePoint(17,2)];
        NSString *number=[space[@"number"] stringValue];
        NSDictionary *attributes=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.whiteColor};
        NSSize size=[number sizeWithAttributes:attributes];
        [number drawAtPoint:NSMakePoint((24-size.width)/2,7) withAttributes:attributes];
        return YES;
    }];
}
static void PostDesktopSwipe(BOOL right) {
    for(NSInteger phaseIndex=0;phaseIndex<3;phaseIndex++) {
        CGEventRef dock=CGEventCreate(NULL),gesture=CGEventCreate(NULL);
        if(!dock || !gesture) { if(dock) CFRelease(dock); if(gesture) CFRelease(gesture); return; }
        CGEventSetType(dock,(CGEventType)30); CGEventSetIntegerValueField(dock,(CGEventField)55,30);
        CGEventSetType(gesture,(CGEventType)29); CGEventSetIntegerValueField(gesture,(CGEventField)55,29);
        CGEventSetIntegerValueField(dock,(CGEventField)110,23);
        CGEventSetIntegerValueField(dock,(CGEventField)132,phaseIndex==0 ? 1 : phaseIndex==1 ? 2 : 4);
        CGEventSetIntegerValueField(dock,(CGEventField)135,right ? 1 : 0);
        CGEventSetIntegerValueField(dock,(CGEventField)123,1);
        CGEventSetDoubleValueField(dock,(CGEventField)119,0);
        CGEventSetDoubleValueField(dock,(CGEventField)139,FLT_MIN);
        if(phaseIndex>0) {
            CGEventSetDoubleValueField(dock,(CGEventField)124,(right ? 1 : -1)*(phaseIndex==1 ? 1.0 : 2.0));
            CGEventSetDoubleValueField(dock,(CGEventField)129,right ? 400 : -400);
            CGEventSetDoubleValueField(dock,(CGEventField)130,0);
        }
        CGEventPost(kCGSessionEventTap,dock); CGEventPost(kCGSessionEventTap,gesture);
        CFRelease(dock); CFRelease(gesture);
    }
}
static NSUInteger desktopSelectionSequence=0;
static void AdvanceDesktopSelection(uint64_t target,NSUInteger sequence,NSInteger attempts) {
    if(sequence!=desktopSelectionSequence || attempts<=0) return;
    NSArray *spaces=DesktopSpaces(); NSInteger active=-1,destination=-1;
    for(NSUInteger i=0;i<spaces.count;i++) {
        if([spaces[i][@"active"] boolValue]) active=i;
        if([spaces[i][@"id"] unsignedLongLongValue]==target) destination=i;
    }
    if(active<0 || destination<0 || active==destination) return;
    if(!AXIsProcessTrusted()) {
        static BOOL requested=NO;
        if(!requested) { requested=YES; AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}); }
        NSLog(@"Desktop selection requires MusicStrip's Accessibility permission."); return;
    }
    PostDesktopSwipe(destination>active);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ AdvanceDesktopSelection(target,sequence,attempts-1); });
}
static void SelectDesktop(uint64_t target) {
    AdvanceDesktopSelection(target,++desktopSelectionSequence,DesktopSpaces().count+2);
}
