// The Dock is read, never rewritten. This panel belongs to MusicStrip and
// does not load Pock or replace the system's brightness/volume controls.
static NSString *const DockCloseID = @"local.musicstrip.dock.close";
static NSString *const DockAppsID = @"local.musicstrip.dock.apps";
static NSString *const DockFoldersID = @"local.musicstrip.dock.folders";

@interface DockLauncher : MusicView
@end
@implementation DockLauncher
- (NSSize)intrinsicContentSize { return NSMakeSize(40,30); }
- (void)updateIcon {
    self.image = [NSImage imageWithSystemSymbolName:@"dock.rectangle" accessibilityDescription:@"Open apps"] ?: [NSImage imageWithSystemSymbolName:@"square.grid.2x2" accessibilityDescription:@"Open apps"];
    self.image.size = NSMakeSize(22,20);
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if (!self.tracking) return;
    BOOL tap=!self.didHold && !self.cancelled && fabs(point.x-self.startX)<12 && NSPointInRect(point,self.bounds);
    self.tracking=NO; self.touchIdentity=nil; [self highlight:NO];
    if(tap && self.performCommand) self.performCommand(2);
}
@end

@interface DockIconButton : NSButton
@property id representedItem;
@property BOOL frontmost;
@property BOOL running;
@end
@implementation DockIconButton
- (NSSize)intrinsicContentSize { return NSMakeSize(44,30); }
- (void)drawRect:(NSRect)rect {
    if(self.highlighted || self.frontmost) {
        [[NSColor colorWithWhite:1 alpha:self.highlighted ? .25 : .12] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,0) xRadius:5 yRadius:5] fill];
    }
    [self.image drawInRect:NSMakeRect((NSWidth(self.bounds)-25)/2,3,25,25) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    if(self.running) { [NSColor.whiteColor setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(self.bounds)-1,28,2,2)] fill]; }
}
@end

static NSArray<NSRunningApplication *> *DockRunningApps(NSArray *running, NSDictionary *dock) {
    NSMutableDictionary *byURL=[NSMutableDictionary dictionary];
    NSMutableArray *remaining=[NSMutableArray array], *ordered=[NSMutableArray array];
    for(NSRunningApplication *app in running) {
        if(app.terminated || app.activationPolicy!=NSApplicationActivationPolicyRegular || !app.bundleURL ||
           [app.bundleIdentifier isEqualToString:@"local.musicstrip.app"] || [app.bundleIdentifier isEqualToString:MidiBundle]) continue;
        byURL[app.bundleURL.URLByStandardizingPath.path]=app;
        [remaining addObject:app];
    }
    for(NSRunningApplication *app in [remaining copy]) if([app.bundleIdentifier isEqualToString:@"com.apple.finder"]) { [ordered addObject:app]; [remaining removeObject:app]; }
    for(NSDictionary *tile in dock[@"persistent-apps"]) {
        NSString *raw=tile[@"tile-data"][@"file-data"][@"_CFURLString"];
        NSRunningApplication *app=raw ? byURL[[NSURL URLWithString:raw].URLByStandardizingPath.path] : nil;
        if(!app) for(NSRunningApplication *candidate in remaining) if([candidate.bundleIdentifier isEqualToString:tile[@"tile-data"][@"bundle-identifier"]]) { app=candidate; break; }
        if(app && [remaining containsObject:app]) { [ordered addObject:app]; [remaining removeObject:app]; }
    }
    [remaining sortUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [(a.launchDate ?: NSDate.distantPast) compare:(b.launchDate ?: NSDate.distantPast)];
    }];
    [ordered addObjectsFromArray:remaining]; return ordered;
}

static NSArray<NSURL *> *DockFolderURLs(NSDictionary *dock) {
    NSMutableArray *result=[NSMutableArray array];
    for(NSDictionary *tile in dock[@"persistent-others"]) {
        if(![tile[@"tile-type"] isEqualToString:@"directory-tile"]) continue;
        NSString *raw=tile[@"tile-data"][@"file-data"][@"_CFURLString"];
        NSURL *url=raw ? [NSURL URLWithString:raw] : nil;
        if(url.isFileURL && ![result containsObject:url]) [result addObject:url];
    }
    return result;
}

@interface DockScrollView : NSScrollView
@property CGFloat reservedWidth;
@property NSLayoutConstraint *panelWidth;
- (void)fitWidth;
@end
@implementation DockScrollView
- (void)fitWidth { CGFloat available=self.window.contentView.bounds.size.width; if(available<=self.reservedWidth+64) return; CGFloat width=available-self.reservedWidth; if(!self.panelWidth) { self.panelWidth=[self.widthAnchor constraintEqualToConstant:width]; self.panelWidth.active=YES; } else if(fabs(self.panelWidth.constant-width)>.5) self.panelWidth.constant=width; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self fitWidth]; }
@end

