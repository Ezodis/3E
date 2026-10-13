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
    puts("Passed apps hold removal, tap/swipe preservation and independent media hold. No live app actions sent.");
} return 0; }
