#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/message.h>
#import <math.h>
#define THREEE_DJ_STANDALONE_TEST 1
#import <stdatomic.h>
#import "../Source/DJSurface.h"
// AppKit-shaped direct-touch fixtures exercise handlers, including a captured
// finger reported against a neighboring view after leaving the compact wheel.
@interface DJTestTouch : NSObject
@property NSPoint point;
@property id identity;
@property NSView *target;
@end
@implementation DJTestTouch
- (NSTouchType)type { return NSTouchTypeDirect; }
- (BOOL)isResting { return YES; }
- (NSPoint)locationInView:(NSView *)view { return self.point; }
@end
@interface DJTestEvent : NSObject
@property DJTestTouch *touch;
@property NSTouchPhase phase;
@end
@implementation DJTestEvent
- (NSSet *)touchesMatchingPhase:(NSTouchPhase)phase inView:(NSView *)view {
    return (phase & self.phase) && (!view || view==self.touch.target) ? [NSSet setWithObject:self.touch] : NSSet.set;
}
@end
static NSMutableArray *sent;
static atomic_int loopbackPackets;
static atomic_int liveLoopbackPackets;
static atomic_int rbReleases,liveReleases;
static atomic_int hiResPackets;
static void Loopback(const MIDIPacketList *packets,void *context,void *unused) {
    const MIDIPacket *p=&packets->packet[0];
    for(UInt32 i=0;i<packets->numPackets;i++,p=MIDIPacketNext(p)) {
        // CoreMIDI can coalesce consecutive received packets in this callback.
        for(UInt16 j=0;j+2<p->length;j+=3) {
            const Byte *b=p->data+j;
            if(b[0]==0x90 && b[1]==1) { if(b[2]==127) atomic_fetch_add(&loopbackPackets,1);else if(b[2]==0) atomic_fetch_add(&rbReleases,1); }
            if(j+5<p->length && b[0]==0xb1 && b[1]==20 && b[2]==64 && b[3]==0xb1 && b[4]==52 && b[5]==64) atomic_fetch_add(&hiResPackets,1);
        }
    }
}
static void LiveLoopback(const MIDIPacketList *packets,void *context,void *unused) {
    const MIDIPacket *p=&packets->packet[0];
    if(packets->numPackets && p->length==3 && p->data[0]==0x90 && p->data[1]==1 && p->data[2]==127) atomic_fetch_add(&liveLoopbackPackets,1);
    if(packets->numPackets && p->length==3 && p->data[0]==0x80 && p->data[1]==1 && p->data[2]==0) atomic_fetch_add(&liveReleases,1);
}
static ThreeEDJControl *Control(DJControlKind kind,NSInteger channel,NSInteger number) {
    ThreeEDJControl *c=[[ThreeEDJControl alloc] initWithFrame:NSMakeRect(0,0,100,30)]; c.kind=kind; c.channel=channel; c.number=number; return c;
}
static void DrainTransport(void) {
    double deadline=NSProcessInfo.processInfo.systemUptime+2;
    while(YES) {
        BOOL pending=NO;for(NSArray *queue in [ThreeEDJMIDI shared].transportQueues.allValues) if(queue.count) pending=YES;
        if(!pending) return;
        NSCAssert(NSProcessInfo.processInfo.systemUptime<deadline,@"Transport queue must finish within the bounded test deadline");
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
}
static void Feed(ThreeEDJMIDI *midi,const UInt8 *bytes,NSUInteger count) { [midi consume:[NSData dataWithBytes:bytes length:count]]; }
static void Render(ThreeEDJRow *row,NSString *path) {
    [row layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap=[row bitmapImageRepForCachingDisplayInRect:row.bounds];
    [row cacheDisplayInRect:row.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
        ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
        id savedTarget=[NSUserDefaults.standardUserDefaults objectForKey:DJTargetKey];
        DJSelectTarget(NO);
        sent=[NSMutableArray new];
        midi.capture=^(UInt8 status,UInt8 number,UInt8 value) { [sent addObject:@[@(status),@(number),@(value)]]; };
        ThreeEDJControl *pad=Control(DJPad,1,23);
        [pad begin:NSMakePoint(20,15) identity:@1]; [pad begin:NSMakePoint(25,15) identity:@2]; [pad end]; [pad end];
        NSCAssert(([sent isEqual:@[@[@0x91,@23,@127],@[@0x81,@23,@0]]]),@"Repeated touches/end must produce exactly one on and off on the correct deck");
        [sent removeAllObjects];
        ThreeEDJControl *disc=Control(DJDisc,0,0);
        [disc begin:NSMakePoint(50,15) identity:@1]; [disc move:NSMakePoint(80,15)]; [disc move:NSMakePoint(85,15)]; [disc move:NSMakePoint(25,15)]; [disc touchesCancelledWithEvent:nil];
        NSCAssert(([sent isEqual:@[@[@0x90,@6,@127],@[@0x80,@6,@0],@[@0x90,@5,@127],@[@0x80,@5,@0]]]),@"Nudge must release previous direction, avoid repeats, and release on cancellation");
        [sent removeAllObjects];
        ThreeEDJControl *knob=Control(DJKnob,1,16);knob.frame=NSMakeRect(0,0,42,30);
        [knob begin:NSMakePoint(21,15) identity:@1];[knob move:NSMakePoint(21,29)];
        [knob advanceKnobToTime:knob.knobTickTime+.1];NSCAssert(sent.count==0,@"Vertical coordinates never adjust a Touch Bar knob");
        [knob move:NSMakePoint(26,15)];NSInteger small=[midi value:1 number:16 note:NO];
        NSCAssert(small>64 && small<85,@"A short swipe changes a modest proportional amount, not an endpoint");
        [knob advanceKnobToTime:knob.knobTickTime+.2];NSCAssert([midi value:1 number:16 note:NO]==small,@"Holding must wait for a settled finger");
        for(NSInteger tick=0;tick<50;tick++) [knob advanceKnobToTime:knob.knobTickTime+.02];
        NSInteger heldValue=[midi value:1 number:16 note:NO];NSCAssert(heldValue>small && heldValue<100,@"Hold continuation is slow and starts gently");
        [knob move:NSMakePoint(24,15)];NSCAssert([midi value:1 number:16 note:NO]<heldValue && knob.knobRate<0,@"A reversal must immediately decrease and hold in the latest direction");
        [knob move:NSMakePoint(21,15)];NSCAssert(knob.knobRate==0,@"Returning to the touch anchor stops continuation");[knob end];NSCAssert(!knob.knobTimer,@"Lift cancels the timer");
        [midi.values removeAllObjects];
        ThreeEDJControl *hi=Control(DJKnob,0,16),*mid=Control(DJKnob,0,17);
        hi.frame=mid.frame=NSMakeRect(0,0,42,30);
        [hi begin:NSMakePoint(21,15) identity:@1];[mid begin:NSMakePoint(21,15) identity:@2];
        [hi move:NSMakePoint(26,15)];[mid move:NSMakePoint(16,15)];
        NSCAssert([midi value:0 number:16 note:NO]>64 && [midi value:0 number:17 note:NO]<64,@"Two x-only fingers adjust in opposite directions independently");
        [mid move:NSMakePoint(18,15)];NSCAssert(mid.knobRate>0 && hi.knobRate>0,@"Reversing a finger makes both holds move in the same direction");
        [hi touchesCancelledWithEvent:nil];[mid end];NSInteger released=[midi value:0 number:16 note:NO];
        [hi advanceKnobToTime:hi.knobTickTime+.1];NSCAssert(!hi.knobTimer && [midi value:0 number:16 note:NO]==released,@"Cancellation cannot continue changing a knob");
        midi.values[DJKey(0,16,NO)]=@64;midi.values[DJKey(0,17,NO)]=@64;
        [hi begin:NSMakePoint(21,15) identity:@1];[mid begin:NSMakePoint(21,15) identity:@2];
        [hi move:NSMakePoint(23,15)];[mid move:NSMakePoint(19,15)];
        NSCAssert(hi.knobRate>0 && hi.knobRate<8 && mid.knobRate<0 && mid.knobRate>-8,@"Small opposite swipes must select gentle independent hold rates");
        double steady=MAX(hi.knobMotionTime,mid.knobMotionTime)+.7;
        [hi advanceKnobToTime:steady];[mid advanceKnobToTime:steady];
        double hiStart=hi.knobPosition,midStart=mid.knobPosition;
        for(NSInteger tick=1;tick<=40;tick++) { [hi advanceKnobToTime:steady+tick*.025];[mid advanceKnobToTime:steady+tick*.025]; }
        double firstChange=hi.knobPosition-hiStart;
        NSCAssert(fabs(firstChange-hi.knobRate)<.001 && fabs(mid.knobPosition-midStart-mid.knobRate)<.001,@"Settled holds must integrate a steady rate in either direction");
        hiStart=hi.knobPosition;
        for(NSInteger tick=41;tick<=80;tick++) [hi advanceKnobToTime:steady+tick*.025];
        NSCAssert(fabs(hi.knobPosition-hiStart-firstChange)<.001,@"Equal hold intervals must produce equal gradual changes without acceleration");
        double settledAt=hi.knobMotionTime,steadyRate=hi.knobRate;
        [hi move:NSMakePoint(22.5,15)];
        NSCAssert(hi.knobRate==steadyRate && hi.knobMotionTime==settledAt,@"Small reversal jitter must not flip or restart a steady hold");
        [hi move:NSMakePoint(23,15)];
        for(NSInteger jitter=0;jitter<10;jitter++) { [hi move:NSMakePoint(22.5,15)];[hi move:NSMakePoint(23,15)]; }
        NSCAssert(hi.knobRate==steadyRate && hi.knobMotionTime==settledAt,@"Repeated stationary fingertip jitter must not ratchet up hold speed or postpone continuation");
        [hi move:NSMakePoint(23.5,15)];[hi move:NSMakePoint(24,15)];
        for(NSInteger resting=0;resting<10;resting++) { [hi move:NSMakePoint(23.5,15)];[hi move:NSMakePoint(24,15)]; }
        NSCAssert(hi.knobRate==steadyRate && hi.knobMotionTime==settledAt,@"Small resting-touch drift must not continually re-arm the dwell or alter the latched hold rate");
        [hi move:NSMakePoint(21.7,15)];NSCAssert(hi.knobRate<0 && mid.knobRate<0,@"A deliberate reversal can make both independent holds decrease together");
        [hi move:NSMakePoint(21,15)];NSCAssert(hi.knobRate==0,@"Returning to the anchor still stops continuation");[hi end];[mid end];
        ThreeEDJControl *timed=Control(DJKnob,1,17);timed.frame=NSMakeRect(0,0,42,30);
        [timed begin:NSMakePoint(21,15) identity:@1];[timed move:NSMakePoint(26,15)];NSInteger immediate=[midi value:1 number:17 note:NO];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
        NSCAssert([midi value:1 number:17 note:NO]==immediate,@"The real timer must not accelerate an ordinary short swipe");
        double timerDeadline=NSProcessInfo.processInfo.systemUptime+2;
        while([midi value:1 number:17 note:NO]==immediate && NSProcessInfo.processInfo.systemUptime<timerDeadline)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert([midi value:1 number:17 note:NO]>immediate,@"A settled hold runs the actual continuation timer");[timed end];
        NSInteger final=[midi value:1 number:17 note:NO];[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        NSCAssert([midi value:1 number:17 note:NO]==final,@"The timer stops after lift");
        // Touch tracking may use a run-loop mode outside the common modes.
        // Begin inside that mode and keep a resting finger down there.
        NSString *trackingMode=@"ThreeEDJDirectTouchTrackingTest";
        ThreeEDJControl *trackingKnob=Control(DJKnob,1,18);trackingKnob.frame=NSMakeRect(0,0,42,30);
        midi.values[DJKey(1,18,NO)]=@64;__block NSInteger trackingInitial=-1;
        NSTimer *startTracking=[NSTimer timerWithTimeInterval:.001 repeats:NO block:^(NSTimer *timer) {
            [trackingKnob begin:NSMakePoint(21,15) identity:@"resting-finger"];
            [trackingKnob move:NSMakePoint(23,15)];trackingInitial=[midi value:1 number:18 note:NO];
        }];
        NSTimer *trackingHeartbeat=[NSTimer timerWithTimeInterval:.02 repeats:YES block:^(NSTimer *timer) {}];
        [NSRunLoop.mainRunLoop addTimer:startTracking forMode:trackingMode];[NSRunLoop.mainRunLoop addTimer:trackingHeartbeat forMode:trackingMode];
        NSDate *trackingDeadline=[NSDate dateWithTimeIntervalSinceNow:1.3];
        while(trackingDeadline.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runMode:trackingMode beforeDate:trackingDeadline];
        [trackingHeartbeat invalidate];
        NSCAssert(trackingInitial>=0 && trackingKnob.knobTickTime>trackingKnob.touchStartTime+.5,@"A held knob's timer must continue firing inside the actual touch-tracking run-loop mode");
        NSCAssert([midi value:1 number:18 note:NO]>trackingInitial,@"A small swipe-and-hold must visibly continue while the finger rests");
        [trackingKnob end];NSCAssert(!trackingKnob.knobTimer && !trackingKnob.knobTrackingMode,@"Lift must invalidate the timer across all registered tracking modes");
        ThreeEDJControl *smooth=Control(DJKnob,0,18);smooth.frame=NSMakeRect(0,0,42,30);
        midi.values[DJKey(0,18,NO)]=@64;[smooth begin:NSMakePoint(21,15) identity:@1];[smooth move:NSMakePoint(33,15)];
        NSCAssert([midi value:0 number:18 note:NO]<110,@"The former endpoint threshold must no longer jump a modest swipe to maximum");[smooth end];
        midi.values[DJKey(0,18,NO)]=@64;[smooth begin:NSMakePoint(40,15) identity:@1];[smooth move:NSMakePoint(41,15)];[smooth end];
        NSCAssert(abs((int)[midi value:0 number:18 note:NO]-64)<=2,@"A small movement beside an edge remains a small change");
        midi.values[DJKey(0,18,NO)]=@0;[smooth begin:NSMakePoint(4,15) identity:@1];NSInteger previousSweepValue=0;
        for(NSInteger x=6;x<=38;x+=2) {
            [smooth move:NSMakePoint(x,15)];NSInteger value=[midi value:0 number:18 note:NO];
            NSCAssert(value>=previousSweepValue && value-previousSweepValue<=12,@"Equal small input steps must make a continuous monotonic sweep without an edge discontinuity");previousSweepValue=value;
        }
        NSCAssert(previousSweepValue==127,@"A full-width stroke still covers the complete range");
        [smooth move:NSMakePoint(36,15)];NSCAssert([midi value:0 number:18 note:NO]<127,@"A reversal responds immediately without crossing the original anchor");
        [smooth move:NSMakePoint(50,15)];[smooth move:NSMakePoint(49,15)];NSCAssert([midi value:0 number:18 note:NO]<127,@"Reversals also respond after overshooting a saturated endpoint");[smooth end];
        ThreeEDJRow *mixer=[[ThreeEDJRow alloc] initWithPads:NO];mixer.frame=NSMakeRect(0,0,756,30);[mixer layout];NSUInteger covered=0;
        for(ThreeEDJControl *c in mixer.controls) if(c.kind==DJKnob && !c.hidden) {
            midi.values[DJKey(c.channel,c.number,NO)]=@0;[c begin:NSMakePoint(4,15) identity:@(covered)];
            [c move:NSMakePoint(NSWidth(c.bounds)/2,15)];NSInteger halfway=[midi value:c.channel number:c.number note:NO];
            NSCAssert(halfway>30 && halfway<90,@"Half a stroke must remain intermediate on every first-view knob");
            [c move:NSMakePoint(NSWidth(c.bounds)-4,15)];NSCAssert([midi value:c.channel number:c.number note:NO]==127,@"Full stroke reaches maximum on every knob");
            [c move:NSMakePoint(4,15)];NSCAssert([midi value:c.channel number:c.number note:NO]==0,@"Full reverse stroke reaches minimum on every knob");[c end];covered++;
        }
        NSCAssert(covered==8,@"All eight first-view knobs are covered");
        [sent removeAllObjects];ThreeEDJControl *slowDisc=Control(DJDisc,0,0);
        [slowDisc begin:NSMakePoint(50,15) identity:@1];for(NSInteger i=1;i<=6;i++) [slowDisc move:NSMakePoint(50+i*.3,15)];
        NSCAssert(slowDisc.nudge==6 && sent.count==1,@"Sub-point wheel packets accumulate into a slow continuous gesture");
        [slowDisc finish];NSCAssert(!slowDisc.search && !slowDisc.discTimer,@"A recognized slow swipe releases and never changes wheel mode");
        [sent removeAllObjects];[slowDisc begin:NSMakePoint(50,15) identity:@1];[slowDisc move:NSMakePoint(54,15)];
        [slowDisc move:NSMakePoint(53.6,15)];[slowDisc move:NSMakePoint(54.2,15)];[slowDisc move:NSMakePoint(53.9,15)];
        NSCAssert(slowDisc.nudge==6 && sent.count==1,@"Small reversal jitter must not alternate bend directions");
        [slowDisc move:NSMakePoint(51.4,15)];NSCAssert(slowDisc.nudge==5 && sent.count==3,@"A deliberate reversal releases old direction before engaging the new one");[slowDisc end];
        [slowDisc begin:NSMakePoint(50,15) identity:@1];[slowDisc move:NSMakePoint(51,15)];[slowDisc finish];
        NSCAssert(!slowDisc.search,@"Even a very small swipe must not be misread as a Search-mode tap");
        [slowDisc begin:NSMakePoint(50,15) identity:@1];slowDisc.touchStartTime-=.5;[slowDisc finish];NSCAssert(!slowDisc.search,@"A stationary hold must not toggle wheel mode");
        [slowDisc begin:NSMakePoint(50,15) identity:@1];[slowDisc finish];NSCAssert(slowDisc.search,@"A genuine short still tap can still choose Search");
        slowDisc.search=NO;[slowDisc begin:NSMakePoint(50,15) identity:@1];[slowDisc finishAt:NSMakePoint(54,15)];
        NSCAssert(!slowDisc.search && !slowDisc.tracking && slowDisc.nudge<0,@"A coalesced release movement must not become a mode-changing tap or leave a held note");
        NSCAssert(DJWireStatus(0x81,NO)==0x91 && DJWireStatus(0x81,YES)==0x81,@"Rekordbox momentary releases use Note On zero; Live uses Note Off");
        [sent removeAllObjects]; disc.search=YES;
        [disc begin:NSMakePoint(50,15) identity:@1];[disc move:NSMakePoint(75,15)];
        NSCAssert(([sent.lastObject isEqual:@[@0x90,@8,@127]]),@"Search uses its own forward control");
        [disc releaseIdleAt:disc.lastMotion+.2];
        NSCAssert(disc.nudge==8,@"Search keeps scanning while held, allowing the host hold threshold to elapse");[disc end];
        NSCAssert(([sent.lastObject isEqual:@[@0x80,@8,@0]]),@"Lifting must release search");
        disc.search=NO;[disc begin:NSMakePoint(50,15) identity:@1];[disc move:NSMakePoint(75,15)];[disc releaseIdleAt:disc.lastMotion+.3];
        NSCAssert(disc.nudge<0,@"A stationary finger must stop tempo bending");[disc end];
        ThreeEDJControl *fader=Control(DJFader,15,8);
        [fader begin:NSMakePoint(7,15) identity:@1]; [fader move:NSMakePoint(93,15)]; [fader end];
        NSCAssert(([sent.lastObject isEqual:@[@0xbf,@8,@127]]),@"Crossfader uses a dedicated master channel");
        NSUInteger before=sent.count;
        UInt8 partial[]={0xb0,16}; Feed(midi,partial,sizeof(partial));
        UInt8 rest[]={0xf8,99,17,33,0x91,0,127,0,0,0xb2,16,111,0xf0,0x7d,1,0xf7,0xb1,19,81}; Feed(midi,rest,sizeof(rest));
        NSCAssert([midi value:0 number:16 note:NO]==99 && [midi value:0 number:17 note:NO]==33,@"Partial packets, realtime bytes and running status must preserve CC feedback");
        NSCAssert([midi value:1 number:0 note:YES]==0 && [midi confirmed:1 number:0 note:YES],@"Note On zero represents an unlit LED");
        NSCAssert(!midi.values[DJKey(2,16,NO)] && [midi value:1 number:19 note:NO]==81,@"Ignore unrelated channels and SysEx without losing later feedback");
        NSCAssert(sent.count==before,@"Incoming feedback must never echo MIDI");
        midi.received[DJKey(1,0,YES)]=@(NSProcessInfo.processInfo.systemUptime-6);
        NSCAssert(![midi confirmed:1 number:0 note:YES],@"Stale feedback must not be represented as live");
        // Each host retains independent values, running status and feedback freshness.
        UInt8 rbPart[]={0xb0,18}; [midi consume:[NSData dataWithBytes:rbPart length:2] live:NO];
        UInt8 liveFull[]={0xb0,18,91}; [midi consume:[NSData dataWithBytes:liveFull length:3] live:YES];
        UInt8 rbEnd[]={22}; [midi consume:[NSData dataWithBytes:rbEnd length:1] live:NO];
        NSCAssert([midi value:0 number:18 note:NO]==22,@"Interleaved Live packets must not disturb rekordbox running status");
        DJSelectTarget(YES); NSCAssert([midi value:0 number:18 note:NO]==91,@"Host values must stay separate"); DJSelectTarget(NO);
        NSMutableArray *sentHosts=[NSMutableArray new];
        __weak ThreeEDJMIDI *weakMIDI=midi;
        midi.capture=^(UInt8 status,UInt8 number,UInt8 value) { [sentHosts addObject:@(weakMIDI.liveTarget)]; };
        ThreeEDJControl *held=Control(DJPad,0,17); [held begin:NSMakePoint(20,15) identity:@1];
        DJSelectTarget(YES); [held begin:NSMakePoint(20,15) identity:@2]; [held end];
        NSCAssert(([sentHosts isEqual:@[@NO,@NO,@YES,@YES]]),@"Switching must release old-host notes before routing new touches to Live");
        DJSelectTarget(NO); midi.capture=^(UInt8 status,UInt8 number,UInt8 value) { [sent addObject:@[@(status),@(number),@(value)]]; };
        [midi.values removeAllObjects]; [midi.received removeAllObjects];
        ThreeEDJRow *row=[[ThreeEDJRow alloc] initWithPads:NO];
        NSCAssert(row.controls.count==29,@"The unified set owns two discs, ten mixer controls, sixteen buttons and one hub");
        for(NSNumber *width in @[@480,@600,@756,@880]) {
            row.frame=NSMakeRect(0,0,width.doubleValue,30);
            for(NSInteger page=0;page<2;page++) {
                row.page=page;[row layout];NSUInteger visible=0;
                NSMutableArray *frames=[NSMutableArray new];
                for(ThreeEDJControl *c in row.controls) if(!c.hidden) {
                    visible++;NSCAssert(NSMinX(c.frame)>=0 && NSMaxX(c.frame)<=width.doubleValue+.1 && NSWidth(c.frame)>10,@"Every visible control must fit");
                    for(NSValue *frame in frames) NSCAssert(!NSIntersectsRect(c.frame,frame.rectValue),@"Targets must not overlap");
                    [frames addObject:[NSValue valueWithRect:c.frame]];
                }
                NSCAssert(visible==(page ? 19 : 13),@"Mixer shows all EQ/levels; Performance shows eight buttons and a disc per deck");
                NSInteger edge=page ? 7 : 1;
                NSCAssert(NSMinX(row.controls[edge].frame)==0 && fabs(NSMaxX(row.controls[14+edge].frame)-width.doubleValue)<.1,@"Levels in MIX and transport buttons in PADS must use the full available width");
                if(page) {
                    NSCAssert(NSMaxX(row.controls[9].frame)<NSMinX(row.controls[0].frame) && NSMaxX(row.controls[0].frame)<NSMinX(row.controls[6].frame) && NSMaxX(row.controls[6].frame)<NSMinX(row.controls[10].frame),@"Deck A has Loop, disc, Play, then hot cue 1");
                    NSCAssert(NSMaxX(row.controls[24].frame)<NSMinX(row.controls[20].frame) && NSMaxX(row.controls[20].frame)<NSMinX(row.controls[14].frame) && NSMaxX(row.controls[14].frame)<NSMinX(row.controls[23].frame),@"Deck B mirrors hot cue 1, Play, disc and Loop");
                } else NSCAssert(NSMaxX(row.controls[1].frame)<NSMinX(row.controls[0].frame) && row.controls[0].platterCenter.x>NSWidth(row.controls[0].bounds)/2,@"Level and song name must sit outside the inward-facing disc");
                for(NSInteger local=0;local<14;local++) {
                    ThreeEDJControl *a=row.controls[local],*b=row.controls[14+local];
                    if(a.hidden) continue;
                    NSCAssert(fabs(NSMidX(a.frame)+NSMidX(b.frame)-width.doubleValue)<.1 && fabs(NSWidth(a.frame)-NSWidth(b.frame))<.1,@"The right deck must mirror every corresponding left control in both views");
                }
                for(NSInteger deck=0;deck<2;deck++) for(NSInteger i=0;i<4;i++) NSCAssert(!row.controls[deck*14+10+i].hidden==page,@"Only four hot cues per deck appear in Performance");
            }
            row.page=0;[row layout];
            NSPoint a=[row.controls[0] convertPoint:row.controls[0].platterCenter toView:row],b=[row.controls[14] convertPoint:row.controls[14].platterCenter toView:row];
            if(width.doubleValue==880) {
                NSCAssert(NSWidth(row.controls[2].frame)>=52 && NSWidth(row.controls[0].frame)<=120,@"Compact descriptions must give every MIX knob at least 52 points on the native bar");
                NSCAssert(a.x<=160 && b.x>=720,@"Both platters must move outward with the shorter descriptions");
                NSCAssert(fabs(row.controls[0].seekTravelPoints-156.5)<.001,@"Shorter descriptions must preserve the approved physical seek response");
            }
            NSCAssert(a.x>width.doubleValue*.15 && b.x<width.doubleValue*.85,@"Both discs must have substantial swipe room on both sides");
            [row nextPage];
            NSCAssert(NSEqualPoints(a,[row.controls[0] convertPoint:row.controls[0].platterCenter toView:row]) && NSEqualPoints(b,[row.controls[14] convertPoint:row.controls[14].platterCenter toView:row]),@"Platter centers must never move when metadata folds away");
            NSCAssert(fabs(NSMidX(row.controls.lastObject.frame)-width.doubleValue/2)<.1,@"The hub remains centered within the usable DJ row");
        }
        row.frame=NSMakeRect(0,0,756,30);row.page=0;[row layout];
        ThreeEDJControl *hub=row.controls.lastObject;NSUInteger tapBefore=sent.count;
        [hub begin:NSMakePoint(30,15) identity:@1];[hub move:NSMakePoint(31,15)];[hub finish];
        NSCAssert(row.page==1 && sent.count==tapBefore,@"A center tap, including small jitter, switches view without moving the crossfader");
        row.page=0;[row layout];
        if(argc>1) {
            row.frame=NSMakeRect(0,0,880,30);[row layout];midi.directSearchAvailable=YES;row.controls[0].search=YES;
            [ThreeEDJTelemetry shared].decks=@[
                @{@"title":@"Deck A",@"time":@"00:03 / 00:08",@"duration":@8,@"elapsed":@3,@"bpm":@121,@"tempo":@0,@"tempoRange":@"±6"},
                @{@"title":@"Deck B",@"time":@"00:12 / 00:14",@"duration":@14,@"elapsed":@12,@"bpm":@121,@"tempo":@-13.5,@"tempoRange":@"±16"}];
            [ThreeEDJTelemetry shared].updated=NSProcessInfo.processInfo.systemUptime;
            Render(row,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"dj-mixer.png"]);
        }
        [row nextPage];
        if(argc>1) Render(row,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"dj-pads.png"]);
        if(argc>1) { midi.directSearchAvailable=NO;row.controls[0].search=NO;[ThreeEDJTelemetry shared].decks=nil;[ThreeEDJTelemetry shared].updated=0; }
        row.controls[0].search=YES;
        NSCAssert([[row.controls[0] accessibilityValue] hasPrefix:@"SEEK"] && [[row.controls[14] accessibilityValue] hasPrefix:@"BEND"],@"Both wheel modes must expose full unambiguous names");row.controls[0].search=NO;
        // Real AppKit customization persistence, isolated identifiers, restored defaults.
        NSString *domain=NSUUID.UUID.UUIDString;
        NSMutableArray *bars=[NSMutableArray new];
        id previous=[NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
        @try {
            for(NSInteger i=0;i<3;i++) { NSTouchBar *bar=[NSTouchBar new]; bar.customizationIdentifier=[NSString stringWithFormat:@"%@.%ld",domain,(long)i]; bar.defaultItemIdentifiers=@[@"original-control"]; [bars addObject:bar]; }
            DJInstallLayouts(bars);
            NSCAssert(([bars[0] itemIdentifiers].count==1 && [[[bars[0] itemIdentifiers] firstObject] isEqual:@"original-control"]),@"First preset stays unchanged");
            NSCAssert(([[bars[1] itemIdentifiers] isEqual:@[DJMixerID]] && [[bars[2] itemIdentifiers] isEqual:@[@"original-control"]]),@"Only the second preset receives the unified DJ set");
            NSDictionary *backup=[NSUserDefaults.standardUserDefaults dictionaryForKey:DJBackupKey];
            NSCAssert(([backup[[bars[1] customizationIdentifier]] isEqual:@[@"original-control"]]),@"Migration preserves the former layout");
            DJSetLayout(bars[1],@[@"user-edited"]); DJInstallLayouts(bars);
            NSCAssert(([[bars[1] itemIdentifiers] isEqual:@[@"user-edited"]]),@"Relaunch must preserve user edits");
        } @finally {
            if(previous) [NSUserDefaults.standardUserDefaults setObject:previous forKey:DJBackupKey]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
            for(NSTouchBar *bar in bars) [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"NSTouchBarConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"]]];
        }
        NSTouchBar *legacy=[NSTouchBar new];legacy.defaultItemIdentifiers=@[DJPadsID];
        NSTouchBar *custom=[NSTouchBar new];custom.defaultItemIdentifiers=@[DJPadsID,@"custom-control"];
        NSArray *catalog=DJUnifiedCatalog(@[bars[0],legacy,bars[1],custom,bars[2]]);
        NSCAssert(catalog.count==4 && catalog[1]==bars[1] && catalog[2]==custom,@"Retire only the generated pad-only preset; preserve every unrelated or customized bar");
        NSCAssert([DJUnifiedCatalog(catalog) isEqual:catalog],@"Catalog consolidation must be idempotent");
        if(argc>1) [DJMappingGuide() writeToFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"Touch-DJ-Setup.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSArray *fixture=@[
            @{@"role":@"AXStaticText",@"text":@"Actual track",@"help":@""},@{@"role":@"AXImage",@"text":@"",@"help":@""},
            @{@"role":@"AXButton",@"text":@"1",@"help":@"Beat Sync: mode"},
            @{@"role":@"AXStaticText",@"text":@"-02:30",@"help":@""},@{@"role":@"AXStaticText",@"text":@".3",@"help":@""},
            @{@"role":@"AXStaticText",@"text":@"00:12",@"help":@""},@{@"role":@"AXButton",@"text":@"",@"help":@"Sync Master:"},
            @{@"role":@"AXStaticText",@"text":@"Library selection is not loaded",@"help":@""}];
        NSArray *metadata=DJParseDecks(fixture);
        NSCAssert(metadata.count==1 && [metadata[0][@"title"] isEqual:@"Actual track"] && fabs([metadata[0][@"duration"] doubleValue]-162.3)<.01,@"Only anchored deck metadata and real time fields may be displayed");
        // Only the loaded deck image anchor can provide a cover region.
        NSMutableArray *coverFixture=[fixture mutableCopy];NSMutableDictionary *coverNode=[coverFixture[1] mutableCopy];
        coverNode[@"artworkRect"]=@[@100,@200,@40,@40];coverFixture[1]=coverNode;
        NSCAssert([DJParseDecks(coverFixture)[0][@"artworkRect"] isEqual:coverNode[@"artworkRect"]],@"Cover coordinates must follow their exact loaded-deck anchor");
        NSCAssert(NSIsEmptyRect(DJArtworkRect(@[@0,@0,@1000,@1000])) && NSIsEmptyRect(DJArtworkRect(@[@0,@0,@40,@100])) && NSIsEmptyRect(DJArtworkRect(@[@0,@0,@(NAN),@40])),@"Only finite small square cover regions can be captured");
        NSRect source=DJArtworkSourceRect(NSMakeRect(-1800,120,40,40),NSMakeRect(-1920,0,1680,1050),NSMakeRect(-1920,0,1920,1080));
        NSCAssert(NSEqualRects(source,NSMakeRect(120,120,40,40)),@"Artwork crops must retain top-left coordinates on secondary displays");
        NSCAssert(NSIsEmptyRect(DJArtworkSourceRect(NSMakeRect(50,50,40,40),NSMakeRect(500,500,400,400),NSMakeRect(0,0,1920,1080))),@"An unrelated window must never supply artwork pixels");
        ThreeEDJTelemetry *covers=[ThreeEDJTelemetry new];NSImage *cover=[[NSImage alloc] initWithSize:NSMakeSize(96,96)];double coverTime=NSProcessInfo.processInfo.systemUptime;
        [covers updateDecks:metadata at:coverTime];NSString *coverKey=DJArtworkKey(metadata[0]);
        [covers acceptArtwork:@{@0:cover} keys:@[coverKey] generation:0];
        NSCAssert([covers artworkForDeck:0]==cover && ![covers artworkForDeck:1],@"Cover artwork stays isolated by deck and track identity");
        NSDictionary *newTrack=@{@"title":@"Another track",@"duration":@100};[covers updateDecks:@[newTrack] at:coverTime];
        [covers acceptArtwork:@{@0:cover} keys:@[coverKey] generation:0];NSCAssert(![covers artworkForDeck:0] && !covers.artworks.count,@"A late screenshot must never paint the previous track onto a newly loaded disc");
        covers.artworkGeneration=2;[covers acceptArtwork:@{@0:cover} keys:@[DJArtworkKey(newTrack)] generation:1];NSCAssert(!covers.artworks.count,@"Timed-out capture generations cannot overwrite newer artwork");
        [covers acceptArtwork:@{@0:cover} keys:@[DJArtworkKey(newTrack)] generation:2];[covers updateDecks:@[] at:coverTime];NSCAssert(!covers.artworks.count && ![covers artworkForDeck:0],@"Unload must clear cached cover artwork");
        NSArray *vitalPanels=@[
            @{@"text":@"140.00",@"help":@""}, // Original track BPM is not the playing BPM.
            @{@"text":@" 121.00",@"help":@"Deck BPM display:"},@{@"text":@" 0.0",@"help":@""},
            @{@"text":@"",@"help":@"Playing speed display :"},@{@"text":@"%",@"help":@""},@{@"text":@"±6",@"help":@"Tempo Range :"},
            @{@"text":@" 121.00",@"help":@"Deck BPM display:"},@{@"text":@"-13.5",@"help":@""},
            @{@"text":@"Playing speed display :",@"help":@""},@{@"text":@"%",@"help":@""},@{@"text":@"± 16",@"help":@"Tempo Range :"}];
        NSArray *vitals=DJDeckVitals(@[metadata[0],metadata[0]],vitalPanels);
        NSCAssert([vitals[0][@"bpm"] doubleValue]==121 && [vitals[0][@"tempo"] doubleValue]==0 && [vitals[0][@"tempoRange"] isEqual:@"±6"] && [vitals[1][@"tempo"] doubleValue]==-13.5 && [vitals[1][@"tempoRange"] isEqual:@"±16"],@"Each platter must use its real playing BPM, pitch and range, not the original track BPM");
        NSArray *partialPanels=[vitalPanels subarrayWithRange:NSMakeRange(1,5)];
        NSArray *partialVitals=DJDeckVitals(@[metadata[0],metadata[0]],partialPanels);
        NSCAssert(!partialVitals[0][@"bpm"] && !partialVitals[1][@"bpm"],@"An incomplete panel read must not assign one deck's tempo to another");
        NSArray *oneLoaded=DJDeckVitals(@[@{@"duration":@0},metadata[0]],partialPanels);
        NSCAssert(!oneLoaded[0][@"bpm"] && [oneLoaded[1][@"bpm"] doubleValue]==121,@"An unloaded Deck A cannot consume Deck B's tempo panel");
        NSArray *browsePanels=@[
            @{@"text":@"Browse",@"help":@"Change layout:"},
            @{@"text":@"121",@"help":@""},@{@"text":@".00",@"help":@""},@{@"text":@"0.0%",@"help":@""},
            @{@"text":@"121",@"help":@""},@{@"text":@".00",@"help":@""},@{@"text":@"-13.5%",@"help":@""}];
        NSArray *browseVitals=DJDeckVitals(@[metadata[0],metadata[0]],browsePanels);
        NSCAssert([browseVitals[1][@"bpm"] doubleValue]==121 && [browseVitals[1][@"tempo"] doubleValue]==-13.5 && !browseVitals[1][@"tempoRange"],@"Browse may supply its segmented BPM/pitch, but must not invent a hidden tempo range");
        NSArray *unanchored=DJDeckVitals(@[metadata[0],metadata[0]],[browsePanels subarrayWithRange:NSMakeRange(1,6)]);
        NSCAssert(!unanchored[0][@"bpm"] && !unanchored[1][@"bpm"],@"Unrelated numeric text must not become deck tempo");
        NSArray *badVitals=DJDeckVitals(@[metadata[0]],@[@{@"text":@"NaN",@"help":@"Deck BPM display:"}]);
        NSCAssert(!badVitals[0][@"bpm"],@"Non-finite or unavailable host values must remain unavailable");
        ThreeEDJTelemetry *telemetry=[ThreeEDJTelemetry shared];telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime-3;
        NSCAssert(![telemetry deck:0],@"Stale host metadata must disappear");
        NSArray *mixerFixture=@[
            @{@"role":@"AXSlider",@"help":@"EQ/ISO (High) knob:",@"text":@"0",@"min":@-50,@"max":@50},
            @{@"role":@"AXSlider",@"help":@"EQ/ISO (High) knob:",@"text":@"-24",@"min":@-50,@"max":@50},
            @{@"role":@"AXSlider",@"help":@"Channel Fader:",@"text":@"80",@"min":@0,@"max":@100},
            @{@"role":@"AXSlider",@"help":@"CROSSFADER:",@"text":@"-10",@"min":@-50,@"max":@50},
            @{@"role":@"AXSlider",@"help":@"EQ/ISO (Mid) knob:",@"text":@"-14"},
            @{@"role":@"AXSlider",@"help":@"EQ/ISO (Mid) knob:",@"text":@"not available"},
            @{@"role":@"AXSlider",@"help":@"Library selection",@"text":@"90",@"min":@0,@"max":@100}];
        NSDictionary *mixerValues=DJParseMixerValues(mixerFixture);
        NSCAssert(mixerValues.count==5 && [mixerValues[DJKey(0,16,NO)] intValue]==64 && [mixerValues[DJKey(1,16,NO)] intValue]==33 && [mixerValues[DJKey(0,7,NO)] intValue]==102 && [mixerValues[DJKey(0,17,NO)] intValue]==46,@"Only known numeric mixer controls with explicit or verified percentage ranges may supply values");
        [midi.values removeAllObjects];[midi.received removeAllObjects];[midi.rbSentAt removeAllObjects];
        telemetry.controlValues=mixerValues;telemetry.controlsUpdated=NSProcessInfo.processInfo.systemUptime;
        NSUInteger beforeRead=sent.count;[midi syncTelemetry];
        NSCAssert([midi value:1 number:16 note:NO]==33 && sent.count==beforeRead,@"Reading host controls must update the display without echoing MIDI");
        [hi begin:NSMakePoint(21,15) identity:@1];
        telemetry.controlValues=@{DJKey(0,16,NO):@20,DJKey(1,16,NO):@21};telemetry.controlsUpdated=NSProcessInfo.processInfo.systemUptime;[midi syncTelemetry];
        NSCAssert([midi value:0 number:16 note:NO]==64 && [midi value:1 number:16 note:NO]==21,@"An active finger owns its CC while the other deck can still refresh");[hi end];
        [midi send:0xb0 number:16 value:70];[midi syncTelemetry];
        NSCAssert([midi value:0 number:16 note:NO]==70,@"A delayed read cannot pull back a recently sent gesture");
        midi.rbSentAt[DJKey(0,16,NO)]=@(NSProcessInfo.processInfo.systemUptime-1);[midi syncTelemetry];
        NSCAssert([midi value:0 number:16 note:NO]==20,@"Fresh host values may take over after the gesture settles");
        midi.received[DJKey(0,16,NO)]=@(telemetry.controlsUpdated+.1);midi.values[DJKey(0,16,NO)]=@30;[midi syncTelemetry];
        NSCAssert([midi value:0 number:16 note:NO]==30,@"A newer MIDI feedback value must win over an older accessibility sample");
        telemetry.controlsUpdated=NSProcessInfo.processInfo.systemUptime-3;midi.values[DJKey(1,16,NO)]=@32;[midi syncTelemetry];
        NSCAssert([midi value:1 number:16 note:NO]==32,@"Stale host controls cannot overwrite current values");
        DJSelectTarget(YES);telemetry.controlsUpdated=NSProcessInfo.processInfo.systemUptime;midi.values[DJKey(0,16,NO)]=@40;[midi syncTelemetry];
        NSCAssert([midi value:0 number:16 note:NO]==40,@"rekordbox mixer reads must never alter Live controls");DJSelectTarget(NO);
        telemetry.controlValues=nil;telemetry.controlsUpdated=0;[midi.rbSentAt removeAllObjects];
        telemetry.updated=NSProcessInfo.processInfo.systemUptime;telemetry.decks=metadata;midi.directSearchAvailable=YES;
        ThreeEDJControl *seek=Control(DJDisc,0,0);seek.search=YES;[sent removeAllObjects];
        [seek begin:NSMakePoint(50,15) identity:@1];[seek move:NSMakePoint(70,15)];
        NSCAssert(sent.count==1 && [sent[0][0] intValue]==0xb0 && [sent[0][1] intValue]==20,@"Updated S sends a direct needle position, never a held search button");
        NSUInteger seekMessages=sent.count;[seek move:NSMakePoint(70,15)];[seek releaseIdleAt:seek.lastMotion+1];
        NSCAssert(sent.count==seekMessages,@"Stopping the finger must stop direct seeking without acceleration");
        NSMutableDictionary *different=[metadata[0] mutableCopy];different[@"title"]=@"Different track";telemetry.decks=@[different];
        [seek move:NSMakePoint(90,15)];NSCAssert(sent.count==seekMessages,@"A track load during a gesture cannot seek using the previous track's origin");[seek end];
        telemetry.decks=nil;[seek begin:NSMakePoint(50,15) identity:@1];[seek move:NSMakePoint(75,15)];
        NSCAssert(sent.count==seekMessages,@"Direct seeking requires real track/time metadata and never silently falls back to fast scan");[seek end];
        // Tiny movements must survive the controller's conversion, including
        // reversals. A long stationary touch must not reuse touch-down time.
        midi.highResolutionSearchAvailable=YES;
        telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        [seek begin:NSMakePoint(50,15) identity:@1];
        NSMutableDictionary *later=[metadata[0] mutableCopy];later[@"elapsed"]=@20;later[@"playing"]=@NO;
        telemetry.decks=@[later];telemetry.updated=NSProcessInfo.processInfo.systemUptime;[sent removeAllObjects];
        [seek move:NSMakePoint(51,15)];
        NSCAssert(seek.seekOrigin==20 && sent.count==2 && [sent[0][1] intValue]==20 && [sent[1][1] intValue]==52,@"A tiny swipe uses a fresh origin and emits both high-resolution bytes");
        NSInteger fineForward=([sent[0][2] integerValue]<<7)|[sent[1][2] integerValue];
        [seek move:NSMakePoint(51.5,15)];
        NSInteger finerForward=([sent[sent.count-2][2] integerValue]<<7)|[sent.lastObject[2] integerValue];
        NSCAssert(finerForward>fineForward && finerForward-fineForward<8,@"A half-point movement must remain a small proportional seek");
        [seek move:NSMakePoint(50.9,15)];
        NSInteger fineBackward=([sent[sent.count-2][2] integerValue]<<7)|[sent.lastObject[2] integerValue];
        NSCAssert(fineBackward<finerForward,@"Small reverse movement must reverse immediately without a coarse-value dead zone");
        NSUInteger fineCount=sent.count;[seek move:NSMakePoint(50.9,15)];[seek end];
        NSCAssert(sent.count==fineCount,@"Stationary and lift on a paused deck send no extra position or transport");
        NSCAssert(DJSeekValue(0,200,YES)==0 && DJSeekValue(200,200,YES)==16383 && DJSeekValue(100,200,YES)==8192,@"High-resolution limits and midpoint must be exact");
        NSMutableDictionary *shortTrack=[metadata[0] mutableCopy];shortTrack[@"title"]=@"Short cueing track";shortTrack[@"duration"]=@8;shortTrack[@"elapsed"]=@4;shortTrack[@"playing"]=@NO;
        double pagePosition[2];
        for(NSInteger page=0;page<2;page++) {
            row.page=page;[row layout];ThreeEDJControl *wheel=row.controls[0];wheel.search=YES;
            telemetry.decks=@[shortTrack];telemetry.updated=NSProcessInfo.processInfo.systemUptime;
            NSPoint center=wheel.platterCenter;[wheel begin:center identity:@1];[wheel move:NSMakePoint(center.x+10,15)];
            pagePosition[page]=wheel.seekPositionSeconds;
            NSCAssert(pagePosition[page]>4 && pagePosition[page]<=4.15+.00001,@"Ten physical points must make a small cue adjustment, not traverse a short track");[wheel end];
        }
        NSCAssert(fabs(pagePosition[0]-pagePosition[1])<.00001,@"Identical physical travel must seek identically in MIX and PADS");
        shortTrack[@"elapsed"]=@7.99;telemetry.decks=@[shortTrack];telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        ThreeEDJControl *edgeWheel=row.controls[0];NSPoint edgeCenter=edgeWheel.platterCenter;
        [edgeWheel begin:edgeCenter identity:@1];[edgeWheel move:NSMakePoint(edgeCenter.x+300,15)];
        NSCAssert(edgeWheel.seekPositionSeconds==8,@"A long swipe can reach the track end");
        [edgeWheel move:NSMakePoint(edgeCenter.x+299,15)];
        NSCAssert(edgeWheel.seekPositionSeconds<8 && edgeWheel.seekLastValue<16383,@"The first reverse movement after overshooting an end must move back immediately");[edgeWheel end];
        NSCAssert(DJSeekSensitivity(.5,160)*10<.02,@"Very short clips must also reserve physical travel for fine cueing");
        midi.highResolutionSearchAvailable=NO;
        // The same real handlers must seek and hold in MIX and compact PADS.
        for(NSInteger resolution=0;resolution<2;resolution++) for(NSInteger page=0;page<2;page++) for(NSInteger deck=0;deck<2;deck++) {
            midi.highResolutionSearchAvailable=resolution;NSUInteger positionMessages=resolution ? 2 : 1;
            row.page=page;[row layout];ThreeEDJControl *wheel=row.controls[deck*14];wheel.search=YES;
            NSMutableDictionary *playing=[metadata[0] mutableCopy];playing[@"playing"]=@YES;
            telemetry.decks=@[playing,playing];telemetry.updated=NSProcessInfo.processInfo.systemUptime;
            midi.values[DJKey(deck,0,YES)]=@127;
            [sent removeAllObjects];DJTestTouch *touch=[DJTestTouch new];touch.identity=NSUUID.UUID;touch.target=wheel;touch.point=NSMakePoint(16,15);
            DJTestEvent *event=[DJTestEvent new];event.touch=touch;event.phase=NSTouchPhaseBegan;
            [wheel touchesBeganWithEvent:(id)event];
            NSCAssert(wheel.tracking && sent.count==0,@"Resting-marked direct touches must start in both views without interrupting a mode tap");
            touch.target=row.controls[deck*14+6];touch.point=NSMakePoint(96,15);event.phase=NSTouchPhaseMoved;
            [wheel touchesMovedWithEvent:(id)event];DrainTransport();
            NSCAssert(wheel.seekHolding && wheel.seekResume && sent.count==2+positionMessages && [sent[0][1] intValue]==0 && [sent[1][0] intValue]==(0x80|deck) && [sent[2][1] intValue]==20,@"A captured wheel swipe outside its compact bounds pauses once, releases Play, then seeks: messages=%@ holding=%d resume=%d page=%ld deck=%ld",sent,wheel.seekHolding,wheel.seekResume,(long)page,(long)deck);
            NSUInteger held=sent.count;[wheel releaseIdleAt:wheel.lastMotion+4];event.phase=NSTouchPhaseStationary;[wheel touchesMovedWithEvent:(id)event];DrainTransport();
            NSCAssert(sent.count==held && wheel.seekHolding,@"Waiting with a stationary finger must remain held without repeated seeks or transport toggles");
            [row layout];NSCAssert(wheel.tracking && !wheel.hidden,@"A repeated layout must preserve active wheels");
            event.phase=NSTouchPhaseEnded;[wheel touchesEndedWithEvent:(id)event];DrainTransport();
            NSCAssert(!wheel.tracking && !wheel.seekHolding && sent.count==held+2 && [sent.lastObject[1] intValue]==0,@"Lift outside the compact wheel resumes precisely once");
            [wheel end];NSCAssert(sent.count==held+2,@"Duplicate end cannot toggle transport again");
            playing[@"playing"]=@NO;telemetry.decks=@[playing,playing];midi.values[DJKey(deck,0,YES)]=@0;
            [sent removeAllObjects];[wheel begin:NSMakePoint(16,15) identity:@1];[wheel move:NSMakePoint(96,15)];[wheel end];
            NSCAssert(sent.count==positionMessages && [sent[0][1] intValue]==20,@"A deck already paused must remain paused after seeking and lifting");
        }
        midi.highResolutionSearchAvailable=NO;
        // A rapid release must finish the coalesced seek before resuming,
        // with real nonzero transport press intervals on the main run loop.
        NSMutableDictionary *rapidPlaying=[metadata[0] mutableCopy];rapidPlaying[@"playing"]=@YES;
        telemetry.decks=@[rapidPlaying];telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        NSMutableArray *pulseTimes=[NSMutableArray new];[sent removeAllObjects];
        midi.capture=^(UInt8 status,UInt8 number,UInt8 value) { [sent addObject:@[@(status),@(number),@(value)]];[pulseTimes addObject:@(NSProcessInfo.processInfo.systemUptime)]; };
        [seek begin:NSMakePoint(20,15) identity:@1];[seek move:NSMakePoint(60,15)];[seek move:NSMakePoint(100,15)];[seek end];[NSThread sleepForTimeInterval:.08];DrainTransport();
        NSCAssert(sent.count==5 && [sent[0][0] intValue]==0x90 && [sent[1][0] intValue]==0x80 && [sent[2][1] intValue]==20 && [sent[3][0] intValue]==0x90 && [sent[4][0] intValue]==0x80,@"A fast swipe/lift must sequence pause press/release, final coalesced seek, then resume press/release");
        NSCAssert([pulseTimes[1] doubleValue]-[pulseTimes[0] doubleValue]>=.04 && [pulseTimes[4] doubleValue]-[pulseTimes[3] doubleValue]>=.04,@"Both real transport pulses must remain pressed long enough for rekordbox's input polling");
        midi.capture=^(UInt8 status,UInt8 number,UInt8 value) { [sent addObject:@[@(status),@(number),@(value)]]; };
        telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;midi.values[DJKey(0,0,YES)]=@127;
        [sent removeAllObjects];[seek begin:NSMakePoint(20,15) identity:@1];[seek move:NSMakePoint(80,15)];DrainTransport();NSUInteger pausedMessages=sent.count;
        NSMutableDictionary *manualPlay=[metadata[0] mutableCopy];manualPlay[@"playing"]=@YES;telemetry.decks=@[manualPlay];telemetry.updated=seek.seekReadyTime+.7;
        [seek releaseIdleAt:seek.lastMotion+1];[seek end];
        NSCAssert(sent.count==pausedMessages,@"Manual host playback takes ownership back; lift cannot pause it again");
        telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        [sent removeAllObjects];[seek begin:NSMakePoint(20,15) identity:@1];[seek move:NSMakePoint(80,15)];DrainTransport();pausedMessages=sent.count;
        telemetry.decks=@[different];[seek end];NSCAssert(sent.count==pausedMessages,@"A track load must never resume the new track");
        telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        [sent removeAllObjects];[seek begin:NSMakePoint(20,15) identity:@1];[seek move:NSMakePoint(80,15)];DrainTransport();pausedMessages=sent.count;
        DJSelectTarget(YES);DrainTransport();NSCAssert(sent.count==pausedMessages+2 && !seek.seekHolding,@"Target changes restore an owned pause through the old host before switching");DJSelectTarget(NO);
        NSMutableArray *bpmFixture=[fixture mutableCopy];NSMutableDictionary *bpmNode=[fixture[2] mutableCopy];bpmNode[@"help"]=@"BPM Sync: mode";bpmFixture[2]=bpmNode;
        NSCAssert(DJParseDecks(bpmFixture).count==1,@"BPM Sync and Beat Sync must both anchor real deck telemetry");
        double observedTime=NSProcessInfo.processInfo.systemUptime;telemetry.decks=nil;telemetry.updated=0;[telemetry updateDecks:metadata at:observedTime];
        [telemetry updateDecks:metadata at:observedTime+.75];NSCAssert([telemetry.decks[0][@"playing"] isEqual:@NO],@"Consecutive stationary real positions confirm a paused deck without MIDI feedback");
        NSMutableDictionary *advanced=[metadata[0] mutableCopy];advanced[@"elapsed"]=@([advanced[@"elapsed"] doubleValue]+.75);
        [telemetry updateDecks:@[advanced] at:observedTime+1.5];NSCAssert([telemetry.decks[0][@"playing"] isEqual:@YES],@"Natural host position progression confirms playback");
        midi.directSearchAvailable=NO;telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        ThreeEDJControl *animated=Control(DJDisc,0,0);midi.values[DJKey(0,0,YES)]=@127;
        double animationTime=NSProcessInfo.processInfo.systemUptime;[animated animateAt:animationTime];
        for(NSInteger frame=0;frame<60;frame++) {
            double beforeAngle=animated.displayAngle;animationTime+=1.0/60;[animated animateAt:animationTime];
            NSCAssert(animated.displayAngle>beforeAngle && animated.displayAngle-beforeAngle<.1,@"Live playback animation advances each frame instead of jumping with metadata polling");
        }
        midi.values[DJKey(0,0,YES)]=@0;double pauseAngle=animated.displayAngle;animationTime+=1.0/60;[animated animateAt:animationTime];
        NSCAssert(fabs(animated.displayAngle-pauseAngle)<.0001,@"Pausing the host stops automatic platter rotation");
        [animated begin:NSMakePoint(50,15) identity:@1];[animated move:NSMakePoint(70,15)];double targetAngle=animated.angle;
        animationTime+=1.0/60;[animated animateAt:animationTime];
        NSCAssert(animated.displayAngle>pauseAngle && animated.displayAngle<targetAngle,@"Gesture rotation is interpolated rather than snapped");[animated end];
        telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        telemetry.updated=NSProcessInfo.processInfo.systemUptime;
        disc.search=NO;[sent removeAllObjects];
        [disc begin:NSMakePoint(50,15) identity:@1];[disc move:NSMakePoint(60,15)];
        NSCAssert(([sent[0] isEqual:@[@0x90,@2,@127]] && [sent[1] isEqual:@[@0x80,@2,@0]] && [sent[2] isEqual:@[@0x90,@6,@127]]),@"Known enabled Sync must be disabled before bending");[disc end];telemetry.decks=nil;
        ThreeEDJRow *paged=[[ThreeEDJRow alloc] initWithPads:YES];[paged layout];
        [paged.controls[6] begin:NSMakePoint(10,15) identity:@1];[paged nextPage];
        NSCAssert(!paged.controls[6].tracking && [sent.lastObject[0] intValue]==0x80,@"Changing view must release hidden held buttons");
        ThreeEDJControl *running=paged.controls[2];[running begin:NSMakePoint(10,15) identity:@1];[running move:NSMakePoint(18,15)];[paged nextPage];
        NSCAssert(!running.knobTimer && !running.tracking,@"Changing view must cancel held knob rates");
        // Actual CoreMIDI source/destination round trip, with a temporary observer.
        [midi start]; NSCAssert(!midi.error && midi.source && midi.destination,@"Virtual DJ endpoints must open");
        MIDIClientRef observer=0; MIDIPortRef input=0,liveInput=0,output=0;
        NSCAssert(MIDIClientCreate(CFSTR("3£ DJ test"),NULL,NULL,&observer)==noErr,@"Observer client");
        NSCAssert(MIDIInputPortCreate(observer,CFSTR("test input"),Loopback,NULL,&input)==noErr,@"Observer input");
        NSCAssert(MIDIOutputPortCreate(observer,CFSTR("test output"),&output)==noErr,@"Observer output");
        NSCAssert(MIDIPortConnectSource(input,midi.source,NULL)==noErr,@"Connect to actual virtual source");
        NSCAssert(MIDIInputPortCreate(observer,CFSTR("test Live input"),LiveLoopback,NULL,&liveInput)==noErr,@"Live observer input");
        NSCAssert(MIDIPortConnectSource(liveInput,midi.liveSource,NULL)==noErr,@"Connect to isolated Live source");
        midi.capture=nil; [midi send:0x90 number:1 value:127];
        [midi seekPosition:8256 channel:1 highResolution:YES];
        Byte storage[128]; MIDIPacketList *list=(MIDIPacketList *)storage; Byte feedback[]={0xb1,16,101};
        MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,feedback);
        NSCAssert(MIDISend(output,midi.destination,list)==noErr,@"Send feedback through actual virtual destination");
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(([midi value:1 number:16 note:NO]!=101 || !atomic_load(&loopbackPackets) || !atomic_load(&hiResPackets)) && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        NSCAssert(atomic_load(&loopbackPackets)==1 && [midi value:1 number:16 note:NO]==101,@"CoreMIDI round trip must deliver exact messages in both directions: notes=%d feedback=%ld hires=%d",atomic_load(&loopbackPackets),(long)[midi value:1 number:16 note:NO],atomic_load(&hiResPackets));
        NSCAssert(atomic_load(&hiResPackets)==1,@"The real MIDI source must deliver a single ordered MSB/LSB packet on the correct deck");
        [midi send:0x80 number:1 value:0];
        DJSelectTarget(YES); [midi send:0x90 number:1 value:127];
        Byte liveFeedback[]={0xb1,16,55};
        MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,liveFeedback);
        NSCAssert(MIDISend(output,midi.liveDestination,list)==noErr,@"Send feedback through the isolated Live destination");
        NSDate *liveDeadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while((!atomic_load(&liveLoopbackPackets) || [midi value:1 number:16 note:NO]!=55) && liveDeadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        NSCAssert(atomic_load(&liveLoopbackPackets)==1 && atomic_load(&loopbackPackets)==1 && [midi value:1 number:16 note:NO]==55,@"Live output must never reach rekordbox, or vice versa");
        [midi send:0x80 number:1 value:0]; DJSelectTarget(NO);
        NSDate *releaseDeadline=[NSDate dateWithTimeIntervalSinceNow:1];
        while((!atomic_load(&rbReleases) || !atomic_load(&liveReleases)) && releaseDeadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        NSCAssert(atomic_load(&rbReleases)==1 && atomic_load(&liveReleases)==1,@"Actual wire release formats must match each host");
        NSCAssert([midi value:1 number:16 note:NO]==101,@"Live feedback must not overwrite rekordbox state");
        MIDIPortDisconnectSource(liveInput,midi.liveSource);MIDIPortDispose(liveInput);
        if(savedTarget) [NSUserDefaults.standardUserDefaults setObject:savedTarget forKey:DJTargetKey]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:DJTargetKey];
        MIDIPortDisconnectSource(input,midi.source); MIDIPortDispose(input); MIDIPortDispose(output); MIDIClientDispose(observer);
        puts("Passed isolated rekordbox/Live CoreMIDI source/destination round trips and host switching.");
        puts("Passed DJ gesture release/cancel/reverse, MIDI channel isolation, CC limits, fragmented/running-status feedback, no echo, stale state, row geometry and isolated layout migration/persistence.");
    }
}
