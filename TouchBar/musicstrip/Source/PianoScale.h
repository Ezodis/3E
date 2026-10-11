// Read-only Live scale feedback. Never transpose, filter or reroute MIDI.
static IMP originalPianoDraw;
static NSUInteger liveScaleMask;
static NSArray<NSNumber *> *liveScaleDegrees;
static char pianoDegreesKey;
static BOOL PianoShowsDegrees(NSView *piano) { return [objc_getAssociatedObject(piano,&pianoDegreesKey) boolValue]; }
static void SetPianoShowsDegrees(NSView *piano,BOOL enabled) {
    objc_setAssociatedObject(piano,&pianoDegreesKey,@(enabled),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    piano.needsDisplay=YES;
}
static NSString *ScaleDegreeForNote(NSInteger note) {
    NSUInteger index=[liveScaleDegrees indexOfObject:@((note%12+12)%12)];
    NSArray *names=@[@"I",@"II",@"III",@"IV",@"V",@"VI",@"VII",@"VIII",@"IX",@"X",@"XI",@"XII"];
    if(index==NSNotFound || index>=names.count) return nil;
    NSString *degree=names[index];
    // Diatonic triads stack alternate degrees. Other scale sizes retain
    // neutral degree labels rather than inventing chord qualities.
    if(liveScaleDegrees.count==7) {
        NSInteger root=[liveScaleDegrees[index] integerValue];
        NSInteger third=([liveScaleDegrees[(index+2)%7] integerValue]-root+12)%12;
        NSInteger fifth=([liveScaleDegrees[(index+4)%7] integerValue]-root+12)%12;
        if(third==3 && fifth==7) return degree.lowercaseString;
        if(third==3 && fifth==6) return [degree.lowercaseString stringByAppendingString:@"°"];
        if(third==4 && fifth==8) return [degree stringByAppendingString:@"+"];
    }
    return degree;
}
static NSRect PianoDegreeLabelRegion(NSRect bounds,NSBezierPath *path,NSBezierPath *whiteMask,BOOL black) {
    if(black) return bounds;
    // Center white-key text in its exposed top stem, not in the wider base
    // where neighboring black keys would obscure a top-aligned label.
    CGFloat y=NSMaxY(bounds)-4,run=NSMinX(bounds),bestLeft=run,bestWidth=0;
    BOOL inside=NO;
    for(CGFloat x=NSMinX(bounds);x<=NSMaxX(bounds)+.5;x+=.5) {
        BOOL visible=x<NSMaxX(bounds) && [path containsPoint:NSMakePoint(x,y)] && [whiteMask containsPoint:NSMakePoint(x,y)];
        if(visible && !inside) run=x;
        if(!visible && inside && x-run>bestWidth) { bestLeft=run; bestWidth=x-run; }
        inside=visible;
    }
    return NSMakeRect(bestLeft,bounds.origin.y,bestWidth,bounds.size.height);
}
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
    NSMutableArray *degrees=[NSMutableArray new];
    if(mask) for(NSNumber *interval in state[@"scale_intervals"]) {
        NSNumber *pitch=@(([state[@"root_note"] integerValue]+interval.integerValue)%12);
        if(![degrees containsObject:pitch]) [degrees addObject:pitch];
    }
    if(mask==liveScaleMask && [degrees isEqual:liveScaleDegrees]) return;
    liveScaleMask=mask;
    liveScaleDegrees=degrees.copy;
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
    // Native drawRect computes a second pair of arrows directly from octave
    // count, ignoring upKey/downKey. They can land on playable end keys.
    // Render the existing native key paths/pressed state without those arrows.
    [piano viewWillDraw];
    [NSGraphicsContext saveGraphicsState];
    NSRect keyboard=piano.bounds;
    keyboard.origin.x+=PianoEdgeRect(piano,NO).size.width;
    keyboard.size.width-=2*PianoEdgeRect(piano,NO).size.width;
    [NSBezierPath clipRect:NSIntersectionRect(keyboard,dirty)];
    [NSColor.blackColor setFill]; NSRectFill(keyboard);
    for(id key in [piano valueForKey:@"pianoKeys"]) {
        NSBezierPath *path=[key valueForKey:@"drawPath"];
        BOOL black=[@[@1,@3,@6,@8,@10] containsObject:@(([[key valueForKey:@"pitch"] integerValue]%12+12)%12)];
        [(ScaleKeyIsPressed(piano,key) ? NSColor.redColor : black ? NSColor.blackColor : NSColor.whiteColor) setFill];
        [path fill]; [NSColor.blackColor setStroke]; [path stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    // The sole arrows occupy the same fixed regions used by touch handling.
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSIntersectionRect(piano.bounds,dirty)];
    CGFloat edge=MIN(14,piano.bounds.size.width/4);
    for(NSInteger side=0;side<2;side++) {
        CGFloat x=PianoEdgeRect(piano,side!=0).origin.x;
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
            ? [NSColor colorWithSRGBRed:.16 green:.64 blue:.74 alpha:1.0]
            : [NSColor colorWithSRGBRed:.52 green:.86 blue:.93 alpha:1.0];
        [accent setFill];
        [path fill];
        if(PianoShowsDegrees(piano)) {
            NSString *degree=ScaleDegreeForNote(start+[[key valueForKey:@"pitch"] integerValue]);
            NSRect bounds=PianoDegreeLabelRegion(NSIntersectionRect(path.bounds,piano.bounds),path,whiteMask,black);
            CGFloat fontSize=9;
            NSMutableDictionary *attributes=[@{NSFontAttributeName:[NSFont systemFontOfSize:fontSize weight:NSFontWeightBold],NSForegroundColorAttributeName:[NSColor colorWithWhite:.05 alpha:1]} mutableCopy];
            while(fontSize>5 && [degree sizeWithAttributes:attributes].width+1>NSWidth(bounds)) {
                fontSize-=.5; attributes[NSFontAttributeName]=[NSFont systemFontOfSize:fontSize weight:NSFontWeightBold];
            }
            NSSize size=[degree sizeWithAttributes:attributes];
            if(degree && size.width+1<=NSWidth(bounds)) {
                [path addClip];
                [degree drawAtPoint:NSMakePoint(NSMidX(bounds)-size.width/2,NSMaxY(piano.bounds)-size.height-1) withAttributes:attributes];
            }
        }
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
}
