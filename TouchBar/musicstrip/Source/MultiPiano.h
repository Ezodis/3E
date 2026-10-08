// Independent instances of the original pianoView; no alternate MIDI engine.
static NSString *const NativePianoID=@"ch.uebe.midi-touchbar.piano";
static NSString *const SecondPianoID=@"ch.uebe.midi-touchbar.piano2";
static NSString *const ThirdPianoID=@"ch.uebe.midi-touchbar.piano3";
static char pianoInstanceKey;
static IMP originalMakeItem, originalPianoTouched, originalExitCustomization;
static NSWindow *customizationWindow;
static NSTouchBar *customizationBar;
static BOOL finishingCustomization;
static NSTouchBar *priorApplicationBar;
static id nativeCustomizationController;
static char pianoCompactWidthKey;
static char pianoEqualWidthsKey;
static char pianoNativeMinimumKey;
static BOOL IsPianoSlot(NSString *identifier) {
    return [@[NativePianoID,SecondPianoID,ThirdPianoID] containsObject:identifier];
}
static NSInteger PianoCount(NSTouchBar *bar) {
    NSInteger count=0;
    for(NSString *identifier in bar.itemIdentifiers) if(IsPianoSlot(identifier)) count++;
    return count;
}
static void SuspendPianoSizing(NSTouchBar *bar) {
    NSArray *equal=objc_getAssociatedObject(bar,&pianoEqualWidthsKey);
    [NSLayoutConstraint deactivateConstraints:equal ?: @[]];
    objc_setAssociatedObject(bar,&pianoEqualWidthsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void SizePianoItem(NSCustomTouchBarItem *item,NSTouchBar *bar) {
    if(!IsPianoSlot(item.identifier) || ![item.view isKindOfClass:NSClassFromString(@"pianoView")]) return;
    NSInteger count=PianoCount(bar);
    if(bar==customizationBar) count=MIN(3,MAX(2,count+1)); // Leave room for the next dropped piano.
    NSArray *minimums=objc_getAssociatedObject(item.view,&pianoNativeMinimumKey);
    if(!minimums) {
        NSMutableArray *saved=[NSMutableArray new];
        for(NSLayoutConstraint *constraint in item.view.constraints)
            if(constraint.firstItem==item.view && constraint.firstAttribute==NSLayoutAttributeWidth && !constraint.secondItem && constraint.relation==NSLayoutRelationGreaterThanOrEqual)
                [saved addObject:@[constraint,@(constraint.constant)]];
        minimums=saved; objc_setAssociatedObject(item.view,&pianoNativeMinimumKey,minimums,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The original piano enforces a 400-point minimum. Three such minima
    // cannot fit; retain that minimum only for the unchanged single piano.
    BOOL changed=NO;
    for(NSArray *saved in minimums) {
        NSLayoutConstraint *minimum=saved[0];
        CGFloat target=count<2 ? [saved[1] doubleValue] : 60;
        if(minimum.constant!=target) { minimum.constant=target; changed=YES; }
    }
    NSLayoutConstraint *width=objc_getAssociatedObject(item.view,&pianoCompactWidthKey);
    if(count<2) { width.active=NO; return; } // Keep the existing single-piano presentation.
    if(!width) {
        changed=YES;
        item.view.translatesAutoresizingMaskIntoConstraints=NO;
        width=[item.view.widthAnchor constraintEqualToConstant:480.0/count];
        width.identifier=@"3£ independent piano width";
        objc_setAssociatedObject(item.view,&pianoCompactWidthKey,width,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat target=bar==customizationBar ? 360.0/count : 80;
    NSLayoutPriority priority=bar==customizationBar ? NSLayoutPriorityRequired : 1;
    if(width.constant!=target || width.priority!=priority) {
        changed=YES;
        width.active=NO; width.constant=target; width.priority=priority;
    }
    if(!width.active) { width.active=YES; changed=YES; }
    [item.view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [item.view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    item.visibilityPriority=NSTouchBarItemPriorityHigh;
    if(changed) [item.view invalidateIntrinsicContentSize];
}
static void SizePianos(NSTouchBar *bar) {
    NSMutableArray<NSView *> *views=[NSMutableArray new];
    for(NSString *identifier in bar.itemIdentifiers) if(IsPianoSlot(identifier)) {
        NSCustomTouchBarItem *item=(NSCustomTouchBarItem *)[bar itemForIdentifier:identifier];
        SizePianoItem(item,bar);
        if([item.view isKindOfClass:NSClassFromString(@"pianoView")]) [views addObject:item.view];
    }
    NSArray<NSLayoutConstraint *> *prior=objc_getAssociatedObject(bar,&pianoEqualWidthsKey);
    if(bar==customizationBar || views.count<2) {
        [NSLayoutConstraint deactivateConstraints:prior ?: @[]];
        objc_setAssociatedObject(bar,&pianoEqualWidthsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    // AppKit supplies the available width. Equal widths in the shared host
    // divide it without assuming a display/Control Strip width.
    NSView *common=views.firstObject.superview;
    while(common) {
        BOOL contains=YES;
        for(NSView *view in views) if(![view isDescendantOf:common]) { contains=NO; break; }
        if(contains) break;
        common=common.superview;
    }
    if(!common) return; // Retry after AppKit attaches the actual item views.
    BOOL unchanged=prior.count==views.count-1;
    for(NSUInteger i=0;unchanged && i<prior.count;i++)
        unchanged=prior[i].firstItem==views[i+1] && prior[i].secondItem==views.firstObject && prior[i].active;
    if(unchanged) return;
    [NSLayoutConstraint deactivateConstraints:prior ?: @[]];
    NSMutableArray *equal=[NSMutableArray new];
    for(NSView *view in [views subarrayWithRange:NSMakeRange(1,views.count-1)]) {
        NSLayoutConstraint *constraint=[view.widthAnchor constraintEqualToAnchor:views.firstObject.widthAnchor];
        constraint.identifier=@"3£ equal flexible piano widths"; [equal addObject:constraint];
    }
    [NSLayoutConstraint activateConstraints:equal];
    objc_setAssociatedObject(bar,&pianoEqualWidthsKey,equal,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [common layoutSubtreeIfNeeded];
}
static NSArray *PianoGeometry(NSTouchBar *bar) {
    NSMutableArray *geometry=[NSMutableArray new];
    for(NSString *identifier in bar.itemIdentifiers) if(IsPianoSlot(identifier)) {
        NSView *view=((NSCustomTouchBarItem *)[bar itemForIdentifier:identifier]).view;
        [geometry addObject:@{@"id":identifier,@"width":@(view.bounds.size.width),@"height":@(view.bounds.size.height),@"attached":@(view.window!=nil),@"windowWidth":@(view.window.contentView.bounds.size.width),@"position":NSStringFromRect([view convertRect:view.bounds toView:nil])}];
    }
    return geometry;
}
@interface StripPianoInstance : NSObject
@property(weak) NSTouchBar *bar;
@property(copy) NSString *identifier;
@end
@implementation StripPianoInstance
@end
static void TransferPianoInstance(NSView *source,NSView *replacement) {
    objc_setAssociatedObject(replacement,&pianoInstanceKey,objc_getAssociatedObject(source,&pianoInstanceKey),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *PianoPrefsKey(NSTouchBar *bar) {
    return [@"ControllerConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"] ?: @""];
}
static NSDictionary *InstanceSettings(NSTouchBar *bar,NSString *identifier) {
    NSDictionary *prefs=[NSUserDefaults.standardUserDefaults dictionaryForKey:PianoPrefsKey(bar)];
    NSString *key=identifier.lastPathComponent; key=[key componentsSeparatedByString:@"."].lastObject;
    NSDictionary *saved=prefs[key];
    if(saved) return saved;
    NSMutableDictionary *settings=[prefs[@"piano"] mutableCopy] ?: [NSMutableDictionary new];
    settings[@"channel"]=[identifier isEqual:SecondPianoID] ? @2 : @3;
    return settings;
}
static void SaveInstanceSettings(NSTouchBar *bar,NSString *identifier,NSDictionary *settings) {
    NSString *key=[identifier componentsSeparatedByString:@"."].lastObject;
    NSMutableDictionary *prefs=[[NSUserDefaults.standardUserDefaults dictionaryForKey:PianoPrefsKey(bar)] mutableCopy] ?: [NSMutableDictionary new];
    prefs[key]=settings;
    [NSUserDefaults.standardUserDefaults setObject:prefs forKey:PianoPrefsKey(bar)];
}
static void SaveExpandedPianoSettings(void) {
    if(!normalLayoutBar || !expandedPianoView || !expandedPianoItem) return;
    NSString *identifier=expandedPianoItem.identifier;
    NSMutableDictionary *settings=[InstanceSettings(normalLayoutBar,identifier) mutableCopy];
    settings[@"channel"]=[expandedPianoView valueForKey:@"channelNumber"];
    settings[@"octaves"]=[expandedPianoView valueForKey:@"numOctaves"];
    settings[@"startOctave"]=[expandedPianoView valueForKey:@"startOctave"];
    settings[@"type"]=PianoModeName([[expandedPianoView valueForKey:@"type"] integerValue]);
    SaveInstanceSettings(normalLayoutBar,identifier,settings);
}
static void ApplyInstanceSettings(NSView *piano,NSDictionary *settings) {
    [piano setValue:settings[@"channel"] ?: @1 forKey:@"channelNumber"];
    [piano setValue:settings[@"octaves"] ?: @2 forKey:@"numOctaves"];
    [piano setValue:settings[@"startOctave"] ?: @4 forKey:@"startOctave"];
    NSInteger mode=[@[@"glissando",@"noglissando",@"pitchbend"] indexOfObject:settings[@"type"] ?: @"glissando"];
    if(mode!=NSNotFound) [piano setValue:@(mode) forKey:@"type"];
    [piano setValue:@(-1) forKey:@"lastWidth"];
    piano.needsDisplay=YES;
}
static id MakeIndependentPiano(id delegate,SEL selector,NSTouchBar *bar,NSString *identifier) {
    if(![identifier isEqual:SecondPianoID] && ![identifier isEqual:ThirdPianoID]) {
        id item=((id(*)(id,SEL,id,id))originalMakeItem)(delegate,selector,bar,identifier);
        if([identifier isEqual:NativePianoID]) SizePianoItem(item,bar);
        return item;
    }
    NSDictionary *settings=InstanceSettings(bar,identifier);
    // Use the original piano's kind/behavior semantics, but a new view and state.
    NSCustomTouchBarItem *native=(NSCustomTouchBarItem *)[bar itemForIdentifier:NativePianoID];
    if(!native) native=((id(*)(id,SEL,id,id))originalMakeItem)(delegate,selector,bar,NativePianoID);
    NSView *prototype=native.view;
    if(![prototype isKindOfClass:NSClassFromString(@"pianoView")]) {
        // The vendor's editing preview is a label; request a normal prototype.
        BOOL editing=[[delegate valueForKey:@"editTouchBar"] boolValue];
        [delegate setValue:@NO forKey:@"editTouchBar"];
        @try { native=((id(*)(id,SEL,id,id))originalMakeItem)(delegate,selector,bar,NativePianoID); prototype=native.view; }
        @finally { [delegate setValue:@(editing) forKey:@"editTouchBar"]; }
    }
    NSView *piano=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),[settings[@"octaves"] ?: @2 intValue],[settings[@"startOctave"] ?: @4 intValue]);
    for(NSString *key in @[@"kind",@"type",@"minValue",@"maxValue",@"oscAddress"])
        [piano setValue:[prototype valueForKey:key] forKey:key];
    piano.wantsLayer=YES; piano.allowedTouchTypes=NSTouchTypeMaskDirect;
    piano.identifier=identifier;
    [piano setValue:delegate forKey:@"pianoDelegate"];
    ApplyInstanceSettings(piano,settings);
    StripPianoInstance *instance=[StripPianoInstance new]; instance.bar=bar; instance.identifier=identifier;
    objc_setAssociatedObject(piano,&pianoInstanceKey,instance,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    item.customizationLabel=@"Piano Keys"; item.view=piano;
    SizePianoItem(item,bar);
    return item;
}
static void ConfigureIndependentPiano(id delegate,SEL selector,NSView *piano) {
    StripPianoInstance *instance=objc_getAssociatedObject(piano,&pianoInstanceKey);
    if(!instance || ![[delegate valueForKey:@"editCCs"] boolValue]) {
        ((void(*)(id,SEL,id))originalPianoTouched)(delegate,selector,piano); return;
    }
    // Same Customize Controls workflow, independently saved per piano/preset.
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Piano MIDI Settings";
    alert.informativeText=@"This keyboard has its own MIDI channel, octave range and position.";
    [alert addButtonWithTitle:@"Apply"]; [alert addButtonWithTitle:@"Cancel"];
    NSView *form=[[NSView alloc] initWithFrame:NSMakeRect(0,0,260,100)];
    NSMutableArray<NSPopUpButton *> *menus=[NSMutableArray new];
    NSArray *titles=@[@"MIDI channel",@"Visible octaves",@"Starting octave"];
    NSArray *keys=@[@"channelNumber",@"numOctaves",@"startOctave"];
    for(NSInteger row=0;row<3;row++) {
        NSTextField *label=[NSTextField labelWithString:titles[row]]; label.frame=NSMakeRect(0,70-row*32,140,24); [form addSubview:label];
        NSPopUpButton *menu=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(150,70-row*32,100,26)];
        NSInteger first=row==2 ? 0 : 1, last=row==0 ? 16 : row==1 ? 4 : 8;
        for(NSInteger value=first;value<=last;value++) [menu addItemWithTitle:[@(value) stringValue]];
        [menu selectItemWithTitle:[[piano valueForKey:keys[row]] stringValue]];
        [form addSubview:menu]; [menus addObject:menu];
    }
    alert.accessoryView=form;
    if([alert runModal]!=NSAlertFirstButtonReturn) return;
    NSMutableDictionary *settings=[InstanceSettings(instance.bar,instance.identifier) mutableCopy];
    settings[@"channel"]=@([menus[0].titleOfSelectedItem intValue]);
    settings[@"octaves"]=@([menus[1].titleOfSelectedItem intValue]);
    settings[@"startOctave"]=@(MIN([menus[2].titleOfSelectedItem intValue],10-[settings[@"octaves"] intValue]));
    SaveInstanceSettings(instance.bar,instance.identifier,settings);
    ApplyInstanceSettings(piano,settings);
}
static NSString *NextPianoSlot(NSArray<NSString *> *items) {
    for(NSString *slot in @[NativePianoID,SecondPianoID,ThirdPianoID])
        if(![items containsObject:slot]) return slot;
    return NativePianoID; // Native duplicate rules prevent a fourth instance.
}
static void ExtendPianoPalette(id delegate) {
    NSMutableArray *bars=[[delegate valueForKey:@"allUserTouchbars"] mutableCopy] ?: [NSMutableArray new];
    NSTouchBar *main=[delegate valueForKey:@"mainTouchBar"]; if(main) [bars addObject:main];
    for(NSTouchBar *bar in bars) {
        NSMutableArray *allowed=[bar.customizationAllowedItemIdentifiers mutableCopy];
        if(![allowed containsObject:NativePianoID] && ![allowed containsObject:SecondPianoID] && ![allowed containsObject:ThirdPianoID]) continue;
        for(NSString *identifier in @[NativePianoID,SecondPianoID,ThirdPianoID])
            if(![allowed containsObject:identifier]) [allowed addObject:identifier];
        bar.customizationAllowedItemIdentifiers=allowed;
    }
}
static BOOL midiTerminating;
static NSApplicationActivationPolicy priorActivationPolicy;
static NSTouchBar *priorDelegateBar;
static NSArray *priorAllowedItems;
static IMP originalNativeComplete, originalNativeDragEnded, originalNativeDragBegan;
static NSArray *layoutBeforePianoDrag;
static NSArray *lastPaletteLayout;
static NSTimer *pianoPaletteTimer;
// A new Piano means add, never replace existing controls. Ordinary removals
// and moves contain no new Piano slot and must retain native macOS behavior.
static NSArray *PreserveLayoutOnPianoAddition(NSArray *before,NSArray *after) {
    NSString *added=nil;
    for(NSString *identifier in after)
        if(IsPianoSlot(identifier) && ![before containsObject:identifier]) { added=identifier; break; }
    if(!added) return after;
    NSMutableArray *merged=[after mutableCopy];
    NSUInteger index=[merged indexOfObject:added];
    for(NSString *identifier in before) if(![merged containsObject:identifier])
        [merged insertObject:identifier atIndex:index++];
    return merged;
}
static void CompleteNativePianoDrag(void) {
    if(!customizationBar || finishingCustomization) return;
    NSArray *current=customizationBar.itemIdentifiers;
    if(layoutBeforePianoDrag && [layoutBeforePianoDrag isEqual:current]) return;
    NSArray *merged=layoutBeforePianoDrag ? PreserveLayoutOnPianoAddition(layoutBeforePianoDrag,current) : current;
    if(![merged isEqual:current]) {
        id config=[customizationBar valueForKey:@"configuration"];
        SEL set=NSSelectorFromString(@"_setCustomizedItemIdentifiers:"), persist=NSSelectorFromString(@"_persistCustomizedItemIdentifiers");
        if(![config respondsToSelector:set] || ![config respondsToSelector:persist])
            [NSException raise:@"NativeCustomizationChanged" format:@"macOS cannot retain the added piano layout."];
        ((void(*)(id,SEL,id))objc_msgSend)(config,set,merged);
        ((void(*)(id,SEL))objc_msgSend)(config,persist);
    }
    SizePianos(customizationBar);
    layoutBeforePianoDrag=nil;
}
static void RefreshNativePianoPalette(void) {
    if(!customizationBar || finishingCustomization) return;
    NSMutableArray *allowed=[priorAllowedItems mutableCopy];
    NSUInteger index=[allowed indexOfObject:NativePianoID];
    [allowed removeObjectsInArray:@[NativePianoID,SecondPianoID,ThirdPianoID]];
    NSString *slot=NextPianoSlot(customizationBar.itemIdentifiers);
    [allowed insertObject:slot atIndex:MIN(index==NSNotFound ? allowed.count : index,allowed.count)];
    customizationBar.customizationAllowedItemIdentifiers=allowed;
    lastPaletteLayout=customizationBar.itemIdentifiers.copy;
    SizePianos(customizationBar);
    id palette=[nativeCustomizationController valueForKey:@"appPaletteViewController"];
    if([palette respondsToSelector:NSSelectorFromString(@"_discardCachedVisiblePaletteBarItems")])
        ((void(*)(id,SEL))objc_msgSend)(palette,NSSelectorFromString(@"_discardCachedVisiblePaletteBarItems"));
    if([palette respondsToSelector:NSSelectorFromString(@"reloadData")])
        ((void(*)(id,SEL))objc_msgSend)(palette,NSSelectorFromString(@"reloadData"));
}
static void FinishNativeCustomization(void) {
    if(!customizationBar || finishingCustomization) return;
    finishingCustomization=YES;
    [pianoPaletteTimer invalidate]; pianoPaletteTimer=nil; lastPaletteLayout=nil;
    id delegate=NSApp.delegate;
    customizationBar.customizationAllowedItemIdentifiers=priorAllowedItems;
    customizationWindow.touchBar=nil;
    [customizationWindow orderOut:nil]; customizationWindow=nil;
    [delegate setValue:priorDelegateBar forKey:@"touchBar"]; priorDelegateBar=nil;
    NSApp.touchBar=priorApplicationBar; priorApplicationBar=nil;
    [NSApp setActivationPolicy:priorActivationPolicy];
    [delegate setValue:@NO forKey:@"editTouchBar"];
    NSTouchBar *finished=customizationBar;
    customizationBar=nil; priorAllowedItems=nil; nativeCustomizationController=nil; layoutBeforePianoDrag=nil;
    SizePianos(finished);
    if(!midiTerminating) {
        ((void(*)(id,SEL))originalExitCustomization)(delegate,NSSelectorFromString(@"exitCustomization"));
        if(![[delegate valueForKey:@"touchbarShown"] boolValue])
            ((void(*)(id,SEL))objc_msgSend)(delegate,NSSelectorFromString(@"toggleTouchbar"));
    }
    finishingCustomization=NO;
}
static void NativeCustomizationComplete(id self,SEL selector,id controller) {
    BOOL ours=self==nativeCustomizationController && customizationBar!=nil;
    ((void(*)(id,SEL,id))originalNativeComplete)(self,selector,controller);
    if(ours) FinishNativeCustomization();
}
static void NativeCustomizationDragEnded(id self,SEL selector,id controller) {
    BOOL ours=self==nativeCustomizationController && customizationBar!=nil;
    ((void(*)(id,SEL,id))originalNativeDragEnded)(self,selector,controller);
    if(ours) dispatch_async(dispatch_get_main_queue(),^{
        @try { CompleteNativePianoDrag(); RefreshNativePianoPalette(); }
        @catch(NSException *exception) { NSLog(@"3£ native Piano palette refresh: %@",exception); }
    });
}
static void NativeCustomizationDragBegan(id self,SEL selector,id controller) {
    if(self==nativeCustomizationController && customizationBar)
        layoutBeforePianoDrag=customizationBar.itemIdentifiers.copy;
    ((void(*)(id,SEL,id))originalNativeDragBegan)(self,selector,controller);
}
static void PollNativePianoPalette(void) {
    if(!customizationBar || finishingCustomization || midiTerminating) return;
    if([lastPaletteLayout isEqual:customizationBar.itemIdentifiers]) return;
    // A native drop may commit after controllerDidEndDragging has returned.
    // Refresh from the confirmed identifiers, not callback timing alone.
    CompleteNativePianoDrag(); RefreshNativePianoPalette();
}
static void SafeCustomizeTouchbar(id delegate,SEL selector,id sender) {
    if(customizationBar) return;
    @try {
        if(!originalNativeComplete || !originalNativeDragEnded || !originalNativeDragBegan)
            [NSException raise:@"NativeCustomizationUnavailable" format:@"macOS customization completion handlers are unavailable."];
        if(pianoExpanded) CollapsePiano();
        NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
        NSInteger index=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
        if(!bars.count) return;
        if(index<0 || index>=(NSInteger)bars.count) index=0;
        [delegate setValue:@(index) forKey:@"userTouchbarNumber"];
        ExtendPianoPalette(delegate);
        customizationBar=bars[index]; priorAllowedItems=customizationBar.customizationAllowedItemIdentifiers;
        priorApplicationBar=NSApp.touchBar; priorDelegateBar=[delegate valueForKey:@"touchBar"];
        priorActivationPolicy=NSApp.activationPolicy;
        if([[delegate valueForKey:@"touchbarShown"] boolValue]) Close(delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
        [delegate setValue:@YES forKey:@"editTouchBar"];
        [delegate setValue:customizationBar forKey:@"touchBar"]; NSApp.touchBar=customizationBar;
        // A native responder host, covered by the system fullscreen palette.
        // No custom controls/palette/drag panel is constructed here.
        customizationWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,480,120) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        customizationWindow.releasedWhenClosed=NO; customizationWindow.alphaValue=0.01;
        customizationWindow.touchBar=customizationBar;
        [customizationWindow center]; [customizationWindow makeKeyAndOrderFront:nil];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp activateIgnoringOtherApps:YES];
        NSTouchBar.automaticCustomizeTouchBarMenuItemEnabled=YES;
        Class rowClass=NSClassFromString(@"NSApplicationFunctionRowController");
        SEL shared=NSSelectorFromString(@"sharedApplicationFunctionRowController");
        if(![rowClass respondsToSelector:shared]) [NSException raise:@"NativeCustomizationUnavailable" format:@"The macOS Touch Bar controller is unavailable."];
        id row=((id(*)(id,SEL))objc_msgSend)(rowClass,shared);
        for(NSString *name in @[@"_setup",@"touchBarFinder:updatedTouchBars:",@"_customizationController"])
            if(![row respondsToSelector:NSSelectorFromString(name)]) [NSException raise:@"NativeCustomizationUnavailable" format:@"The macOS Touch Bar controller has changed."];
        ((void(*)(id,SEL))objc_msgSend)(row,NSSelectorFromString(@"_setup"));
        ((void(*)(id,SEL,id,id))objc_msgSend)(row,NSSelectorFromString(@"touchBarFinder:updatedTouchBars:"),nil,@[customizationBar]);
        nativeCustomizationController=((id(*)(id,SEL))objc_msgSend)(row,NSSelectorFromString(@"_customizationController"));
        if(!nativeCustomizationController) [NSException raise:@"NativeCustomizationUnavailable" format:@"macOS did not create its customization controller."];
        [nativeCustomizationController setValue:@[customizationBar] forKey:@"activeTouchBars"];
        [nativeCustomizationController setValue:@[customizationBar] forKey:@"currentResponderTouchBars"];
        RefreshNativePianoPalette();
        pianoPaletteTimer=[NSTimer timerWithTimeInterval:.15 repeats:YES block:^(NSTimer *timer) {
            @try { PollNativePianoPalette(); }
            @catch(NSException *exception) { NSLog(@"3£ native Piano palette update: %@",exception); }
        }];
        [NSRunLoop.mainRunLoop addTimer:pianoPaletteTimer forMode:NSRunLoopCommonModes];
        // Let the native function row acquire its physical display geometry.
        // Opening before that reply arrives produces an unusable palette.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            if(!customizationBar || midiTerminating) return;
            @try { ((void(*)(id,SEL,id))objc_msgSend)(nativeCustomizationController,NSSelectorFromString(@"toggleCustomizationPalette:"),sender); }
            @catch(NSException *exception) { NSLog(@"3£ native customization: %@",exception); FinishNativeCustomization(); }
        });
    } @catch(NSException *exception) {
        NSLog(@"3£ native customization failed safely: %@",exception);
        FinishNativeCustomization();
        NSAlert *alert=[NSAlert new]; alert.messageText=@"macOS Touch Bar customization could not open";
        alert.informativeText=@"Your saved layout has not been replaced. Please reopen 3£ and try again.";
        [alert runModal];
    }
}
static void ExitCustomization(id delegate,SEL selector) {
    if(customizationBar) { FinishNativeCustomization(); return; }
    ((void(*)(id,SEL))originalExitCustomization)(delegate,selector);
}
static void InstallNativeCustomizationHooks(void) {
    Class cls=NSClassFromString(@"NSTouchBarCustomizationController");
    Method complete=class_getInstanceMethod(cls,NSSelectorFromString(@"controllerDidComplete:"));
    Method dragEnded=class_getInstanceMethod(cls,NSSelectorFromString(@"controllerDidEndDragging:"));
    Method dragBegan=class_getInstanceMethod(cls,NSSelectorFromString(@"controllerWillBeginDragging:"));
    if(complete) originalNativeComplete=method_setImplementation(complete,(IMP)NativeCustomizationComplete);
    if(dragEnded) originalNativeDragEnded=method_setImplementation(dragEnded,(IMP)NativeCustomizationDragEnded);
    if(dragBegan) originalNativeDragBegan=method_setImplementation(dragBegan,(IMP)NativeCustomizationDragBegan);
}
