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
@protocol ThreeEDJAnimating <NSObject>
- (void)animateAt:(double)time;
@end
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
@property NSTimer *animationTimer;
@property void (^capture)(UInt8,UInt8,UInt8);
@property OSStatus error;
@property BOOL directSearchAvailable;
@property BOOL highResolutionSearchAvailable;
@property NSMutableDictionary<NSString *,NSMutableArray *> *transportQueues;
+ (instancetype)shared;
- (void)start;
- (void)send:(UInt8)status number:(UInt8)number value:(UInt8)value;
- (void)emit:(UInt8)status number:(UInt8)number value:(UInt8)value live:(BOOL)live;
- (void)seekPosition:(NSInteger)value channel:(NSInteger)channel highResolution:(BOOL)highResolution;
- (void)pulseTransport:(NSInteger)channel;
- (void)pulseTransport:(NSInteger)channel when:(BOOL (^)(void))condition;
- (void)enqueueTransport:(void (^)(void (^)(void)))action channel:(NSInteger)channel live:(BOOL)live;
- (void)runTransport:(NSString *)key;
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
static NSInteger DJSeekValue(double seconds,double duration,BOOL highResolution) {
    NSInteger steps=highResolution ? 16384 : 128;
    return duration>0 ? MAX(0,MIN(steps-1,lround(seconds/duration*steps))) : -1;
}
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
    if((self=[super init])) { self.values=[NSMutableDictionary new]; self.received=[NSMutableDictionary new]; self.liveValues=[NSMutableDictionary new]; self.liveReceived=[NSMutableDictionary new]; self.views=[NSHashTable weakObjectsHashTable];self.transportQueues=[NSMutableDictionary new]; }
    return self;
}
- (void)start {
    if(self.client) return;
#ifdef THREEE_DJ_STANDALONE_TEST
    CFStringRef rbName=CFSTR("3£ DJ Verification"), liveName=CFSTR("3£ DJ Live Verification");
#else
    CFStringRef rbName=CFSTR("3£ DJ"), liveName=CFSTR("3£ DJ Live");
#endif
#ifndef THREEE_DJ_STANDALONE_TEST
    NSString *profile=[NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Pioneer/rekordbox6/MidiMappings/3£ DJ.midi.csv"] encoding:NSUTF8StringEncoding error:nil];
    for(NSString *line in [profile componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray *fields=[line componentsSeparatedByString:@","];
        if(fields.count>5 && [fields[0] isEqual:@"NeedleSearch"] && [fields[4] isEqual:@"B014"] && [fields[5] isEqual:@"B114"]) {
            self.directSearchAvailable=YES;
            self.highResolutionSearchAvailable=[fields[2] isEqual:@"KnobSliderHiRes"];
        }
    }
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
    // Separate animation from the slower MIDI/metadata polling clock.
    self.animationTimer=[NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) {
        double now=NSProcessInfo.processInfo.systemUptime;
        for(NSView *view in weakSelf.views) if(view.window && !view.hiddenOrHasHiddenAncestor && [view respondsToSelector:@selector(animateAt:)]) [(id<ThreeEDJAnimating>)view animateAt:now];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
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
    [self emit:status number:number value:value live:self.liveTarget];
}
- (void)emit:(UInt8)status number:(UInt8)number value:(UInt8)value live:(BOOL)live {
    if(self.capture) { self.capture(status,number,value); return; }
    MIDIEndpointRef output=live ? self.liveSource : self.source;
    if(!output) return;
    Byte storage[128]; MIDIPacketList *list=(MIDIPacketList *)storage;
    Byte bytes[]={DJWireStatus(status,live),number,value};
    MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,bytes);
    MIDIReceived(output,list);
    [self redraw];
}
- (void)runTransport:(NSString *)key {
    NSMutableArray *queue=self.transportQueues[key];if(!queue.count) return;
    void (^action)(void (^)(void))=queue.firstObject;
    action(^{[queue removeObjectAtIndex:0];if(queue.count) [self runTransport:key];});
}
- (void)seekPosition:(NSInteger)value channel:(NSInteger)channel highResolution:(BOOL)highResolution {
    if(channel<0 || channel>1 || value<0 || value>(highResolution ? 16383 : 127)) return;
    if(!highResolution) { [self emit:0xb0|channel number:20 value:(UInt8)value live:NO];return; }
    // rekordbox caches the MSB and commits on the LSB. Keep the complete pair
    // in one packet so another control cannot interleave with the position.
    UInt8 status=0xb0|channel;
    Byte bytes[]={status,20,(UInt8)(value>>7),status,52,(UInt8)(value&127)};
    if(self.capture) { self.capture(status,20,bytes[2]);self.capture(status,52,bytes[5]);return; }
    if(!self.source) return;
    Byte storage[128];MIDIPacketList *list=(MIDIPacketList *)storage;
    MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,sizeof(bytes),bytes);
    MIDIReceived(self.source,list);
}
- (void)enqueueTransport:(void (^)(void (^)(void)))action channel:(NSInteger)channel live:(BOOL)live {
    NSString *key=[NSString stringWithFormat:@"%d:%ld",live,(long)channel];
    NSMutableArray *queue=self.transportQueues[key];if(!queue) self.transportQueues[key]=queue=[NSMutableArray new];
    [queue addObject:[action copy]];if(queue.count==1) [self runTransport:key];
}
- (void)pulseTransport:(NSInteger)channel { [self pulseTransport:channel when:nil]; }
- (void)pulseTransport:(NSInteger)channel when:(BOOL (^)(void))condition {
    BOOL live=self.liveTarget;
    [self enqueueTransport:^(void (^done)(void)) {
        if(condition && !condition()) { done();return; }
        [self emit:0x90|channel number:0 value:127 live:live];
        // Measure from the actual press, not a scheduled deadline: a busy main
        // thread must never collapse press/release or reorder seek and resume.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            [self emit:0x80|channel number:0 value:0 live:live];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_MSEC),dispatch_get_main_queue(),done);
        });
    } channel:channel live:live];
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

