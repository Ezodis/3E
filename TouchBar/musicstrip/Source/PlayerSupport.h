#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static NSString *ServiceForURL(NSString *url) {
    if(![url isKindOfClass:NSString.class] || !url.length) return nil;
    NSString *host = [NSURLComponents componentsWithString:url].host.lowercaseString;
    if ([host isEqualToString:@"youtube.com"] || [host hasSuffix:@".youtube.com"] || [host isEqualToString:@"youtu.be"]) return @"youtube";
    if ([host isEqualToString:@"netflix.com"] || [host hasSuffix:@".netflix.com"]) return @"netflix";
    if ([host isEqualToString:@"spotify.com"] || [host hasSuffix:@".spotify.com"]) return @"spotify";
    return nil;
}
static NSImage *ServiceIcon(NSString *service) {
    if (![service isEqualToString:@"youtube"] && ![service isEqualToString:@"netflix"]) return nil;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(24,24) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        if ([service isEqualToString:@"youtube"]) {
            [[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1,4,22,16) xRadius:4 yRadius:4] fill];
            [NSColor.whiteColor setFill];
            NSBezierPath *triangle = [NSBezierPath bezierPath];
            [triangle moveToPoint:NSMakePoint(10,8)]; [triangle lineToPoint:NSMakePoint(17,12)];
            [triangle lineToPoint:NSMakePoint(10,16)]; [triangle closePath]; [triangle fill];
        } else {
            [@"N" drawAtPoint:NSMakePoint(4,0) withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:23],
                NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:0.9 green:0.035 blue:0.08 alpha:1]}];
        }
        return YES;
    }];
    image.template = NO;
    return image;
}
static pid_t SafariMediaPID(void) {
    @try {
        id client = [RequestValue(@"localNowPlayingPlayerPath") valueForKey:@"client"];
        for (NSString *name in @[@"processIdentifier", @"pid"]) {
            SEL selector = NSSelectorFromString(name);
            if ([client respondsToSelector:selector]) return ((pid_t (*)(id, SEL))objc_msgSend)(client,selector);
        }
    } @catch (NSException *e) {}
    return 0;
}
static NSString *ReadSafariURL(pid_t mediaPID) {
    // Prefer the tab whose WebContent PID is publishing Now Playing. Safari
    // exposes that PID through its existing scripting dictionary. Fall back to
    // the front tab when macOS has not supplied a per-tab process identity.
    NSString *source = [NSString stringWithFormat:
        @"tell application id \"com.apple.Safari\"\nif (count of windows) is 0 then return \"\"\n"
         "if %d > 0 then\nrepeat with w in windows\nrepeat with t in tabs of w\ntry\n"
         "if pid of t is %d then return URL of t\nend try\nend repeat\nend repeat\nend if\n"
         "return URL of current tab of front window\nend tell",mediaPID,mediaPID];
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *error;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&error];
    if (error) NSLog(@"Safari icon lookup unavailable (Automation status %@)", error[NSAppleScriptErrorNumber]);
    return result.stringValue;
}
static BOOL IsTextRole(NSString *role) {
    return [role isEqualToString:(__bridge NSString *)kAXTextFieldRole] || [role isEqualToString:(__bridge NSString *)kAXTextAreaRole] ||
        [role isEqualToString:(__bridge NSString *)kAXComboBoxRole];
}
static BOOL SendAbletonToggle(pid_t pid) {
    if (pid <= 0 || !AXIsProcessTrusted()) return NO;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app,0.25);
    CFTypeRef focused = NULL;
    AXError query = AXUIElementCopyAttributeValue(app,kAXFocusedUIElementAttribute,&focused);
    if (query == kAXErrorSuccess && focused && CFGetTypeID(focused) == AXUIElementGetTypeID()) {
        CFTypeRef role = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focused,kAXRoleAttribute,&role);
        BOOL textEditing = role && IsTextRole((__bridge NSString *)role);
        if (role) CFRelease(role);
        if (textEditing) { CFRelease(focused); CFRelease(app); NSLog(@"Finish editing text in Ableton before using its transport."); return NO; }
    }
    if (focused) CFRelease(focused);
    CFRelease(app);
    // Ableton's documented Space transport shortcut, sent only to its running
    // PID. It does not activate Live, type into another app or send a media key.
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef down = CGEventCreateKeyboardEvent(source,49,true);
    CGEventRef up = CGEventCreateKeyboardEvent(source,49,false);
    BOOL sent = down && up;
    if (sent) { CGEventSetFlags(down,0); CGEventSetFlags(up,0); CGEventPostToPid(pid,down); CGEventPostToPid(pid,up); }
    if (down) CFRelease(down); if (up) CFRelease(up); if (source) CFRelease(source);
    return sent;
}

