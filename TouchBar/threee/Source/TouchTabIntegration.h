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
    if(!StripGestureClass) {
        NSString *path=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/ThreeEGestureEngine.dylib"];
        if(!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)) { NSLog(@"3£ gesture module unavailable: %s",dlerror()); return @"unavailable"; }
        StripGestureClass=NSClassFromString(@"ThreeEGestures");
    }
    if(!StripGestureClass) return @"unavailable";
    if(!StripGesturesRunning()) ((BOOL(*)(id,SEL))objc_msgSend)(StripGestureClass,NSSelectorFromString(@"start"));
    // Test the capabilities actually used by TouchTab. The general AX trust
    // query is not a substitute for an enabled event tap and event-post access.
    if(StripGesturesRunning() && CGPreflightPostEventAccess()) return @"on";
    if(!CGPreflightPostEventAccess() || !AccessibilityTrusted(NO)) { StripStopGestures(); return @"permission"; }
    return @"unavailable";
}
#endif
