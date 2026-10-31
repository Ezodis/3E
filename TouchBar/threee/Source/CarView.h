// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>
#import <float.h>
#import "CarViewMenu.h"

// Reflection changes only presentation. Native and phone input keep their
// original desktop coordinates. Reflecting the image a second time in glass
// puts both the content and pointer back over the actual click target.
static NSPoint ThreeECarPresentedPoint(NSPoint point,NSRect screen,BOOL mirror) {
    return NSMakePoint(mirror?NSMinX(screen)+NSMaxX(screen)-point.x:point.x,point.y);
}
static double ThreeECarModeScore(size_t width,size_t height,size_t pixels,double hz,
                                size_t originalWidth,size_t originalHeight,double originalHz) {
    if(width<1024 || height<640 || width>=originalWidth || !originalHeight ||
       fabs((double)width/height-(double)originalWidth/originalHeight)>.025 ||
       (hz>0 && hz<50))return DBL_MAX;
    // Prefer a moderate increase in size and Retina output when offered.
    return fabs((double)width/MAX(1024.,originalWidth*.75)-1)*100+
           (pixels>=width*2?0:3)+(hz>0&&originalHz>0?fabs(hz-originalHz)*.01:0);
}
static CGDisplayModeRef ThreeECarLargerMode(CGDirectDisplayID display,CGDisplayModeRef original) CF_RETURNS_RETAINED {
    NSArray *modes=CFBridgingRelease(CGDisplayCopyAllDisplayModes(display,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES}));
    CGDisplayModeRef best=NULL;double score=DBL_MAX;
    for(id object in modes) {
        CGDisplayModeRef mode=(__bridge CGDisplayModeRef)object;
        if(!CGDisplayModeIsUsableForDesktopGUI(mode))continue;
        double candidate=ThreeECarModeScore(CGDisplayModeGetWidth(mode),CGDisplayModeGetHeight(mode),CGDisplayModeGetPixelWidth(mode),CGDisplayModeGetRefreshRate(mode),CGDisplayModeGetWidth(original),CGDisplayModeGetHeight(original),CGDisplayModeGetRefreshRate(original));
        if(candidate<score){score=candidate;best=mode;}
    }
    return best?(CGDisplayModeRef)CFRetain(best):NULL;
}
static CGError ThreeECarApplyMode(CGDirectDisplayID display,CGDisplayModeRef mode) {
    CGDisplayConfigRef config=NULL;CGError result=CGBeginDisplayConfiguration(&config);
    if(result!=kCGErrorSuccess)return result;
    result=CGConfigureDisplayWithDisplayMode(config,display,mode,NULL);
    if(result!=kCGErrorSuccess){CGCancelDisplayConfiguration(config);return result;}
    // WindowServer also restores the session configuration if this process dies.
    return CGCompleteDisplayConfiguration(config,kCGConfigureForAppOnly);
}
static NSScreen *ThreeECarScreen(CGDirectDisplayID display) {
    for(NSScreen *screen in NSScreen.screens)if([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==display)return screen;
    return nil;
}

@interface ThreeECarOverlay : NSPanel
@end

@implementation ThreeECarOverlay
- (BOOL)canBecomeKeyWindow{return NO;}
- (BOOL)canBecomeMainWindow{return NO;}
@end
static ThreeECarOverlay *ThreeECarOverlayWindow(NSRect frame,NSInteger level) {
    ThreeECarOverlay *window=[[ThreeECarOverlay alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;window.opaque=NO;window.backgroundColor=NSColor.clearColor;
    window.hasShadow=NO;window.ignoresMouseEvents=YES;window.level=level;
    window.hidesOnDeactivate=NO;window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorIgnoresCycle;
    return window;
}

@interface ThreeECarPointerView : NSView
@property BOOL mirrored;
@property CGFloat pointerHeight;
@end
@implementation ThreeECarPointerView
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform=[NSAffineTransform transform];
    [transform translateXBy:self.mirrored?self.bounds.size.width-8:8 yBy:8];
    [transform scaleXBy:(self.mirrored?-1:1)*self.pointerHeight/48 yBy:self.pointerHeight/48];[transform concat];
    NSBezierPath *path=[NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(0,0)];[path lineToPoint:NSMakePoint(0,37)];
    [path lineToPoint:NSMakePoint(9,28)];[path lineToPoint:NSMakePoint(18,46)];
    [path lineToPoint:NSMakePoint(25,42)];[path lineToPoint:NSMakePoint(16,25)];
    [path lineToPoint:NSMakePoint(30,25)];[path closePath];path.lineJoinStyle=NSLineJoinStyleRound;
    NSShadow *glow=[NSShadow new];glow.shadowColor=[NSColor colorWithSRGBRed:0 green:1 blue:.76 alpha:.9];glow.shadowBlurRadius=7;[glow set];
    [[NSColor colorWithWhite:.015 alpha:.97] setFill];[path fill];
    [[NSColor colorWithSRGBRed:0 green:1 blue:.76 alpha:1] setStroke];path.lineWidth=3;[path stroke];
    glow.shadowBlurRadius=0;[glow set];[NSColor.whiteColor setStroke];path.lineWidth=.75;[path stroke];
    [NSGraphicsContext restoreGraphicsState];
}
@end

API_AVAILABLE(macos(12.3))
@interface ThreeECarMirror : NSObject <SCStreamOutput,SCStreamDelegate>
@property SCStream *stream;
@property ThreeECarOverlay *window;
@property AVSampleBufferDisplayLayer *video;
@property dispatch_queue_t queue;
@property dispatch_semaphore_t frameGate;
@property BOOL stopped;
@property NSUInteger frames;
@property (copy) void (^ready)(void);
@property (copy) void (^failed)(NSString *);
- (void)startDisplay:(CGDirectDisplayID)display excluding:(NSArray<NSWindow *> *)windows;
- (void)stop;
@end
@implementation ThreeECarMirror
- (void)startDisplay:(CGDirectDisplayID)display excluding:(NSArray<NSWindow *> *)windows {
    NSScreen *screen=ThreeECarScreen(display);if(!screen){self.failed(@"The main display is unavailable.");return;}
    self.queue=dispatch_queue_create("local.musicstrip.carMirror",DISPATCH_QUEUE_SERIAL);
    self.frameGate=dispatch_semaphore_create(1);
    self.window=ThreeECarOverlayWindow(screen.frame,CGWindowLevelForKey(kCGScreenSaverWindowLevelKey));
    self.window.alphaValue=.001;self.window.contentView.wantsLayer=YES;
    self.video=[AVSampleBufferDisplayLayer layer];self.video.frame=self.window.contentView.bounds;
    self.video.autoresizingMask=kCALayerWidthSizable|kCALayerHeightSizable;self.video.videoGravity=AVLayerVideoGravityResize;
    self.video.transform=CATransform3DMakeScale(-1,1,1);[self.window.contentView.layer addSublayer:self.video];
    [self.window orderFrontRegardless];
    NSMutableSet *excludedIDs=[NSMutableSet setWithObject:@(self.window.windowNumber)];
    for(NSWindow *window in windows)[excludedIDs addObject:@(window.windowNumber)];
    __weak ThreeECarMirror *weakSelf=self;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            ThreeECarMirror *self=weakSelf;if(!self||self.stopped)return;
            SCDisplay *source=nil;for(SCDisplay *candidate in content.displays)if(candidate.displayID==display)source=candidate;
            NSMutableArray *excluded=[NSMutableArray new];for(SCWindow *window in content.windows)if([excludedIDs containsObject:@(window.windowID)])[excluded addObject:window];
            if(error||!source||excluded.count!=excludedIDs.count){self.failed(error.localizedDescription?:@"Could not isolate the mirror from the captured desktop.");return;}
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDisplay:source excludingWindows:excluded];
            SCStreamConfiguration *config=[SCStreamConfiguration new];
            CGFloat factor=MIN(2,2560./screen.frame.size.width);
            config.width=(size_t)llround(screen.frame.size.width*factor);config.height=(size_t)llround(screen.frame.size.height*factor);
            config.minimumFrameInterval=CMTimeMake(1,60);config.queueDepth=3;config.showsCursor=NO;
            config.pixelFormat=kCVPixelFormatType_32BGRA;config.scalesToFit=YES;
            // Only screen video is requested. No audio, recording or network sink.
            self.stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            NSError *outputError=nil;
            if(![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self.queue error:&outputError]){self.failed(outputError.localizedDescription);return;}
            [self.stream startCaptureWithCompletionHandler:^(NSError *startError){if(startError)dispatch_async(dispatch_get_main_queue(),^{if(!self.stopped)self.failed(startError.localizedDescription);});}];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{ThreeECarMirror *self=weakSelf;if(self&&!self.stopped&&!self.frames)self.failed(@"No desktop frames arrived. Check Screen Recording access for 3£.");});
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(type!=SCStreamOutputTypeScreen||!CMSampleBufferIsValid(sample)||!CMSampleBufferGetImageBuffer(sample))return;
    NSArray *attachments=CFBridgingRelease(CMSampleBufferGetSampleAttachmentsArray(sample,NO)?CFRetain(CMSampleBufferGetSampleAttachmentsArray(sample,NO)):NULL);
    if(attachments.count&&[attachments[0][SCStreamFrameInfoStatus] integerValue]!=SCFrameStatusComplete)return;
    if(dispatch_semaphore_wait(self.frameGate,DISPATCH_TIME_NOW)!=0)return;
    // Display the freshest frame immediately; SCK's capture timestamps are not
    // the sample display layer's playback clock.
    CFArrayRef sampleAttachments=CMSampleBufferGetSampleAttachmentsArray(sample,YES);
    if(sampleAttachments&&CFArrayGetCount(sampleAttachments))CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(sampleAttachments,0),kCMSampleAttachmentKey_DisplayImmediately,kCFBooleanTrue);
    CFRetain(sample);
    dispatch_async(dispatch_get_main_queue(),^{
        if(!self.stopped) {
            if(self.video.status==AVQueuedSampleBufferRenderingStatusFailed)[self.video flush];
            if(self.video.readyForMoreMediaData){[self.video enqueueSampleBuffer:sample];self.frames++;if(self.frames==1){self.window.alphaValue=1;if(self.ready)self.ready();}}
        }
        CFRelease(sample);
        dispatch_semaphore_signal(self.frameGate);
    });
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {dispatch_async(dispatch_get_main_queue(),^{if(!self.stopped)self.failed(error.localizedDescription);});}
- (void)stop {
    self.stopped=YES;[self.window orderOut:nil];[self.window close];self.window=nil;
    [self.stream stopCaptureWithCompletionHandler:^(NSError *error){}];self.stream=nil;[self.video flushAndRemoveImage];self.video=nil;
}
@end

