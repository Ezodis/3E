// Included after MidiNavigationButton: reuse its proven direct-touch tracking.
// Commands are acknowledged by Live's control-surface thread, not UI guesses.
static NSString *const RecordID = @"local.musicstrip.midi.ableton-record";
@class StripRecordController;
@interface StripRecordButton : MidiNavigationButton
@property (weak) StripRecordController *recordController;
@property NSInteger pendingSwipeDirection;
@property BOOL controlSurfaceGesture;
@end
@interface StripPerformanceButton : MidiNavigationButton
@property (weak) StripRecordController *recordController;
@property NSString *holdMenu;
@property NSString *swipeForward;
@property NSString *swipeBack;
@property BOOL loopActive;
@property BOOL punchInActive;
@property BOOL punchOutActive;
@property double dragStartTempo;
@property NSString *dragSession;
@end
@interface StripRecordController : NSObject <NSTouchBarDelegate>
@property NSCustomTouchBarItem *item;
@property NSTouchBar *optionsTouchBar;
@property StripRecordButton *button;
@property NSTimer *pollTimer;
@property NSDictionary *state;
@property NSMutableDictionary<NSString *,NSButton *> *options;
@property NSMutableDictionary<NSString *,NSPopoverTouchBarItem *> *performanceMenus;
@property NSMutableArray<NSTouchBar *> *menuStack;
@property NSTouchBar *menuReturnBar;
@property NSTouchBar *activeMenuBar;
@property NSHashTable<StripRecordButton *> *menuRecordButtons;
@property NSString *pending;
@property NSTimeInterval pendingTime;
@property NSDictionary *queuedArmCommand;
@property NSString *message;
@property NSTimeInterval messageUntil;
@property NSNumber *queuedTempo;
@property NSString *queuedTempoSession;
@property NSArray<NSString *> *legacyTempoTokens;
@property BOOL returnSurfaceMode;
@property NSView *nativeSurfaceView;
@property NSView *nativeDeviceView;
- (void)send:(NSString *)action;
- (BOOL)isControlSurfaceMode;
- (NSArray<NSNumber *> *)selectedTrackIndicesForSwipe;
- (void)send:(NSString *)action payload:(NSDictionary *)payload;
- (void)setTempoFromDrag:(double)tempo;
- (BOOL)writeCommand:(NSString *)action payload:(NSDictionary *)payload token:(NSString *)token;
- (void)showOptions;
- (void)refresh;
- (void)showMenu:(NSString *)name;
- (void)perform:(NSString *)action;
- (void)refreshButtonsConnected:(BOOL)connected;
- (void)backMenu:(id)sender;
- (void)returnToMidi;
- (void)presentMenuBar:(NSTouchBar *)source;
@end
static StripRecordController *recordController;
static NSString *RecordDirectory(void) {
#ifdef STRIP3_RECORD_TESTING
    const char *testDirectory=getenv("STRIP_RECORD_TEST_DIRECTORY");
    if(testDirectory) return @(testDirectory);
#endif
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Strip3/AbletonRecord"];
}
static NSDictionary *RecordJSON(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static id RecordAXValue(AXUIElementRef element,CFStringRef attribute) {
    CFTypeRef value=NULL;
    if(AXUIElementCopyAttributeValue(element,attribute,&value)!=kAXErrorSuccess || !value) return nil;
    return CFBridgingRelease(value);
}
static NSString *RecordTrackNameFromAXTitle(NSString *title) {
    NSString *name=[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Live decorates selected row titles with transient track states, e.g.
    // "20-Bandøledu, Armed". Match the stable track name from the LOM.
    for(NSString *suffix in @[@", Armed",@", Muted",@", Solo"]) {
        if([name hasSuffix:suffix]) {
            name=[[name substringToIndex:name.length-suffix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
    }
    return name;
}
static void RecordSelectedTrackTitles(AXUIElementRef element,NSMutableArray<NSString *> *titles,NSInteger depth,NSInteger *visited) {
    if(depth>24 || (*visited)++>6000) return;
    NSString *role=RecordAXValue(element,kAXRoleAttribute);
    NSString *identifier=RecordAXValue(element,CFSTR("AXIdentifier"));
    if([role isEqualToString:(__bridge NSString *)kAXOutlineRole] &&
       ([identifier containsString:@"ArrangementView"] || [identifier containsString:@"SessionView"])) {
        NSArray *selectedRows=RecordAXValue(element,CFSTR("AXSelectedRows"));
        for(id object in selectedRows) {
            AXUIElementRef row=(__bridge AXUIElementRef)object;
            NSString *rowID=RecordAXValue(row,CFSTR("AXIdentifier"));
            if(![rowID containsString:@".Track["] && ![rowID containsString:@".GroupTrack["]) continue;
            NSString *title=RecordTrackNameFromAXTitle(RecordAXValue(row,kAXTitleAttribute));
            if(title.length && ![titles containsObject:title]) [titles addObject:title];
        }
    }
    NSArray *children=RecordAXValue(element,kAXChildrenAttribute);
    for(id object in children) {
        if(CFGetTypeID((__bridge CFTypeRef)object)!=AXUIElementGetTypeID()) continue;
        RecordSelectedTrackTitles((__bridge AXUIElementRef)object,titles,depth+1,visited);
        if(*visited>6000) return;
    }
}
static NSArray<NSString *> *RecordLiveSelectedTrackTitles(pid_t pid) {
    static BOOL requestedPermission=NO;
    if(!AXIsProcessTrusted()) {
        if(!requestedPermission) {
            requestedPermission=YES;
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
        }
        return @[];
    }
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    if(!app) return @[];
    NSMutableArray *titles=[NSMutableArray new]; NSInteger visited=0;
    RecordSelectedTrackTitles(app,titles,0,&visited);
    CFRelease(app);
    return titles;
}
static void ApplyRecordLight(StripRecordButton *button,BOOL connected,NSDictionary *state) {
    button.recordLit=connected && [state[@"record"] boolValue];
    button.needsDisplay=YES;
    button.bezelColor=button.recordLit ? NSColor.systemRedColor : nil;
    button.contentTintColor=NSColor.whiteColor;
}
@implementation StripRecordButton
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.image=[NSImage imageWithSystemSymbolName:@"record.circle" accessibilityDescription:@"Ableton Record"];
        self.contentTintColor=NSColor.whiteColor;
        [self setAccessibilityLabel:@"Ableton Record: tap for Arrangement Record; swipe right to arm selected tracks and left to disarm them; in Control Surface Mode swipe right to arm only selected tracks and disarm the rest, or left to toggle all tracks; hold without swiping for recording options"];
    }
    return self;
}
- (void)step:(NSInteger)direction {
    if(!self.tracking || self.cancelled || self.held || self.didStep) return;
    self.pendingSwipeDirection=direction;
}
- (void)beginAt:(NSPoint)point identity:(id)identity {
    [super beginAt:point identity:identity];
    self.controlSurfaceGesture=[self.recordController isControlSurfaceMode];
}
- (void)finishAt:(NSPoint)point {
    if(!self.tracking) return;
    [self moveAt:point];
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.cancelled && !self.didStep && self.pendingSwipeDirection) {
        self.didStep=YES;
        if(self.controlSurfaceGesture && self.pendingSwipeDirection>0) {
            NSArray *indices=[self.recordController selectedTrackIndicesForSwipe];
            [self.recordController send:@"arm-exclusive" payload:@{@"track_indices":indices}];
        } else if(self.controlSurfaceGesture)
            [self.recordController send:@"arm-all-toggle"];
        else {
            NSArray *indices=[self.recordController selectedTrackIndicesForSwipe];
            [self.recordController send:self.pendingSwipeDirection>0 ? @"arm-on" : @"arm-off"
                                  payload:@{@"track_indices":indices}];
        }
    }
    if(!self.cancelled && !self.held && !self.didStep &&
       NSPointInRect(point,self.bounds) && hypot(point.x-self.startX,point.y-self.startY)<8)
        [self.recordController send:@"record"];
    self.tracking=NO; self.touchIdentity=nil; self.pendingSwipeDirection=0; [self highlight:NO];
}
- (void)cancelGesture { self.pendingSwipeDirection=0; [super cancelGesture]; }
- (void)fireHold {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.tracking || self.cancelled || self.held || self.didStep ||
       fabs(self.endX-self.startX)>=8 || fabs(self.endY-self.startY)>=3) return;
    self.held=YES;
    __weak StripRecordController *controller=self.recordController;
    __weak StripRecordButton *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.24*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        StripRecordButton *button=weakSelf;
        if(button.tracking && button.held) [controller showOptions];
    });
}
- (BOOL)accessibilityPerformPress { [self.recordController send:@"record"]; return YES; }
@end
@implementation StripPerformanceButton
- (void)beginAt:(NSPoint)point identity:(id)identity {
    [super beginAt:point identity:identity];
    if([self.identifier isEqual:@"tempo"]) { self.dragStartTempo=[self.recordController.state[@"tempo"] doubleValue]; self.dragSession=self.recordController.state[@"session_id"] ?: @""; }
}
- (void)moveAt:(NSPoint)point {
    if(![self.identifier isEqual:@"tempo"]) { [super moveAt:point]; return; }
    if(!self.tracking || self.cancelled || self.held) return;
    self.endX=point.x; self.endY=point.y;
    CGFloat dx=point.x-self.startX,dy=point.y-self.startY;
    if(fabs(dx)>=8 || fabs(dy)>=3) { [self.holdTimer invalidate]; self.holdTimer=nil; }
    if((!self.enabled && !self.didStep) || ![self.dragSession isEqual:self.recordController.state[@"session_id"] ?: @""] || fabs(dy)>12 || (!self.didStep && (fabs(dx)<8 || fabs(dx)<fabs(dy)))) return;
    self.didStep=YES; [self highlight:NO];
    // Absolute target from gesture origin: reversals and coalesced events
    // cannot lose distance while a previous command awaits acknowledgment.
    [self.recordController setTempoFromDrag:MAX(20,MIN(999,self.dragStartTempo+round(dx/4.0)))];
}
- (void)drawRect:(NSRect)dirty {
    if(![self.identifier isEqual:@"loop"]) { [super drawRect:dirty]; return; }
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *background=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0,1) xRadius:7 yRadius:7];
    [[NSColor colorWithWhite:self.highlighted ? .28 : .16 alpha:1] setFill]; [background fill];
    NSColor *on=[NSColor colorWithSRGBRed:1 green:.65 blue:.16 alpha:self.enabled ? 1 : .35];
    NSColor *off=[NSColor colorWithWhite:.50 alpha:self.enabled ? 1 : .35];
    for(NSInteger side=0;side<2;side++) {
        NSBezierPath *punch=[NSBezierPath bezierPath];
        if(!side) { [punch moveToPoint:NSMakePoint(7,22)]; [punch lineToPoint:NSMakePoint(14,22)]; [punch lineToPoint:NSMakePoint(21,12)]; }
        else { [punch moveToPoint:NSMakePoint(65,12)]; [punch lineToPoint:NSMakePoint(72,22)]; [punch lineToPoint:NSMakePoint(79,22)]; }
        NSAffineTransform *horizontalScale=[NSAffineTransform transform]; [horizontalScale scaleXBy:NSWidth(self.bounds)/86.0 yBy:1];
        [punch transformUsingAffineTransform:horizontalScale];
        punch.lineWidth=2; punch.lineCapStyle=NSLineCapStyleRound;
        [(side ? self.punchOutActive : self.punchInActive) ? on : off setStroke]; [punch stroke];
    }
    CGFloat xScale=NSWidth(self.bounds)/86.0;
    NSColor *tint=self.loopActive ? on : [NSColor colorWithWhite:.90 alpha:self.enabled ? 1 : .35];
    NSImage *image=[NSImage imageWithSystemSymbolName:@"repeat" accessibilityDescription:@"Loop"];
    NSImage *glyph=[NSImage imageWithSize:NSMakeSize(18,14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [image drawInRect:rect]; [tint setFill]; NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn); return YES;
    }];
    [glyph drawInRect:NSMakeRect(34*xScale,14,18*xScale,14)];
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightMedium],NSForegroundColorAttributeName:tint};
    NSSize text=[self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds)-text.width)/2,2) withAttributes:attributes];
    [NSGraphicsContext restoreGraphicsState];
}
- (void)step:(NSInteger)direction {
    if(!self.enabled || !self.tracking || self.cancelled || self.held || self.didStep) return;
    self.didStep=YES; [self.holdTimer invalidate]; self.holdTimer=nil; [self highlight:NO];
    NSString *action=direction>0 ? self.swipeForward : self.swipeBack;
    if(action) [self.recordController perform:action];
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.tracking) return;
    [self moveAt:point];
    if(self.enabled && !self.cancelled && !self.held && !self.didStep && NSPointInRect(point,self.bounds) && hypot(point.x-self.startX,point.y-self.startY)<8)
        [self.recordController perform:self.identifier];
    self.tracking=NO; self.touchIdentity=nil; [self highlight:NO];
}
- (void)fireHold {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.enabled || !self.holdMenu || !self.tracking || self.cancelled || self.held || self.didStep || fabs(self.endX-self.startX)>=8 || fabs(self.endY-self.startY)>=3) return;
    self.held=YES;
    __weak StripRecordController *controller=self.recordController; NSString *menu=self.holdMenu;
    dispatch_async(dispatch_get_main_queue(),^{ [controller showMenu:menu]; });
}
- (BOOL)accessibilityPerformPress { if(!self.enabled) return NO; [self.recordController perform:self.identifier]; return YES; }
@end
@implementation StripRecordController
- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    for(NSTouchBarItem *item in touchBar.templateItems) if([item.identifier isEqual:identifier]) return item;
    return nil;
}
- (StripPerformanceButton *)performanceButton:(NSString *)action label:(NSString *)label symbol:(NSString *)symbol {
    StripPerformanceButton *button=[[StripPerformanceButton alloc] initWithFrame:NSMakeRect(0,0,54,30)];
    button.recordController=self; button.identifier=action; button.title=label;
    button.image=nil; button.imagePosition=NSNoImage;
    button.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    if(symbol) { button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label]; button.imagePosition=NSImageOnly; }
    CGFloat width=[action isEqual:@"loop"] ? 76 : [action isEqual:@"tempo"] ? 86 : [action hasPrefix:@"punch"] ? 64 : symbol ? 54 : MAX(54,[label sizeWithAttributes:@{NSFontAttributeName:button.font}].width+20);
    [button.widthAnchor constraintEqualToConstant:width].active=YES;
    [button setAccessibilityLabel:label]; button.toolTip=label;
    self.options[action]=button; return button;
}
- (NSTouchBar *)performanceBar:(NSArray<NSArray *> *)specs {
    NSMutableArray *items=[NSMutableArray new], *ids=[NSMutableArray new];
    for(NSArray *spec in specs) {
        NSString *action=spec[0], *label=spec[1], *symbol=spec.count>2 ? spec[2] : nil;
        NSString *identifier=[RecordID stringByAppendingFormat:@".performance.%@",action];
        StripPerformanceButton *button=[self performanceButton:action label:label symbol:symbol];
        NSTouchBarItem *item;
        if([@[@"loop",@"tempo",@"more"] containsObject:action]) {
            NSPopoverTouchBarItem *popover=[[NSPopoverTouchBarItem alloc] initWithIdentifier:identifier];
            popover.customizationLabel=label;
            // AppKit applies NSButton's bezel alignment outsets to a direct
            // collapsed representation, clipping our edge-drawn Punch icons.
            // A plain, fixed-size host keeps the full drawing and touch region.
            CGFloat width=[action isEqual:@"loop"] ? 76 : [action isEqual:@"tempo"] ? 86 : 54;
            NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,width,30)];
            [host.widthAnchor constraintEqualToConstant:width].active=YES;
            [host.heightAnchor constraintEqualToConstant:30].active=YES;
            button.frame=host.bounds; button.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
            [host addSubview:button];
            popover.collapsedRepresentation=host; popover.showsCloseButton=YES;
            self.performanceMenus[action]=popover; button.holdMenu=action;
            if([action isEqual:@"tempo"]) { button.swipeForward=@"tempo-up"; button.swipeBack=@"tempo-down"; }
            if([action isEqual:@"loop"]) { button.swipeForward=@"punch-out"; button.swipeBack=@"punch-in"; }
            item=popover;
        } else {
            NSCustomTouchBarItem *control=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier]; control.view=button; control.customizationLabel=label; item=control;
        }
        item.visibilityPriority=NSTouchBarItemPriorityHigh;
        [items addObject:item]; [ids addObject:identifier];
    }
    NSTouchBar *bar=[NSTouchBar new]; bar.templateItems=[NSSet setWithArray:items]; bar.defaultItemIdentifiers=ids; return bar;
}
- (instancetype)init {
    if((self=[super init])) {
        // Keep Record as a plain custom view. NSPopoverTouchBarItem consumes
        // the initial touch to open its popover, preventing our swipe/hold
        // recognizer from seeing the full gesture on the outer bar.
        self.item=[[NSCustomTouchBarItem alloc] initWithIdentifier:RecordID];
        self.item.customizationLabel=@"Ableton Record";
        self.item.visibilityPriority=NSTouchBarItemPriorityHigh;
        self.button=[[StripRecordButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        self.button.recordController=self;
        [self.button.widthAnchor constraintEqualToConstant:32].active=YES;
        self.item.view=self.button;
        self.options=[NSMutableDictionary dictionary];
        self.performanceMenus=[NSMutableDictionary dictionary];
        self.menuStack=[NSMutableArray new];
        self.menuRecordButtons=[NSHashTable weakObjectsHashTable];
        self.optionsTouchBar=[self performanceBar:@[
            @[@"loop",@"Loop",@"repeat"], @[@"tempo",@"BPM"], @[@"more",@"More",@"ellipsis"]
        ]];
        self.performanceMenus[@"loop"].popoverTouchBar=[self performanceBar:@[
            @[@"loop-1",@"1 bar"], @[@"loop-2",@"2 bars"], @[@"loop-4",@"4 bars"], @[@"loop-8",@"8 bars"],
            @[@"loop-half",@"÷2"], @[@"loop-double",@"×2"], @[@"loop-prev",@"← Loop"], @[@"loop-next",@"Loop →"]
        ]];
        self.performanceMenus[@"tempo"].popoverTouchBar=[self performanceBar:@[
            @[@"tempo-down",@"−1 BPM"], @[@"tempo-up",@"+1 BPM"],
            @[@"tempo-down-fine",@"−0.1"], @[@"tempo-up-fine",@"+0.1"]
        ]];
        self.performanceMenus[@"more"].popoverTouchBar=[self performanceBar:@[
            @[@"session-capture",@"Session Rec"], @[@"overdub",@"Overdub"], @[@"click",@"Click"],
            @[@"quantization",@"Record Q"], @[@"automation-arm",@"Auto Arm"],
            @[@"re-enable-automation",@"Re-enable"], @[@"stop-clips",@"Stop Clips"]
        ]];
        self.options[@"loop"].toolTip=@"Tap: Loop. Swipe left: Punch In. Swipe right: Punch Out. Hold: loop lengths and resize.";
        self.options[@"tempo"].toolTip=@"Tap: Tap Tempo. Swipe: ±1 BPM. Hold: fine/coarse tempo controls.";
        __weak StripRecordController *weakSelf=self;
        self.pollTimer=[NSTimer timerWithTimeInterval:.2 repeats:YES block:^(NSTimer *timer){ [weakSelf refresh]; }];
        [NSRunLoop.mainRunLoop addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
        [self refresh];
    }
    return self;
}
- (BOOL)connected {
    NSDictionary *state=self.state;
    NSTimeInterval age=NSDate.date.timeIntervalSince1970-[state[@"time"] doubleValue];
    NSRunningApplication *live=[NSRunningApplication runningApplicationWithProcessIdentifier:[state[@"pid"] intValue]];
    return [state[@"protocol"] integerValue]==1 && age>=-1 && age<3 &&
        [live.bundleIdentifier isEqualToString:@"com.ableton.live"] && !live.terminated;
}
- (BOOL)isControlSurfaceMode {
    return self.activeMenuBar!=nil || [[(id)NSApp.delegate valueForKey:@"controlSurfadeMode"] boolValue];
}
- (NSArray<NSNumber *> *)selectedTrackIndicesForSwipe {
    NSInteger primary=[self.state[@"track_index"] integerValue];
    NSArray<NSDictionary *> *tracks=[self.state[@"tracks"] isKindOfClass:NSArray.class] ? self.state[@"tracks"] : @[];
    if(!tracks.count) return primary>=0 ? @[@(primary)] : @[];
    NSArray<NSString *> *selectedNames=RecordLiveSelectedTrackTitles([self.state[@"pid"] intValue]);
    if(!selectedNames.count) return primary>=0 ? @[@(primary)] : @[];
    NSMutableArray<NSNumber *> *indices=[NSMutableArray new];
    NSMutableSet<NSNumber *> *used=[NSMutableSet new];
    for(NSString *name in selectedNames) {
        NSNumber *match=nil;
        for(NSDictionary *track in tracks) {
            NSNumber *index=track[@"index"];
            if([track[@"name"] isEqual:name] && ![used containsObject:index]) {
                match=index;
                if(index.integerValue==primary) break;
            }
        }
        if(match) { [indices addObject:match]; [used addObject:match]; }
    }
    if(!indices.count && primary>=0) return @[@(primary)];
    return indices;
}
- (void)notice:(NSString *)message {
    self.message=message; self.messageUntil=NSDate.date.timeIntervalSince1970+3;
    NSLog(@"Strip3 Record: %@",message);
    [self refresh];
}
- (void)send:(NSString *)action {
    [self refresh];
    [self send:action payload:@{}];
}
- (void)send:(NSString *)action payload:(NSDictionary *)payload {
    if(self.pending) {
        // Arm-on/off are explicit states, so keep the newest request if a
        // second swipe lands before Live acknowledges the previous command.
        if([@[@"arm-on",@"arm-off"] containsObject:action])
            self.queuedArmCommand=@{@"action":action,@"payload":payload.copy ?: @{}};
        return;
    }
    if(![self connected]) { [self notice:@"Live link?"]; return; }
    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
    if([self writeCommand:action payload:payload token:token]) {
        self.pending=token; self.pendingTime=NSDate.date.timeIntervalSince1970;
    }
}
- (BOOL)writeCommand:(NSString *)action payload:(NSDictionary *)payload token:(NSString *)token {
    NSString *directory=[RecordDirectory() stringByAppendingPathComponent:@"commands"];
    NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        self.message=@"Link error"; self.messageUntil=NSDate.date.timeIntervalSince1970+3; return NO;
    }
    NSMutableDictionary *command=[@{@"session":self.state[@"session_id"] ?: @"", @"action":action,
        @"time":@(NSDate.date.timeIntervalSince1970), @"track_index":self.state[@"track_index"] ?: @(-1)} mutableCopy];
    [command addEntriesFromDictionary:payload];
    NSData *data=[NSJSONSerialization dataWithJSONObject:command options:0 error:&error];
    if(!data || ![data writeToFile:[directory stringByAppendingPathComponent:[token stringByAppendingString:@".json"]] options:NSDataWritingAtomic error:&error]) {
        self.message=@"Link error"; self.messageUntil=NSDate.date.timeIntervalSince1970+3; return NO;
    }
    return YES;
}
- (void)setTempoFromDrag:(double)tempo {
    if(!isfinite(tempo) || ![self connected]) return;
    if([self.state[@"performance"] integerValue]!=1) return;
    self.queuedTempo=@(MAX(20,MIN(999,tempo))); self.queuedTempoSession=self.state[@"session_id"];
    [self refresh];
}
- (void)option:(NSButton *)sender { [self send:sender.identifier]; }
- (void)perform:(NSString *)action {
    if([action isEqual:@"tempo"]) [self send:@"tap-tempo"];
    else if([action isEqual:@"more"]) [self showMenu:action];
    else [self send:action];
}
- (void)presentMenuBar:(NSTouchBar *)source {
    if(!source || !presentation) return;
    if(!self.menuStack.count) self.menuReturnBar=presentation;
    NSTouchBar *bar=[NSTouchBar new];
    NSCustomTouchBarItem *record=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.record"];
    StripRecordButton *button=[[StripRecordButton alloc] initWithFrame:NSMakeRect(0,0,32,30)];
    button.recordController=self; button.standaloneRecord=YES;
    // Use the same direct button view as normal MIDI so AppKit applies
    // identical alignment insets at the shared right edge.
    [button.widthAnchor constraintEqualToConstant:32].active=YES;
    record.view=button;record.visibilityPriority=NSTouchBarItemPriorityHigh;
    [self.menuRecordButtons addObject:button];
    ApplyRecordLight(button,[self connected],self.state);
    NSString *nativeID=@"local.musicstrip.performance.native-surface";
    if([source.itemIdentifiers containsObject:nativeID]) {
        NSString *loopID=[RecordID stringByAppendingString:@".performance.loop"];
        NSString *tempoID=[RecordID stringByAppendingString:@".performance.tempo"];
        NSString *moreID=[RecordID stringByAppendingString:@".performance.more"];
        NSMutableSet *rootItems=source.templateItems.mutableCopy;
        [rootItems addObject:record]; bar.templateItems=rootItems;
        // Match normal MIDI: Record owns the fixed rightmost slot. Loop,
        // Tempo, More and the native surface use the area to its left.
        bar.defaultItemIdentifiers=@[loopID,tempoID,moreID,NSTouchBarItemIdentifierFlexibleSpace,nativeID,record.identifier];
        // The trailing Record slot is positioned by flexible space, as in MIDI.
    } else {
        // Keep the source's real items directly on the root bar. A nested
        // group adds native alignment padding that shifts the Record slot.
        NSMutableSet *items=source.templateItems.mutableCopy;[items addObject:record];
        bar.templateItems=items;bar.delegate=source.delegate;
        NSMutableArray *ids=source.itemIdentifiers.mutableCopy;
        [ids addObjectsFromArray:@[NSTouchBarItemIdentifierFlexibleSpace,record.identifier]];
        bar.defaultItemIdentifiers=ids;
    }
    ((void(*)(id,SEL,id))originalClose)(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),self.activeMenuBar ?: presentation);
    self.activeMenuBar=bar; [self.menuStack addObject:bar];
    ((void(*)(id,SEL,id,id))originalOpen)(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,normalIdentifier);
}
- (void)backMenu:(id)sender {
    if(!self.activeMenuBar) return;
    ((void(*)(id,SEL,id))originalClose)(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),self.activeMenuBar);
    [self.menuStack removeLastObject];
    NSTouchBar *next=self.menuStack.lastObject ?: self.menuReturnBar;
    self.activeMenuBar=self.menuStack.lastObject;
    if(!self.menuStack.count) { self.menuReturnBar=nil; [(id)NSApp.delegate setValue:@(self.returnSurfaceMode) forKey:@"controlSurfadeMode"]; }
    ((void(*)(id,SEL,id,id))originalOpen)(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),next,normalIdentifier);
}
- (void)returnToMidi {
    if(!self.activeMenuBar) return;
    ((void(*)(id,SEL,id))originalClose)(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),self.activeMenuBar);
    NSTouchBar *normal=self.menuReturnBar ?: presentation;
    self.activeMenuBar=nil; self.menuReturnBar=nil; [self.menuStack removeAllObjects];
    [(id)NSApp.delegate setValue:@(self.returnSurfaceMode) forKey:@"controlSurfadeMode"];
    ((void(*)(id,SEL,id,id))originalOpen)(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),normal,normalIdentifier);
}
- (void)showMenu:(NSString *)name { [self refresh]; [self presentMenuBar:self.performanceMenus[name].popoverTouchBar]; }
- (void)showOptions {
    if(self.activeMenuBar) { [self returnToMidi]; return; }
    [self refresh];
    self.returnSurfaceMode=[[(id)NSApp.delegate valueForKey:@"controlSurfadeMode"] boolValue];
    [(id)NSApp.delegate setValue:@YES forKey:@"controlSurfadeMode"];
    NSTouchBar *source=[NSTouchBar new];
    NSMutableSet *items=self.optionsTouchBar.templateItems.mutableCopy;
    NSMutableArray *ids=self.optionsTouchBar.defaultItemIdentifiers.mutableCopy;
    // Preserve the vendor's actual control-surface view, delegates and MIDI
    // ports. Only its outer navigation/close wrapper is replaced.
    @try {
        NSTouchBar *nativeBar=[(id)NSApp.delegate valueForKey:@"controlStripGroup"];
        NSCustomTouchBarItem *original=(id)[nativeBar itemForIdentifier:@"com.uebe.midi-touchbar.controlstrip-view"];
        // Resolve through the vendor bar's item factory. The delegate's item
        // property alone is still an uninitialized blank view on first use.
        if(!self.nativeSurfaceView) self.nativeSurfaceView=[original valueForKey:@"view"];
        if(self.nativeSurfaceView) {
            // Reparent its real view into a fresh item; retain the original
            // delegate and parameter state instead of rebuilding the controls.
            [self.nativeSurfaceView removeFromSuperview];
            CGFloat host=lastMidiHostWidth>200 ? lastMidiHostWidth : 1004;
            CGFloat width=MAX(320,host-32-76-86-54-48);
            for(NSLayoutConstraint *constraint in self.nativeSurfaceView.constraints)
                if(constraint.firstAttribute==NSLayoutAttributeWidth && !constraint.secondItem && constraint.relation==NSLayoutRelationEqual) constraint.active=NO;
            NSView *hostView=[[NSView alloc] initWithFrame:NSMakeRect(0,0,width,30)];
            [hostView.widthAnchor constraintEqualToConstant:width].active=YES;
            [hostView.heightAnchor constraintEqualToConstant:30].active=YES;
            self.nativeSurfaceView.translatesAutoresizingMaskIntoConstraints=NO;
            [hostView addSubview:self.nativeSurfaceView];
            [NSLayoutConstraint activateConstraints:@[
                [self.nativeSurfaceView.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
                [self.nativeSurfaceView.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
                [self.nativeSurfaceView.topAnchor constraintEqualToAnchor:hostView.topAnchor],
                [self.nativeSurfaceView.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor]
            ]];
            NSCustomTouchBarItem *surface=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.native-surface"];
            surface.view=hostView;
            [items addObject:surface]; [ids insertObject:surface.identifier atIndex:0]; source.principalItemIdentifier=surface.identifier;
            NSCustomTouchBarItem *gap=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.surface-gap"];
            NSView *gapView=[[NSView alloc] initWithFrame:NSMakeRect(0,0,16,30)];
            [gapView.widthAnchor constraintEqualToConstant:16].active=YES; gap.view=gapView;
            [items addObject:gap]; [ids insertObject:gap.identifier atIndex:1];
        }
    } @catch(NSException *exception) { NSLog(@"3£ control surface unavailable: %@",exception.reason); }
    source.templateItems=items; source.defaultItemIdentifiers=ids;
    source.delegate=self;
    [self presentMenuBar:source];
}
- (void)refresh {
    UpdateNavigationColor();
    UpdateActivePianoSizing();
    self.state=RecordJSON([RecordDirectory() stringByAppendingPathComponent:@"state.json"]);
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(self.legacyTempoTokens.count) {
        NSMutableArray *waiting=[NSMutableArray new]; BOOL failed=NO;
        for(NSString *token in self.legacyTempoTokens) {
            NSString *path=[[RecordDirectory() stringByAppendingPathComponent:@"responses"] stringByAppendingPathComponent:[token stringByAppendingString:@".json"]];
            NSDictionary *response=RecordJSON(path);
            if(response) { failed |= ![response[@"ok"] boolValue]; [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }
            else [waiting addObject:token];
        }
        if(failed || now-self.pendingTime>2.5) {
            self.queuedTempo=nil; self.message=@"Live link?"; self.messageUntil=now+3;
        }
        self.legacyTempoTokens=waiting;
        if(!waiting.count || now-self.pendingTime>2.5) { self.legacyTempoTokens=nil; self.pending=nil; }
    }
    if(self.pending && !self.legacyTempoTokens.count) {
        NSString *path=[[RecordDirectory() stringByAppendingPathComponent:@"responses"] stringByAppendingPathComponent:[self.pending stringByAppendingString:@".json"]];
        NSDictionary *response=RecordJSON(path);
        if(response || now-self.pendingTime>2.5) {
            if(response) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            self.pending=nil;
            if(![response[@"ok"] boolValue]) {
                self.message=response ? @"Check track" : @"Live link?"; self.messageUntil=now+3;
                NSLog(@"Strip3 Record: %@",response[@"error"] ?: @"Live did not acknowledge command");
            }
        }
    }
    if(self.queuedArmCommand && !self.pending) {
        NSDictionary *next=self.queuedArmCommand;
        self.queuedArmCommand=nil;
        [self send:next[@"action"] payload:next[@"payload"]];
    }
    BOOL connected=[self connected];
    if(self.queuedTempo && (!connected || ![self.queuedTempoSession isEqual:self.state[@"session_id"]])) self.queuedTempo=nil;
    if(self.queuedTempo && !self.pending) {
        NSNumber *tempo=self.queuedTempo;
        if([self.state[@"tempo_drag"] integerValue]==1) {
            self.queuedTempo=nil; [self send:@"tempo-set" payload:@{@"tempo":tempo}];
        } else {
            // Old Live scripts already understand these operations. Submit a
            // bounded batch per acknowledgment, not one step per gesture.
            double difference=tempo.doubleValue-[self.state[@"tempo"] doubleValue];
            BOOL coarse=fabs(difference)>=1;
            NSInteger steps=MIN(32,coarse ? (NSInteger)floor(fabs(difference)+.0001) : (NSInteger)llround(fabs(difference)/.1));
            if(!steps) self.queuedTempo=nil;
            else {
                NSString *action=difference>0 ? (coarse ? @"tempo-up" : @"tempo-up-fine") : (coarse ? @"tempo-down" : @"tempo-down-fine");
                NSMutableArray *tokens=[NSMutableArray new];
                for(NSInteger i=0;i<steps;i++) {
                    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
                    if(![self writeCommand:action payload:@{} token:token]) { self.queuedTempo=nil; break; }
                    [tokens addObject:token];
                }
                self.legacyTempoTokens=tokens; self.pending=tokens.lastObject; self.pendingTime=now;
            }
        }
    }
    UpdateLiveScale(self.state,connected);
    BOOL armed=connected && [self.state[@"armed"] boolValue];
    ApplyRecordLight(self.button,connected,self.state);
    for(StripRecordButton *button in self.menuRecordButtons.allObjects) ApplyRecordLight(button,connected,self.state);
    self.button.toolTip=connected ? [NSString stringWithFormat:@"Ableton Record — %@%@",self.state[@"track_name"] ?: @"",armed ? @" (armed)" : @""] : @"Open Ableton with its MIDITouchbar control surface enabled";
    // Keep the Record glyph stable. Connection/command notices belong in its
    // tooltip and menu controls; replacing its image with transient text makes
    // the button look like a gesture label and can obscure the touch target.
    self.button.imagePosition=NSImageOnly;
    self.button.title=@"";
    [self refreshButtonsConnected:connected];
}
- (void)refreshButtonsConnected:(BOOL)connected {
    for(NSString *action in self.options) {
        NSButton *button=self.options[action];
        BOOL menu=[action isEqual:@"more"];
        BOOL legacy=[@[@"record",@"session",@"punch-in",@"punch-out",@"overdub",@"loop",@"click",@"quantization"] containsObject:action];
        BOOL performance=connected && [self.state[@"performance"] integerValue]==1;
        button.enabled=menu || (connected && (!self.pending || [action isEqual:@"tempo"]) && (legacy || performance));
        BOOL active=connected && [self.state[[action isEqual:@"session-capture"] ? @"session" : action] boolValue];
        button.bezelColor=active ? ([action isEqual:@"record"] || [action isEqual:@"session-capture"] ? NSColor.systemRedColor : NSColor.systemOrangeColor) : nil;
        button.contentTintColor=NSColor.whiteColor;
        if([action isEqual:@"play"]) {
            BOOL playing=performance && [self.state[@"playing"] boolValue];
            button.image=[NSImage imageWithSystemSymbolName:playing ? @"pause.fill" : @"play.fill" accessibilityDescription:playing ? @"Pause" : @"Play"];
            button.bezelColor=playing ? NSColor.systemGreenColor : nil;
        }
        if([action isEqual:@"tempo"]) button.title=performance ? [NSString stringWithFormat:@"%.1f BPM",[self.state[@"tempo"] doubleValue]] : @"— BPM";
        if([action isEqual:@"loop"]) {
            CGFloat beats=[self.state[@"beats_per_bar"] doubleValue];
            CGFloat bars=beats>0 ? [self.state[@"loop_length"] doubleValue]/beats : 0;
            button.title=performance ? [NSString stringWithFormat:@"%.2g bar",bars] : @"Loop";
            button.imagePosition=NSImageLeft;
            StripPerformanceButton *loop=(id)button;
            loop.loopActive=connected && [self.state[@"loop"] boolValue];
            loop.punchInActive=connected && [self.state[@"punch-in"] boolValue];
            loop.punchOutActive=connected && [self.state[@"punch-out"] boolValue];
            loop.needsDisplay=YES;
            [loop setAccessibilityLabel:[NSString stringWithFormat:@"Loop %@. Punch In %@. Punch Out %@. Tap Loop; swipe left Punch In; swipe right Punch Out.",loop.loopActive ? @"on" : @"off",loop.punchInActive ? @"on" : @"off",loop.punchOutActive ? @"on" : @"off"]];
        }
        if([action isEqualToString:@"quantization"]) {
            NSInteger q=[self.state[@"quantization"] integerValue];
            button.title=q==2 ? @"Q: 1/8" : q==5 ? @"Q: 1/16" : q==0 ? @"Q: Off" : @"Record Q";
            button.bezelColor=nil;
        }
    }
}
- (void)dealloc { [self.pollTimer invalidate]; [self.button cancelGesture]; }
@end
