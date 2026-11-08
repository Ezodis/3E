// A temporary overlay keeps the original Touch Bar and touch owner alive.
// Switching bars during a hold would cancel the finger before its release.
static NSArray<NSArray *> *MidiWorkspaceCatalog(void) {
    return @[
        @[@"Control Surface", @"slider.horizontal.3", @[]],
        @[@"Clip Settings", @"switch.2", @[@[@"clip-launch",@"Trigger"],@[@"clip-legato",@"Legato"],@[@"clip-quantization",@"Q: Global"],@[@"clip-loop",@"Loop"],@[@"clip-velocity",@"Vel: 0%"]]],
        @[@"Loop Builder", @"square.stack.3d.up", @[@[@"clip-new",@"New 4 bars"],@[@"clip-duplicate",@"Variation"],@[@"clip-double",@"Double"],@[@"clip-down",@"−1 note"],@[@"clip-up",@"+1 note"],@[@"session-capture",@"Session Rec"],@[@"stop-clips",@"Stop Clips"]]],
        @[@"Song Sounds", @"music.note.list", @[@[@"song-diabla",@"DIABLA"],@[@"song-ruff",@"RUFF"],@[@"song-nota",@"NOTA"],@[@"stop-clips",@"Stop Clips"]]],
        @[@"Vocals", @"mic.fill", @[@[@"arm-exclusive",@"Arm selected"],@[@"punch-in",@"Punch In"],@[@"punch-out",@"Punch Out"],@[@"click",@"Click"],@[@"loop-4",@"4 bars"],@[@"play",@"Play / Pause"],@[@"stop",@"Stop"]]],
        @[@"Instruments", @"pianokeys", @[@[@"arm-exclusive",@"Arm selected"],@[@"overdub",@"Overdub"],@[@"click",@"Click"],@[@"quantization",@"Record Q"],@[@"loop-8",@"8 bars"],@[@"session-capture",@"Session Rec"]]],
        @[@"Techno", @"waveform", @[@[@"loop-1",@"1 bar"],@[@"loop-4",@"4 bars"],@[@"loop-8",@"8 bars"],@[@"overdub",@"Overdub"],@[@"quantization",@"Record Q"],@[@"automation-arm",@"Auto Arm"],@[@"tap-tempo",@"Tap BPM"]]],
        @[@"Reggaeton", @"drum.fill", @[@[@"loop-2",@"2 bars"],@[@"loop-4",@"4 bars"],@[@"overdub",@"Overdub"],@[@"quantization",@"Record Q"],@[@"click",@"Click"],@[@"tap-tempo",@"Tap BPM"],@[@"session-capture",@"Session Rec"]]],
        @[@"Loops", @"repeat", @[@[@"loop-1",@"1 bar"],@[@"loop-2",@"2 bars"],@[@"loop-4",@"4 bars"],@[@"loop-8",@"8 bars"],@[@"loop-half",@"÷2"],@[@"loop-double",@"×2"],@[@"loop-prev",@"← Loop"],@[@"loop-next",@"Loop →"]]],
        @[@"Tempo", @"metronome", @[@[@"tap-tempo",@"Tap BPM"],@[@"tempo-down",@"−1 BPM"],@[@"tempo-up",@"+1 BPM"],@[@"tempo-down-fine",@"−0.1"],@[@"tempo-up-fine",@"+0.1"],@[@"click",@"Click"]]],
        @[@"Automation", @"slider.horizontal.3", @[@[@"automation-arm",@"Auto Arm"],@[@"re-enable-automation",@"Re-enable"],@[@"overdub",@"Overdub"],@[@"loop-8",@"8 bars"],@[@"play",@"Play / Pause"],@[@"stop",@"Stop"]]],
        @[@"Session", @"square.grid.3x3.fill", @[@[@"session-capture",@"Session Rec"],@[@"arm-exclusive",@"Arm selected"],@[@"overdub",@"Overdub"],@[@"quantization",@"Record Q"],@[@"play",@"Play / Pause"],@[@"stop-clips",@"Stop Clips"]]]
    ];
}
@interface StripRecordController (Workspaces)
- (void)showWorkspace:(NSInteger)index;
@end
@implementation StripRecordController (Workspaces)
- (void)showWorkspace:(NSInteger)index {
    NSArray *catalog=MidiWorkspaceCatalog();
    if(index<0 || index>=(NSInteger)catalog.count) return;
    [self returnToMidi];
    if(index==0) { [self showOptions]; return; }
    self.returnSurfaceMode=[[(id)NSApp.delegate valueForKey:@"controlSurfadeMode"] boolValue];
    [(id)NSApp.delegate setValue:@YES forKey:@"controlSurfadeMode"];
    NSTouchBar *source=[self performanceBar:catalog[index][2]];
    // Reserve the same X and Record slots even on the shorter laptop bar.
    CGFloat host=lastMidiHostWidth>200 ? lastMidiHostWidth : 685;
    CGFloat width=MAX(42,floor((host-96)/source.itemIdentifiers.count)-8);
    for(NSCustomTouchBarItem *item in source.templateItems) {
        NSButton *button=(id)item.view;
        for(NSLayoutConstraint *constraint in button.constraints)
            if(constraint.firstAttribute==NSLayoutAttributeWidth && !constraint.secondItem)
                constraint.constant=MIN(constraint.constant,width);
        button.font=[NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    }
    [self presentMenuBar:source];
    [self refresh];
}
@end
@interface MidiWorkspaceChooser : NSView
@property NSArray<NSArray *> *choices;
@property (weak) MidiNavigationButton *owner;
@property BOOL workspaces;
@property NSInteger selected;
@property CGFloat offset;
@property NSPoint point;
@property NSTimer *scrollTimer;
- (void)updateAt:(NSPoint)point;
@end
static MidiWorkspaceChooser *midiWorkspaceChooser;
@implementation MidiWorkspaceChooser
- (BOOL)isOpaque { return YES; }
// The original button owns this gesture until release, including outside its bounds.
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (CGFloat)tileWidth { return 112; }
- (void)updateAt:(NSPoint)point {
    self.point=point;
    NSInteger index=(NSInteger)floor((point.x+self.offset)/self.tileWidth);
    self.selected=NSPointInRect(point,self.bounds) && index>=0 && index<(NSInteger)self.choices.count ? index : -1;
    self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirty {
    [NSColor.blackColor setFill]; NSRectFill(self.bounds);
    for(NSInteger i=0;i<(NSInteger)self.choices.count;i++) {
        NSRect tile=NSMakeRect(i*self.tileWidth-self.offset+2,1,self.tileWidth-4,NSHeight(self.bounds)-2);
        if(!NSIntersectsRect(tile,self.bounds)) continue;
        [(i==self.selected ? NSColor.selectedControlColor : [NSColor colorWithWhite:.18 alpha:1]) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:tile xRadius:5 yRadius:5] fill];
        NSImage *icon=[NSImage imageWithSystemSymbolName:self.choices[i][1] accessibilityDescription:nil] ?: [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:nil];
        NSImage *glyph=[NSImage imageWithSize:NSMakeSize(16,14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            [icon drawInRect:rect]; [NSColor.whiteColor setFill];
            NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn); return YES;
        }];
        [glyph drawInRect:NSMakeRect(NSMidX(tile)-8,NSMaxY(tile)-17,16,14)];
        NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.alignment=NSTextAlignmentCenter; style.lineBreakMode=NSLineBreakByTruncatingTail;
        [self.choices[i][0] drawInRect:NSMakeRect(tile.origin.x+3,2,tile.size.width-6,12) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:style}];
    }
}
@end
static void BeginMidiChooser(MidiNavigationButton *button,BOOL workspaces) {
    if(midiWorkspaceChooser || !button.window) return;
    NSView *host=button.window.contentView;
    NSArray *bars=workspaces ? nil : [(id)NSApp.delegate valueForKey:@"allUserTouchbars"];
    NSMutableArray *choices=[NSMutableArray new];
    if(workspaces) [choices addObjectsFromArray:MidiWorkspaceCatalog()];
    else for(NSUInteger i=0;i<bars.count;i++) {
        NSTouchBar *bar=bars[i];
        NSString *name=bar.customizationIdentifier;
        // Identifiers are internal; use a stable, human-readable preset number.
        if(!name.length || [name containsString:@"."]) name=[NSString stringWithFormat:@"MIDI %lu",(unsigned long)i+1];
        [choices addObject:@[name,@"pianokeys",@(i)]];
    }
    if(!choices.count) return;
    NSRect frame=host.bounds; frame.origin.x+=40; frame.size.width-=40;
    if(frame.size.width<=0) return;
    MidiWorkspaceChooser *picker=[[MidiWorkspaceChooser alloc] initWithFrame:frame];
    picker.owner=button; picker.workspaces=workspaces; picker.choices=choices; picker.selected=-1;
    picker.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    midiWorkspaceChooser=picker;
    [host addSubview:picker positioned:NSWindowAbove relativeTo:nil];
    // Do not select a tile until the finger moves into the chooser.
    picker.point=NSMakePoint(-100,-100);
    __weak MidiWorkspaceChooser *weakPicker=picker;
    picker.scrollTimer=[NSTimer timerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer *timer) {
        MidiWorkspaceChooser *view=weakPicker;
        if(!view) { [timer invalidate]; return; }
        if(!NSPointInRect(view.point,view.bounds)) return;
        CGFloat direction=view.point.x<24 ? -1 : view.point.x>NSWidth(view.bounds)-24 ? 1 : 0;
        CGFloat maximum=MAX(0,view.choices.count*view.tileWidth-NSWidth(view.bounds));
        view.offset=MAX(0,MIN(maximum,view.offset+direction*6));
        [view updateAt:view.point];
    }];
    [NSRunLoop.mainRunLoop addTimer:picker.scrollTimer forMode:NSRunLoopCommonModes];
}
static BOOL MoveMidiChooser(MidiNavigationButton *button,NSPoint point) {
    if(!midiWorkspaceChooser || midiWorkspaceChooser.owner!=button) return NO;
    [midiWorkspaceChooser updateAt:[midiWorkspaceChooser convertPoint:point fromView:button]];
    return YES;
}
static BOOL FinishMidiChooser(MidiNavigationButton *button,NSPoint point,BOOL cancelled) {
    MidiWorkspaceChooser *picker=midiWorkspaceChooser;
    if(!picker || picker.owner!=button) return NO;
    // A stationary hold/release cancels; selection requires sliding first.
    if(picker.selected>=0 && !cancelled) [picker updateAt:[picker convertPoint:point fromView:button]];
    NSInteger selected=cancelled ? -1 : picker.selected;
    BOOL workspaces=picker.workspaces;
    StripRecordController *controller=[button isKindOfClass:StripRecordButton.class] ? ((StripRecordButton *)button).recordController : recordController;
    [picker.scrollTimer invalidate]; [picker removeFromSuperview]; midiWorkspaceChooser=nil;
    if(selected>=0) dispatch_async(dispatch_get_main_queue(),^{
        if(workspaces) [controller showWorkspace:selected];
        else {
            [controller returnToMidi];
            id delegate=NSApp.delegate;
            NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
            if(selected>=(NSInteger)bars.count) return;
            [delegate setValue:@NO forKey:@"controlSurfadeMode"];
            ((void(*)(id,SEL,id,id))objc_msgSend)(delegate,NSSelectorFromString(@"receivedGlobalKeyFrom:key:"),nil,@(selected));
            UpdateNavigationColor();
        }
    });
    return YES;
}
