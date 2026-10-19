// macOS hosts one system-tray view per application process. The internal
// accessory helper owns only the Apps button; the parent owns all panels.
static void AppsReport(NSString *line) {
    NSData *data=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    write(STDOUT_FILENO,data.bytes,data.length);
}
@interface AppsTrayDelegate : NSObject <NSApplicationDelegate>
@property NSCustomTouchBarItem *item;
@property DockPanel *panel;
@property DockLauncher *launcher;
@property NSView *host;
@property NSTimer *recovery;
@end
@implementation AppsTrayDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    if(!LoadInterfaces()) { AppsReport(@"FAILED"); [NSApp terminate:nil]; return; }
    self.launcher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,40,30)];
    self.launcher.translatesAutoresizingMaskIntoConstraints=NO;
    [self.launcher setAccessibilityLabel:@"Apps: tap for running apps; hold for Touch Bar desktops"];
    self.launcher.performCommand=^(int command){ AppsReport(@"OPEN_APPS"); };
    self.launcher.performHold=^{ AppsReport(@"DESKTOP_PICKER"); };
    self.host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,40,30)];
    [self.host addSubview:self.launcher];
    [NSLayoutConstraint activateConstraints:@[
        [self.launcher.widthAnchor constraintEqualToConstant:40],
        [self.launcher.heightAnchor constraintEqualToConstant:30],
        [self.launcher.centerXAnchor constraintEqualToAnchor:self.host.centerXAnchor],
        [self.launcher.centerYAnchor constraintEqualToAnchor:self.host.centerYAnchor]
    ]];
    self.item=[[NSCustomTouchBarItem alloc] initWithIdentifier:AppsTrayID]; self.item.view=self.host; self.item.customizationLabel=@"Apps";
    self.panel=[DockPanel new];
    self.panel.selectSpace=^(uint64_t sid){ AppsReport([NSString stringWithFormat:@"SPACE %llu",(unsigned long long)sid]); };
    self.panel.didClose=^{ AppsReport(@"PANEL_HIDDEN"); };
    // Presentation helper only. The parent is the sole tray provider.
    AppsReport(@"READY");
    __weak AppsTrayDelegate *weakSelf=self;
    NSThread *reader=[[NSThread alloc] initWithBlock:^{
        NSMutableData *buffer=[NSMutableData data];
        for(;;) {
            NSData *data=NSFileHandle.fileHandleWithStandardInput.availableData;
            if(!data.length) break;
            [buffer appendData:data];
            const uint8_t *bytes=buffer.bytes; NSUInteger length=buffer.length,start=0;
            for(NSUInteger i=0;i<length;i++) if(bytes[i]=='\n') {
                NSString *command=[[NSString alloc] initWithBytes:bytes+start length:i-start encoding:NSUTF8StringEncoding];
                dispatch_async(dispatch_get_main_queue(),^{
                    AppsTrayDelegate *self=weakSelf; if(!self) return;
                    if([command isEqualToString:@"TAP"]) { [self.launcher beginAt:NSMakePoint(20,15) identity:nil]; [self.launcher finishAt:NSMakePoint(20,15)]; }
                    else if([command isEqualToString:@"STATUS"]) {
                        NSMutableDictionary *state=[[self.panel snapshot] mutableCopy];
                        state[@"buttonWidth"]=@(NSWidth(self.launcher.frame)); state[@"hostWidth"]=@(NSWidth(self.host.frame)); state[@"pid"]=@(NSProcessInfo.processInfo.processIdentifier); state[@"bundle"]=NSBundle.mainBundle.bundleIdentifier ?: @"";
                        NSData *json=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil]; AppsReport([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
                    } else if([command isEqualToString:@"SHOW"]) { if(self.panel.desktopsMode) [self.panel close:nil]; self.panel.desktopsMode=NO; [self.panel show]; AppsReport(@"PANEL_VISIBLE"); }
                    else if([command isEqualToString:@"DESKTOPS"]) { [self.panel close:nil]; self.panel.desktopsMode=YES; [self.panel show]; AppsReport(@"PANEL_VISIBLE"); }
                    else if([command isEqualToString:@"HIDE"]) { if(self.panel.visible) [self.panel close:nil]; else AppsReport(@"PANEL_HIDDEN"); }
                    else if([command isEqualToString:@"RESTORE"]) [self.panel restorePresentation];
                    else if([command hasPrefix:@"FOLDER "]) { DockIconButton *button=[self.panel buttonFor:[NSURL fileURLWithPath:[command substringFromIndex:7] isDirectory:YES] label:@"Folder" image:nil action:@selector(openFolder:)]; [self.panel openFolder:button]; }
                    else if([command isEqualToString:@"BACK"]) [self.panel.folderBrowser willDismiss:nil];
                    else if([command isEqualToString:@"ROOT"]) [self.panel.folderBrowser willClose:nil];
                    else if([command isEqualToString:@"QUIT"]) [NSApp terminate:nil];
                });
                start=i+1;
            }
            if(start) [buffer replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
        }
        dispatch_async(dispatch_get_main_queue(),^{ [NSApp terminate:nil]; });
    }];
    [reader start];
}
- (void)applicationWillTerminate:(NSNotification *)note {
    [self.panel close:nil];
    [self.recovery invalidate]; [self.launcher.holdTimer invalidate];
}
@end
