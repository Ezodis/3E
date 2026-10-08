// Keep the original gesture receiver mounted while its choices cover the row.
// Native scrolling and short taps retain their existing behavior outside a swipe.
#import <CoreGraphics/CoreGraphics.h>
@interface DockSwipeGesture : NSGestureRecognizer
@property NSPoint startPoint;
@property NSPoint currentPoint;
@property id identity;
@property BOOL tracking;
@property BOOL swiping;
@property NSGestureRecognizerState trackingPhase;
@property (copy) void (^onTouchBegin)(DockSwipeGesture *gesture);
@property (copy) BOOL (^shouldStart)(DockSwipeGesture *gesture);
@property (copy) void (^onUpdate)(DockSwipeGesture *gesture);
- (void)beginAt:(NSPoint)point identity:(id)identity;
- (void)moveAt:(NSPoint)point;
- (void)endAt:(NSPoint)point;
- (void)cancelTracking;
@end
@implementation DockSwipeGesture
- (BOOL)canBePreventedByGestureRecognizer:(NSGestureRecognizer *)other { return [other isKindOfClass:NSPressGestureRecognizer.class] && other.state==NSGestureRecognizerStateBegan; }
- (void)reset { [super reset]; self.tracking=NO; self.swiping=NO; self.identity=nil; }
- (void)beginAt:(NSPoint)point identity:(id)identity {
    if(self.tracking) { [self cancelTracking]; return; }
    self.startPoint=point; self.currentPoint=point; self.identity=identity; self.tracking=YES; self.swiping=NO; self.trackingPhase=NSGestureRecognizerStatePossible;
    if(self.onTouchBegin) self.onTouchBegin(self);
}
- (void)moveAt:(NSPoint)point {
    if(!self.tracking) return;
    self.currentPoint=point;
    if(!self.swiping && hypot(point.x-self.startPoint.x,point.y-self.startPoint.y)>=12) {
        if(self.shouldStart && !self.shouldStart(self)) { self.tracking=NO; self.trackingPhase=NSGestureRecognizerStateFailed; self.state=NSGestureRecognizerStateFailed; return; }
        self.swiping=YES; self.trackingPhase=NSGestureRecognizerStateBegan; self.state=NSGestureRecognizerStateBegan;
        if(self.onUpdate) self.onUpdate(self);
    } else if(self.swiping) {
        self.trackingPhase=NSGestureRecognizerStateChanged; self.state=NSGestureRecognizerStateChanged;
        if(self.onUpdate) self.onUpdate(self);
    }
}
- (void)endAt:(NSPoint)point {
    if(!self.tracking) return;
    self.currentPoint=point; self.tracking=NO;
    self.trackingPhase=self.swiping ? NSGestureRecognizerStateEnded : NSGestureRecognizerStateFailed;
    if(self.swiping && self.onUpdate) self.onUpdate(self);
    self.state=self.trackingPhase; self.swiping=NO;
}
- (void)cancelTracking {
    self.tracking=NO; self.identity=nil;
    self.trackingPhase=self.swiping ? NSGestureRecognizerStateCancelled : NSGestureRecognizerStateFailed;
    if(self.swiping && self.onUpdate) self.onUpdate(self);
    self.state=self.trackingPhase; self.swiping=NO;
}
- (void)mouseDown:(NSEvent *)event { [super mouseDown:event]; [self beginAt:[self.view convertPoint:event.locationInWindow fromView:nil] identity:nil]; }
- (void)mouseDragged:(NSEvent *)event { [super mouseDragged:event]; [self moveAt:[self.view convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [super mouseUp:event]; [self endAt:[self.view convertPoint:event.locationInWindow fromView:nil]]; }
- (void)touchesBeganWithEvent:(NSEvent *)event {
    [super touchesBeganWithEvent:event]; NSSet *touches=[event touchesMatchingPhase:NSTouchPhaseBegan inView:self.view];
    if(touches.count!=1 || self.tracking) { [self cancelTracking]; return; }
    NSTouch *touch=touches.anyObject;
    if(touch.type==NSTouchTypeDirect) [self beginAt:[touch locationInView:self.view] identity:touch.identity];
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    [super touchesMovedWithEvent:event];
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:self.view]) if([touch.identity isEqual:self.identity]) [self moveAt:[touch locationInView:self.view]];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    [super touchesEndedWithEvent:event];
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:self.view]) if([touch.identity isEqual:self.identity]) [self endAt:[touch locationInView:self.view]];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event { [super touchesCancelledWithEvent:event]; [self cancelTracking]; }
@end

