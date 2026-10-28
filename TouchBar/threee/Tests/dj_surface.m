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
static void Loopback(const MIDIPacketList *packets,void *context,void *unused) {
    const MIDIPacket *p=&packets->packet[0];
    if(packets->numPackets && p->length==3 && p->data[0]==0x90 && p->data[1]==1 && p->data[2]==127) atomic_fetch_add(&loopbackPackets,1);
}
static void LiveLoopback(const MIDIPacketList *packets,void *context,void *unused) {
    const MIDIPacket *p=&packets->packet[0];
    if(packets->numPackets && p->length==3 && p->data[0]==0x90 && p->data[1]==1 && p->data[2]==127) atomic_fetch_add(&liveLoopbackPackets,1);
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
        [knob begin:NSMakePoint(50,15) identity:@1]; [knob move:NSMakePoint(1000,15)]; [knob move:NSMakePoint(-1000,15)]; [knob move:NSMakePoint(50,15)]; [knob end];
        NSCAssert(([sent isEqual:@[@[@0xb1,@16,@127],@[@0xb1,@16,@0],@[@0xb1,@16,@64]]]),@"Swipe clamps both ends and reverses from original value");
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
        for(BOOL pads=NO;;pads=YES) {
            ThreeEDJRow *row=[[ThreeEDJRow alloc] initWithPads:pads];
            for(NSNumber *width in @[@600,@480,@720]) {
                row.frame=NSMakeRect(0,0,width.doubleValue,30); [row layout];
                for(ThreeEDJControl *c in row.controls) NSCAssert(NSMinX(c.frame)>=0 && NSMaxX(c.frame)<=width.doubleValue+.1 && NSWidth(c.frame)>10,@"All controls must fit their row");
            }
            row.frame=NSMakeRect(0,0,600,30); [row layout];
            if(argc>1) Render(row,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:pads ? @"dj-pads.png" : @"dj-mixer.png"]);
            if(pads) break;
        }
        // Real AppKit customization persistence, isolated identifiers, restored defaults.
        NSString *domain=NSUUID.UUID.UUIDString;
        NSMutableArray *bars=[NSMutableArray new];
        id previous=[NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
        @try {
            for(NSInteger i=0;i<3;i++) { NSTouchBar *bar=[NSTouchBar new]; bar.customizationIdentifier=[NSString stringWithFormat:@"%@.%ld",domain,(long)i]; bar.defaultItemIdentifiers=@[@"original-control"]; [bars addObject:bar]; }
            DJInstallLayouts(bars);
            NSCAssert(([bars[0] itemIdentifiers].count==1 && [[[bars[0] itemIdentifiers] firstObject] isEqual:@"original-control"]),@"First preset stays unchanged");
            NSCAssert(([[bars[1] itemIdentifiers] isEqual:@[DJMixerID]] && [[bars[2] itemIdentifiers] isEqual:@[DJPadsID]]),@"Second and third presets must contain actual custom items");
            NSDictionary *backup=[NSUserDefaults.standardUserDefaults dictionaryForKey:DJBackupKey];
            NSCAssert(([backup[[bars[1] customizationIdentifier]] isEqual:@[@"original-control"]]),@"Migration preserves the former layout");
            DJSetLayout(bars[1],@[@"user-edited"]); DJInstallLayouts(bars);
            NSCAssert(([[bars[1] itemIdentifiers] isEqual:@[@"user-edited"]]),@"Relaunch must preserve user edits");
        } @finally {
            if(previous) [NSUserDefaults.standardUserDefaults setObject:previous forKey:DJBackupKey]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:DJBackupKey];
            for(NSTouchBar *bar in bars) [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"NSTouchBarConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"]]];
        }
        if(argc>1) [DJMappingGuide() writeToFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"Touch-DJ-Setup.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
        NSCAssert([midi value:1 number:16 note:NO]==101,@"Live feedback must not overwrite rekordbox state");
        MIDIPortDisconnectSource(liveInput,midi.liveSource);MIDIPortDispose(liveInput);
        if(savedTarget) [NSUserDefaults.standardUserDefaults setObject:savedTarget forKey:DJTargetKey]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:DJTargetKey];
        MIDIPortDisconnectSource(input,midi.source); MIDIPortDispose(input); MIDIPortDispose(output); MIDIClientDispose(observer);
        puts("Passed isolated rekordbox/Live CoreMIDI source/destination round trips and host switching.");
        puts("Passed DJ gesture release/cancel/reverse, MIDI channel isolation, CC limits, fragmented/running-status feedback, no echo, stale state, row geometry and isolated layout migration/persistence.");
    }
}