@interface ThreeECarView : NSObject <NSWindowDelegate>
@property BOOL enabled;
@property BOOL mirrored;
@property BOOL startingMirror;
@property CGDirectDisplayID display;
@property (nonatomic) CGDisplayModeRef originalMode;
@property size_t expectedWidth;
@property size_t expectedHeight;
@property ThreeECarOverlay *pointerWindow;
@property ThreeECarPointerView *pointerView;
@property NSTimer *pointerTimer;
@property BOOL cursorHidden;
@property id mirror;
@property NSString *statusText;
@property EventHotKeyRef exitKey;
@property EventHandlerRef keyHandler;
@property id localKeyMonitor;
@property (copy) void (^changed)(BOOL);
- (void)stop;
- (void)toggle:(id)sender;
- (void)toggleMirror:(id)sender;
@end
static OSStatus ThreeECarExitHotKey(EventHandlerCallRef next,EventRef event,void *context) {
    EventHotKeyID key={0,0};
    if(GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,NULL,sizeof(key),NULL,&key)!=noErr||key.signature!='3ECV'||key.id!=1)return eventNotHandledErr;
    ThreeECarView *car=(__bridge ThreeECarView *)context;
    dispatch_async(dispatch_get_main_queue(),^{[car stop];});return noErr;
}
@implementation ThreeECarView
- (instancetype)init {
    if((self=[super init])) {
        self.statusText=@"Larger controls and a bright neon pointer on your main display.";
        __weak ThreeECarView *weakSelf=self;
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            ThreeECarView *self=weakSelf;if(!self.enabled)return;
            CGDisplayModeRef mode=CGDisplayCopyDisplayMode(self.display);
            BOOL sameDisplay=CGMainDisplayID()==self.display&&mode&&CGDisplayModeGetWidth(mode)==self.expectedWidth&&CGDisplayModeGetHeight(mode)==self.expectedHeight;
            if(mode)CFRelease(mode);
            // Mode-change notifications can arrive several seconds after our
            // transaction. Compare the actual mode rather than a time window.
            if(!sameDisplay){[self stop];self.statusText=@"Display changed. Car View is off.";[self refresh];}
        }];
        for(NSNotificationName name in @[NSWorkspaceScreensDidSleepNotification,NSWorkspaceSessionDidResignActiveNotification])
            [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[weakSelf stop];}];
    }return self;
}
- (void)refresh { if(self.changed)self.changed(self.enabled); }
- (void)toggleCarView:(id)sender { [self toggle:sender]; }
- (void)toggleCarMirror:(id)sender { [self toggleMirror:sender]; }
- (void)toggle:(id)sender {
    if(self.enabled){[self stop];return;}
    [NSApp activateIgnoringOtherApps:YES];
    self.display=CGMainDisplayID();self.originalMode=CGDisplayCopyDisplayMode(self.display);
    if(!self.originalMode){self.statusText=@"The main display is unavailable.";[self refresh];return;}
    CGDisplayModeRef larger=ThreeECarLargerMode(self.display,self.originalMode);
    CGError result=larger?ThreeECarApplyMode(self.display,larger):kCGErrorSuccess;
    if(larger)CFRelease(larger);
    CGDisplayModeRef applied=CGDisplayCopyDisplayMode(self.display);self.expectedWidth=CGDisplayModeGetWidth(applied);self.expectedHeight=CGDisplayModeGetHeight(applied);if(applied)CFRelease(applied);
    self.enabled=YES;
    self.statusText=result!=kCGErrorSuccess?@"Neon pointer is on. macOS could not change the display size.":larger?@"Larger controls and neon pointer are on. Your original size returns when Car View stops.":@"Neon pointer is on. This display is already at its largest supported control size.";
    self.pointerWindow=ThreeECarOverlayWindow(NSMakeRect(0,0,88,88),CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)+1);
    self.pointerView=[[ThreeECarPointerView alloc] initWithFrame:NSMakeRect(0,0,88,88)];self.pointerView.pointerHeight=60;self.pointerWindow.contentView=self.pointerView;
    [self.pointerWindow orderFrontRegardless];
    self.cursorHidden=CGDisplayHideCursor(self.display)==kCGErrorSuccess;
    // Menu actions may arrive from the separate MIDI helper. Apply the owned
    // hide again after activation reaches the host, keeping its count balanced.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self.enabled&&self.cursorHidden){CGDisplayShowCursor(self.display);CGDisplayHideCursor(self.display);}
    });
    __weak ThreeECarView *weakSelf=self;
    self.pointerTimer=[NSTimer timerWithTimeInterval:1./120 repeats:YES block:^(NSTimer *timer){[weakSelf updatePointer];}];
    [NSRunLoop.mainRunLoop addTimer:self.pointerTimer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:self.pointerTimer forMode:NSEventTrackingRunLoopMode];
    EventTypeSpec type={kEventClassKeyboard,kEventHotKeyPressed};
    OSStatus handler=InstallEventHandler(GetEventDispatcherTarget(),ThreeECarExitHotKey,1,&type,(__bridge void *)self,&_keyHandler);
    OSStatus key=handler==noErr?RegisterEventHotKey(kVK_ANSI_0,controlKey|optionKey|cmdKey,(EventHotKeyID){'3ECV',1},GetEventDispatcherTarget(),0,&_exitKey):handler;
    if(key!=noErr)NSLog(@"3£ Car View exit shortcut unavailable: %d",(int)key);
    // Directly delivered app key events don't pass the global hot-key router.
    self.localKeyMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event){
        NSEventModifierFlags flags=NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagCommand;
        if(event.keyCode==kVK_ANSI_0&&(event.modifierFlags&flags)==flags){dispatch_async(dispatch_get_main_queue(),^{[weakSelf stop];});return nil;}return event;
    }];
    [self updatePointer];[self refresh];
}
- (void)updatePointer {
    NSPoint point=NSEvent.mouseLocation;NSScreen *screen=ThreeECarScreen(self.display);
    BOOL mirror=self.mirrored&&screen&&NSPointInRect(point,screen.frame);
    if(mirror)point=ThreeECarPresentedPoint(point,screen.frame,YES);
    if(self.pointerView.mirrored!=mirror){self.pointerView.mirrored=mirror;self.pointerView.needsDisplay=YES;}
    CGFloat tipX=mirror?self.pointerWindow.frame.size.width-8:8;
    [self.pointerWindow setFrameOrigin:NSMakePoint(point.x-tipX,point.y-self.pointerWindow.frame.size.height+8)];
}
- (void)toggleMirror:(id)sender {
    if(self.mirrored||self.startingMirror){[self stopMirror];self.statusText=@"Mirror is off. Car View stays on.";[self refresh];return;}
    if(@available(macOS 12.3,*)) {
        if(!CGPreflightScreenCaptureAccess()) {
            BOOL granted=CGRequestScreenCaptureAccess();
            if(!granted){self.statusText=@"Allow 3£ in System Settings → Privacy & Security → Screen Recording, then try Mirror again.";[self refresh];return;}
        }
        if(!self.enabled)[self toggle:nil];if(!self.enabled)return;
        self.startingMirror=YES;self.statusText=@"Starting the live reflection view…";[self refresh];
        ThreeECarMirror *mirror=[ThreeECarMirror new];self.mirror=mirror;
        __weak ThreeECarView *weakSelf=self;__weak ThreeECarMirror *weakMirror=mirror;
        mirror.ready=^{ThreeECarView *self=weakSelf;if(self.mirror!=weakMirror)return;self.startingMirror=NO;self.mirrored=YES;self.statusText=@"Mirror is on. Look at the reflection; mouse and phone gestures keep their normal direction.";[self updatePointer];[self refresh];};
        mirror.failed=^(NSString *message){ThreeECarView *self=weakSelf;if(self.mirror!=weakMirror)return;[self stopMirror];self.statusText=[@"Mirror stopped: " stringByAppendingString:message?:@"Screen capture unavailable."];[self refresh];};
        [mirror startDisplay:self.display excluding:@[self.pointerWindow]];
    }else{self.statusText=@"Mirror requires macOS 12.3 or newer.";[self refresh];}
}
- (void)stopMirror {
    if(@available(macOS 12.3,*))[(ThreeECarMirror *)self.mirror stop];self.mirror=nil;self.mirrored=NO;self.startingMirror=NO;[self updatePointer];
}
- (void)stop {
    [self stopMirror];[self.pointerTimer invalidate];self.pointerTimer=nil;
    [self.pointerWindow orderOut:nil];[self.pointerWindow close];self.pointerWindow=nil;self.pointerView=nil;
    if(self.cursorHidden){CGDisplayShowCursor(self.display);self.cursorHidden=NO;}
    if(self.exitKey){UnregisterEventHotKey(self.exitKey);self.exitKey=NULL;}if(self.keyHandler){RemoveEventHandler(self.keyHandler);self.keyHandler=NULL;}
    if(self.localKeyMonitor){[NSEvent removeMonitor:self.localKeyMonitor];self.localKeyMonitor=nil;}
    self.enabled=NO;
    CGError restored=kCGErrorSuccess;
    if(self.originalMode){restored=ThreeECarApplyMode(self.display,self.originalMode);CFRelease(self.originalMode);self.originalMode=NULL;}
    self.statusText=restored==kCGErrorSuccess?@"Car View is off. Your original display size is restored.":@"Pointer and mirror are off. Quit 3£ to let macOS restore the display size.";[self refresh];
}
@end