typedef NS_ENUM(NSInteger,DJControlKind) { DJKnob,DJFader,DJDisc,DJPad };
@interface ThreeEDJControl : NSView <ThreeEDJAnimating>
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
@property double displayAngle;
@property double animationTime;
@property BOOL animationReady;
@property NSUInteger animationFrames;
@property id identity;
@property BOOL moved;
@property BOOL compactDisc;
@property NSTimer *knobTimer;
@property double knobPosition;
@property double knobRate;
@property double knobTickTime;
@property double knobMotionTime;
@property double knobPreviousDrag;
@property double knobAcceptedX;
@property double knobHoldTravel;
@property double knobReverseTravel;
@property double touchStartTime;
@property double discAnchorX;
@property double discMotionX;
@property double discTurnX;
@property NSTimer *discTimer;
@property BOOL needleSearch;
@property BOOL seekHighResolution;
@property BOOL seekHolding;
@property BOOL seekResume;
@property double seekTravelPoints;
@property double seekReadyTime;
@property NSUInteger seekGeneration;
@property NSUInteger seekSerial;
@property double seekOrigin;
@property double seekPositionSeconds;
@property double seekPointX;
@property double seekDuration;
@property NSInteger seekLastValue;
@property NSString *seekTitle;
- (void)publishKnob;
- (void)advanceKnobToTime:(double)time;
- (NSPoint)platterCenter;
@property BOOL search;
@property BOOL gestureSearch;
@property double lastMotion;
@property void (^tapAction)(void);
- (void)releaseIdleAt:(double)time;
- (void)begin:(NSPoint)point identity:(id)identity;
- (void)move:(NSPoint)point;
- (void)end;
@end
static double DJKnobDrag(double distance,double width) {
    double span=MAX(1,width-8),bounded=MAX(-4096,MIN(4096,distance));
    return copysign(127*pow(fabs(bounded)/span,1.35),bounded);
}
static double DJKnobHoldRate(double distance,double width) {
    if(fabs(distance)<=.6) return 0;
    double strength=MAX(0,MIN(1,(fabs(distance)-.6)/MAX(8,(width-8)*.5-.6)));
    // The low end remains usable: a tiny settled displacement creeps steadily,
    // while a large hold tops out at 8 values/second. Direct swipes stay fast.
    return copysign(.5+7.5*pow(strength,1.5),distance);
}
static double DJSeekSensitivity(double duration,double travel) {
    // A physical movement has the same meaning on both pages. Keep even short
    // clips from traversing their entire length with a tiny captured swipe.
    return duration>0 ? MIN(.015,duration/(2*MAX(96,travel))) : .015;
}
static void DJText(NSString *text,NSRect rect,CGFloat size,NSColor *color) {
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.alignment=NSTextAlignmentCenter; style.lineBreakMode=NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
@implementation ThreeEDJControl
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) { self.allowedTouchTypes=NSTouchTypeMaskDirect; self.wantsRestingTouches=YES; self.nudge=-1; [[ThreeEDJMIDI shared].views addObject:self]; }
    return self;
}
- (NSPoint)platterCenter { return NSMakePoint(self.channel==0 ? NSWidth(self.bounds)-16 : 16,15); }
- (id)accessibilityValue {
    if(self.kind==DJDisc) return self.search ? @"SEEK: track position" : @"BEND: temporary tempo adjustment";
    return [super accessibilityValue];
}
- (void)animateAt:(double)time {
    if(self.kind!=DJDisc) return;
    self.animationFrames++;
    if(!self.animationReady) { self.displayAngle=self.angle;self.animationTime=time;self.animationReady=YES; }
    double dt=MAX(0,MIN(.05,time-self.animationTime));self.animationTime=time;
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
    BOOL playing=[deck[@"duration"] doubleValue]>0 && (deck[@"playing"] ? [deck[@"playing"] boolValue] : [midi value:self.channel number:0 note:YES]>0);
    if(self.tracking || !playing) self.displayAngle+=(self.angle-self.displayAngle)*(1-exp(-dt/.045));
    else { self.displayAngle+=dt*(2*M_PI*33.333/60);self.angle=self.displayAngle; }
    self.needsDisplay=YES;
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
        CGFloat discX=self.platterCenter.x-12, textX=left ? 3 : 31;
        NSRect disc=NSMakeRect(discX,3,24,24);
        [[NSColor colorWithWhite:.17 alpha:1] setFill]; [[NSBezierPath bezierPathWithOvalInRect:disc] fill];
        [color setStroke]; NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(disc,1,1)]; ring.lineWidth=self.search ? 1.8 : 1.1;
        if(!self.search) { CGFloat dash[]={3,2};[ring setLineDash:dash count:2 phase:0]; }
        [ring stroke];
        NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
        double angle=self.animationReady ? self.displayAngle : self.angle;
        NSPoint center=NSMakePoint(discX+12,15);
        for(NSNumber *radius in @[@5,@8,@10]) {
            NSBezierPath *groove=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x-radius.doubleValue,center.y-radius.doubleValue,2*radius.doubleValue,2*radius.doubleValue)];
            groove.lineWidth=.35;[[NSColor colorWithWhite:.45 alpha:.35] setStroke];[groove stroke];
        }
        NSBezierPath *shine=[NSBezierPath bezierPath];
        [shine appendBezierPathWithArcWithCenter:center radius:9 startAngle:angle*180/M_PI+15 endAngle:angle*180/M_PI+70];
        shine.lineWidth=1.3;[[color colorWithAlphaComponent:.65] setStroke];[shine stroke];
        NSBezierPath *needle=[NSBezierPath bezierPath];
        [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+8*sin(angle),center.y+8*cos(angle))]; needle.lineWidth=1.5; [needle stroke];
        if(!self.compactDisc) {
        DJText(deck[@"title"] ?: (left ? @"Deck A" : @"Deck B"),NSMakeRect(textX,17,w-34,11),8,color);
        DJText(deck[@"time"] ?: @"— / —",NSMakeRect(textX,8,w-34,9),6.5,dim);
        DJText(self.seekHolding ? (self.seekResume ? @"SEEK · HOLD / lift to play" : @"SEEK · HOLD / paused") : self.search ? (midi.directSearchAvailable && !midi.liveTarget ? @"SEEK · position ↔" : @"SCAN · position ↔") : @"BEND · tempo − / +",NSMakeRect(textX,0,w-34,9),6,self.tracking ? color : dim);
        }
        NSRect badge=NSMakeRect(discX-1,10,26,10);
        [[NSColor colorWithWhite:.045 alpha:1] setFill];[[NSBezierPath bezierPathWithRoundedRect:badge xRadius:3 yRadius:3] fill];
        if(self.search) { [[color colorWithAlphaComponent:self.seekHolding ? .4 : .18] setFill];[[NSBezierPath bezierPathWithRoundedRect:badge xRadius:3 yRadius:3] fill]; }
        DJText(self.search ? @"SEEK" : @"BEND",badge,6.5,self.search ? NSColor.whiteColor : color);
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
        double shownValue=self.tracking ? self.knobPosition : value;
        CGFloat theta=(225-270*shownValue/127.0)*M_PI/180;
        NSBezierPath *needle=[NSBezierPath bezierPath]; [needle moveToPoint:center]; [needle lineToPoint:NSMakePoint(center.x+7*cos(theta),center.y+7*sin(theta))];
        needle.lineWidth=2; [color setStroke]; [needle stroke];
        DJText([NSString stringWithFormat:@"%ld",(long)value],NSMakeRect(w/2,12,w/2-3,12),8,confirmed ? color : dim);
        DJText(self.tracking && fabs(self.knobRate)>0 ? [NSString stringWithFormat:self.knobRate>0 ? @"%@ ›" : @"‹ %@",self.caption] : self.caption,NSMakeRect(1,1,w-2,10),7,NSColor.whiteColor);
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
    self.gestureSearch=self.search;self.touchStartTime=NSProcessInfo.processInfo.systemUptime;
    self.originValue=[[ThreeEDJMIDI shared] value:self.channel number:self.number note:NO];
    if(self.kind==DJKnob) {
        self.knobPosition=self.originValue;self.knobRate=0;self.knobTickTime=self.knobMotionTime=self.touchStartTime;
        self.knobPreviousDrag=0;self.knobAcceptedX=point.x;self.knobHoldTravel=0;self.knobReverseTravel=0;
        __weak ThreeEDJControl *weakSelf=self;
        self.knobTimer=[NSTimer timerWithTimeInterval:.03 repeats:YES block:^(NSTimer *timer) { [weakSelf advanceKnobToTime:NSProcessInfo.processInfo.systemUptime]; }];
        [NSRunLoop.mainRunLoop addTimer:self.knobTimer forMode:NSRunLoopCommonModes];
    }
    if(self.kind==DJDisc) {
        self.discAnchorX=self.discMotionX=self.discTurnX=point.x;self.lastMotion=self.touchStartTime;
        ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
        NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
        self.needleSearch=self.gestureSearch && !midi.liveTarget && midi.directSearchAvailable;
        self.seekHighResolution=midi.highResolutionSearchAvailable;
        self.seekOrigin=[deck[@"elapsed"] doubleValue];self.seekDuration=[deck[@"duration"] doubleValue];self.seekTitle=deck[@"title"];
        self.seekPositionSeconds=self.seekOrigin;self.seekPointX=point.x;
        self.seekHolding=self.seekResume=NO;self.seekReadyTime=0;self.seekGeneration++;self.seekSerial=0;
        self.seekLastValue=DJSeekValue(self.seekOrigin,self.seekDuration,self.seekHighResolution);
        if(self.animationReady) self.angle=self.displayAngle;
        __weak ThreeEDJControl *weakSelf=self;
        self.discTimer=[NSTimer timerWithTimeInterval:.02 repeats:YES block:^(NSTimer *timer) { [weakSelf releaseIdleAt:NSProcessInfo.processInfo.systemUptime]; }];
        [NSRunLoop.mainRunLoop addTimer:self.discTimer forMode:NSRunLoopCommonModes];
    }
    if(self.kind==DJPad) [[ThreeEDJMIDI shared] send:0x90|self.channel number:self.number value:127];
    if(self.kind==DJFader && !self.tapAction) [self move:point];
    self.needsDisplay=YES;
}
- (void)publishKnob {
    self.knobPosition=MAX(0,MIN(127,self.knobPosition));
    NSInteger value=lround(self.knobPosition);
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    if(value!=[midi value:self.channel number:self.number note:NO]) [midi send:0xb0|self.channel number:(UInt8)self.number value:(UInt8)value];
    self.needsDisplay=YES;
}
- (void)advanceKnobToTime:(double)time {
    if(!self.tracking || self.kind!=DJKnob || !isfinite(time)) return;
    // Movement is distance-based. Holding adds a slower continuation only
    // after a settled finger, with a soft start rather than instant velocity.
    double holdStart=self.knobMotionTime+.35;
    double dt=MAX(0,MIN(.05,time-MAX(self.knobTickTime,holdStart)));
    self.knobTickTime=time;
    double ramp=MAX(0,MIN(1,(time-holdStart)/.25));
    self.knobPosition+=self.knobRate*dt*ramp;
    [self publishKnob];
}
- (void)move:(NSPoint)point {
    if(!self.tracking || !isfinite(point.x)) return;
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    CGFloat dx=point.x-self.origin.x;
    // Only horizontal input is meaningful on the Touch Bar.
    if(fabs(dx)>(self.kind==DJDisc ? .8 : 2)) self.moved=YES;
    if(self.kind==DJKnob) {
        [self advanceKnobToTime:NSProcessInfo.processInfo.systemUptime];
        double motion=point.x-self.knobAcceptedX;
        if(fabs(motion)>=.45) {
            double drag=DJKnobDrag(dx,NSWidth(self.bounds));
            self.knobPosition+=drag-self.knobPreviousDrag;
            self.knobPreviousDrag=drag;self.knobAcceptedX=point.x;
            BOOL deliberate=YES;
            if(motion*self.knobHoldTravel<0) {
                self.knobReverseTravel+=motion;
                deliberate=fabs(self.knobReverseTravel)>=1.2;
                if(deliberate) { self.knobHoldTravel=self.knobReverseTravel;self.knobReverseTravel=0; }
            } else {
                // A return from sub-threshold reversal jitter cancels that
                // excursion; it must not ratchet the held speed upward.
                double net=motion+self.knobReverseTravel;
                if(net*self.knobHoldTravel<0) { self.knobReverseTravel=net;deliberate=NO; }
                else { self.knobHoldTravel+=net;self.knobReverseTravel=0;deliberate=fabs(net)>=.45; }
            }
            double span=MAX(8,(NSWidth(self.bounds)-8)*.5);
            self.knobHoldTravel=MAX(-span,MIN(span,self.knobHoldTravel));
            if(fabs(dx)<=.6) { self.knobHoldTravel=0;self.knobReverseTravel=0;deliberate=YES; }
            self.knobRate=DJKnobHoldRate(self.knobHoldTravel,NSWidth(self.bounds));
            // Normal fingertip jitter must not repeatedly restart a settled hold.
            if(deliberate) self.knobMotionTime=NSProcessInfo.processInfo.systemUptime;
            [self publishKnob];
        }
    } else if(self.kind==DJFader) {
        if(self.tapAction && !self.moved) { self.last=point;return; }
        NSInteger value=self.tapAction ? lround(self.originValue+dx/MAX(1,NSWidth(self.bounds)-14)*127) : lround((point.x-7)/MAX(1,NSWidth(self.bounds)-14)*127);
        value=MAX(0,MIN(127,value));
        if(value!=[midi value:self.channel number:self.number note:NO]) [midi send:0xb0|self.channel number:self.number value:(UInt8)value];
    } else if(self.kind==DJDisc) {
        double motion=point.x-self.discMotionX;
        if(fabs(motion)>=.35) {
            if(!self.needleSearch) self.angle+=motion*.12;
            self.discMotionX=point.x;
            self.lastMotion=NSProcessInfo.processInfo.systemUptime;
        }
        if(self.needleSearch) {
            NSDictionary *deck=[[ThreeEDJTelemetry shared] deck:self.channel];
            // Never seek a different track or invent an origin if telemetry
            // disappeared. A new touch can acquire the new track safely.
            if(self.moved && self.seekDuration>0 && [deck[@"title"] isEqual:self.seekTitle] && fabs([deck[@"duration"] doubleValue]-self.seekDuration)<.5) {
                if(!self.seekHolding) {
                    self.seekHolding=YES;
                    NSNumber *play=midi.values[DJKey(self.channel,0,YES)];
                    BOOL playing=deck[@"playing"] ? [deck[@"playing"] boolValue] : play.integerValue>0;
                    // A finger may rest on the wheel for several seconds before
                    // swiping. Acquire the origin now, not at touch-down. Account
                    // for ordinary playback since the latest displayed sample.
                    self.seekOrigin=[deck[@"elapsed"] doubleValue];
                    if(playing) self.seekOrigin+=MAX(0,MIN(.8,NSProcessInfo.processInfo.systemUptime-[ThreeEDJTelemetry shared].updated));
                    self.seekOrigin=MAX(0,MIN(self.seekDuration,self.seekOrigin));
                    self.seekPositionSeconds=self.seekOrigin;
                    self.seekLastValue=DJSeekValue(self.seekOrigin,self.seekDuration,self.seekHighResolution);
                    self.seekResume=playing;
                    if(playing) {
                        [midi pulseTransport:self.channel];
                        self.seekReadyTime=NSProcessInfo.processInfo.systemUptime;
                    }
                }
                double travel=point.x-self.seekPointX;
                if(fabs(travel)<.2) { self.last=point;self.needsDisplay=YES;return; }
                self.seekPointX=point.x;
                double sensitivity=DJSeekSensitivity(self.seekDuration,self.seekTravelPoints);
                // Integrate distance rather than clamping the original anchor:
                // after reaching either end, the first reverse movement works.
                double previousPosition=self.seekPositionSeconds;
                self.seekPositionSeconds=MAX(0,MIN(self.seekDuration,self.seekPositionSeconds+travel*sensitivity));
                self.angle+=(self.seekPositionSeconds-previousPosition)*(2*M_PI*33.333/60);
                double seconds=self.seekPositionSeconds;
                NSInteger value=DJSeekValue(seconds,self.seekDuration,self.seekHighResolution);
                if(value!=self.seekLastValue) {
                    self.seekLastValue=value;NSUInteger generation=self.seekGeneration,serial=++self.seekSerial;
                    [midi enqueueTransport:^(void (^done)(void)) {
                        NSDictionary *current=[[ThreeEDJTelemetry shared] deck:self.channel];
                        if(self.seekGeneration!=generation || self.seekSerial!=serial || ![current[@"title"] isEqual:self.seekTitle] || fabs([current[@"duration"] doubleValue]-self.seekDuration)>=.5) { done();return; }
                        // Pause must settle before Needle Search, which otherwise races transport.
                        [midi seekPosition:value channel:self.channel highResolution:self.seekHighResolution];
                        self.seekReadyTime=NSProcessInfo.processInfo.systemUptime;done();
                    } channel:self.channel live:NO];
                }
            }
            self.last=point;self.needsDisplay=YES;return;
        }
        NSInteger next=self.nudge;
        if(self.nudge<0) {
            double travel=point.x-self.discAnchorX;
            if(fabs(travel)>=1.5) next=self.gestureSearch ? (travel>0 ? 8 : 7) : (travel>0 ? 6 : 5);
        } else {
            BOOL forward=self.nudge==6 || self.nudge==8;
            self.discTurnX=forward ? MAX(self.discTurnX,point.x) : MIN(self.discTurnX,point.x);
            double reverse=point.x-self.discTurnX;
            if((forward && reverse<=-2.5) || (!forward && reverse>=2.5)) next=self.gestureSearch ? (reverse>0 ? 8 : 7) : (reverse>0 ? 6 : 5);
        }
        if(next>=0 && next!=self.nudge) {
            if(!self.gestureSearch && self.nudge<0) {
                NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
                if([deck[@"sync"] boolValue]) {
                    [midi send:0x90|self.channel number:2 value:127];[midi send:0x80|self.channel number:2 value:0];
                    NSMutableDictionary *updated=[deck mutableCopy];updated[@"sync"]=@NO;
                    NSMutableArray *decks=[[ThreeEDJTelemetry shared].decks mutableCopy];decks[self.channel]=updated;[ThreeEDJTelemetry shared].decks=decks;
                }
            }
            if(self.nudge>=0) [midi send:0x80|self.channel number:(UInt8)self.nudge value:0];
            [midi send:0x90|self.channel number:(UInt8)next value:127];self.nudge=next;
            self.discTurnX=point.x;self.moved=YES;
        }
    }
    self.last=point; self.needsDisplay=YES;
}
- (void)releaseIdleAt:(double)time {
    // PlayPause LED feedback can blink while paused. Only actual continued
    // host position progression can relinquish our owned pause during a hold.
    if(self.seekHolding && self.seekResume && time-self.lastMotion>.8 && [ThreeEDJTelemetry shared].updated>self.seekReadyTime+.6 && [[[[ThreeEDJTelemetry shared] deck:self.channel] objectForKey:@"playing"] boolValue]) self.seekResume=NO;
    if(!self.gestureSearch && self.nudge>=0 && time-self.lastMotion>=.22) {
        [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.nudge value:0];self.nudge=-1;self.discAnchorX=self.discTurnX=self.last.x;
    }
}
- (void)end {
    if(!self.tracking) return;
    ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
    NSDictionary *deck=midi.liveTarget ? nil : [[ThreeEDJTelemetry shared] deck:self.channel];
    BOOL resume=self.seekHolding && self.seekResume && [deck[@"title"] isEqual:self.seekTitle] && fabs([deck[@"duration"] doubleValue]-self.seekDuration)<.5;
    self.seekHolding=self.seekResume=NO;
    if(resume) {
        NSString *title=self.seekTitle;double duration=self.seekDuration;
        [midi pulseTransport:self.channel when:^BOOL{
            NSDictionary *current=[[ThreeEDJTelemetry shared] deck:self.channel];
            return [current[@"title"] isEqual:title] && fabs([current[@"duration"] doubleValue]-duration)<.5;
        }];
    }

    if(self.kind==DJPad) [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.number value:0];
    if(self.nudge>=0) [[ThreeEDJMIDI shared] send:0x80|self.channel number:(UInt8)self.nudge value:0];
    [self.knobTimer invalidate];self.knobTimer=nil;self.knobRate=0;
    [self.discTimer invalidate];self.discTimer=nil;self.needleSearch=NO;
    self.nudge=-1; self.tracking=NO; self.identity=nil; self.needsDisplay=YES;
}
- (void)viewWillMoveToWindow:(NSWindow *)newWindow { if(!newWindow) [self end]; [super viewWillMoveToWindow:newWindow]; }
- (void)touchesBeganWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseBegan inView:self]) if(touch.type==NSTouchTypeDirect) { [self begin:[touch locationInView:self] identity:touch.identity]; break; }
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:nil]) if([touch.identity isEqual:self.identity]) [self move:[touch locationInView:self]];
}
- (void)finish {
    BOOL tap=self.tracking && !self.moved;
    if(self.kind==DJDisc && NSProcessInfo.processInfo.systemUptime-self.touchStartTime>.3) tap=NO;
    [self end];
    if(tap && self.kind==DJDisc) { self.search=!self.search;self.needsDisplay=YES; }
    else if(tap && self.tapAction) self.tapAction();
}
- (void)finishAt:(NSPoint)point {
    // A coalesced last movement can arrive only on touch/mouse release.
    if(self.tracking && fabs(point.x-self.last.x)>=.45) [self move:point];
    [self finish];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:nil]) if([touch.identity isEqual:self.identity]) [self finishAt:[touch locationInView:self]];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event { [self end]; }
