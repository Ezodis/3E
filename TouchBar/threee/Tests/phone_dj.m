#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <objc/message.h>
#import <math.h>
#import <stdatomic.h>
#define THREEE_DJ_STANDALONE_TEST 1
#import "../Source/DJSurface.h"
int main(void){@autoreleasepool{
 [NSApplication sharedApplication];NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
 ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];id saved=[NSUserDefaults.standardUserDefaults objectForKey:DJTargetKey];DJSelectTarget(NO);
 NSMutableArray *sent=[NSMutableArray new];midi.capture=^(UInt8 s,UInt8 n,UInt8 v){[sent addObject:@[@(s),@(n),@(v)]];};
 DJPhoneCommand(@{@"op":@"open"});NSCAssert(![DJPhoneSnapshot()[@"paired"] boolValue],@"Unattached phone has both modes without claiming a Touch Bar");
 ThreeEDJRow *row=[[ThreeEDJRow alloc] initWithPads:NO];row.frame=NSMakeRect(0,0,880,30);[row layout];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:row.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.contentView=row;
 NSCAssert([DJPhoneSnapshot()[@"paired"] boolValue],@"Mounted DJ row pairs");NSCAssert([DJPhoneSnapshot()[@"page"] integerValue]==1,@"MIX on Touch Bar gives phone PADS");
 [row nextPage];NSCAssert([DJPhoneSnapshot()[@"page"] integerValue]==0,@"Touch Bar switch changes phone");
 DJPhoneCommand(@{@"op":@"page",@"page":@1});NSCAssert(row.page==0,@"Phone switch changes Touch Bar to complement");
 DJPhoneCommand(@{@"op":@"begin",@"control":@28,@"id":@8});DJPhoneCommand(@{@"op":@"move",@"control":@28,@"id":@8,@"x":@.51});DJPhoneCommand(@{@"op":@"end",@"control":@28,@"id":@8});NSCAssert(row.page==0&&[midi value:15 number:8 note:NO]==65,@"Fine crossfade does not accidentally switch modes");
 midi.values[DJKey(0,7,NO)]=@83;[sent removeAllObjects];DJPhoneCommand(@{@"op":@"begin",@"control":@1,@"id":@9});NSCAssert(sent.count==0,@"Touching level cannot jump to zero");DJPhoneCommand(@{@"op":@"move",@"control":@1,@"id":@9,@"x":@.5});NSCAssert([midi value:0 number:7 note:NO]==64,@"Phone level sets the same MIDI parameter");
 DJPhoneCommand(@{@"op":@"begin",@"control":@2,@"id":@10});DJPhoneCommand(@{@"op":@"begin",@"control":@17,@"id":@11});
 DJPhoneCommand(@{@"op":@"move",@"control":@2,@"id":@10,@"x":@.15});DJPhoneCommand(@{@"op":@"move",@"control":@17,@"id":@11,@"x":@(-.15)});
 ThreeEDJControl *a=DJPhoneRow.controls[2],*b=DJPhoneRow.controls[17];NSCAssert(a.knobRate>0&&b.knobRate<0,@"Independent opposite knob holds");
 double av=a.knobPosition,bv=b.knobPosition;[a advanceKnobToTime:a.knobMotionTime+.7];[b advanceKnobToTime:b.knobMotionTime+.7];NSCAssert(a.knobPosition>av&&b.knobPosition<bv,@"Native phone holds continue turning");
 DJPhoneCommand(@{@"op":@"abort",@"control":@2,@"id":@10});NSCAssert(!a.tracking&&b.tracking,@"Cancelling one finger leaves another active");
 DJPhoneCommand(@{@"op":@"end",@"control":@17,@"id":@999});NSCAssert(b.tracking,@"Stale finger cannot release current touch");
 DJPhoneCommand(@{@"op":@"cancel"});NSCAssert(!b.tracking,@"Disconnect releases all phone fingers");
 [sent removeAllObjects];DJPhoneCommand(@{@"op":@"begin",@"control":@20,@"id":@12});DJPhoneSeen-=4;DJPhoneTick();NSCAssert(!DJPhoneRow.controls[20].tracking&&sent.count==2,@"Lease expiry releases held pads");
 [sent removeAllObjects];[row.controls[2] begin:NSMakePoint(20,15) identity:@"real"];DJPhoneCommand(@{@"op":@"begin",@"control":@2,@"id":@13});NSCAssert(!a.tracking,@"Phone cannot steal a physically held knob");[row.controls[2] end];
 DJPhoneCommand(@{@"op":@"begin",@"control":@0,@"id":@14});DJPhoneCommand(@{@"op":@"abort",@"control":@0,@"id":@14});NSCAssert(!DJPhoneRow.controls[0].search,@"Cancelled disc touch does not switch SEEK/BEND");
 window.contentView=nil;NSCAssert(![DJPhoneSnapshot()[@"paired"] boolValue],@"Removing Touch Bar returns phone to standalone");
 if(saved)[NSUserDefaults.standardUserDefaults setObject:saved forKey:DJTargetKey];else[NSUserDefaults.standardUserDefaults removeObjectForKey:DJTargetKey];
 puts("PASS: complementary views, independent holds, shared MIDI, level continuity, per-finger cancel, conflict ownership and disconnect lease");
}}
