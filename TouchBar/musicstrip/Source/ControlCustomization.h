// Preserve the vendor's control editor while presenting the real live preset.
static IMP originalCustomizeControls, originalSelectControl, originalWriteControl, originalReloadControls;
static NSMutableArray<NSTouchBar *> *controlPresetCatalog;
static NSString *const PresetCountPreference=@"ThreeEPresetCount";
static char countEditorKey;
static char selectedControlKey;
static void InitializePresetCatalog(void) {
    if(controlPresetCatalog.count) return;
    NSArray *bars=[(id)NSApp.delegate valueForKey:@"allUserTouchbars"];
    if(!bars.count) return;
    controlPresetCatalog=[bars mutableCopy];
    NSInteger saved=[NSUserDefaults.standardUserDefaults integerForKey:PresetCountPreference];
    if(saved>0 && saved<(NSInteger)controlPresetCatalog.count)
        [(id)NSApp.delegate setValue:[[controlPresetCatalog subarrayWithRange:NSMakeRange(0,saved)] mutableCopy] forKey:@"allUserTouchbars"];
}

static void HideExpandedOnlySettings(id controller) {
    NSView *control=objc_getAssociatedObject(controller,&selectedControlKey);
    if(![control isKindOfClass:NSClassFromString(@"pianoView")]) return;
    for(NSString *key in @[@"behaviorButton",@"numOctavesButton",@"startOctaveButton"])
        [[controller valueForKey:key] setHidden:YES];
    NSMutableArray *views=[NSMutableArray new]; CollectPianoSettingsViews([controller view],views);
    for(NSView *view in views) if([view isKindOfClass:NSTextField.class]) {
        NSTextField *label=(id)view;
        if(label.isEditable) continue;
        NSString *text=label.stringValue;
        if([@[@"Type:",@"Octaves:",@"Start:"] containsObject:text]) label.hidden=YES;
        else if([text containsString:@"Octaves:"]) label.stringValue=[text stringByReplacingOccurrencesOfString:@"Octaves:" withString:@""];
    }
}

static void SelectCustomizationControl(id controller,SEL selector,id control) {
    ((void(*)(id,SEL,id))originalSelectControl)(controller,selector,control);
    // The recovered vendor getter is never assigned by setCurrentControl:.
    // Track the effective selection without interfering with its save prompt.
    NSString *identifier=[[control valueForKey:@"identifier"] componentsSeparatedByString:@"."].lastObject;
    if([[controller valueForKey:@"controlIdentifier"] isEqual:identifier])
        objc_setAssociatedObject(controller,&selectedControlKey,control,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HideExpandedOnlySettings(controller);
}
static void WriteCustomizationControl(id controller,SEL selector,NSMutableDictionary *prefs) {
    ((void(*)(id,SEL,id))originalWriteControl)(controller,selector,prefs);
    NSView *piano=objc_getAssociatedObject(controller,&selectedControlKey);
    if([piano isKindOfClass:NSClassFromString(@"pianoView")]) {
        // These controls are hidden here; never overwrite the expanded piano's
        // mode/range when applying a channel, kind or scale change.
        [prefs setObject:[piano valueForKey:@"numOctaves"] forKey:@"octaves"];
        [prefs setObject:[piano valueForKey:@"startOctave"] forKey:@"startOctave"];
        [prefs setObject:PianoModeName([[piano valueForKey:@"type"] integerValue]) forKey:@"type"];
    }
}

@interface StripPresetCountEditor : NSObject
@property(nonatomic,weak) NSViewController *controller;
@property(nonatomic,strong) NSStepper *stepper;
@property(nonatomic,strong) NSTextField *label;
- (void)changeCount:(id)sender;
@end
@implementation StripPresetCountEditor
- (void)changeCount:(id)sender {
    id delegate=NSApp.delegate;
    NSArray *active=[delegate valueForKey:@"allUserTouchbars"];
    // Retain hidden bars in memory as well as their unchanged preferences.
    for(NSUInteger i=0;i<active.count && i<controlPresetCatalog.count;i++) controlPresetCatalog[i]=active[i];
    NSInteger count=MAX(1,MIN((NSInteger)controlPresetCatalog.count,self.stepper.integerValue));
    [delegate setValue:[[controlPresetCatalog subarrayWithRange:NSMakeRange(0,count)] mutableCopy] forKey:@"allUserTouchbars"];
    [NSUserDefaults.standardUserDefaults setInteger:count forKey:PresetCountPreference];
    self.stepper.integerValue=count; self.label.stringValue=[NSString stringWithFormat:@"Bars: %ld",(long)count];
    NSInteger selected=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
    if(selected>=count) {
        selected=count-1;
        [delegate setValue:@(selected) forKey:@"userTouchbarNumber"];
        ((void(*)(id,SEL))objc_msgSend)(self.controller,NSSelectorFromString(@"setInitialState"));
        ((void(*)(id,SEL,int))objc_msgSend)(self.controller,NSSelectorFromString(@"setTouchBarNumber:"),(int)selected);
        Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),controlPresetCatalog[selected],nil);
    }
    UpdateNavigationColor();
}
@end