- (void)mouseDown:(NSEvent *)event { [self begin:[self convertPoint:event.locationInWindow fromView:nil] identity:@"mouse"]; }
- (void)mouseDragged:(NSEvent *)event { [self move:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self finishAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
@end

@interface ThreeEDJRow : NSView
@property NSMutableArray<ThreeEDJControl *> *controls;
@property NSInteger page;
@property NSLayoutConstraint *rowWidth;
- (void)nextPage;
@end
@implementation ThreeEDJRow
- (instancetype)initWithPads:(BOOL)pads {
    if((self=[super initWithFrame:NSMakeRect(0,0,600,30)])) {
        self.controls=[NSMutableArray new];
        self.page=pads ? 1 : 0; // Legacy tile opens the same unified set.
        for(NSInteger deck=0;deck<2;deck++) {
            NSArray *labels=@[@"DISC",@"LEVEL",@"HI",@"MID",@"LOW",@"FILTER",@"▶",@"CUE",@"SYNC",@"LOOP",@"1",@"2",@"3",@"4"];
            for(NSInteger i=0;i<(NSInteger)labels.count;i++) {
                ThreeEDJControl *control=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,30,30)];
                control.channel=deck;control.caption=labels[i];
                control.kind=i==0 ? DJDisc : i==1 ? DJFader : i<6 ? DJKnob : DJPad;
                control.number=i==0 ? 0 : i==1 ? 7 : i<6 ? 14+i : i<10 ? i-6 : 16+i-10;
                NSString *action=i==0 ? @"Tap to switch the labeled SEEK / BEND modes. Swipe SEEK for fine position changes; hold stays paused, lift resumes a previously playing deck" : i==1 ? @"Swipe horizontally to set level" : i<6 ? @"Swipe horizontally for a proportional change; pause and hold for slower continuation. A full-width stroke covers the range. Lift to stop" : @"Press and release MIDI note";
                control.accessibilityLabel=[NSString stringWithFormat:@"Deck %@ %@. %@",deck ? @"B" : @"A",labels[i],action];
                [self.controls addObject:control];[self addSubview:control];
            }
        }
        ThreeEDJControl *cross=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,64,30)];
        cross.kind=DJFader;cross.channel=15;cross.number=8;
        __weak ThreeEDJRow *weakSelf=self;cross.tapAction=^{[weakSelf nextPage];};
        cross.accessibilityLabel=@"Swipe crossfader; tap to switch Mixer and Performance in the same DJ set";
        [self.controls addObject:cross];[self addSubview:cross];
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(600,30); }
- (void)nextPage {
    for(ThreeEDJControl *control in self.controls) [control end];
    self.page=1-self.page;[self layout];self.needsDisplay=YES;
}
- (void)layout {
    [super layout]; CGFloat w=NSWidth(self.bounds),center=w/2;
    CGFloat host=self.window.contentView.bounds.size.width;
    if(host>200 && host<2048 && self.rowWidth) {
        CGFloat target=MAX(300,host-124);
        if(fabs(self.rowWidth.constant-target)>.1) self.rowWidth.constant=target;
    }
    // Both pages share the platter anchor between four transport controls
    // and four hot cues. Mixer metadata grows outward from that same anchor.
    CGFloat hub=64,hubGap=7,half=(w-hub)/2-hubGap;
    CGFloat padGap=3,compactWheel=40,padWidth=(half-compactWheel-8*padGap)/8;
    CGFloat discStart=4*(padWidth+padGap),discEnd=discStart+compactWheel;
    CGFloat mixGap=4,levelWidth=MAX(24,MIN(52,round(half*.13*2)/2));
    CGFloat mixerDiscStart=levelWidth+mixGap,mixerDiscWidth=discEnd-mixerDiscStart;
    for(NSUInteger index=0;index<self.controls.count;index++) {
        NSUInteger local=index%14;
        BOOL visible=index==28 || local==0 || (self.page ? local>=6 : local<=5);
        self.controls[index].hidden=!visible;
    }
    ThreeEDJControl *middle=self.controls.lastObject;middle.hidden=NO;
    middle.frame=NSMakeRect(center-hub/2,0,hub,30);
    middle.caption=self.page ? @"PADS ›" : @"MIX ›";
    middle.accessibilityValue=self.page ? @"Performance view" : @"Mixer view";
    for(NSInteger deck=0;deck<2;deck++) {
        NSRect (^frame)(CGFloat,CGFloat)=^NSRect(CGFloat x,CGFloat width) {
            return NSMakeRect(deck ? w-x-width : x,0,width,30);
        };
        ThreeEDJControl *disc=self.controls[deck*14];
        // Store a single physical travel reference for both layouts; compact
        // platters must never multiply a finger's sensitivity.
        disc.seekTravelPoints=MAX(96,mixerDiscWidth-8);
        disc.compactDisc=self.page==1;
        if(self.page) {
            CGFloat x=0;
            for(NSNumber *index in @[@6,@7,@8,@9,@0,@10,@11,@12,@13]) {
                ThreeEDJControl *control=self.controls[deck*14+index.integerValue];
                CGFloat width=index.integerValue==0 ? compactWheel : padWidth;
                control.frame=frame(x,width);x+=width+padGap;
            }
        } else {
            self.controls[deck*14+1].frame=frame(0,levelWidth);
            disc.frame=frame(mixerDiscStart,mixerDiscWidth);
            CGFloat x=discEnd+mixGap,knobWidth=(half-x-3*mixGap)/4;
            for(NSNumber *index in @[@5,@4,@3,@2]) {
                self.controls[deck*14+index.integerValue].frame=frame(x,knobWidth);
                x+=knobWidth+mixGap;
            }
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
    item.customizationLabel=@"rekordbox · Touch DJ (Mixer + Performance)";
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
    if(bars.count<2 || [NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey]) return;
    NSTouchBar *bar=bars[1];NSArray *before=bar.itemIdentifiers ?: @[];
    [NSUserDefaults.standardUserDefaults setObject:@{bar.customizationIdentifier:before} forKey:DJBackupKey];
    @try { DJSetLayout(bar,@[DJMixerID]); }
    @catch(NSException *exception) {
        @try { DJSetLayout(bar,before); } @catch(NSException *ignored) {}
        [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
        NSLog(@"Touch DJ layout kept unchanged: %@",exception);
    }
}
// Filter only the standalone pad preset we generated; customized bars survive.
static BOOL DJIsRetiredPreset(NSTouchBar *bar) { return [bar.itemIdentifiers isEqual:@[DJPadsID]]; }
static NSMutableArray *DJUnifiedCatalog(NSArray<NSTouchBar *> *bars) {
    NSMutableArray *result=[NSMutableArray new];
    for(NSTouchBar *bar in bars) if(!DJIsRetiredPreset(bar)) [result addObject:bar];
    return result;
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
    NSMutableString *guide=[NSMutableString stringWithString:@"3£ TOUCH DJ — rekordbox / Ableton\n\nOne DJ set: tap the center RB/LIVE hub to switch MIX / PADS without changing presets. Swipe the hub for crossfade. The DJ set fills its available width. Levels sit at the outer edges. Each song name sits outside its disc; the discs stay fixed between Loop and hot cue 1 when switching to PADS.\nMIX: channel levels, HI / MID / LOW / FILTER, track names, elapsed / total time and both discs.\nPADS: Play, Cue, Sync, Loop and four hot cues per deck. The same discs stay active, with their metadata area folded away.\nCyan = Deck A. Amber = Deck B. Knobs follow horizontal swipe distance with a gentle curve: a short swipe makes a small change; a full control-width stroke can cover the complete range. There is no edge snap. A settled hold starts a steady, gentle continuation after 350 ms. A slight displacement creeps slowly; a larger hold reaches at most eight MIDI values per second. Deliberate reversals change direction; small fingertip jitter does not restart the hold. Lift to stop; return to the touch anchor to stop holding. Each finger remains independent.\nTap a disc to switch BEND / SEEK. The full mode name stays on each disc in both views: solid ring for SEEK, segmented ring for BEND. Swipe left/right to slow/speed or search backward/forward. Bend accumulates slow movements, ignores tiny reversal jitter and releases after 220 ms without motion. A swipe or stationary hold cannot switch wheel mode; only a short still tap does. With the updated rekordbox mapping, S is direct needle seeking: movement changes position and pauses a playing deck for the hold. Keep your finger down to wait at that position; lift resumes only a deck paused by that gesture. A deck already paused stays paused. Both views use the same physical wheel sensitivity: compact wheels do not amplify travel. Small motions make small cue adjustments (about 0.015 seconds per point, gentler for very short clips). Repeat swipes for longer travel. Reversing at either track end responds immediately, including after overshooting. It acquires its starting position when the swipe begins, including playback since the last sample. The updated mapping sends 14-bit paired CC 20/52; older Value mappings retain 7-bit input. rekordbox may still land Needle Search on beat-sized steps, even with Quantize off; it is not sample-accurate scratching. It needs fresh track/time data. Mappings without Needle Search retain fast scan until the new mapping is imported and rekordbox is restarted. Live has no needle-position mapping in the supplied set. If rekordbox reports Sync enabled, bending first turns it off. These are MIDI bend/search controls, not scratch jog wheels.\n\nSETUP\nOpen 3£ first. Choose Install / Show Touch DJ in its menu once. This seeds a ready mapping only if 3£ DJ has no existing mapping. Restart rekordbox once after initial setup. Select rekordbox in Touch DJ Target. In rekordbox select PERFORMANCE → MIDI → 3£ DJ.\nMIDI Learn requires an eligible plan or trial, or compatible Hardware Unlock equipment.\nIf needed, use Save rekordbox Mapping below, then IMPORT it for the 3£ DJ device. For manual mapping, add the matching function/deck and enter MIDI IN, or use LEARN and touch the control. Turn LEARN off when finished.\nFor supported indicators, set MIDI OUT to the same code and route output to 3£ DJ.\nA dot under a pad / colored value means recently received feedback; gray values are local positions. Track name and elapsed/total time come from a read-only adapter for the visible rekordbox deck fields, using existing macOS Accessibility permission. Metadata clears after 2.5 seconds without a fresh read. The port does not prove rekordbox is connected.\n\nThe virtual port must be verified in your installed rekordbox version. Some third-party functions and jog wheels are restricted. Bend uses momentary +/- notes. Updated S uses paired 14-bit Needle Search on CC 20/52, with fine horizontal sensitivity (at most 0.015 seconds per point, identical in both views). It is position seeking, not vinyl scratching. Needle Lock in rekordbox can restrict seeking during playback. No driver spoofing.\nGeneric MIDI does not provide track titles or time. The separate accessibility adapter reads only rekordbox deck fields; it does not inspect the library database, track selections or audio. No waveform is simulated. If unavailable, the discs show dashes. Live metadata is not provided by this adapter.\n\nABLETON\nEnable Remote for 3£ DJ Live input and output. Keep input Track off for controller-only use. Keep Remote off for the separate 3£ DJ port in Live. Select Ableton Live in 3£ → Touch DJ Target; choose rekordbox to return. The center fader shows LIVE or RB. Feedback is cached separately for each host. Use Live MIDI Map on levels, EQ, filter, crossfader and clip/transport buttons. Add EQ/filter devices first. DJ Cue/Sync/Hot Cue semantics depend on your Live mapping.\n\nMAPPING (hex; MIDI channels are 1-based)\n"];
    for(NSInteger deck=0;deck<2;deck++) {
        [guide appendFormat:@"\nDECK %@ — MIDI channel %ld\n",deck ? @"B" : @"A",(long)deck+1];
        NSArray *names=@[@"Play/Pause",@"Cue (momentary)",@"Beat Sync",@"Loop",@"unused",@"Tempo bend - (momentary)",@"Tempo bend + (momentary)",@"Search reverse (momentary)",@"Search forward (momentary)"];
        for(NSUInteger i=0;i<names.count;i++) if(i!=4) [guide appendFormat:@"%-28s %02lX%02lX   Button\n",[names[i] UTF8String],(long)(0x90+deck),(long)i];
        for(NSInteger i=0;i<8;i++) [guide appendFormat:@"Hot Cue %ld                    %02lX%02lX   Pad\n",(long)i+1,(long)(0x90+deck),(long)(16+i)];
        NSArray *knobs=@[@"EQ High",@"EQ Mid",@"EQ Low",@"Color Filter"];
        [guide appendFormat:@"Channel level                %02lX07   Knob/Slider 0–127\n",(long)(0xb0+deck)];
        for(NSInteger i=0;i<4;i++) [guide appendFormat:@"%-28s %02lX%02lX   Knob/Slider 0–127\n",[knobs[i] UTF8String],(long)(0xb0+deck),(long)(16+i)];
        [guide appendFormat:@"Needle Search                 %02lX14 + CC52   KnobSliderHiRes\n",(long)(0xb0+deck)];
    }
    [guide appendString:@"\nCrossfader (global)           BF08   Knob/Slider 0–127\n\nrekordbox buttons release with Note On velocity 0; Live uses standard Note Off. Mixer CC values are 7-bit absolute; Needle Search uses a paired 14-bit value.\nThe bundled rekordbox mapping assigns these functions to both decks. Custom assignments can use Learn.\n\nOfficial guide: https://cdn.rekordbox.com/files/20241203210623/rekordbox7.0.5_midi_learn_operation_guide_EN.pdf\nPlans: https://rekordbox.com/en/support/faq/rekordbox7/\n"];
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
