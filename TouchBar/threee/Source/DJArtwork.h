// Loaded-deck cover thumbnails only; no library or audio-file lookup.
#ifndef THREEE_DJ_STANDALONE_TEST
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <dlfcn.h>
#endif
static NSString *DJArtworkKey(NSDictionary *deck) {
    return [deck[@"duration"] doubleValue]>0 && [deck[@"title"] length] ? [NSString stringWithFormat:@"%@|%.0f",deck[@"title"],[deck[@"duration"] doubleValue]] : nil;
}
static NSRect DJArtworkRect(NSArray *components) {
    if(![components isKindOfClass:NSArray.class] || components.count!=4) return NSZeroRect;
    double v[4];for(NSUInteger i=0;i<4;i++) { if(![components[i] respondsToSelector:@selector(doubleValue)]) return NSZeroRect;v[i]=[components[i] doubleValue];if(!isfinite(v[i])) return NSZeroRect; }
    // Deck covers are small square controls. Reject unexpected UI regions.
    if(v[2]<12 || v[3]<12 || v[2]>256 || v[3]>256 || fabs(v[2]-v[3])>2) return NSZeroRect;
    return NSMakeRect(v[0],v[1],v[2],v[3]);
}
static NSRect DJArtworkSourceRect(NSRect cover,NSRect window,NSRect display) {
    if(NSIsEmptyRect(cover) || !NSContainsRect(window,cover) || !NSContainsRect(display,cover)) return NSZeroRect;
    return NSOffsetRect(cover,-display.origin.x,-display.origin.y);
}
#ifndef THREEE_DJ_STANDALONE_TEST
static NSArray *DJAXFrame(AXUIElementRef element) {
    id position=DJAX(element,kAXPositionAttribute),size=DJAX(element,kAXSizeAttribute);CGPoint p;CGSize s;
    if(!position || !size || CFGetTypeID((__bridge CFTypeRef)position)!=AXValueGetTypeID() || CFGetTypeID((__bridge CFTypeRef)size)!=AXValueGetTypeID()) return nil;
    if(!AXValueGetValue((__bridge AXValueRef)position,kAXValueCGPointType,&p) || !AXValueGetValue((__bridge AXValueRef)size,kAXValueCGSizeType,&s)) return nil;
    return @[@(p.x),@(p.y),@(s.width),@(s.height)];
}
static void DJCaptureCovers(pid_t pid,NSArray *rects,void (^completion)(NSDictionary<NSNumber *,NSImage *> *)) {
    if(@available(macOS 14.0,*)) {
        // The MIDI helper also runs on older macOS releases. Load this optional
        // framework only for artwork, and never request new permission here.
        static void *framework;static dispatch_once_t once;
        dispatch_once(&once,^{framework=dlopen("/System/Library/Frameworks/ScreenCaptureKit.framework/ScreenCaptureKit",RTLD_LAZY|RTLD_LOCAL);});
        if(!framework || !CGPreflightScreenCaptureAccess()) { completion(@{});return; }
        [NSClassFromString(@"SCShareableContent") getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content,NSError *error) {
            NSMutableDictionary *images=[NSMutableDictionary new];dispatch_group_t group=dispatch_group_create();
            if(!error) for(NSUInteger i=0;i<rects.count;i++) {
                NSRect cover=DJArtworkRect(rects[i]);if(NSIsEmptyRect(cover)) continue;
                SCWindow *window=nil;for(SCWindow *candidate in content.windows) if(candidate.owningApplication.processID==pid && [candidate.title isEqual:@"rekordbox"] && NSContainsRect(candidate.frame,cover)) { window=candidate;break; }
                if(!window) continue;
                SCDisplay *display=nil;for(SCDisplay *candidate in content.displays) if(NSContainsRect(candidate.frame,cover)) { display=candidate;break; }
                if(!display) continue;
                NSRect source=DJArtworkSourceRect(cover,window.frame,display.frame);if(NSIsEmptyRect(source)) continue;
                // A display filter including only this rekordbox window lets
                // sourceRect crop at capture time. Single-window filters ignore
                // sourceRect and would capture unnecessary UI.
                SCContentFilter *filter=[[NSClassFromString(@"SCContentFilter") alloc] initWithDisplay:display includingWindows:@[window]];
                SCStreamConfiguration *configuration=[NSClassFromString(@"SCStreamConfiguration") new];
                configuration.sourceRect=source;configuration.width=96;configuration.height=96;configuration.showsCursor=NO;configuration.scalesToFit=YES;
                dispatch_group_enter(group);
                [NSClassFromString(@"SCScreenshotManager") captureImageWithFilter:filter configuration:configuration completionHandler:^(CGImageRef image,NSError *captureError) {
                    if(image && !captureError) { NSImage *thumbnail=[[NSImage alloc] initWithCGImage:image size:NSMakeSize(96,96)];@synchronized(images) { images[@(i)]=thumbnail; } }
                    dispatch_group_leave(group);
                }];
            }
            dispatch_group_notify(group,dispatch_get_main_queue(),^{completion(images.copy);});
        }];
        return;
    }
    completion(@{});
}
#endif
