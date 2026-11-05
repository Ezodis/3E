#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main

@interface CountingAppsScrubber : StripAppsScrubber
@property NSUInteger reloads;
@end
@implementation CountingAppsScrubber
- (void)reloadData { self.reloads++; [super reloadData]; }
@end

@interface QuitTestApp : NSObject
@property (getter=isTerminated) BOOL terminated;
@property NSUInteger quits;
- (BOOL)terminate;
@end
@implementation QuitTestApp
- (BOOL)terminate { self.quits++;return YES; }
@end
@interface QuitTestPress : NSPressGestureRecognizer
@property NSGestureRecognizerState fixtureState;
@end
@implementation QuitTestPress
- (NSGestureRecognizerState)state { return self.fixtureState; }
@end

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DockPanel *quitPanel=[DockPanel new];QuitTestApp *app=[QuitTestApp new];QuitTestPress *press=[QuitTestPress new];quitPanel.appHoldRecognizer=press;
    quitPanel.heldApplication=(id)app;press.fixtureState=NSGestureRecognizerStateBegan;[quitPanel holdApp:press];
    for(NSUInteger tick=0;tick<10;tick++){press.fixtureState=NSGestureRecognizerStateChanged;[quitPanel holdApp:press];}
    NSCAssert(!app.quits && quitPanel.appQuitArmed,@"Holding, however long, only arms quit");
    press.fixtureState=NSGestureRecognizerStateEnded;[quitPanel holdApp:press];[quitPanel holdApp:press];
    NSCAssert(app.quits==1 && !quitPanel.appQuitArmed && !quitPanel.heldApplication,@"Release dispatches one normal quit and consumes the held target");
    for(NSNumber *state in @[@(NSGestureRecognizerStateCancelled),@(NSGestureRecognizerStateFailed)]) {
        quitPanel.heldApplication=(id)app;press.fixtureState=NSGestureRecognizerStateBegan;[quitPanel holdApp:press];
        press.fixtureState=state.integerValue;[quitPanel holdApp:press];press.fixtureState=NSGestureRecognizerStateEnded;[quitPanel holdApp:press];
    }
    NSCAssert(app.quits==1,@"Cancelled or failed holds never quit on a later release");
    quitPanel.heldApplication=(id)app;press.fixtureState=NSGestureRecognizerStateEnded;[quitPanel holdApp:press];
    NSCAssert(app.quits==1,@"A short tap cannot quit without an armed hold");
    quitPanel.heldApplication=(id)app;press.fixtureState=NSGestureRecognizerStateBegan;[quitPanel holdApp:press];[quitPanel close:nil];
    press.fixtureState=NSGestureRecognizerStateEnded;[quitPanel holdApp:press];NSCAssert(app.quits==1,@"Closing the app bar cancels an armed quit");
    DockPanel *panel=[DockPanel new]; panel.visible=YES;
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,800,30)];
    DockSwipeChooser *chooser=[[DockSwipeChooser alloc] initWithFrame:host.bounds];
    chooser.windowChoices=YES; chooser.choices=@[]; chooser.selectedIndex=-1;
    chooser.windowQueryPending=YES;
    [host addSubview:chooser]; panel.swipeChooser=chooser;
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Lifting before the window response immediately restores apps");
    [panel completeWindowLoad:@[] chooser:chooser finished:NO];
    NSCAssert(!panel.swipeChooser,@"Late retries cannot restore a cancelled picker");
    panel.swipeChooser=chooser; [host addSubview:chooser];
    DockSwipeChoice *one=[DockSwipeChoice new],*two=[DockSwipeChoice new];
    one.title=@"Same window title"; two.title=one.title;
    [panel completeWindowLoad:@[] chooser:chooser finished:NO];
    NSCAssert(chooser.hidden,@"Pending window lookups keep the app row visible");
    [panel completeWindowLoad:@[one,two] chooser:chooser finished:YES];
    NSCAssert(!chooser.hidden,@"Resolved windows become visible without a loading label");
    NSCAssert(chooser.choices.count==2,@"Distinct windows with identical titles must remain distinct");
    [chooser updateAt:NSMakePoint([chooser origin]+[chooser pitch]/2,15)];
    NSCAssert(chooser.selectedIndex==0,@"Late-arriving real choices remain selectable");
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Selecting a loaded choice restores the app row");
    panel.swipeChooser=chooser; chooser.choices=@[]; chooser.selectedIndex=-1;
    chooser.awaitingSelection=NO; chooser.windowQueryPending=NO; [host addSubview:chooser];
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Releasing a resolved empty picker must immediately restore apps");
    panel.swipeChooser=chooser; chooser.awaitingSelection=NO; chooser.windowQueryPending=YES; [host addSubview:chooser];
    [panel finishSwipeCancelled:NO];
    [panel completeWindowLoad:@[] chooser:chooser finished:NO];
    NSCAssert(!panel.swipeChooser,@"Intermediate retries cannot retain a released picker");
    [panel completeWindowLoad:@[] chooser:chooser finished:YES];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Final empty response after a lift must restore apps automatically");
    [panel completeWindowLoad:@[one,two] chooser:chooser finished:YES];
    NSCAssert(!panel.swipeChooser,@"Stale callbacks must never reopen a dismissed picker");
    panel.swipeChooser=chooser; chooser.awaitingSelection=NO; chooser.windowQueryPending=YES; [host addSubview:chooser];
    [panel completeWindowLoad:@[] chooser:chooser finished:YES];
    NSCAssert(panel.swipeChooser==chooser,@"While the finger is still down, show the actual empty result");
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser,@"Lifting after an empty response must restore apps");
    panel.swipeChooser=chooser; chooser.choices=@[one,two]; chooser.selectedIndex=-1; [host addSubview:chooser];
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Lifting outside loaded windows restores apps without selecting");
    panel.swipeChooser=chooser; chooser.choices=@[]; chooser.selectedIndex=-1; [host addSubview:chooser];
    [panel finishSwipeCancelled:YES];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Cancel or close must dismiss even an empty retained chooser");
    DockPanel *stable=[DockPanel new]; stable.visible=YES;
    stable.appsItem=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"test.apps"];
    [stable refresh];
    NSScrubber *original=stable.appsScrubber;
    id hold=stable.appHoldRecognizer, swipe=stable.appSwipeRecognizer;
    stable.signature=nil; [stable refresh];
    NSCAssert(stable.appsScrubber==original && stable.appsItem.view==original,@"App list changes retain the mounted scrubber");
    NSCAssert(stable.appHoldRecognizer==hold && stable.appSwipeRecognizer==swipe,@"Refresh preserves hold-to-quit and swipe recognizers");
    CountingAppsScrubber *counter=[[CountingAppsScrubber alloc] initWithFrame:NSMakeRect(0,0,800,30)];
    stable.appsScrubber=counter;
    [stable refresh]; [stable refreshFrontmost]; [stable refresh];
    NSCAssert(counter.reloads==0,@"Unchanged lists and app activation never reload cells");
    stable.signature=nil; [stable refresh];
    NSCAssert(counter.reloads==1 && stable.appsScrubber==counter,@"A changed list reloads once without replacing the view");
    puts("Passed empty-on-release dismissal, late empty completion, retry dismissal, real-window selection, stale callbacks and cancellation. No cross-app actions sent.");
} return 0; }
