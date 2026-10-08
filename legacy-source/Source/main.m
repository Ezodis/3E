#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <math.h>
#import <Carbon/Carbon.h>
#import <objc/message.h>
#import <ApplicationServices/ApplicationServices.h>

// These macOS interfaces are private. Resolve them at runtime so unsupported
// systems fail cleanly instead of crashing during application loading.
@interface NSTouchBarItem (SystemTray)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static NSString *const ItemID = @"local.musicstrip.music";
static void (*SetPresence)(NSString *, BOOL);
static void (*ConfigureSystemModal)(BOOL);
static Boolean (*SendCommandToApp)(int, CFDictionaryRef, void *, CFStringRef, uint32_t, dispatch_queue_t, void (^)(uint32_t, CFArrayRef));
static void (*RegisterNotifications)(dispatch_queue_t);
static void *mediaFramework;
static void *dfrFramework;
static NSString *const MidiBundle = @"ch.uebe.MIDI-Touchbar";
static NSString *MidiPath(void) { return [[NSBundle mainBundle].bundleURL URLByAppendingPathComponent:@"Contents/Helpers/MIDI Touchbar.app"].path; }

typedef struct { CGKeyCode keyCode; CGEventFlags flags; BOOL valid; } MidiShortcut;

static MidiShortcut DecodeMidiShortcut(NSNumber *encoded) {
    if (!encoded || encoded.unsignedLongLongValue == 0) return (MidiShortcut){0, 0, NO};
    uint64_t value = encoded.unsignedLongLongValue;
    CGKeyCode code = value & 0xffff;
    CGEventFlags mask = kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;
    if (code > 127 || (value & ~(mask | 0xffffULL))) return (MidiShortcut){0, 0, NO};
    return (MidiShortcut){code, value & mask, YES};
}

static MidiShortcut ReadMidiShortcut(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:MidiBundle];
    NSDictionary *keys = [prefs dictionaryForKey:@"HotKeys"];
    // The installed app's default is Option-Tab; use its current setting when
    // present, so changing the MIDI app's shortcut does not break the helper.
    NSNumber *encoded = keys[@"showHide"] ?: @524336;
    return DecodeMidiShortcut(encoded);
}

static void PostMidiShortcut(MidiShortcut shortcut) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef down = CGEventCreateKeyboardEvent(source, shortcut.keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, shortcut.keyCode, false);
    if (down && up) {
        CGEventSetFlags(down, shortcut.flags);
        CGEventSetFlags(up, shortcut.flags);
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
        NSLog(@"Posted MIDI Touchbar Show/Hide shortcut");
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (source) CFRelease(source);
}

// Match Pock's direction: left = previous, right = next. A small movement
// tolerance keeps the natural jitter of a tap from skipping a track.
static int CommandForMovement(CGFloat dx) {
    return dx <= -12 ? 5 : (dx >= 12 ? 4 : 2);
}

static BOOL LoadInterfaces(void) {
    dfrFramework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    mediaFramework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    SetPresence = dlsym(dfrFramework ?: RTLD_DEFAULT, "DFRElementSetControlStripPresenceForIdentifier");
    ConfigureSystemModal = dlsym(dfrFramework ?: RTLD_DEFAULT, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    SendCommandToApp = dlsym(mediaFramework ?: RTLD_DEFAULT, "MRMediaRemoteSendCommandToApp");
    RegisterNotifications = dlsym(mediaFramework ?: RTLD_DEFAULT, "MRMediaRemoteRegisterForNowPlayingNotifications");
    return SetPresence && SendCommandToApp && [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)];
}

static NSString *MediaKey(const char *symbol) {
    NSString *__unsafe_unretained *key = (NSString *__unsafe_unretained *)dlsym(mediaFramework ?: RTLD_DEFAULT, symbol);
    return key ? *key : nil;
}

static BOOL IsAllowedPlayer(NSString *bundle) {
    return bundle.length && ![bundle isEqualToString:@"com.apple.Music"] && ![bundle isEqualToString:@"com.apple.iTunes"];
}

static id RequestValue(NSString *selector) {
    Class request = NSClassFromString(@"MRNowPlayingRequest");
    SEL method = NSSelectorFromString(selector);
    if (![request respondsToSelector:method]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(request, method); }
    @catch (NSException *e) { return nil; }
}

