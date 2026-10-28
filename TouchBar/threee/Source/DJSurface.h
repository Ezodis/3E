// Native two-deck MIDI surface. No DAW process inspection or fabricated telemetry.
static NSString *const DJMixerID=@"local.threepounds.dj.mixer";
static NSString *const DJPadsID=@"local.threepounds.dj.pads";
#ifndef THREEE_DJ_STANDALONE_TEST
static void DJActivateLayouts(void);
#else
static void DJActivateLayouts(void) {}
#endif
static NSString *const DJEnabledKey=@"ThreeEDJEnabled";
static NSString *const DJBackupKey=@"ThreeEDJOriginalLayoutsV1";
static NSColor *DJColor(NSInteger deck) {
    return deck ? [NSColor colorWithSRGBRed:1 green:.63 blue:.28 alpha:1] : [NSColor colorWithSRGBRed:.23 green:.82 blue:.94 alpha:1];
}
@interface ThreeEDJMIDI : NSObject
@property MIDIClientRef client;
@property MIDIEndpointRef source;
@property MIDIEndpointRef destination;
@property NSMutableDictionary<NSString *,NSNumber *> *values;
@property NSMutableDictionary<NSString *,NSNumber *> *received;
@property NSHashTable<NSView *> *views;
@property NSTimer *timer;
@property void (^capture)(UInt8,UInt8,UInt8);
@property UInt8 runningStatus;
@property UInt8 pending;
@property NSInteger dataCount;
@property BOOL sysex;
@property OSStatus error;
+ (instancetype)shared;
- (void)start;
- (void)send:(UInt8)status number:(UInt8)number value:(UInt8)value;
- (void)consume:(NSData *)data;
- (NSInteger)value:(NSInteger)channel number:(NSInteger)number note:(BOOL)note;
- (BOOL)confirmed:(NSInteger)channel number:(NSInteger)number note:(BOOL)note;
- (void)redraw;
@end
static NSString *DJKey(NSInteger channel,NSInteger number,BOOL note) { return [NSString stringWithFormat:@"%ld:%ld:%d",(long)channel,(long)number,note]; }
static void DJRead(const MIDIPacketList *packets,void *context,void *unused) {
    ThreeEDJMIDI *midi=(__bridge ThreeEDJMIDI *)context;
    const MIDIPacket *packet=&packets->packet[0];
    NSMutableData *bytes=[NSMutableData new];
    for(UInt32 i=0;i<packets->numPackets;i++) { [bytes appendBytes:packet->data length:packet->length]; packet=MIDIPacketNext(packet); }
    dispatch_async(dispatch_get_main_queue(),^{ [midi consume:bytes]; });
}
@implementation ThreeEDJMIDI
+ (instancetype)shared { static ThreeEDJMIDI *midi; static dispatch_once_t once; dispatch_once(&once,^{ midi=[self new]; }); return midi; }
- (instancetype)init {
    if((self=[super init])) { self.values=[NSMutableDictionary new]; self.received=[NSMutableDictionary new]; self.views=[NSHashTable weakObjectsHashTable]; }
    return self;
}
- (void)start {
    if(self.client) return;
    self.error=MIDIClientCreate(CFSTR("3£ DJ"),NULL,NULL,&_client);
    if(!self.error) self.error=MIDISourceCreate(self.client,CFSTR("3£ DJ"),&_source);
    if(!self.error) self.error=MIDIDestinationCreate(self.client,CFSTR("3£ DJ"),DJRead,(__bridge void *)self,&_destination);
    if(self.error) {
        if(self.source) MIDIEndpointDispose(self.source);
        if(self.destination) MIDIEndpointDispose(self.destination);
        if(self.client) MIDIClientDispose(self.client);
        self.source=0; self.destination=0; self.client=0;
        NSLog(@"3£ DJ MIDI unavailable: %d",(int)self.error); return;
    }
    MIDIObjectSetIntegerProperty(self.source,kMIDIPropertyUniqueID,0x33454441);
    MIDIObjectSetIntegerProperty(self.destination,kMIDIPropertyUniqueID,0x33454442);
    __weak ThreeEDJMIDI *weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(NSTimer *timer) { [weakSelf redraw]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)redraw { for(NSView *view in self.views) if(view.window) view.needsDisplay=YES; }
- (NSInteger)value:(NSInteger)channel number:(NSInteger)number note:(BOOL)note {
    NSNumber *value=self.values[DJKey(channel,number,note)];
    return value ? value.integerValue : note ? 0 : (number==7 ? 100 : 64);
}
- (BOOL)confirmed:(NSInteger)channel number:(NSInteger)number note:(BOOL)note {
    NSNumber *time=self.received[DJKey(channel,number,note)];
    // Feedback describes the latest received value, not a guaranteed connection.
    return time && NSProcessInfo.processInfo.systemUptime-time.doubleValue<5;
}
- (void)send:(UInt8)status number:(UInt8)number value:(UInt8)value {
    if(number>127 || value>127) return;
    BOOL note=(status&0xf0)==0x90 || (status&0xf0)==0x80;
    if(!note) { self.values[DJKey(status&15,number,NO)]=@(value); [self.received removeObjectForKey:DJKey(status&15,number,NO)]; }
    if(self.capture) { self.capture(status,number,value); return; }
    if(!self.source) return;
    Byte storage[128]; MIDIPacketList *list=(MIDIPacketList *)storage;
    Byte bytes[]={status,number,value};
    MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,bytes);
    MIDIReceived(self.source,list);
    [self redraw];
}
- (void)consume:(NSData *)data {
    const UInt8 *bytes=data.bytes;
    for(NSUInteger i=0;i<data.length;i++) {
        UInt8 byte=bytes[i];
        if(byte>=0xf8) continue; // Clock does not interrupt running status.
        if(byte==0xf0) { self.sysex=YES; self.runningStatus=0; self.dataCount=0; continue; }
        if(byte==0xf7) { self.sysex=NO; continue; }
        if(self.sysex) continue;
        if(byte&0x80) { self.runningStatus=byte<0xf0 ? byte : 0; self.dataCount=0; continue; }
        UInt8 kind=self.runningStatus&0xf0;
        if(!self.runningStatus) continue;
        if(kind==0xc0 || kind==0xd0) continue;
        if(!self.dataCount) { self.pending=byte; self.dataCount=1; continue; }
        self.dataCount=0;
        if(kind!=0xb0 && kind!=0x90 && kind!=0x80) continue;
        NSInteger channel=self.runningStatus&15;
        if(channel!=0 && channel!=1 && channel!=15) continue;
        BOOL note=kind!=0xb0;
        // Accept only our documented mapping; no unrelated MIDI can light controls.
        BOOL allowed=note ? channel<2 && (self.pending<4 || self.pending==5 || self.pending==6 || (self.pending>=16 && self.pending<=23)) :
            (channel<2 && (self.pending==7 || (self.pending>=16 && self.pending<=23))) || (channel==15 && self.pending==8);
        if(!allowed) continue;
        NSString *key=DJKey(channel,self.pending,note);
        self.values[key]=@(kind==0x80 ? 0 : byte);
        self.received[key]=@(NSProcessInfo.processInfo.systemUptime);
    }
    [self redraw]; // Feedback never passes through send: (no MIDI echo).
}
@end

