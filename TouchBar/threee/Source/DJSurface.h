// Native two-deck MIDI surface with read-only displayed deck metadata.
#import "DJTelemetry.h"
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
typedef struct { UInt8 status, pending; NSInteger count; BOOL sysex; } DJMIDIParser;
static NSString *const DJTargetKey=@"ThreeEDJLiveTarget";
@interface ThreeEDJMIDI : NSObject
@property MIDIClientRef client;
@property MIDIEndpointRef source;
@property MIDIEndpointRef destination;
@property MIDIEndpointRef liveSource;
@property MIDIEndpointRef liveDestination;
@property NSMutableDictionary<NSString *,NSNumber *> *liveValues;
@property NSMutableDictionary<NSString *,NSNumber *> *liveReceived;
@property DJMIDIParser rbParser;
@property DJMIDIParser liveParser;
@property(readonly) BOOL liveTarget;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *values;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *received;
@property NSHashTable<NSView *> *views;
@property NSTimer *timer;
@property void (^capture)(UInt8,UInt8,UInt8);
@property OSStatus error;
+ (instancetype)shared;
- (void)start;
- (void)send:(UInt8)status number:(UInt8)number value:(UInt8)value;
- (void)consume:(NSData *)data;
- (void)consume:(NSData *)data live:(BOOL)live;
- (NSInteger)value:(NSInteger)channel number:(NSInteger)number note:(BOOL)note;
- (BOOL)confirmed:(NSInteger)channel number:(NSInteger)number note:(BOOL)note;
- (void)redraw;
@end
static UInt8 DJWireStatus(UInt8 status,BOOL live) {
    // rekordbox's button mappings require Note On velocity zero for release.
    // Live keeps standard Note Off; internal gesture/capture semantics stay paired.
    return !live && (status&0xf0)==0x80 ? 0x90|(status&15) : status;
}
static NSString *DJKey(NSInteger channel,NSInteger number,BOOL note) { return [NSString stringWithFormat:@"%ld:%ld:%d",(long)channel,(long)number,note]; }
static void DJReadHost(const MIDIPacketList *packets,void *context,BOOL live) {
    ThreeEDJMIDI *midi=(__bridge ThreeEDJMIDI *)context;
    const MIDIPacket *packet=&packets->packet[0];
    NSMutableData *bytes=[NSMutableData new];
    for(UInt32 i=0;i<packets->numPackets;i++) { [bytes appendBytes:packet->data length:packet->length]; packet=MIDIPacketNext(packet); }
    dispatch_async(dispatch_get_main_queue(),^{ [midi consume:bytes live:live]; });
}
static void DJRead(const MIDIPacketList *packets,void *context,void *unused) { DJReadHost(packets,context,NO); }
static void DJReadLive(const MIDIPacketList *packets,void *context,void *unused) { DJReadHost(packets,context,YES); }
@implementation ThreeEDJMIDI
@synthesize values=_values, received=_received;
- (BOOL)liveTarget { return [NSUserDefaults.standardUserDefaults boolForKey:DJTargetKey]; }
- (NSMutableDictionary *)values { return self.liveTarget ? self.liveValues : _values; }
- (NSMutableDictionary *)received { return self.liveTarget ? self.liveReceived : _received; }
+ (instancetype)shared { static ThreeEDJMIDI *midi; static dispatch_once_t once; dispatch_once(&once,^{ midi=[self new]; }); return midi; }
- (instancetype)init {
    if((self=[super init])) { self.values=[NSMutableDictionary new]; self.received=[NSMutableDictionary new]; self.liveValues=[NSMutableDictionary new]; self.liveReceived=[NSMutableDictionary new]; self.views=[NSHashTable weakObjectsHashTable]; }
    return self;
}
- (void)start {
    if(self.client) return;
#ifdef THREEE_DJ_STANDALONE_TEST
    CFStringRef rbName=CFSTR("3£ DJ Verification"), liveName=CFSTR("3£ DJ Live Verification");
#else
    CFStringRef rbName=CFSTR("3£ DJ"), liveName=CFSTR("3£ DJ Live");
#endif
    self.error=MIDIClientCreate(CFSTR("3£ DJ"),NULL,NULL,&_client);
    if(!self.error) self.error=MIDISourceCreate(self.client,rbName,&_source);
    if(!self.error) self.error=MIDIDestinationCreate(self.client,rbName,DJRead,(__bridge void *)self,&_destination);
    if(!self.error) self.error=MIDISourceCreate(self.client,liveName,&_liveSource);
    if(!self.error) self.error=MIDIDestinationCreate(self.client,liveName,DJReadLive,(__bridge void *)self,&_liveDestination);
    if(self.error) {
        if(self.source) MIDIEndpointDispose(self.source);
        if(self.destination) MIDIEndpointDispose(self.destination);
        if(self.liveSource) MIDIEndpointDispose(self.liveSource);
        if(self.liveDestination) MIDIEndpointDispose(self.liveDestination);
        if(self.client) MIDIClientDispose(self.client);
        self.source=0; self.destination=0; self.liveSource=0; self.liveDestination=0; self.client=0;
        NSLog(@"3£ DJ MIDI unavailable: %d",(int)self.error); return;
    }
#ifndef THREEE_DJ_STANDALONE_TEST
    MIDIObjectSetIntegerProperty(self.source,kMIDIPropertyUniqueID,0x33454441);
    MIDIObjectSetIntegerProperty(self.destination,kMIDIPropertyUniqueID,0x33454442);
    MIDIObjectSetIntegerProperty(self.liveSource,kMIDIPropertyUniqueID,0x33454443);
    MIDIObjectSetIntegerProperty(self.liveDestination,kMIDIPropertyUniqueID,0x33454444);
#endif
    __weak ThreeEDJMIDI *weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(NSTimer *timer) { [weakSelf redraw]; if(!weakSelf.liveTarget) [[ThreeEDJTelemetry shared] poll]; }];
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
    MIDIEndpointRef output=self.liveTarget ? self.liveSource : self.source;
    if(!output) return;
    Byte storage[128]; MIDIPacketList *list=(MIDIPacketList *)storage;
    Byte bytes[]={DJWireStatus(status,self.liveTarget),number,value};
    MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,bytes);
    MIDIReceived(output,list);
    [self redraw];
}
- (void)consume:(NSData *)data { [self consume:data live:self.liveTarget]; }
- (void)consume:(NSData *)data live:(BOOL)live {
    DJMIDIParser parser=live ? self.liveParser : self.rbParser;
    NSMutableDictionary *values=live ? self.liveValues : _values;
    NSMutableDictionary *received=live ? self.liveReceived : _received;
    const UInt8 *bytes=data.bytes;
    for(NSUInteger i=0;i<data.length;i++) {
        UInt8 byte=bytes[i];
        if(byte>=0xf8) continue; // Clock does not interrupt running status.
        if(byte==0xf0) { parser.sysex=YES; parser.status=0; parser.count=0; continue; }
        if(byte==0xf7) { parser.sysex=NO; continue; }
        if(parser.sysex) continue;
        if(byte&0x80) { parser.status=byte<0xf0 ? byte : 0; parser.count=0; continue; }
        UInt8 kind=parser.status&0xf0;
        if(!parser.status) continue;
        if(kind==0xc0 || kind==0xd0) continue;
        if(!parser.count) { parser.pending=byte; parser.count=1; continue; }
        parser.count=0;
        if(kind!=0xb0 && kind!=0x90 && kind!=0x80) continue;
        NSInteger channel=parser.status&15;
        if(channel!=0 && channel!=1 && channel!=15) continue;
        BOOL note=kind!=0xb0;
        // Accept only our documented mapping; no unrelated MIDI can light controls.
        BOOL allowed=note ? channel<2 && (parser.pending<4 || parser.pending==5 || parser.pending==6 || parser.pending==7 || parser.pending==8 || (parser.pending>=16 && parser.pending<=23)) :
            (channel<2 && (parser.pending==7 || (parser.pending>=16 && parser.pending<=19))) || (channel==15 && parser.pending==8);
        if(!allowed) continue;
        NSString *key=DJKey(channel,parser.pending,note);
        values[key]=@(kind==0x80 ? 0 : byte);
        received[key]=@(NSProcessInfo.processInfo.systemUptime);
    }
    if(live) self.liveParser=parser; else self.rbParser=parser;
    [self redraw]; // Feedback never passes through send: (no MIDI echo).
}
@end