// The native harness starts no MIDI/media modules and posts no input.
static NSDictionary *ThreeECarStatus(ThreeECarView *car) {
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode(CGMainDisplayID());
    NSMutableDictionary *status=[@{@"enabled":@(car.enabled),@"mirrored":@(car.mirrored),@"starting":@(car.startingMirror),@"captureAccess":@(CGPreflightScreenCaptureAccess()),@"width":@(CGDisplayModeGetWidth(mode)),@"height":@(CGDisplayModeGetHeight(mode)),@"pointerHeight":@(car.pointerView.pointerHeight),@"message":car.statusText?:@""} mutableCopy];
    if(@available(macOS 12.3,*))status[@"frames"]=@([(ThreeECarMirror *)car.mirror frames]);
    status[@"exitShortcutRegistered"]=@(car.exitKey!=NULL);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    status[@"nativeCursorVisible"]=@(CGCursorIsVisible());
#pragma clang diagnostic pop
    if(mode)CFRelease(mode);return status;
}
static void ThreeECarPrintStatus(ThreeECarView *car) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:ThreeECarStatus(car) options:0 error:nil];
    puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);fflush(stdout);
}
static int ThreeECarRunHarness(void) {
    [NSApplication sharedApplication];NSApp.activationPolicy=NSApplicationActivationPolicyAccessory;
    ThreeECarView *car=[ThreeECarView new];
    NSStatusItem *status=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];status.button.title=@"3£";
    NSMenu *menu=[NSMenu new];NSMenuItem *row=ThreeECarViewMenu(car,NO);[menu addItem:row];status.menu=menu;
    __weak ThreeECarView *weakCar=car;
    car.changed=^(BOOL enabled){ThreeECarView *car=weakCar;ThreeECarMenuUpdate(row,enabled,car.mirrored,car.startingMirror,car.statusText);};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        char *line=NULL;size_t capacity=0;
        while(getline(&line,&capacity,stdin)>0){NSString *command=[[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(dispatch_get_main_queue(),^{
                if([command isEqual:@"SHOW"]){[NSApp activateIgnoringOtherApps:YES];[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMidX(NSScreen.mainScreen.frame),NSMaxY(NSScreen.mainScreen.frame)-40) inView:nil];}
                else if([command isEqual:@"ENABLE"]&&!car.enabled)[car toggle:nil];
                else if([command isEqual:@"MIRROR"])[car toggleMirror:nil];
                else if([command isEqual:@"STOP"])[car stop];
                else if([command isEqual:@"QUIT"]){[car stop];ThreeECarPrintStatus(car);exit(0);}
                ThreeECarPrintStatus(car);
            });
        }free(line);dispatch_async(dispatch_get_main_queue(),^{[car stop];exit(0);});
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_SEC),dispatch_get_main_queue(),^{[car stop];exit(0);});
    ThreeECarPrintStatus(car);[NSApp run];[car stop];return 0;
}
