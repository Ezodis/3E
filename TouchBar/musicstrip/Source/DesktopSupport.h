// Space metadata uses SkyLight's managed-display APIs; no synthetic key or
// undocumented CGEventType values are posted for Spaces navigation.
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
    NSString *display=spaces[(NSUInteger)destination][@"display"];
    if(!display.length) { NSLog(@"Cannot identify the display for this Space."); return; }
    void *sky=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
    int (*connection)(void)=dlsym(sky,"CGSMainConnectionID");
    int (*setCurrentSpace)(int,CFStringRef,uint64_t)=dlsym(sky,"SLSManagedDisplaySetCurrentSpace");
    if(!setCurrentSpace)setCurrentSpace=dlsym(sky,"CGSManagedDisplaySetCurrentSpace");
    if(!connection||!setCurrentSpace) { NSLog(@"This macOS version does not expose direct Space selection."); return; }
    setCurrentSpace(connection(),(__bridge CFStringRef)display,target);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ AdvanceDesktopSelection(target,sequence,attempts-1); });
}
static void SelectDesktop(uint64_t target) {
    AdvanceDesktopSelection(target,++desktopSelectionSequence,DesktopSpaces().count+2);
}
static void StepDesktop(NSInteger direction) {
    if(!direction)return;
    NSArray *spaces=DesktopSpaces();NSInteger active=-1;
    if(spaces.count<=1) { PostMacSystemAction(@"missionControl",0);return; }
    for(NSUInteger i=0;i<spaces.count;i++)if([spaces[i][@"active"] boolValue]){active=(NSInteger)i;break;}
    NSInteger destination=active+(direction>0?1:-1);
    if(active<0||destination<0||destination>=(NSInteger)spaces.count)return;
    SelectDesktop([spaces[(NSUInteger)destination][@"id"] unsignedLongLongValue]);
}