typedef NS_ENUM(NSInteger,DJControlKind) { DJKnob,DJFader,DJDisc,DJPad,DJBank };
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
@property BOOL search;
@property BOOL gestureSearch;
@property double lastMotion;
@property void (^tapAction)(void);
- (void)releaseIdleAt:(double)time;
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
        BOOL left=self.channel==0;
        CGFloat discX=left ? w-29 : 4, textX=left ? 3 : 31;
        NSRect disc=NSMakeRect(discX,3,24,24);
        [[NSColor colorWithWhite:.17 alpha:1] setFill]; [[NSBezierPath bezierPathWithOvalInRect:disc] fill];
        [color setStroke]; NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(disc,1,1)]; ring.lineWidth=1.3; [ring stroke];
        NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
        double angle=deck ? [deck[@"elapsed"] doubleValue]*.6 : self.angle;
        NSPoint center=NSMakePoint(discX+12,15); NSBezierPath *needle=[NSBezierPath bezierPath];
        [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+8*sin(angle),center.y+8*cos(angle))]; needle.lineWidth=1.5; [needle stroke];
        DJText(deck[@"title"] ?: (left ? @"Deck A" : @"Deck B"),NSMakeRect(textX,17,w-34,11),8,color);
        DJText(deck[@"time"] ?: @"— / —",NSMakeRect(textX,8,w-34,9),6.5,dim);
        DJText(self.search ? @"SEARCH ↔ hold · tap: bend" : @"BEND ↔ · tap: search",NSMakeRect(textX,0,w-34,9),5.5,self.tracking ? color : dim);
        DJText(self.search ? @"S" : @"±",NSMakeRect(discX+5,8,14,12),8,color);
    } else if(self.kind==DJBank) {
        DJText(midi.liveTarget ? @"LIVE" : @"RB",NSMakeRect(1,15,w-2,12),9,NSColor.whiteColor);
        DJText(self.caption,NSMakeRect(1,2,w-2,11),7,dim);
    } else if(self.kind==DJPad) {
        BOOL lit=self.tracking || value>0;
        if(lit) { [[color colorWithAlphaComponent:.25] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5] fill]; }
        [[color colorWithAlphaComponent:.5] setFill]; NSRectFill(NSMakeRect(3,27,w-6,1));
        DJText(self.caption,NSMakeRect(1,8,w-2,15),self.caption.length>2 ? 9 : 12,lit ? color : [color colorWithAlphaComponent:.85]);
        if(confirmed) { [color setFill]; NSRectFill(NSMakeRect(w/2-2,3,4,2)); }
    } else if(self.kind==DJKnob) {
        NSPoint center=NSMakePoint(w/2-11,17); NSBezierPath *arc=[NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:center radius:7 startAngle:225 endAngle:-45 clockwise:YES];
        arc.lineWidth=2; [[NSColor colorWithWhite:.25 alpha:1] setStroke]; [arc stroke];
        CGFloat theta=(225-270*value/127.0)*M_PI/180;
        NSBezierPath *needle=[NSBezierPath bezierPath]; [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+7*cos(theta),center.y+7*sin(theta))];
        needle.lineWidth=2; [color setStroke]; [needle stroke];
        DJText([NSString stringWithFormat:@"%ld",(long)value],NSMakeRect(w/2,12,w/2-3,12),8,confirmed ? color : dim);
        DJText(self.caption,NSMakeRect(1,1,w-2,10),7,NSColor.whiteColor);
    } else {
        DJText(self.channel==15 ? ([NSString stringWithFormat:@"%@ · %@",midi.liveTarget ? @"LIVE" : @"RB",self.caption]) : self.caption,NSMakeRect(3,18,w-6,10),7,confirmed ? color : dim);
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
    self.gestureSearch=self.search;
    self.originValue=[[ThreeEDJMIDI shared] value:self.channel number:self.number note:NO];
    if(self.kind==DJPad) [[ThreeEDJMIDI shared] send:0x90|self.channel number:self.number value:127];
    if(self.kind==DJFader && !self.tapAction) [self move:point];
    self.needsDisplay=YES;
}
- (void)move:(NSPoint)point {
    if(!self.tracking || !isfinite(point.x) || !isfinite(point.y)) return;
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    CGFloat dx=point.x-self.origin.x, step=point.x-self.last.x;
    if(hypot(dx,point.y-self.origin.y)>2) self.moved=YES;
    if(self.kind==DJKnob || self.kind==DJFader) {
        NSInteger value=self.kind==DJKnob ? lround(self.originValue+(point.y-self.origin.y)*6.0) : self.tapAction ? lround(self.originValue+dx/MAX(1,NSWidth(self.bounds)-14)*127) : lround((point.x-7)/MAX(1,NSWidth(self.bounds)-14)*127);
        value=MAX(0,MIN(127,value));
        if(value!=[midi value:self.channel number:self.number note:NO]) [midi send:0xb0|self.channel number:self.number value:(UInt8)value];
    } else if(self.kind==DJDisc && fabs(step)>=1) {
        NSInteger next=self.gestureSearch ? (step>0 ? 8 : 7) : (step>0 ? 6 : 5);
        if(!self.gestureSearch && self.nudge<0) {
            NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
            if([deck[@"sync"] boolValue]) { // Only toggle sync when the host reports it is enabled.
                [midi send:0x90|self.channel number:2 value:127]; [midi send:0x80|self.channel number:2 value:0];
                NSMutableDictionary *updated=[deck mutableCopy];updated[@"sync"]=@NO;
                NSMutableArray *decks=[[ThreeEDJTelemetry shared].decks mutableCopy];decks[self.channel]=updated;[ThreeEDJTelemetry shared].decks=decks;
            }
        }
        if(next!=self.nudge) {
            if(self.nudge>=0) [midi send:0x80|self.channel number:(UInt8)self.nudge value:0];
            [midi send:0x90|self.channel number:(UInt8)next value:127]; self.nudge=next;
        }
        self.angle+=step*.12; self.lastMotion=NSProcessInfo.processInfo.systemUptime;
        double stamp=self.lastMotion; __weak ThreeEDJControl *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.16*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if(weakSelf.lastMotion==stamp) [weakSelf releaseIdleAt:NSProcessInfo.processInfo.systemUptime];
        });
    }
    self.last=point; self.needsDisplay=YES;
}
- (void)releaseIdleAt:(double)time {
    if(!self.gestureSearch && self.nudge>=0 && time-self.lastMotion>=.15) {
        [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.nudge value:0];self.nudge=-1;
    }
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
- (void)finish {
    BOOL tap=self.tracking && !self.moved;[self end];
    if(tap && self.kind==DJDisc) { self.search=!self.search;self.needsDisplay=YES; }
    else if(tap && self.tapAction) self.tapAction();
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:self]) if([touch.identity isEqual:self.identity]) [self finish];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event { [self end]; }
- (void)mouseDown:(NSEvent *)event { [self begin:[self convertPoint:event.locationInWindow fromView:nil] identity:@"mouse"]; }
- (void)mouseDragged:(NSEvent *)event { [self move:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self finish]; }
@end

