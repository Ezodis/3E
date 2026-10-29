#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/message.h>
#import <math.h>
#define THREEE_DJ_STANDALONE_TEST 1
#import <stdatomic.h>
#import "../Source/DJSurface.h"
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
        ThreeEDJControl *knob=Control(DJKnob,1,16);
        [knob begin:NSMakePoint(50,15) identity:@1];[knob move:NSMakePoint(50,29)];
        [knob advanceKnobToTime:knob.knobTickTime+.1];
        NSCAssert(sent.count==0,@"Vertical coordinates must never adjust a Touch Bar knob");
        [knob move:NSMakePoint(58,15)];
        for(NSInteger tick=0;tick<25;tick++) [knob advanceKnobToTime:knob.knobTickTime+.1];
        NSCAssert([midi value:1 number:16 note:NO]==127,@"An eight-point horizontal displacement can reach maximum while held");
        [knob move:NSMakePoint(42,15)];
        for(NSInteger tick=0;tick<25;tick++) [knob advanceKnobToTime:knob.knobTickTime+.1];
        NSCAssert([midi value:1 number:16 note:NO]==0,@"Reversing a short horizontal gesture decreases without crossing lanes");
        [knob move:NSMakePoint(50,15)];NSInteger stopped=[midi value:1 number:16 note:NO];
        [knob advanceKnobToTime:knob.knobTickTime+.1];
        NSCAssert(knob.knobRate==0 && [midi value:1 number:16 note:NO]==stopped,@"Return to the original x stops the change");
        [knob end];NSCAssert(!knob.knobTimer,@"Lift must invalidate the rate timer");
        [midi.values removeAllObjects];
        ThreeEDJControl *hi=Control(DJKnob,0,16),*mid=Control(DJKnob,0,17);
        [hi begin:NSMakePoint(20,15) identity:@1];[mid begin:NSMakePoint(60,15) identity:@2];
        [hi move:NSMakePoint(28,15)];[mid move:NSMakePoint(52,15)];
        for(NSInteger tick=0;tick<5;tick++) { [hi advanceKnobToTime:hi.knobTickTime+.1];[mid advanceKnobToTime:mid.knobTickTime+.1]; }
        NSCAssert([midi value:0 number:16 note:NO]>64 && [midi value:0 number:17 note:NO]<64,@"Independent x-only fingers must turn knobs in opposite directions");
        [mid move:NSMakePoint(68,15)];
        for(NSInteger tick=0;tick<5;tick++) [mid advanceKnobToTime:mid.knobTickTime+.1];
        NSCAssert(mid.knobRate>0 && hi.knobRate>0,@"Both fingers can turn in the same direction independently");
        [hi touchesCancelledWithEvent:nil];[mid end];
        NSInteger released=[midi value:0 number:16 note:NO];[hi advanceKnobToTime:hi.knobTickTime+.1];
        NSCAssert(!hi.knobTimer && [midi value:0 number:16 note:NO]==released,@"Cancellation cannot keep changing a knob");
        ThreeEDJControl *timed=Control(DJKnob,1,17);
        NSInteger initial=[midi value:1 number:17 note:NO];[timed begin:NSMakePoint(20,15) identity:@1];[timed move:NSMakePoint(28,15)];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.18]];
        NSCAssert([midi value:1 number:17 note:NO]>initial,@"A horizontal hold must run the actual rate timer");[timed end];
        NSInteger final=[midi value:1 number:17 note:NO];[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        NSCAssert([midi value:1 number:17 note:NO]==final,@"The actual timer must stop sending after lift");
        NSCAssert(DJWireStatus(0x81,NO)==0x91 && DJWireStatus(0x81,YES)==0x81,@"Rekordbox momentary releases use Note On zero; Live uses Note Off");
        [sent removeAllObjects]; disc.search=YES;
        [disc begin:NSMakePoint(50,15) identity:@1];[disc move:NSMakePoint(75,15)];
        NSCAssert(([sent.lastObject isEqual:@[@0x90,@8,@127]]),@"Search uses its own forward control");
        [disc releaseIdleAt:disc.lastMotion+.2];
        NSCAssert(disc.nudge==8,@"Search keeps scanning while held, allowing the host hold threshold to elapse");[disc end];
        NSCAssert(([sent.lastObject isEqual:@[@0x80,@8,@0]]),@"Lifting must release search");
        disc.search=NO;[disc begin:NSMakePoint(50,15) identity:@1];[disc move:NSMakePoint(75,15)];[disc releaseIdleAt:disc.lastMotion+.2];
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
                for(NSInteger deck=0;deck<2;deck++) for(NSInteger i=0;i<4;i++) NSCAssert(!row.controls[deck*14+10+i].hidden==page,@"Only four hot cues per deck appear in Performance");
            }
            row.page=0;[row layout];
            NSPoint a=[row.controls[0] convertPoint:row.controls[0].platterCenter toView:row],b=[row.controls[14] convertPoint:row.controls[14].platterCenter toView:row];
            [row nextPage];
            NSCAssert(NSEqualPoints(a,[row.controls[0] convertPoint:row.controls[0].platterCenter toView:row]) && NSEqualPoints(b,[row.controls[14] convertPoint:row.controls[14].platterCenter toView:row]),@"Platter centers must never move when metadata folds away");
            NSCAssert(fabs(NSMidX(row.controls.lastObject.frame)-width.doubleValue/2)<.1,@"The same hub remains centered");
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