static dispatch_queue_t ProviderQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("local.musicstrip.provider",DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static id AXValue(AXUIElementRef element, CFStringRef name);
static NSInteger SafariTransportLabelState(NSString *label) {
    if(![label isKindOfClass:NSString.class]) return -1;
    NSString *text=[[label lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([text hasSuffix:@" (k)"]) text=[text substringToIndex:text.length-4];
    if([@[@"pause",@"pausa",@"pausar"] containsObject:text]) return 1;
    if([@[@"play",@"reproducir",@"reproduzir"] containsObject:text]) return 0;
    return -1;
}
static NSInteger ReadSafariState(pid_t pid) {
    if(pid<=0 || !AXIsProcessTrusted()) return -1;
    AXUIElementRef app=AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app,.05);
    id window=AXValue(app,kAXMainWindowAttribute);
    NSMutableArray *queue=[NSMutableArray array]; if(window) [queue addObject:window];
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent(); NSInteger fallback=-1; BOOL conflicting=NO;
    for(NSUInteger index=0;index<queue.count && index<1800 && CFAbsoluteTimeGetCurrent()-start<.8;index++) {
        id element=queue[index]; NSString *role=AXValue((__bridge AXUIElementRef)element,kAXRoleAttribute);
        if([role isEqualToString:(__bridge NSString *)kAXButtonRole]) {
            NSArray *labels=@[AXValue((__bridge AXUIElementRef)element,kAXTitleAttribute) ?: @"",AXValue((__bridge AXUIElementRef)element,kAXDescriptionAttribute) ?: @""];
            for(NSString *label in labels) {
                NSInteger state=SafariTransportLabelState(label); if(state<0) continue;
                // YouTube's (k) transport shortcut distinguishes its actual
                // video control from the Play buttons on recommendations.
                if([label.lowercaseString hasSuffix:@" (k)"]) { CFRelease(app); return state; }
                if(fallback>=0 && fallback!=state) conflicting=YES; else fallback=state;
            }
        }
        NSArray *children=AXValue((__bridge AXUIElementRef)element,kAXChildrenAttribute);
        if([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    // A bare Play button may belong to a recommended video. Only a
    // transport-specific Play (k) control above can prove YouTube paused.
    CFRelease(app); return conflicting || fallback!=1 ? -1 : 1;
}

static BOOL ShouldRestartPrevious(double elapsed) {
    return isfinite(elapsed) && elapsed>3.0;
}
static BOOL IsYouTubeSeekSlider(NSString *label) {
    if(![label isKindOfClass:NSString.class]) return NO;
    return [@[@"seek slider",@"control deslizante de búsqueda",@"controle deslizante de busca"] containsObject:label.lowercaseString];
}
static double YouTubeElapsedLabel(NSString *label) {
    if(![label isKindOfClass:NSString.class]) return NAN;
    NSString *text=label.lowercaseString;
    NSRange separator=[text rangeOfString:@" de "]; if(separator.location==NSNotFound) separator=[text rangeOfString:@" of "];
    if(separator.location==NSNotFound) separator=[text rangeOfString:@" / "];
    if(separator.location==NSNotFound) return NAN;
    text=[text substringToIndex:separator.location];
    NSRegularExpression *clock=[NSRegularExpression regularExpressionWithPattern:@"^([0-9]+:)?[0-9]+:[0-9]+$" options:0 error:nil];
    if([clock numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)]) {
        double seconds=0; for(NSString *part in [text componentsSeparatedByString:@":"]) seconds=seconds*60+part.doubleValue; return seconds;
    }
    NSRegularExpression *units=[NSRegularExpression regularExpressionWithPattern:@"([0-9]+) (hours?|horas?|minutes?|minutos?|seconds?|segundos?)" options:0 error:nil];
    NSArray *matches=[units matchesInString:text options:0 range:NSMakeRange(0,text.length)];
    if(!matches.count || [matches.firstObject range].location!=0) return NAN;
    double seconds=0;
    for(NSTextCheckingResult *match in matches) {
        double value=[[text substringWithRange:[match rangeAtIndex:1]] doubleValue];
        NSString *unit=[text substringWithRange:[match rangeAtIndex:2]];
        seconds+=value*([unit hasPrefix:@"h"] ? 3600 : [unit hasPrefix:@"m"] ? 60 : 1);
    }
    return seconds;
}
// 1: restart needed; 0: already near the beginning; -1: timeline unavailable.
static NSInteger SafariYouTubePreviousAction(pid_t pid) {
    if(pid<=0 || !AXIsProcessTrusted()) return -1;
    AXUIElementRef app=AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app,.05);
    id window=AXValue(app,kAXMainWindowAttribute);
    NSMutableArray *queue=[NSMutableArray array]; if(window) [queue addObject:window];
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent(); double sliderElapsed=NAN, elapsed=NAN;
    for(NSUInteger i=0;i<queue.count && i<1800 && CFAbsoluteTimeGetCurrent()-start<1;i++) {
        AXUIElementRef element=(__bridge AXUIElementRef)queue[i];
        NSString *role=AXValue(element,kAXRoleAttribute);
        if([role isEqual:(__bridge NSString *)kAXButtonRole]) {
            elapsed=YouTubeElapsedLabel(AXValue(element,kAXTitleAttribute));
            if(!isfinite(elapsed)) elapsed=YouTubeElapsedLabel(AXValue(element,kAXDescriptionAttribute));
            if(isfinite(elapsed)) break;
        }
        if([role isEqual:(__bridge NSString *)kAXSliderRole] &&
           (IsYouTubeSeekSlider(AXValue(element,kAXTitleAttribute)) || IsYouTubeSeekSlider(AXValue(element,kAXDescriptionAttribute)))) {
            id value=AXValue(element,kAXValueAttribute), minimum=AXValue(element,kAXMinValueAttribute);
            if([value isKindOfClass:NSNumber.class] && [minimum isKindOfClass:NSNumber.class] && [minimum doubleValue]==0) sliderElapsed=[value doubleValue];
        }
        NSArray *children=AXValue(element,kAXChildrenAttribute); if([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    // YouTube's custom ARIA slider can retain its old value after seeking.
    // Its separate time button reflects the updated video position.
    CFRelease(app); if(!isfinite(elapsed)) elapsed=sliderElapsed;
    return isfinite(elapsed) ? (ShouldRestartPrevious(elapsed) ? 1 : 0) : -1;
}

// Read-only diagnostic of the visible browser's media sliders.
static void DiagnoseSafariSliders(pid_t pid) {
    if(pid<=0 || !AXIsProcessTrusted()) return;
    AXUIElementRef app=AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app,.05);
    id window=AXValue(app,kAXMainWindowAttribute);
    NSMutableArray *queue=[NSMutableArray array]; if(window) [queue addObject:window];
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
    for(NSUInteger i=0;i<queue.count && i<1800 && CFAbsoluteTimeGetCurrent()-start<1;i++) {
        AXUIElementRef element=(__bridge AXUIElementRef)queue[i];
        if([AXValue(element,kAXRoleAttribute) isEqual:(__bridge NSString *)kAXSliderRole]) {
            NSLog(@"Browser slider: title=%@ description=%@ value=%@ min=%@ max=%@ valueDescription=%@",AXValue(element,kAXTitleAttribute),AXValue(element,kAXDescriptionAttribute),AXValue(element,kAXValueAttribute),AXValue(element,kAXMinValueAttribute),AXValue(element,kAXMaxValueAttribute),AXValue(element,CFSTR("AXValueDescription")));
        }
        NSArray *children=AXValue(element,kAXChildrenAttribute); if([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    CFRelease(app);
}

static NSInteger ReadSpotifyState(pid_t pid) {
    if (pid<=0) return -1;
    NSAppleEventDescriptor *target=[NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID bytes:&pid length:sizeof(pid)];
    NSAppleEventDescriptor *property=[NSAppleEventDescriptor recordDescriptor];
    [property setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:typeProperty] forKeyword:keyAEDesiredClass];
    [property setDescriptor:[NSAppleEventDescriptor nullDescriptor] forKeyword:keyAEContainer];
    [property setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formPropertyID] forKeyword:keyAEKeyForm];
    [property setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:'pPlS'] forKeyword:keyAEKeyData];
    NSAppleEventDescriptor *event=[NSAppleEventDescriptor appleEventWithEventClass:kAECoreSuite eventID:kAEGetData targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[property coerceToDescriptorType:typeObjectSpecifier] forKeyword:keyDirectObject];
    AppleEvent reply={typeNull,NULL};
    OSStatus error=AESendMessage(event.aeDesc,&reply,kAEWaitReply|kAENeverInteract,60);
    NSInteger state=-1;
    if (!error) {
        NSAppleEventDescriptor *response=[[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&reply];
        NSAppleEventDescriptor *value=[response paramDescriptorForKeyword:keyDirectObject];
        if (value.descriptorType==typeEnumerated) { AEKeyword code=value.enumCodeValue; if(code=='kPSP') state=1; else if(code=='kPSp'||code=='kPSS') state=0; }
    } else AEDisposeDesc(&reply);
    return state;
}
static AXUIElementRef livePlayElement;
static pid_t livePlayPID;
static id AXValue(AXUIElementRef element, CFStringRef name) {
    CFTypeRef value=NULL;
    return AXUIElementCopyAttributeValue(element,name,&value)==kAXErrorSuccess ? CFBridgingRelease(value) : nil;
}
static NSInteger LivePlayState(AXUIElementRef element) {
    if (!element) return -1;
    id value=AXValue(element,kAXValueAttribute) ?: AXValue(element,kAXSelectedAttribute);
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue] ? 1 : 0;
    if ([value isKindOfClass:NSString.class]) {
        if ([value isEqualToString:@"1"] || [value caseInsensitiveCompare:@"on"]==NSOrderedSame) return 1;
        if ([value isEqualToString:@"0"] || [value caseInsensitiveCompare:@"off"]==NSOrderedSame) return 0;
    }
    return -1;
}
static NSInteger ReadAbletonState(pid_t pid) {
    if (!AXIsProcessTrusted()) return -1;
    if (livePlayElement && livePlayPID==pid) {
        NSInteger state=LivePlayState(livePlayElement); if(state>=0) return state;
    }
    if (livePlayElement) { CFRelease(livePlayElement); livePlayElement=NULL; }
    livePlayPID=pid;
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app,0.08);
    NSArray *windows=AXValue(app,kAXWindowsAttribute);
    NSMutableArray *queue=[NSMutableArray arrayWithArray:windows ?: @[]];
    NSTimeInterval deadline=NSDate.timeIntervalSinceReferenceDate+1.5;
    for (NSUInteger index=0;index<queue.count && index<500 && NSDate.timeIntervalSinceReferenceDate<deadline;index++) {
        AXUIElementRef element=(__bridge AXUIElementRef)queue[index];
        NSString *role=AXValue(element,kAXRoleAttribute);
        if ([role isEqualToString:@"AXCheckBox"] || [role isEqualToString:@"AXButton"]) {
            NSString *name=AXValue(element,kAXTitleAttribute) ?: AXValue(element,kAXDescriptionAttribute);
            NSString *label=name.lowercaseString;
            if ([label isEqualToString:@"play"] || [label isEqualToString:@"play button"] || [label isEqualToString:@"play/stop"]) {
                NSInteger state=LivePlayState(element);
                if (state>=0) { livePlayElement=(AXUIElementRef)CFRetain(element); CFRelease(app); return state; }
            }
        }
        NSArray *children=AXValue(element,kAXChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    CFRelease(app);return -1;
}
static AXUIElementRef FindAbletonStop(pid_t pid) {
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app,0.08);
    NSArray *windows=AXValue(app,kAXWindowsAttribute);
    NSMutableArray *queue=[NSMutableArray arrayWithArray:windows ?: @[]];
    AXUIElementRef stop=NULL;
    NSTimeInterval deadline=NSDate.timeIntervalSinceReferenceDate+1.5;
    for (NSUInteger index=0;index<queue.count && index<500 && NSDate.timeIntervalSinceReferenceDate<deadline;index++) {
        AXUIElementRef element=(__bridge AXUIElementRef)queue[index];
        NSString *role=AXValue(element,kAXRoleAttribute);
        if ([role isEqualToString:@"AXCheckBox"] || [role isEqualToString:@"AXButton"]) {
            NSString *name=AXValue(element,kAXTitleAttribute) ?: AXValue(element,kAXDescriptionAttribute);
            NSString *label=name.lowercaseString;
            if ([label isEqualToString:@"stop"] || [label isEqualToString:@"stop button"]) { stop=(AXUIElementRef)CFRetain(element); break; }
        }
        NSArray *children=AXValue(element,kAXChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    CFRelease(app); return stop;
}
static NSInteger AbletonDesiredState(NSInteger current, NSInteger desired) {
    return desired>=0 ? desired : current>=0 ? (current==1 ? 0 : 1) : -1;
}
static BOOL SendAbletonState(pid_t pid, NSInteger desired) {
    NSInteger current=ReadAbletonState(pid);
    desired=AbletonDesiredState(current,desired);
    if (desired>=0 && current==desired) return YES;
    // Live's Play button retriggers playback; it is not a toggle. Stop must
    // press the separate square transport control, never Play a second time.
    if (desired==0) {
        AXUIElementRef stop=FindAbletonStop(pid);
        if (stop) {
            BOOL sent=AXUIElementPerformAction(stop,kAXPressAction)==kAXErrorSuccess;
            CFRelease(stop);
            if (sent) return YES;
        }
    } else if (desired==1 && livePlayElement && livePlayPID==pid) {
        if(AXUIElementPerformAction(livePlayElement,kAXPressAction)==kAXErrorSuccess) return YES;
    }
    return SendAbletonToggle(pid);
}
static NSImage *IconWithAction(NSImage *source, NSInteger action, BOOL stopAction) {
    if (!source) return nil;
    if(action<0) action=0; // Keep Play visible until authoritative state arrives.
    return [NSImage imageWithSize:NSMakeSize(34,20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [source drawInRect:NSMakeRect(0,1,18,18)];
        [NSColor.whiteColor setFill];
        if(action==1 && stopAction) {
            NSRectFill(NSMakeRect(23,5,10,10));
        } else if(action==1) {
            NSRectFill(NSMakeRect(23,4,3,12));NSRectFill(NSMakeRect(29,4,3,12));
        } else {
            NSBezierPath *triangle=[NSBezierPath bezierPath];[triangle moveToPoint:NSMakePoint(23,3)];
            [triangle lineToPoint:NSMakePoint(33,10)];[triangle lineToPoint:NSMakePoint(23,17)];[triangle closePath];[triangle fill];
        }
        return YES;
    }];
}
