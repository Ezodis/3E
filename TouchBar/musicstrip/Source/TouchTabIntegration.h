#ifdef STRIP_COMBINED_TOUCHTAB
static Class StripGestureClass;
static BOOL StripGesturesEnabled(void) {
    id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"TouchTabGesturesEnabled"];
    return saved ? [saved boolValue] : YES;
}
static BOOL StripGesturesRunning(void) {
    return StripGestureClass && ((BOOL(*)(id,SEL))objc_msgSend)(StripGestureClass,NSSelectorFromString(@"running"));
}
static void StripStopGestures(void) {
    if(StripGestureClass) ((void(*)(id,SEL))objc_msgSend)(StripGestureClass,NSSelectorFromString(@"stop"));
}
static NSString *StripRefreshGestures(void) {
    if(!StripGesturesEnabled()) { StripStopGestures(); return @"off"; }
    if(!AccessibilityTrusted(NO)) { StripStopGestures(); return @"permission"; }
    if(!StripGestureClass) {
        NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/ThreeEGestureEngine.dylib"];
        if(!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)) { NSLog(@"3£ gesture module unavailable: %s",dlerror()); return @"unavailable"; }
        StripGestureClass=NSClassFromString(@"ThreeEGestures");
    }
    if(!StripGestureClass) return @"unavailable";
    if(!StripGesturesRunning()) ((BOOL(*)(id,SEL))objc_msgSend)(StripGestureClass,NSSelectorFromString(@"start"));
    return StripGesturesRunning() ? @"on" : @"unavailable";
}
#endif