@interface ThreeEDJRow : NSView
@property BOOL pads;
@property NSMutableArray<ThreeEDJControl *> *controls;
@property NSInteger page;
@property NSLayoutConstraint *rowWidth;
- (void)nextPage;
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
                control.accessibilityLabel=[NSString stringWithFormat:@"Deck %@ %@. %@",deck ? @"B" : @"A",labels[i],pads ? @"Press and release MIDI note" : i==0 ? @"Tap for Bend/Search. Swipe to bend; swipe and hold to search; lift releases" : i==1 ? @"Swipe horizontally to set level" : @"Short vertical strokes adjust independently; lift and regrip"];
                [self.controls addObject:control]; [self addSubview:control];
            }
        }
        {
            ThreeEDJControl *cross=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,96,30)];
            cross.kind=pads ? DJBank : DJFader; cross.channel=15; cross.number=8; cross.caption=@"DECKS ›";
            cross.accessibilityLabel=@"Crossfader: swipe left for A, right for B";
            __weak ThreeEDJRow *weakSelf=self;cross.tapAction=^{[weakSelf nextPage];};
            cross.accessibilityLabel=pads ? @"Tap to cycle Transport, Pads 1–4, Pads 5–8" : @"Swipe crossfader; tap to switch Decks and EQ pages";
            [self.controls addObject:cross]; [self addSubview:cross];
        }
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(600,30); }
- (void)nextPage {
    for(ThreeEDJControl *control in self.controls) [control end];
    self.page=(self.page+1)%(self.pads ? 3 : 2);[self layout];self.needsDisplay=YES;
}
- (void)layout {
    [super layout]; CGFloat w=NSWidth(self.bounds),center=w/2;
    CGFloat host=self.window.contentView.bounds.size.width;
    if(host>200 && host<2048 && self.rowWidth) {
        CGFloat target=MAX(300,host-124);
        if(fabs(self.rowWidth.constant-target)>.1) self.rowWidth.constant=target;
        center=host/2-[self convertPoint:NSZeroPoint toView:nil].x;
    }
    center=MAX(0,MIN(w,center));
    CGFloat span=MAX(0,2*MIN(center,w-center)),hub=64,gap=7,half=(span-hub)/2-gap;
    for(ThreeEDJControl *control in self.controls) control.hidden=YES;
    ThreeEDJControl *middle=self.controls.lastObject;middle.hidden=NO;
    middle.frame=NSMakeRect(center-hub/2,0,hub,30);
    middle.caption=self.pads ? @[@"PLAY ›",@"PADS 1–4 ›",@"PADS 5–8 ›"][self.page] : self.page ? @"EQ ›" : @"DECKS ›";
    if(!self.pads) middle.accessibilityValue=self.page ? @"EQ page" : @"Decks page";
    for(NSInteger deck=0;deck<2;deck++) {
        NSArray *indices=self.pads ? (self.page==0 ? @[@0,@1,@2,@3] : self.page==1 ? @[@4,@5,@6,@7] : @[@8,@9,@10,@11]) : self.page ? @[@2,@3,@4,@5] : @[@1,@5,@0];
        CGFloat x=deck ? center+hub/2+gap : center-hub/2-gap-half;
        for(NSInteger slot=0;slot<(NSInteger)indices.count;slot++) {
            NSInteger which=deck==0 && !self.pads ? (NSInteger)indices.count-1-slot : slot;
            // A mirrors B: both platters sit immediately beside the center hub.
            if(!self.pads && !self.page) which=deck ? 2-slot : slot;
            NSInteger index=[indices[which] integerValue];
            ThreeEDJControl *control=self.controls[deck*(self.pads ? 12 : 6)+index];
            CGFloat cell=(!self.pads && !self.page) ? (index==0 ? half*.54 : (half*.46-2*gap)/2) : (half-gap*(indices.count-1))/indices.count;
            control.frame=NSMakeRect(x,0,MAX(12,cell),30);control.hidden=NO;x+=cell+gap;
        }
    }
    for(ThreeEDJControl *control in self.controls) control.needsDisplay=YES;
}