static NSString *CurrentPlayerBundle(void) {
    @try {
        id client = [RequestValue(@"localNowPlayingPlayerPath") valueForKey:@"client"];
        NSString *bundle = [client valueForKey:@"bundleIdentifier"];
        if ([bundle isEqualToString:@"com.apple.WebKit.WebContent"]) {
            NSString *parent = [client valueForKey:@"parentAppBundleIdentifier"];
            bundle = parent.length ? parent : @"com.apple.Safari";
        }
        return [bundle isKindOfClass:NSString.class] ? bundle : nil;
    } @catch (NSException *e) { return nil; }
}

// Selection is separate from sending so stale sessions, quit/relaunch, and
// browser-versus-Spotify priority can be tested without affecting playback.
static NSString *ChoosePlayer(NSString *current, NSString *last, NSString *front, NSSet<NSString *> *running) {
    if (IsAllowedPlayer(current) && [running containsObject:current]) return current;
    if ([front isEqualToString:@"com.spotify.client"] && [running containsObject:front]) return front;
    if (IsAllowedPlayer(last) && [running containsObject:last]) return last;
    if ([running containsObject:@"com.spotify.client"]) return @"com.spotify.client";
    return nil;
}

static NSDictionary *NoLaunchOptions(void) {
    NSString *key = MediaKey("kMRMediaRemoteOptionDisableImplicitAppLaunchBehaviors");
    return @{key ?: @"kMRMediaRemoteOptionDisableImplicitAppLaunchBehaviors": @YES};
}

// A process-addressed Apple Event cannot launch a default music app or a
// closed Spotify instance. Spotify documents these command IDs in its sdef.
static OSStatus SendSpotifyCommand(pid_t pid, int command) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID bytes:&pid length:sizeof(pid)];
    AEEventID eventID = command == 5 ? 'Prev' : command == 4 ? 'Next' : 'PlPs';
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:'spfy' eventID:eventID targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    AppleEvent reply = {typeNull, NULL};
    OSStatus error = AESendMessage(event.aeDesc, &reply, kAEWaitReply | kAECanInteract, 60 * 30);
    if (!error) {
        SInt32 replyError = 0;
        if (AEGetParamPtr(&reply, keyErrorNumber, typeSInt32, NULL, &replyError, sizeof(replyError), NULL) == noErr) error = replyError;
    }
    AEDisposeDesc(&reply);
    return error;
}

@interface MusicView : NSButton
@property NSImage *artwork;
@property BOOL tracking;
@property CGFloat startX;
@property CGFloat endX;
@property id touchIdentity;
@property BOOL cancelled;
@property int feedbackCommand;
@property BOOL showingFeedback;
@property BOOL didHold;
@property NSTimer *holdTimer;
@property (copy) void (^performCommand)(int);
@property (copy) void (^performHold)(void);
- (void)updateIcon;
- (void)moveAt:(NSPoint)point;
- (void)fireHold;
@end

