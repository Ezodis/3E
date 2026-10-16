// SPDX-License-Identifier: MIT
// Native menu/QR presentation; networking, gestures and MIDI mapping are shared.
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import <ApplicationServices/ApplicationServices.h>
@interface ThreeEPhoneController : NSObject
@property NSTask *task;
@property NSPipe *input;
@property NSPipe *output;
@property NSMutableData *buffer;
@property NSString *url;
@property NSWindow *window;
@property(copy) void (^media)(int);
@property NSString *controlsJSON;
@property NSString *appsIcon;
- (void)show;
- (void)copyLink:(id)sender;
- (void)stop;
- (void)updateArtwork:(NSImage *)image playing:(NSInteger)playing stop:(BOOL)stop;
@end
@implementation ThreeEPhoneController
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
    NSDictionary *controls=@{@"appsIcon":self.appsIcon,@"media":@{@"artwork":[self iconData:image],@"playing":playing<0 ? NSNull.null : @(playing==1),@"stop":@(stop)}};
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"controls":controls} options:0 error:nil] encoding:NSUTF8StringEncoding];
    if(![json isEqual:self.controlsJSON]){self.controlsJSON=json;[self send:json];}
}
- (void)message:(NSString *)text {
    NSAlert *alert=[NSAlert new];alert.messageText=@"3£ Phone";alert.informativeText=text;[alert runModal];
}
- (void)send:(NSString *)line {
    @try{[self.input.fileHandleForWriting writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];}@catch(NSException *e){[self message:@"The phone receiver stopped. Open it again to reconnect."];}
}
- (void)show {
    if (@available(macOS 14.0,*)) {} else { [self message:@"Phone Bar requires macOS 14 or later. Other 3£ modules remain available."]; return; }
    if(self.task.running){[self send:@"START"];return;}
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
    self.output.fileHandleForReading.readabilityHandler=^(NSFileHandle *handle){
        NSData *data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}
        dispatch_async(dispatch_get_main_queue(),^{
            ThreeEPhoneController *strong=weak;if(!strong)return;[strong.buffer appendData:data];
            const unsigned char *bytes=strong.buffer.bytes;NSUInteger count=strong.buffer.length,start=0;
            for(NSUInteger i=0;i<count;i++)if(bytes[i]=='\n'){
                NSData *line=[strong.buffer subdataWithRange:NSMakeRange(start,i-start)];start=i+1;
                NSDictionary *reply=[NSJSONSerialization JSONObjectWithData:line options:0 error:nil];if(![reply isKindOfClass:NSDictionary.class])continue;
                if([reply[@"media"] isKindOfClass:NSNumber.class]){if(strong.media)strong.media([reply[@"media"] intValue]);continue;}
                if([reply[@"url"] isKindOfClass:NSString.class]){strong.url=reply[@"url"];[strong showQR];}
                else if([reply[@"error"] isKindOfClass:NSString.class])[strong message:reply[@"error"]];
            }
            if(start)[strong.buffer replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
        });
    };
    NSTask *launch=self.task;
    self.task.terminationHandler=^(NSTask *finished){dispatch_async(dispatch_get_main_queue(),^{if(weak.task==finished){weak.task=nil;weak.url=nil;[weak.window close];weak.window=nil;if(finished.terminationStatus!=0)[weak message:@"The phone receiver could not start. This feature requires macOS 14 or later; the rest of 3£ is unaffected."];}});};
    NSError *error=nil;if(![launch launchAndReturnError:&error]){self.task=nil;[self message:error.localizedDescription];}
    else {self.controlsJSON=nil;[self updateArtwork:nil playing:-1 stop:NO];}
}
- (void)showQR {
    [self.window close];self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,250,250) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"3£ Phone Bar";self.window.releasedWhenClosed=NO;self.window.backgroundColor=NSColor.whiteColor;
    CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];[filter setValue:[self.url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];[filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *qr=filter.outputImage;CIContext *context=[CIContext contextWithOptions:nil];CGImageRef pixels=[context createCGImage:qr fromRect:qr.extent];
    NSImageView *view=[[NSImageView alloc] initWithFrame:NSMakeRect(15,15,220,220)];view.image=[[NSImage alloc] initWithCGImage:pixels size:NSMakeSize(220,220)];CGImageRelease(pixels);view.imageScaling=NSImageScaleProportionallyUpOrDown;[self.window.contentView addSubview:view];
    [self.window center];[NSApp activateIgnoringOtherApps:YES];[self.window makeKeyAndOrderFront:nil];
}
- (void)copyLink:(id)sender{if(self.url){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:self.url forType:NSPasteboardTypeString];}}
- (void)stop {
    [self.window close];self.window=nil;self.url=nil;
    NSTask *previous=self.task;self.task=nil;previous.terminationHandler=nil;
    if(previous.running){[self send:@"STOP"];[self.input.fileHandleForWriting closeFile];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC*3),dispatch_get_main_queue(),^{if(previous.running)[previous terminate];});}
    self.output.fileHandleForReading.readabilityHandler=nil;
}
@end
