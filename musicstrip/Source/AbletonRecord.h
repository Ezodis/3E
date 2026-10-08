// Included after MidiNavigationButton: reuse its proven direct-touch tracking.
// Commands are acknowledged by Live's control-surface thread, not UI guesses.
static NSString *const RecordID = @"local.musicstrip.midi.ableton-record";
@class StripRecordController;
@interface StripRecordButton : MidiNavigationButton
@property (weak) StripRecordController *recordController;
@end
@interface StripPerformanceButton : MidiNavigationButton
@property (weak) StripRecordController *recordController;
@property NSString *holdMenu;
@property NSString *swipeForward;
@property NSString *swipeBack;
@end
@interface StripRecordController : NSObject
@property NSPopoverTouchBarItem *item;
@property StripRecordButton *button;
@property NSTimer *pollTimer;
@property NSDictionary *state;
@property NSMutableDictionary<NSString *,NSButton *> *options;
@property NSMutableDictionary<NSString *,NSPopoverTouchBarItem *> *performanceMenus;
@property NSMutableArray<NSTouchBar *> *menuStack;
@property NSTouchBar *menuReturnBar;
@property NSTouchBar *activeMenuBar;
@property NSString *pending;
@property NSTimeInterval pendingTime;
@property NSString *message;
@property NSTimeInterval messageUntil;
- (void)send:(NSString *)action;
- (void)showOptions;
- (void)refresh;
- (void)showMenu:(NSString *)name;
- (void)perform:(NSString *)action;
- (void)refreshButtonsConnected:(BOOL)connected;
- (void)backMenu:(id)sender;
@end
static StripRecordController *recordController;
static NSString *RecordDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Strip3/AbletonRecord"];
}
static NSDictionary *RecordJSON(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
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
        [self setAccessibilityLabel:@"Ableton Record: tap for Arrangement Record; swipe right to arm selected track without disarming others, left to disarm selected track; hold for recording options"];
    }
    return self;
}
- (void)step:(NSInteger)direction {
    if(!self.tracking || self.cancelled || self.held || self.didStep) return;
    self.didStep=YES; [self.holdTimer invalidate]; self.holdTimer=nil;
    [self highlight:NO];
    [self.recordController send:direction>0 ? @"arm-on" : @"arm-off"];
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.tracking) return;
    [self moveAt:point];
    if(!self.cancelled && !self.held && !self.didStep &&
       NSPointInRect(point,self.bounds) && hypot(point.x-self.startX,point.y-self.startY)<8)
        [self.recordController send:@"record"];
    self.tracking=NO; self.touchIdentity=nil; [self highlight:NO];
}
- (void)fireHold {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if(!self.tracking || self.cancelled || self.held || self.didStep ||
       fabs(self.endX-self.startX)>=8 || fabs(self.endY-self.startY)>=3) return;
    self.held=YES;
    __weak StripRecordController *controller=self.recordController;
    dispatch_async(dispatch_get_main_queue(),^{ [controller showOptions]; });
}
- (BOOL)accessibilityPerformPress { [self.recordController send:@"record"]; return YES; }
@end
@implementation StripPerformanceButton
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
- (StripPerformanceButton *)performanceButton:(NSString *)action label:(NSString *)label symbol:(NSString *)symbol {
    StripPerformanceButton *button=[[StripPerformanceButton alloc] initWithFrame:NSMakeRect(0,0,54,30)];
    button.recordController=self; button.identifier=action; button.title=label;
    button.image=nil; button.imagePosition=NSNoImage;
    button.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    if(symbol) { button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label]; button.imagePosition=NSImageOnly; }
    CGFloat width=[@[@"tempo",@"loop"] containsObject:action] ? 86 : [action hasPrefix:@"punch"] ? 64 : symbol ? 54 : MAX(54,[label sizeWithAttributes:@{NSFontAttributeName:button.font}].width+20);
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
            popover.collapsedRepresentation=button; popover.showsCloseButton=YES;
            self.performanceMenus[action]=popover; button.holdMenu=action;
            if([action isEqual:@"tempo"]) { button.swipeForward=@"tempo-up"; button.swipeBack=@"tempo-down"; }
            if([action isEqual:@"loop"]) { button.swipeForward=@"loop-next"; button.swipeBack=@"loop-prev"; }
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
        self.item=[[NSPopoverTouchBarItem alloc] initWithIdentifier:RecordID];
        self.item.customizationLabel=@"Ableton Record";
        self.item.visibilityPriority=NSTouchBarItemPriorityHigh;
        self.item.showsCloseButton=YES;
        self.button=[[StripRecordButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        self.button.recordController=self;
        [self.button.widthAnchor constraintEqualToConstant:44].active=YES;
        self.item.collapsedRepresentation=self.button;
        self.options=[NSMutableDictionary dictionary];
        self.performanceMenus=[NSMutableDictionary dictionary];
        self.menuStack=[NSMutableArray new];
        self.item.popoverTouchBar=[self performanceBar:@[
            @[@"play",@"Play / Pause",@"play.fill"], @[@"stop",@"Stop",@"stop.fill"],
            @[@"record",@"Record",@"record.circle"], @[@"punch-in",@"Punch In"],
            @[@"loop",@"Loop",@"repeat"], @[@"punch-out",@"Punch Out"],
            @[@"tempo",@"BPM"], @[@"tap-tempo",@"Tap"], @[@"more",@"More",@"ellipsis"]
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
        self.options[@"loop"].toolTip=@"Tap: loop on/off. Hold: loop lengths and resize. Swipe: move loop brace left/right.";
        self.options[@"tempo"].toolTip=@"Swipe: ±1 BPM. Tap or hold: fine/coarse tempo controls.";
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
- (void)notice:(NSString *)message {
    self.message=message; self.messageUntil=NSDate.date.timeIntervalSince1970+3;
    NSLog(@"Strip3 Record: %@",message);
    [self refresh];
}
- (void)send:(NSString *)action {
    [self refresh];
    if(self.pending) return; // Never enqueue repeated toggles while awaiting Live.
    if(![self connected]) { [self notice:@"Live link?"]; return; }
    NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
    NSString *directory=[RecordDirectory() stringByAppendingPathComponent:@"commands"];
    NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        [self notice:@"Link error"]; return;
    }
    NSDictionary *command=@{@"session":self.state[@"session_id"] ?: @"", @"action":action,
        @"time":@(NSDate.date.timeIntervalSince1970), @"track_index":self.state[@"track_index"] ?: @(-1)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:command options:0 error:&error];
    if(!data || ![data writeToFile:[directory stringByAppendingPathComponent:[token stringByAppendingString:@".json"]] options:NSDataWritingAtomic error:&error]) {
        [self notice:@"Link error"]; return;
    }
    self.pending=token; self.pendingTime=NSDate.date.timeIntervalSince1970;
}
- (void)option:(NSButton *)sender { [self send:sender.identifier]; }
- (void)perform:(NSString *)action {
    if([action isEqual:@"tempo"] || [action isEqual:@"more"]) [self showMenu:action];
    else [self send:action];
}
- (void)presentMenuBar:(NSTouchBar *)source {
    if(!source || !presentation) return;
    if(!self.menuStack.count) self.menuReturnBar=presentation;
    NSTouchBar *bar=[NSTouchBar new];
    NSCustomTouchBarItem *back=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.back"];
    NSButton *button=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Back to MIDI"] target:self action:@selector(backMenu:)];
    button.bezelStyle=NSBezelStyleRounded; [button.widthAnchor constraintEqualToConstant:44].active=YES; back.view=button;
    NSGroupTouchBarItem *group=[[NSGroupTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.controls"];
    group.groupTouchBar=source;
    bar.templateItems=[NSSet setWithArray:@[back,group]];
    bar.defaultItemIdentifiers=@[back.identifier,group.identifier];
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
    if(!self.menuStack.count) self.menuReturnBar=nil;
    ((void(*)(id,SEL,id,id))originalOpen)(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),next,normalIdentifier);
}
- (void)showMenu:(NSString *)name { [self refresh]; [self presentMenuBar:self.performanceMenus[name].popoverTouchBar]; }
- (void)showOptions { [self refresh]; [self presentMenuBar:self.item.popoverTouchBar]; }
- (void)refresh {
    UpdateNavigationColor();
    UpdateActivePianoSizing();
    self.state=RecordJSON([RecordDirectory() stringByAppendingPathComponent:@"state.json"]);
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(self.pending) {
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
    BOOL connected=[self connected];
    UpdateLiveScale(self.state,connected);
    BOOL armed=connected && [self.state[@"armed"] boolValue];
    ApplyRecordLight(self.button,connected,self.state);
    self.button.toolTip=connected ? [NSString stringWithFormat:@"Ableton Record — %@%@",self.state[@"track_name"] ?: @"",armed ? @" (armed)" : @""] : @"Open Ableton with its MIDITouchbar control surface enabled";
    BOOL showMessage=self.messageUntil>now;
    self.button.imagePosition=showMessage ? NSNoImage : NSImageOnly;
    self.button.title=showMessage ? self.message : @"";
    self.button.font=[NSFont systemFontOfSize:9];
    [self refreshButtonsConnected:connected];
}
- (void)refreshButtonsConnected:(BOOL)connected {
    for(NSString *action in self.options) {
        NSButton *button=self.options[action];
        BOOL menu=[action isEqual:@"tempo"] || [action isEqual:@"more"];
        BOOL legacy=[@[@"record",@"session",@"punch-in",@"punch-out",@"overdub",@"loop",@"click",@"quantization"] containsObject:action];
        BOOL performance=connected && [self.state[@"performance"] integerValue]==1;
        button.enabled=menu || (connected && !self.pending && (legacy || performance));
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
