// The Dock is read, never rewritten. This panel belongs to MusicStrip and
// keeps the system's brightness/volume controls.
#import "PockFolderUI.h"
#import <objc/runtime.h>
static NSString *const DockCloseID = @"local.musicstrip.dock.close";
static NSString *const DockAppsID = @"local.musicstrip.dock.apps";
static IMP OriginalAppsModalCloseUpdate;
static void AppsModalCloseUpdate(id overlay,SEL selector) {
    NSTouchBar *bar=[overlay valueForKey:@"_touchBar"];
    if([bar.defaultItemIdentifiers containsObject:DockAppsID]) [overlay setValue:@NO forKey:@"_showsCloseWhenInactive"];
    ((void(*)(id,SEL))OriginalAppsModalCloseUpdate)(overlay,selector);
}
static void ConfigureAppsOverlay(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Method method=class_getInstanceMethod(NSClassFromString(@"NSSystemModalTouchBarOverlay"),NSSelectorFromString(@"_updateCloseButton"));
        if(method) OriginalAppsModalCloseUpdate=method_setImplementation(method,(IMP)AppsModalCloseUpdate);
    });
    if(ConfigureSystemModal) ConfigureSystemModal(NO);
}
static NSString *const DockBalanceID = @"local.musicstrip.dock.balance";
static NSString *const DockFoldersID = @"local.musicstrip.dock.folders";

@interface DockLauncher : MusicView
@property BOOL panelOpen;
@end
@implementation DockLauncher
- (NSSize)intrinsicContentSize { return NSMakeSize(40,30); }
- (void)updateIcon { self.image=nil; }
- (void)drawRect:(NSRect)rect {
    // Flat extension beside the macOS chevron: no independent bezel, glyph,
    // divider or state-dependent X. The system arrow itself remains untouched.
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSIntersectionRect(self.bounds,rect)];
    CGFloat level=self.highlighted ? .28 : .20;
    [[NSColor colorWithWhite:level alpha:1] setFill]; NSRectFill(self.bounds);
    // Feather the native arrow's dark right edge into our flat extension.
    // Only paint inside our view; never overlap or intercept the system arrow.
    CGFloat fade=MIN(8,NSWidth(self.bounds));
    NSGradient *blend=[[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithWhite:.08 alpha:1],0.0,
        [NSColor colorWithWhite:level*.76 alpha:1],0.40,
        [NSColor colorWithWhite:level alpha:1],1.0,nil];
    [blend drawInRect:NSMakeRect(NSMinX(self.bounds),NSMinY(self.bounds),fade,NSHeight(self.bounds)) angle:0];
    [NSGraphicsContext restoreGraphicsState];
}
- (void)moveAt:(NSPoint)point {
    [super moveAt:point];
    if(self.tracking && fabs(point.x-self.startX)>=8) { [self.holdTimer invalidate]; self.holdTimer=nil; }
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if (!self.tracking) return;
    CGFloat dx=point.x-self.startX;
    BOOL swipe=!self.didHold && !self.cancelled && fabs(dx)>=8;
    BOOL tap=!self.didHold && !self.cancelled && !swipe && NSPointInRect(point,self.bounds);
    self.tracking=NO; self.touchIdentity=nil; [self highlight:NO];
    if(self.performCommand && (swipe || tap)) self.performCommand(swipe ? (dx<0 ? 5 : 4) : 2);
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    // The 14-point edge is intentionally narrow. Follow its original finger
    // beyond the view so a swipe does not disappear into the music button.
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:nil])
        if([touch.identity isEqual:self.touchIdentity]) [self moveAt:[touch locationInView:self]];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:nil])
        if([touch.identity isEqual:self.touchIdentity]) [self finishAt:[touch locationInView:self]];
}
- (void)fireHold {
    if(fabs(self.endX-self.startX)>=8) return;
    [super fireHold];
}
@end

// Both launchers share one native registration; the host's intrinsic size
// fits both controls inside the native 70-point tray slot.
@interface LauncherPairView : NSView
@property DockLauncher *apps;
@property MusicView *music;
@end
@implementation LauncherPairView
- (NSSize)intrinsicContentSize { return NSMakeSize(70,30); }
- (void)layout {
    [super layout];
    self.apps.frame=NSMakeRect(0,0,14,30);
    self.music.frame=NSMakeRect(14,0,56,30);
}
@end

@interface DockIconButton : NSButton
@property id representedItem;
@property (nonatomic) BOOL frontmost;
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

