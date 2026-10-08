#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <math.h>
#import <float.h>
#import <Carbon/Carbon.h>
#import <objc/message.h>
#import <signal.h>
#import <unistd.h>
#import <QuartzCore/QuartzCore.h>


@interface StripApplication : NSApplication
@end
@implementation StripApplication
- (void)reportException:(NSException *)exception {
    NSLog(@"Strip exception: %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
    if([NSProcessInfo.processInfo.arguments componentsJoinedByString:@" "].length && [[NSProcessInfo.processInfo.arguments componentsJoinedByString:@" "] containsString:@"smoke-test"]) exit(1);
    [super reportException:exception];
}
@end

// These macOS interfaces are private. Resolve them at runtime so unsupported
// systems fail cleanly instead of crashing during application loading.
@interface NSTouchBarItem (SystemTray)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static NSString *const ItemID = @"local.musicstrip.music";
static NSString *const AppsTrayID = @"local.musicstrip.apps";
static void (*SetPresence)(NSString *, BOOL);
static void (*ConfigureSystemModal)(BOOL);
static Boolean (*SendCommandToApp)(int, CFDictionaryRef, void *, CFStringRef, uint32_t, dispatch_queue_t, void (^)(uint32_t, CFArrayRef));
static void (*RegisterNotifications)(dispatch_queue_t);
static void *mediaFramework;
static void *dfrFramework;
static NSString *const MidiBundle = @"ch.uebe.MIDI-Touchbar";
// Music gesture direction: right = next, left = previous. A small movement
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

// AXIsProcessTrusted() can retain a stale result after the user approves the
// current signed bundle in System Settings.  The prompt-capable API refreshes
// the TCC decision for this process and also associates the approval with the
// exact bundle currently running.
static BOOL AccessibilityTrusted(BOOL prompt) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
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

static NSString *CanonicalPlayerBundle(NSString *bundle,NSString *parent) {
    if(![bundle isKindOfClass:NSString.class]) return nil;
    if([bundle hasPrefix:@"com.apple.WebKit."]) return [parent isKindOfClass:NSString.class] && parent.length ? parent : @"com.apple.Safari";
    return bundle;
}
// An absent snapshot is unknown, not evidence that a browser has paused.
static NSInteger MediaSnapshotState(id rate,BOOL hasInfo,BOOL hasPlayingFlag,BOOL playing) {
    if([rate respondsToSelector:@selector(doubleValue)]) return [rate doubleValue]>0 ? 1 : 0;
    if(playing && hasPlayingFlag) return 1;
    return hasInfo && hasPlayingFlag ? 0 : -1;
}
static NSString *CurrentPlayerBundle(void) {
    @try {
        id client = [RequestValue(@"localNowPlayingPlayerPath") valueForKey:@"client"];
        NSString *bundle = [client valueForKey:@"bundleIdentifier"];
        NSString *parent=nil;
        if([bundle hasPrefix:@"com.apple.WebKit."]) {
            @try { parent=[client valueForKey:@"parentAppBundleIdentifier"]; } @catch(NSException *exception) {}
        }
        return CanonicalPlayerBundle(bundle,parent);
    } @catch (NSException *e) { return nil; }
}

#import "PlayerSupport.h"
#import "PlaybackBook.h"

// Selection is separate from sending so stale sessions, quit/relaunch, and
// browser-versus-Spotify priority can be tested without affecting playback.
static NSString *ChoosePlayer(NSString *current, NSString *last, NSString *front, NSSet<NSString *> *running) {
    // last is updated on player activation and observed media transitions,
    // rather than overwritten on every timer tick by a stale Now Playing client.
    if (IsAllowedPlayer(last) && [running containsObject:last]) return last;
    if (([front isEqualToString:@"com.ableton.live"] || [front isEqualToString:@"com.spotify.client"]) && [running containsObject:front]) return front;
    if (IsAllowedPlayer(current) && [running containsObject:current]) return current;
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
    AEEventID eventID = command == 5 ? 'Prev' : command == 4 ? 'Next' : command == 1 ? 'Paus' : command == 0 ? 'Play' : 'PlPs';
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
@property NSInteger nextAction;
@property BOOL stopAction;
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
        self.nextAction = -1;
        self.title = @"";
        self.bezelStyle = NSBezelStyleRounded;
        self.buttonType = NSButtonTypeMomentaryLight;
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.allowedTouchTypes = NSTouchTypeMaskDirect;
        self.wantsRestingTouches = YES;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
        [self setAccessibilityLabel:@"Music: tap to play or pause, swipe right for next track, swipe left for previous track; hold to open MIDI Touchbar"];
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
    NSImage *icon = IconWithAction(self.artwork ?: [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:nil], self.nextAction, self.stopAction);
    if (self.didHold && self.tracking) {
        icon = [NSImage imageWithSystemSymbolName:@"pianokeys" accessibilityDescription:nil];
    } else if(self.showingFeedback && (self.feedbackCommand==4 || self.feedbackCommand==5)) {
        icon=[NSImage imageWithSystemSymbolName:self.feedbackCommand==5 ? @"backward.end.fill" : @"forward.end.fill" accessibilityDescription:self.feedbackCommand==5 ? @"Previous track" : @"Next track"];
    }
    icon = [icon copy];
    BOOL transient=(self.didHold && self.tracking) || (self.showingFeedback && (self.feedbackCommand==4 || self.feedbackCommand==5));
    icon.size = transient ? NSMakeSize(20,20) : NSMakeSize(34,20);
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
        self.feedbackCommand = command;
        if (self.performCommand) self.performCommand(command);
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

#import "DesktopSupport.h"
#import "DockSupport.h"
#import "AppsTrayHelper.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSCustomTouchBarItem *item;
@property NSTask *appsTask;
@property NSPipe *appsInput;
@property NSPipe *appsOutput;
@property NSMutableString *appsBuffer;
@property NSDictionary *appsStatus;
@property BOOL appsReady;
@property BOOL appsVisible;
@property NSCustomTouchBarItem *appsOverlayTrayItem;
@property BOOL appsRequested;
@property MusicView *musicView;
@property DockLauncher *dockLauncher;
@property DockPanel *dockPanel;
@property id notificationToken;
@property id workspaceToken;
@property NSTimer *recoveryTimer;
@property NSTimer *nativeTrayTimer;
@property BOOL nativeTrayNeedsReinstall;
@property NSMutableSet<NSNumber *> *nativeTrayTerminations;
@property NSString *lastPlayer;
@property NSString *displayedPlayer;
@property NSString *observedMediaPlayer;
@property BOOL observedPlaying;
@property BOOL didObservePlayer;
@property NSString *browserService;
@property NSString *browserURL;
@property NSMutableDictionary *siteIcons;
@property BOOL browserLookupPending;
@property NSDate *browserLookupDate;
@property BOOL abletonPermissionPrompted;
@property BOOL commandPending;
@property PlaybackBook *playbackBook;
@property BOOL playbackPollPending;
@property BOOL didPollProviders;
@property NSTask *midiTask;
@property NSPipe *midiInput;
@property NSPipe *midiOutput;
@property BOOL midiReady;
@property BOOL midiStarting;
@property BOOL midiVisible;
@property BOOL midiRequested;
@property NSMutableString *midiBuffer;
@property NSUInteger midiResolvedItems;
- (NSString *)selectedPlayer;
- (void)performMediaCommand:(int)command;
- (void)openMidi;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (!LoadInterfaces()) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"This macOS version does not expose the required Touch Bar interfaces.";
        alert.informativeText = @"Strip3£ could not add its music button.";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    // Never summon the system permission dialog automatically. macOS can
    // re-display it on every launch when the TCC decision is still settling;
    // use a silent check and let the swipe path report the actual state.
    AccessibilityTrusted(NO);
    self.playbackBook = [PlaybackBook new];
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
    self.dockPanel.willShow=^{ [weakSelf sendMidi:@"HIDE"]; weakSelf.midiRequested=NO; weakSelf.dockLauncher.panelOpen=YES; weakSelf.dockLauncher.needsDisplay=YES; [weakSelf.dockLauncher setAccessibilityLabel:@"Close apps: tap to close the Touch Bar picker; hold for desktops"]; };
    self.item=[[NSCustomTouchBarItem alloc] initWithIdentifier:ItemID];
    self.dockLauncher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,40,30)];
    self.dockLauncher.performCommand=^(int command){ [weakSelf sendApps:@"TAP"]; };
    [self.dockLauncher setAccessibilityLabel:@"Apps: tap for running apps; hold for Touch Bar desktops"];
    self.dockLauncher.performHold=^{ [weakSelf openDesktops]; };
    LauncherPairView *pair=[[LauncherPairView alloc] initWithFrame:NSMakeRect(0,0,70,30)];
    pair.apps=self.dockLauncher; pair.music=self.musicView;
    self.musicView.translatesAutoresizingMaskIntoConstraints=YES;
    [pair addSubview:self.dockLauncher]; [pair addSubview:self.musicView]; [pair layout];
    self.item.customizationLabel=@"Apps and Music"; self.item.view=pair;
    if(ConfigureSystemModal) ConfigureSystemModal(NO);
    [NSTouchBarItem addSystemTrayItem:self.item]; SetPresence(ItemID,YES);
    [self startApps];
    NSLog(@"Registered one tray item containing Apps and Music.");
    if (RegisterNotifications) RegisterNotifications(dispatch_get_main_queue());
    self.notificationToken = [NSNotificationCenter.defaultCenter addObserverForName:nil object:nil queue:nil usingBlock:^(NSNotification *note) {
        if ([note.name hasPrefix:@"kMR"] && ![note.name containsString:@"Volume"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf suppressNativeMediaTray];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
            });
        }
    }];
    self.workspaceToken = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:nil object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.name isEqualToString:NSWorkspaceDidActivateApplicationNotification]) {
            NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
            NSString *bundle = app.bundleIdentifier;
            if ([bundle isEqualToString:@"com.ableton.live"] || [bundle isEqualToString:@"com.spotify.client"]) { weakSelf.lastPlayer = bundle; [weakSelf.playbackBook prefer:bundle]; }
            if ([bundle isEqualToString:@"com.apple.Safari"]) [weakSelf updateBrowserService:YES];
        }
        if ([note.name isEqualToString:NSWorkspaceDidLaunchApplicationNotification] || [note.name isEqualToString:NSWorkspaceDidTerminateApplicationNotification] || [note.name isEqualToString:NSWorkspaceDidWakeNotification] || [note.name isEqualToString:NSWorkspaceDidActivateApplicationNotification]) [weakSelf refresh];
    }];
    self.lastPlayer = [NSUserDefaults.standardUserDefaults stringForKey:@"LastPlayer"];
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    if ([front isEqualToString:@"com.ableton.live"] || [front isEqualToString:@"com.spotify.client"]) self.lastPlayer = front;
    self.browserService = [NSUserDefaults.standardUserDefaults stringForKey:@"LastBrowserService"];
    self.siteIcons = [NSMutableDictionary dictionary];
    self.recoveryTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    self.nativeTrayTerminations=[NSMutableSet set];
    self.nativeTrayTimer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:YES block:^(NSTimer *timer){ [weakSelf suppressNativeMediaTray]; }];
    [self suppressNativeMediaTray];
    [self refresh];
    [self startMidi];
}
- (void)sendApps:(NSString *)command {
    if([command isEqualToString:@"TAP"]) {
        if(self.dockPanel.visible) { [self sendApps:@"HIDE"]; return; }
        self.appsRequested=YES; self.midiRequested=NO; [self sendMidi:@"HIDE"]; [self sendApps:@"SHOW"];
    } else if([command isEqualToString:@"SHOW"] || [command isEqualToString:@"DESKTOPS"]) {
        BOOL desktops=[command isEqualToString:@"DESKTOPS"];
        if(self.dockPanel.visible && self.dockPanel.desktopsMode!=desktops) [self.dockPanel close:nil];
        self.dockPanel.desktopsMode=desktops; self.appsRequested=YES;
        [self.dockPanel show]; self.appsVisible=self.dockPanel.visible;
        if(self.appsVisible && !self.appsOverlayTrayItem) {
            // macOS hides the originating tray identifier while a modal bar is
            // open. Keep the same paired view in the app's one tray slot under
            // a stable presentation identifier, including after the picker closes.
            self.appsOverlayTrayItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:AppsTrayID];
            self.appsOverlayTrayItem.customizationLabel=self.item.customizationLabel;
            self.appsOverlayTrayItem.view=self.item.view;
            [NSTouchBarItem addSystemTrayItem:self.appsOverlayTrayItem]; SetPresence(AppsTrayID,YES);
        }
        NSLog(@"Apps panel: VISIBLE");
    } else if([command isEqualToString:@"HIDE"] || [command isEqualToString:@"QUIT"]) {
        [self.dockPanel close:nil];
    } else if([command isEqualToString:@"RESTORE"]) [self.dockPanel restorePresentation];
    else if([command isEqualToString:@"STATUS"]) {
        NSMutableDictionary *state=[[self.dockPanel snapshot] mutableCopy];
        state[@"buttonWidth"]=@(NSWidth(self.dockLauncher.frame)); self.appsStatus=state;
    } else if([command hasPrefix:@"FOLDER "]) {
        DockIconButton *button=[self.dockPanel buttonFor:[NSURL fileURLWithPath:[command substringFromIndex:7] isDirectory:YES] label:@"Folder" image:nil action:@selector(openFolder:)]; [self.dockPanel openFolder:button];
    } else if([command isEqualToString:@"BACK"]) [self.dockPanel.folderBrowser willDismiss:nil];
    else if([command isEqualToString:@"ROOT"]) [self.dockPanel.folderBrowser willClose:nil];
}
- (void)openDesktops {
    self.appsRequested=YES; self.midiRequested=NO;
    [self sendMidi:@"HIDE"]; [self sendApps:@"DESKTOPS"];
}
- (void)startApps {
    self.appsReady=YES; [self.dockPanel prepareSwipeApps];
    __weak AppDelegate *weakSelf=self;
    self.dockPanel.selectSpace=^(uint64_t sid){ SelectDesktop(sid); };
    self.dockPanel.didClose=^{
        weakSelf.appsVisible=NO; weakSelf.appsRequested=NO;
        // Keep the paired view in its existing host. Removing the temporary
        // host here lets delayed native teardown detach the restored buttons.
        NSString *identifier=weakSelf.appsOverlayTrayItem ? AppsTrayID : ItemID;
        SetPresence(identifier,YES);
        weakSelf.dockLauncher.panelOpen=NO; weakSelf.dockLauncher.needsDisplay=YES;
        [weakSelf.dockLauncher setAccessibilityLabel:@"Apps: tap for running apps; hold for Touch Bar desktops"];
        if(weakSelf.midiRequested && weakSelf.midiReady) { weakSelf.midiRequested=NO; [weakSelf sendMidi:@"SHOW"]; }
    };
}
- (NSString *)selectedPlayer {
    NSMutableSet *running = [NSMutableSet set];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) if (app.bundleIdentifier && !app.terminated) [running addObject:app.bundleIdentifier];
    NSString *fallback=ChoosePlayer(CurrentPlayerBundle(), self.lastPlayer, NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier, running);
    return [self.playbackBook target:running fallback:fallback];
}
- (void)sendMidi:(NSString *)command {
    if (!self.midiTask.running) return;
    @try { [self.midiInput.fileHandleForWriting writeData:[[command stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; }
    @catch (NSException *e) { NSLog(@"MIDI connection closed: %@", e); }
}
- (void)startMidi {
    if (self.midiTask.running || self.midiStarting) return;
    NSString *helper = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/MIDI Touchbar.app"];
    NSString *executable = [helper stringByAppendingPathComponent:@"Contents/MacOS/MIDI Touchbar"];
    if (![NSFileManager.defaultManager fileExistsAtPath:executable]) { NSLog(@"Bundled MIDI engine missing"); return; }
    // Preserve the original MIDI port identities; avoid running two engines.
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:MidiBundle]) [app terminate];
    self.midiReady = NO;
    self.midiVisible = NO;
    self.midiInput = [NSPipe pipe];
    self.midiOutput = [NSPipe pipe];
    self.midiBuffer = [NSMutableString string];
    self.midiTask = [NSTask new];
    self.midiTask.executableURL = [NSURL fileURLWithPath:executable];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"DYLD_INSERT_LIBRARIES"] = [helper stringByAppendingPathComponent:@"Contents/Frameworks/MusicStripMidiBridge.dylib"];
    self.midiTask.environment = environment;
    self.midiTask.standardInput = self.midiInput;
    self.midiTask.standardOutput = self.midiOutput;
    __weak AppDelegate *weakSelf = self;
    self.midiOutput.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) { handle.readabilityHandler = nil; return; }
        NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *self = weakSelf;
            if (!self || !message) return;
            [self.midiBuffer appendString:message];
            NSRange newline;
            while ((newline = [self.midiBuffer rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [self.midiBuffer substringToIndex:newline.location];
                [self.midiBuffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
                NSLog(@"MIDI engine: %@", line);
                if ([line hasPrefix:@"{"]) {
                    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    self.midiResolvedItems = [status[@"modalLayout"] count];
                }
                if ([line isEqualToString:@"READY"]) {
                    self.midiReady = YES;
                    if (self.midiRequested) { self.midiRequested = NO; [self sendMidi:@"SHOW"]; }
                } else if ([line isEqualToString:@"VISIBLE"]) {
                    self.midiVisible=YES;
                    if(self.appsVisible || self.appsRequested) [self sendMidi:@"HIDE"];
                } else if ([line isEqualToString:@"HIDDEN"]) {
                    self.midiVisible=NO; [self refresh];
                    if(self.appsVisible) [self sendApps:@"RESTORE"];
                }
            }
        });
    };
    self.midiTask.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.midiTask != task) return;
            NSLog(@"MIDI engine exited: status %d, reason %ld", task.terminationStatus, (long)task.terminationReason);
            weakSelf.midiReady = NO; weakSelf.midiVisible = NO; [weakSelf refresh];
        });
    };
    self.midiStarting = YES;
    NSTask *task = self.midiTask;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        BOOL launched = [task launchAndReturnError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.midiTask != task) return;
            weakSelf.midiStarting = NO;
            if (!launched) NSLog(@"Could not start bundled MIDI engine: %@", error);
        });
    });
}
- (void)openMidi {
    self.appsRequested=NO;
    self.midiRequested=YES;
    [self sendApps:@"HIDE"];
    [self startMidi];
    // Closing Apps may complete synchronously and consume the request in its
    // callback. If the engine is ready and the request remains, open it here.
    if(self.midiReady && self.midiRequested) { self.midiRequested=NO; [self sendMidi:@"SHOW"]; }
}

