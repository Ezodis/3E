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
    // The vendor also sizes its drawn chevrons by octave density. Redraw
    // only the reserved edges with legible, compact fixed-size chevrons.
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSIntersectionRect(piano.bounds,dirty)];
    CGFloat edge=MIN(14,piano.bounds.size.width/4);
    for(NSInteger side=0;side<2;side++) {
        CGFloat x=side ? NSMaxX(piano.bounds)-edge : NSMinX(piano.bounds);
        [NSColor.blackColor setFill]; NSRectFill(NSMakeRect(x,0,edge,piano.bounds.size.height));
        CGFloat midY=NSMidY(piano.bounds),center=x+edge/2;
        NSBezierPath *arrow=[NSBezierPath bezierPath];
        [arrow moveToPoint:NSMakePoint(center+(side ? -3 : 3),midY-8)];
        [arrow lineToPoint:NSMakePoint(center+(side ? 3 : -3),midY)];
        [arrow lineToPoint:NSMakePoint(center+(side ? -3 : 3),midY+8)];
        arrow.lineWidth=2; arrow.lineCapStyle=NSLineCapStyleRound;
        [NSColor.whiteColor setStroke]; [arrow stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
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
        // One cyan color family, with a strong light/dark split so the
        // original white/black key pattern remains readable in the scale.
        NSColor *accent=black
            ? [NSColor colorWithSRGBRed:.08 green:.40 blue:.47 alpha:1.0]
            : [NSColor colorWithSRGBRed:.52 green:.86 blue:.93 alpha:1.0];
        [accent setFill];
        [path fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
}