@class DockAppEntry;
@interface PockAppIconView : NSScrubberItemView
@property (nonatomic) NSImage *icon;
@property (nonatomic) BOOL frontmost;
@property NSImageView *iconView;
@property NSView *dot;
@property NSRunningApplication *application;
@property DockAppEntry *entry;
@end
@implementation PockAppIconView
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:NSMakeRect(0,0,40,30)])) {
        self.wantsLayer=YES; self.layer.cornerRadius=6;
        self.iconView=[[NSImageView alloc] initWithFrame:NSMakeRect(8,4,24,24)]; self.iconView.imageScaling=NSImageScaleProportionallyDown;
        self.dot=[[NSView alloc] initWithFrame:NSMakeRect(18.5,0,3,3)]; self.dot.wantsLayer=YES; self.dot.layer.cornerRadius=1.5; self.dot.layer.backgroundColor=NSColor.lightGrayColor.CGColor;
        [self addSubview:self.iconView]; [self addSubview:self.dot];
    }
    return self;
}
- (void)setIcon:(NSImage *)icon { _icon=icon; self.iconView.image=icon; }
- (void)setFrontmost:(BOOL)frontmost { _frontmost=frontmost; self.layer.backgroundColor=(frontmost || self.highlighted ? NSColor.darkGrayColor : NSColor.clearColor).CGColor; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.layer.backgroundColor=(highlighted || self.frontmost ? NSColor.darkGrayColor : NSColor.clearColor).CGColor; }
- (void)layout { [super layout]; self.iconView.frame=NSMakeRect((NSWidth(self.bounds)-24)/2,4,24,24); self.dot.frame=NSMakeRect(NSMidX(self.bounds)-1.5,0,3,3); }
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

// Pinned launchers remain present independently of their running processes.
@interface DockAppEntry : NSObject
@property NSString *bundleIdentifier;
@property NSURL *bundleURL;
@property NSString *localizedName;
@property NSImage *icon;
@property NSRunningApplication *application;
@end
@implementation DockAppEntry
@end
static NSArray<DockAppEntry *> *DockAppEntries(NSArray<NSRunningApplication *> *running, NSDictionary *dock) {
    NSArray *pins=@[@{@"id":@"com.apple.finder",@"name":@"Finder",@"path":@"/System/Library/CoreServices/Finder.app"},
                   @{@"id":@"com.apple.apps.launcher",@"name":@"Apps",@"path":@"/System/Applications/Apps.app"},
                   @{@"id":@"com.apple.Safari",@"name":@"Safari",@"path":@"/Applications/Safari.app"}];
    NSMutableDictionary *byID=[NSMutableDictionary new];
    for(NSRunningApplication *app in running) if(app.bundleIdentifier && !app.terminated) byID[app.bundleIdentifier]=app;
    NSMutableArray *entries=[NSMutableArray new]; NSMutableSet *pinned=[NSMutableSet new];
    for(NSDictionary *pin in pins) {
        DockAppEntry *entry=[DockAppEntry new]; entry.bundleIdentifier=pin[@"id"]; entry.localizedName=pin[@"name"];
        entry.application=byID[entry.bundleIdentifier];
        entry.bundleURL=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:entry.bundleIdentifier] ?: [NSURL fileURLWithPath:pin[@"path"]];
        entry.icon=[NSWorkspace.sharedWorkspace iconForFile:entry.bundleURL.path];
        [entries addObject:entry]; [pinned addObject:entry.bundleIdentifier];
    }
    for(NSRunningApplication *app in DockRunningApps(running,dock)) {
        if([pinned containsObject:app.bundleIdentifier]) continue;
        DockAppEntry *entry=[DockAppEntry new]; entry.bundleIdentifier=app.bundleIdentifier; entry.bundleURL=app.bundleURL;
        entry.localizedName=app.localizedName; entry.icon=app.icon; entry.application=app; [entries addObject:entry];
    }
    return entries;
}

#import "AppSwipeSupport.h"

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
- (void)fitWidth {
    CGFloat available=self.window.contentView.bounds.size.width;
    if(available<=self.reservedWidth+64) return;
    CGFloat width=available-self.reservedWidth;
    if(!self.panelWidth) { self.panelWidth=[self.widthAnchor constraintEqualToConstant:width]; self.panelWidth.active=YES; }
    else if(fabs(self.panelWidth.constant-width)>.5) self.panelWidth.constant=width;
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self fitWidth]; }
@end

