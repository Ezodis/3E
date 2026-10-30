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
static void Loopback(const MIDIPacketList *packets,void *context,void *unused) {
    const MIDIPacket *p=&packets->packet[0];
    if(packets->numPackets && p->length==3 && p->data[0]==0x90 && p->data[1]==1) { if(p->data[2]==127) atomic_fetch_add(&loopbackPackets,1);else if(p->data[2]==0) atomic_fetch_add(&rbReleases,1); }
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
                NSInteger edge=page ? 6 : 1;
                NSCAssert(NSMinX(row.controls[edge].frame)==0 && fabs(NSMaxX(row.controls[14+edge].frame)-width.doubleValue)<.1,@"Levels in MIX and transport buttons in PADS must use the full available width");
                if(page) {
                    NSCAssert(NSMaxX(row.controls[9].frame)<NSMinX(row.controls[0].frame) && NSMaxX(row.controls[0].frame)<NSMinX(row.controls[10].frame),@"Deck A disc must sit between Loop and hot cue 1");
                    NSCAssert(NSMaxX(row.controls[24].frame)<NSMinX(row.controls[14].frame) && NSMaxX(row.controls[14].frame)<NSMinX(row.controls[23].frame),@"Deck B mirrors hot cue 1, disc and Loop");
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
        if(argc>1) Render(row,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"dj-mixer.png"]);
        [row nextPage];
        if(argc>1) Render(row,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"dj-pads.png"]);
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
        ThreeEDJTelemetry *telemetry=[ThreeEDJTelemetry shared];telemetry.decks=metadata;telemetry.updated=NSProcessInfo.processInfo.systemUptime-3;
        NSCAssert(![telemetry deck:0],@"Stale host metadata must disappear");
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
        // The same real handlers must seek and hold in MIX and compact PADS.
        for(NSInteger page=0;page<2;page++) for(NSInteger deck=0;deck<2;deck++) {
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
            NSCAssert(wheel.seekHolding && wheel.seekResume && sent.count==3 && [sent[0][1] intValue]==0 && [sent[1][0] intValue]==(0x80|deck) && [sent[2][1] intValue]==20,@"A captured wheel swipe outside its compact bounds pauses once, releases Play, then seeks: messages=%@ holding=%d resume=%d page=%ld deck=%ld",sent,wheel.seekHolding,wheel.seekResume,(long)page,(long)deck);
            NSUInteger held=sent.count;[wheel releaseIdleAt:wheel.lastMotion+4];event.phase=NSTouchPhaseStationary;[wheel touchesMovedWithEvent:(id)event];DrainTransport();
            NSCAssert(sent.count==held && wheel.seekHolding,@"Waiting with a stationary finger must remain held without repeated seeks or transport toggles");
            [row layout];NSCAssert(wheel.tracking && !wheel.hidden,@"A repeated layout must preserve active wheels");
            event.phase=NSTouchPhaseEnded;[wheel touchesEndedWithEvent:(id)event];DrainTransport();
            NSCAssert(!wheel.tracking && !wheel.seekHolding && sent.count==held+2 && [sent.lastObject[1] intValue]==0,@"Lift outside the compact wheel resumes precisely once");
            [wheel end];NSCAssert(sent.count==held+2,@"Duplicate end cannot toggle transport again");
            playing[@"playing"]=@NO;telemetry.decks=@[playing,playing];midi.values[DJKey(deck,0,YES)]=@0;
            [sent removeAllObjects];[wheel begin:NSMakePoint(16,15) identity:@1];[wheel move:NSMakePoint(96,15)];[wheel end];
            NSCAssert(sent.count==1 && [sent[0][1] intValue]==20,@"A deck already paused must remain paused after seeking and lifting");
        }
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
        Byte storage[128]; MIDIPacketList *list=(MIDIPacketList *)storage; Byte feedback[]={0xb1,16,101};
        MIDIPacketListAdd(list,sizeof(storage),MIDIPacketListInit(list),0,3,feedback);
        NSCAssert(MIDISend(output,midi.destination,list)==noErr,@"Send feedback through actual virtual destination");
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(([midi value:1 number:16 note:NO]!=101 || !atomic_load(&loopbackPackets)) && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        NSCAssert(atomic_load(&loopbackPackets)==1 && [midi value:1 number:16 note:NO]==101,@"CoreMIDI round trip must deliver exact messages in both directions");
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