@interface DockSwipeChoice : NSObject
@property NSString *title;
@property NSImage *icon;
@property DockAppEntry *entry;
@property NSRunningApplication *application;
@property id window;
@property CGWindowID windowID;
@property NSUInteger windowIndex;
@end
@implementation DockSwipeChoice
@end

static NSString *WindowScriptBundle(NSString *bundleIdentifier) {
    NSString *escaped=[bundleIdentifier stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}
static NSArray<NSString *> *SystemEventsWindowNames(NSRunningApplication *app) {
    if(!app.bundleIdentifier.length) return @[];
    NSString *bundle=WindowScriptBundle(app.bundleIdentifier);
    NSString *source=[NSString stringWithFormat:@"tell application \"System Events\"\nset p to first application process whose bundle identifier is \"%@\"\nset resultLines to {}\nrepeat with w in windows of p\ntry\nset windowName to (name of w as text)\nif windowName is not \"\" then set end of resultLines to windowName\nend try\nend repeat\nreturn resultLines\nend tell",bundle];
    NSDictionary *error=nil;
    NSAppleEventDescriptor *result=[[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if(!result || error) return @[];
    NSMutableArray *names=[NSMutableArray new];
    for(NSInteger i=1;i<=result.numberOfItems;i++) {
        NSString *name=[result descriptorAtIndex:i].stringValue;
        if(name.length) [names addObject:name];
    }
    return names;
}
static void RaiseSystemEventsWindow(NSRunningApplication *app, NSUInteger index) {
    if(!app.bundleIdentifier.length || !index) return;
    NSString *bundle=WindowScriptBundle(app.bundleIdentifier);
    NSString *source=[NSString stringWithFormat:@"tell application \"System Events\"\nset p to first application process whose bundle identifier is \"%@\"\nset frontmost of p to true\nperform action \"AXRaise\" of window %lu of p\nend tell",bundle,(unsigned long)index];
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:nil];
}

typedef int CGSConnectionID;
typedef int (*MusicStripCGSMainConnectionID)(void);
typedef int (*MusicStripCGSOrderWindow)(CGSConnectionID, CGWindowID, int, CGWindowID);
static void RaiseWindowServerWindow(CGWindowID windowID) {
    if(!windowID) return;
    void *skyLight=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
    MusicStripCGSMainConnectionID mainConnection=(MusicStripCGSMainConnectionID)dlsym(skyLight,"CGSMainConnectionID");
    MusicStripCGSOrderWindow orderWindow=(MusicStripCGSOrderWindow)dlsym(skyLight,"CGSOrderWindow");
    if(mainConnection && orderWindow) orderWindow(mainConnection(),windowID,1,0);
    if(skyLight) dlclose(skyLight);
}

static NSArray<DockSwipeChoice *> *InstalledSwipeApps(void) {
    NSMutableArray<DockAppEntry *> *entries=[DockAppEntries(@[],@{}) mutableCopy];
    NSMutableSet *seen=[NSMutableSet new]; for(DockAppEntry *entry in entries) [seen addObject:entry.bundleIdentifier];
    NSMutableArray *other=[NSMutableArray new];
    NSArray *roots=@[@"/Applications",@"/System/Applications",[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]];
    for(NSString *root in roots) {
        NSDirectoryEnumerator *files=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        for(NSURL *url in files) {
            if(![url.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            [files skipDescendants]; NSBundle *bundle=[NSBundle bundleWithURL:url]; NSDictionary *info=bundle.infoDictionary;
            NSString *identifier=bundle.bundleIdentifier ?: url.path;
            if([seen containsObject:identifier] || [identifier isEqualToString:@"local.musicstrip.app"] || [identifier isEqualToString:MidiBundle] || [info[@"LSUIElement"] boolValue] || [info[@"LSBackgroundOnly"] boolValue]) continue;
            [seen addObject:identifier]; DockAppEntry *entry=[DockAppEntry new]; entry.bundleURL=url; entry.bundleIdentifier=bundle.bundleIdentifier;
            entry.localizedName=bundle.localizedInfoDictionary[@"CFBundleDisplayName"] ?: info[@"CFBundleDisplayName"] ?: [url.lastPathComponent stringByDeletingPathExtension];
            entry.icon=[NSWorkspace.sharedWorkspace iconForFile:url.path]; [other addObject:entry];
        }
    }
    [other sortUsingComparator:^NSComparisonResult(DockAppEntry *a,DockAppEntry *b){ return [a.localizedName localizedStandardCompare:b.localizedName]; }]; [entries addObjectsFromArray:other];
    NSMutableArray *choices=[NSMutableArray new];
    for(DockAppEntry *entry in entries) { DockSwipeChoice *choice=[DockSwipeChoice new]; choice.entry=entry; choice.title=entry.localizedName; choice.icon=entry.icon; [choices addObject:choice]; }
    return choices;
}
static NSArray<DockSwipeChoice *> *SwipeWindows(NSRunningApplication *app) {
    if(!app || app.terminated) return @[];
    AXUIElementRef target=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(target,2.0);
    CFTypeRef raw=NULL; AXUIElementCopyAttributeValue(target,kAXWindowsAttribute,&raw); CFRelease(target);
    NSMutableArray *choices=[NSMutableArray new];
    if(raw) {
        NSArray *windows=CFBridgingRelease(raw);
        for(id window in windows) {
            AXUIElementRef element=(__bridge AXUIElementRef)window; AXUIElementSetMessagingTimeout(element,2.0);
            CFTypeRef title=NULL; AXUIElementCopyAttributeValue(element,kAXTitleAttribute,&title);
            NSString *name=CFBridgingRelease(title);
            if(![name isKindOfClass:NSString.class] || !name.length) name=@"Untitled window";
            DockSwipeChoice *choice=[DockSwipeChoice new]; choice.title=name; choice.icon=app.icon; choice.application=app; choice.window=window; [choices addObject:choice];
        }
    }
    if(choices.count) return choices;

    // Some applications expose their window collection late, but still
    // expose the focused window immediately. A single real window must never
    // become an empty chooser.
    AXUIElementRef focusedApp=AXUIElementCreateApplication(app.processIdentifier);
    AXUIElementSetMessagingTimeout(focusedApp,2.0);
    CFTypeRef focusedRaw=NULL;
    AXUIElementCopyAttributeValue(focusedApp,kAXFocusedWindowAttribute,&focusedRaw);
    CFRelease(focusedApp);
    if(focusedRaw) {
        id focusedObject=CFBridgingRelease(focusedRaw);
        AXUIElementRef focused=(__bridge AXUIElementRef)focusedObject;
        CFTypeRef title=NULL; AXUIElementCopyAttributeValue(focused,kAXTitleAttribute,&title);
        NSString *name=CFBridgingRelease(title);
        if(![name isKindOfClass:NSString.class] || !name.length) name=@"Untitled window";
        DockSwipeChoice *choice=[DockSwipeChoice new]; choice.title=name; choice.icon=app.icon; choice.application=app; choice.window=focusedObject;
        [choices addObject:choice];
        return choices;
    }

    // If AX is unavailable, use System Events' named user windows. This is
    // preferable to showing WindowServer's anonymous toolbar and menu-bar
    // surfaces as if they were app windows.
    NSArray<NSString *> *scriptNames=SystemEventsWindowNames(app);
    if(scriptNames.count) {
        NSMutableArray *named=[NSMutableArray new];
        [scriptNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
            DockSwipeChoice *choice=[DockSwipeChoice new]; choice.title=name; choice.icon=app.icon; choice.application=app; choice.windowIndex=index+1; [named addObject:choice];
        }];
        return named;
    }
    // Last resort: only explicitly named WindowServer records. Anonymous
    // records commonly represent toolbars, menu bars, or compositor layers.
    NSArray *windowInfo=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
    for(NSDictionary *info in windowInfo) {
        if([info[(id)kCGWindowOwnerPID] intValue]!=app.processIdentifier || [info[(id)kCGWindowLayer] integerValue]!=0) continue;
        NSDictionary *bounds=info[(id)kCGWindowBounds];
        CGRect rect=CGRectZero; CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)bounds,&rect);
        if(CGRectGetWidth(rect)<2 || CGRectGetHeight(rect)<2) continue;
        if([info[(id)kCGWindowAlpha] doubleValue]<=0) continue;
        NSString *name=info[(id)kCGWindowName];
        if(!name.length) continue;
        DockSwipeChoice *choice=[DockSwipeChoice new]; choice.title=name; choice.icon=app.icon; choice.application=app; choice.windowID=[info[(id)kCGWindowNumber] unsignedIntValue]; [choices addObject:choice];
    }
    return choices;
}

@interface DockSwipeChooser : NSView
@property NSArray<DockSwipeChoice *> *choices;
@property NSString *message;
@property BOOL windowChoices;
@property BOOL awaitingSelection;
@property (copy) void (^didSelect)(DockSwipeChooser *chooser);
@property CGFloat visualCenter;
@property CGFloat offset;
@property NSPoint finger;
@property NSInteger selectedIndex;
@property NSTimer *edgeTimer;
@property NSTimeInterval lastTick;
- (void)updateAt:(NSPoint)point;
- (void)advanceBy:(NSTimeInterval)seconds;
- (void)startScrolling;
- (void)stopScrolling;
- (CGFloat)pitch;
- (CGFloat)contentWidth;
- (CGFloat)origin;
@end
@implementation DockSwipeChooser
- (void)touchesBeganWithEvent:(NSEvent *)event {
    [super touchesBeganWithEvent:event];
    if(!self.awaitingSelection) return;
    NSSet *touches=[event touchesMatchingPhase:NSTouchPhaseBegan inView:self];
    if(touches.count==1) [self updateAt:[touches.anyObject locationInView:self]];
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    [super touchesMovedWithEvent:event];
    if(!self.awaitingSelection) return;
    NSSet *touches=[event touchesMatchingPhase:NSTouchPhaseTouching inView:self];
    if(touches.count==1) [self updateAt:[touches.anyObject locationInView:self]];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    [super touchesEndedWithEvent:event];
    if(!self.awaitingSelection) return;
    NSSet *touches=[event touchesMatchingPhase:NSTouchPhaseEnded inView:self];
    if(touches.count==1) {
        [self updateAt:[touches.anyObject locationInView:self]];
        if(self.selectedIndex>=0 && self.didSelect) self.didSelect(self);
    }
}
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame])) { self.selectedIndex=-1; self.message=@"Loading…"; self.wantsLayer=YES; self.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; } return self; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (CGFloat)pitch { return self.windowChoices ? 160 : 56; }
- (CGFloat)contentWidth { return MAX(0,self.choices.count*[self pitch]-12); }
- (CGFloat)origin { CGFloat span=[self contentWidth],width=NSWidth(self.bounds); return (span<=width ? MIN(MAX(0,self.visualCenter-span/2),width-span) : 0)-self.offset; }
- (void)updateAt:(NSPoint)point {
    self.finger=point; self.selectedIndex=-1;
    if(point.y>=-12 && point.y<=NSHeight(self.bounds)+12) {
        CGFloat x=MIN(MAX(0,point.x),MAX(0,NSWidth(self.bounds)-.1))-[self origin]; NSInteger index=(NSInteger)floor(x/[self pitch]);
        if(x>=0 && index>=0 && index<(NSInteger)self.choices.count && x<=[self contentWidth]) self.selectedIndex=index;
    }
    self.needsDisplay=YES;
}
- (void)advanceBy:(NSTimeInterval)seconds {
    CGFloat width=NSWidth(self.bounds),limit=MAX(0,[self contentWidth]-width),edge=48,speed=0;
    if(self.finger.y>=-12 && self.finger.y<=NSHeight(self.bounds)+12) {
        if(self.finger.x<edge) speed=-420*MIN(1,MAX(0,(edge-self.finger.x)/edge));
        else if(self.finger.x>width-edge) speed=420*MIN(1,MAX(0,(self.finger.x-width+edge)/edge));
    }
    self.offset=MIN(limit,MAX(0,self.offset+speed*MIN(seconds,.1))); [self updateAt:self.finger];
}
- (void)startScrolling {
    [self stopScrolling]; self.lastTick=NSProcessInfo.processInfo.systemUptime;
    __weak DockSwipeChooser *weakSelf=self;
    self.edgeTimer=[NSTimer timerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer *timer){
        DockSwipeChooser *chooser=weakSelf; if(!chooser) { [timer invalidate]; return; }
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime; [chooser advanceBy:now-chooser.lastTick]; chooser.lastTick=now;
    }]; [NSRunLoop.mainRunLoop addTimer:self.edgeTimer forMode:NSRunLoopCommonModes];
}
- (void)stopScrolling { [self.edgeTimer invalidate]; self.edgeTimer=nil; }
- (void)dealloc { [self.edgeTimer invalidate]; }
- (void)drawRect:(NSRect)dirty {
    [NSColor.blackColor setFill]; NSRectFill(self.bounds);
    if(!self.choices.count) { NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:NSColor.lightGrayColor}; NSSize size=[self.message sizeWithAttributes:attributes]; [self.message drawAtPoint:NSMakePoint(MAX(0,(NSWidth(self.bounds)-size.width)/2),8) withAttributes:attributes]; return; }
    CGFloat origin=[self origin],pitch=[self pitch];
    for(NSUInteger i=0;i<self.choices.count;i++) {
        NSRect rect=NSMakeRect(origin+i*pitch,0,pitch-12,30); if(!NSIntersectsRect(rect,self.bounds)) continue;
        DockSwipeChoice *choice=self.choices[i];
        if(self.windowChoices || (NSInteger)i==self.selectedIndex) { [(NSInteger)i==self.selectedIndex ? [NSColor colorWithWhite:.35 alpha:1] : [NSColor colorWithWhite:.12 alpha:1] setFill]; [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6] fill]; }
        NSRect icon=self.windowChoices ? NSMakeRect(rect.origin.x+5,5,20,20) : NSMakeRect(NSMidX(rect)-10,9,20,20);
        [choice.icon drawInRect:icon fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.lineBreakMode=NSLineBreakByTruncatingTail; style.alignment=self.windowChoices ? NSTextAlignmentLeft : NSTextAlignmentCenter;
        NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:self.windowChoices ? 10 : 8],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:style};
        NSRect label=self.windowChoices ? NSMakeRect(rect.origin.x+30,8,NSWidth(rect)-34,14) : NSMakeRect(rect.origin.x,0,NSWidth(rect),9);
        [choice.title drawInRect:label withAttributes:attributes];
    }
    if(self.offset>0) [@"‹" drawAtPoint:NSMakePoint(0,3) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:20],NSForegroundColorAttributeName:NSColor.whiteColor}];
    if(self.offset<[self contentWidth]-NSWidth(self.bounds)) [@"›" drawAtPoint:NSMakePoint(NSWidth(self.bounds)-10,3) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:20],NSForegroundColorAttributeName:NSColor.whiteColor}];
}
@end
