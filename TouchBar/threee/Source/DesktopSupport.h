// Space metadata uses SkyLight's managed-display APIs. Space changes post the
// complete Dock swipe gesture sequence (see PostDesktopSwipe below).
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
        [result addObject:@{@"id":@(sid),@"display":selected[@"Display Identifier"] ?: @"",@"active":@(sid==currentID),@"title":title,@"number":@(full ? fullscreen : desktop),@"fullscreen":@(full)}];
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
static NSUInteger desktopSelectionSequence=0;
// Synthetic Dock swipes, adapted from InstantSpaceSwitcher (MIT; see
// Resources/InstantSpaceSwitcher-LICENSE.txt). macOS 27 ignores a plain
// DockControl event: it must carry the raw IOHID fluid-gesture payload a real
// trackpad sends, plus a companion Gesture event, and the fling velocity on the
// Ended phase is what commits the switch. Earlier macOS takes the plain event.
#include <sys/sysctl.h>
#include <mach/mach_time.h>
static BOOL DesktopSwipeNeedsPayload(void) {
    static int cached=-1;
    if(cached>=0)return cached;
    char version[32]={0};size_t size=sizeof(version);int major=0;
    cached=sysctlbyname("kern.osproductversion",version,&size,NULL,0)==0&&sscanf(version,"%d",&major)==1&&major>=27;
    return cached;
}
static int32_t DesktopFixed1616(double value) {
    int32_t fixed=(int32_t)(value*65536.0);
    return fixed==0&&value!=0 ? (value>0?1:-1) : fixed;
}
#pragma pack(push,1)
typedef struct { uint32_t size,type,options; uint8_t depth,reserved[3]; } DesktopHIDBase;
typedef struct { DesktopHIDBase base; int32_t x,y,z; uint32_t mask; uint16_t motion,flavor; int32_t progress; } DesktopHIDFluid;
typedef struct { DesktopHIDBase base; int32_t x,y,z; } DesktopHIDVelocity;
typedef struct { uint64_t timestamp,sender; uint32_t options,attributes,count; } DesktopHIDHeader;
#pragma pack(pop)
_Static_assert(sizeof(DesktopHIDBase)==16&&sizeof(DesktopHIDFluid)==40&&sizeof(DesktopHIDVelocity)==28&&sizeof(DesktopHIDHeader)==28,"IOHID layout");
// Appends the IOHID payload (field 4205) to the event's serialized form.
static CGEventRef DesktopAugmentedSwipe(CGEventRef event) {
    CFDataRef data=CGEventCreateData(kCFAllocatorDefault,event);
    if(!data)return NULL;
    const uint8_t *bytes=CFDataGetBytePtr(data);CFIndex length=CFDataGetLength(data);
    if(length<4||bytes[0]||bytes[1]||bytes[2]||bytes[3]!=2){CFRelease(data);return NULL;}
    int64_t phase=CGEventGetIntegerValueField(event,(CGEventField)132);
    double velocityX=CGEventGetDoubleValueField(event,(CGEventField)129),velocityY=CGEventGetDoubleValueField(event,(CGEventField)130);
    BOOL withVelocity=velocityX!=0||velocityY!=0||phase==4;
    size_t payload=sizeof(DesktopHIDHeader)+sizeof(DesktopHIDFluid)+(withVelocity?sizeof(DesktopHIDVelocity):0);
    uint8_t *buffer=calloc(1,(size_t)length+4+payload);
    if(!buffer){CFRelease(data);return NULL;}
    memcpy(buffer,bytes,(size_t)length);
    buffer[length]=(uint8_t)(payload>>8);buffer[length+1]=(uint8_t)payload;
    buffer[length+2]=(uint8_t)(4205>>8);buffer[length+3]=(uint8_t)4205;
    DesktopHIDHeader *header=(DesktopHIDHeader *)(buffer+length+4);
    uint64_t timestamp=CGEventGetTimestamp(event);
    header->timestamp=timestamp?timestamp:mach_absolute_time();header->count=withVelocity?2:1;
    DesktopHIDFluid *fluid=(DesktopHIDFluid *)(header+1);
    fluid->base.size=sizeof(DesktopHIDFluid);fluid->base.type=23;fluid->base.options=(uint32_t)((phase&0xFF)<<24);
    fluid->x=DesktopFixed1616(CGEventGetDoubleValueField(event,(CGEventField)125));
    fluid->y=DesktopFixed1616(CGEventGetDoubleValueField(event,(CGEventField)126));
    fluid->mask=(uint32_t)CGEventGetIntegerValueField(event,(CGEventField)115);
    fluid->motion=(uint16_t)CGEventGetIntegerValueField(event,(CGEventField)123);
    fluid->flavor=3;
    fluid->progress=DesktopFixed1616(CGEventGetDoubleValueField(event,(CGEventField)124));
    if(withVelocity){
        DesktopHIDVelocity *velocity=(DesktopHIDVelocity *)(fluid+1);
        velocity->base.size=sizeof(DesktopHIDVelocity);velocity->base.type=9;velocity->base.depth=1;
        velocity->x=DesktopFixed1616(velocityX);velocity->y=DesktopFixed1616(velocityY);
    }
    CFDataRef augmented=CFDataCreate(kCFAllocatorDefault,buffer,(CFIndex)((size_t)length+4+payload));
    free(buffer);CFRelease(data);
    if(!augmented)return NULL;
    CGEventRef result=CGEventCreateFromData(kCFAllocatorDefault,augmented);
    CFRelease(augmented);
    return result;
}
// On macOS 27 a swipe toward the right-hand Space is negative, and the Dock
// applies the natural-scrolling preference to the posted sign.
static double DesktopModernSign(BOOL right) {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    Boolean valid=false;
    Boolean natural=CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"),kCFPreferencesAnyApplication,&valid);
    double sign=right?-1.0:1.0;
    return (!valid||natural)?sign:-sign;
}
static BOOL PostDesktopSwipePhase(int64_t phase,BOOL right) {
    CGEventRef dock=CGEventCreate(NULL);
    if(!dock)return NO;
    CGEventSetIntegerValueField(dock,(CGEventField)55,30);   // DockControl
    CGEventSetIntegerValueField(dock,(CGEventField)110,23);  // IOHID Dock swipe
    CGEventSetIntegerValueField(dock,(CGEventField)132,phase);
    CGEventSetIntegerValueField(dock,(CGEventField)123,1);   // horizontal
    if(!DesktopSwipeNeedsPayload()) {
        double velocity=right?2000.0:-2000.0;
        CGEventSetDoubleValueField(dock,(CGEventField)124,right?0.000016:-0.000016);
        CGEventSetDoubleValueField(dock,(CGEventField)129,velocity);
        CGEventSetDoubleValueField(dock,(CGEventField)130,velocity);
        CGEventPost(kCGSessionEventTap,dock);CFRelease(dock);
        return YES;
    }
    double sign=DesktopModernSign(right);
    CGEventSetDoubleValueField(dock,(CGEventField)124,sign*0.000016);
    CGEventSetIntegerValueField(dock,(CGEventField)134,phase);
    CGEventSetDoubleValueField(dock,(CGEventField)138,3.0);
    CGEventSetDoubleValueField(dock,(CGEventField)169,(double)mach_absolute_time());
    CGEventSetDoubleValueField(dock,(CGEventField)125,0.1);
    if(phase==4)CGEventSetDoubleValueField(dock,(CGEventField)129,sign*9999.0);
    CGEventRef augmented=DesktopAugmentedSwipe(dock);CFRelease(dock);
    if(!augmented)return NO;
    CGEventRef companion=CGEventCreate(NULL);
    if(!companion){CFRelease(augmented);return NO;}
    CGEventSetIntegerValueField(companion,(CGEventField)55,29); // Gesture
    CGEventPost(kCGSessionEventTap,augmented);CGEventPost(kCGSessionEventTap,companion);
    CFRelease(augmented);CFRelease(companion);
    return YES;
}
// Began, Changed and Ended; with fewer phases the Dock ignores the gesture.
static void PostDesktopSwipe(BOOL right) {
    if(PostDesktopSwipePhase(1,right)&&PostDesktopSwipePhase(2,right))PostDesktopSwipePhase(4,right);
}
static void AdvanceDesktopSelection(uint64_t target,NSUInteger sequence,NSInteger attempts);
static void WaitForDesktopSelection(uint64_t target,NSUInteger sequence,uint64_t previous,NSInteger attempts,CFAbsoluteTime started) {
    if(sequence!=desktopSelectionSequence)return;
    NSArray *spaces=DesktopSpaces();uint64_t active=0;
    for(NSDictionary *space in spaces)if([space[@"active"] boolValue]){active=[space[@"id"] unsignedLongLongValue];break;}
    if(active==target)return;
    BOOL moved=active&&active!=previous;
    if(moved||CFAbsoluteTimeGetCurrent()-started>=1.5) {
        if(attempts<=1)return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ AdvanceDesktopSelection(target,sequence,attempts-1); });
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ WaitForDesktopSelection(target,sequence,previous,attempts,started); });
}
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
        NSLog(@"Desktop selection requires ThreeE's Accessibility permission."); return;
    }
    uint64_t previous=[spaces[(NSUInteger)active][@"id"] unsignedLongLongValue];
    PostDesktopSwipe(destination>active);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ WaitForDesktopSelection(target,sequence,previous,attempts,CFAbsoluteTimeGetCurrent()); });
}
static void SelectDesktop(uint64_t target) {
    AdvanceDesktopSelection(target,++desktopSelectionSequence,DesktopSpaces().count+2);
}
// The phone sends a destination direction, already opposite the finger swipe.
// Use the regular Control-arrow shortcut so Dock owns the normal animation.
static CGEventRef DesktopShortcutEvent(NSInteger direction,BOOL down) {
    CGEventRef event=CGEventCreateKeyboardEvent(NULL,direction>0?124:123,down);
    if(event)CGEventSetFlags(event,kCGEventFlagMaskControl);
    return event;
}
static CFAbsoluteTime desktopStepReadyAt=0;
static void StepDesktop(NSInteger direction) {
    if(!direction)return;
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    if(now<desktopStepReadyAt)return;
    NSArray *spaces=DesktopSpaces();NSInteger active=-1;
    if(spaces.count<=1) { PostMacSystemAction(@"missionControl",0);return; }
    for(NSUInteger i=0;i<spaces.count;i++)if([spaces[i][@"active"] boolValue]){active=(NSInteger)i;break;}
    NSInteger destination=active+(direction>0?1:-1);
    if(active<0||destination<0||destination>=(NSInteger)spaces.count)return;
    if(!AccessibilityTrusted(NO)){AccessibilityTrusted(YES);return;}
    CGEventRef down=DesktopShortcutEvent(direction,YES),up=DesktopShortcutEvent(direction,NO);
    if(down&&up){
        // Invalidate any older picker retry and allow this transition to settle.
        ++desktopSelectionSequence;desktopStepReadyAt=now+.5;
        CGEventPost(kCGHIDEventTap,down);CGEventPost(kCGHIDEventTap,up);
    }
    if(down)CFRelease(down);if(up)CFRelease(up);
}