@implementation MusicView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.title = @"";
        self.bezelStyle = NSBezelStyleRounded;
        self.buttonType = NSButtonTypeMomentaryLight;
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.allowedTouchTypes = NSTouchTypeMaskDirect;
        self.wantsRestingTouches = YES;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
        [self setAccessibilityLabel:@"Music: tap to play or pause, swipe left for previous track, swipe right for next track; hold to open MIDI Touchbar"];
        [self updateIcon];
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(70, 30); }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSView *)hitTest:(NSPoint)point {
    return NSPointInRect([self convertPoint:point fromView:self.superview], self.bounds) ? self : nil;
}
- (void)updateIcon {
    NSImage *icon = self.artwork ?: [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:nil];
    if (self.didHold && self.tracking) {
        icon = [NSImage imageWithSystemSymbolName:@"pianokeys" accessibilityDescription:nil];
    } else if (self.showingFeedback) {
        NSString *symbol = self.feedbackCommand == 5 ? @"backward.end.fill" : self.feedbackCommand == 4 ? @"forward.end.fill" : @"playpause.fill";
        icon = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    }
    icon = [icon copy];
    icon.size = NSMakeSize(20, 20);
    self.image = icon;
}
- (void)beginAt:(NSPoint)point identity:(id)identity {
    if (self.tracking || !NSPointInRect(point, self.bounds)) return;
    self.tracking = YES;
    [self highlight:YES];
    self.cancelled = NO;
    self.didHold = NO;
    self.startX = self.endX = point.x;
    self.touchIdentity = identity;
    [self.holdTimer invalidate];
    __weak MusicView *weakSelf = self;
    self.holdTimer = [NSTimer timerWithTimeInterval:0.65 repeats:NO block:^(NSTimer *timer) { [weakSelf fireHold]; }];
    [NSRunLoop.mainRunLoop addTimer:self.holdTimer forMode:NSRunLoopCommonModes];
    self.needsDisplay = YES;
}
- (void)moveAt:(NSPoint)point {
    if (!self.tracking) return;
    self.endX = point.x;
    if (fabs(self.endX - self.startX) >= 12) {
        [self.holdTimer invalidate];
        self.holdTimer = nil;
    }
}
- (void)fireHold {
    [self.holdTimer invalidate];
    self.holdTimer = nil;
    if (!self.tracking || self.cancelled || self.didHold || fabs(self.endX - self.startX) >= 12) return;
    self.didHold = YES;
    [self updateIcon];
    if (self.performHold) self.performHold();
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate];
    self.holdTimer = nil;
    if (!self.tracking) return;
    self.tracking = NO;
    [self highlight:NO];
    self.touchIdentity = nil;
    CGFloat dx = point.x - self.startX;
    if (!self.didHold && !self.cancelled && (fabs(dx) >= 12 || NSPointInRect(point, self.bounds))) {
        int command = CommandForMovement(dx);
        if (self.performCommand) self.performCommand(command);
        self.feedbackCommand = command;
        self.showingFeedback = YES;
        [self updateIcon];
        __weak MusicView *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            weakSelf.showingFeedback = NO;
            [weakSelf updateIcon];
            weakSelf.needsDisplay = YES;
        });
    }
    [self updateIcon];
    self.needsDisplay = YES;
}
- (void)touchesBeganWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches = [event touchesMatchingPhase:NSTouchPhaseBegan inView:self];
    if (self.tracking || touches.count != 1) { self.cancelled = YES; [self.holdTimer invalidate]; self.holdTimer = nil; return; }
    NSTouch *touch = touches.anyObject;
    if (touch.type == NSTouchTypeDirect) [self beginAt:[touch locationInView:self] identity:touch.identity];
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    for (NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:self]) {
        if ([touch.identity isEqual:self.touchIdentity]) [self moveAt:[touch locationInView:self]];
    }
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for (NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:self]) {
        if ([touch.identity isEqual:self.touchIdentity]) [self finishAt:[touch locationInView:self]];
    }
}
- (void)touchesCancelledWithEvent:(NSEvent *)event {
    self.cancelled = YES;
    [self.holdTimer invalidate];
    self.holdTimer = nil;
    self.tracking = NO;
    [self highlight:NO];
    self.touchIdentity = nil;
    [self updateIcon];
    self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event { [self beginAt:[self convertPoint:event.locationInWindow fromView:nil] identity:nil]; }
- (void)mouseDragged:(NSEvent *)event { [self moveAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self finishAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (BOOL)accessibilityPerformPress { if (self.performCommand) self.performCommand(2); return YES; }
@end

 #import "DockSupport.h"

static pid_t AbletonPID(void) {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
        if ([app.bundleIdentifier isEqualToString:@"com.ableton.live"]) return app.processIdentifier;
    return 0;
}

static BOOL AXTextContains(AXUIElementRef element, NSString *needle) {
    if (!element || !needle.length) return NO;
    for (NSString *attribute in @[(__bridge NSString *)kAXTitleAttribute, (__bridge NSString *)kAXDescriptionAttribute, (__bridge NSString *)kAXRoleDescriptionAttribute]) {
        CFTypeRef value = NULL;
        if (AXUIElementCopyAttributeValue(element, (__bridge CFStringRef)attribute, &value) == kAXErrorSuccess && value && CFGetTypeID(value) == CFStringGetTypeID()) {
            BOOL match = [((__bridge NSString *)value) localizedCaseInsensitiveContainsString:needle];
            CFRelease(value); if (match) return YES;
        } else if (value) CFRelease(value);
    }
    return NO;
}

static BOOL AbletonFindAndAct(NSString *needle, NSNumber *value, BOOL press) {
    pid_t pid = AbletonPID(); if (!pid || !AXIsProcessTrusted()) return NO;
    AXUIElementRef app = AXUIElementCreateApplication(pid); if (!app) return NO;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:(__bridge id)app]; BOOL acted = NO;
    while (queue.count && !acted) {
        AXUIElementRef node = (__bridge AXUIElementRef)queue.firstObject; [queue removeObjectAtIndex:0];
        if (AXTextContains(node, needle)) {
            if (press && AXUIElementPerformAction(node, kAXPressAction) == kAXErrorSuccess) acted = YES;
            else if (value && AXUIElementSetAttributeValue(node, kAXValueAttribute, (__bridge CFTypeRef)value) == kAXErrorSuccess) acted = YES;
        }
        CFTypeRef children = NULL;
        if (!acted && AXUIElementCopyAttributeValue(node, kAXChildrenAttribute, &children) == kAXErrorSuccess && children && CFGetTypeID(children) == CFArrayGetTypeID()) {
            for (id child in (__bridge NSArray *)children) [queue addObject:child];
        }
        if (children) CFRelease(children);
    }
    CFRelease(app); return acted;
}

@interface AbletonRecordView : NSView
@property (copy) void (^action)(NSString *);
@property BOOL tracking;
@property BOOL didHold;
@property CGFloat startX;
@property NSTimer *holdTimer;
@property BOOL recording;
@end

@implementation AbletonRecordView
- (instancetype)initWithFrame:(NSRect)frame { if ((self=[super initWithFrame:frame])) { self.wantsLayer=YES; self.layer.cornerRadius=5; [self setAccessibilityElement:YES]; [self setAccessibilityRole:NSAccessibilityButtonRole]; [self setAccessibilityLabel:@"Ableton record"]; } return self; }
- (void)drawRect:(NSRect)rect { [[(self.recording ? NSColor.systemRedColor : [NSColor colorWithCalibratedRed:.45 green:.06 blue:.06 alpha:1]) colorWithAlphaComponent:.95] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5] fill]; [[NSColor.whiteColor colorWithAlphaComponent:.95] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((NSWidth(self.bounds)-12)/2,9,12,12)] fill]; }
- (void)fireHold { if (self.tracking && !self.didHold) { self.didHold=YES; if(self.action) self.action(@"options"); [self setNeedsDisplay:YES]; } }
- (void)mouseDown:(NSEvent *)event { self.tracking=YES; self.didHold=NO; self.startX=[self convertPoint:event.locationInWindow fromView:nil].x; __weak AbletonRecordView *weakSelf=self; self.holdTimer=[NSTimer scheduledTimerWithTimeInterval:.6 repeats:NO block:^(NSTimer *timer){ [weakSelf fireHold]; }]; }
- (void)mouseDragged:(NSEvent *)event { CGFloat x=[self convertPoint:event.locationInWindow fromView:nil].x; if(fabs(x-self.startX)>12){ [self.holdTimer invalidate]; self.holdTimer=nil; } }
- (void)mouseUp:(NSEvent *)event { CGFloat x=[self convertPoint:event.locationInWindow fromView:nil].x; [self.holdTimer invalidate]; self.holdTimer=nil; BOOL hold=self.didHold; BOOL swipe=fabs(x-self.startX)>=12; self.tracking=NO; self.didHold=NO; if(hold) return; if(self.action) self.action(swipe ? (x>self.startX ? @"arm-on" : @"arm-off") : @"toggle"); }
- (BOOL)accessibilityPerformPress { if(self.action) self.action(@"toggle"); return YES; }
@end