static void CustomizeControls(id delegate,SEL selector,id sender) {
    InitializePresetCatalog();
    if(pianoExpanded) CollapsePiano();
    NSTouchBar *bar=normalLayoutBar;
    NSInteger selected=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
    if(!bar && selected>=0 && selected<(NSInteger)bars.count) bar=bars[selected];
    // Native customizeControls: opens mainTouchBar, which is only an empty
    // shell under our stable modal layout. Restore the actual selected model.
    ((void(*)(id,SEL,id))originalCustomizeControls)(delegate,selector,sender);
    NSViewController *vc=[delegate valueForKey:@"settingsViewController"];
    ((void(*)(id,SEL,int))objc_msgSend)(vc,NSSelectorFromString(@"setTouchBarNumber:"),(int)selected);
    if(bar) Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,nil);
    if(objc_getAssociatedObject(vc,&countEditorKey)) return;
    StripPresetCountEditor *editor=[StripPresetCountEditor new]; editor.controller=vc;
    editor.label=[NSTextField labelWithString:[NSString stringWithFormat:@"Bars: %lu",(unsigned long)bars.count]];
    editor.label.font=[NSFont systemFontOfSize:12];
    editor.stepper=[NSStepper new]; editor.stepper.minValue=1; editor.stepper.maxValue=controlPresetCatalog.count;
    editor.stepper.increment=1; editor.stepper.valueWraps=NO; editor.stepper.integerValue=bars.count;
    editor.stepper.target=editor; editor.stepper.action=@selector(changeCount:);
    editor.stepper.toolTip=@"Number of MIDI Touch Bars. Hidden bars keep their settings.";
    editor.stepper.accessibilityLabel=@"Number of Touch Bars";
    NSView *title=[vc valueForKey:@"touchBarName"];
    for(NSView *view in @[editor.label,editor.stepper]) { view.translatesAutoresizingMaskIntoConstraints=NO; [vc.view addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        // Native title field spans the whole window, not just its text.
        [editor.label.leadingAnchor constraintEqualToAnchor:title.centerXAnchor constant:70],
        [editor.label.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [editor.stepper.leadingAnchor constraintEqualToAnchor:editor.label.trailingAnchor constant:6],
        [editor.stepper.centerYAnchor constraintEqualToAnchor:title.centerYAnchor]
    ]];
    objc_setAssociatedObject(vc,&countEditorKey,editor,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ReloadCustomizationControls(id delegate,SEL selector) {
    if(!normalLayoutBar || ![[delegate valueForKey:@"editCCs"] boolValue]) {
        ((void(*)(id,SEL))originalReloadControls)(delegate,selector); return;
    }
    // Native reload invalidates mainTouchBar's item cache, but that is only
    // our shell. Rebuild the selected preset's items from its saved mappings,
    // keeping the outer host/buttons intact and avoiding a blank bar flash.
    NSTouchBar *old=normalLayoutBar, *fresh=[NSTouchBar new];
    fresh.delegate=old.delegate; fresh.customizationIdentifier=old.customizationIdentifier;
    fresh.customizationAllowedItemIdentifiers=old.customizationAllowedItemIdentifiers;
    fresh.customizationRequiredItemIdentifiers=old.customizationRequiredItemIdentifiers;
    fresh.defaultItemIdentifiers=old.itemIdentifiers;
    fresh.principalItemIdentifier=old.principalItemIdentifier;
    NSMutableArray *bars=[[delegate valueForKey:@"allUserTouchbars"] mutableCopy];
    NSUInteger index=[bars indexOfObjectIdenticalTo:old];
    if(index==NSNotFound) for(NSUInteger i=0;i<bars.count;i++)
        if([bars[i] customizationIdentifier] && [[bars[i] customizationIdentifier] isEqual:old.customizationIdentifier]) { index=i; break; }
    if(index<bars.count) { bars[index]=fresh; [delegate setValue:bars forKey:@"allUserTouchbars"]; }
    if(index<controlPresetCatalog.count) controlPresetCatalog[index]=fresh;
    Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),fresh,nil);
}

static void InstallControlCustomizationHooks(Class delegateClass) {
    // Launch notification precedes the vendor's deferred preset creation.
    dispatch_async(dispatch_get_main_queue(),^{ InitializePresetCatalog(); });
    originalCustomizeControls=method_setImplementation(class_getInstanceMethod(delegateClass,NSSelectorFromString(@"customizeControls:")),(IMP)CustomizeControls);
    originalReloadControls=method_setImplementation(class_getInstanceMethod(delegateClass,NSSelectorFromString(@"reloadTouchbar")),(IMP)ReloadCustomizationControls);
    Class vc=NSClassFromString(@"CCSettingsViewController");
    originalSelectControl=method_setImplementation(class_getInstanceMethod(vc,NSSelectorFromString(@"setCurrentControl:")),(IMP)SelectCustomizationControl);
    originalWriteControl=method_setImplementation(class_getInstanceMethod(vc,NSSelectorFromString(@"WritingToPreferences:")),(IMP)WriteCustomizationControl);
}
