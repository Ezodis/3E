#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DockPanel *panel=[DockPanel new]; panel.visible=YES;
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,800,30)];
    DockSwipeChooser *chooser=[[DockSwipeChooser alloc] initWithFrame:host.bounds];
    chooser.windowChoices=YES; chooser.choices=@[]; chooser.selectedIndex=-1;
    chooser.windowQueryPending=YES;
    [host addSubview:chooser]; panel.swipeChooser=chooser;
    [panel finishSwipeCancelled:NO];
    NSCAssert(panel.swipeChooser==chooser && chooser.superview==host && chooser.awaitingSelection,@"Lifting before the window response must retain the actual chooser");
    DockSwipeChoice *one=[DockSwipeChoice new],*two=[DockSwipeChoice new];
    one.title=@"Same window title"; two.title=one.title;
    [panel completeWindowLoad:@[one,two] chooser:chooser finished:YES];
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
    NSCAssert(panel.swipeChooser==chooser,@"Intermediate retries must still allow real windows to arrive");
    [panel completeWindowLoad:@[] chooser:chooser finished:YES];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Final empty response after a lift must restore apps automatically");
    [panel completeWindowLoad:@[one,two] chooser:chooser finished:YES];
    NSCAssert(!panel.swipeChooser,@"Stale callbacks must never reopen a dismissed picker");
    panel.swipeChooser=chooser; chooser.awaitingSelection=NO; chooser.windowQueryPending=YES; [host addSubview:chooser];
    [panel completeWindowLoad:@[] chooser:chooser finished:YES];
    NSCAssert(panel.swipeChooser==chooser,@"While the finger is still down, show the actual empty result");
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser,@"Lifting after an empty response must restore apps");
    panel.swipeChooser=chooser; chooser.choices=@[]; chooser.selectedIndex=-1; [host addSubview:chooser];
    [panel finishSwipeCancelled:YES];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Cancel or close must dismiss even an empty retained chooser");
    puts("Passed empty-on-release dismissal, late empty completion, retry retention, real-window selection, stale callbacks and cancellation. No cross-app actions sent.");
} return 0; }