@end
static NSCustomTouchBarItem *DJMakeItem(NSString *identifier) {
    if(![identifier isEqual:DJMixerID] && ![identifier isEqual:DJPadsID]) return nil;
    NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    ThreeEDJRow *row=[[ThreeEDJRow alloc] initWithPads:[identifier isEqual:DJPadsID]];
    row.translatesAutoresizingMaskIntoConstraints=NO;
    row.rowWidth=[row.widthAnchor constraintEqualToConstant:704]; row.rowWidth.active=YES;
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
static NSString *DJBundledMapping(void) {
    NSString *contents=NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    return [contents stringByAppendingPathComponent:@"Resources/DJ/3£ DJ.midi.csv"];
}
static void DJInstallRekordboxMapping(void) {
    NSData *data=[NSData dataWithContentsOfFile:DJBundledMapping()]; if(!data.length) return;
    NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Pioneer/rekordbox6/MidiMappings"];
    NSString *path=[folder stringByAppendingPathComponent:@"3£ DJ.midi.csv"];
    NSString *current=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    // A populated user mapping is never replaced, including on app updates.
    for(NSString *line in [current componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        if(line.length && ![line hasPrefix:@"@file"] && ![line hasPrefix:@"#"]) return;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *error=nil;
    if(![data writeToFile:path options:NSDataWritingAtomic error:&error]) NSLog(@"3£ DJ mapping setup: %@",error);
}
static NSPopUpButton *djTargetChooser;
static NSString *DJMappingGuide(void) {
    NSMutableString *guide=[NSMutableString stringWithString:@"3£ TOUCH DJ — rekordbox / Ableton\n\nBar 2: tap the center RB/LIVE hub to switch Decks and EQ pages. Swipe the hub for crossfade. Decks has two discs, levels and filters; EQ has eight spaced knobs.\nBar 3: tap the center hub to cycle Transport, Pads 1–4, Pads 5–8. Larger targets replace the crowded 24-button row.\nCyan = Deck A. Amber = Deck B. Move knobs with short vertical strokes; lift/regrip for more range. Each finger stays in its own lane.\nTap a disc to switch BEND / SEARCH. Swipe left/right to slow/speed or search backward/forward. Bend releases after 150 ms without motion. SEARCH is fast search: swipe then hold to scan; lift/cancel releases immediately. Short taps are below rekordbox’s search hold threshold. If rekordbox reports Sync enabled, bending first turns it off. These are MIDI bend/search controls, not scratch jog wheels.\n\nSETUP\nOpen 3£ first. Choose Install / Show Touch DJ in its menu once. This seeds a ready mapping only if 3£ DJ has no existing mapping. Restart rekordbox once after initial setup. Select rekordbox in Touch DJ Target. In rekordbox select PERFORMANCE → MIDI → 3£ DJ.\nMIDI Learn requires Core or higher, or compatible Hardware Unlock equipment.\nIf needed, use Save rekordbox Mapping below, then IMPORT it for the 3£ DJ device. For manual mapping, add the matching function/deck and enter MIDI IN, or use LEARN and touch the control. Turn LEARN off when finished.\nFor supported indicators, set MIDI OUT to the same code and route output to 3£ DJ.\nA dot under a pad / colored value means recently received feedback; gray values are local positions. Track name and elapsed/total time come from a read-only adapter for the visible rekordbox deck fields, using existing macOS Accessibility permission. Metadata clears after 2.5 seconds without a fresh read. The port does not prove rekordbox is connected.\n\nThe virtual port must be verified in your installed rekordbox version. Some third-party functions and jog wheels are restricted. Discs use two momentary tempo-bend notes; map them to available bend +/- actions. No driver spoofing.\nGeneric MIDI does not provide track titles or time. The separate accessibility adapter reads only rekordbox deck fields; it does not inspect the library database, track selections or audio. No waveform is simulated. If unavailable, the discs show dashes. Live metadata is not provided by this adapter.\n\nABLETON\nEnable Remote for 3£ DJ Live input and output. Keep input Track off for controller-only use. Keep Remote off for the separate 3£ DJ port in Live. Select Ableton Live in 3£ → Touch DJ Target; choose rekordbox to return. The center fader shows LIVE or RB. Feedback is cached separately for each host. Use Live MIDI Map on levels, EQ, filter, crossfader and clip/transport buttons. Add EQ/filter devices first. DJ Cue/Sync/Hot Cue semantics depend on your Live mapping.\n\nMAPPING (hex; MIDI channels are 1-based)\n"];
    for(NSInteger deck=0;deck<2;deck++) {
        [guide appendFormat:@"\nDECK %@ — MIDI channel %ld\n",deck ? @"B" : @"A",(long)deck+1];
        NSArray *names=@[@"Play/Pause",@"Cue (momentary)",@"Beat Sync",@"Loop",@"unused",@"Tempo bend - (momentary)",@"Tempo bend + (momentary)",@"Search reverse (momentary)",@"Search forward (momentary)"];
        for(NSUInteger i=0;i<names.count;i++) if(i!=4) [guide appendFormat:@"%-28s %02lX%02lX   Button\n",[names[i] UTF8String],(long)(0x90+deck),(long)i];
        for(NSInteger i=0;i<8;i++) [guide appendFormat:@"Hot Cue %ld                    %02lX%02lX   Pad\n",(long)i+1,(long)(0x90+deck),(long)(16+i)];
        NSArray *knobs=@[@"EQ High",@"EQ Mid",@"EQ Low",@"Color Filter"];
        [guide appendFormat:@"Channel level                %02lX07   Knob/Slider 0–127\n",(long)(0xb0+deck)];
        for(NSInteger i=0;i<4;i++) [guide appendFormat:@"%-28s %02lX%02lX   Knob/Slider 0–127\n",[knobs[i] UTF8String],(long)(0xb0+deck),(long)(16+i)];
    }
    [guide appendString:@"\nCrossfader (global)           BF08   Knob/Slider 0–127\n\nrekordbox buttons release with Note On velocity 0; Live uses standard Note Off. CC values are 7-bit absolute.\nThe bundled rekordbox mapping assigns these functions to both decks. Custom assignments can use Learn.\n\nOfficial guide: https://cdn.rekordbox.com/files/20241203210623/rekordbox7.0.5_midi_learn_operation_guide_EN.pdf\nPlans: https://rekordbox.com/en/support/faq/rekordbox7/\n"];
    return guide;
}
@interface ThreeEDJActions : NSObject
+ (void)setup:(id)sender;
+ (void)restore:(id)sender;
+ (void)install:(id)sender;
+ (void)targetRekordbox:(id)sender;
+ (void)targetLive:(id)sender;
+ (void)chooseTarget:(NSPopUpButton *)sender;
+ (void)saveMapping:(id)sender;
@end
static void DJSelectTarget(BOOL live) {
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    // Release every held pad/nudge through the old output before switching.
    for(NSView *view in midi.views) if([view respondsToSelector:@selector(end)]) [(ThreeEDJControl *)view end];
    [NSUserDefaults.standardUserDefaults setBool:live forKey:DJTargetKey];
    [djTargetChooser selectItemAtIndex:live ? 1 : 0];
    [midi redraw];
}
@implementation ThreeEDJActions
+ (void)targetRekordbox:(id)sender { DJSelectTarget(NO); }
+ (void)targetLive:(id)sender { DJSelectTarget(YES); }
+ (void)chooseTarget:(NSPopUpButton *)sender { DJSelectTarget(sender.indexOfSelectedItem==1); }
+ (void)saveMapping:(id)sender {
    NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"3£ DJ.midi.csv";
    if([panel runModal]!=NSModalResponseOK) return;
    NSError *error=nil; NSData *data=[NSData dataWithContentsOfFile:DJBundledMapping()];
    if(!data || ![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
        NSAlert *alert=[NSAlert new]; alert.messageText=@"The rekordbox mapping could not be saved";
        alert.informativeText=error.localizedDescription ?: @"The bundled mapping file is missing.";[alert runModal];
    }
}
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
        NSRect area=window.contentView.bounds; area.origin.y=44; area.size.height-=44;
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:area]; scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller=YES;
        NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,690,1500)]; text.editable=NO; text.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; text.textContainerInset=NSMakeSize(20,20);
        text.string=DJMappingGuide(); text.autoresizingMask=NSViewWidthSizable; text.textContainer.widthTracksTextView=YES;
        scroll.documentView=text; [window.contentView addSubview:scroll];
        djTargetChooser=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(18,8,200,28) pullsDown:NO];
        [djTargetChooser addItemsWithTitles:@[@"Target: rekordbox",@"Target: Ableton Live"]];
        djTargetChooser.target=self;djTargetChooser.action=@selector(chooseTarget:);
        djTargetChooser.accessibilityLabel=@"Touch DJ output target";
        [window.contentView addSubview:djTargetChooser];
        NSButton *save=[NSButton buttonWithTitle:@"Save rekordbox Mapping…" target:self action:@selector(saveMapping:)];
        save.frame=NSMakeRect(240,8,230,28);[window.contentView addSubview:save];
        [window center];
    }
    [djTargetChooser selectItemAtIndex:[ThreeEDJMIDI shared].liveTarget ? 1 : 0];
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
    NSMenuItem *target=nil;
    for(NSMenuItem *item in menu.itemArray) if([item.identifier isEqual:@"local.threepounds.dj.target"]) target=item;
    if(!target) {
        target=[[NSMenuItem alloc] initWithTitle:@"Touch DJ Target" action:nil keyEquivalent:@""];
        target.identifier=@"local.threepounds.dj.target";target.submenu=[NSMenu new];
        NSMenuItem *rb=[[NSMenuItem alloc] initWithTitle:@"rekordbox" action:@selector(targetRekordbox:) keyEquivalent:@""];
        NSMenuItem *live=[[NSMenuItem alloc] initWithTitle:@"Ableton Live" action:@selector(targetLive:) keyEquivalent:@""];
        rb.target=ThreeEDJActions.class; live.target=ThreeEDJActions.class;
        [target.submenu addItem:rb];[target.submenu addItem:live];[menu addItem:target];
    }
    BOOL live=[ThreeEDJMIDI shared].liveTarget;
    target.title=live ? @"Touch DJ Target: Ableton Live" : @"Touch DJ Target: rekordbox";
    target.submenu.itemArray[0].state=live ? NSControlStateValueOff : NSControlStateValueOn;
    target.submenu.itemArray[1].state=live ? NSControlStateValueOn : NSControlStateValueOff;
    if([menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item,NSUInteger idx,BOOL *stop) { return [item.identifier isEqual:@"local.threepounds.dj.setup"]; }]!=NSNotFound) return;
    NSMenuItem *setup=[[NSMenuItem alloc] initWithTitle:@"Touch DJ Setup…" action:@selector(setup:) keyEquivalent:@""]; setup.target=ThreeEDJActions.class; setup.identifier=@"local.threepounds.dj.setup";
    NSMenuItem *install=[[NSMenuItem alloc] initWithTitle:@"Install / Show Touch DJ" action:@selector(install:) keyEquivalent:@""]; install.target=ThreeEDJActions.class;
    NSMenuItem *restore=[[NSMenuItem alloc] initWithTitle:@"Restore Layouts Before Touch DJ" action:@selector(restore:) keyEquivalent:@""]; restore.target=ThreeEDJActions.class;
    [menu addItem:install]; [menu addItem:setup]; [menu addItem:restore];
}
