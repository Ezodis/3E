// Keep DJ input, feedback and note releases alive in AppKit's private Touch Bar
// tracking modes as well as ordinary app modes. Every queued action runs once.
#import <AppKit/AppKit.h>
static NSHashTable<NSTimer *> *DJTrackingTimers;
static void DJRunOnMain(dispatch_block_t action) {
    if(NSThread.isMainThread){action();return;}
    CFRunLoopRef loop=CFRunLoopGetMain();CFStringRef mode=CFRunLoopCopyCurrentMode(loop);
    __block BOOL delivered=NO;
    dispatch_block_t once=^{if(!delivered){delivered=YES;action();}};
    CFRunLoopPerformBlock(loop,kCFRunLoopCommonModes,once);
    if(mode&&!CFEqual(mode,kCFRunLoopDefaultMode))CFRunLoopPerformBlock(loop,mode,once);
    if(mode)CFRelease(mode);CFRunLoopWakeUp(loop);
}
static void DJTrackCurrentMode(void) {
    NSString *mode=NSRunLoop.mainRunLoop.currentMode;if(!mode.length)return;
    for(NSTimer *timer in DJTrackingTimers)if(timer.valid)[NSRunLoop.mainRunLoop addTimer:timer forMode:mode];
}
static void DJRegisterTimer(NSTimer *timer) {
    if(!DJTrackingTimers)DJTrackingTimers=[NSHashTable weakObjectsHashTable];[DJTrackingTimers addObject:timer];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSEventTrackingRunLoopMode];DJTrackCurrentMode();
}
static void DJAfter(NSTimeInterval delay,dispatch_block_t action) {
    NSTimer *timer=[NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *t){action();}];DJRegisterTimer(timer);
}