// Prefer the full application area; macOS supplies the available width beside
// the Control Strip. App count affects the scroll content, never the viewport.
@interface StripAppsScrubber : NSScrubber
@property NSLayoutConstraint *viewportWidth;
@property NSView *centerMarker;
@property NSUInteger layoutGeneration;
@property CGFloat preparedWidth;
@property CGFloat preparedCenter;
- (void)revealWhenReady:(NSUInteger)generation attempts:(NSUInteger)attempts;
- (CGFloat)visualCenterX;
- (void)fitAvailableWidth;
@end
@implementation StripAppsScrubber
- (NSSize)intrinsicContentSize { return NSMakeSize(self.viewportWidth ? self.viewportWidth.constant : 1004,30); }
- (void)fitAvailableWidth {
    CGFloat available=NSWidth(self.window.contentView.bounds);
    if(available<=16) return;
    CGFloat width=available-16; // Native item padding at the two ends.
    BOOL changed=NO;
    if(!self.viewportWidth) {
        self.viewportWidth=[self.widthAnchor constraintEqualToConstant:width];
        self.viewportWidth.priority=999; self.viewportWidth.active=YES; changed=YES;
    } else if(fabs(self.viewportWidth.constant-width)>.5) { self.viewportWidth.constant=width; changed=YES; }
    if(changed) [self invalidateIntrinsicContentSize];
}
- (CGFloat)visualCenterX {
    if(self.centerMarker.superview && NSMinX(self.centerMarker.frame)>0)
        return [self convertPoint:self.centerMarker.frame.origin fromView:self.centerMarker.superview].x;
    return NSMidX(self.bounds);
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.alphaValue=0; self.layoutGeneration++;
    self.preparedWidth=0; self.preparedCenter=0;
    [self.centerMarker removeFromSuperview]; self.centerMarker=nil;
    // Use the native bar's visual-center anchor, which accounts for the
    // Control Strip, rather than centering inside the left app viewport.
    for(NSView *host=self.superview;self.window && host;host=host.superview) {
        SEL selector=NSSelectorFromString(@"visualCenterXAnchor");
        if(![host respondsToSelector:selector]) continue;
        NSLayoutXAxisAnchor *anchor=((id(*)(id,SEL))objc_msgSend)(host,selector);
        NSView *marker=[NSView new]; marker.translatesAutoresizingMaskIntoConstraints=NO; marker.hidden=YES;
        [host addSubview:marker];
        [NSLayoutConstraint activateConstraints:@[
            [marker.leadingAnchor constraintEqualToAnchor:anchor],
            [marker.topAnchor constraintEqualToAnchor:host.topAnchor],
            [marker.widthAnchor constraintEqualToConstant:0],
            [marker.heightAnchor constraintEqualToConstant:0]]];
        self.centerMarker=marker; break;
    }
    [self fitAvailableWidth];
    NSUInteger generation=self.layoutGeneration;
    __weak StripAppsScrubber *weakSelf=self;
    // Let the modal host and tray registration finish their initial sizing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [weakSelf revealWhenReady:generation attempts:0]; });
}
- (void)revealWhenReady:(NSUInteger)generation attempts:(NSUInteger)attempts {
    if(generation!=self.layoutGeneration || !self.window) return;
    [self fitAvailableWidth];
    [self.window.contentView layoutSubtreeIfNeeded];
    [self layoutSubtreeIfNeeded];
    CGFloat width=NSWidth(self.bounds), center=[self visualCenterX];
    BOOL valid=self.centerMarker.superview && NSMinX(self.centerMarker.frame)>0 && fabs(width-self.viewportWidth.constant)<.5;
    BOOL settled=valid && fabs(width-self.preparedWidth)<.5 && fabs(center-self.preparedCenter)<.5;
    self.preparedWidth=width; self.preparedCenter=center;
    if(!settled && attempts<15) {
        __weak StripAppsScrubber *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [weakSelf revealWhenReady:generation attempts:attempts+1]; });
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration=0; context.allowsImplicitAnimation=NO;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        [self.scrubberLayout invalidateLayout]; [self reloadData]; [self layoutSubtreeIfNeeded];
        if([NSProcessInfo.processInfo.arguments containsObject:@"--apps-persistence-smoke-test"]) {
            NSInteger count=[self.dataSource numberOfItemsForScrubber:self];
            NSRect first=[self.scrubberLayout layoutAttributesForItemAtIndex:0].frame, last=[self.scrubberLayout layoutAttributesForItemAtIndex:count-1].frame;
            CGFloat span=MAX(0,count*52-12), target=MIN(MAX(span/2,center),width-span/2);
            NSCAssert(settled,@"Apps must settle before becoming visible");
            if(count && span<=width) NSCAssert(fabs((NSMinX(first)+NSMaxX(last))/2-target)<.5,@"First visible app frame is centered");
            NSLog(@"Apps first visible frame: width=%.1f center=%.1f settled=%d",width,center,settled);
        }
        self.alphaValue=1;
        [CATransaction commit];
    } completionHandler:nil];
}
- (void)dealloc { [self.centerMarker removeFromSuperview]; }
@end

