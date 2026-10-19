// SPDX-License-Identifier: MIT
// Native menu/QR presentation; networking, gestures and MIDI mapping are shared.
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import <ApplicationServices/ApplicationServices.h>
static NSString *const ThreeEPhoneBarEnabledKey=@"ThreeEPhoneBarEnabled";
@interface ThreeEPhoneController : NSObject
@property NSTask *task;
@property BOOL receiverWanted;
@property BOOL sleeping;
@property NSTimer *retryTimer;
@property NSTimeInterval retryDelay;
@property NSUInteger receiverGeneration;
@property NSPipe *input;
@property NSPipe *output;
@property NSMutableData *buffer;
@property NSString *url;
@property NSWindow *window;
@property BOOL qrRequested;
@property BOOL qrHovering;
@property(copy) void (^media)(int);
@property(copy) void (^systemAction)(NSString *,NSInteger);
@property NSString *controlsJSON;
@property NSString *appsIcon;
- (void)show;
- (void)startReceiver;
- (void)toggleReceiver;
- (void)showQRForHover;
- (void)hideQRForHover;
- (void)copyLink:(id)sender;
- (void)stop;
- (void)updateArtwork:(NSImage *)image playing:(NSInteger)playing stop:(BOOL)stop;
- (void)performSystemAction:(NSString *)action direction:(NSInteger)direction;
@end
@interface ThreeEPhoneQRView : NSView
@property (weak) ThreeEPhoneController *controller;
@end
@implementation ThreeEPhoneController
- (instancetype)init {
    if((self=[super init])) {
        NSNotificationCenter *center=NSWorkspace.sharedWorkspace.notificationCenter;
        [center addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [center addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];[_retryTimer invalidate]; }
- (void)scheduleRecovery {
    if(!self.receiverWanted||self.sleeping||self.retryTimer)return;
    NSTimeInterval delay=self.retryDelay>0?self.retryDelay:1;
    self.retryDelay=MIN(delay*2,30);
    __weak ThreeEPhoneController *weak=self;
    self.retryTimer=[NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer){
        ThreeEPhoneController *strong=weak;strong.retryTimer=nil;
        if(strong.receiverWanted&&!strong.sleeping)[strong startReceiver];
    }];
}
- (void)willSleep:(NSNotification *)note {
    self.sleeping=YES;[self.retryTimer invalidate];self.retryTimer=nil;
    if(self.receiverWanted&&self.task.running)[self send:@"SLEEP"];
}
- (void)didWake:(NSNotification *)note {
    self.sleeping=NO;
    if(!self.receiverWanted)return;
    if(self.task.running)[self send:@"WAKE"];else [self startReceiver];
}
- (void)receiverExited:(NSTask *)finished {
    if(self.task!=finished)return;
    self.output.fileHandleForReading.readabilityHandler=nil;
    self.task=nil;[self.window close];self.window=nil;
    [self scheduleRecovery];
}
- (NSString *)iconData:(NSImage *)image {
    if(!image)return @"";
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:48 pixelsHigh:48 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0,0,48,48) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];[NSGraphicsContext restoreGraphicsState];
    NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png ? [@"data:image/png;base64," stringByAppendingString:[png base64EncodedStringWithOptions:0]] : @"";
}
- (void)updateArtwork:(NSImage *)image playing:(NSInteger)playing stop:(BOOL)stop {
    if(!self.task.running)return;
    if(!self.appsIcon) {
        NSString *path=@"/System/Applications/Apps.app";
        if(![NSFileManager.defaultManager fileExistsAtPath:path])path=@"/System/Applications/Launchpad.app";
        self.appsIcon=[NSFileManager.defaultManager fileExistsAtPath:path] ? [self iconData:[NSWorkspace.sharedWorkspace iconForFile:path]] : @"";
    }
    NSDictionary *controls=@{@"appsIcon":self.appsIcon,@"media":@{@"artwork":[self iconData:image],@"playing":playing<0 ? NSNull.null : (playing==1 ? @YES : @NO),@"stop":@(stop)}};
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"controls":controls} options:0 error:nil] encoding:NSUTF8StringEncoding];
    if(![json isEqual:self.controlsJSON]){self.controlsJSON=json;[self send:json];}
}
- (void)message:(NSString *)text {
    NSAlert *alert=[NSAlert new];alert.messageText=@"3£ Phone";alert.informativeText=text;[alert runModal];
}
- (void)send:(NSString *)line {
    @try{[self.input.fileHandleForWriting writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];}@catch(NSException *e){NSLog(@"3E phone receiver pipe interrupted; recovering");if(self.task.running)[self.task terminate];[self scheduleRecovery];}
}
- (void)show {
    self.qrRequested=YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:ThreeEPhoneBarEnabledKey];
    if (@available(macOS 14.0,*)) {} else { [self message:@"Phone Bar requires macOS 14 or later. Other 3£ modules remain available."]; return; }
    [self startReceiver];
    if(self.url)[self showQR];
}
- (void)startReceiver {
    self.receiverWanted=YES;
    if(self.sleeping)return;
    [self.retryTimer invalidate];self.retryTimer=nil;
    if (@available(macOS 14.0,*)) {} else { return; }
    if(self.task.running)return;
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
#if defined(__arm64__)
    NSString *arch=@"arm64";
#else
    NSString *arch=@"x64";
#endif
    NSString *relative=[NSString stringWithFormat:@"Contents/Resources/PhoneControl/%@/ThreeE.PhoneHost",arch];
    NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:relative];
    if(![NSFileManager.defaultManager isExecutableFileAtPath:path]){[self message:@"This build does not include the phone receiver."];return;}
    self.task=[NSTask new];self.task.executableURL=[NSURL fileURLWithPath:path];self.input=[NSPipe pipe];self.output=[NSPipe pipe];self.buffer=[NSMutableData new];self.task.standardInput=self.input;self.task.standardOutput=self.output;self.task.standardError=[NSFileHandle fileHandleWithNullDevice];
    __weak ThreeEPhoneController *weak=self;
    NSUInteger generation=++self.receiverGeneration;
    self.output.fileHandleForReading.readabilityHandler=^(NSFileHandle *handle){
        NSData *data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}
        dispatch_async(dispatch_get_main_queue(),^{
            ThreeEPhoneController *strong=weak;if(!strong||strong.receiverGeneration!=generation)return;[strong.buffer appendData:data];
            const unsigned char *bytes=strong.buffer.bytes;NSUInteger count=strong.buffer.length,start=0;
            for(NSUInteger i=0;i<count;i++)if(bytes[i]=='\n'){
                NSData *line=[strong.buffer subdataWithRange:NSMakeRange(start,i-start)];start=i+1;
                NSDictionary *reply=[NSJSONSerialization JSONObjectWithData:line options:0 error:nil];if(![reply isKindOfClass:NSDictionary.class])continue;
                if([reply[@"media"] isKindOfClass:NSNumber.class]){if(strong.media)strong.media([reply[@"media"] intValue]);continue;}
                if([reply[@"systemAction"] isKindOfClass:NSString.class]){[strong performSystemAction:reply[@"systemAction"] direction:[reply[@"direction"] integerValue]];continue;}
                if([reply[@"url"] isKindOfClass:NSString.class]){strong.url=reply[@"url"];strong.retryDelay=1;if(strong.qrRequested)[strong showQR];}
                else if([reply[@"error"] isKindOfClass:NSString.class])NSLog(@"3E phone receiver: %@",reply[@"error"]);
            }
            if(start)[strong.buffer replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
        });
    };
    NSTask *launch=self.task;
    self.task.terminationHandler=^(NSTask *finished){dispatch_async(dispatch_get_main_queue(),^{[weak receiverExited:finished];});};
    NSError *error=nil;if(![launch launchAndReturnError:&error]){self.task=nil;NSLog(@"3E phone receiver launch failed: %@",error.localizedDescription);[self scheduleRecovery];}
    else {self.controlsJSON=nil;[self updateArtwork:nil playing:-1 stop:NO];}
}
- (void)performSystemAction:(NSString *)action direction:(NSInteger)direction {
    if(self.systemAction){self.systemAction(action,direction);return;}
    if([action isEqual:@"missionControl"]) {
        NSURL *url=[NSURL fileURLWithPath:@"/System/Applications/Mission Control.app"];
        NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];configuration.activates=YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration completionHandler:nil];
        return;
    }
    if(![action isEqual:@"showDesktop"])return;
    void (^postKey)(CGKeyCode,BOOL,CGEventFlags)=^(CGKeyCode key,BOOL down,CGEventFlags flags){
        CGEventRef event=CGEventCreateKeyboardEvent(NULL,key,down);
        if(event){CGEventSetFlags(event,flags);CGEventPost(kCGSessionEventTap,event);CFRelease(event);}
    };
    CGEventFlags fn=(CGEventFlags)1<<23;
    postKey(63,YES,fn);postKey(103,YES,fn);postKey(103,NO,fn);postKey(63,NO,0);
}
- (void)toggleReceiver {
    // Only the user's own toggle changes the remembered state; quitting does not.
    if(self.receiverWanted){[NSUserDefaults.standardUserDefaults setBool:NO forKey:ThreeEPhoneBarEnabledKey];[self stop];return;}
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:ThreeEPhoneBarEnabledKey];
    if (@available(macOS 14.0,*)) {} else { [self message:@"Phone Bar requires macOS 14 or later. Other 3£ features remain available."]; return; }
    self.qrRequested=self.qrHovering;[self startReceiver];if(self.url&&self.qrRequested)[self showQR];
}
- (void)showQRForHover { self.qrHovering=YES;if(!self.task.running)return;self.qrRequested=YES;if(self.url)[self showQR]; }
- (void)hideQRForHover {
    self.qrHovering=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(!self.qrHovering){self.qrRequested=NO;[self.window orderOut:nil];}
    });
}
- (void)showQR {
    [self.window close];self.window=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,320,320) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];self.window.releasedWhenClosed=NO;self.window.backgroundColor=NSColor.whiteColor;self.window.opaque=YES;self.window.hasShadow=YES;self.window.level=NSPopUpMenuWindowLevel;
    CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];[filter setValue:[self.url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];[filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *qr=filter.outputImage;CGFloat factor=floor(288.0/qr.extent.size.width);CIImage *scaled=[qr imageByApplyingTransform:CGAffineTransformMakeScale(factor,factor)];CIContext *context=[CIContext contextWithOptions:nil];CGImageRef pixels=[context createCGImage:scaled fromRect:scaled.extent];
    ThreeEPhoneQRView *content=[[ThreeEPhoneQRView alloc] initWithFrame:NSMakeRect(0,0,320,320)];content.controller=self;self.window.contentView=content;
    CGFloat size=pixels?CGImageGetWidth(pixels):288;NSImageView *view=[[NSImageView alloc] initWithFrame:NSMakeRect((320-size)/2,(320-size)/2,size,size)];view.image=[[NSImage alloc] initWithCGImage:pixels size:NSMakeSize(size,size)];if(pixels)CGImageRelease(pixels);view.imageScaling=NSImageScaleNone;[content addSubview:view];
    NSPoint point=NSEvent.mouseLocation;NSScreen *screen=NSScreen.mainScreen;NSRect visible=screen.visibleFrame;NSPoint origin=NSMakePoint(MIN(point.x+18,NSMaxX(visible)-320),MAX(NSMinY(visible),MIN(point.y-160,NSMaxY(visible)-320)));[self.window setFrameOrigin:origin];[self.window orderFrontRegardless];
}
- (void)copyLink:(id)sender{if(self.url){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:self.url forType:NSPasteboardTypeString];}}
- (void)stop {
    self.receiverWanted=NO;self.receiverGeneration++;[self.retryTimer invalidate];self.retryTimer=nil;
    self.qrRequested=NO;self.qrHovering=NO;[self.window close];self.window=nil;self.url=nil;
    NSTask *previous=self.task;self.task=nil;previous.terminationHandler=nil;
    if(previous.running){[self send:@"STOP"];[self.input.fileHandleForWriting closeFile];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC*3),dispatch_get_main_queue(),^{if(previous.running)[previous terminate];});}
    self.output.fileHandleForReading.readabilityHandler=nil;
}
@end
@implementation ThreeEPhoneQRView
- (void)updateTrackingAreas {
    [super updateTrackingAreas];for(NSTrackingArea *area in self.trackingAreas)[self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { self.controller.qrHovering=YES; }
- (void)mouseExited:(NSEvent *)event { [self.controller hideQRForHover]; }
@end