typedef NS_ENUM(NSInteger,DJControlKind) { DJKnob,DJFader,DJDisc,DJPad };
@interface ThreeEDJControl : NSView
@property DJControlKind kind;
@property NSInteger channel;
@property NSInteger number;
@property NSString *caption;
@property BOOL tracking;
@property NSPoint origin;
@property NSPoint last;
@property NSInteger originValue;
@property NSInteger nudge;
@property double angle;
@property id identity;
@property BOOL moved;
- (void)begin:(NSPoint)point identity:(id)identity;
- (void)move:(NSPoint)point;
- (void)end;
@end
static void DJText(NSString *text,NSRect rect,CGFloat size,NSColor *color) {
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.alignment=NSTextAlignmentCenter; style.lineBreakMode=NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
@implementation ThreeEDJControl
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) { self.allowedTouchTypes=NSTouchTypeMaskDirect; self.wantsRestingTouches=YES; self.nudge=-1; [[ThreeEDJMIDI shared].views addObject:self]; }
    return self;
}
- (void)drawRect:(NSRect)dirty {
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    NSColor *color=DJColor(self.channel==1), *dim=[NSColor colorWithWhite:.57 alpha:1];
    CGFloat w=NSWidth(self.bounds);
    [[NSColor colorWithWhite:self.tracking ? .15 : .075 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5] fill];
    NSInteger value=[midi value:self.channel number:self.number note:self.kind==DJPad];
    BOOL confirmed=[midi confirmed:self.channel number:self.number note:self.kind==DJPad];
    if(self.kind==DJDisc) {
        NSRect disc=NSMakeRect(4,3,24,24);
        [[NSColor colorWithWhite:.17 alpha:1] setFill]; [[NSBezierPath bezierPathWithOvalInRect:disc] fill];
        [color setStroke]; NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(disc,1,1)]; ring.lineWidth=1.3; [ring stroke];
        NSPoint center=NSMakePoint(16,15); NSBezierPath *needle=[NSBezierPath bezierPath];
        [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+8*sin(self.angle),center.y+8*cos(self.angle))]; needle.lineWidth=1.5; [needle stroke];
        DJText(self.channel ? @"B" : @"A",NSMakeRect(28,14,w-29,12),10,color);
        BOOL feedback=[midi confirmed:self.channel number:0 note:YES];
        DJText(feedback ? ([midi value:self.channel number:0 note:YES] ? @"PLAY" : @"STOP") : @"BEND",NSMakeRect(28,3,w-29,10),6,dim);
    } else if(self.kind==DJPad) {
        BOOL lit=self.tracking || value>0;
        if(lit) { [[color colorWithAlphaComponent:.25] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5] fill]; }
        [[color colorWithAlphaComponent:.5] setFill]; NSRectFill(NSMakeRect(3,27,w-6,1));
        DJText(self.caption,NSMakeRect(1,8,w-2,15),self.caption.length>2 ? 7 : 10,lit ? color : [color colorWithAlphaComponent:.85]);
        if(confirmed) { [color setFill]; NSRectFill(NSMakeRect(w/2-2,3,4,2)); }
    } else if(self.kind==DJKnob) {
        NSPoint center=NSMakePoint(12,17); NSBezierPath *arc=[NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:center radius:7 startAngle:225 endAngle:-45 clockwise:YES];
        arc.lineWidth=2; [[NSColor colorWithWhite:.25 alpha:1] setStroke]; [arc stroke];
        CGFloat theta=(225-270*value/127.0)*M_PI/180;
        NSBezierPath *needle=[NSBezierPath bezierPath]; [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+7*cos(theta),center.y+7*sin(theta))];
        needle.lineWidth=2; [color setStroke]; [needle stroke];
        DJText([NSString stringWithFormat:@"%ld",(long)value],NSMakeRect(21,12,w-22,12),8,confirmed ? color : dim);
        DJText(self.caption,NSMakeRect(1,1,w-2,10),7,NSColor.whiteColor);
    } else {
        DJText(self.caption,NSMakeRect(3,18,w-6,10),7,confirmed ? color : dim);
        CGFloat inset=7, length=MAX(1,w-2*inset),x=inset+length*value/127.0;
        [[NSColor colorWithWhite:.25 alpha:1] setFill]; NSRectFill(NSMakeRect(inset,9,length,2));
        [color setFill]; NSRectFill(NSMakeRect(inset,9,x-inset,2));
        [[NSColor colorWithWhite:.9 alpha:1] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x-2,5,4,10) xRadius:1 yRadius:1] fill];
        if(self.channel==15) { [[NSColor colorWithWhite:.5 alpha:1] setFill]; NSRectFill(NSMakeRect(w/2,4,.5,3)); }
    }
}
- (void)begin:(NSPoint)point identity:(id)identity {
    if(self.tracking || !NSPointInRect(point,self.bounds)) return;
    self.tracking=YES; self.identity=identity; self.origin=self.last=point; self.moved=NO;
    self.originValue=[[ThreeEDJMIDI shared] value:self.channel number:self.number note:NO];
    if(self.kind==DJPad) [[ThreeEDJMIDI shared] send:0x90|self.channel number:self.number value:127];
    if(self.kind==DJFader) [self move:point];
    self.needsDisplay=YES;
}
- (void)move:(NSPoint)point {
    if(!self.tracking || !isfinite(point.x) || !isfinite(point.y)) return;
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    CGFloat dx=point.x-self.origin.x, step=point.x-self.last.x;
    if(hypot(dx,point.y-self.origin.y)>2) self.moved=YES;
    if(self.kind==DJKnob || self.kind==DJFader) {
        NSInteger value=self.kind==DJKnob ? lround(self.originValue+dx*1.5) : lround((point.x-7)/MAX(1,NSWidth(self.bounds)-14)*127);
        value=MAX(0,MIN(127,value));
        if(value!=[midi value:self.channel number:self.number note:NO]) [midi send:0xb0|self.channel number:self.number value:(UInt8)value];
    } else if(self.kind==DJDisc && fabs(step)>=1) {
        NSInteger next=step>0 ? 6 : 5; // Pitch bend + / -, released on direction changes and cancellation.
        if(next!=self.nudge) {
            if(self.nudge>=0) [midi send:0x80|self.channel number:(UInt8)self.nudge value:0];
            [midi send:0x90|self.channel number:(UInt8)next value:127]; self.nudge=next;
        }
        self.angle+=step*.12;
    }
    self.last=point; self.needsDisplay=YES;
}
- (void)end {
    if(!self.tracking) return;
    if(self.kind==DJPad) [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.number value:0];
    if(self.nudge>=0) [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.nudge value:0];
    self.nudge=-1; self.tracking=NO; self.identity=nil; self.needsDisplay=YES;
}
- (void)viewWillMoveToWindow:(NSWindow *)newWindow { if(!newWindow) [self end]; [super viewWillMoveToWindow:newWindow]; }
- (void)touchesBeganWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseBegan inView:self]) if(touch.type==NSTouchTypeDirect && !touch.isResting) { [self begin:[touch locationInView:self] identity:touch.identity]; break; }
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseMoved inView:self]) if([touch.identity isEqual:self.identity]) [self move:[touch locationInView:self]];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:self]) if([touch.identity isEqual:self.identity]) [self end];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event { [self end]; }
- (void)mouseDown:(NSEvent *)event { [self begin:[self convertPoint:event.locationInWindow fromView:nil] identity:@"mouse"]; }
- (void)mouseDragged:(NSEvent *)event { [self move:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self end]; }
@end