// Keep the icons themselves centered, including when the app count changes.
@interface CenteredAppsLayout : NSScrubberLayout
@end
@implementation CenteredAppsLayout
- (NSSize)scrubberContentSize {
    NSInteger count=[self.scrubber.dataSource numberOfItemsForScrubber:self.scrubber];
    return NSMakeSize(MAX(NSWidth(self.scrubber.bounds),MAX(0,count*52-12)),30);
}
- (NSScrubberLayoutAttributes *)layoutAttributesForItemAtIndex:(NSInteger)index {
    NSInteger count=[self.scrubber.dataSource numberOfItemsForScrubber:self.scrubber];
    if(index<0 || index>=count) return nil;
    CGFloat width=NSWidth(self.scrubber.bounds), content=MAX(0,count*52-12);
    CGFloat center=[self.scrubber isKindOfClass:StripAppsScrubber.class] ? [(StripAppsScrubber *)self.scrubber visualCenterX] : width/2;
    CGFloat origin=content<=width ? MIN(MAX(0,center-content/2),width-content) : 0;
    NSScrubberLayoutAttributes *attribute=[NSScrubberLayoutAttributes layoutAttributesForItemAtIndex:index];
    attribute.frame=NSMakeRect(origin+index*52,0,40,30); attribute.alpha=1; return attribute;
}
- (NSSet *)layoutAttributesForItemsInRect:(NSRect)rect {
    NSMutableSet *attributes=[NSMutableSet set];
    NSInteger count=[self.scrubber.dataSource numberOfItemsForScrubber:self.scrubber];
    for(NSInteger index=0;index<count;index++) { NSScrubberLayoutAttributes *a=[self layoutAttributesForItemAtIndex:index]; if(NSIntersectsRect(a.frame,rect)) [attributes addObject:a]; }
    return attributes;
}
- (BOOL)shouldInvalidateLayoutForChangeFromVisibleRect:(NSRect)oldRect toVisibleRect:(NSRect)newRect { return NSWidth(oldRect)!=NSWidth(newRect); }
@end

@interface DockPanel : NSObject <NSScrubberDataSource,NSScrubberDelegate,NSGestureRecognizerDelegate>
@property NSTouchBar *bar;
@property NSCustomTouchBarItem *appsItem;
@property NSCustomTouchBarItem *foldersItem;
@property DockScrollView *appsScroll;
@property NSScrubber *appsScrubber;
@property NSArray<DockAppEntry *> *runningApps;
@property NSPressGestureRecognizer *appHoldRecognizer;
@property DockSwipeGesture *appSwipeRecognizer;
@property DockAppEntry *swipeSource;
@property DockSwipeChooser *swipeChooser;
@property NSArray<DockSwipeChoice *> *installedChoices;
@property BOOL cycleWindowsReverse;
@property BOOL scanningApps;
@property NSRunningApplication *heldApplication;
@property NSTimeInterval suppressAppSelectionUntil;
@property NSPopoverTouchBarItem *overlay;


@property NSArray<DockIconButton *> *appButtons;
@property NSString *signature;
@property NSTimer *timer;
@property BOOL visible;
@property BOOL desktopsMode;
@property NSArray<NSDictionary *> *spaces;
@property (copy) void (^selectSpace)(uint64_t);
@property NSURL *browsingFolder;
@property PockFolderBrowser *folderBrowser;
@property NSMutableArray<NSURL *> *folderStack;
@property DockIconButton *trashButton;
@property NSRunningApplication *previousFront;

@property (copy) void (^willShow)(void);
@property (copy) void (^didClose)(void);
- (void)show;
- (void)close:(id)sender;
- (void)refresh;
- (NSDictionary *)snapshot;
- (void)restorePresentation;
- (void)holdApp:(NSPressGestureRecognizer *)gesture;
- (void)prepareSwipeApps;
- (void)swipeApp:(DockSwipeGesture *)gesture;
- (void)finishSwipeCancelled:(BOOL)cancelled;
@end

