#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DockPanel *panel=[DockPanel new]; panel.visible=YES;
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,800,30)];
    DockSwipeChooser *chooser=[[DockSwipeChooser alloc] initWithFrame:host.bounds];
    chooser.windowChoices=YES; chooser.choices=@[]; chooser.selectedIndex=-1;
    [host addSubview:chooser]; panel.swipeChooser=chooser;
    [panel finishSwipeCancelled:NO];
    NSCAssert(panel.swipeChooser==chooser && chooser.superview==host && chooser.awaitingSelection,@"Lifting before the window response must retain the actual chooser");
    DockSwipeChoice *one=[DockSwipeChoice new],*two=[DockSwipeChoice new];
    one.title=@"Same window title"; two.title=one.title;
    chooser.choices=@[one,two];
    NSCAssert(chooser.choices.count==2,@"Distinct windows with identical titles must remain distinct");
    [chooser updateAt:NSMakePoint([chooser origin]+[chooser pitch]/2,15)];
    NSCAssert(chooser.selectedIndex==0,@"Late-arriving real choices remain selectable");
    [panel finishSwipeCancelled:NO];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Selecting a loaded choice restores the app row");
    panel.swipeChooser=chooser; chooser.choices=@[]; chooser.selectedIndex=-1; [host addSubview:chooser];
    [panel finishSwipeCancelled:YES];
    NSCAssert(!panel.swipeChooser && !chooser.superview,@"Cancel or close must dismiss even an empty retained chooser");
    puts("Passed delayed-window lift retention, late choice selection, identical titles, and cancellation. No cross-app actions sent.");
} return 0; }