- (void)performMediaCommand:(int)command {
    if (self.commandPending) return;
    NSString *bundle = self.displayedPlayer ?: [self selectedPlayer];
    if (!IsAllowedPlayer(bundle)) { NSLog(@"No running media player; no command sent."); return; }
    NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject;
    if (!app || app.terminated) return;
    if (command==2) {
        NSInteger state=[self.playbackBook state:bundle];
        if (state>=0) command=state==1 ? 1 : 0;
        self.musicView.feedbackCommand=command;
    }
    self.commandPending = YES;
    __weak AppDelegate *weakSelf = self;
    if ([bundle isEqualToString:@"com.ableton.live"]) {
        if (command != 2 && command != 0 && command != 1) { self.commandPending = NO; return; }
        if (!AXIsProcessTrusted()) {
            self.commandPending = NO;
            if (!self.abletonPermissionPrompted) {
                self.abletonPermissionPrompted = YES;
                AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
            }
            NSLog(@"Enable Strip3£ in macOS Accessibility to control Ableton's transport.");
            return;
        }
        pid_t pid = app.processIdentifier;
        dispatch_async(ProviderQueue(), ^{
            BOOL sent = SendAbletonState(pid, command==0 ? 1 : command==1 ? 0 : -1);
            NSLog(@"Ableton play/stop: %@", sent ? @"sent to Live" : @"not sent");
            dispatch_async(dispatch_get_main_queue(), ^{ if(sent && command<2) [weakSelf.playbackBook commit:bundle playing:command==0]; weakSelf.commandPending = NO; [weakSelf refresh]; });
        });
    } else if ([bundle isEqualToString:@"com.spotify.client"]) {
        pid_t pid = app.processIdentifier;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            OSStatus error = SendSpotifyCommand(pid, command);
            NSLog(@"Spotify command %d completed with status %d", command, (int)error);
            dispatch_async(dispatch_get_main_queue(), ^{ if(!error && command<2) [weakSelf.playbackBook commit:bundle playing:command==0]; weakSelf.commandPending = NO; [weakSelf refresh]; });
        });
    } else if(command==5 && [bundle isEqualToString:@"com.apple.Safari"] && [self.browserService isEqualToString:@"youtube"]) {
        pid_t pid=app.processIdentifier; pid_t mediaPID=SafariMediaPID();
        dispatch_async(ProviderQueue(), ^{
            BOOL youtube=[ServiceForURL(ReadSafariURL(mediaPID)) isEqualToString:@"youtube"];
            NSInteger restart=youtube ? SafariYouTubePreviousAction(pid) : -1;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableDictionary *options=[NoLaunchOptions() mutableCopy];
                if(restart==1) options[MediaKey("kMRMediaRemoteOptionPlaybackPosition") ?: @"kMRMediaRemoteOptionPlaybackPosition"]=@0;
                BOOL queued=SendCommandToApp(restart==1 ? 24 : 5,(__bridge CFDictionaryRef)options,NULL,(__bridge CFStringRef)bundle,0,dispatch_get_main_queue(),^(uint32_t error,CFArrayRef statuses) {
                    NSLog(@"YouTube Previous: %@ status %u",restart==1 ? @"restart" : @"previous video",error);
                    weakSelf.commandPending=NO; [weakSelf refresh];
                });
                if(!queued) weakSelf.commandPending=NO;
            });
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{ weakSelf.commandPending=NO; });
    } else {
        // No blind command or implicit app launch: the current player must be
        // identified and already running. Apple Music is excluded above.
        BOOL queued = SendCommandToApp(command, (__bridge CFDictionaryRef)NoLaunchOptions(), NULL, (__bridge CFStringRef)bundle, 0, dispatch_get_main_queue(), ^(uint32_t error, CFArrayRef statuses) {
            NSLog(@"Targeted media command completed with status %u", error);
            if (!error && command<2) [weakSelf.playbackBook commit:bundle playing:command==0];
            weakSelf.commandPending = NO;
            [weakSelf refresh];
        });
        if (!queued) self.commandPending = NO;
        // Recover if this private API omits its callback.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ weakSelf.commandPending = NO; });
    }
}
- (void)updateBrowserService:(BOOL)force {
    if (self.browserLookupPending || ![NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].count) return;
    if (!force && self.browserLookupDate && -self.browserLookupDate.timeIntervalSinceNow < 3) return;
    self.browserLookupPending = YES;
    self.browserLookupDate = [NSDate date];
    __weak AppDelegate *weakSelf = self;
    pid_t mediaPID = [CurrentPlayerBundle() isEqualToString:@"com.apple.Safari"] ? SafariMediaPID() : 0;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSString *url = ReadSafariURL(mediaPID);
        NSString *service = ServiceForURL(url);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.browserLookupPending = NO;
            weakSelf.browserService = service;
            weakSelf.browserURL = url;
            [weakSelf loadSiteIcon:url];
            if (service) {
                [NSUserDefaults.standardUserDefaults setObject:service forKey:@"LastBrowserService"];
                if ([NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.Safari"]) weakSelf.lastPlayer = @"com.apple.Safari";
            }
            [weakSelf refresh];
        });
    });
}
- (void)loadSiteIcon:(NSString *)url {
    if(![url isKindOfClass:NSString.class] || !url.length) return;
    NSURLComponents *page = [NSURLComponents componentsWithString:url];
    NSString *host = page.host.lowercaseString;
    if (!host.length || self.siteIcons[host] || ServiceIcon(ServiceForURL(url))) return;
    self.siteIcons[host] = NSNull.null;
    // Fetch from the playing site's own origin, without sending the page URL
    // or browsing history to a third-party favicon service.
    NSURLComponents *origin = [NSURLComponents new];
    origin.scheme = @"https"; origin.host = host; origin.path = @"/favicon.ico";
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 5;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    __weak AppDelegate *weakSelf = self;
    [[session dataTaskWithURL:origin.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSImage *image = !error && data.length < 1024*1024 ? [[NSImage alloc] initWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (image) { weakSelf.siteIcons[host] = image; [weakSelf refresh]; } });
        [session finishTasksAndInvalidate];
    }] resume];
}
- (void)pollPlayback {
    if (self.playbackPollPending) return;
    self.playbackPollPending=YES;
    NSRunningApplication *spotify=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"].firstObject;
    NSRunningApplication *live=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.ableton.live"].firstObject;
    NSRunningApplication *safari=[CurrentPlayerBundle() isEqualToString:@"com.apple.Safari"] ? [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].firstObject : nil;
    __weak AppDelegate *weakSelf=self;
    dispatch_async(ProviderQueue(), ^{
        NSInteger spotifyState=spotify && !spotify.terminated ? ReadSpotifyState(spotify.processIdentifier) : -1;
        NSInteger liveState=live && !live.terminated ? ReadAbletonState(live.processIdentifier) : -1;
        NSInteger safariState=safari && !safari.terminated ? ReadSafariState(safari.processIdentifier) : -1;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.playbackBook report:@"com.spotify.client" state:spotifyState];
            [weakSelf.playbackBook report:@"com.ableton.live" state:liveState];
            if([CurrentPlayerBundle() isEqualToString:@"com.apple.Safari"]) [weakSelf.playbackBook report:@"com.apple.Safari" state:safariState];
            if (!weakSelf.didPollProviders) {
                [weakSelf.playbackBook prefer:CurrentPlayerBundle()];
                weakSelf.didPollProviders=YES;
            }
            // Keep pending while refreshing to avoid an immediate polling loop.
            [weakSelf refresh];
            weakSelf.playbackPollPending=NO;
        });
    });
}
- (void)suppressNativeMediaTray {
    BOOL nativePresent=NO;
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.NowPlayingTouchUI"]) {
        if(app.terminated || ![app.bundleURL.path isEqualToString:@"/System/Library/CoreServices/NowPlayingTouchUI.app"]) continue;
        nativePresent=YES;
        NSNumber *pid=@(app.processIdentifier);
        if([self.nativeTrayTerminations containsObject:pid]) continue;
        // This process provides only Apple's Touch Bar media UI. MediaRemote,
        // Safari, Spotify and the audio service continue running.
        if(kill(app.processIdentifier,SIGTERM)==0) {
            [self.nativeTrayTerminations addObject:pid]; self.nativeTrayNeedsReinstall=YES;
            NSLog(@"Suppressed native NowPlayingTouchUI tray provider (%@)",pid);
        }
    }
    if(!nativePresent && self.nativeTrayNeedsReinstall && self.item && !self.midiVisible && !self.appsVisible && !self.appsRequested) {
        NSTouchBarItem *active=self.appsOverlayTrayItem ?: self.item;
        NSString *identifier=self.appsOverlayTrayItem ? AppsTrayID : ItemID;
        [NSTouchBarItem removeSystemTrayItem:active];
        [NSTouchBarItem addSystemTrayItem:active]; SetPresence(identifier,YES);
        self.nativeTrayNeedsReinstall=NO; [self.nativeTrayTerminations removeAllObjects];
        NSLog(@"Restored Apps/Music tray ownership after native media UI exit.");
    }
}
- (void)refresh {
    [self suppressNativeMediaTray];
    if (self.item && !self.midiVisible && !self.appsVisible && !self.appsRequested) SetPresence(self.appsOverlayTrayItem ? AppsTrayID : ItemID, YES);

    NSString *current = CurrentPlayerBundle();
    NSDictionary *info = nil;
    @try { info = [RequestValue(@"localNowPlayingItem") valueForKey:@"nowPlayingInfo"]; } @catch (NSException *e) {}
    id rate=info[MediaKey("kMRMediaRemoteNowPlayingInfoPlaybackRate") ?: @"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    Class request=NSClassFromString(@"MRNowPlayingRequest");
    BOOL hasPlaying=current.length && [request respondsToSelector:NSSelectorFromString(@"localIsPlaying")];
    BOOL playing=hasPlaying && ((BOOL(*)(id,SEL))objc_msgSend)(request,NSSelectorFromString(@"localIsPlaying"));
    NSInteger mediaState=MediaSnapshotState(rate,info.count>0,hasPlaying,playing);
    // Browser controls and Spotify/Live providers are more authoritative than
    // MediaRemote's missing or cached default playback state.
    if(IsAllowedPlayer(current) && ![current isEqualToString:@"com.spotify.client"] && ![current isEqualToString:@"com.ableton.live"] && ![current isEqualToString:@"com.apple.Safari"]) [self.playbackBook report:current state:mediaState];
    if([current isEqualToString:@"com.apple.Safari"] && mediaState>=0 && [self.playbackBook state:current]<0) [self.playbackBook report:current state:mediaState];
    if(self.didObservePlayer && IsAllowedPlayer(current) && (![current isEqualToString:self.observedMediaPlayer] || (mediaState==1 && !self.observedPlaying))) self.lastPlayer=current;
    self.didObservePlayer=YES; self.observedMediaPlayer=current;
    if(mediaState>=0) self.observedPlaying=mediaState==1;
    NSString *bundle = [self selectedPlayer];
    if (IsAllowedPlayer(bundle)) {
        self.lastPlayer = bundle;
        [NSUserDefaults.standardUserDefaults setObject:bundle forKey:@"LastPlayer"];
    }
    NSRunningApplication *app = bundle ? [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject : nil;
    NSImage *icon = app.icon;
    if ([bundle isEqualToString:@"com.apple.Safari"]) {
        NSString *service = nil;
        NSString *pageURL = nil;
        for (id value in ([current isEqualToString:@"com.apple.Safari"] ? info.allValues : @[])) if ([value isKindOfClass:NSString.class]) {
            NSURLComponents *url = [NSURLComponents componentsWithString:value];
            if (([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"]) && url.host.length) { pageURL = value; service = ServiceForURL(value); break; }
        }
        pageURL = pageURL ?: self.browserURL;
        service = service ?: self.browserService;
        id favicon = self.siteIcons[(pageURL.length ? [NSURLComponents componentsWithString:pageURL].host.lowercaseString : nil) ?: @""];
        icon = ServiceIcon(service) ?: ([favicon isKindOfClass:NSImage.class] ? favicon : nil) ?: icon;
        if ([service isEqualToString:@"spotify"]) icon = [NSWorkspace.sharedWorkspace iconForFile:@"/Applications/Spotify.app"];
        [self loadSiteIcon:pageURL];
    }
    self.displayedPlayer = bundle;
    self.musicView.artwork = icon;
    NSInteger state=[self.playbackBook state:bundle];
    self.musicView.stopAction=[bundle isEqualToString:@"com.ableton.live"];
    self.musicView.nextAction=state<0 ? -1 : state==1 ? 1 : 0;
    [self.musicView updateIcon];
    if ([bundle isEqualToString:@"com.apple.Safari"] || [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.Safari"]) [self updateBrowserService:NO];
    [self pollPlayback];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    [NSApp terminate:nil];
    return NO;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.dockPanel close:nil];
    [self.dockLauncher.holdTimer invalidate];
    if (SetPresence && self.item) SetPresence(ItemID, NO);
    if(self.appsOverlayTrayItem) { SetPresence(AppsTrayID,NO); [NSTouchBarItem removeSystemTrayItem:self.appsOverlayTrayItem]; }
    [self sendApps:@"QUIT"];
    [self.appsInput.fileHandleForWriting closeFile];
    if (self.item && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) [NSTouchBarItem removeSystemTrayItem:self.item];

    if (self.notificationToken) [NSNotificationCenter.defaultCenter removeObserver:self.notificationToken];
    if (self.workspaceToken) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self.workspaceToken];
    [self.recoveryTimer invalidate];
    [self.nativeTrayTimer invalidate];
    [self.musicView.holdTimer invalidate];
    [self sendMidi:@"QUIT"];
    [self.midiInput.fileHandleForWriting closeFile];
}
@end

int main(int argc, const char *argv[]) {
    if(argc>1 && strcmp(argv[1],"--accessibility-status")==0) { printf("Accessibility: %s\n",AXIsProcessTrusted() ? "approved" : "not approved for this build"); return 0; }
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (argc > 1 && strcmp(argv[1], "--diagnose") == 0) {
            BOOL ready = LoadInterfaces();
            printf("Control Strip and media command interfaces: %s\n", ready ? "available" : "unavailable");
            printf("Current player: %s\n", [CurrentPlayerBundle() UTF8String] ?: "none");
            printf("Automatic player launching: disabled\n");
            printf("Ableton transport access: %s\n", AXIsProcessTrusted() ? "available" : "Accessibility permission needed");
            NSRunningApplication *spotify=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"].firstObject;
            NSRunningApplication *live=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.ableton.live"].firstObject;
            printf("Spotify state: %ld; Ableton state: %ld (1=playing, 0=paused/stopped, -1=unavailable)\n",(long)(spotify ? ReadSpotifyState(spotify.processIdentifier) : -1),(long)(live ? ReadAbletonState(live.processIdentifier) : -1));
            NSRunningApplication *safari=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].firstObject;
            printf("Safari player controls: %ld (1=playing, 0=paused, -1=unavailable)\n",(long)(safari ? ReadSafariState(safari.processIdentifier) : -1));
            if(safari) DiagnoseSafariSliders(safari.processIdentifier);
            printf("MIDI: bundled full engine, direct private pipe; no keyboard shortcut\n");
            return ready ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--youtube-restart-test") == 0) {
            LoadInterfaces();
            NSRunningApplication *safari=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].firstObject;
            if(![ServiceForURL(ReadSafariURL(SafariMediaPID())) isEqual:@"youtube"]) return 2;
            NSInteger result=SafariYouTubePreviousAction(safari.processIdentifier);
            if(result!=1) { printf("Restart test requires a video beyond three seconds (action %ld)\n",(long)result); return 2; }
            NSMutableDictionary *options=[NoLaunchOptions() mutableCopy];
            options[MediaKey("kMRMediaRemoteOptionPlaybackPosition") ?: @"kMRMediaRemoteOptionPlaybackPosition"]=@0;
            __block BOOL done=NO; __block uint32_t status=UINT32_MAX;
            BOOL queued=SendCommandToApp(24,(__bridge CFDictionaryRef)options,NULL,CFSTR("com.apple.Safari"),0,dispatch_get_main_queue(),^(uint32_t error,CFArrayRef statuses) { status=error; done=YES; NSLog(@"Seek handler statuses %@",(__bridge NSArray *)statuses); });
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
            while(queued && !done && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
            NSInteger after=SafariYouTubePreviousAction(safari.processIdentifier);
            printf("YouTube seek queued=%d status=%u; near beginning=%d\n",queued,status,after==0);
            DiagnoseSafariSliders(safari.processIdentifier);
            return queued && status==0 && after==0 ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
            __block NSInteger dockTaps=0,dockHolds=0;
            DockLauncher *launcher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,40,30)];
            launcher.performCommand=^(int command){ dockTaps++; };
            launcher.performHold=^{ dockHolds++; };
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher finishAt:NSMakePoint(20,15)];
            NSCAssert(dockTaps==1 && dockHolds==0,@"Apps tap opens only the app panel");
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher fireHold]; [launcher fireHold]; [launcher finishAt:NSMakePoint(20,15)];
            NSCAssert(dockTaps==1 && dockHolds==1,@"Desktop picker hold must run once without opening apps afterward");
            [launcher beginAt:NSMakePoint(20,15) identity:nil]; [launcher moveAt:NSMakePoint(35,15)]; [launcher fireHold]; [launcher finishAt:NSMakePoint(35,15)];
            NSCAssert(dockTaps==1 && dockHolds==1,@"Dragged apps button must not trigger a tap or hold");
            DockPanel *centerPanel=[DockPanel new];
            NSScrubber *centerScrubber=[[NSScrubber alloc] initWithFrame:NSMakeRect(0,0,660,30)];
            centerScrubber.dataSource=centerPanel; centerScrubber.scrubberLayout=[CenteredAppsLayout new];
            for(NSNumber *size in @[@1,@4,@9,@16]) {
                centerPanel.runningApps=[NSArray arrayWithObjects:(id __unsafe_unretained [16]){launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher,launcher} count:size.unsignedIntegerValue];
                NSScrubberLayout *layout=centerScrubber.scrubberLayout;
                NSRect first=[layout layoutAttributesForItemAtIndex:0].frame,last=[layout layoutAttributesForItemAtIndex:size.integerValue-1].frame;
                if(size.integerValue<=9) NSCAssert(fabs((NSMinX(first)+NSMaxX(last))/2-330)<.01,@"App rows remain centered after count changes");
                else NSCAssert(NSMaxX(last)>660 && NSMinX(first)==0,@"Overflow remains scrollable without losing first apps");
            }
            NSDictionary *folderFixture=@{@"persistent-others":@[@{@"tile-type":@"directory-tile",@"tile-data":@{@"file-data":@{@"_CFURLString":@"file:///tmp/Downloads/"}}},@{@"tile-type":@"url-tile",@"tile-data":@{@"file-data":@{@"_CFURLString":@"https://example.com"}}}]};
            NSCAssert(DockFolderURLs(folderFixture).count==1,@"Read only Dock folder tiles");
            NSSet *players = [NSSet setWithArray:@[@"com.spotify.client", @"com.apple.Safari", @"com.apple.Music"]];
            NSCAssert([ChoosePlayer(@"com.apple.Safari", @"com.apple.Safari", nil, players) isEqualToString:@"com.apple.Safari"], @"A newly observed browser must be selected");
            NSCAssert([ChoosePlayer(nil, @"com.spotify.client", nil, players) isEqualToString:@"com.spotify.client"], @"Reopened Spotify must be resumed");
            NSCAssert([ChoosePlayer(nil, @"com.spotify.client", @"com.spotify.client", players) isEqualToString:@"com.spotify.client"], @"Freshly opened Spotify must beat a stale browser session");
            NSCAssert(ChoosePlayer(@"com.apple.Music", @"com.apple.Music", nil, [NSSet setWithObject:@"com.apple.Music"]) == nil, @"Apple Music must never be selected");
            NSCAssert(ChoosePlayer(nil, @"com.spotify.client", nil, [NSSet set]) == nil, @"A closed player must not be launched");
            NSCAssert([NoLaunchOptions().allValues.firstObject boolValue], @"App launch fallback must be disabled");
            NSSet *dawPlayers = [players setByAddingObject:@"com.ableton.live"];
            NSCAssert([ChoosePlayer(@"com.spotify.client", @"com.ableton.live", nil, dawPlayers) isEqualToString:@"com.ableton.live"], @"Stale Spotify must not override recently used Ableton");
            NSCAssert([ChoosePlayer(@"com.spotify.client", @"com.spotify.client", nil, dawPlayers) isEqualToString:@"com.spotify.client"], @"Returning to Spotify must select Spotify");
            NSCAssert([ChoosePlayer(nil, @"com.ableton.live", nil, players) isEqualToString:@"com.spotify.client"], @"Closed Ableton must not receive transport commands");
            NSCAssert([CanonicalPlayerBundle(@"com.apple.WebKit.GPU",nil) isEqual:@"com.apple.Safari"],@"Safari GPU playback must report Safari transport state");
            NSCAssert([CanonicalPlayerBundle(@"com.apple.WebKit.WebContent",@"com.example.browser") isEqual:@"com.example.browser"],@"WebKit's reported parent must be preserved");
            NSCAssert(NSEqualSizes(IconWithAction(ServiceIcon(@"youtube"),-1,NO).size,NSMakeSize(34,20)),@"Unknown status retains an action alongside the source icon");
            NSCAssert(MediaSnapshotState(nil,NO,YES,NO)==-1,@"Missing metadata must not masquerade as paused");
            NSCAssert(MediaSnapshotState(@1,YES,YES,NO)==1,@"Positive playback rate survives a stale global paused flag");
            NSCAssert(SafariTransportLabelState(@"Pausa (k)")==1 && SafariTransportLabelState(@"Reproducir (k)")==0,@"YouTube transport labels reflect playing and paused");
            NSCAssert(YouTubeElapsedLabel(@"7 minutos 34 segundos de 17 minutos 6 segundos")==454 && YouTubeElapsedLabel(@"0 minutos 0 segundos de 17 minutos 6 segundos")==0 && YouTubeElapsedLabel(@"1:02 / 3:45")==62 && isnan(YouTubeElapsedLabel(@"100% volumen")),@"YouTube elapsed time must use the current-time control and exclude volume");
            NSCAssert(!ShouldRestartPrevious(0) && !ShouldRestartPrevious(3) && ShouldRestartPrevious(3.1) && !ShouldRestartPrevious(NAN),@"Previous restarts only beyond the opening three seconds");
            NSCAssert(IsYouTubeSeekSlider(@"Control deslizante de búsqueda") && IsYouTubeSeekSlider(@"Seek slider") && !IsYouTubeSeekSlider(@"Volumen"),@"Restart must never change volume");
            NSCAssert(SafariTransportLabelState(@"Play all")==-1,@"Recommendation controls must not change video state");
            PlaybackBook *browserBook=[PlaybackBook new]; [browserBook commit:@"com.apple.Safari" playing:YES];
            browserBook.sources[@"com.apple.Safari"][@"settle"]=[NSDate distantPast];
            for(NSInteger i=0;i<8;i++) [browserBook report:@"com.apple.Safari" state:MediaSnapshotState(nil,NO,YES,NO)];
            NSCAssert([browserBook state:@"com.apple.Safari"]==1,@"Missing snapshots after the settle window cannot undo confirmed Play");
            [browserBook report:@"com.apple.Safari" state:SafariTransportLabelState(@"Reproducir (k)")];
            NSCAssert([browserBook state:@"com.apple.Safari"]==0,@"A real YouTube pause must still update the action");
            NSCAssert(ServiceForURL(nil)==nil && ServiceForURL(@"")==nil,@"Missing Safari URL must be safe during startup and media handover");
            NSCAssert([ServiceForURL(@"https://www.youtube.com/watch?v=123") isEqualToString:@"youtube"], @"YouTube tab must use YouTube icon");
            NSCAssert([ServiceForURL(@"https://www.netflix.com/watch/123") isEqualToString:@"netflix"], @"Netflix tab must use Netflix icon");
            NSCAssert(ServiceForURL(@"https://youtube.com.example.org/") == nil, @"Unrelated domains must not be branded as YouTube");
            NSCAssert(IsTextRole(@"AXTextField") && !IsTextRole(@"AXButton"), @"Ableton text edits must be protected");
            NSCAssert(ServiceIcon(@"youtube") && ServiceIcon(@"netflix"), @"Service icons must render");
            NSCAssert(AbletonDesiredState(1,-1)==0 && AbletonDesiredState(0,-1)==1,@"Ableton toggle must alternate its separate stop and play actions");
            NSCAssert(AbletonDesiredState(1,0)==0 && AbletonDesiredState(0,1)==1,@"Explicit Ableton actions must retain their transport direction");
            NSCAssert(IconWithAction(ServiceIcon(@"youtube"),1,YES),@"Stop icon must render");
            PlaybackBook *book=[PlaybackBook new];
            [book report:@"com.spotify.client" state:1]; [book report:@"com.apple.Safari" state:1];
            NSCAssert([[book target:players fallback:@"com.spotify.client"] isEqualToString:@"com.apple.Safari"],@"Most recent playing source must be paused first");
            [book commit:@"com.apple.Safari" playing:NO];
            [book report:@"com.apple.Safari" state:1];
            NSCAssert([book state:@"com.apple.Safari"]==0,@"A stale observation during command completion must not undo pause");
            NSCAssert([[book target:players fallback:@"com.apple.Safari"] isEqualToString:@"com.spotify.client"],@"After pausing Safari, hand off to still-playing Spotify");
            [book commit:@"com.spotify.client" playing:NO];
            NSCAssert([[book target:players fallback:@"com.spotify.client"] isEqualToString:@"com.spotify.client"] && [book state:@"com.spotify.client"]==0,@"After both pause, the next action must be play");
            [book commit:@"com.apple.Safari" playing:YES];
            NSCAssert([[book target:players fallback:@"com.spotify.client"] isEqualToString:@"com.apple.Safari"],@"Resuming a source must move it to the front");
            NSCAssert([[book target:[NSSet setWithObject:@"com.spotify.client"] fallback:@"com.spotify.client"] isEqualToString:@"com.spotify.client"],@"Closed sources must never win");
            NSCAssert([book state:@"com.apple.Safari"]==-1,@"Exited sessions must lose their stale playback state");
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
            puts("Passed: multi-source pause/handoff/resume; stale-state protection; hold-once, swipe/cancel/release handling; player routing and Apple Music exclusion. No media or MIDI actions sent.");
            return 0;
        }
        NSApplication *app = StripApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if(argc>1 && strcmp(argv[1],"--apps-helper")==0) {
            AppsTrayDelegate *apps=[AppsTrayDelegate new]; app.delegate=apps; [app run]; return 0;
        }
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        if(argc>1 && strcmp(argv[1],"--apps-swipe-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; [delegate.dockPanel activateEntry:delegate.dockPanel.runningApps[0]]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; DockSwipeGesture *gesture=panel.appSwipeRecognizer;
                NSView *icon=[panel.appsScrubber itemViewForItemAtIndex:1]; NSCAssert(icon,@"Apps icon is mounted");
                NSPoint start=[icon convertPoint:NSMakePoint(NSMidX(icon.bounds),15) toView:panel.appsScrubber];
                [gesture beginAt:start identity:nil]; [gesture moveAt:NSMakePoint(start.x+20,15)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,13*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; NSCAssert(panel.swipeChooser && !panel.swipeChooser.windowChoices && panel.swipeChooser.choices.count>3,@"Apps swipe shows installed applications");
                [panel.appSwipeRecognizer moveAt:NSMakePoint(NSWidth(panel.swipeChooser.bounds)-1,15)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; NSCAssert(panel.swipeChooser.offset>100,@"Stationary finger at right edge scrolls choices");
                NSLog(@"Swipe capture: APPS; count=%lu offset=%.1f selected=%ld",(unsigned long)panel.swipeChooser.choices.count,panel.swipeChooser.offset,(long)panel.swipeChooser.selectedIndex);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; [panel.appSwipeRecognizer cancelTracking]; NSCAssert(!panel.swipeChooser,@"Cancellation restores app row");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,18*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; DockSwipeGesture *gesture=panel.appSwipeRecognizer;
                NSView *icon=[panel.appsScrubber itemViewForItemAtIndex:0]; NSPoint start=[icon convertPoint:NSMakePoint(NSMidX(icon.bounds),15) toView:panel.appsScrubber];
                [gesture beginAt:start identity:nil]; [gesture moveAt:NSMakePoint(start.x+20,15)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; NSCAssert(panel.swipeChooser.windowChoices,@"Running app swipe shows window choices");
                NSLog(@"Swipe capture: WINDOWS; trusted=%d count=%lu",AXIsProcessTrusted(),(unsigned long)panel.swipeChooser.choices.count);
                if(AXIsProcessTrusted()) NSCAssert(panel.swipeChooser.choices.count>0,@"Finder windows available for selection");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                DockPanel *panel=delegate.dockPanel; NSPoint point=NSMakePoint([panel.swipeChooser origin]+[panel.swipeChooser pitch]/2,15);
                [panel.appSwipeRecognizer moveAt:point]; [panel.appSwipeRecognizer endAt:point];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.dockPanel.visible && !delegate.dockPanel.swipeChooser,@"Lift restores persistent running-app row");
                NSLog(@"Swipe capture: RESTORED");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,27*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"HIDE"]; NSLog(@"Passed Touch Bar app/window swipes, edge scrolling and lift selection"); [NSApp terminate:nil]; });
        }
        if(argc>1 && strcmp(argv[1],"--finder-reopen-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate.dockPanel activateEntry:delegate.dockPanel.runningApps[0]]; });
            for(NSNumber *second in @[@14,@19]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,second.integerValue*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSRunningApplication *finder=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject;
                NSCAssert([NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.finder"],@"Finder tap brings Finder forward");
                NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
                NSInteger count=0;
                for(NSDictionary *window in windows) if([window[(id)kCGWindowOwnerPID] intValue]==finder.processIdentifier && [window[(id)kCGWindowLayer] intValue]==0) count++;
                NSCAssert(count>0,@"Finder tap restores or opens a visible Finder window");
                NSCAssert(delegate.dockPanel.visible && delegate.dockPanel.appsScrubber.window,@"Finder keeps the Apps Touch Bar visible");
                NSLog(@"Finder capture: %@; visible windows=%ld",second.integerValue==14 ? @"OPEN" : @"REOPENED",(long)count);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate.dockPanel activateEntry:delegate.dockPanel.runningApps[0]]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"HIDE"]; NSLog(@"Passed Finder reopen and persistent Apps Touch Bar"); [NSApp terminate:nil]; });
        }
        if(argc>1 && strcmp(argv[1],"--apps-launcher-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
                [delegate.dockPanel activateEntry:delegate.dockPanel.runningApps[1]];
                NSLog(@"Applications folder dispatch took %.3f seconds",NSProcessInfo.processInfo.systemUptime-start);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert([NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.finder"],@"Apps icon opens Finder");
                NSCAssert(delegate.dockPanel.visible && delegate.dockPanel.appsScrubber.window,@"Apps row remains mounted while Applications is open");
                NSLog(@"Launcher capture: OPEN");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate.dockPanel activateEntry:delegate.dockPanel.runningApps[1]];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,19*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Launcher capture: REOPENED"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.dockPanel.visible && delegate.dockLauncher.panelOpen,@"Opening Applications retains apps panel");
                [delegate sendApps:@"HIDE"]; NSLog(@"Passed Applications in Finder with persistent Apps Touch Bar"); [NSApp terminate:nil];
            });
        }
        if(argc>1 && strcmp(argv[1],"--apps-persistence-smoke-test")==0) {
            __block NSRunningApplication *initialFront=NSWorkspace.sharedWorkspace.frontmostApplication;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSRunningApplication *finder=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject;
                [finder activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,13*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [initialFront activateWithOptions:NSApplicationActivateIgnoringOtherApps]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.dockPanel.visible && delegate.dockLauncher.panelOpen,@"Apps must persist across foreground-app changes");
                NSCAssert(!NSApp.active,@"The picker must not steal foreground-app focus");
                NSCAssert(delegate.dockPanel.appsScrubber.window!=nil,@"Apps overlay stays mounted across app switches");
                NSLog(@"Persistent apps snapshot: %@",[delegate.dockPanel snapshot]);
                NSLog(@"Apps toggle capture: READY");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,19*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate sendApps:@"TAP"];
                NSCAssert(!delegate.dockPanel.visible && !delegate.dockLauncher.panelOpen,@"Apps launcher explicitly closes the persistent picker");
                NSLog(@"Closed apps capture: READY");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate sendApps:@"TAP"]; NSCAssert(delegate.dockPanel.visible,@"Persistent apps can reopen");
                NSLog(@"Reopened apps capture: READY");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate sendApps:@"HIDE"]; [initialFront activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                NSLog(@"Passed app-switch persistence, no focus stealing, explicit close and reopen"); [NSApp terminate:nil];
            });
        }
        if(argc>1 && strcmp(argv[1],"--apps-toggle-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendMidi:@"HIDE"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; NSLog(@"Apps toggle capture: READY"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                // Another foreground app may legitimately dismiss the application bar during a live test.
                if(!delegate.dockPanel.visible) {
                    NSCAssert(!NSApp.active,@"Picker may close automatically only after the app loses focus");
                    [delegate sendApps:@"TAP"];
                }
                NSCAssert(delegate.dockPanel.visible && delegate.dockLauncher.panelOpen,@"Apps tap must open picker and change launcher to close");
                NSLog(@"Apps full-width snapshot: %@",[delegate.dockPanel snapshot]);
                NSScrubber *scrubber=delegate.dockPanel.appsScrubber;
                CGFloat rootWidth=NSWidth(scrubber.window.contentView.bounds);
                if(rootWidth>16) {
                    CGFloat viewport=NSWidth(scrubber.bounds);
                    NSCAssert(fabs(viewport-(rootWidth-16))<1,@"App viewport fills the area beside the Control Strip");
                    NSArray *actualApps=delegate.dockPanel.runningApps;
                    if(actualApps.count) for(NSNumber *number in @[@1,@4,@9,@16]) {
                        NSMutableArray *fixture=[NSMutableArray new];
                        for(NSInteger i=0;i<number.integerValue;i++) [fixture addObject:actualApps[i%actualApps.count]];
                        delegate.dockPanel.runningApps=fixture;
                        NSScrubberLayout *layout=scrubber.scrubberLayout;
                        NSRect first=[layout layoutAttributesForItemAtIndex:0].frame,last=[layout layoutAttributesForItemAtIndex:fixture.count-1].frame;
                        CGFloat content=fixture.count*52-12;
                        if(content<=viewport) {
                            CGFloat target=[(StripAppsScrubber *)scrubber visualCenterX];
                            CGFloat fitted=MIN(MAX(content/2,target),viewport-content/2);
                            NSCAssert(fabs((NSMinX(first)+NSMaxX(last))/2-fitted)<.01,@"App rows follow the native visual center without clipping");
                        }
                        else NSCAssert(NSMinX(first)==0 && NSMaxX(last)>viewport && layout.scrubberContentSize.width>=content,@"Large app rows use the full viewport and scroll for overflow");
                        NSCAssert(NSWidth(scrubber.bounds)==viewport,@"App count must never shrink the viewport");
                    }
                    delegate.dockPanel.runningApps=actualApps;
                    NSLog(@"Passed full available width, native-centered app counts 1/4/9 and 16-app overflow");
                }
                NSCAssert([delegate.dockPanel.bar.itemIdentifiers isEqual:@[DockAppsID]],@"Apps overlay has no extra close items");
                [delegate sendApps:@"TAP"];
                NSCAssert(!delegate.dockPanel.visible && !delegate.dockLauncher.panelOpen,@"Second tap closes picker and restores app glyph");
                [delegate sendApps:@"TAP"];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,18*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                if(!delegate.dockPanel.visible) {
                    NSCAssert(!NSApp.active,@"A reopened picker closes only when another app activates");
                    [delegate sendApps:@"TAP"];
                }
                NSCAssert(delegate.dockPanel.visible,@"Apps can reopen after toggle");
                [delegate sendApps:@"HIDE"]; NSLog(@"Passed apps overlay, launcher close glyph, toggle and reopen"); [NSApp terminate:nil];
            });
        }
        if(argc>1 && strcmp(argv[1],"--dock-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendMidi:@"HIDE"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Capture baseline: READY"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSLog(@"Dock snapshot: %@",delegate.appsStatus);
                NSCAssert(delegate.appsVisible && [delegate.appsStatus[@"visible"] boolValue],@"Apps button presents native overlay");
                NSCAssert([delegate.appsStatus[@"buttonWidth"] doubleValue]==14 && delegate.musicView.frame.size.width==54,@"Both launchers fit the native tray slot");
                NSCAssert(([delegate.appsStatus[@"layout"] isEqual:@[DockAppsID]]),@"Centered apps; close through the persistent launcher");
                [delegate openMidi];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,21*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.midiVisible && !delegate.appsVisible,@"MIDI replaces overlay cleanly"); [delegate sendApps:@"TAP"];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(delegate.appsVisible && !delegate.midiVisible,@"Apps replaces MIDI cleanly");
                [delegate sendApps:@"HIDE"]; NSLog(@"Passed native Apps overlay, sizes and MIDI transitions"); [NSApp terminate:nil];
            });
        }
        if(argc>1 && strcmp(argv[1],"--browser-state-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendMidi:@"HIDE"]; });
            for(NSNumber *second in @[@10,@15,@21]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,second.integerValue*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    NSRunningApplication *safari=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].firstObject;
                    NSInteger actual=safari ? ReadSafariState(safari.processIdentifier) : -1;
                    NSInteger tracked=[delegate.playbackBook state:@"com.apple.Safari"];
                    NSLog(@"Browser stability at %@s: actual %ld, tracked %ld, next action %ld",second,(long)actual,(long)tracked,(long)delegate.musicView.nextAction);
                    if(actual==1) NSCAssert(tracked==1,@"Playing YouTube cannot revert to a paused tracker after the settle window");
                    if(actual==1 && [delegate.displayedPlayer isEqual:@"com.apple.Safari"]) NSCAssert(delegate.musicView.nextAction==1,@"The next action must remain Pause while YouTube is playing");
                    if(second.integerValue==21) NSLog(@"Browser stability: CAPTURE");
                });
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,24*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Passed sustained browser playback tracking"); [NSApp terminate:nil]; });
        }
        if(argc>1 && strcmp(argv[1],"--native-media-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendMidi:@"HIDE"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Native media takeover test: READY"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,13*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert(![NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.NowPlayingTouchUI"].count,@"Native Touch Bar media provider must be suppressed");
                NSCAssert(!delegate.nativeTrayNeedsReinstall,@"Apps/Music tray ownership must be restored");
                NSLog(@"Native media takeover test: CAPTURE");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Passed native Touch Bar takeover suppression"); [NSApp terminate:nil]; });
        }
        if(argc>1 && strcmp(argv[1],"--desktop-smoke-test")==0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendMidi:@"HIDE"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,9*NSEC_PER_SEC),dispatch_get_main_queue(),^{ NSLog(@"Capture launcher: READY"); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,11*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                [delegate.dockLauncher beginAt:NSMakePoint(7,15) identity:nil]; [delegate.dockLauncher fireHold]; [delegate.dockLauncher finishAt:NSMakePoint(7,15)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,14*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSLog(@"Desktop snapshot: %@",delegate.appsStatus);
                NSCAssert(delegate.appsVisible && [delegate.appsStatus[@"mode"] isEqual:@"desktops"] && [delegate.appsStatus[@"spaces"] count]>0,@"Hold opens real Touch Bar desktops");
                NSCAssert([delegate.appsStatus[@"centerError"] doubleValue]<.01,@"Desktop row is centered");
                NSLog(@"Capture desktops: READY"); [delegate sendApps:@"SHOW"];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSLog(@"Apps snapshot: %@",delegate.appsStatus);
                NSCAssert([delegate.appsStatus[@"mode"] isEqual:@"apps"] && [delegate.appsStatus[@"centerError"] doubleValue]<.01,@"Apps row is centered");
                NSCAssert(([delegate.appsStatus[@"layout"] isEqual:@[DockAppsID]]),@"No folder or Trash items");
                NSLog(@"Capture apps: READY");
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"HIDE"]; NSLog(@"Passed desktop hold, centered apps and no folders/Trash"); [NSApp terminate:nil]; });
        }
        if(argc>1 && strcmp(argv[1],"--folder-smoke-test")==0) {
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [NSFileManager.defaultManager createDirectoryAtPath:[path stringByAppendingPathComponent:@"Subfolder"] withIntermediateDirectories:YES attributes:nil error:nil];
            [@"fixture" writeToFile:[path stringByAppendingPathComponent:@"Example.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [@"nested fixture" writeToFile:[path stringByAppendingPathComponent:@"Subfolder/Nested.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,7*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"TAP"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:[@"FOLDER " stringByAppendingString:path]]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSLog(@"Folder capture: READY %@",delegate.appsStatus);
                NSCAssert([delegate.appsStatus[@"folderReady"] boolValue] && [delegate.appsStatus[@"folderCount"] intValue]==2,@"Pock interface loaded with names/types and count");
                [delegate sendApps:[@"FOLDER " stringByAppendingString:[path stringByAppendingPathComponent:@"Subfolder"]]];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,21*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,23*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert([delegate.appsStatus[@"folderDepth"] intValue]==2 && [delegate.appsStatus[@"folderCount"] intValue]==1,@"Nested folder navigation"); [delegate sendApps:@"BACK"];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,27*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,29*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                NSCAssert([delegate.appsStatus[@"folderDepth"] intValue]==1 && [delegate.appsStatus[@"folderCount"] intValue]==2,@"Back returns to parent"); [delegate sendApps:@"ROOT"];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,31*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [delegate sendApps:@"HIDE"]; [NSFileManager.defaultManager removeItemAtPath:path error:nil]; NSLog(@"Passed original Pock folder layout, thumbnails, names/types, count, nested Back and root close"); [NSApp terminate:nil]; });
        }
        if (argc > 1 && strcmp(argv[1], "--smoke-test") == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSLog(@"Smoke test complete; removing item and quitting.");
                [NSApp terminate:nil];
            });
        }
        if (argc > 1 && strcmp(argv[1], "--midi-smoke-test") == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [delegate.musicView beginAt:NSMakePoint(30, 10) identity:nil]; [delegate.musicView fireHold]; [delegate.musicView finishAt:NSMakePoint(30, 10)]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NSCAssert(delegate.midiReady && delegate.midiVisible, @"Long hold must directly open bundled MIDI engine"); [delegate sendMidi:@"STATUS"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NSCAssert(delegate.midiResolvedItems > 0, @"MIDI must resolve a real configured layout"); [delegate sendMidi:@"HIDE"]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 14 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NSCAssert(delegate.midiReady && !delegate.midiVisible, @"Closing MIDI must return to music mode"); NSLog(@"Passed bundled MIDI show/close integration test"); [NSApp terminate:nil]; });
        }
        [app run];
    }
    return 0;
}
