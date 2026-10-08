// Read-only Live scale feedback. Never transpose, filter or reroute MIDI.
static IMP originalPianoDraw;
static NSUInteger liveScaleMask;
static NSHashTable<NSView *> *scalePianos;
static NSUInteger ScaleMaskForState(NSDictionary *state,BOOL connected) {
    if(!connected || ![state[@"scale_supported"] boolValue] || ![state[@"scale_mode"] boolValue]) return 0;
    id root=state[@"root_note"], intervals=state[@"scale_intervals"];
    if(![root isKindOfClass:NSNumber.class] || [root integerValue]<0 || [root integerValue]>11 || ![intervals isKindOfClass:NSArray.class] || ![intervals count]) return 0;
    NSUInteger mask=0;
    for(id interval in intervals) {
        if(![interval isKindOfClass:NSNumber.class] || [interval integerValue]<0 || [interval integerValue]>24) return 0;
        mask|=1UL<<(([root integerValue]+[interval integerValue])%12);
    }
    return mask;
}
static BOOL NoteInLiveScale(NSInteger note,NSUInteger mask) { return (mask & (1UL<<((note%12+12)%12)))!=0; }
static void UpdateLiveScale(NSDictionary *state,BOOL connected) {
    NSUInteger mask=ScaleMaskForState(state,connected);
    if(mask==liveScaleMask) return;
    liveScaleMask=mask;
    for(NSView *piano in scalePianos.allObjects) piano.needsDisplay=YES;
}
static BOOL ScaleKeyIsPressed(NSView *piano,id key) {
    NSBezierPath *path=[key valueForKey:@"drawPath"], *touch=[key valueForKey:@"touchPath"];
    for(id active in [piano valueForKey:@"activeKeys"]) {
        id pressed=[active valueForKey:@"pianoKey"];
        if(pressed==path || pressed==touch) return YES;
    }
    return NO;
}
static void DrawPianoScale(NSView *piano,SEL selector,NSRect dirty) {
    ((void(*)(id,SEL,NSRect))originalPianoDraw)(piano,selector,dirty);
    if(!scalePianos) scalePianos=[NSHashTable weakObjectsHashTable];
    [scalePianos addObject:piano];
    if(!liveScaleMask) return;
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSIntersectionRect(piano.bounds,dirty)];
    for(id active in [piano valueForKey:@"activeKeys"]) {
        NSBezierPath *pressed=[active valueForKey:@"pianoKey"];
        if(![pressed isKindOfClass:NSBezierPath.class]) continue;
        NSBezierPath *unpressed=[NSBezierPath bezierPathWithRect:piano.bounds];
        unpressed.windingRule=NSWindingRuleEvenOdd; [unpressed appendBezierPath:pressed]; [unpressed addClip];
    }
    NSInteger start=[[piano valueForKey:@"startOctave"] integerValue]*12;
    NSBezierPath *whiteMask=[NSBezierPath bezierPathWithRect:piano.bounds];
    whiteMask.windingRule=NSWindingRuleEvenOdd;
    for(id key in [piano valueForKey:@"pianoKeys"])
        if([@[@1,@3,@6,@8,@10] containsObject:@(([[key valueForKey:@"pitch"] integerValue]%12+12)%12)])
            [whiteMask appendBezierPath:[key valueForKey:@"drawPath"]];
    for(id key in [piano valueForKey:@"pianoKeys"]) {
        if(!NoteInLiveScale(start+[[key valueForKey:@"pitch"] integerValue],liveScaleMask) || ScaleKeyIsPressed(piano,key)) continue;
        NSBezierPath *path=[key valueForKey:@"drawPath"];
        BOOL black=[@[@1,@3,@6,@8,@10] containsObject:@(([[key valueForKey:@"pitch"] integerValue]%12+12)%12)];
        [NSGraphicsContext saveGraphicsState];
        if(!black) [whiteMask addClip];
        // Dark keys need a luminous accent, not the same translucent tint
        // used over white keys. Keep the two physical key types distinct.
        NSColor *accent=black
            ? [NSColor colorWithSRGBRed:.20 green:.85 blue:1.0 alpha:.78]
            : [NSColor colorWithSRGBRed:.56 green:.20 blue:.85 alpha:.32];
        [accent setFill];
        [path fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
}