@interface ThreeEDJRow : NSView
@property BOOL pads;
@property NSMutableArray<ThreeEDJControl *> *controls;
@end
@implementation ThreeEDJRow
- (instancetype)initWithPads:(BOOL)pads {
    if((self=[super initWithFrame:NSMakeRect(0,0,600,30)])) {
        self.pads=pads; self.controls=[NSMutableArray new];
        for(NSInteger deck=0;deck<2;deck++) {
            NSArray *labels=pads ? @[@"▶",@"CUE",@"SYNC",@"LOOP",@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8"] : @[@"DISC",@"LEVEL",@"HI",@"MID",@"LOW",@"FILTER"];
            for(NSInteger i=0;i<(NSInteger)labels.count;i++) {
                ThreeEDJControl *control=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,30,30)];
                control.channel=deck; control.caption=labels[i];
                control.kind=pads ? DJPad : i==0 ? DJDisc : i==1 ? DJFader : DJKnob;
                control.number=pads ? (i<4 ? i : 16+i-4) : i==0 ? 0 : i==1 ? 7 : 14+i;
                control.accessibilityLabel=[NSString stringWithFormat:@"Deck %@ %@. %@",deck ? @"B" : @"A",labels[i],pads ? @"Press and release MIDI note" : i==0 ? @"Swipe to nudge; release to stop bending" : @"Swipe horizontally to adjust"];
                [self.controls addObject:control]; [self addSubview:control];
            }
        }
        if(!pads) {
            ThreeEDJControl *cross=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,96,30)];
            cross.kind=DJFader; cross.channel=15; cross.number=8; cross.caption=@"A    CROSSFADE    B";
            cross.accessibilityLabel=@"Crossfader: swipe left for A, right for B";
            [self.controls addObject:cross]; [self addSubview:cross];
        }
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(600,30); }
- (void)layout {
    [super layout]; CGFloat w=NSWidth(self.bounds);
    if(self.pads) {
        CGFloat gap=2, deckGap=8, cell=(w-22*gap-deckGap)/24;
        for(NSInteger i=0;i<24;i++) self.controls[i].frame=NSMakeRect(i*(cell+gap)+(i>=12 ? deckGap-gap : 0),0,cell,30);
    } else {
        CGFloat cross=MAX(64,w*.16), deck=(w-cross-8)/2, x=0;
        for(NSInteger d=0;d<2;d++) {
            CGFloat widths[]={deck*.22,deck*.19,deck*.1475,deck*.1475,deck*.1475,deck*.1475};
            for(NSInteger i=0;i<6;i++) { self.controls[d*6+i].frame=NSMakeRect(x,0,widths[i],30); x+=widths[i]; }
            if(d==0) { self.controls.lastObject.frame=NSMakeRect(x+4,0,cross,30); x+=cross+8; }
        }
    }
}
@end
static NSCustomTouchBarItem *DJMakeItem(NSString *identifier) {
    if(![identifier isEqual:DJMixerID] && ![identifier isEqual:DJPadsID]) return nil;
    NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    ThreeEDJRow *row=[[ThreeEDJRow alloc] initWithPads:[identifier isEqual:DJPadsID]];
    row.translatesAutoresizingMaskIntoConstraints=NO;
    [row.widthAnchor constraintEqualToConstant:600].active=YES;
    [row.heightAnchor constraintEqualToConstant:30].active=YES;
    item.view=row;
    item.customizationLabel=row.pads ? @"rekordbox · Two-deck Performance Pads" : @"rekordbox · Pioneer-style Mixer";
    item.visibilityPriority=NSTouchBarItemPriorityHigh;
    return item;
}
static void DJSetLayout(NSTouchBar *bar,NSArray *items) {
    id configuration=[bar valueForKey:@"configuration"];
    if(![configuration respondsToSelector:NSSelectorFromString(@"_setCustomizedItemIdentifiers:")] || ![configuration respondsToSelector:NSSelectorFromString(@"_persistCustomizedItemIdentifiers")])
        [NSException raise:@"DJCustomizationUnavailable" format:@"This macOS version cannot persist Touch DJ layouts"];
    ((void(*)(id,SEL,id))objc_msgSend)(configuration,NSSelectorFromString(@"_setCustomizedItemIdentifiers:"),items);
    ((void(*)(id,SEL))objc_msgSend)(configuration,NSSelectorFromString(@"_persistCustomizedItemIdentifiers"));
}
static void DJInstallLayouts(NSArray<NSTouchBar *> *bars) {
    if(bars.count<3 || [NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey]) return;
    NSMutableDictionary *backups=[NSMutableDictionary new];
    for(NSUInteger index=1;index<=2;index++) {
        NSTouchBar *bar=bars[index];
        backups[bar.customizationIdentifier]=bar.itemIdentifiers ?: @[];
    }
    [NSUserDefaults.standardUserDefaults setObject:backups forKey:DJBackupKey];
    @try {
        for(NSUInteger index=1;index<=2;index++) DJSetLayout(bars[index],@[index==1 ? DJMixerID : DJPadsID]);
    } @catch(NSException *exception) {
        for(NSUInteger index=1;index<=2;index++) {
            @try { DJSetLayout(bars[index],backups[bars[index].customizationIdentifier]); } @catch(NSException *ignored) {}
        }
        [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
        NSLog(@"Touch DJ layouts kept unchanged: %@",exception);
    }
}
static NSString *DJMappingGuide(void) {
    NSMutableString *guide=[NSMutableString stringWithString:@"3£ TOUCH DJ — rekordbox / Ableton\n\nBar 2: two nudge discs, levels, HI / MID / LOW / FILTER and crossfader.\nBar 3: Play, Cue, Sync, Loop and eight Hot Cues on each deck.\nCyan = Deck A. Amber = Deck B. Swipe knobs horizontally.\nDiscs bend while your finger moves; lifting or cancelling releases the bend. They are not scratch jog wheels.\n\nSETUP\nOpen 3£ first. Choose Install / Show Touch DJ in its menu once. In rekordbox select PERFORMANCE → MIDI → 3£ DJ.\nMIDI Learn requires Core or higher, or compatible Hardware Unlock equipment.\nFor each row below, add the matching function/deck and enter MIDI IN, or use LEARN and touch the control. Turn LEARN off when finished.\nFor supported indicators, set MIDI OUT to the same code and route output to 3£ DJ.\nA dot under a pad / colored value means recently received feedback; gray values are local positions. PLAY/STOP appears only from received play feedback, then expires after five seconds without updates. The port does not prove rekordbox is connected.\n\nThe virtual port must be verified in your installed rekordbox version. Some third-party functions and jog wheels are restricted. Discs use two momentary tempo-bend notes; map them to available bend +/- actions. No driver spoofing.\nNo track titles, BPM, waveforms or audio meters are claimed through generic MIDI.\n\nABLETON\nEnable Remote for 3£ DJ input and output. Keep input Track off for controller-only use. Use Live MIDI Map on levels, EQ, filter, crossfader and clip/transport buttons. Add EQ/filter devices first. DJ Cue/Sync/Hot Cue semantics depend on your Live mapping.\n\nMAPPING (hex; MIDI channels are 1-based)\n"];
    for(NSInteger deck=0;deck<2;deck++) {
        [guide appendFormat:@"\nDECK %@ — MIDI channel %ld\n",deck ? @"B" : @"A",(long)deck+1];
        NSArray *names=@[@"Play/Pause",@"Cue (momentary)",@"Beat Sync",@"Loop",@"unused",@"Tempo bend - (momentary)",@"Tempo bend + (momentary)"];
        for(NSUInteger i=0;i<names.count;i++) if(i!=4) [guide appendFormat:@"%-28s %02lX%02lX   Button\n",[names[i] UTF8String],(long)(0x90+deck),(long)i];
        for(NSInteger i=0;i<8;i++) [guide appendFormat:@"Hot Cue %ld                    %02lX%02lX   Pad\n",(long)i+1,(long)(0x90+deck),(long)(16+i)];
        NSArray *knobs=@[@"EQ High",@"EQ Mid",@"EQ Low",@"Color Filter"];
        [guide appendFormat:@"Channel level                %02lX07   Knob/Slider 0–127\n",(long)(0xb0+deck)];
        for(NSInteger i=0;i<4;i++) [guide appendFormat:@"%-28s %02lX%02lX   Knob/Slider 0–127\n",[knobs[i] UTF8String],(long)(0xb0+deck),(long)(16+i)];
    }
    [guide appendString:@"\nCrossfader (global)           BF08   Knob/Slider 0–127\n\nNotes release with Note Off, velocity 0. CC values are 7-bit absolute.\nThe MIDI addresses are ready; rekordbox function assignments still need Learn.\n\nOfficial guide: https://cdn.rekordbox.com/files/20241203210623/rekordbox7.0.5_midi_learn_operation_guide_EN.pdf\nPlans: https://rekordbox.com/en/support/faq/rekordbox7/\n"];
    return guide;
}
@interface ThreeEDJActions : NSObject
+ (void)setup:(id)sender;
+ (void)restore:(id)sender;
+ (void)install:(id)sender;
@end
@implementation ThreeEDJActions
+ (void)install:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:DJEnabledKey];
    DJActivateLayouts();
    NSArray *bars=[(id)NSApp.delegate valueForKey:@"allUserTouchbars"];
    if(bars.count>=2) {
        [(id)NSApp.delegate setValue:@1 forKey:@"userTouchbarNumber"];
        ((void(*)(id,SEL,id))objc_msgSend)(NSApp.delegate,NSSelectorFromString(@"showTouchbar:"),bars[1]);
    }
}
+ (void)setup:(id)sender {
    static NSWindow *window;
    if(!window) {
        window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,720,580) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO; window.title=@"3£ · Touch DJ Setup";
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:window.contentView.bounds]; scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller=YES;
        NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,690,1500)]; text.editable=NO; text.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; text.textContainerInset=NSMakeSize(20,20);
        text.string=DJMappingGuide(); text.autoresizingMask=NSViewWidthSizable; text.textContainer.widthTracksTextView=YES;
        scroll.documentView=text; [window.contentView addSubview:scroll]; [window center];
    }
    [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
+ (void)restore:(id)sender {
    NSArray *bars=[(id)NSApp.delegate valueForKey:@"allUserTouchbars"];
    NSDictionary *backups=[NSUserDefaults.standardUserDefaults dictionaryForKey:DJBackupKey];
    for(NSTouchBar *bar in bars) if(backups[bar.customizationIdentifier]) DJSetLayout(bar,backups[bar.customizationIdentifier]);
    // Keep the migration marker so restored layouts are not replaced on relaunch.
    if(bars.count && [[(id)NSApp.delegate valueForKey:@"touchbarShown"] boolValue] && [NSApp.delegate respondsToSelector:NSSelectorFromString(@"showTouchbar:")]) ((void(*)(id,SEL,id))objc_msgSend)(NSApp.delegate,NSSelectorFromString(@"showTouchbar:"),bars[MAX(0,MIN((NSInteger)bars.count-1,[[(id)NSApp.delegate valueForKey:@"userTouchbarNumber"] integerValue]))]);
}
@end
static void DJAddMenu(NSMenu *menu) {
    if([menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item,NSUInteger idx,BOOL *stop) { return [item.identifier isEqual:@"local.threepounds.dj.setup"]; }]!=NSNotFound) return;
    NSMenuItem *setup=[[NSMenuItem alloc] initWithTitle:@"Touch DJ Setup…" action:@selector(setup:) keyEquivalent:@""]; setup.target=ThreeEDJActions.class; setup.identifier=@"local.threepounds.dj.setup";
    NSMenuItem *install=[[NSMenuItem alloc] initWithTitle:@"Install / Show Touch DJ" action:@selector(install:) keyEquivalent:@""]; install.target=ThreeEDJActions.class;
    NSMenuItem *restore=[[NSMenuItem alloc] initWithTitle:@"Restore Layouts Before Touch DJ" action:@selector(restore:) keyEquivalent:@""]; restore.target=ThreeEDJActions.class;
    [menu addItem:install]; [menu addItem:setup]; [menu addItem:restore];
}
