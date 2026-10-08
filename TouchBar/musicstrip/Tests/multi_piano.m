#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
static void TestFlexiblePianoWidths(NSInteger count) {
    Class pianoClass=NSClassFromString(@"pianoView");
    if(!pianoClass) { pianoClass=objc_allocateClassPair(NSView.class,"pianoView",0); objc_registerClassPair(pianoClass); }
    NSTouchBar *bar=[NSTouchBar new];
    NSArray *ids=[@[NativePianoID,SecondPianoID,ThirdPianoID] subarrayWithRange:NSMakeRange(0,count)];
    bar.defaultItemIdentifiers=ids;
    NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,30) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    host.releasedWhenClosed=NO;
    NSMutableArray *items=[NSMutableArray new], *views=[NSMutableArray new];
    NSView *previous=nil;
    for(NSString *identifier in ids) {
        NSView *view=[[pianoClass alloc] initWithFrame:NSMakeRect(0,0,80,30)];
        view.translatesAutoresizingMaskIntoConstraints=NO;
        [view.widthAnchor constraintGreaterThanOrEqualToConstant:400].active=YES;
        [host.contentView addSubview:view];
        [view.leadingAnchor constraintEqualToAnchor:previous ? previous.trailingAnchor : host.contentView.leadingAnchor].active=YES;
        [view.topAnchor constraintEqualToAnchor:host.contentView.topAnchor].active=YES;
        [view.heightAnchor constraintEqualToConstant:30].active=YES;
        NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier]; item.view=view;
        [items addObject:item]; [views addObject:view]; previous=view;
    }
    [previous.trailingAnchor constraintEqualToAnchor:host.contentView.trailingAnchor].active=YES;
    bar.templateItems=[NSSet setWithArray:items]; SizePianos(bar);
    NSArray *firstConstraints=objc_getAssociatedObject(bar,&pianoEqualWidthsKey);
    for(NSInteger pass=0;pass<20;pass++) SizePianos(bar);
    NSCAssert(firstConstraints==objc_getAssociatedObject(bar,&pianoEqualWidthsKey),@"Repeated refreshes must retain the exact equal-width constraints instead of rebuilding the visible layout");
    for(NSNumber *available in @[@600,@900]) {
        [host setContentSize:NSMakeSize(available.doubleValue,30)]; [host.contentView layoutSubtreeIfNeeded];
        for(NSView *view in views) NSCAssert(fabs(view.bounds.size.width-available.doubleValue/count)<.1,@"Two or three keyboards must divide all available width equally, including after resizing");
    }
    [NSLayoutConstraint deactivateConstraints:objc_getAssociatedObject(bar,&pianoEqualWidthsKey)];
    bar.defaultItemIdentifiers=@[NativePianoID]; SizePianos(bar);
    NSArray *minimums=objc_getAssociatedObject(views.firstObject,&pianoNativeMinimumKey);
    NSCAssert([minimums.firstObject[0] constant]==400 && ![objc_getAssociatedObject(views.firstObject,&pianoCompactWidthKey) isActive],@"Returning to one piano must restore the original minimum and unconstrained expansion");
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
        NSTouchBar *bar=[NSTouchBar new];
        bar.customizationIdentifier=[@"local.musicstrip.test." stringByAppendingString:NSUUID.UUID.UUIDString];
        bar.customizationAllowedItemIdentifiers=@[NativePianoID,SecondPianoID,ThirdPianoID,@"pad1"];
        NSMutableArray *items=[NSMutableArray arrayWithObject:@"pad1"];
        for(NSString *expected in @[NativePianoID,SecondPianoID,ThirdPianoID]) {
            NSString *slot=NextPianoSlot(items);
            NSCAssert([slot isEqual:expected],@"Repeated use of one Piano tile must allocate distinct native instances");
            [items addObject:slot];
        }
        NSCAssert([NextPianoSlot(items) isEqual:NativePianoID],@"All occupied slots must never invent a fourth keyboard ID");
        [items removeObject:SecondPianoID];
        NSCAssert([NextPianoSlot(items) isEqual:SecondPianoID],@"A removed slot becomes reusable");
        customizationBar=bar; priorAllowedItems=bar.customizationAllowedItemIdentifiers;
        bar.defaultItemIdentifiers=@[NativePianoID,@"pad1"];
        RefreshNativePianoPalette();
        NSCAssert(([bar.customizationAllowedItemIdentifiers isEqual:@[SecondPianoID,@"pad1"]]),@"Native palette must show exactly one Piano tile, plus existing non-piano controls");
        bar.defaultItemIdentifiers=@[NativePianoID,SecondPianoID,@"pad1"];
        RefreshNativePianoPalette();
        NSCAssert(([bar.customizationAllowedItemIdentifiers isEqual:@[ThirdPianoID,@"pad1"]]),@"The same tile must advance to the third independent instance");
        bar.defaultItemIdentifiers=@[NativePianoID,@"pad1"];
        RefreshNativePianoPalette(); layoutBeforePianoDrag=bar.itemIdentifiers.copy;
        CompleteNativePianoDrag();
        NSCAssert(layoutBeforePianoDrag!=nil,@"An early drag-end callback must retain the pre-drop snapshot until the native layout commits");
        bar.defaultItemIdentifiers=@[NativePianoID,SecondPianoID,@"pad1"];
        PollNativePianoPalette();
        NSCAssert(([bar.customizationAllowedItemIdentifiers isEqual:@[ThirdPianoID,@"pad1"]]),@"A late native commit must offer the third piano without reopening customization");
        customizationBar=nil; priorAllowedItems=nil;
        NSArray *original=@[NativePianoID,@"pad1"];
        NSCAssert(([PreserveLayoutOnPianoAddition(original,@[SecondPianoID]) isEqual:@[NativePianoID,@"pad1",SecondPianoID]]),@"Native replacement drop must preserve existing keyboard and controls");
        NSArray *two=@[NativePianoID,SecondPianoID,@"pad1"];
        NSCAssert(([PreserveLayoutOnPianoAddition(two,@[ThirdPianoID]) isEqual:@[NativePianoID,SecondPianoID,@"pad1",ThirdPianoID]]),@"Adding a third keyboard must preserve both existing mappings");
        NSCAssert(([PreserveLayoutOnPianoAddition(two,@[NativePianoID,@"pad1"]) isEqual:@[NativePianoID,@"pad1"]]),@"Explicit removal must remain possible");
        NSCAssert(([PreserveLayoutOnPianoAddition(two,@[SecondPianoID,NativePianoID,@"pad1"]) isEqual:@[SecondPianoID,NativePianoID,@"pad1"]]),@"Reordering must not be undone");
        id nativeConfig=[bar valueForKey:@"configuration"];
        ((void(*)(id,SEL,id))objc_msgSend)(nativeConfig,NSSelectorFromString(@"_setCustomizedItemIdentifiers:"),@[SecondPianoID]);
        customizationBar=bar; layoutBeforePianoDrag=original;
        CompleteNativePianoDrag();
        NSCAssert(([bar.itemIdentifiers isEqual:@[NativePianoID,@"pad1",SecondPianoID]]),@"Native AppKit configuration must retain both actual piano identifiers after replacement");
        customizationBar=nil;
        NSString *layoutKey=[@"NSTouchBarConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"]];
        SaveInstanceSettings(bar,SecondPianoID,@{@"channel":@7,@"octaves":@1,@"startOctave":@3});
        SaveInstanceSettings(bar,ThirdPianoID,@{@"channel":@12,@"octaves":@2,@"startOctave":@5});
        NSCAssert([InstanceSettings(bar,SecondPianoID)[@"channel"] intValue]==7 && [InstanceSettings(bar,ThirdPianoID)[@"channel"] intValue]==12,@"Saved MIDI channels must remain independent");
        NSTouchBar *reopened=[NSTouchBar new]; reopened.customizationIdentifier=bar.customizationIdentifier;
        NSCAssert([InstanceSettings(reopened,SecondPianoID)[@"channel"] intValue]==7,@"Independent mapping must survive bar recreation");
        NSCAssert(([[NSUserDefaults.standardUserDefaults dictionaryForKey:layoutKey][@"CurrentItems"] isEqual:@[NativePianoID,@"pad1",SecondPianoID]]),@"AppKit must persist the repaired multi-piano layout, not the replacement");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:layoutKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:PianoPrefsKey(bar)];
        TestFlexiblePianoWidths(2); TestFlexiblePianoWidths(3);
        puts("Passed late-drop third-slot refresh, equal expanding two/three-piano layouts, native replacement repair and persistence, removal/reorder and independent MIDI mappings. No user layouts or MIDI changed.");
    }
    return 0;
}
