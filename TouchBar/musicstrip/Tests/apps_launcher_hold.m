#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DockLauncher *launcher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,18,30)];
    __block NSInteger taps=0, opens=0, closes=0, holds=0;
    launcher.performCommand=^(int command){ if(command==5) opens++; else if(command==4) closes++; else taps++; };
    launcher.performHold=^{ holds++; }; // Even an accidental callback must not run.
    for(NSInteger i=0;i<3;i++) {
        [launcher beginAt:NSMakePoint(7,15) identity:nil];
        [launcher fireHold]; [launcher fireHold];
        [launcher finishAt:NSMakePoint(7,15)];
    }
    NSCAssert(!holds && !taps && !opens && !closes,@"Holding apps has no transition, desktop request or release tap");
    [launcher beginAt:NSMakePoint(7,15) identity:nil]; [launcher finishAt:NSMakePoint(7,15)];
    NSCAssert(taps==1,@"Normal tap remains available");
    for(NSNumber *delta in @[@-15,@15]) {
        [launcher beginAt:NSMakePoint(7,15) identity:nil];
        NSPoint end=NSMakePoint(7+delta.doubleValue,15);
        [launcher moveAt:end]; [launcher fireHold]; [launcher finishAt:end];
    }
    NSCAssert(opens==1 && closes==1 && taps==1 && !holds,@"Both swipe directions remain unchanged");
    MusicView *media=[[MusicView alloc] initWithFrame:NSMakeRect(0,0,52,30)];
    media.performHold=^{ holds++; };
    [media beginAt:NSMakePoint(20,15) identity:nil]; [media fireHold]; [media finishAt:NSMakePoint(20,15)];
    NSCAssert(holds==1,@"Media hold to open MIDI is unaffected");
    LauncherPairView *pair=[[LauncherPairView alloc] initWithFrame:NSMakeRect(0,0,70,30)];
    pair.apps=launcher; pair.music=media; [pair addSubview:launcher]; [pair addSubview:media]; [pair layout];
    NSCAssert(pair.allowedTouchTypes==NSTouchTypeMaskDirect && [pair hitTest:NSMakePoint(7,15)]==pair && [pair hitTest:NSMakePoint(40,15)]==pair,
              @"Registered root accepts direct touches across both button regions");
    __block NSInteger mediaTaps=0;
    media.performCommand=^(int command){ mediaTaps++; };
    [pair beginAt:NSMakePoint(7,15) identity:@1]; [pair finishAt:NSMakePoint(7,15)];
    NSCAssert(taps==2 && !mediaTaps,@"Root forwards app tap to the app button only");
    [pair beginAt:NSMakePoint(7,15) identity:@2]; [pair moveAt:NSMakePoint(35,15)]; [pair finishAt:NSMakePoint(35,15)];
    NSCAssert(closes==2 && !mediaTaps,@"Swipe crossing into media retains its original app target");
    [pair beginAt:NSMakePoint(7,15) identity:@3]; [pair moveAt:NSMakePoint(-12,15)]; [pair finishAt:NSMakePoint(-12,15)];
    NSCAssert(opens==2,@"Left swipe finishing outside the root still opens apps");
    [pair beginAt:NSMakePoint(40,15) identity:@4]; [pair finishAt:NSMakePoint(40,15)];
    NSCAssert(mediaTaps==1 && taps==2,@"Root forwards media taps independently");
    [pair beginAt:NSMakePoint(40,15) identity:@5]; [media fireHold]; [pair finishAt:NSMakePoint(40,15)];
    NSCAssert(holds==2 && mediaTaps==1,@"Root media hold preserves MIDI behavior without a release tap");
    [pair beginAt:NSMakePoint(7,15) identity:@6]; [launcher fireHold]; [pair finishAt:NSMakePoint(7,15)];
    NSCAssert(taps==2 && holds==2,@"Root app hold remains inactive");
    [pair beginAt:NSMakePoint(7,15) identity:@7]; [pair cancelInput]; [pair finishAt:NSMakePoint(7,15)];
    NSCAssert(taps==2 && !pair.inputTarget && !launcher.tracking && !launcher.holdTimer,@"Cancelled input cannot leave a dead tracked button or trigger a tap");
    puts("Passed apps hold removal, tap/swipe preservation and independent media hold. No live app actions sent.");
} return 0; }