@implementation DockPanel
- (void)restorePresentation {
    if(!self.visible) return;
    ConfigureAppsOverlay();
    ((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"),self.bar,0,ItemID);
    if(SetPresence) SetPresence(ItemID,YES);
}

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
    self.previousFront=NSWorkspace.sharedWorkspace.frontmostApplication;

    self.appsItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:DockAppsID];
    self.appsItem.visibilityPriority=NSTouchBarItemPriorityHigh;
    self.bar=[NSTouchBar new]; self.bar.templateItems=[NSSet setWithObject:self.appsItem];
    self.bar.defaultItemIdentifiers=@[DockAppsID];
    self.bar.principalItemIdentifier=DockAppsID;
    self.signature=nil; self.visible=YES; [self refresh];
    [self restorePresentation];
    __weak DockPanel *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){ [weakSelf refresh]; }];
    NSLog(@"Touch Bar %@ picker visible",self.desktopsMode ? @"desktop" : @"app");
}
- (void)close:(id)sender {
    if(!self.visible) return;
    [self finishSwipeCancelled:YES];
    NSLog(@"Apps picker closing; active=%d front=%@",NSApp.active,NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier);
    ((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,NSSelectorFromString(@"dismissSystemModalTouchBar:"),self.bar);
    self.visible=NO; [self.timer invalidate]; self.timer=nil;
    self.bar=nil; self.appsItem=nil; self.foldersItem=nil; self.appsScroll=nil; self.appButtons=nil; self.signature=nil; self.browsingFolder=nil;
    self.folderBrowser=nil; self.folderStack=nil; self.trashButton=nil; self.appsScrubber=nil; self.runningApps=nil;
    self.previousFront=nil;
    if(self.didClose) self.didClose();
}
- (void)refresh {
    [self.appsScroll fitWidth];
    if([self.appsScrubber isKindOfClass:StripAppsScrubber.class]) [(StripAppsScrubber *)self.appsScrubber fitAvailableWidth];
    if(!self.visible || self.browsingFolder || self.swipeChooser) return;
    CFPreferencesAppSynchronize(CFSTR("com.apple.dock"));
    NSDictionary *dock=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.apple.dock"] ?: @{};
    NSArray *apps=DockAppEntries(NSWorkspace.sharedWorkspace.runningApplications,dock);
    NSArray *folders=@[];
    if(self.desktopsMode) self.spaces=DesktopSpaces();
    NSMutableArray *keys=[NSMutableArray array];
    for(DockAppEntry *app in apps) [keys addObject:[NSString stringWithFormat:@"%@:%d",app.bundleIdentifier,app.application.processIdentifier]];
    for(NSURL *url in folders) [keys addObject:url.absoluteString];
    if(self.desktopsMode) { [keys removeAllObjects]; for(NSDictionary *space in self.spaces) [keys addObject:[NSString stringWithFormat:@"%@:%@",space[@"id"],space[@"active"]]]; }
    NSString *signature=[keys componentsJoinedByString:@"|"];
    if(![signature isEqualToString:self.signature]) {
        NSPoint offset=self.appsScroll.contentView.bounds.origin;
        self.signature=signature; NSMutableArray *buttons=[NSMutableArray array];
        for(DockAppEntry *app in apps) {
            DockIconButton *button=[self buttonFor:app label:app.localizedName image:app.icon action:@selector(activateApp:)];
            button.running=app.application && !app.application.terminated; [buttons addObject:button];
        }
        self.appButtons=buttons; self.runningApps=apps;
        NSScrubber *scrubber=[[StripAppsScrubber alloc] initWithFrame:NSMakeRect(0,0,1004,30)];
        scrubber.alphaValue=0;
        [scrubber setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [scrubber setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        CenteredAppsLayout *layout=[CenteredAppsLayout new];
        scrubber.scrubberLayout=layout; scrubber.mode=NSScrubberModeFree; scrubber.continuous=NO; scrubber.showsAdditionalContentIndicators=YES;
        [scrubber registerClass:PockAppIconView.class forItemIdentifier:@"AppIcon"];
        scrubber.dataSource=self; scrubber.delegate=self; self.appsScrubber=scrubber;
        NSPressGestureRecognizer *hold=[[NSPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdApp:)];
        hold.minimumPressDuration=.65; hold.allowableMovement=8; hold.numberOfTouchesRequired=1;
        hold.allowedTouchTypes=NSTouchTypeMaskDirect; hold.delegate=self;
        [scrubber addGestureRecognizer:hold]; self.appHoldRecognizer=hold;
        DockSwipeGesture *swipe=[[DockSwipeGesture alloc] initWithTarget:nil action:NULL];
        __weak DockPanel *weakPanel=self;
        swipe.onTouchBegin=^(DockSwipeGesture *gesture){ [weakPanel gestureRecognizerShouldBegin:gesture]; };
        swipe.shouldStart=^BOOL(DockSwipeGesture *gesture){
            DockPanel *panel=weakPanel;
            return panel.visible && !panel.desktopsMode && !panel.swipeChooser && panel.swipeSource && panel.appHoldRecognizer.state!=NSGestureRecognizerStateBegan && panel.appHoldRecognizer.state!=NSGestureRecognizerStateChanged;
        };
        swipe.onUpdate=^(DockSwipeGesture *gesture){ [weakPanel swipeApp:gesture]; };
        swipe.allowedTouchTypes=NSTouchTypeMaskDirect; [scrubber addGestureRecognizer:swipe]; self.appSwipeRecognizer=swipe;
        self.appsItem.view=scrubber; [scrubber.heightAnchor constraintEqualToConstant:30].active=YES;
        (void)offset;

    }
    pid_t front=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    for(DockIconButton *button in self.appButtons) { button.frontmost=[(DockAppEntry *)button.representedItem application].processIdentifier==front; button.needsDisplay=YES; }
    [self.appsScrubber reloadData];

}
- (void)activateApp:(DockIconButton *)sender {
    DockAppEntry *app=sender.representedItem;
    [self activateEntry:app];
    [self refresh];
}
- (void)activateEntry:(DockAppEntry *)entry {
    if([entry.bundleIdentifier isEqualToString:@"com.apple.apps.launcher"]) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@"/Applications" isDirectory:YES]];
        return;
    }
    if([entry.bundleIdentifier isEqualToString:@"com.apple.finder"]) {
        // Opening the app sends its standard reopen action, unlike merely
        // activating its process: Finder restores or creates a browser window.
        NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration]; configuration.activates=YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:entry.bundleURL configuration:configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
            if(error) NSLog(@"Could not reopen Finder: %@",error);
        }];
        return;
    }
    if(entry.bundleIdentifier) entry.application=[NSRunningApplication runningApplicationsWithBundleIdentifier:entry.bundleIdentifier].firstObject;
    if(entry.application && !entry.application.terminated) [entry.application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    else if(entry.bundleURL) [NSWorkspace.sharedWorkspace openURL:entry.bundleURL];
}
- (NSInteger)numberOfItemsForScrubber:(NSScrubber *)scrubber { return self.desktopsMode ? self.spaces.count : self.runningApps.count; }
- (NSScrubberItemView *)scrubber:(NSScrubber *)scrubber viewForItemAtIndex:(NSInteger)index {
    PockAppIconView *view=(id)[scrubber makeItemWithIdentifier:@"AppIcon" owner:self];
    if(self.desktopsMode) {
        NSDictionary *space=self.spaces[index];
        view.application=nil; view.entry=nil; view.dot.hidden=YES;
        view.icon=DesktopIcon(space); view.frontmost=[space[@"active"] boolValue];
        [view setAccessibilityLabel:space[@"title"]]; return view;
    }
    DockAppEntry *app=self.runningApps[index]; view.application=app.application; view.entry=app; view.icon=app.icon; view.frontmost=app.application && app.application.processIdentifier==NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    view.dot.hidden=!app.application || app.application.terminated;
    if([app.bundleIdentifier isEqualToString:@"com.apple.apps.launcher"]) {
        view.application=nil; view.dot.hidden=YES; view.frontmost=NO;
        [view setAccessibilityLabel:@"Apps: open Applications in Finder"]; view.needsDisplay=YES; return view;
    }
    [view setAccessibilityLabel:[app.localizedName stringByAppendingString:app.application ? @": tap to switch; hold to quit" : @": tap to open"]]; view.needsDisplay=YES; return view;
}
- (void)prepareSwipeApps {
    if(self.scanningApps) return;
    self.scanningApps=YES; __weak DockPanel *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSArray *choices=InstalledSwipeApps();
        dispatch_async(dispatch_get_main_queue(),^{
            DockPanel *panel=weakSelf; panel.installedChoices=choices; panel.scanningApps=NO;
            if(panel.swipeChooser && !panel.swipeChooser.windowChoices) {
                panel.swipeChooser.choices=choices; panel.swipeChooser.message=@"No applications found";
                [panel.swipeChooser updateAt:panel.appSwipeRecognizer.currentPoint];
            }
        });
    });
}
- (void)swipeApp:(DockSwipeGesture *)gesture {
    if(gesture.trackingPhase==NSGestureRecognizerStateBegan) {
        [self.appHoldRecognizer setEnabled:NO]; [self.appHoldRecognizer setEnabled:YES];
        self.suppressAppSelectionUntil=NSProcessInfo.processInfo.systemUptime+1;
        BOOL windowChoices=![self.swipeSource.bundleIdentifier isEqualToString:@"com.apple.apps.launcher"];
        NSRunningApplication *app=self.swipeSource.application;
        if(windowChoices && (!app || app.terminated) && self.swipeSource.bundleIdentifier.length) {
            app=[NSRunningApplication runningApplicationsWithBundleIdentifier:self.swipeSource.bundleIdentifier].firstObject;
            self.swipeSource.application=app;
        }
        DockSwipeChooser *chooser=[[DockSwipeChooser alloc] initWithFrame:self.appsScrubber.bounds];
        chooser.visualCenter=[(StripAppsScrubber *)self.appsScrubber visualCenterX];
        chooser.windowChoices=windowChoices;
        self.swipeChooser=chooser; [self.appsScrubber addSubview:chooser positioned:NSWindowAbove relativeTo:nil];
        [chooser updateAt:gesture.currentPoint]; [chooser startScrolling];
        if(!chooser.windowChoices) {
            chooser.choices=self.installedChoices ?: @[]; [chooser updateAt:gesture.currentPoint];
            if(!self.installedChoices) [self prepareSwipeApps];
        } else {
            if(!app || app.terminated) { chooser.message=@"No open windows"; chooser.needsDisplay=YES; return; }
            chooser.choices=@[];
            chooser.message=@"Loading windows…";
            [chooser updateAt:gesture.currentPoint];
            __weak DockPanel *weakSelf=self;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                NSArray *windows=SwipeWindows(app);
                dispatch_async(dispatch_get_main_queue(),^{
                    DockPanel *panel=weakSelf;
                    if(!panel || panel.swipeChooser!=chooser || !panel.visible) return;
                    chooser.choices=windows;
                    chooser.message=windows.count ? @"" : @"Loading windows…";
                    [chooser updateAt:gesture.currentPoint];
                    if(!windows.count) {
                        // Keep polling for the duration of the held touch.
                        // The first AX request can legitimately overlap the
                        // Touch Bar gesture transition; one retry is not
                        // enough for the live-finger path.
                        __block NSUInteger attempts=0;
                        __block void (^retry)(void);
                        retry=^{
                            if(panel.swipeChooser!=chooser || !panel.visible || attempts++>=12) return;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                                if(panel.swipeChooser!=chooser || !panel.visible) return;
                                NSArray *next=SwipeWindows(app);
                                chooser.choices=next;
                                chooser.message=next.count ? @"" : @"Loading windows…";
                                [chooser updateAt:gesture.currentPoint];
                                if(!next.count) retry();
                            });
                        };
                        retry();
                    }
                });
            });
        }
    } else if(gesture.trackingPhase==NSGestureRecognizerStateChanged) {
        self.cycleWindowsReverse=gesture.currentPoint.x < gesture.startPoint.x;
        [self.swipeChooser updateAt:gesture.currentPoint];
    }
    else if(gesture.trackingPhase==NSGestureRecognizerStateEnded) { [self.swipeChooser updateAt:gesture.currentPoint]; [self finishSwipeCancelled:NO]; }
    else if(gesture.trackingPhase==NSGestureRecognizerStateCancelled || gesture.trackingPhase==NSGestureRecognizerStateFailed) [self finishSwipeCancelled:YES];
}
- (void)finishSwipeCancelled:(BOOL)cancelled {
    DockSwipeChooser *chooser=self.swipeChooser; if(!chooser) return;
    NSInteger index=chooser.selectedIndex;
    DockSwipeChoice *choice=!cancelled && index>=0 && index<(NSInteger)chooser.choices.count ? chooser.choices[index] : nil;
    NSRunningApplication *windowApp=choice.application ?: self.swipeSource.application;
    [chooser stopScrolling]; [chooser removeFromSuperview]; self.swipeChooser=nil; self.swipeSource=nil;
    self.suppressAppSelectionUntil=NSProcessInfo.processInfo.systemUptime+.25;
    if(choice.entry) [self activateEntry:choice.entry];
    else if(choice.window && choice.application && !choice.application.terminated) {
        [choice.application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            AXUIElementRef window=(__bridge AXUIElementRef)choice.window;
            AXUIElementSetAttributeValue(window,kAXMinimizedAttribute,kCFBooleanFalse);
            AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue);
            AXUIElementPerformAction(window,kAXRaiseAction);
        });
    } else if(choice.windowID && choice.application && !choice.application.terminated) {
        [choice.application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        RaiseWindowServerWindow(choice.windowID);
    } else if(choice.windowIndex && choice.application && !choice.application.terminated) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ RaiseSystemEventsWindow(choice.application,choice.windowIndex); });
    } else if(!cancelled && chooser.windowChoices && windowApp && !windowApp.terminated) {
        CycleApplicationWindow(windowApp,self.cycleWindowsReverse);
    }
    self.cycleWindowsReverse=NO;
}
- (BOOL)gestureRecognizerShouldBegin:(NSGestureRecognizer *)gesture {
    if(self.desktopsMode || self.swipeChooser) return NO;
    if(gesture==self.appSwipeRecognizer) {
        if(self.appHoldRecognizer.state==NSGestureRecognizerStateBegan || self.appHoldRecognizer.state==NSGestureRecognizerStateChanged) return NO;
        NSPoint start=self.appSwipeRecognizer.startPoint; self.swipeSource=nil;
        for(NSInteger index=0;index<(NSInteger)self.runningApps.count;index++) {
            PockAppIconView *view=(id)[self.appsScrubber itemViewForItemAtIndex:index];
            if(view && NSPointInRect([view convertPoint:start fromView:self.appsScrubber],view.bounds)) { self.swipeSource=view.entry; break; }
        }
        return self.swipeSource!=nil;
    }
    if(gesture!=self.appHoldRecognizer) return NO;
    self.heldApplication=nil;
    NSPoint point=[gesture locationInView:self.appsScrubber];
    for(NSInteger index=0;index<(NSInteger)self.runningApps.count;index++) {
        PockAppIconView *view=(id)[self.appsScrubber itemViewForItemAtIndex:index];
        if(view && NSPointInRect([view convertPoint:point fromView:self.appsScrubber],view.bounds)) { self.heldApplication=view.application; break; }
    }
    return self.heldApplication && !self.heldApplication.terminated;
}
- (void)holdApp:(NSPressGestureRecognizer *)gesture {
    if(gesture.state==NSGestureRecognizerStateBegan) {
        self.suppressAppSelectionUntil=NSProcessInfo.processInfo.systemUptime+1;
        NSRunningApplication *app=self.heldApplication;
        self.heldApplication=nil; // Exactly one normal Quit request per hold.
        if(app && !app.terminated) [app terminate];
    } else if(gesture.state==NSGestureRecognizerStateEnded || gesture.state==NSGestureRecognizerStateCancelled) {
        self.heldApplication=nil;
        self.suppressAppSelectionUntil=NSProcessInfo.processInfo.systemUptime+.15;
    }
}
- (void)scrubber:(NSScrubber *)scrubber didSelectItemAtIndex:(NSInteger)index {
    if(!self.desktopsMode && (self.swipeChooser || NSProcessInfo.processInfo.systemUptime<self.suppressAppSelectionUntil || self.appHoldRecognizer.state==NSGestureRecognizerStateBegan || self.appHoldRecognizer.state==NSGestureRecognizerStateChanged)) {
        scrubber.selectedIndex=-1; return;
    }
    if(self.desktopsMode) {
        if(index>=0 && index<(NSInteger)self.spaces.count && self.selectSpace) self.selectSpace([self.spaces[index][@"id"] unsignedLongLongValue]);
        scrubber.selectedIndex=-1; return;
    }
    if(index>=0 && index<(NSInteger)self.runningApps.count) [self activateEntry:self.runningApps[index]];
    scrubber.selectedIndex=-1;
}
- (void)openURL:(DockIconButton *)sender { [NSWorkspace.sharedWorkspace openURL:sender.representedItem]; }
- (void)openFolder:(DockIconButton *)sender {
    if(!self.folderStack) self.folderStack=[NSMutableArray array];
    [self.folderStack addObject:sender.representedItem]; [self presentFolder];
}
- (void)presentFolder {
    NSURL *url=self.folderStack.lastObject; if(!url) return;
    PockFolderBrowser *browser=[PockFolderBrowser new];
    if(![browser loadFolder:url nested:self.folderStack.count>1]) return;
    __weak DockPanel *weakSelf=self;
    browser.onClose=^{ [weakSelf backToApps:nil]; };
    browser.onBack=^{ [weakSelf.folderStack removeLastObject]; [weakSelf presentFolder]; };
    browser.onNavigate=^(NSURL *nested){ [weakSelf.folderStack addObject:nested]; [weakSelf presentFolder]; };
    SEL dismiss=NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if(self.overlay) [self.overlay dismissPopover:nil];
    else ((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,dismiss,self.folderBrowser.touchBar ?: self.bar);
    self.browsingFolder=url; self.folderBrowser=browser;

    if(ConfigureSystemModal) ConfigureSystemModal(NO);
    if(self.overlay) { self.overlay.popoverTouchBar=browser.touchBar; [self.overlay showPopover:nil]; }
    else ((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"),browser.touchBar,0,ItemID);
}
- (void)backToApps:(id)sender {
    if(self.folderBrowser) { if(self.overlay) [self.overlay dismissPopover:nil]; else ((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,NSSelectorFromString(@"dismissSystemModalTouchBar:"),self.folderBrowser.touchBar); }
    self.folderBrowser=nil; self.folderStack=nil; self.browsingFolder=nil; self.signature=nil; [self refresh];
    if(ConfigureSystemModal) ConfigureSystemModal(NO);
    [self restorePresentation];
}
- (NSDictionary *)snapshot {
    NSMutableArray *apps=[NSMutableArray array];
    for(DockIconButton *b in self.appButtons) [apps addObject:[(DockAppEntry *)b.representedItem bundleIdentifier] ?: @""];
    NSInteger count=[self numberOfItemsForScrubber:self.appsScrubber];
    NSScrubberLayout *layout=self.appsScrubber.scrubberLayout;
    NSRect first=[layout layoutAttributesForItemAtIndex:0].frame,last=[layout layoutAttributesForItemAtIndex:count-1].frame;
    CGFloat width=NSWidth(self.appsScrubber.bounds), content=MAX(0,count*52-12);
    CGFloat target=[self.appsScrubber isKindOfClass:StripAppsScrubber.class] ? [(StripAppsScrubber *)self.appsScrubber visualCenterX] : width/2;
    CGFloat fittedCenter=MIN(MAX(content/2,target),width-content/2);
    CGFloat centerError=count && content<=width ? fabs((NSMinX(first)+NSMaxX(last))/2-fittedCenter) : 0;
    return @{@"visible":@(self.visible),@"centerError":@(centerError),@"visualCenter":@(target),@"actualCenter":@((NSMinX(first)+NSMaxX(last))/2),@"itemCount":@(count),@"mode":self.desktopsMode ? @"desktops" : @"apps",@"spaces":self.spaces ?: @[],@"apps":apps,@"layout":self.bar.defaultItemIdentifiers ?: @[],@"width":@(NSWidth(self.appsScrubber.bounds)),@"rightWidth":@(NSWidth(self.foldersItem.view.bounds)),@"windowWidth":@(NSWidth(self.appsScrubber.window.contentView.bounds)),@"folderCount":@(self.folderBrowser.entries.count),@"folderReady":@(self.folderBrowser.ready),@"folderDepth":@(self.folderStack.count)};
}
@end