@interface DockPanel : NSObject
@property NSTouchBar *bar;
@property NSCustomTouchBarItem *appsItem;
@property NSCustomTouchBarItem *foldersItem;
@property DockScrollView *appsScroll;
@property NSArray<DockIconButton *> *appButtons;
@property NSString *signature;
@property NSTimer *timer;
@property BOOL visible;
@property NSURL *browsingFolder;
@property (copy) void (^willShow)(void);
- (void)show;
- (void)close:(id)sender;
- (void)refresh;
- (NSDictionary *)snapshot;
@end

@implementation DockPanel
- (DockIconButton *)buttonFor:(id)item label:(NSString *)label image:(NSImage *)image action:(SEL)action {
    DockIconButton *button=[[DockIconButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
    button.representedItem=item; button.title=@""; button.bordered=NO; button.image=image;
    button.target=self; button.action=action; button.toolTip=label;
    [button setAccessibilityLabel:label]; [button.widthAnchor constraintEqualToConstant:44].active=YES;
    return button;
}
- (DockScrollView *)scrollForButtons:(NSArray *)buttons {
    DockScrollView *scroll=[[DockScrollView alloc] initWithFrame:NSMakeRect(0,0,800,30)];
    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));
    NSUInteger rightCount=DockFolderURLs([NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.apple.dock"] ?: @{}).count+1;
    scroll.reservedWidth=32+32+rightCount*44+(rightCount-1)*8;
    scroll.drawsBackground=NO; scroll.borderType=NSNoBorder;
    scroll.hasHorizontalScroller=YES; scroll.autohidesScrollers=YES;
    scroll.horizontalScrollElasticity=NSScrollElasticityAllowed;
    scroll.verticalScrollElasticity=NSScrollElasticityNone;
    NSView *document=[[NSView alloc] initWithFrame:NSMakeRect(0,0,MAX(1,buttons.count*44),30)];
    for(NSUInteger i=0;i<buttons.count;i++) { NSButton *b=buttons[i]; b.frame=NSMakeRect(i*44,0,44,30); [document addSubview:b]; }
    scroll.documentView=document;
    [scroll.heightAnchor constraintEqualToConstant:30].active=YES;
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [scroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return scroll;
}
- (void)show {
    SEL selector=NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    if(![NSTouchBar respondsToSelector:selector]) { NSLog(@"App panel presentation unavailable"); return; }
    if(self.visible) return;
    if(self.willShow) self.willShow();
    NSCustomTouchBarItem *close=[[NSCustomTouchBarItem alloc] initWithIdentifier:DockCloseID];
    NSButton *x=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close apps"] target:self action:@selector(close:)];
    x.bordered=NO; [x.widthAnchor constraintEqualToConstant:32].active=YES;
    close.view=x; close.visibilityPriority=NSTouchBarItemPriorityHigh;
    self.appsItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:DockAppsID];
    self.foldersItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:DockFoldersID];
    self.foldersItem.visibilityPriority=NSTouchBarItemPriorityHigh;
    self.bar=[NSTouchBar new]; self.bar.templateItems=[NSSet setWithArray:@[close,self.appsItem,self.foldersItem]];
    self.bar.defaultItemIdentifiers=@[DockCloseID,DockAppsID,DockFoldersID];
    self.bar.principalItemIdentifier=DockAppsID;
    self.signature=nil; self.visible=YES; [self refresh];
    // Pock's hideControlStrip setting uses placement 1 as well.
    ((void (*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,selector,self.bar,1,ItemID);
    __weak DockPanel *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){ [weakSelf refresh]; }];
    NSLog(@"Apps panel visible: %lu apps, folders and Trash",(unsigned long)self.appButtons.count);
}
- (void)close:(id)sender {
    if(!self.visible) return;
    SEL selector=NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if([NSTouchBar respondsToSelector:selector]) ((void (*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,selector,self.bar);
    self.visible=NO; [self.timer invalidate]; self.timer=nil;
    self.bar=nil; self.appsItem=nil; self.foldersItem=nil; self.appsScroll=nil; self.appButtons=nil; self.signature=nil; self.browsingFolder=nil;
}
- (void)refresh {
    [self.appsScroll fitWidth];
    if(!self.visible || self.browsingFolder) return;
    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));
    NSDictionary *dock=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.apple.dock"] ?: @{};
    NSArray *apps=DockRunningApps(NSWorkspace.sharedWorkspace.runningApplications,dock);
    NSArray *folders=DockFolderURLs(dock);
    NSMutableArray *keys=[NSMutableArray array];
    for(NSRunningApplication *app in apps) [keys addObject:@(app.processIdentifier).stringValue];
    for(NSURL *url in folders) [keys addObject:url.absoluteString];
    NSString *signature=[keys componentsJoinedByString:@"|"];
    if(![signature isEqualToString:self.signature]) {
        NSPoint offset=self.appsScroll.contentView.bounds.origin;
        self.signature=signature; NSMutableArray *buttons=[NSMutableArray array];
        for(NSRunningApplication *app in apps) {
            DockIconButton *button=[self buttonFor:app label:app.localizedName image:app.icon action:@selector(activateApp:)];
            button.running=YES; [buttons addObject:button];
        }
        self.appButtons=buttons; self.appsScroll=[self scrollForButtons:buttons]; self.appsItem.view=self.appsScroll;
        [self.appsScroll.contentView scrollToPoint:offset];
        NSMutableArray *right=[NSMutableArray array];
        for(NSURL *url in folders) [right addObject:[self buttonFor:url label:url.lastPathComponent image:[NSWorkspace.sharedWorkspace iconForFile:url.path] action:@selector(openFolder:)]];
        NSURL *trash=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"] isDirectory:YES];
        NSImage *trashIcon=[[NSImage alloc] initWithContentsOfFile:@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"];
        [right addObject:[self buttonFor:trash label:@"Trash" image:trashIcon ?: [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:nil] action:@selector(openURL:)]];
        NSStackView *stack=[NSStackView stackViewWithViews:right]; stack.orientation=NSUserInterfaceLayoutOrientationHorizontal; stack.spacing=8;
        // The remote host otherwise expands this stack as much as the app row.
        [stack.widthAnchor constraintEqualToConstant:right.count*44+MAX(0,(NSInteger)right.count-1)*8].active=YES;
        [stack.heightAnchor constraintEqualToConstant:30].active=YES;
        self.foldersItem.view=stack;
    }
    pid_t front=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    for(DockIconButton *button in self.appButtons) { button.frontmost=[(NSRunningApplication *)button.representedItem processIdentifier]==front; button.needsDisplay=YES; }
}
- (void)activateApp:(DockIconButton *)sender {
    NSRunningApplication *app=sender.representedItem;
    if(!app.terminated) [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [self refresh];
}
- (void)openURL:(DockIconButton *)sender { [NSWorkspace.sharedWorkspace openURL:sender.representedItem]; }
- (void)openFolder:(DockIconButton *)sender {
    NSURL *url=sender.representedItem;
    self.browsingFolder=url;
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    files=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){ return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }];
    NSMutableArray *buttons=[NSMutableArray array];
    [buttons addObject:[self buttonFor:nil label:@"Back to running apps" image:[NSImage imageWithSystemSymbolName:@"chevron.backward" accessibilityDescription:nil] action:@selector(backToApps:)]];
    [buttons addObject:[self buttonFor:url label:@"Open folder in Finder" image:[NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil] action:@selector(openURL:)]];
    // Keep large Downloads folders responsive; Finder exposes the complete list.
    for(NSURL *file in [files subarrayWithRange:NSMakeRange(0,MIN(files.count,256))]) {
        NSNumber *directory=nil; [file getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        [buttons addObject:[self buttonFor:file label:file.lastPathComponent image:[NSWorkspace.sharedWorkspace iconForFile:file.path] action:directory.boolValue ? @selector(openFolder:) : @selector(openURL:)]];
    }
    self.appsScroll=[self scrollForButtons:buttons]; self.appsItem.view=self.appsScroll;
}
- (void)backToApps:(id)sender { self.browsingFolder=nil; self.signature=nil; [self refresh]; }
- (NSDictionary *)snapshot {
    NSMutableArray *apps=[NSMutableArray array];
    for(DockIconButton *b in self.appButtons) [apps addObject:[(NSRunningApplication *)b.representedItem bundleIdentifier] ?: @""];
    return @{@"visible":@(self.visible),@"apps":apps,@"layout":self.bar.defaultItemIdentifiers ?: @[],@"width":@(NSWidth(self.appsScroll.bounds)),@"rightWidth":@(NSWidth(self.foldersItem.view.bounds)),@"windowWidth":@(NSWidth(self.appsScroll.window.contentView.bounds))};
}
@end