static NSArray<NSString *> *AbletonRecordOptionNames(void) { return @[@"Arrangement Record", @"Session Record", @"Punch In", @"Punch Out", @"Overdub", @"Count In"]; }

@interface RecordOptionsDelegate : NSObject <NSTouchBarDelegate>
@end
@implementation RecordOptionsDelegate
- (NSTouchBarItem *)touchBar:(NSTouchBar *)bar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier { NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier]; NSButton *button=[NSButton buttonWithTitle:identifier target:self action:@selector(option:)]; button.bezelStyle=NSBezelStyleRounded; item.view=button; return item; }
- (void)option:(NSButton *)button { AbletonFindAndAct(button.title, @YES, YES); SEL dismiss=NSSelectorFromString(@"dismissSystemModalTouchBar:"); if([NSTouchBar respondsToSelector:dismiss]) ((void(*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,dismiss,button.window.touchBar); }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSCustomTouchBarItem *item;
@property MusicView *musicView;
@property DockLauncher *dockLauncher;
@property DockPanel *dockPanel;
@property id notificationToken;
@property id workspaceToken;
@property NSTimer *recoveryTimer;
@property NSString *lastPlayer;
@property BOOL commandPending;
@property BOOL midiOpening;
@property BOOL midiPermissionPrompted;
@property BOOL midiRequested;
@property BOOL midiVisible;
@property NSCustomTouchBarItem *recordItem;
@property AbletonRecordView *recordView;
@property RecordOptionsDelegate *recordOptionsDelegate;
- (NSString *)selectedPlayer;
- (void)performMediaCommand:(int)command;
- (void)openMidi;
- (void)handleRecordAction:(NSString *)action;
- (void)showRecordOptions;
- (void)sendMidi:(NSString *)command;
@end

@implementation AppDelegate
- (void)sendMidi:(NSString *)command { (void)command; self.midiVisible = NO; }
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (!LoadInterfaces()) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"This macOS version does not expose the required Touch Bar interfaces.";
        alert.informativeText = @"MusicStrip could not add its music button.";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    self.musicView = [[MusicView alloc] initWithFrame:NSMakeRect(0, 0, 70, 30)];
    self.musicView.translatesAutoresizingMaskIntoConstraints = NO;
    // The remote Touch Bar host owns final dimensions. Required size
    // constraints conflict with its root view; intrinsic size is sufficient.
    __weak AppDelegate *weakSelf = self;
    self.musicView.performCommand = ^(int command) {
        [weakSelf performMediaCommand:command];
    };
    self.musicView.performHold = ^{ [weakSelf openMidi]; };
    self.dockPanel=[DockPanel new];
    self.dockPanel.willShow=^{ [weakSelf sendMidi:@"HIDE"]; weakSelf.midiRequested=NO; };
    self.dockLauncher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,40,30)];
    [self.dockLauncher setAccessibilityLabel:@"Apps: tap for running apps, folders and Trash; hold for Mission Control"];
    self.dockLauncher.performCommand=^(int command){ [weakSelf.dockPanel show]; };
    self.dockLauncher.performHold=^{
        [weakSelf.dockPanel close:nil]; [weakSelf sendMidi:@"HIDE"]; weakSelf.midiRequested=NO;
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@"/System/Applications/Mission Control.app"]];
    };
    self.item = [[NSCustomTouchBarItem alloc] initWithIdentifier:ItemID];
    self.item.customizationLabel = @"Music and Apps";
    // Keep two independent native buttons adjacent in one tray item.
    NSStackView *launchers=[NSStackView stackViewWithViews:@[self.musicView,self.dockLauncher]];
    launchers.orientation=NSUserInterfaceLayoutOrientationHorizontal; launchers.spacing=4;
    [self.musicView.widthAnchor constraintEqualToConstant:70].active=YES;
    [self.dockLauncher.widthAnchor constraintEqualToConstant:40].active=YES;
    self.item.view = launchers;
    self.recordView=[[AbletonRecordView alloc] initWithFrame:NSMakeRect(0,0,42,30)];
    __weak AppDelegate *recordSelf= self;
    self.recordView.action=^(NSString *action){ [recordSelf handleRecordAction:action]; };
    self.recordItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.ableton.record"];
    self.recordItem.customizationLabel=@"Ableton Record"; self.recordItem.view=self.recordView;
    // Required before registration: without it the system accepts the item but
    // leaves the Control Strip's tray provider inactive, so no button appears.
    if (ConfigureSystemModal) ConfigureSystemModal(YES);
    [NSTouchBarItem addSystemTrayItem:self.item];
    [NSTouchBarItem addSystemTrayItem:self.recordItem];
    SetPresence(ItemID, YES);
    NSLog(@"Registered adjacent Music and Apps Control Strip buttons. Open MusicStrip again to quit.");
    if (RegisterNotifications) RegisterNotifications(dispatch_get_main_queue());
    self.notificationToken = [NSNotificationCenter.defaultCenter addObserverForName:nil object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.name hasPrefix:@"kMR"] && ![note.name containsString:@"Volume"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
        }
    }];
    self.workspaceToken = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:nil object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.name isEqualToString:NSWorkspaceDidLaunchApplicationNotification] || [note.name isEqualToString:NSWorkspaceDidTerminateApplicationNotification] || [note.name isEqualToString:NSWorkspaceDidWakeNotification] || [note.name isEqualToString:NSWorkspaceDidActivateApplicationNotification]) [weakSelf refresh];
    }];
    self.lastPlayer = [NSUserDefaults.standardUserDefaults stringForKey:@"LastPlayer"];
    self.recoveryTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    [self refresh];
}
- (void)handleRecordAction:(NSString *)action {
    if ([action isEqualToString:@"options"]) { [self showRecordOptions]; return; }
    if ([action isEqualToString:@"toggle"]) { if(AbletonFindAndAct(@"Record", nil, YES)) self.recordView.recording=!self.recordView.recording; return; }
    if ([action isEqualToString:@"arm-on"]) { self.recordView.recording=AbletonFindAndAct(@"Arm", @YES, YES) || AbletonFindAndAct(@"Record", @YES, YES); return; }
    if ([action isEqualToString:@"arm-off"]) { self.recordView.recording=!AbletonFindAndAct(@"Arm", @NO, NO); return; }
}
- (void)showRecordOptions {
    self.recordOptionsDelegate=[RecordOptionsDelegate new];
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=self.recordOptionsDelegate; bar.defaultItemIdentifiers=AbletonRecordOptionNames(); bar.customizationAllowedItemIdentifiers=AbletonRecordOptionNames();
    SEL present=NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"); if([NSTouchBar respondsToSelector:present]) ((void(*)(id,SEL,id,NSInteger,id))objc_msgSend)(NSTouchBar.class,present,bar,0,@"local.musicstrip.ableton.record.options");
}
- (NSString *)selectedPlayer {
    NSMutableSet *running = [NSMutableSet set];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) if (app.bundleIdentifier && !app.terminated) [running addObject:app.bundleIdentifier];
    return ChoosePlayer(CurrentPlayerBundle(), self.lastPlayer, NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier, running);
}
- (void)openMidi {
    [self.dockPanel close:nil];
    if (self.midiOpening) return;
    MidiShortcut shortcut = ReadMidiShortcut();
    if (!shortcut.valid) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Set a Show/Hide shortcut in MIDI Touchbar first.";
        alert.informativeText = @"Use MIDI Touchbar’s Customize Key Commands menu, then hold the music button again.";
        [alert runModal];
        return;
    }
    if (!AXIsProcessTrusted()) {
        if (!self.midiPermissionPrompted) {
            self.midiPermissionPrompted = YES;
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
        }
        NSLog(@"MIDI hold needs Accessibility permission for MusicStrip; no keyboard shortcut was sent.");
        return;
    }
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:MidiBundle].count) {
        PostMidiShortcut(shortcut);
        return;
    }
    NSString *midiPath=MidiPath();
    if (![NSFileManager.defaultManager fileExistsAtPath:midiPath]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"MIDI Touchbar could not be found.";
        alert.informativeText = midiPath;
        [alert runModal];
        return;
    }
    self.midiOpening = YES;
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    __weak AppDelegate *weakSelf = self;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:midiPath] configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            weakSelf.midiOpening = NO;
            if (app && !app.terminated && !error) PostMidiShortcut(ReadMidiShortcut());
            else NSLog(@"Could not launch MIDI Touchbar: %@", error);
        });
    }];
}
- (void)performMediaCommand:(int)command {
    if (self.commandPending) return;
    NSString *bundle = [self selectedPlayer];
    if (!IsAllowedPlayer(bundle)) { NSLog(@"No running media player; no command sent."); return; }
    NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject;
    if (!app || app.terminated) return;
    self.commandPending = YES;
    __weak AppDelegate *weakSelf = self;
    if ([bundle isEqualToString:@"com.spotify.client"]) {
        pid_t pid = app.processIdentifier;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            OSStatus error = SendSpotifyCommand(pid, command);
            NSLog(@"Spotify command %d completed with status %d", command, (int)error);
            dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.commandPending = NO; [weakSelf refresh]; });
        });
    } else {
        // No blind command or implicit app launch: the current player must be
        // identified and already running. Apple Music is excluded above.
        BOOL queued = SendCommandToApp(command, (__bridge CFDictionaryRef)NoLaunchOptions(), NULL, (__bridge CFStringRef)bundle, 0, dispatch_get_main_queue(), ^(uint32_t error, CFArrayRef statuses) {
            NSLog(@"Targeted media command completed with status %u", error);
            weakSelf.commandPending = NO;
            [weakSelf refresh];
        });
        if (!queued) self.commandPending = NO;
        // Recover if this private API omits its callback.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ weakSelf.commandPending = NO; });
    }
}
- (void)refresh {
    if (self.item) SetPresence(ItemID, YES);
    NSString *bundle = [self selectedPlayer];
    if (IsAllowedPlayer(bundle)) {
        self.lastPlayer = bundle;
        [NSUserDefaults.standardUserDefaults setObject:bundle forKey:@"LastPlayer"];
    }
    NSRunningApplication *app = bundle ? [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject : nil;
    self.musicView.artwork = app.icon;
    [self.musicView updateIcon];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    [NSApp terminate:nil];
    return NO;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.dockPanel close:nil];
    [self.dockLauncher.holdTimer invalidate];
    if (SetPresence && self.item) SetPresence(ItemID, NO);
    if (self.item && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) [NSTouchBarItem removeSystemTrayItem:self.item];
    if (self.recordItem && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) [NSTouchBarItem removeSystemTrayItem:self.recordItem];
    if (self.notificationToken) [NSNotificationCenter.defaultCenter removeObserver:self.notificationToken];
    if (self.workspaceToken) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self.workspaceToken];
    [self.recoveryTimer invalidate];
    [self.musicView.holdTimer invalidate];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--diagnose") == 0) {
            BOOL ready = LoadInterfaces();
            printf("Control Strip and media command interfaces: %s\n", ready ? "available" : "unavailable");
            printf("Current player: %s\n", [CurrentPlayerBundle() UTF8String] ?: "none");
            printf("Automatic player launching: disabled\n");
            MidiShortcut shortcut = ReadMidiShortcut();
            printf("MIDI shortcut: key %u, flags 0x%llx (%s)\n", shortcut.keyCode, (unsigned long long)shortcut.flags, shortcut.valid ? "valid" : "invalid");
            printf("MIDI shortcut permission: %s\n", AXIsProcessTrusted() ? "available" : "Accessibility permission needed");
            return ready ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            __block NSInteger dockTaps=0,dockHolds=0;
            DockLauncher *launcher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,40,30)];
            launcher.performCommand=^(int command){ dockTaps++; };
            launcher.performHold=^{ dockHolds++; };
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher finishAt:NSMakePoint(20,15)];
            NSCAssert(dockTaps==1 && dockHolds==0,@"Apps tap opens only the app panel");
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher fireHold]; [launcher fireHold]; [launcher finishAt:NSMakePoint(20,15)];
            NSCAssert(dockTaps==1 && dockHolds==1,@"Mission Control hold must run once without opening apps afterward");
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher moveAt:NSMakePoint(35,15)]; [launcher fireHold]; [launcher finishAt:NSMakePoint(35,15)];
            NSCAssert(dockTaps==1 && dockHolds==1,@"Dragged apps button must not trigger a tap or hold");
            NSDictionary *folderFixture=@{@"persistent-others":@[@{@"tile-type":@"directory-tile",@"tile-data":@{@"file-data":@{@"_CFURLString":@"file:///tmp/Downloads/"}}},@{@"tile-type":@"url-tile",@"tile-data":@{@"file-data":@{@"_CFURLString":@"https://example.com"}}}]};
            NSCAssert(DockFolderURLs(folderFixture).count==1,@"Read only Dock folder tiles");
            NSSet *players = [NSSet setWithArray:@[@"com.spotify.client", @"com.apple.Safari", @"com.apple.Music"]];
            NSCAssert([ChoosePlayer(@"com.apple.Safari", @"com.spotify.client", nil, players) isEqualToString:@"com.apple.Safari"], @"Active browser must beat remembered Spotify");
            NSCAssert([ChoosePlayer(nil, @"com.spotify.client", nil, players) isEqualToString:@"com.spotify.client"], @"Reopened Spotify must be resumed");
            NSCAssert([ChoosePlayer(nil, @"com.apple.Safari", @"com.spotify.client", players) isEqualToString:@"com.spotify.client"], @"Freshly opened Spotify must beat a stale browser session");
            NSCAssert(ChoosePlayer(@"com.apple.Music", @"com.apple.Music", nil, [NSSet setWithObject:@"com.apple.Music"]) == nil, @"Apple Music must never be selected");
            NSCAssert(ChoosePlayer(nil, @"com.spotify.client", nil, [NSSet set]) == nil, @"A closed player must not be launched");
            NSCAssert([NoLaunchOptions().allValues.firstObject boolValue], @"App launch fallback must be disabled");
            MidiShortcut midiKey = DecodeMidiShortcut(@524336);
            NSCAssert(midiKey.valid && midiKey.keyCode == 48 && midiKey.flags == kCGEventFlagMaskAlternate, @"MIDI Option-Tab setting must decode correctly");
            NSCAssert(!DecodeMidiShortcut(@0).valid && !DecodeMidiShortcut(@65535).valid, @"Disabled and invalid MIDI shortcuts must not be posted");
            MusicView *view = [[MusicView alloc] initWithFrame:NSMakeRect(0, 0, 118, 30)];
            __block int sent = -1;
            view.performCommand = ^(int command) { sent = command; };
            __block int holds = 0;
            view.performHold = ^{ holds++; };
            [view finishAt:NSMakePoint(20, 10)];
            NSCAssert(sent == -1, @"No command without a touch start");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view finishAt:NSMakePoint(33, 10)];
            NSCAssert(sent == 2, @"Tap jitter must toggle playback");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view finishAt:NSMakePoint(5, 10)];
            NSCAssert(sent == 5, @"Swipe left must request previous track");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view finishAt:NSMakePoint(80, 10)];
            NSCAssert(sent == 4, @"Swipe right must request next track");
            sent = -1;
            [view beginAt:NSMakePoint(30, 10) identity:nil]; view.cancelled = YES; [view finishAt:NSMakePoint(80, 10)];
            NSCAssert(sent == -1, @"Cancelled touch must do nothing");
            [view beginAt:NSMakePoint(-5, 10) identity:nil]; [view finishAt:NSMakePoint(20, 10)];
            NSCAssert(sent == -1, @"Touches beginning outside must do nothing");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view fireHold]; [view fireHold]; [view finishAt:NSMakePoint(30, 10)];
            NSCAssert(holds == 1 && sent == -1, @"Hold must fire once and suppress playback on release");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view moveAt:NSMakePoint(55, 10)]; [view fireHold]; [view finishAt:NSMakePoint(55, 10)];
            NSCAssert(holds == 1 && sent == 4, @"Swipe must cancel the hold and still request next track");
            sent = -1;
            [view beginAt:NSMakePoint(30, 10) identity:nil]; view.cancelled = YES; [view fireHold]; [view finishAt:NSMakePoint(30, 10)];
            NSCAssert(holds == 1 && sent == -1, @"Cancelled hold must neither open MIDI nor affect playback");
            [view beginAt:NSMakePoint(30, 10) identity:nil]; [view finishAt:NSMakePoint(30, 10)]; [view fireHold];
            NSCAssert(holds == 1 && sent == 2, @"Short tap must not leave a pending MIDI action");
            puts("Passed: MIDI shortcut decoding; hold-once, swipe/cancel/release handling; player routing and Apple Music exclusion. No media or MIDI actions sent.");
            return 0;
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        if (argc > 1 && strcmp(argv[1], "--dock-smoke-test") == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate.dockLauncher beginAt:NSMakePoint(20,15) identity:nil]; [delegate.dockLauncher finishAt:NSMakePoint(20,15)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSDictionary *snapshot=[delegate.dockPanel snapshot];
                NSLog(@"Dock snapshot: %@",snapshot);
                NSCAssert([snapshot[@"visible"] boolValue] && [snapshot[@"apps"] count]>0,@"Apps tap must present real running apps");
                NSCAssert(([snapshot[@"layout"] isEqual:@[DockCloseID,DockAppsID,DockFoldersID]]),@"X first, expanding apps, folders and Trash last");
                NSCAssert([snapshot[@"width"] doubleValue]>500,@"App row must fill available Touch Bar width");
                [delegate.dockPanel close:nil]; NSCAssert(!delegate.dockPanel.visible,@"X returns to the Control Strip");
                [delegate.dockPanel show];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate openMidi]; NSCAssert(!delegate.dockPanel.visible,@"MIDI closes apps presentation first");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.midiVisible,@"Bundled MIDI remains available");
                [delegate.dockPanel show];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.dockPanel.visible && !delegate.midiVisible,@"Apps closes MIDI before presenting");
                [delegate.dockPanel close:nil]; NSLog(@"Passed Apps/MIDI presentation integration checks"); [NSApp terminate:nil];
            });
        }
        if (argc > 1 && strcmp(argv[1], "--smoke-test") == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSLog(@"Smoke test complete; removing item and quitting.");
                [NSApp terminate:nil];
            });
        }
        [app run];
    }
    return 0;
}
