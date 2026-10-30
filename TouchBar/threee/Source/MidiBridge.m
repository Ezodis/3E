#import <AppKit/AppKit.h>
#import "../../../Shared/Brand/ThreeEStatusBrand.h"
#import <ApplicationServices/ApplicationServices.h>
#import "../../../Shared/PhoneControl/MacHost/PhoneBarMenu.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <math.h>
#import <CoreMIDI/CoreMIDI.h>
#import "ReleaseUpdates.h"
#import "DJSurface.h"

// Change labels only on this engine's own streams. Do not recreate endpoints,
// change their unique IDs, or touch another application's MIDI connections.
static void BrandMIDIPorts(void) {
    NSDictionary *labels=@{@"virtualSurfaceInputStream":@"3E Surface",
                           @"virtualSurfaceOutputStream":@"3E Surface",
                           @"virtualUserInputStream":@"3E Keyboard",
                           @"virtualUserOutputStream":@"3E Keyboard"};
    for(NSString *key in labels) {
        @try {
            id stream=[(id)NSApp.delegate valueForKey:key];
            if(![stream respondsToSelector:NSSelectorFromString(@"endpoint")]) continue;
            id endpoint=[stream valueForKey:@"endpoint"];
            SEL selector=NSSelectorFromString(@"endpointRef");
            if(![endpoint respondsToSelector:selector]) continue;
            MIDIEndpointRef ref=((MIDIEndpointRef(*)(id,SEL))objc_msgSend)(endpoint,selector);
            if(!ref) continue;
            CFStringRef rawName=NULL;
            if(MIDIObjectGetStringProperty(ref,kMIDIPropertyName,&rawName)!=noErr || !rawName) continue;
            NSString *name=CFBridgingRelease(rawName);
            NSString *label=labels[key];
            if(![name isEqualToString:label] &&
               [@[@"MIDI Touchbar Surface",@"MIDI Touchbar User"] containsObject:name]) {
                if(MIDIObjectSetStringProperty(ref,kMIDIPropertyName,(__bridge CFStringRef)label)==noErr)
                    MIDIObjectSetStringProperty(ref,kMIDIPropertyDisplayName,(__bridge CFStringRef)label);
            }
        } @catch(NSException *exception) {
            // Older engine versions may not expose a stream yet; retry later.
        }
    }
}

// Loaded only into our bundled personal copy of MIDI Touchbar. Its original
// MIDI engine, storyboard, menus, defaults domain and DAW integrations remain.
static void Report(const char *message) { write(STDOUT_FILENO, message, strlen(message)); }
static void QuitThreeEParent(void) {
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.musicstrip.app"]) {
        if(app.processIdentifier==NSProcessInfo.processInfo.processIdentifier || app.terminated) continue;
        [app terminate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.75*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if(!app.terminated) [app forceTerminate];
        });
    }
}
static IMP originalOpen, originalClose, originalPresetHandler, originalChangeMode, originalShow;
static void InitializePresetCatalog(void);
static NSTouchBar *presentation;
static NSButton *closeButton;
static NSString *const CloseID = @"local.musicstrip.midi.close";
static NSString *const LayoutID = @"local.musicstrip.midi.layout";
static void Cycle(id target, SEL selector, id sender);
static void ChangeOctaves(NSInteger direction);
static void CycleOctaves(void);
static void SetOctaveCount(NSInteger next);
static void ExpandPiano(NSView *piano);
static void CollapsePiano(void);
static void ResetPianoExpansion(void);
static void CancelPianoHold(NSView *piano);
static void UpdateActivePianoSizing(void);
static void SuspendPianoSizing(NSTouchBar *bar);
static NSInteger PianoCount(NSTouchBar *bar);
static void SizePianos(NSTouchBar *bar);
static NSCustomTouchBarItem *CompactPianoRow(NSTouchBar *bar);
static char compactPianoRowKey;
static CGFloat lastMidiHostWidth;
static NSTouchBar *NormalPresetContent(NSTouchBar *bar) {
    if(PianoCount(bar)<2 || (NSUInteger)PianoCount(bar)!=bar.itemIdentifiers.count) return bar;
    NSTouchBar *content=[NSTouchBar new];
    NSCustomTouchBarItem *row=CompactPianoRow(bar);
    content.templateItems=[NSSet setWithObject:row]; content.defaultItemIdentifiers=@[row.identifier];
    content.principalItemIdentifier=row.identifier;
    return content;
}
static void TransferPianoInstance(NSView *source,NSView *replacement);
static void SaveExpandedPianoSettings(void);
static void CycleExpandedPianoSetting(BOOL channel,NSInteger direction);
static NSString *PianoModeName(NSInteger mode) { return @[@"glissando",@"noglissando",@"pitchbend"][MIN(2,MAX(0,mode))]; }
@class PianoArrowHold;
static NSMapTable<NSView *,PianoArrowHold *> *pianoHolds;
static BOOL pianoExpanded, rebuildingPresentation;
static NSTouchBar *normalLayoutBar;
static id normalIdentifier;
static NSCustomTouchBarItem *expandedPianoItem;
static NSView *expandedPianoView;
static NSView *expandedPianoContainer;
static NSUInteger presentationSerial;
static NSView *normalPianoView;
static NSArray<NSLayoutConstraint *> *pianoWidthConstraints;
static NSRect pianoNormalFrame;
static NSLayoutPriority pianoHugging, pianoResistance;
static NSLayoutConstraint *pianoFullWidthConstraint;
static CGFloat pianoFullWidth;
static NSInteger pianoNormalOctaves;
static IMP originalPianoBegan, originalPianoMoved, originalPianoEnded, originalPianoCancelled, originalPianoLayout;
static char halfOctaveKey,halfGeometryKey;
static BOOL PianoHalf(NSView *piano) { return [objc_getAssociatedObject(piano,&halfOctaveKey) boolValue]; }
static NSInteger PianoStartNote(NSView *piano) { return [[piano valueForKey:@"startOctave"] integerValue]*12+(PianoHalf(piano) ? 6 : 0); }
static NSRect PianoEdgeRect(NSView *piano,BOOL right) {
    NSRect bounds=piano.bounds;
    CGFloat edge=MIN(14,bounds.size.width/4);
    return NSMakeRect(right ? NSMaxX(bounds)-edge : NSMinX(bounds),NSMinY(bounds),edge,bounds.size.height);
}
static void SetPianoStartNote(NSView *piano,NSInteger note) {
    NSInteger octaves=[[piano valueForKey:@"numOctaves"] integerValue];
    note=MIN(MAX(0,note),MAX(0,(10-octaves)*12));
    [piano setValue:@(note/12) forKey:@"startOctave"];
    objc_setAssociatedObject(piano,&halfOctaveKey,@(note%12==6),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [piano setValue:@(-1) forKey:@"lastWidth"]; piano.needsDisplay=YES;
}
static BOOL PianoKeyIsBlack(id key) {
    NSInteger pitch=([[key valueForKey:@"pitch"] integerValue]%12+12)%12;
    return [@[@1,@3,@6,@8,@10] containsObject:@(pitch)];
}
static NSArray<NSValue *> *ClipPianoPolygon(NSArray<NSValue *> *points,NSRect rect) {
    for(NSInteger edge=0;edge<4 && points.count;edge++) {
        NSMutableArray *next=[NSMutableArray new]; NSPoint previous=points.lastObject.pointValue;
        CGFloat limit=edge==0 ? NSMinX(rect) : edge==1 ? NSMaxX(rect) : edge==2 ? NSMinY(rect) : NSMaxY(rect);
        for(NSValue *value in points) {
            NSPoint point=value.pointValue;
            CGFloat a=edge<2 ? previous.x : previous.y,b=edge<2 ? point.x : point.y;
            BOOL insideA=edge%2==0 ? a>=limit : a<=limit,insideB=edge%2==0 ? b>=limit : b<=limit;
            if(insideA!=insideB) {
                CGFloat ratio=(limit-a)/(b-a);
                [next addObject:[NSValue valueWithPoint:NSMakePoint(previous.x+ratio*(point.x-previous.x),previous.y+ratio*(point.y-previous.y))]];
            }
            if(insideB) [next addObject:value]; previous=point;
        }
        points=next;
    }
    return points;
}
static NSBezierPath *ClippedPianoPath(NSBezierPath *shape,NSRect rect) {
    NSBezierPath *copy=shape.copy; copy.flatness=.1;
    NSBezierPath *flat=copy.bezierPathByFlatteningPath,*result=[NSBezierPath bezierPath];
    NSMutableArray *points=[NSMutableArray new];
    for(NSInteger i=0;i<=flat.elementCount;i++) {
        NSPoint point[3]; NSBezierPathElement element=i<flat.elementCount ? [flat elementAtIndex:i associatedPoints:point] : NSBezierPathElementClosePath;
        if(element==NSBezierPathElementMoveTo || element==NSBezierPathElementClosePath) {
            NSArray *clipped=ClipPianoPolygon(points,rect);
            if(clipped.count>=3) {
                [result moveToPoint:[clipped.firstObject pointValue]];
                for(NSValue *value in [clipped subarrayWithRange:NSMakeRange(1,clipped.count-1)]) [result lineToPoint:value.pointValue];
                [result closePath];
            }
            [points removeAllObjects];
        }
        if(element==NSBezierPathElementMoveTo || element==NSBezierPathElementLineTo) [points addObject:[NSValue valueWithPoint:point[0]]];
    }
    return result;
}
@interface PianoWhiteHitPath : NSBezierPath
@property NSArray<NSBezierPath *> *blackContours;
@end
@implementation PianoWhiteHitPath
- (BOOL)containsPoint:(NSPoint)point {
    // A black contour owns its shared edge too. AppKit's even-odd path test
    // can otherwise include the coincident edge of a clipped white hole.
    for(NSBezierPath *black in self.blackContours) if([black containsPoint:point]) return NO;
    return [super containsPoint:point];
}
@end
static void SetPianoHitRegions(NSView *piano) {
    NSRect keyboard=piano.bounds;
    CGFloat edge=PianoEdgeRect(piano,NO).size.width;
    keyboard.origin.x+=edge; keyboard.size.width=MAX(0,keyboard.size.width-2*edge);
    if(NSIsEmptyRect(keyboard)) return;
    NSMutableArray *whiteKeys=[NSMutableArray new],*blackPaths=[NSMutableArray new];
    for(id key in [piano valueForKey:@"pianoKeys"]) {
        if(PianoKeyIsBlack(key)) {
            NSBezierPath *path=ClippedPianoPath([key valueForKey:@"drawPath"],keyboard);
            [key setValue:path forKey:@"touchPath"];
            if(path.elementCount) [blackPaths addObject:path];
        } else [whiteKeys addObject:key];
    }
    [whiteKeys sortUsingComparator:^NSComparisonResult(id a,id b) {
        CGFloat left=NSMinX([[a valueForKey:@"drawPath"] bounds]),right=NSMinX([[b valueForKey:@"drawPath"] bounds]);
        return left<right ? NSOrderedAscending : left>right ? NSOrderedDescending : NSOrderedSame;
    }];
    for(NSUInteger i=0;i<whiteKeys.count;i++) {
        id key=whiteKeys[i]; NSRect shape=[[key valueForKey:@"drawPath"] bounds];
        CGFloat left=i ? (NSMaxX([[whiteKeys[i-1] valueForKey:@"drawPath"] bounds])+NSMinX(shape))/2 : NSMinX(keyboard);
        CGFloat right=i+1<whiteKeys.count ? (NSMaxX(shape)+NSMinX([[whiteKeys[i+1] valueForKey:@"drawPath"] bounds]))/2 : NSMaxX(keyboard);
        NSRect rect=NSIntersectionRect(NSMakeRect(left,keyboard.origin.y,MAX(0,right-left),keyboard.size.height),keyboard);
        PianoWhiteHitPath *path=[PianoWhiteHitPath new]; [path appendBezierPathWithRect:rect]; path.windingRule=NSWindingRuleEvenOdd;
        NSMutableArray *adjacentBlackContours=[NSMutableArray new];
        // Follow the visible black-key contours, including their rounded
        // lower edge, instead of cutting every key at an imaginary halfway line.
        for(NSBezierPath *black in blackPaths) if(NSIntersectsRect(rect,black.bounds)) {
            [adjacentBlackContours addObject:black];
            [path appendBezierPath:ClippedPianoPath(black,rect)];
        }
        path.blackContours=adjacentBlackContours;
        [key setValue:path forKey:@"touchPath"];
    }
}
// Keep the original key shapes, note engine and appearance. Split touch
// regions separately after generating the final visible keyboard geometry.
// At a half-octave position, rotate the generated keyboard window by six notes.
static void StabilizePianoEdges(NSView *piano) {
    CGFloat width=piano.bounds.size.width,edge=MIN(14,width/4);
    if(width<=0) return;
    NSInteger octaves=[[piano valueForKey:@"numOctaves"] integerValue];
    if(octaves>0 && (width-2*edge)/(octaves*7)<10) {
        // Native fixed pixel gutters dominate very narrow keys. Generate the
        // same native shapes at a readable density, then scale the geometry
        // together so gutters shrink proportionally instead of eating keys.
        NSInteger start=[[piano valueForKey:@"startOctave"] integerValue];
        NSView *sample=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),(int)octaves,(int)start);
        sample.frame=NSMakeRect(0,0,octaves*7*14+2*edge,30);
        ((void(*)(id,SEL))originalPianoLayout)(sample,@selector(viewWillDraw));
        for(NSString *name in @[@"pianoKeys",@"upKey",@"downKey"]) [piano setValue:[sample valueForKey:name] forKey:name];
        NSArray *labels=[piano valueForKey:@"textFields"],*sampleLabels=[sample valueForKey:@"textFields"];
        for(NSUInteger i=0;i<MIN(labels.count,sampleLabels.count);i++) ((NSView *)labels[i]).frame=((NSView *)sampleLabels[i]).frame;
    }
    NSArray *keys=[piano valueForKey:@"pianoKeys"];
    CGFloat left=CGFLOAT_MAX,right=-CGFLOAT_MAX;
    for(id key in keys) {
        NSRect rect=[[key valueForKey:@"drawPath"] bounds];
        left=MIN(left,NSMinX(rect)); right=MAX(right,NSMaxX(rect));
    }
    if(right>left) {
        CGFloat scale=(width-2*edge)/(right-left);
        NSAffineTransform *transform=[NSAffineTransform transform];
        transform.transformStruct=(NSAffineTransformStruct){scale,0,0,1,edge-left*scale,0};
        for(id key in keys) for(NSString *name in @[@"drawPath",@"touchPath"]) {
            NSBezierPath *path=[[key valueForKey:name] copy]; [path transformUsingAffineTransform:transform]; [key setValue:path forKey:name];
        }
        for(NSTextField *label in [piano valueForKey:@"textFields"]) {
            NSRect rect=label.frame; rect.origin.x=edge+(rect.origin.x-left)*scale;
            rect.size.width*=scale; label.frame=rect;
        }
    }
    for(NSString *name in @[@"downKey",@"upKey"]) {
        NSBezierPath *path=[[piano valueForKey:name] copy]; NSRect rect=path.bounds;
        if(rect.size.width<=0) continue;
        CGFloat scale=edge/rect.size.width,target=[name isEqual:@"upKey"] ? width-edge : 0;
        NSAffineTransform *transform=[NSAffineTransform transform];
        transform.transformStruct=(NSAffineTransformStruct){scale,0,0,1,target-rect.origin.x*scale,0};
        [path transformUsingAffineTransform:transform]; [piano setValue:path forKey:name];
    }
}
static void PianoLayout(NSView *piano,SEL selector) {
    BOOL rebuilt=[[piano valueForKey:@"lastWidth"] doubleValue]!=piano.bounds.size.width;
    ((void(*)(id,SEL))originalPianoLayout)(piano,selector);
    if(rebuilt) StabilizePianoEdges(piano);
    if(!PianoHalf(piano)) { if(rebuilt) SetPianoHitRegions(piano); return; }
    NSArray *keys=[piano valueForKey:@"pianoKeys"];
    NSMutableDictionary *templates=[NSMutableDictionary dictionary];
    for(id key in keys) { NSInteger pitch=[[key valueForKey:@"pitch"] integerValue]; if(pitch>=0 && pitch<12) templates[@(pitch)]=key; }
    NSInteger octaves=[[piano valueForKey:@"numOctaves"] integerValue];
    NSDictionary *geometry=objc_getAssociatedObject(piano,&halfGeometryKey);
    if(templates.count==12) {
        CGFloat left=CGFLOAT_MAX,right=-CGFLOAT_MAX;
        for(id key in keys) { NSBezierPath *path=[key valueForKey:@"drawPath"]; left=MIN(left,NSMinX(path.bounds));right=MAX(right,NSMaxX(path.bounds)); }
        // Ask the original engine for interior key shapes, avoiding its special
        // first/last edge keys. Copy those exact paths into the shifted window.
        NSView *sample=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),3,0);
        sample.frame=NSMakeRect(0,0,600,30); ((void(*)(id,SEL))originalPianoLayout)(sample,selector);
        NSMutableDictionary *interior=[NSMutableDictionary dictionary];
        for(id key in [sample valueForKey:@"pianoKeys"]) interior[[key valueForKey:@"pitch"]]=key;
        NSBezierPath *c=[interior[@12] valueForKey:@"drawPath"],*d=[interior[@14] valueForKey:@"drawPath"],*nextD=[interior[@26] valueForKey:@"drawPath"],*fs=[interior[@18] valueForKey:@"drawPath"];
        CGFloat period=NSMinX(nextD.bounds)-NSMinX(d.bounds);
        if(period<=0 || right<=left) return;
        CGFloat scale=(right-left)/(octaves*period),shift=(NSMidX(fs.bounds)-NSMinX(c.bounds))*scale,span=period*scale;
        CGFloat labelOffset=((NSView *)[[piano valueForKey:@"textFields"] firstObject]).frame.origin.x-left;
        geometry=@{@"left":@(left),@"span":@(span),@"shift":@(shift),@"labelOffset":@(labelOffset)};
        objc_setAssociatedObject(piano,&halfGeometryKey,geometry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSMutableArray *shifted=[NSMutableArray array];
        // Preserve the original drawing/hit-test order as well as its curves.
        for(id source in [sample valueForKey:@"pianoKeys"]) {
            NSInteger pc=[[source valueForKey:@"pitch"] integerValue]-12; if(pc<0 || pc>=12) continue;
            for(NSInteger octave=0;octave<=octaves;octave++) {
                NSInteger pitch=octave*12+pc; if(pitch<6 || pitch>=octaves*12+6) continue;
                id key=[[source class] new]; [key setValue:[source valueForKey:@"type"] forKey:@"type"]; [key setValue:@(pitch) forKey:@"pitch"];
                NSAffineTransform *transform=[NSAffineTransform transform];
                transform.transformStruct=(NSAffineTransformStruct){scale,0,0,1,left-NSMinX(c.bounds)*scale+octave*span-shift,0};
                for(NSString *name in @[@"drawPath",@"touchPath"]) { NSBezierPath *path=[[source valueForKey:name] copy]; [path transformUsingAffineTransform:transform]; [key setValue:path forKey:name]; }
                [shifted addObject:key];
            }
        }
        [piano setValue:shifted forKey:@"pianoKeys"];
    }
    if(!geometry) return;
    NSArray *labels=[piano valueForKey:@"textFields"];
    for(NSUInteger i=0;i<labels.count;i++) {
        NSTextField *label=labels[i]; NSRect frame=label.frame;
        frame.origin.x=[geometry[@"left"] doubleValue]+(i+1)*[geometry[@"span"] doubleValue]-[geometry[@"shift"] doubleValue]+[geometry[@"labelOffset"] doubleValue]; label.frame=frame;
        NSRegularExpression *number=[NSRegularExpression regularExpressionWithPattern:@"-?[0-9]+" options:0 error:nil];
        NSTextCheckingResult *match=[number firstMatchInString:label.stringValue options:0 range:NSMakeRange(0,label.stringValue.length)];
        if(match) label.stringValue=[label.stringValue stringByReplacingCharactersInRange:match.range withString:[NSString stringWithFormat:@"%ld",(long)([[label.stringValue substringWithRange:match.range] integerValue]+1)]];
    }
    if(rebuilt || templates.count==12) SetPianoHitRegions(piano);
}
static void MovePianoHalf(NSView *piano,NSInteger direction) {
    if([[piano valueForKey:@"activeKeys"] count]) return;
    SetPianoStartNote(piano,PianoStartNote(piano)+direction*6);
    Report("PIANO_HALF_MOVED\n");
}
#import "PianoScale.h"
static NSString *const OctavesID = @"local.musicstrip.midi.octaves";
static NSString *const NavigationID = @"local.musicstrip.midi.navigation";
@interface MidiNavigationButton : NSButton
@property BOOL tracking;
@property BOOL cancelled;
@property BOOL held;
@property BOOL didStep;
@property CGFloat startX;
@property CGFloat endX;
@property CGFloat startY;
@property CGFloat endY;
@property BOOL octaveControl;
@property NSString *stackedCaption;
@property BOOL octaveSpanSymbol;
@property NSInteger joinedEdge; // 1 = left half, 2 = right half; 0 = native bezel.
@property NSInteger optionSegment; // 1..3 for the expanded piano's joined settings.
@property BOOL standaloneRecord;
@property BOOL degreeToggle;
@property BOOL degreeToggleOn;
@property BOOL compactGlyph;
@property BOOL firstConfigurationSegment;
@property BOOL configurationHasClose;
@property BOOL iconAboveCaption;
@property CGFloat presetHue;
@property BOOL recordLit;
@property id touchIdentity;
@property NSTimer *holdTimer;
- (void)beginAt:(NSPoint)point identity:(id)identity;
- (void)moveAt:(NSPoint)point;
- (void)finishAt:(NSPoint)point;
- (void)fireHold;
- (void)cancelGesture;
- (void)step:(NSInteger)direction;
@end
static MidiNavigationButton *navigationButton;
static MidiNavigationButton *octavesButton;
static NSView *pianoConfigurationGroup;
@implementation MidiNavigationButton
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.title=@""; self.bezelStyle=NSBezelStyleRounded;
        self.buttonType=NSButtonTypeMomentaryLight; self.imagePosition=NSImageOnly;
        self.allowedTouchTypes=NSTouchTypeMaskDirect; self.wantsRestingTouches=YES;
        self.image=[NSImage imageWithSize:NSMakeSize(24,16) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            [[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:nil] drawInRect:NSMakeRect(1,2,8,12)];
            [[NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil] drawInRect:NSMakeRect(15,2,8,12)];
            return YES;
        }];
        self.image.template=YES; self.imageScaling=NSImageScaleProportionallyDown;
        [self setAccessibilityLabel:@"MIDI presets: tap left for previous or right for next; swipe left for previous or right for next; hold to switch control-surface mode"];
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(44,30); }
- (void)drawRect:(NSRect)dirtyRect {
    if(self.stackedCaption) {
        [NSGraphicsContext saveGraphicsState];
        [NSBezierPath clipRect:NSIntersectionRect(self.bounds,dirtyRect)];
        NSInteger segment=self.optionSegment ?: (self.joinedEdge==2 ? 2 : 1);
        CGFloat groupWidth=self.configurationHasClose ? 132 : self.optionSegment ? 132 : 88;
        CGFloat segmentOffset=self.configurationHasClose ? (segment==1 ? 32 : segment==2 ? 68 : 104) : 44*(segment-1);
        NSRect whole=NSMakeRect(-segmentOffset,1,groupWidth,28);
        [[NSBezierPath bezierPathWithRoundedRect:whole xRadius:7 yRadius:7] addClip];
        NSColor *start=[NSColor colorWithCalibratedHue:self.presetHue saturation:.72 brightness:.82 alpha:1];
        NSColor *end=[NSColor colorWithCalibratedHue:fmod(self.presetHue+.10,1) saturation:.85 brightness:.46 alpha:1];
        [[[NSGradient alloc] initWithStartingColor:start endingColor:end] drawInRect:whole angle:0];
        if(self.highlighted) { [[NSColor colorWithWhite:1 alpha:.12] setFill]; NSRectFill(self.bounds); }
        if(segment>1 || self.firstConfigurationSegment) { [[NSColor colorWithWhite:1 alpha:.12] setFill]; NSRectFill(NSMakeRect(0,5,.5,20)); }
        if(self.degreeToggle) {
            NSColor *tint=self.degreeToggleOn ? [NSColor colorWithSRGBRed:.52 green:.86 blue:.93 alpha:1] : [NSColor colorWithWhite:.55 alpha:1];
            if(self.degreeToggleOn) { [[tint colorWithAlphaComponent:.16] setFill]; NSRectFillUsingOperation(self.bounds,NSCompositingOperationSourceOver); }
            CGFloat glyphWidth=self.compactGlyph ? 14 : 22, glyphHeight=self.compactGlyph ? 12 : 18;
            NSImage *symbol=[NSImage imageWithSize:NSMakeSize(glyphWidth,glyphHeight) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                NSSize size=self.image.size;
                CGFloat ratio=MIN(glyphWidth/MAX(1,size.width),glyphHeight/MAX(1,size.height));
                NSSize fitted=NSMakeSize(size.width*ratio,size.height*ratio);
                [self.image drawInRect:NSMakeRect((glyphWidth-fitted.width)/2,(glyphHeight-fitted.height)/2,fitted.width,fitted.height)];
                [tint setFill]; NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn); return YES;
            }];
            [symbol drawInRect:NSMakeRect((NSWidth(self.bounds)-glyphWidth)/2,(30-glyphHeight)/2,glyphWidth,glyphHeight)];
            if(self.degreeToggleOn) { [tint setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSWidth(self.bounds)-9,23,4,4)] fill]; }
            [NSGraphicsContext restoreGraphicsState]; return;
        }
        if(self.image) {
            CGFloat glyphWidth=self.iconAboveCaption ? 16 : 18, glyphHeight=self.iconAboveCaption ? 12 : 13;
            NSImage *glyph=[NSImage imageWithSize:NSMakeSize(glyphWidth,glyphHeight) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                NSSize size=self.image.size;
                CGFloat scale=MIN(glyphWidth/MAX(1,size.width),glyphHeight/MAX(1,size.height));
                NSSize fitted=NSMakeSize(size.width*scale,size.height*scale);
                [self.image drawInRect:NSMakeRect((glyphWidth-fitted.width)/2,(glyphHeight-fitted.height)/2,fitted.width,fitted.height)];
                [NSColor.whiteColor setFill]; NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn); return YES;
            }];
            [glyph drawInRect:NSMakeRect((NSWidth(self.bounds)-glyphWidth)/2,self.iconAboveCaption ? 2 : 14,glyphWidth,glyphHeight)];
        } else {
            NSDictionary *top=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.whiteColor};
            NSSize size=[self.title sizeWithAttributes:top];
            [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds)-size.width)/2,11) withAttributes:top];
        }
        NSDictionary *bottom=@{NSFontAttributeName:[NSFont systemFontOfSize:8 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor colorWithWhite:.90 alpha:1]};
        if(self.octaveSpanSymbol) {
            // A miniature keyboard enclosed by span markers, without text.
            NSBezierPath *span=[NSBezierPath bezierPath];
            CGFloat keyboardWidth=MIN(16,MAX(10,NSWidth(self.bounds)-16));
            CGFloat keyboardX=(NSWidth(self.bounds)-keyboardWidth)/2;
            [span moveToPoint:NSMakePoint(keyboardX-3,3)]; [span lineToPoint:NSMakePoint(keyboardX-3,9)];
            [span moveToPoint:NSMakePoint(keyboardX+keyboardWidth+3,3)]; [span lineToPoint:NSMakePoint(keyboardX+keyboardWidth+3,9)];
            [span appendBezierPathWithRect:NSMakeRect(keyboardX,3,keyboardWidth,6)];
            for(NSInteger i=1;i<7;i++) {
                CGFloat x=keyboardX+i*keyboardWidth/7;
                [span moveToPoint:NSMakePoint(x,3)]; [span lineToPoint:NSMakePoint(x,9)];
            }
            span.lineWidth=.65; [[NSColor colorWithWhite:.90 alpha:1] setStroke]; [span stroke];
        } else {
            NSSize size=[self.stackedCaption sizeWithAttributes:bottom];
            [self.stackedCaption drawAtPoint:NSMakePoint((NSWidth(self.bounds)-size.width)/2,self.iconAboveCaption ? 16 : 2) withAttributes:bottom];
        }
        [NSGraphicsContext restoreGraphicsState]; return;
    }
    if(!self.joinedEdge && !self.standaloneRecord) { [super drawRect:dirtyRect]; return; }
    [NSGraphicsContext saveGraphicsState];
    NSRect whole=self.standaloneRecord ? self.bounds : NSMakeRect(self.joinedEdge==2 ? -32 : 0,0,76,30);
    [[NSBezierPath bezierPathWithRoundedRect:whole xRadius:7 yRadius:7] addClip];
    NSColor *start, *end;
    if(self.joinedEdge==1 || self.standaloneRecord) {
        start=self.recordLit ? [NSColor colorWithSRGBRed:.95 green:.12 blue:.18 alpha:1] : [NSColor colorWithWhite:.20 alpha:1];
        end=self.recordLit ? [NSColor colorWithSRGBRed:.64 green:.02 blue:.10 alpha:1] : [NSColor colorWithWhite:.11 alpha:1];
    } else {
        start=[NSColor colorWithCalibratedHue:self.presetHue saturation:.72 brightness:.82 alpha:1];
        end=[NSColor colorWithCalibratedHue:fmod(self.presetHue+.10,1) saturation:.85 brightness:.46 alpha:1];
    }
    [[[NSGradient alloc] initWithStartingColor:start endingColor:end] drawInRect:whole angle:0];
    if(self.highlighted) { [[NSColor colorWithWhite:1 alpha:.16] setFill]; NSRectFillUsingOperation(self.bounds,NSCompositingOperationSourceOver); }
    if(self.imagePosition!=NSNoImage && self.image) {
        NSColor *tint=NSColor.whiteColor;
        NSImage *glyph=[NSImage imageWithSize:self.image.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
            [self.image drawInRect:rect]; [tint setFill]; NSRectFillUsingOperation(rect,NSCompositingOperationSourceIn); return YES;
        }];
        NSSize source=glyph.size;
        CGFloat scale=MIN(24/MAX(1,source.width),16/MAX(1,source.height));
        NSSize fitted=NSMakeSize(source.width*scale,source.height*scale);
        [glyph drawInRect:NSMakeRect((NSWidth(self.bounds)-fitted.width)/2,(NSHeight(self.bounds)-fitted.height)/2,fitted.width,fitted.height)];
    } else {
        NSDictionary *attributes=@{NSFontAttributeName:self.font ?: [NSFont systemFontOfSize:9],NSForegroundColorAttributeName:NSColor.whiteColor};
        NSSize size=[self.title sizeWithAttributes:attributes];
        [self.title drawAtPoint:NSMakePoint((44-size.width)/2,(30-size.height)/2) withAttributes:attributes];
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (void)highlight:(BOOL)flag { [super highlight:flag]; if(self.joinedEdge) self.needsDisplay=YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSView *)hitTest:(NSPoint)point { return NSPointInRect([self convertPoint:point fromView:self.superview],self.bounds) ? self : nil; }
- (void)beginAt:(NSPoint)point identity:(id)identity {
    if (self.tracking || !NSPointInRect(point,self.bounds)) return;
    self.tracking=YES; self.cancelled=NO; self.held=NO; self.didStep=NO;
    self.startX=self.endX=point.x; self.startY=self.endY=point.y; self.touchIdentity=identity;
    [self highlight:YES];
    [self.holdTimer invalidate];
    if(self.octaveControl) return;
    __weak MidiNavigationButton *weakSelf=self;
    self.holdTimer=[NSTimer timerWithTimeInterval:0.65 repeats:NO block:^(NSTimer *timer){ [weakSelf fireHold]; }];
    [NSRunLoop.mainRunLoop addTimer:self.holdTimer forMode:NSRunLoopCommonModes];
}
- (void)step:(NSInteger)direction {
    if(!self.tracking || self.cancelled || self.held || self.didStep) return;
    self.didStep=YES;
    [self.holdTimer invalidate]; self.holdTimer=nil; [self highlight:NO];
    BOOL octaves=self.octaveControl;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(octaves) ChangeOctaves(direction);
        else Cycle(NSApp.delegate,NSSelectorFromString(direction<0 ? @"threeECycleBack:" : @"threeECycle:"),nil);
    });
}
- (void)moveAt:(NSPoint)point {
    if (!self.tracking) return;
    self.endX=point.x; self.endY=point.y;
    CGFloat dx=self.endX-self.startX, dy=self.endY-self.startY;
    // Commit horizontal movement once, even if the finger leaves the button.
    if(fabs(dx)>=8 && fabs(dx)>=fabs(dy)) [self step:dx>0 ? 1 : -1];
    if(fabs(dy)>=3 || fabs(dx)>=8) { [self.holdTimer invalidate]; self.holdTimer=nil; }
}
- (void)fireHold {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if (self.octaveControl || !self.tracking || self.cancelled || self.held || self.didStep || fabs(self.endY-self.startY)>=3 || fabs(self.endX-self.startX)>=8) return;
    self.held=YES;
    // A held preset switch is inert. Arrangement/control-surface access now
    // belongs exclusively to the Record hold gesture.
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if (!self.tracking) return;
    [self moveAt:point];
    CGFloat dx=point.x-self.startX, dy=point.y-self.startY;
    if(!self.didStep && !self.held && !self.cancelled && NSPointInRect(point,self.bounds) && hypot(dx,dy)<8) {
        if(self.octaveControl) CycleOctaves();
        else { BOOL back=self.startX<NSMidX(self.bounds); [self step:back ? -1 : 1]; }
    }
    self.tracking=NO; self.touchIdentity=nil; [self highlight:NO];
}
- (void)cancelGesture {
    self.cancelled=YES; self.tracking=NO; self.touchIdentity=nil;
    [self.holdTimer invalidate]; self.holdTimer=nil; [self highlight:NO];
}
- (void)touchesBeganWithEvent:(NSEvent *)event {
    NSSet<NSTouch *> *touches=[event touchesMatchingPhase:NSTouchPhaseBegan inView:self];
    if (self.tracking || touches.count!=1) { [self cancelGesture]; return; }
    NSTouch *touch=touches.anyObject;
    if(touch.type==NSTouchTypeDirect) [self beginAt:[touch locationInView:self] identity:touch.identity];
}
- (void)touchesMovedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:nil]) if([touch.identity isEqual:self.touchIdentity]) [self moveAt:[touch locationInView:self]];
}
- (void)touchesEndedWithEvent:(NSEvent *)event {
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseEnded inView:nil]) if([touch.identity isEqual:self.touchIdentity]) [self finishAt:[touch locationInView:self]];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event { [self cancelGesture]; }
- (void)mouseDown:(NSEvent *)event { [self beginAt:[self convertPoint:event.locationInWindow fromView:nil] identity:nil]; }
- (void)mouseDragged:(NSEvent *)event { [self moveAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self finishAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (BOOL)accessibilityPerformPress { if(self.octaveControl) CycleOctaves(); else Cycle(NSApp.delegate,NSSelectorFromString(@"threeECycle:"),nil); return YES; }
- (void)dealloc { [self.holdTimer invalidate]; }
@end
static void UpdateNavigationColor(void);
@interface PianoConfigButton : MidiNavigationButton
@property BOOL channelControl;
@end
@implementation PianoConfigButton
- (void)step:(NSInteger)direction {
    if(!self.tracking || self.cancelled || self.didStep) return;
    self.didStep=YES; [self highlight:NO];
    CycleExpandedPianoSetting(self.channelControl,direction);
}
- (void)finishAt:(NSPoint)point {
    if(self.tracking && !self.cancelled && !self.didStep && NSPointInRect(point,self.bounds) && hypot(point.x-self.startX,point.y-self.startY)<8) [self step:1];
    [super finishAt:point];
}
@end
static PianoConfigButton *pianoModeButton,*pianoChannelButton;
@interface PianoDegreeButton : MidiNavigationButton
@end
static PianoDegreeButton *pianoDegreeButton;
static void UpdateDegreeButton(void) {
    BOOL enabled=PianoShowsDegrees(expandedPianoView);
    pianoDegreeButton.title=@"";
    pianoDegreeButton.stackedCaption=@"";
    pianoDegreeButton.degreeToggle=YES; pianoDegreeButton.degreeToggleOn=enabled;
    pianoDegreeButton.compactGlyph=YES;
    pianoDegreeButton.image=[NSImage imageWithSystemSymbolName:@"music.note.list" accessibilityDescription:@"Scale harmony"] ?: [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:@"Scale harmony"];
    pianoDegreeButton.needsDisplay=YES;
    [pianoDegreeButton setAccessibilityLabel:enabled ? @"Scale degrees shown. Tap to hide." : @"Scale degrees hidden. Tap to show."];
}
@implementation PianoDegreeButton
- (void)toggleDegrees {
    SetPianoShowsDegrees(expandedPianoView,!PianoShowsDegrees(expandedPianoView));
    SaveExpandedPianoSettings(); UpdateDegreeButton();
}
- (void)step:(NSInteger)direction {
    if(!self.tracking || self.cancelled || self.didStep) return;
    self.didStep=YES; [self highlight:NO]; [self toggleDegrees];
}
- (void)finishAt:(NSPoint)point {
    if(self.tracking && !self.cancelled && !self.didStep && NSPointInRect(point,self.bounds) && hypot(point.x-self.startX,point.y-self.startY)<8) [self step:1];
    [super finishAt:point];
}
- (BOOL)accessibilityPerformPress { [self toggleDegrees]; return YES; }
@end
static void UpdatePianoConfigControls(void) {
    UpdateDegreeButton();
    NSInteger mode=[[expandedPianoView valueForKey:@"type"] integerValue]; mode=MIN(2,MAX(0,mode));
    pianoModeButton.title=@[@"GLISS",@"HOLD",@"BEND"][mode];
    pianoModeButton.stackedCaption=pianoModeButton.title;
    pianoModeButton.image=[NSImage imageWithSystemSymbolName:@[@"pianokeys",@"hand.raised.fill",@"waveform"][mode] accessibilityDescription:nil];
    pianoModeButton.iconAboveCaption=YES;
    pianoModeButton.needsDisplay=YES;
    [pianoModeButton setAccessibilityLabel:[NSString stringWithFormat:@"Piano gesture: %@. Tap to cycle, swipe left or right to change.",@[@"Glissando",@"No Glissando",@"Pitchbend"][mode]]];
    pianoChannelButton.title=[NSString stringWithFormat:@"Ch %@",[expandedPianoView valueForKey:@"channelNumber"]];
    [pianoChannelButton setAccessibilityLabel:[NSString stringWithFormat:@"MIDI channel %@. Tap or swipe to change this piano only.",[expandedPianoView valueForKey:@"channelNumber"]]];
}
#import "AbletonRecord.h"
@interface StripJoinedMidiControl : NSView
@property(weak) MidiNavigationButton *navigation;
@property CGFloat presetHue;
@end
@implementation StripJoinedMidiControl
- (NSSize)intrinsicContentSize { return self.frame.size; }
- (void)drawRect:(NSRect)dirtyRect {
    CGFloat hue=self.navigation ? self.navigation.presetHue : self.presetHue;
    NSColor *start=[NSColor colorWithCalibratedHue:hue saturation:.72 brightness:.82 alpha:1];
    NSColor *end=[NSColor colorWithCalibratedHue:fmod(hue+.10,1) saturation:.85 brightness:.46 alpha:1];
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7 yRadius:7] addClip];
    [[[NSGradient alloc] initWithStartingColor:start endingColor:end] drawInRect:self.bounds angle:0];
    [NSGraphicsContext restoreGraphicsState];
}
@end
static void UpdateNavigationColor(void) {
    id delegate=NSApp.delegate;
    NSInteger preset=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSUInteger count=[[delegate valueForKey:@"allUserTouchbars"] count];
    BOOL surface=[[delegate valueForKey:@"controlSurfadeMode"] boolValue];
    CGFloat hue=surface ? .08 : fmod(.58+MAX(0,preset)/(double)MAX(1,count),1);
    if(navigationButton) {
        if(navigationButton.presetHue!=hue) { navigationButton.presetHue=hue; navigationButton.needsDisplay=YES; navigationButton.superview.needsDisplay=YES; }
        navigationButton.toolTip=surface ? @"MIDI Control Surface" : [NSString stringWithFormat:@"MIDI preset %ld",(long)preset+1];
    }
    if(pianoConfigurationGroup) {
        ((StripJoinedMidiControl *)pianoConfigurationGroup).presetHue=hue;
        pianoConfigurationGroup.needsDisplay=YES;
    }
    NSArray *pianoButtons=@[pianoModeButton ?: (id)NSNull.null,octavesButton ?: (id)NSNull.null,pianoDegreeButton ?: (id)NSNull.null];
    for(id button in pianoButtons) if(button!=NSNull.null) { [button setPresetHue:hue]; [button setNeedsDisplay:YES]; }
}
static NSView *JoinCloseNavigation(NSButton *close,MidiNavigationButton *navigation,NSInteger preset,NSUInteger count) {
    navigation.presetHue=fmod(.58+MAX(0,preset)/(double)MAX(1,count),1);
    navigation.joinedEdge=2;
    NSView *joined=[[StripJoinedMidiControl alloc] initWithFrame:NSMakeRect(0,0,76,30)];
    ((StripJoinedMidiControl *)joined).navigation=navigation;
    joined.translatesAutoresizingMaskIntoConstraints=NO;
    [joined setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [joined setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    close.frame=NSMakeRect(0,0,32,30); navigation.frame=NSMakeRect(32,0,44,30);
    close.translatesAutoresizingMaskIntoConstraints=NO;
    navigation.translatesAutoresizingMaskIntoConstraints=NO;
    [joined addSubview:close]; [joined addSubview:navigation];
    [NSLayoutConstraint activateConstraints:@[
        [joined.widthAnchor constraintEqualToConstant:76], [joined.heightAnchor constraintEqualToConstant:30],
        [close.leadingAnchor constraintEqualToAnchor:joined.leadingAnchor],
        [close.topAnchor constraintEqualToAnchor:joined.topAnchor],
        [close.widthAnchor constraintEqualToConstant:32],
        [close.heightAnchor constraintEqualToConstant:30],
        [navigation.leadingAnchor constraintEqualToAnchor:close.trailingAnchor],
        [navigation.topAnchor constraintEqualToAnchor:joined.topAnchor],
        [navigation.widthAnchor constraintEqualToConstant:44],
        [navigation.heightAnchor constraintEqualToConstant:30],
        [navigation.trailingAnchor constraintEqualToAnchor:joined.trailingAnchor]
    ]];
    return joined;
}
static void RemoveCycleKey(id delegate) {
    id center = [delegate valueForKey:@"keyCenter"];
    for (NSString *action in @[@"threeECycle:", @"threeECycleBack:"]) {
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(center, NSSelectorFromString(@"unregisterHotKeysWithTarget:action:"), delegate, NSSelectorFromString(action));
    }
}
static id RegisterKey(id center, SEL selector, unsigned short code, NSUInteger flags, id target, SEL action, id object) {
    // Navigation is exclusively controlled by Touch Bar gestures.
    return nil;
}
static id BlockHotKey(id self, SEL selector, id key) { return nil; }
static void IgnoreKeyCommands(id self, SEL selector, id sender) {}
static NSString *combinedGestureState=@"permission";
static BOOL appsMenuVisible;
static BOOL downloadsEnabled;
static NSMenuItem *MenuSeparator(void) { return [NSMenuItem separatorItem]; }
static void CleanMenu(NSMenu *menu) {
    NSStatusItem *statusItem=[(id)NSApp.delegate valueForKey:@"theItem"];
    // Touch Tab is shown whenever the installed bundle is the combined edition
    // (Info.plist), never based on environment variables or build flags.
    if(menu==statusItem.menu) {
        DJAddMenu(menu);
        NSMenuItem *toggle=nil;
        for(NSMenuItem *item in menu.itemArray) if([item.identifier isEqual:@"local.musicstrip.touchTabToggle"]) toggle=item;
        if(!toggle) {
            toggle=[[NSMenuItem alloc] initWithTitle:@"Touch Tab" action:NSSelectorFromString(@"toggleTouchTab:") keyEquivalent:@""];
            toggle.target=NSClassFromString(@"ThreeEMidiBridge"); toggle.identifier=@"local.musicstrip.touchTabToggle";
            [menu insertItem:toggle atIndex:0];
        }
        // Place Touch Tab immediately after Phone Bar in the existing menu.
        [menu removeItem:toggle];
        NSInteger position=menu.numberOfItems && [menu.itemArray.firstObject.title containsString:@"(v."] ? 1 : 0;
        for(NSInteger index=position;index<menu.numberOfItems;index++) {
            NSMenuItem *item=menu.itemArray[(NSUInteger)index];
            if([item.identifier isEqual:@"local.musicstrip.phone"]) { position=index+1; break; }
        }
        [menu insertItem:toggle atIndex:position];
        toggle.state=[combinedGestureState isEqual:@"on"] ? NSControlStateValueOn : NSControlStateValueOff;
        toggle.title=StripHasModule(@"touchtab")?@"Touch Tab":@"Touch Tab — Install…";
        toggle.toolTip=[combinedGestureState isEqual:@"permission"] ? @"Accessibility approval is required for the main 3E app" : [combinedGestureState isEqual:@"unavailable"] ? @"Trackpad gesture listener unavailable" : @"Toggle trackpad gestures";
    }
    for(NSMenuItem *item in menu.itemArray.copy) {
        NSString *title=item.title.lowercaseString;
        if([title containsString:@"check for update"]) { [menu removeItem:item]; continue; }
        if([title isEqual:@"control surface mode"]) {
            item.target=NSClassFromString(@"ThreeEMidiBridge");
            item.action=NSSelectorFromString(@"toggleSurfaceMode:");
            item.state=recordController.activeMenuBar ? NSControlStateValueOn : NSControlStateValueOff;
        }
        if([title isEqual:@"touch bar midi"] ||
           (([title hasPrefix:@"hide "] || [title hasPrefix:@"show "]) &&
            ([title containsString:@"3E"] || [title containsString:@"3£"] || [title containsString:@"midi touchbar"] || [title containsString:@"touch bar midi"]))) {
            item.title=@"Touch Bar Midi";
            item.target=NSClassFromString(@"ThreeEMidiBridge");
            item.action=NSSelectorFromString(@"toggleMidi:");
            item.state=[[(id)NSApp.delegate valueForKey:@"touchbarShown"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        if(item.action==NSSelectorFromString(@"setKeyCommands:") || [title containsString:@"key command"] || [title containsString:@"keyboard shortcut"]) { [menu removeItem:item]; continue; }
        if([item.title hasPrefix:@"MIDI Touchbar (v."] || [item.title hasPrefix:@"3£ (v."] || [item.title hasPrefix:@"3E (v."])
            item.title=[NSString stringWithFormat:@"3E (v. %@)",StripInstalledVersion()];
        else if([title hasPrefix:@"hide "] && ([title containsString:@"3£"] || [title containsString:@"3E"] || [title containsString:@"midi touchbar"])) item.title=@"Hide Touch Bar Midi";
        else if([title hasPrefix:@"show "] && ([title containsString:@"3£"] || [title containsString:@"3E"] || [title containsString:@"midi touchbar"])) item.title=@"Show Touch Bar Midi";
        else if([item.title containsString:@"MIDI Touchbar"]) item.title=[item.title stringByReplacingOccurrencesOfString:@"MIDI Touchbar" withString:@"3E"];
        else if([item.title containsString:@"Strip3£"]) item.title=[item.title stringByReplacingOccurrencesOfString:@"Strip3£" withString:@"3E"];
        item.keyEquivalent=@""; item.keyEquivalentModifierMask=0;
        if(item.submenu) CleanMenu(item.submenu);
    }
    if(menu==statusItem.menu) {
        NSMenuItem *version=nil,*trackTab=nil,*phone=nil,*apps=nil,*midi=nil,*surface=nil,*downloads=nil,*automatic=nil;
        NSMenuItem *reset=nil,*restart=nil,*quit=nil;NSMutableArray<NSMenuItem *> *remaining=[NSMutableArray array];
        for(NSMenuItem *item in menu.itemArray.copy) {
            NSString *title=item.title.lowercaseString;
            if(!version && [title containsString:@"(v."])version=item;
            else if([item.identifier isEqual:@"local.musicstrip.touchTabToggle"])trackTab=item;
            else if([item.identifier isEqual:@"local.musicstrip.phone"])phone=item;
            else if([item.identifier isEqual:@"local.musicstrip.appsToggle"])apps=item;
            else if(item.action==NSSelectorFromString(@"toggleMidi:"))midi=item;
            else if(item.action==NSSelectorFromString(@"toggleSurfaceMode:"))surface=item;
            else if([item.identifier isEqual:@"local.musicstrip.downloads"])downloads=item;
            else if([item.identifier isEqual:@"local.musicstrip.automaticUpdates"])automatic=item;
            else if([item.identifier isEqual:@"local.musicstrip.modules"]) continue;
            else if([title containsString:@"check for update"] || item.isSeparatorItem || [item.identifier hasPrefix:@"local.musicstrip.section."]) continue;
            else if([item.identifier isEqual:@"local.musicstrip.restart"])restart=item;
            else if([title isEqual:@"reset touch bar"])reset=item;
            else if([title isEqual:@"quit"])quit=item;
            else [remaining addObject:item];
        }
        if(!phone)phone=ThreeEPhoneBarMenu(NSClassFromString(@"ThreeEMidiBridge"));
        if(!StripHasModule(@"phone")) { phone.title=@"Phone Bar — Install…"; phone.state=NSControlStateValueOff; }
        if(!apps) {
            apps=[[NSMenuItem alloc] initWithTitle:@"Touch Bar App" action:NSSelectorFromString(@"toggleApps:") keyEquivalent:@""];
            apps.identifier=@"local.musicstrip.appsToggle";apps.target=NSClassFromString(@"ThreeEMidiBridge");
        }
        if(!downloads) {
            downloads=[[NSMenuItem alloc] initWithTitle:@"Auto-move Downloads to Desktop" action:NSSelectorFromString(@"toggleDownloads:") keyEquivalent:@""];
            downloads.identifier=@"local.musicstrip.downloads";downloads.target=NSClassFromString(@"ThreeEMidiBridge");
        }
        if(!automatic) {
            automatic=[[NSMenuItem alloc] initWithTitle:@"Automatically Install Updates" action:NSSelectorFromString(@"toggleAutomaticUpdates:") keyEquivalent:@""];
            automatic.identifier=@"local.musicstrip.automaticUpdates";automatic.target=NSClassFromString(@"ThreeEMidiBridge");
        }
        if(!restart) {
            restart=[[NSMenuItem alloc] initWithTitle:@"Restart" action:NSSelectorFromString(@"restartAll:") keyEquivalent:@""];
            restart.identifier=@"local.musicstrip.restart";restart.target=NSClassFromString(@"ThreeEMidiBridge");
            restart.toolTip=@"Restart 3E and check for updates";
        }
        apps.state=appsMenuVisible&&!recordController.activeMenuBar?NSControlStateValueOn:NSControlStateValueOff;
        if(midi)midi.state=[[(id)NSApp.delegate valueForKey:@"touchbarShown"] boolValue] && !recordController.activeMenuBar && !appsMenuVisible ? NSControlStateValueOn:NSControlStateValueOff;
        downloads.title=@"Auto-move Downloads to Desktop";downloads.state=downloadsEnabled?NSControlStateValueOn:NSControlStateValueOff;
        automatic.state=StripAutomaticUpdatesEnabled()?NSControlStateValueOn:NSControlStateValueOff;
        if(surface) { surface.title=@"Control Surface Mode";surface.state=recordController.activeMenuBar&&!appsMenuVisible?NSControlStateValueOn:NSControlStateValueOff; }

        [menu removeAllItems];
        if(version)[menu addItem:version];
        [menu addItem:phone];if(trackTab)[menu addItem:trackTab];
        [menu addItem:MenuSeparator()];
        [menu addItem:apps];if(midi)[menu addItem:midi];if(surface)[menu addItem:surface];
        [menu addItem:MenuSeparator()];
        for(NSMenuItem *item in remaining)[menu addItem:item];
        [menu addItem:MenuSeparator()];
        [menu addItem:downloads];[menu addItem:automatic];
        [menu addItem:MenuSeparator()];
        [menu addItem:StripModuleSettingsMenu()];
        if(reset)[menu addItem:reset];[menu addItem:restart];if(quit)[menu addItem:quit];
    }
}
static void ApplyBranding(void) {
    NSStatusItem *item=[(id)NSApp.delegate valueForKey:@"theItem"];
    item.length=27; ThreeEBrandStatusButton(item.button);
    CleanMenu(item.menu); CleanMenu(NSApp.mainMenu);
}
static NSArray *MenuTitles(NSMenu *menu) {
    NSMutableArray *titles=[NSMutableArray new];
    for(NSMenuItem *item in menu.itemArray) { [titles addObject:item.title]; if(item.submenu) [titles addObjectsFromArray:MenuTitles(item.submenu)]; }
    return titles;
}

@interface ThreeEMidiBridge : NSObject
+ (void)closeMidi:(id)sender;
+ (void)toggleTouchTab:(id)sender;
+ (void)toggleSurfaceMode:(id)sender;
+ (void)toggleMidi:(id)sender;
+ (void)toggleAutomaticUpdates:(id)sender;
+ (void)toggleApps:(id)sender;
+ (void)openPhone:(id)sender;
+ (void)copyPhone:(id)sender;
+ (void)stopPhone:(id)sender;
+ (void)togglePhoneBar:(id)sender;
+ (void)hoverPhoneBar:(id)sender;
+ (void)hidePhoneBarQR:(id)sender;
+ (void)toggleDownloads:(id)sender;
+ (void)restartAll:(id)sender;
@end
static void SuppressTray(id cls, SEL sel, id item) { Report("TRAY_SUPPRESSED\n"); }
static void Open(id self, SEL sel, NSTouchBar *bar, id identifier) {
    InitializePresetCatalog();
    if(recordController.activeMenuBar && [bar.itemIdentifiers containsObject:@"com.uebe.midi-touchbar.8fader-view"]) {
        NSTouchBar *device=[NSTouchBar new];
        NSCustomTouchBarItem *original=(id)[bar itemForIdentifier:@"com.uebe.midi-touchbar.8fader-view"];
        if(!recordController.nativeDeviceView) recordController.nativeDeviceView=[original valueForKey:@"view"];
        [recordController.nativeDeviceView removeFromSuperview];
        NSCustomTouchBarItem *item=[[NSCustomTouchBarItem alloc] initWithIdentifier:@"local.musicstrip.performance.native-device"];
        item.view=recordController.nativeDeviceView;
        device.templateItems=[NSSet setWithObject:item]; device.defaultItemIdentifiers=@[item.identifier];
        device.delegate=recordController;
        device.principalItemIdentifier=item.identifier;
        [recordController presentMenuBar:device]; return; // No vendor X or preset navigation.
    }
    CGFloat host=closeButton.window.contentView.bounds.size.width;
    if(isfinite(host) && host>200 && host<2048) lastMidiHostWidth=host;
    if (!rebuildingPresentation) ResetPianoExpansion();
    normalLayoutBar=bar; normalIdentifier=identifier;
    NSGroupTouchBarItem *existing=(id)[presentation itemForIdentifier:LayoutID];
    if(!pianoExpanded && [existing isKindOfClass:NSGroupTouchBarItem.class] && recordController && !recordController.activeMenuBar) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration=0; context.allowsImplicitAnimation=NO;
            SizePianos(bar);
            existing.groupTouchBar=NormalPresetContent(bar);
            [self setValue:presentation forKey:@"currentRootTouchbar"];
            [self setValue:@YES forKey:@"touchbarShown"];
            UpdateNavigationColor();
        } completionHandler:nil];
        Report("PRESET_CONTENT_REUSED\n"); return;
    }
    // Keep the original configurable bar intact inside a seamless group.
    // The fixed outer row guarantees that saved presets cannot hide the X.
    NSTouchBar *outer = [NSTouchBar new];
    NSCustomTouchBarItem *close = [[NSCustomTouchBarItem alloc] initWithIdentifier:CloseID];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Close MIDI Touchbar"];
    closeButton = [NSButton buttonWithImage:image target:ThreeEMidiBridge.class action:@selector(closeMidi:)];
    [closeButton setAccessibilityLabel:pianoExpanded ? @"Back to normal piano layout" : @"Close MIDI Touchbar"];
    closeButton.bordered = NO;
    closeButton.imagePosition = NSImageOnly;
    [closeButton.widthAnchor constraintEqualToConstant:32].active = YES;
    close.view = closeButton;
    close.visibilityPriority = NSTouchBarItemPriorityHigh;
    if(!pianoExpanded) SizePianos(bar);
    // Alert-style groups let the client choose spacing rather than inserting
    // standard button-sized gutters between neighboring keyboards.
    NSGroupTouchBarItem *layout=[[NSGroupTouchBarItem alloc] initWithIdentifier:LayoutID];
    layout.prefersEqualWidths=NO;
    layout.groupTouchBar=pianoExpanded ? bar : NormalPresetContent(bar);
    navigationButton=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
    [navigationButton.widthAnchor constraintEqualToConstant:44].active=YES;
    recordController=[StripRecordController new];
    NSInteger preset=[[(id)NSApp.delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSUInteger presets=[[(id)NSApp.delegate valueForKey:@"allUserTouchbars"] count];
    // The X keeps its original 32-point slot. Navigation extends that slot,
    // rather than moving the X or adding an extra native inter-item gutter.
    if(!pianoExpanded) close.view=JoinCloseNavigation(closeButton,navigationButton,preset,presets);
    recordController.button.standaloneRecord=YES;
    outer.templateItems = [NSSet setWithArray:@[close, layout, recordController.item]];
    // Surplus width belongs to the spacer, never to pads/transport buttons.
    // Piano-only rows explicitly claim their usable width; keep the same
    // identifiers for every normal preset so the outer controls never move.
    outer.defaultItemIdentifiers = @[CloseID,LayoutID,NSTouchBarItemIdentifierFlexibleSpace,RecordID];
    if (pianoExpanded) {
        recordController.button.joinedEdge=0;
        NSCustomTouchBarItem *options=[[NSCustomTouchBarItem alloc] initWithIdentifier:OctavesID];
        closeButton.contentTintColor=NSColor.whiteColor;
        closeButton.image.template=YES;
        closeButton.frame=NSMakeRect(0,0,32,30);
        closeButton.translatesAutoresizingMaskIntoConstraints=NO;
        octavesButton=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,36,30)];
        octavesButton.octaveControl=YES;
        octavesButton.stackedCaption=@""; octavesButton.octaveSpanSymbol=YES; octavesButton.joinedEdge=2;
        octavesButton.optionSegment=2;
        octavesButton.image=nil; octavesButton.imagePosition=NSNoImage;
        octavesButton.title=[[expandedPianoView valueForKey:@"numOctaves"] stringValue];
        octavesButton.font=[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightMedium];
        [octavesButton setAccessibilityLabel:@"Visible piano octaves: swipe right to increase or left to decrease; tapping does nothing"];
        [octavesButton.widthAnchor constraintEqualToConstant:36].active=YES;
        pianoChannelButton=nil;
        pianoModeButton=[[PianoConfigButton alloc] initWithFrame:NSMakeRect(0,0,36,30)];
        pianoModeButton.octaveControl=YES;
        pianoModeButton.joinedEdge=1;
        pianoModeButton.optionSegment=1;
        pianoModeButton.configurationHasClose=YES; pianoModeButton.firstConfigurationSegment=YES;
        pianoModeButton.font=[NSFont systemFontOfSize:8 weight:NSFontWeightMedium];
        pianoModeButton.imagePosition=NSImageAbove;
        [pianoModeButton.widthAnchor constraintEqualToConstant:36].active=YES;
        pianoDegreeButton=[[PianoDegreeButton alloc] initWithFrame:NSMakeRect(0,0,28,30)];
        pianoDegreeButton.image=nil; pianoDegreeButton.imagePosition=NSNoImage;
        pianoDegreeButton.octaveControl=YES; pianoDegreeButton.optionSegment=3;
        pianoDegreeButton.configurationHasClose=YES;
        [pianoDegreeButton.widthAnchor constraintEqualToConstant:28].active=YES;
        octavesButton.configurationHasClose=YES;
        NSView *joined=[[StripJoinedMidiControl alloc] initWithFrame:NSMakeRect(0,0,132,30)];
        pianoConfigurationGroup=joined;
        joined.translatesAutoresizingMaskIntoConstraints=NO;
        [joined setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [joined setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        pianoModeButton.translatesAutoresizingMaskIntoConstraints=NO; octavesButton.translatesAutoresizingMaskIntoConstraints=NO;
        pianoDegreeButton.translatesAutoresizingMaskIntoConstraints=NO;
        [joined addSubview:closeButton]; [joined addSubview:pianoModeButton]; [joined addSubview:octavesButton]; [joined addSubview:pianoDegreeButton];
        [NSLayoutConstraint activateConstraints:@[
            [joined.widthAnchor constraintEqualToConstant:132], [joined.heightAnchor constraintEqualToConstant:30],
            [closeButton.leadingAnchor constraintEqualToAnchor:joined.leadingAnchor],
            [closeButton.topAnchor constraintEqualToAnchor:joined.topAnchor],
            [closeButton.widthAnchor constraintEqualToConstant:32], [closeButton.heightAnchor constraintEqualToConstant:30],
            [pianoModeButton.leadingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
            [pianoModeButton.topAnchor constraintEqualToAnchor:joined.topAnchor], [pianoModeButton.heightAnchor constraintEqualToConstant:30],
            [octavesButton.leadingAnchor constraintEqualToAnchor:pianoModeButton.trailingAnchor],
            [octavesButton.topAnchor constraintEqualToAnchor:joined.topAnchor], [octavesButton.heightAnchor constraintEqualToConstant:30],
            [pianoDegreeButton.leadingAnchor constraintEqualToAnchor:octavesButton.trailingAnchor],
            [pianoDegreeButton.topAnchor constraintEqualToAnchor:joined.topAnchor], [pianoDegreeButton.heightAnchor constraintEqualToConstant:30],
            [pianoDegreeButton.trailingAnchor constraintEqualToAnchor:joined.trailingAnchor]
        ]];
        UpdateNavigationColor();
        options.view=joined; options.visibilityPriority=NSTouchBarItemPriorityHigh;
        UpdatePianoConfigControls();
        outer.templateItems=[NSSet setWithArray:@[expandedPianoItem,options]];
        outer.defaultItemIdentifiers=@[OctavesID,expandedPianoItem.identifier];
        outer.principalItemIdentifier=expandedPianoItem.identifier;
        navigationButton=nil;
    }
    presentationSerial++;
    presentation = outer;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration=0; context.allowsImplicitAnimation=NO;
        ((void (*)(id, SEL, id, id))originalOpen)(self, sel, outer, identifier);
        CGFloat host=closeButton.window.contentView.bounds.size.width;
        if(isfinite(host) && host>200 && host<2048) lastMidiHostWidth=host;
        UpdateActivePianoSizing();
    } completionHandler:nil];
    RemoveCycleKey(self);
    Report("VISIBLE\n");
}
static NSCustomTouchBarItem *PianoItemForView(NSView *view) {
    if (!normalLayoutBar) return nil;
    for (NSString *identifier in normalLayoutBar.itemIdentifiers) {
        NSTouchBarItem *item=[normalLayoutBar itemForIdentifier:identifier];
        if ([item isKindOfClass:NSCustomTouchBarItem.class]) {
            NSCustomTouchBarItem *custom=(NSCustomTouchBarItem *)item;
            if (custom.view==view || (!view && [custom.view isKindOfClass:NSClassFromString(@"pianoView")])) return custom;
        }
    }
    return nil;
}
static void ResetPianoExpansion(void) {
    for(NSView *view in pianoHolds.keyEnumerator.allObjects) CancelPianoHold(view);
    if (expandedPianoView) {
        NSInteger startNote=PianoStartNote(expandedPianoView);
        pianoFullWidthConstraint.active=NO; pianoFullWidthConstraint=nil;
        SaveExpandedPianoSettings();
        [expandedPianoView removeFromSuperview];
        if(expandedPianoView!=normalPianoView) {
            normalPianoView=expandedPianoView;
            pianoWidthConstraints=nil; // Old constraints belong to the replaced view.
        }
        expandedPianoItem.view=normalPianoView;
        [NSLayoutConstraint activateConstraints:pianoWidthConstraints ?: @[]];
        [normalPianoView setContentHuggingPriority:pianoHugging forOrientation:NSLayoutConstraintOrientationHorizontal];
        [normalPianoView setContentCompressionResistancePriority:pianoResistance forOrientation:NSLayoutConstraintOrientationHorizontal];
        normalPianoView.frame=pianoNormalFrame;
        SetPianoStartNote(normalPianoView,startNote);
        [normalPianoView setValue:@(-1) forKey:@"lastWidth"];
        normalPianoView.needsDisplay=YES;
    }
    normalPianoView=nil; expandedPianoContainer=nil;
    pianoConfigurationGroup=nil;
    [octavesButton cancelGesture]; octavesButton=nil;
    [pianoModeButton cancelGesture]; [pianoChannelButton cancelGesture]; pianoModeButton=nil; pianoChannelButton=nil;
    [pianoDegreeButton cancelGesture]; pianoDegreeButton=nil;
    pianoExpanded=NO; expandedPianoItem=nil; expandedPianoView=nil; pianoWidthConstraints=nil;
}
static void ReopenPresentation(void) {
    id delegate=NSApp.delegate;
    NSTouchBar *bar=normalLayoutBar; id identifier=normalIdentifier;
    RemoveCycleKey(delegate);
    ((void (*)(id,SEL,id))originalClose)(delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
    if(pianoExpanded && !pianoFullWidthConstraint) {
        pianoFullWidthConstraint=[expandedPianoContainer.widthAnchor constraintEqualToConstant:pianoFullWidth];
        pianoFullWidthConstraint.active=YES;
    }
    rebuildingPresentation=YES;
    Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,identifier);
    [delegate setValue:bar forKey:@"currentRootTouchbar"];
    rebuildingPresentation=NO;
}
static void MountExpandedPiano(NSView *piano) {
    [expandedPianoContainer addSubview:piano]; piano.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[
        [piano.leadingAnchor constraintEqualToAnchor:expandedPianoContainer.leadingAnchor],
        [piano.trailingAnchor constraintEqualToAnchor:expandedPianoContainer.trailingAnchor],
        [piano.topAnchor constraintEqualToAnchor:expandedPianoContainer.topAnchor],
        [piano.bottomAnchor constraintEqualToAnchor:expandedPianoContainer.bottomAnchor]]];
}
static void ExpandPiano(NSView *piano) {
    id delegate=NSApp.delegate;
    if (pianoExpanded || ![[delegate valueForKey:@"touchbarShown"] boolValue] ||
        [[delegate valueForKey:@"editTouchBar"] boolValue] || [[delegate valueForKey:@"editCCs"] boolValue] ||
        [[piano valueForKey:@"activeKeys"] count]) return;
    NSCustomTouchBarItem *item=PianoItemForView(piano);
    if (!item) return;
    // Touch Bar content width reflects the real available region, including
    // the system's collapsed Control Strip. Reserve the close, Record and
    // octave-count controls plus item margins so AppKit won't hide the piano.
    CGFloat available=piano.window.contentView.bounds.size.width;
    if (available<=0) available=closeButton.window.contentView.bounds.size.width;
    if (available<=64) return;
    normalPianoView=piano; expandedPianoView=piano; expandedPianoItem=item; pianoNormalFrame=piano.frame;
    pianoNormalOctaves=[[piano valueForKey:@"numOctaves"] integerValue];
    pianoFullWidth=available-32-132-24;
    pianoHugging=[piano contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal];
    pianoResistance=[piano contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray *widths=[NSMutableArray array];
    for(NSLayoutConstraint *constraint in piano.constraints) {
        if(constraint.active && constraint.firstItem==piano && constraint.firstAttribute==NSLayoutAttributeWidth && !constraint.secondItem) [widths addObject:constraint];
    }
    pianoWidthConstraints=widths;
    SuspendPianoSizing(normalLayoutBar);
    [NSLayoutConstraint deactivateConstraints:widths];
    [piano setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [piano setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    expandedPianoContainer=[[NSView alloc] initWithFrame:NSMakeRect(0,0,pianoFullWidth,30)];
    expandedPianoContainer.translatesAutoresizingMaskIntoConstraints=NO;
    [expandedPianoContainer.heightAnchor constraintEqualToConstant:30].active=YES;
    expandedPianoItem.view=expandedPianoContainer; MountExpandedPiano(piano);
    pianoExpanded=YES;
    ReopenPresentation();
    piano.needsDisplay=YES;
    Report("PIANO_EXPANDED\n");
}
static void ChangeOctaves(NSInteger direction) {
    if(!pianoExpanded || !expandedPianoView || [[expandedPianoView valueForKey:@"activeKeys"] count]) return;
    NSInteger current=[[expandedPianoView valueForKey:@"numOctaves"] integerValue];
    NSInteger start=[[expandedPianoView valueForKey:@"startOctave"] integerValue];
    NSInteger next=MIN(MAX(1,10-start),MAX(1,current+direction));
    SetOctaveCount(next);
}
static void CycleOctaves(void) {
    if(!pianoExpanded || !expandedPianoView || [[expandedPianoView valueForKey:@"activeKeys"] count]) return;
    NSInteger current=[[expandedPianoView valueForKey:@"numOctaves"] integerValue];
    NSInteger start=[[expandedPianoView valueForKey:@"startOctave"] integerValue];
    NSInteger maximum=MAX(1,10-start);
    SetOctaveCount(current>=maximum ? 1 : current+1);
}
static void SetOctaveCount(NSInteger next) {
    if(!pianoExpanded || !expandedPianoView || [[expandedPianoView valueForKey:@"activeKeys"] count]) return;
    NSInteger current=[[expandedPianoView valueForKey:@"numOctaves"] integerValue];
    NSInteger start=[[expandedPianoView valueForKey:@"startOctave"] integerValue];
    next=MIN(MAX(1,10-start),MAX(1,next));
    if(next!=current) {
        // The original engine allocates octave-label arrays during init. Build
        // a matching piano through that initializer instead of mutating its
        // octave count underneath arrays created for a different count.
        NSView *source=expandedPianoView; NSInteger startNote=PianoStartNote(source);
        id allocated=[NSClassFromString(@"pianoView") alloc];
        NSView *replacement=((id(*)(id,SEL,int,int))objc_msgSend)(allocated,NSSelectorFromString(@"initWithOctaves:andTransposition:"),(int)next,(int)start);
        for(NSString *key in @[@"channelNumber",@"type",@"kind",@"oscAddress",@"minValue",@"maxValue",@"pianoDelegate"]) [replacement setValue:[source valueForKey:key] forKey:key];
        SetPianoStartNote(replacement,startNote);
        replacement.identifier=source.identifier;
        TransferPianoInstance(source,replacement);
        replacement.allowedTouchTypes=NSTouchTypeMaskDirect;
        replacement.wantsLayer=YES;
        replacement.translatesAutoresizingMaskIntoConstraints=NO;
        replacement.frame=NSMakeRect(0,0,pianoFullWidth,30);
        [replacement.heightAnchor constraintEqualToConstant:30].active=YES;
        [replacement setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [replacement setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [source removeFromSuperview]; expandedPianoView=replacement;
        MountExpandedPiano(replacement);
        [expandedPianoContainer layoutSubtreeIfNeeded];
        replacement.needsDisplay=YES;
    }
    octavesButton.title=[NSString stringWithFormat:@"%ld",(long)next];
    Report("OCTAVES_CHANGED\n");
}
static void CollapsePiano(void) {
    if(!pianoExpanded || [[expandedPianoView valueForKey:@"activeKeys"] count]) return;
    ResetPianoExpansion(); ReopenPresentation();
    Report("PIANO_RESTORED\n");
}
static void CycleExpandedPianoSetting(BOOL channel,NSInteger direction) {
    if(!pianoExpanded || !expandedPianoView || [[expandedPianoView valueForKey:@"activeKeys"] count]) return;
    NSString *key=channel ? @"channelNumber" : @"type";
    NSInteger value=[[expandedPianoView valueForKey:key] integerValue];
    value=channel ? (value-1+direction+16)%16+1 : (value+direction+3)%3;
    [expandedPianoView setValue:@(value) forKey:key];
    SaveExpandedPianoSettings(); UpdatePianoConfigControls();
}
@interface PianoArrowHold : NSObject
@property (weak) NSView *piano;
@property id identity;
@property NSPoint point;
@property NSInteger octave;
@property NSInteger startNote;
@property NSTimer *timer;
@property BOOL fired;
@property BOOL cancelled;
@property BOOL didSwipe;
@property NSInteger direction;
- (void)fire;
@end
@implementation PianoArrowHold
- (void)fire {
    [self.timer invalidate]; self.timer=nil;
    NSView *piano=self.piano;
    if(self.fired || self.cancelled || self.didSwipe || !piano || [[piano valueForKey:@"activeKeys"] count]) return;
    self.fired=YES;
    if(!pianoExpanded) ExpandPiano(piano);
}
- (void)dealloc { [self.timer invalidate]; }
@end
static void CancelPianoHold(NSView *piano) {
    PianoArrowHold *hold=[pianoHolds objectForKey:piano]; [hold.timer invalidate];
    [pianoHolds removeObjectForKey:piano];
}
static void BeginPianoHold(NSView *piano,id identity,NSPoint point,NSInteger octave) {
    CancelPianoHold(piano);
    PianoArrowHold *hold=[PianoArrowHold new];hold.piano=piano;hold.identity=identity;hold.point=point;hold.octave=octave;hold.startNote=PianoStartNote(piano);
    [pianoHolds setObject:hold forKey:piano];
    __weak PianoArrowHold *weakHold=hold;
    hold.timer=[NSTimer timerWithTimeInterval:0.65 repeats:NO block:^(NSTimer *timer){ [weakHold fire]; }];
    [NSRunLoop.mainRunLoop addTimer:hold.timer forMode:NSRunLoopCommonModes];
}
static void PianoBegan(NSView *piano,SEL selector,NSEvent *event) {
    if([[(id)NSApp.delegate valueForKey:@"editTouchBar"] boolValue]) return;
    CancelPianoHold(piano);
    if([[(id)NSApp.delegate valueForKey:@"editCCs"] boolValue]) {
        ((void(*)(id,SEL,id))objc_msgSend)(NSApp.delegate,NSSelectorFromString(@"pianoTouched:"),piano);
        return; // Selecting a keyboard must not play notes or expand it.
    }
    NSSet<NSTouch *> *touches=[event touchesMatchingPhase:NSTouchPhaseBegan inView:piano];
    NSTouch *touch=touches.count==1 ? touches.anyObject : nil;
    NSPoint point=touch ? [touch locationInView:piano] : NSZeroPoint;
    // Hit-test the exact regions we draw, independent of cached native paths.
    BOOL forward=NSPointInRect(point,PianoEdgeRect(piano,YES));
    BOOL region=forward || NSPointInRect(point,PianoEdgeRect(piano,NO));
    if(touch && touch.type==NSTouchTypeDirect && region && ![[piano valueForKey:@"activeKeys"] count]) {
        NSInteger note=PianoStartNote(piano);
        BeginPianoHold(piano,touch.identity,point,note/12);
        [pianoHolds objectForKey:piano].direction=forward ? 1 : -1;
        Report("PIANO_ARROW_HOLD_ARMED\n");
        return;
    }
    ((void(*)(id,SEL,id))originalPianoBegan)(piano,selector,event);
}
static void PianoMoved(NSView *piano,SEL selector,NSEvent *event) {
    if([[(id)NSApp.delegate valueForKey:@"editCCs"] boolValue]) return;
    PianoArrowHold *hold=[pianoHolds objectForKey:piano];
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:piano]) {
        if(hold && [touch.identity isEqual:hold.identity]) {
            NSPoint point=[touch locationInView:piano];
            CGFloat dx=point.x-hold.point.x,dy=point.y-hold.point.y;
            if(!hold.fired && !hold.cancelled && !hold.didSwipe && fabs(dx)>=8 && fabs(dx)>=fabs(dy)) {
                hold.didSwipe=YES; [hold.timer invalidate]; hold.timer=nil;
                MovePianoHalf(piano,dx>0 ? 1 : -1);
            }
            NSRect edge=PianoEdgeRect(piano,hold.direction>0);
            if(!hold.didSwipe && !NSPointInRect(point,NSInsetRect(edge,-4,-4))) { hold.cancelled=YES; [hold.timer invalidate];hold.timer=nil; }
        }
    }
    if(!hold) ((void(*)(id,SEL,id))originalPianoMoved)(piano,selector,event);
}
static void PianoEnded(NSView *piano,SEL selector,NSEvent *event) {
    if([[(id)NSApp.delegate valueForKey:@"editCCs"] boolValue]) { CancelPianoHold(piano); return; }
    PianoArrowHold *hold=[pianoHolds objectForKey:piano];
    if(hold && !hold.fired && !hold.cancelled && !hold.didSwipe) MovePianoHalf(piano,hold.direction);
    CancelPianoHold(piano);
    ((void(*)(id,SEL,id))originalPianoEnded)(piano,selector,event);
}
static void PianoCancelled(NSView *piano,SEL selector,NSEvent *event) {
    CancelPianoHold(piano);
    ((void(*)(id,SEL,id))originalPianoCancelled)(piano,selector,event);
}
static void ChangeMode(id self,SEL selector,id sender) {
    if(pianoExpanded) { CollapsePiano(); if(pianoExpanded) return; }
    id delegate=NSApp.delegate;
    if([[delegate valueForKey:@"editTouchBar"] boolValue] || [[delegate valueForKey:@"editCCs"] boolValue]) return;
    if(!recordController) {
        NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
        if(!bars.count) return;
        NSInteger index=MAX(0,MIN((NSInteger)bars.count-1,[[delegate valueForKey:@"userTouchbarNumber"] integerValue]));
        [delegate setValue:@NO forKey:@"controlSurfadeMode"];
        Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bars[index],nil);
    }
    [recordController showOptions];
}
static void PresetKey(id self,SEL selector,id sender,id key) {
    if(pianoExpanded) { CollapsePiano(); if(pianoExpanded) return; }
    NSInteger count=[[self valueForKey:@"allUserTouchbars"] count];
    if([key isKindOfClass:NSNumber.class] && count && [key integerValue]>=count) key=@(count-1);
    ((void(*)(id,SEL,id,id))originalPresetHandler)(self,selector,sender,key);
}
static void ShowPreset(id self,SEL selector,NSTouchBar *bar) {
    if([[self valueForKey:@"editTouchBar"] boolValue]) {
        ((void(*)(id,SEL,id))originalShow)(self,selector,bar);
        return;
    }
    // The vendor showTouchbar: empties the live root before copying the next
    // preset identifiers. That bypasses openTouchbar: and exposes an empty,
    // then partially fitted row. Keep its selected preset/model but replace
    // only the stable outer group's content, without clearing the live root.
    Open(self,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,nil);
}
static void Close(id self, SEL sel, id bar) {
    if(recordController.activeMenuBar) [self setValue:@(recordController.returnSurfaceMode) forKey:@"controlSurfadeMode"];
    ((void (*)(id, SEL, id))originalClose)(self, sel, recordController.activeMenuBar ?: presentation ?: bar);
    RemoveCycleKey(self);
    ResetPianoExpansion(); normalLayoutBar=nil; normalIdentifier=nil;
    presentation = nil;
    closeButton = nil;
    [navigationButton cancelGesture]; navigationButton=nil;
    [recordController.button cancelGesture]; recordController=nil;
    Report("HIDDEN\n");
}
static void Cycle(id delegate, SEL selector, id sender) {
    if (![[delegate valueForKey:@"touchbarShown"] boolValue] ||
        [[delegate valueForKey:@"editTouchBar"] boolValue] || [[delegate valueForKey:@"editCCs"] boolValue]) return;
    NSArray *bars = [delegate valueForKey:@"allUserTouchbars"];
    if (!bars.count) return;
    BOOL daw = [[delegate valueForKey:@"controlSurfadeMode"] boolValue];
    NSInteger current = [[delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSInteger count = (NSInteger)bars.count;
    NSInteger direction = selector == NSSelectorFromString(@"threeECycleBack:") ? -1 : 1;
    NSInteger next = daw ? (direction < 0 ? count - 1 : 0) : (current + direction + count) % count;
    [delegate setValue:@NO forKey:@"controlSurfadeMode"];
    // Use the original preset-switch handler so all mappings, settings and
    // per-preset customization continue to resolve through the original engine.
    ((void (*)(id, SEL, id, id))objc_msgSend)(delegate,
        NSSelectorFromString(@"receivedGlobalKeyFrom:key:"), nil, @(next));
    UpdateNavigationColor();
    Report("CYCLED\n");
}
static NSInteger CycleKeyCount(id delegate, NSEventModifierFlags flags) {
    id center = [delegate valueForKey:@"keyCenter"];
    id keys = ((id (*)(id, SEL))objc_msgSend)(center, NSSelectorFromString(@"registeredHotKeys"));
    NSInteger count = 0;
    for (id key in keys) {
        if ([[key valueForKey:@"keyCode"] unsignedShortValue] == 48 &&
            [[key valueForKey:@"modifierFlags"] unsignedLongLongValue] == flags) count++;
    }
    return count;
}
#import "MultiPiano.h"
#import "ControlCustomization.h"
static void DJActivateLayouts(void) {
    DJInstallRekordboxMapping();
    InitializePresetCatalog();
    BOOL install=![NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey];
    DJInstallLayouts(controlPresetCatalog);
    if(install && [NSUserDefaults.standardUserDefaults objectForKey:DJBackupKey] && [[(id)NSApp.delegate valueForKey:@"allUserTouchbars"] count]<2) {
        [(id)NSApp.delegate setValue:[[controlPresetCatalog subarrayWithRange:NSMakeRange(0,2)] mutableCopy] forKey:@"allUserTouchbars"];
        [NSUserDefaults.standardUserDefaults setInteger:2 forKey:PresetCountPreference];
    }
}
static void UpdateActivePianoSizing(void) {
    if(!presentation || pianoExpanded || customizationBar || recordController.activeMenuBar) return;
    // Normal presets retain the same outer host/items. No post-presentation
    // constraint installation or FlexibleSpace insertion/removal.
}
@interface PianoTestTouch : NSObject
@property NSPoint point;
@property id identity;
@end
@implementation PianoTestTouch
- (NSTouchType)type { return NSTouchTypeDirect; }
- (BOOL)isResting { return NO; }
- (NSPoint)locationInView:(NSView *)view { return self.point; }
@end
@interface PianoTestEvent : NSObject
@property PianoTestTouch *touch;
@property NSTouchPhase phase;
@end
@implementation PianoTestEvent
- (NSSet *)touchesMatchingPhase:(NSTouchPhase)phase inView:(NSView *)view { return phase & self.phase ? [NSSet setWithObject:self.touch] : [NSSet set]; }
- (NSWindow *)window { return nil; }
- (NSEventType)type { return NSEventTypeGesture; }
@end
@interface PianoTestOutput : NSObject
@property NSMutableArray *notes;
@property NSMutableArray *bends;
@property NSInteger expectedChannel;
@end
@implementation PianoTestOutput
- (instancetype)init { if((self=[super init])) { self.notes=[NSMutableArray array]; self.bends=[NSMutableArray array]; } return self; }
- (void)sendNoteOn:(int)note withVelocity:(int)velocity channel:(int)channel { NSCAssert(!self.expectedChannel || channel==self.expectedChannel,@"Piano must send its own MIDI channel"); [self.notes addObject:@[@(note),@(velocity)]]; }
- (void)sendPitchBend:(unsigned short)value channel:(int)channel { [self.bends addObject:@(value)]; }
- (void)pianoTouched:(id)sender {}
- (void)sendOSCMessageWithAddressPattern:(id)address andValues:(id)values { NSCAssert(NO,@"Note test must not send OSC"); }
@end
static void TestPianoNotesView(NSView *piano) {
    [piano viewWillDraw];
    id delegate=[piano valueForKey:@"pianoDelegate"]; id kind=[piano valueForKey:@"kind"];
    PianoTestOutput *output=[PianoTestOutput new];
    output.expectedChannel=[[piano valueForKey:@"channelNumber"] integerValue];
    [piano setValue:output forKey:@"pianoDelegate"]; [piano setValue:@1 forKey:@"kind"];
    NSInteger checked=0;
    @try {
        NSArray *keys=[[piano valueForKey:@"pianoKeys"] copy];
        NSBezierPath *up=[piano valueForKey:@"upKey"], *down=[piano valueForKey:@"downKey"];
        for(id key in keys) {
            NSBezierPath *path=[key valueForKey:@"touchPath"]; NSRect rect=NSIntersectionRect(path.bounds,piano.bounds);
            NSPoint point=NSZeroPoint; BOOL found=NO;
            for(CGFloat y=NSMinY(rect)+1;y<NSMaxY(rect) && !found;y+=2) for(CGFloat x=NSMinX(rect)+1;x<NSMaxX(rect);x+=2) {
                NSPoint candidate=NSMakePoint(x,y);
                if([path containsPoint:candidate] && !NSPointInRect(candidate,NSInsetRect(up.bounds,-6,-4)) && !NSPointInRect(candidate,NSInsetRect(down.bounds,-6,-4))) {
                    id selected=nil; for(id possible in keys) if([[possible valueForKey:@"touchPath"] containsPoint:candidate]) selected=possible;
                    if(selected==key) { point=candidate;found=YES;break; }
                }
            }
            if(!found) continue;
            [output.notes removeAllObjects];
            PianoTestTouch *touch=[PianoTestTouch new];touch.point=point;touch.identity=NSUUID.UUID;
            PianoTestEvent *event=[PianoTestEvent new];event.touch=touch;event.phase=NSTouchPhaseBegan;
            PianoBegan(piano,@selector(touchesBeganWithEvent:),(NSEvent *)event);
            event.phase=NSTouchPhaseEnded;PianoEnded(piano,@selector(touchesEndedWithEvent:),(NSEvent *)event);
            NSInteger expected=[[key valueForKey:@"pitch"] integerValue]+[[piano valueForKey:@"startOctave"] integerValue]*12;
            NSCAssert(output.notes.count>=2,@"A playable key must send Note On and Note Off");
            for(NSArray *note in output.notes) NSCAssert([note[0] integerValue]==expected,@"Visible key and emitted MIDI pitch must agree: expected %ld actual %@ at %@",(long)expected,note,NSStringFromPoint(point));
            NSCAssert([output.notes.lastObject[1] integerValue]==0 && ![[piano valueForKey:@"activeKeys"] count],@"Release must stop the note");
            checked++;
        }
        NSCAssert(checked>=[[piano valueForKey:@"numOctaves"] integerValue]*12-2,@"The keyboard window must expose all but at most two clipped edge keys");
        Report("PIANO_NOTES_PASSED\n");
    } @finally { [piano setValue:delegate forKey:@"pianoDelegate"]; [piano setValue:kind forKey:@"kind"]; }
}
static void TestPianoNotes(void) { TestPianoNotesView(expandedPianoView ?: PianoItemForView(nil).view); }
static void TestPianoHalfHeightHits(void) {
    for(NSNumber *width in @[@200,@600]) for(NSNumber *count in @[@1,@3,@10]) for(NSNumber *half in @[@NO,@YES]) {
        if(half.boolValue && count.intValue==10) continue;
        NSView *piano=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),count.intValue,0);
        piano.frame=NSMakeRect(0,0,width.doubleValue,30);
        if(half.boolValue) SetPianoStartNote(piano,6);
        [piano viewWillDraw];
        NSArray *keys=[piano valueForKey:@"pianoKeys"];
        CGFloat blackBottom=30;
        for(id key in keys) if(PianoKeyIsBlack(key)) {
            NSBezierPath *path=[key valueForKey:@"touchPath"];
            if(path.elementCount) blackBottom=MIN(blackBottom,NSMinY(path.bounds));
            NSPoint visible=NSMakePoint(NSMidX(path.bounds),NSMinY(path.bounds)+2);
            if([[key valueForKey:@"drawPath"] containsPoint:visible]) {
                NSCAssert([path containsPoint:visible],@"Black hits include their actual visible lower contour, not just the upper half");
                for(id white in keys) if(!PianoKeyIsBlack(white)) NSCAssert(![[white valueForKey:@"touchPath"] containsPoint:visible],@"Visible black contours must not be cut by the neighboring white key's middle line: width %@ count %@ half %@ black %@ white %@ point %@ blackBounds %@ whiteBounds %@",width,count,half,[key valueForKey:@"pitch"],[white valueForKey:@"pitch"],NSStringFromPoint(visible),NSStringFromRect(path.bounds),NSStringFromRect([[white valueForKey:@"touchPath"] bounds]));
            }
        }
        for(NSNumber *y in @[@1,@(blackBottom/2),@(blackBottom-.1)]) for(CGFloat x=14.371;x<width.doubleValue-14;x+=.73) {
            NSInteger hits=0;
            for(id key in keys) if([[key valueForKey:@"touchPath"] containsPoint:NSMakePoint(x,y.doubleValue)]) {
                hits++; NSCAssert(!PianoKeyIsBlack(key),@"Bottom-half touches must never select black keys");
            }
            NSCAssert(hits==1,@"Native lower-half white-key lane must have no gaps or overlapping hit regions");
        }
        PianoTestOutput *output=[PianoTestOutput new];
        [piano setValue:output forKey:@"pianoDelegate"]; [piano setValue:@1 forKey:@"kind"];
        for(NSInteger mode=0;mode<3;mode++) {
            [piano setValue:@(mode) forKey:@"type"];
            for(id key in keys) if(PianoKeyIsBlack(key)) {
                NSRect hit=[[key valueForKey:@"touchPath"] bounds]; if(NSIsEmptyRect(hit)) continue;
                [output.notes removeAllObjects];
                PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID; touch.point=NSMakePoint(NSMidX(hit),NSMidY(hit));
                PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
                PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
                event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(id)event);
                NSCAssert(output.notes.count==2 && [output.notes.firstObject[0] integerValue]==[[key valueForKey:@"pitch"] integerValue],@"Upper-half black taps still play and release the correct pitch in every mode");
            }
            [output.notes removeAllObjects]; [output.bends removeAllObjects];
            PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID; touch.point=NSMakePoint(14.371,7.5);
            PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
            PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
            for(CGFloat x=15.101;x<width.doubleValue-14;x+=.73) {
                touch.point=NSMakePoint(x,7.5); event.phase=NSTouchPhaseMoved; PianoMoved(piano,@selector(touchesMovedWithEvent:),(id)event);
            }
            event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(id)event);
            for(NSArray *note in output.notes) NSCAssert((![@[@1,@3,@6,@8,@10] containsObject:@([note[0] integerValue]%12)]),@"Native bottom gliss/hold/bend gesture must never emit a black-key note");
            NSCAssert(output.notes.count>=2 && [output.notes.lastObject[1] intValue]==0 && ![[piano valueForKey:@"activeKeys"] count],@"Every mode must release without stuck notes");
            NSCAssert(mode==0 ? output.notes.count>2 : mode==1 ? output.notes.count==2 && output.bends.count==0 : output.bends.count>0,@"Glissando, hold and pitchbend retain their own behavior");
        }
    }
    Report("NATIVE_VISIBLE_KEY_CONTOURS_ALL_MODES_WIDTHS_OCTAVES_AND_HALF_SHIFTS_PASSED\n");
}
static void TestPianoArrowSwipes(void) {
    for(NSNumber *side in @[@NO,@YES]) for(NSNumber *direction in @[@(-1),@1]) {
        NSView *piano=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),3,4);
        piano.frame=NSMakeRect(0,0,600,30); [piano viewWillDraw];
        PianoTestOutput *output=[PianoTestOutput new]; [piano setValue:output forKey:@"pianoDelegate"];
        PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
        touch.point=NSMakePoint(NSMidX(PianoEdgeRect(piano,side.boolValue)),15);
        NSPoint start=touch.point; NSInteger note=PianoStartNote(piano);
        PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
        PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
        event.phase=NSTouchPhaseMoved; touch.point=NSMakePoint(start.x+direction.intValue*10,15);
        PianoMoved(piano,@selector(touchesMovedWithEvent:),(id)event);
        NSCAssert(PianoStartNote(piano)==note+direction.intValue*6,@"Either edge arrow follows swipe direction, not which arrow was touched");
        [[pianoHolds objectForKey:piano] fire];
        touch.point=NSMakePoint(start.x+direction.intValue*20,15); PianoMoved(piano,@selector(touchesMovedWithEvent:),(id)event);
        event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(id)event);
        NSCAssert(PianoStartNote(piano)==note+direction.intValue*6 && output.notes.count==0 && !pianoExpanded,@"A swipe advances once, never expands, plays a note, or repeats on release");
        touch.identity=NSUUID.UUID; touch.point=start; event.phase=NSTouchPhaseBegan;
        PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
        event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(id)event);
        NSCAssert(PianoStartNote(piano)==note+direction.intValue*6+(side.boolValue ? 6 : -6),@"Taps retain the original left/back and right/next behavior");
    }
    Report("BOTH_PIANO_ARROW_SWIPE_DIRECTIONS_AND_ORIGINAL_TAPS_PASSED\n");
}
static void TestArrangementLayout(BOOL viaMenu,BOOL fromHidden) {
    if(fromHidden) Close(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),nil);
    if(viaMenu) {
        ApplyBranding();
        NSMenu *menu=[[(id)NSApp.delegate valueForKey:@"theItem"] menu];
        NSMenuItem *surface=nil;
        for(NSMenuItem *item in menu.itemArray) if([item.title isEqual:@"Control Surface Mode"]) surface=item;
        NSCAssert(surface && surface.action==@selector(toggleSurfaceMode:),@"The real status-menu item must use the Record-hold route");
        NSCAssert([NSApp sendAction:surface.action to:surface.target from:surface],@"Actual menu action must be dispatchable");
    }
    StripRecordController *controller=recordController;
    NSCAssert(controller,@"Menu must initialize MIDI even from hidden");
    if(!viaMenu) {
        Report([[NSString stringWithFormat:@"NORMAL_RECORD %@ host=%g\n",NSStringFromRect([controller.button convertRect:controller.button.bounds toView:nil]),controller.button.window.contentView.bounds.size.width] UTF8String]);
        NSCAssert(!controller.activeMenuBar,@"Start on a normal MIDI preset");
        [controller.button beginAt:NSMakePoint(16,15) identity:NSUUID.UUID]; [controller.button fireHold];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,270*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[controller.button finishAt:NSMakePoint(16,15)];});
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        NSTouchBar *arrangement=controller.activeMenuBar;
        NSCAssert([[(id)NSApp.delegate valueForKey:@"controlSurfadeMode"] boolValue],@"The native surface engine must actually enter Control Surface Mode, not just display its view");
        NSCAssert(arrangement && ![arrangement.itemIdentifiers containsObject:CloseID],@"Record hold opens Arrangement without a close or preset-switch item");
        NSArray *expectedArrangement=@[[RecordID stringByAppendingString:@".performance.loop"],[RecordID stringByAppendingString:@".performance.tempo"],[RecordID stringByAppendingString:@".performance.more"],NSTouchBarItemIdentifierFlexibleSpace,@"local.musicstrip.performance.native-surface",@"local.musicstrip.performance.record"];
        NSCAssert([arrangement.defaultItemIdentifiers isEqualToArray:expectedArrangement],@"Loop, BPM, More and the native surface precede the consistent far-right Record control");
        for(NSString *identifier in arrangement.itemIdentifiers) {
            if([identifier isEqual:NSTouchBarItemIdentifierFlexibleSpace]) continue;
            NSTouchBarItem *item=[arrangement itemForIdentifier:identifier];
            if(![item isKindOfClass:NSPopoverTouchBarItem.class] && ![item respondsToSelector:@selector(view)]) continue;
            NSView *view=[item isKindOfClass:NSPopoverTouchBarItem.class] ? [(NSPopoverTouchBarItem *)item collapsedRepresentation] : [(NSCustomTouchBarItem *)item view];
            NSCAssert(view.window && view.bounds.size.width>0,@"Each combined arrangement control must really be visible: %@ %@",identifier,NSStringFromRect(view.frame));
            Report([[NSString stringWithFormat:@"ARRANGEMENT_VISIBLE %@ %@\n",identifier,NSStringFromRect([view convertRect:view.bounds toView:nil])] UTF8String]);
            if([identifier isEqual:@"local.musicstrip.performance.native-surface"]) {
                NSMutableArray *descendants=[NSMutableArray arrayWithObject:view]; NSView *native=nil;
                while(descendants.count) {
                    NSView *candidate=descendants.lastObject; [descendants removeLastObject]; [descendants addObjectsFromArray:candidate.subviews];
                    if([candidate isKindOfClass:NSClassFromString(@"controlStripView")]) native=candidate;
                }
                view=native;
                NSCAssert([view isKindOfClass:NSClassFromString(@"controlStripView")],@"The actual native surface view must never become an empty placeholder");
                [view viewWillDraw];
                NSCAssert([[view valueForKey:@"ends"] count]>0 && view.subviews.count>0,@"Native surface must build its real fader hit regions and labels");
                NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
                [view drawRect:view.bounds];
                [NSGraphicsContext restoreGraphicsState];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-native-surface.png" atomically:YES];
            }
        }
        StripRecordButton *record=(id)((NSCustomTouchBarItem *)[arrangement itemForIdentifier:@"local.musicstrip.performance.record"]).view;
        NSRect frame=[record convertRect:record.bounds toView:nil];
        for(NSString *action in @[@"loop",@"tempo"]) {
            NSView *button=controller.options[action];
            NSRect full=[button convertRect:button.bounds toView:nil];
            for(NSView *ancestor=button.superview;ancestor;ancestor=ancestor.superview) {
                NSRect clip=[ancestor convertRect:ancestor.bounds toView:nil];
                NSCAssert(NSMinX(full)>=NSMinX(clip)-.1 && NSMaxX(full)<=NSMaxX(clip)+.1,@"The full %@ drawing and gesture area must be unclipped: %@ within %@",action,NSStringFromRect(full),NSStringFromRect(clip));
            }
        }
        NSView *loopView=controller.performanceMenus[@"loop"].collapsedRepresentation;
        NSRect loopFrame=[loopView convertRect:loopView.bounds toView:nil];
        NSCAssert(record.window && fabs(NSWidth(frame)-32)<.1 && fabs(NSMaxX(frame)-record.window.contentView.bounds.size.width)<1 && fabs(NSWidth(loopFrame)-76)<.1,@"Arrangement places the 32-point Record button at the far right: Loop %@ Record %@",NSStringFromRect(loopFrame),NSStringFromRect(frame));
        NSTouchBar *device=[(id)NSApp.delegate valueForKey:@"eightFaderGroup"];
        Open(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),device,nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            NSTouchBar *active=controller.activeMenuBar;
            NSCustomTouchBarItem *deviceItem=(id)[active itemForIdentifier:@"local.musicstrip.performance.native-device"];
            NSCAssert(deviceItem.view==controller.nativeDeviceView && deviceItem.view.window && [active.itemIdentifiers.lastObject isEqual:@"local.musicstrip.performance.record"] && ![active.itemIdentifiers containsObject:CloseID],@"Native device faders retain the real view and a far-right Record slot without the vendor close button");
            StripRecordButton *back=(id)((NSCustomTouchBarItem *)[active itemForIdentifier:@"local.musicstrip.performance.record"]).view;
            NSCAssert(fabs(NSMinX([back convertRect:back.bounds toView:nil])-NSMinX(frame))<1,@"Nested device controls must keep Record in the same right slot: nested %@ root %@ host=%g",NSStringFromRect([back convertRect:back.bounds toView:nil]),NSStringFromRect(frame),back.window.contentView.bounds.size.width);
            [back beginAt:NSMakePoint(16,15) identity:NSUUID.UUID]; [back fireHold];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,270*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[back finishAt:NSMakePoint(16,15)];});
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                NSCAssert(!controller.activeMenuBar && controller.menuStack.count==0 && recordController==controller,@"Holding Record returns directly to the original MIDI bar even from nested device controls");
                NSRect returnedRecord=[controller.button convertRect:controller.button.bounds toView:nil];
                NSCAssert(controller.button.window && fabs(NSMinX(returnedRecord)-NSMinX(frame))<1,@"Returning to MIDI keeps Record aligned with Control Surface Mode");
                Report("COMBINED_NATIVE_SURFACE_ARRANGEMENT_DEVICE_AND_RECORD_HOLD_RETURN_PASSED\n");
                if(viaMenu) {
                    [ThreeEMidiBridge toggleSurfaceMode:nil];
                    NSCAssert(controller.activeMenuBar,@"Menu can re-open the same combined bar");
                    [ThreeEMidiBridge toggleSurfaceMode:nil];
                    NSCAssert(!controller.activeMenuBar,@"Selecting the menu again returns to MIDI");
                    Report(fromHidden ? "SURFACE_MENU_FROM_HIDDEN_PASSED\n" : "SURFACE_MENU_FROM_MIDI_PASSED\n");
                }
            });
        });
    });
}
static void TestNativePianoAddition(void) {
    NSCAssert(!customizationBar,@"Finish customization before this isolated native test");
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=(id<NSTouchBarDelegate>)NSApp.delegate;
    bar.customizationIdentifier=[@"local.musicstrip.native-piano-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    bar.customizationAllowedItemIdentifiers=@[NativePianoID,SecondPianoID,ThirdPianoID,@"ch.uebe.midi-touchbar.pad1"];
    bar.defaultItemIdentifiers=@[NativePianoID,@"ch.uebe.midi-touchbar.pad1"];
    NSString *layoutKey=[@"NSTouchBarConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"]];
    id config=[bar valueForKey:@"configuration"];
    @try {
        for(NSString *added in @[SecondPianoID,ThirdPianoID]) {
            NSArray *before=bar.itemIdentifiers.copy;
            // Model AppKit's actual replacement operation, not an append.
            ((void(*)(id,SEL,id))objc_msgSend)(config,NSSelectorFromString(@"_setCustomizedItemIdentifiers:"),@[added]);
            customizationBar=bar; layoutBeforePianoDrag=before;
            CompleteNativePianoDrag(); customizationBar=nil;
            SizePianos(bar);
            for(NSString *identifier in before) NSCAssert([bar.itemIdentifiers containsObject:identifier],@"A new Piano drop must not delete any existing control");
        }
        NSCAssert(bar.itemIdentifiers.count==4,@"Three actual pianos and the existing pad must remain");
        NSMutableSet *views=[NSMutableSet new];
        for(NSString *identifier in @[NativePianoID,SecondPianoID,ThirdPianoID]) {
            NSCustomTouchBarItem *item=(NSCustomTouchBarItem *)[bar itemForIdentifier:identifier];
            NSCAssert([item.view isKindOfClass:NSClassFromString(@"pianoView")],@"Each retained slot needs a real native keyboard");
            NSCAssert(![views containsObject:item.view],@"Every retained piano has its own view"); [views addObject:item.view];
            NSLayoutConstraint *width=objc_getAssociatedObject(item.view,&pianoCompactWidthKey);
            NSCAssert(width.active && width.priority<NSLayoutPriorityRequired,@"Normal keyboards must stretch, not be fixed to a compact width");
            item.view.frame=NSMakeRect(0,0,160,30); TestPianoNotesView(item.view);
        }
        NSCAssert([[NSUserDefaults.standardUserDefaults dictionaryForKey:layoutKey][@"CurrentItems"] isEqual:bar.itemIdentifiers],@"AppKit must save all three actual piano slots");
        Report("NATIVE_REPLACEMENT_ADD_THREE_PIANOS_PASSED\n");
    } @finally {
        customizationBar=nil; layoutBeforePianoDrag=nil;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:layoutKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:PianoPrefsKey(bar)];
    }
}
static void TestIndependentPianos(void) {
    id delegate=NSApp.delegate;
    NSTouchBar *bar=[[delegate valueForKey:@"allUserTouchbars"] firstObject];
    NSMutableArray *views=[NSMutableArray new];
    for(NSString *identifier in @[NativePianoID,SecondPianoID,ThirdPianoID]) {
        NSCustomTouchBarItem *item=(NSCustomTouchBarItem *)[bar itemForIdentifier:identifier];
        NSCAssert([item.view isKindOfClass:NSClassFromString(@"pianoView")],@"Every piano slot must resolve to the original keyboard view");
        NSCAssert(![views containsObject:item.view],@"Pianos must never share a view or note state");
        [views addObject:item.view];
        item.view.frame=NSMakeRect(0,0,360,30);
        TestPianoNotesView(item.view);
    }
    id channel=[views[1] valueForKey:@"channelNumber"];
    id first=[views[0] valueForKey:@"channelNumber"], third=[views[2] valueForKey:@"channelNumber"];
    [views[1] setValue:@7 forKey:@"channelNumber"];
    NSCAssert([[views[0] valueForKey:@"channelNumber"] isEqual:first] && [[views[2] valueForKey:@"channelNumber"] isEqual:third],@"Editing one piano channel must not change others");
    [views[1] setValue:channel forKey:@"channelNumber"];
    Report("THREE_INDEPENDENT_PIANOS_PASSED\n");
}
static void TestNativeFlexiblePianos(NSInteger count) {
    NSCAssert(!customizationBar && normalLayoutBar && !pianoExpanded,@"Show the normal MIDI bar before the native sizing test");
    id delegate=NSApp.delegate;
    NSTouchBar *saved=normalLayoutBar; id savedIdentifier=normalIdentifier;
    NSArray *savedBars=[[delegate valueForKey:@"allUserTouchbars"] copy];
    NSNumber *savedPreset=[delegate valueForKey:@"userTouchbarNumber"];
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=(id<NSTouchBarDelegate>)delegate;
    bar.defaultItemIdentifiers=[@[NativePianoID,SecondPianoID,ThirdPianoID] subarrayWithRange:NSMakeRange(0,count)];
    bar.customizationIdentifier=[@"local.musicstrip.flex-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    [delegate setValue:[savedBars arrayByAddingObject:bar].mutableCopy forKey:@"allUserTouchbars"];
    Close(delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
    Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,savedIdentifier);
    NSTouchBar *stablePresentation=presentation;
    NSUInteger stableSerial=presentationSerial;
    NSArray *firstItems=presentation.defaultItemIdentifiers.copy;
    NSCAssert([firstItems containsObject:NSTouchBarItemIdentifierFlexibleSpace],@"A permanent spacer protects fixed controls from expansion");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        @try {
            UpdateActivePianoSizing();
            NSCAssert([firstItems isEqual:presentation.defaultItemIdentifiers],@"Refreshing must not rebuild the visible multi-piano row");
            NSArray *geometry=PianoGeometry(bar); CGFloat width=[geometry.firstObject[@"width"] doubleValue];
            NSCAssert(fabs(closeButton.bounds.size.width-32)<=1 && fabs(navigationButton.bounds.size.width-44)<.1 && fabs(recordController.button.bounds.size.width-32)<.1,@"Fixed controls retain widths (allow AppKit's half-point close-button alignment)");
            NSRect closeFrame=[closeButton convertRect:closeButton.bounds toView:nil];
            NSRect navigationFrame=[navigationButton convertRect:navigationButton.bounds toView:nil];
            NSRect recordFrame=[recordController.button convertRect:recordController.button.bounds toView:nil];
            Report([[NSString stringWithFormat:@"FIXED_CONTROL_GEOMETRY close=%@ navigation=%@ record=%@\n",NSStringFromRect(closeFrame),NSStringFromRect(navigationFrame),NSStringFromRect(recordFrame)] UTF8String]);
            NSCAssert(fabs(NSMinX(closeButton.frame))<=1 && fabs(NSMaxX(closeButton.frame)-NSMinX(navigationButton.frame))<1,@"Keep the X in its original slot and join navigation directly beside it (allow native half-point alignment)");
            NSCAssert([presentation.itemIdentifiers.lastObject isEqual:RecordID] && fabs(NSMaxX(recordFrame)-recordController.button.window.contentView.bounds.size.width)<1 && NSMinX(recordFrame)>NSMaxX(navigationFrame),@"Record stays at the far right while X and preset navigation remain joined on the left");
            for(NSDictionary *view in geometry) {
                NSRect position=NSRectFromString(view[@"position"]);
                NSCAssert([view[@"attached"] boolValue] && fabs([view[@"width"] doubleValue]-width)<1 && position.origin.y>=0 && NSMaxX(position)<=[view[@"windowWidth"] doubleValue],@"Actual native Touch Bar must display all three keyboards at equal widths without clipping or hidden containers");
            }
            NSCAssert(width*count>480,@"Native keyboards must expand beyond the old fixed 480-point total");
            CGFloat previousEnd=0;
            for(NSDictionary *entry in geometry) {
                NSRect rect=NSRectFromString(entry[@"position"]);
                if(previousEnd) NSCAssert(fabs(NSMinX(rect)-previousEnd-2)<.1,@"Pianos use only a two-point inter-item gap");
                previousEnd=NSMaxX(rect);
            }
            for(NSInteger switchIndex=0;switchIndex<6;switchIndex++) {
                ((void(*)(id,SEL,id,id))objc_msgSend)(delegate,NSSelectorFromString(@"receivedGlobalKeyFrom:key:"),nil,savedPreset);
                ((void(*)(id,SEL,id,id))objc_msgSend)(delegate,NSSelectorFromString(@"receivedGlobalKeyFrom:key:"),nil,@(savedBars.count));
                NSCAssert(presentation==stablePresentation && presentationSerial==stableSerial && normalLayoutBar==bar,@"Real preset handler must swap content without rebuilding the outer bar");
                NSCAssert(fabs(closeButton.bounds.size.width-32)<=1 && fabs(navigationButton.bounds.size.width-44)<.1 && fabs(recordController.button.bounds.size.width-32)<.1,@"Switching cannot stretch fixed outer controls");
                NSArray *reopened=PianoGeometry(bar);
                for(NSUInteger i=0;i<geometry.count;i++) NSCAssert(fabs([geometry[i][@"width"] doubleValue]-[reopened[i][@"width"] doubleValue])<.1,@"Returning to a multi-piano preset must start at its final width");
                UpdateActivePianoSizing();
                NSArray *refreshed=PianoGeometry(bar);
                for(NSUInteger i=0;i<geometry.count;i++) NSCAssert(fabs([refreshed[i][@"width"] doubleValue]-[reopened[i][@"width"] doubleValue])<.1,@"Sizing refresh must never stretch a visible piano row");
            }
            for(NSString *identifier in bar.itemIdentifiers)
                TestPianoNotesView(((NSCustomTouchBarItem *)[bar itemForIdentifier:identifier]).view);
            NSData *json=[NSJSONSerialization dataWithJSONObject:geometry options:0 error:nil];
            Report([[NSString stringWithFormat:@"NATIVE_FLEX_%ld_PIANOS_PASSED %@\n",(long)count,[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]] UTF8String]);
        } @finally {
            [delegate setValue:savedBars.mutableCopy forKey:@"allUserTouchbars"];
            [delegate setValue:savedPreset forKey:@"userTouchbarNumber"];
            Close(delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
            Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),saved,savedIdentifier);
            NSString *key=[@"NSTouchBarConfig: " stringByAppendingString:[bar.customizationIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"·"]];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
    });
}
static void TestPianoExpansionCase(NSTouchBar *bar,NSTouchBar *saved,id savedIdentifier,NSInteger index) {
    if(index==6) {
        Close(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
        Open(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),saved,savedIdentifier);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:PianoPrefsKey(bar)];
        Report("ALL_THREE_PIANOS_BOTH_SIDE_HOLDS_AND_OCTAVES_PASSED\n"); return;
    }
    NSString *identifier=@[NativePianoID,SecondPianoID,ThirdPianoID][index/2];
    NSCustomTouchBarItem *item=(id)[bar itemForIdentifier:identifier];
    NSView *piano=item.view;
    NSMutableArray *others=[NSMutableArray new];
    for(NSString *slot in bar.itemIdentifiers) if(![slot isEqual:identifier]) {
        NSView *view=((NSCustomTouchBarItem *)[bar itemForIdentifier:slot]).view;
        [others addObject:@[view,[view valueForKey:@"numOctaves"],[view valueForKey:@"channelNumber"]]];
    }
    [piano viewWillDraw];
    NSBezierPath *arrow=[piano valueForKey:index%2 ? @"upKey" : @"downKey"];
    PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
    touch.point=NSMakePoint(NSMidX(arrow.bounds),NSMidY(arrow.bounds));
    PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
    CGFloat compactWidth=piano.bounds.size.width;
    NSInteger start=PianoStartNote(piano),count=[[piano valueForKey:@"numOctaves"] integerValue];
    id channel=[piano valueForKey:@"channelNumber"];
    PianoBegan(piano,@selector(touchesBeganWithEvent:),(NSEvent *)event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        NSCAssert(pianoExpanded && expandedPianoItem==item && expandedPianoView==piano,@"Each side's timed hold must expand the touched piano, not the first one");
        NSRect expandedRect=[piano convertRect:piano.bounds toView:nil];
        Report([[NSString stringWithFormat:@"EXPANDED_GEOMETRY compact=%g expanded=%@ window=%g attached=%d container=%g full=%g\n",compactWidth,NSStringFromRect(expandedRect),piano.window.contentView.bounds.size.width,piano.window!=nil,expandedPianoContainer.bounds.size.width,pianoFullWidth] UTF8String]);
        NSCAssert(piano.window && piano.bounds.size.width>compactWidth*2 && expandedRect.origin.x>=0 && NSMaxX(expandedRect)<=piano.window.contentView.bounds.size.width,@"The selected piano must actually expand visibly without clipping");
        event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(NSEvent *)event);
        NSCAssert(PianoStartNote(piano)==start,@"Hold release must not transpose");
        NSCAssert(![presentation.itemIdentifiers containsObject:RecordID] && [presentation.defaultItemIdentifiers.firstObject isEqual:OctavesID] && ![presentation.itemIdentifiers containsObject:NavigationID],@"Expanded piano starts with the joined Close/configuration control and hides Record and preset navigation");
        for(NSInteger modeStep=0;modeStep<3;modeStep++) {
            NSInteger before=[[expandedPianoView valueForKey:@"type"] integerValue];
            [pianoModeButton beginAt:NSMakePoint(22,15) identity:NSUUID.UUID]; [pianoModeButton finishAt:NSMakePoint(22,15)];
            NSCAssert([[expandedPianoView valueForKey:@"type"] integerValue]==(before+1)%3,@"Actual gesture button must cycle the native modes");
        }
        NSCAssert(!pianoChannelButton && ![presentation.itemIdentifiers containsObject:@"local.musicstrip.piano.channel"],@"MIDI channel belongs in Customize Controls, not the expanded piano");
        NSCAssert(closeButton.superview==pianoModeButton.superview && pianoModeButton.superview==octavesButton.superview && fabs(NSMaxX(closeButton.frame)-NSMinX(pianoModeButton.frame))<.1 && fabs(NSMaxX(pianoModeButton.frame)-NSMinX(octavesButton.frame))<.1,@"Close, gesture mode and octaves must share one gapless preset-colored item");
        NSCAssert([pianoModeButton.stackedCaption isEqual:pianoModeButton.title] && octavesButton.octaveSpanSymbol && octavesButton.stackedCaption.length==0,@"Piano options use a stacked mode label and a text-free octave symbol");
        NSCAssert(pianoDegreeButton.superview==octavesButton.superview && fabs(NSMaxX(octavesButton.frame)-NSMinX(pianoDegreeButton.frame))<.1 && pianoDegreeButton.compactGlyph && fabs(NSWidth(pianoDegreeButton.bounds)-28)<.1 && fabs(NSWidth(pianoModeButton.bounds)-36)<.1 && fabs(NSWidth(octavesButton.bounds)-36)<.1 && fabs(NSWidth(pianoConfigurationGroup.bounds)-132)<.1,@"Three compact controls share a joined item; Labels is narrower");
        NSCAssert(pianoModeButton.iconAboveCaption,@"Gesture icon is drawn above its GLISS/HOLD/BEND caption");
        BOOL beforeDegrees=PianoShowsDegrees(piano);
        [pianoDegreeButton beginAt:NSMakePoint(22,15) identity:NSUUID.UUID]; [pianoDegreeButton finishAt:NSMakePoint(22,15)];
        NSCAssert(PianoShowsDegrees(piano)!=beforeDegrees && [InstanceSettings(bar,identifier)[@"showDegrees"] boolValue]!=beforeDegrees,@"A real button tap persists degree visibility for this piano only");
        for(NSView *control in @[closeButton,pianoModeButton,octavesButton,pianoDegreeButton]) {
            NSRect frame=[control convertRect:control.bounds toView:nil];
            NSCAssert(control.window && frame.origin.x>=0 && NSMaxX(frame)<=control.window.contentView.bounds.size.width,@"All expanded settings controls must be visible");
        }
        NSInteger octaveDirection=count<10-[[expandedPianoView valueForKey:@"startOctave"] integerValue] ? 1 : -1;
        ChangeOctaves(octaveDirection);
        NSCAssert(PianoShowsDegrees(expandedPianoView)!=beforeDegrees,@"Octave replacement retains degree visibility");
        NSCAssert([[expandedPianoView valueForKey:@"numOctaves"] integerValue]==count+octaveDirection && [[expandedPianoView valueForKey:@"channelNumber"] isEqual:channel],@"Expanded octave changes keep this piano's channel");
        NSCAssert(objc_getAssociatedObject(expandedPianoView,&pianoInstanceKey)==objc_getAssociatedObject(piano,&pianoInstanceKey),@"Replacement must retain independent settings identity");
        TestPianoNotesView(expandedPianoView);
        for(NSArray *other in others) NSCAssert([[other[0] valueForKey:@"numOctaves"] isEqual:other[1]] && [[other[0] valueForKey:@"channelNumber"] isEqual:other[2]],@"Do not change other pianos");
        CollapsePiano();
        NSCAssert([[InstanceSettings(bar,identifier) objectForKey:@"octaves"] integerValue]==count+octaveDirection,@"Persist only the touched slot's octave count");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            UpdateActivePianoSizing();
            NSArray *geometry=PianoGeometry(bar); CGFloat width=[geometry.firstObject[@"width"] doubleValue];
            for(NSDictionary *view in geometry) NSCAssert([view[@"attached"] boolValue] && fabs([view[@"width"] doubleValue]-width)<1,@"Collapse must restore three equal visible keyboards");
            Report([[NSString stringWithFormat:@"PIANO_%ld_%@_HOLD_PASSED\n",(long)(index/2+1),index%2 ? @"RIGHT" : @"LEFT"] UTF8String]);
            TestPianoExpansionCase(bar,saved,savedIdentifier,index+1);
        });
    });
}
static void TestAllPianoExpansion(void) {
    NSCAssert(normalLayoutBar && !pianoExpanded,@"Show normal MIDI before testing");
    NSTouchBar *saved=normalLayoutBar; id identifier=normalIdentifier;
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=(id)NSApp.delegate;
    bar.customizationIdentifier=[@"local.musicstrip.expand-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    bar.defaultItemIdentifiers=@[NativePianoID,SecondPianoID,ThirdPianoID];
    // Exercise the narrowest multi-piano layout at the maximum octave count.
    for(NSString *slot in @[SecondPianoID,ThirdPianoID])
        SaveInstanceSettings(bar,slot,@{@"channel":[slot isEqual:SecondPianoID] ? @2 : @3,@"kind":@"note",@"type":@"glissando",@"octaves":@10,@"startOctave":@0});
    Close(NSApp.delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
    Open(NSApp.delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,identifier);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ UpdateActivePianoSizing(); TestPianoExpansionCase(bar,saved,identifier,0); });
}
static void TestNativeScaleDrawing(void) {
    NSUInteger saved=liveScaleMask;
    NSArray *savedDegrees=liveScaleDegrees;
    NSView *piano=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),2,4);
    piano.frame=NSMakeRect(0,0,600,30); [piano viewWillDraw];
    NSArray *masks=@[@(ScaleMaskForState(@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@0,@"scale_intervals":@[@0,@2,@4,@5,@7,@9,@11]},YES)),
        @(ScaleMaskForState(@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@6,@"scale_intervals":@[@0,@2,@3,@5,@7,@8,@10]},YES)),@0];
    @try {
        for(NSUInteger row=0;row<masks.count;row++) {
            NSImage *preview=[[NSImage alloc] initWithSize:NSMakeSize(600,30)]; [preview lockFocus];
            liveScaleMask=[masks[row] unsignedIntegerValue];
            [piano drawRect:piano.bounds]; [preview unlockFocus];
            NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:preview.TIFFRepresentation];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"/tmp/3pounds-native-scale-%lu.png",(unsigned long)row] atomically:YES];
        }
        UpdateLiveScale(@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@6,@"scale_intervals":@[@0,@2,@3,@5,@7,@8,@10]},YES);
        SetPianoShowsDegrees(piano,YES);
        NSImage *degreesPreview=[[NSImage alloc] initWithSize:NSMakeSize(600,30)]; [degreesPreview lockFocus];
        [piano drawRect:piano.bounds]; [degreesPreview unlockFocus];
        NSBitmapImageRep *degreesRep=[NSBitmapImageRep imageRepWithData:degreesPreview.TIFFRepresentation];
        [[degreesRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-piano-degrees.png" atomically:YES];
        SetPianoShowsDegrees(piano,NO);
        TestPianoNotesView(piano);
        id first=nil; NSPoint point=NSZeroPoint;
        for(id key in [piano valueForKey:@"pianoKeys"]) if([[key valueForKey:@"pitch"] integerValue]==0) { first=key; break; }
        NSBezierPath *touchPath=[first valueForKey:@"touchPath"];
        NSBezierPath *up=[piano valueForKey:@"upKey"], *down=[piano valueForKey:@"downKey"];
        BOOL found=NO;
        for(CGFloat y=1;y<NSHeight(piano.bounds) && !found;y+=2) for(CGFloat x=1;x<NSWidth(piano.bounds);x+=2) {
            NSPoint candidate=NSMakePoint(x,y); if(![touchPath containsPoint:candidate]) continue;
            if(NSPointInRect(candidate,NSInsetRect(up.bounds,-6,-4)) || NSPointInRect(candidate,NSInsetRect(down.bounds,-6,-4))) continue;
            id selected=nil; for(id key in [piano valueForKey:@"pianoKeys"]) if([[key valueForKey:@"touchPath"] containsPoint:candidate]) selected=key;
            if(selected==first) { point=candidate; found=YES; break; }
        }
        id delegate=[piano valueForKey:@"pianoDelegate"], kind=[piano valueForKey:@"kind"];
        PianoTestOutput *output=[PianoTestOutput new]; output.expectedChannel=[[piano valueForKey:@"channelNumber"] integerValue];
        PianoTestTouch *touch=[PianoTestTouch new]; touch.point=point; touch.identity=NSUUID.UUID;
        PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch;
        @try {
            NSCAssert(found,@"Scale test needs a playable C key");
            [piano setValue:output forKey:@"pianoDelegate"]; [piano setValue:@1 forKey:@"kind"];
            event.phase=NSTouchPhaseBegan; PianoBegan(piano,@selector(touchesBeganWithEvent:),(NSEvent *)event);
            NSCAssert(ScaleKeyIsPressed(piano,first),@"Scale overlay must recognize and preserve the real native pressed-key feedback");
            liveScaleMask=[masks.firstObject unsignedIntegerValue];
            NSImage *pressedPreview=[[NSImage alloc] initWithSize:NSMakeSize(600,30)]; [pressedPreview lockFocus];
            [piano drawRect:piano.bounds]; [pressedPreview unlockFocus];
            NSBitmapImageRep *pressedRep=[NSBitmapImageRep imageRepWithData:pressedPreview.TIFFRepresentation];
            [[pressedRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3pounds-native-scale-pressed.png" atomically:YES];
            event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(NSEvent *)event);
            NSCAssert(output.notes.count==2 && [output.notes.lastObject[1] integerValue]==0,@"Scale feedback must keep native Note On/Off intact");
        } @finally { CancelPianoHold(piano); [piano setValue:delegate forKey:@"pianoDelegate"]; [piano setValue:kind forKey:@"kind"]; }
        Report("NATIVE_SCALE_DRAWING_AND_UNCHANGED_NOTES_PASSED\n");
    } @finally { liveScaleMask=saved; liveScaleDegrees=savedDegrees; for(NSView *view in scalePianos.allObjects) view.needsDisplay=YES; }
}
static void TestPianoPhysicalHold(BOOL up) {
    NSView *piano=PianoItemForView(nil).view;
    if(!piano) { Report("PIANO_UNAVAILABLE\n");return; }
    [piano viewWillDraw]; // Sample the current arrow geometry after layout.
    NSBezierPath *path=[piano valueForKey:up ? @"upKey" : @"downKey"];
    PianoTestTouch *touch=[PianoTestTouch new];
    touch.identity=NSUUID.UUID; touch.point=NSMakePoint(NSMidX(path.bounds),NSMidY(path.bounds));
    PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
    NSInteger note=PianoStartNote(piano);
    PianoBegan(piano,@selector(touchesBeganWithEvent:),(NSEvent *)event);
    NSCAssert(PianoStartNote(piano)==note,@"Touch-down must not shift before deciding tap versus hold");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ NSCAssert(PianoStartNote(piano)==note,@"Holding must not briefly shift the keyboard"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        event.phase=NSTouchPhaseEnded;
        PianoEnded(piano,@selector(touchesEndedWithEvent:),(NSEvent *)event);
        NSCAssert(PianoStartNote(expandedPianoView ?: piano)==note,@"Releasing a hold must not shift the expanded keyboard");
        Report("PIANO_PHYSICAL_HOLD_FINISHED\n");
    });
}
static void TestPianoEndKeys(void) {
    NSUInteger saved=liveScaleMask; liveScaleMask=0;
    @try {
        for(NSNumber *count in @[@1,@2,@10]) for(NSNumber *width in @[@284,@800]) {
            NSView *piano=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),count.intValue,0);
            piano.frame=NSMakeRect(0,0,width.doubleValue,30); [piano viewWillDraw];
            PianoTestOutput *output=[PianoTestOutput new]; [piano setValue:output forKey:@"pianoDelegate"]; [piano setValue:@1 forKey:@"kind"];
            id last=nil;
            for(id key in [piano valueForKey:@"pianoKeys"]) if([[key valueForKey:@"pitch"] integerValue]==count.integerValue*12-1) last=key;
            NSCAssert(last,@"Last B must exist");
            NSBezierPath *path=[last valueForKey:@"drawPath"];
            PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
            touch.point=NSMakePoint(NSMidX(path.bounds),5);
            PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
            PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
            NSCAssert(ScaleKeyIsPressed(piano,last) && ![pianoHolds objectForKey:piano],@"Last key plays a note, not an arrow action");
            NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width.integerValue pixelsHigh:30 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            [piano drawRect:piano.bounds]; [NSGraphicsContext restoreGraphicsState];
            for(NSInteger y=4;y<27;y++) for(NSInteger x=ceil(NSMinX(path.bounds)+2);x<floor(NSMaxX(path.bounds)-2);x++) {
                if(![path containsPoint:NSMakePoint(x,y)]) continue;
                NSColor *pixel=[[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                NSCAssert(pixel.greenComponent<.2 && pixel.blueComponent<.2,@"Pressed end key must not acquire a white native arrow");
            }
            if(count.intValue==1 && width.intValue==800) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-last-key-pressed.png" atomically:YES];
            event.phase=NSTouchPhaseEnded; PianoEnded(piano,@selector(touchesEndedWithEvent:),(id)event);
            NSCAssert(output.notes.count==2 && [output.notes.lastObject[1] integerValue]==0,@"End key must release normally");
            // A stale native arrow path must not override the visible edge.
            [piano setValue:[NSBezierPath bezierPathWithRect:NSMakeRect(40,0,4,4)] forKey:@"upKey"];
            touch.point=NSMakePoint(NSMidX(PianoEdgeRect(piano,YES)),25); event.phase=NSTouchPhaseBegan;
            PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
            NSCAssert([pianoHolds objectForKey:piano].direction==1 && ![[piano valueForKey:@"activeKeys"] count],@"Visible right edge must arm expansion despite stale native paths");
            CancelPianoHold(piano);
        }
        Report("PIANO_END_KEYS_NO_GHOST_ARROWS_AND_RIGHT_EDGE_PASSED\n");
    } @finally { liveScaleMask=saved; }
}
static void Command(NSString *command) {
    id delegate = NSApp.delegate;
    @try {
        if ([command isEqualToString:@"DJ_SETUP"]) {
            [ThreeEDJActions setup:nil];
        } else if ([command isEqualToString:@"DJ_TARGET_LIVE"]) {
            [ThreeEDJActions targetLive:nil]; Report("DJ_TARGET_LIVE\n");
        } else if ([command isEqualToString:@"DJ_TARGET_REKORDBOX"]) {
            [ThreeEDJActions targetRekordbox:nil]; Report("DJ_TARGET_REKORDBOX\n");
        } else if ([command isEqualToString:@"DJ_TEST"]) {
            NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
            NSCAssert(bars.count>=2,@"Unified DJ preset available");
            NSTouchBar *bar=bars[1];
            NSCAssert([bar.customizationAllowedItemIdentifiers containsObject:DJMixerID] && ![bar.customizationAllowedItemIdentifiers containsObject:DJPadsID],@"Only one DJ tile appears in native palette");
            for(NSTouchBar *preset in bars) NSCAssert(!DJIsRetiredPreset(preset),@"Generated standalone pads no longer appear in preset navigation");
            [delegate setValue:@1 forKey:@"userTouchbarNumber"];ShowPreset(delegate,NSSelectorFromString(@"showTouchbar:"),bar);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                ThreeEDJRow *row=[(NSCustomTouchBarItem *)[bar itemForIdentifier:DJMixerID] view];
                row.page=0;[row layoutSubtreeIfNeeded];[row layout];
                NSCAssert(row.controls[0].animationFrames>=10 && row.controls[14].animationFrames>=10,@"Both platters must receive animation updates faster than metadata polling");
                Report([[NSString stringWithFormat:@"DJ_ANIMATION ticksA=%lu ticksB=%lu directSeek=%d\n",(unsigned long)row.controls[0].animationFrames,(unsigned long)row.controls[14].animationFrames,[ThreeEDJMIDI shared].directSearchAvailable] UTF8String]);
                NSPoint platterA=[row.controls[0] convertPoint:row.controls[0].platterCenter toView:nil],platterB=[row.controls[14] convertPoint:row.controls[14].platterCenter toView:nil];
                NSRect closeFrame=[closeButton convertRect:closeButton.bounds toView:nil],recordFrame=[recordController.button convertRect:recordController.button.bounds toView:nil];
                for(NSInteger page=0;page<2;page++) {
                    row.page=page;[row layout];[row layoutSubtreeIfNeeded];
                    CGFloat center=[row convertPoint:NSMakePoint(NSMidX(row.controls.lastObject.frame),15) toView:nil].x,host=row.window.contentView.bounds.size.width;
                    NSUInteger visible=0;CGFloat minimum=1000;
                    for(ThreeEDJControl *control in row.controls) if(!control.hidden) { visible++;minimum=MIN(minimum,NSWidth(control.frame)); }
                    Report([[NSString stringWithFormat:@"DJ_GEOMETRY view=%ld window=%d width=%g visible=%lu minTarget=%g hub=%g host=%g\n",(long)page,row.window!=nil,NSWidth(row.bounds),(unsigned long)visible,minimum,center,host] UTF8String]);
                    NSCAssert(row.window && row.controls.count==29 && visible==(page ? 19 : 13) && minimum>=24,@"Unified set must fit both real native views");
                    NSCAssert(fabs(center-[row convertPoint:NSMakePoint(NSMidX(row.bounds),15) toView:nil].x)<1,@"The hub sits between equally distributed decks in the available DJ area");
                    NSInteger edge=page ? 6 : 1;
                    NSCAssert(NSMinX(row.controls[edge].frame)==0 && fabs(NSMaxX(row.controls[14+edge].frame)-NSWidth(row.bounds))<.1,@"Levels and transport controls fill the outer edges");
                    if(page) NSCAssert(NSMaxX(row.controls[9].frame)<NSMinX(row.controls[0].frame) && NSMaxX(row.controls[0].frame)<NSMinX(row.controls[10].frame),@"The fixed platter lies between Loop and hot cue 1 in Performance");
                    for(NSInteger local=0;local<14;local++) if(!row.controls[local].hidden) NSCAssert(fabs(NSMidX(row.controls[local].frame)+NSMidX(row.controls[14+local].frame)-NSWidth(row.bounds))<.1,@"Both native deck rows must mirror their corresponding controls");
                    NSCAssert(NSEqualPoints(platterA,[row.controls[0] convertPoint:row.controls[0].platterCenter toView:nil]) && NSEqualPoints(platterB,[row.controls[14] convertPoint:row.controls[14].platterCenter toView:nil]),@"Both wheels remain anchored across views");
                    NSCAssert(NSEqualRects(closeFrame,[closeButton convertRect:closeButton.bounds toView:nil]) && NSEqualRects(recordFrame,[recordController.button convertRect:recordController.button.bounds toView:nil]),@"Close, Change and Record never move");
                }
                row.page=0;[row layout];Report("DJ_NATIVE_LAYOUTS_PASSED\n");
            });
        } else if ([command isEqualToString:@"DJ_STATUS"]) {
            ThreeEDJMIDI *midi=[ThreeEDJMIDI shared];
            Report([[NSString stringWithFormat:@"DJ_STATUS %@\n",@{@"source":@(midi.source),@"destination":@(midi.destination),@"error":@(midi.error),@"liveSource":@(midi.liveSource),@"liveDestination":@(midi.liveDestination),@"target":midi.liveTarget ? @"live" : @"rekordbox",@"metadata":[ThreeEDJTelemetry shared].decks ?: @[],@"metadataPermission":@(AXIsProcessTrusted()),@"directSearch":@(midi.directSearchAvailable),@"highResolutionSearch":@(midi.highResolutionSearchAvailable),@"values":midi.values,@"layouts":[[delegate valueForKey:@"allUserTouchbars"] valueForKey:@"itemIdentifiers"]}] UTF8String]);
        } else if ([command isEqualToString:@"CONTROLS_COLOR_TEST"]) {
            NSTouchBar *bar=normalLayoutBar;
            NSString *key=PianoPrefsKey(bar);
            NSDictionary *prior=[NSUserDefaults.standardUserDefaults dictionaryForKey:key];
            CustomizeControls(delegate,NSSelectorFromString(@"customizeControls:"),nil);
            id vc=[delegate valueForKey:@"settingsViewController"];
            @try {
                for(NSString *slot in @[@"pad1",@"pad2",@"pad3",@"pad4"]) {
                    NSString *identifier=[@"ch.uebe.midi-touchbar." stringByAppendingString:slot];
                    NSView *pad=[(NSCustomTouchBarItem *)[normalLayoutBar itemForIdentifier:identifier] view];
                    ((void(*)(id,SEL))objc_msgSend)(vc,NSSelectorFromString(@"setInitialState"));
                    SelectCustomizationControl(vc,NSSelectorFromString(@"setCurrentControl:"),pad);
                    NSColorWell *well=[vc valueForKey:@"colorWell"];
                    NSCAssert(well.enabled && !well.hidden,@"Pad color must remain editable");
                    NSCAssert(ControlColorsMatch(well.color,StoredControlColor(prior[slot][@"color"])),@"Selection must load this pad's own saved color");
                    NSColor *target=[NSColor colorWithSRGBRed:.2 green:.7 blue:.9 alpha:1];
                    well.color=target;
                    ((void(*)(id,SEL,id))objc_msgSend)(vc,NSSelectorFromString(@"colorChanged:"),well);
                    NSMutableDictionary *written=[[vc valueForKey:@"currentControlPrefs"] mutableCopy];
                    WriteCustomizationControl(vc,NSSelectorFromString(@"WritingToPreferences:"),written);
                    NSCAssert(ControlColorsMatch(target,StoredControlColor(written[@"color"])),@"Writer must use the actual picker, not a stale cached color");
                    ((void(*)(id,SEL,id))objc_msgSend)(vc,NSSelectorFromString(@"applySettings:"),nil);
                    NSButton *live=[(NSCustomTouchBarItem *)[normalLayoutBar itemForIdentifier:identifier] view];
                    NSCAssert(ControlColorsMatch(target,live.bezelColor) && ControlColorsMatch(target,[live.cell valueForKey:@"bezelColor"]),@"Apply must update both the actual live button and its cell");
                    NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:key];
                    for(NSString *mapping in @[@"channel",@"kind",@"value",@"type",@"scaleFrom",@"scaleTo"])
                        NSCAssert([saved[slot][mapping] isEqual:prior[slot][mapping]],@"Color edits must preserve the MIDI mapping");
                }
                Report("CC1_TO_CC4_PICKER_SAVE_AND_LIVE_COLOR_PASSED\n");
            } @finally {
                [NSUserDefaults.standardUserDefaults setObject:prior forKey:key];
                ReloadCustomizationControls(delegate,NSSelectorFromString(@"reloadTouchbar"));
                ((void(*)(id,SEL))objc_msgSend)(vc,NSSelectorFromString(@"setInitialState"));
            }
        } else if ([command isEqualToString:@"CONTROL_COLOR_STATUS"]) {
            NSArray *bars=[delegate valueForKey:@"allUserTouchbars"];
            for(NSTouchBar *bar in bars) {
                NSDictionary *prefs=[NSUserDefaults.standardUserDefaults dictionaryForKey:PianoPrefsKey(bar)];
                for(NSString *identifier in bar.itemIdentifiers) {
                    NSString *slot=[identifier componentsSeparatedByString:@"."].lastObject;
                    NSDictionary *settings=prefs[slot];
                    if(!settings[@"color"]) continue;
                    id item=[bar itemForIdentifier:identifier];
                    NSColor *saved=StoredControlColor(settings[@"color"]);
                    NSView *view=[item respondsToSelector:@selector(view)] ? [item view] : nil;
                    NSColor *shown=[view respondsToSelector:@selector(bezelColor)] ? [(NSButton *)view bezelColor] : nil;
                    Report([[NSString stringWithFormat:@"CONTROL_COLOR %@ %@ channel %@ cc %@ class %@ saved %@ shown %@\n",bar.customizationIdentifier,slot,settings[@"channel"],settings[@"value"],NSStringFromClass(view.class),saved,shown] UTF8String]);
                    if(view.window && view.bounds.size.width>0) {
                        NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
                        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
                        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@"/tmp/3e-color-" stringByAppendingFormat:@"%@.png",slot] atomically:YES];
                    }
                }
            }
        } else if ([command isEqualToString:@"CONTROLS_APPLY_TEST"]) {
            NSCAssert([[delegate valueForKey:@"editCCs"] boolValue],@"Open the control editor first");
            id vc=[delegate valueForKey:@"settingsViewController"];
            NSString *prefsKey=PianoPrefsKey(normalLayoutBar);
            NSDictionary *prior=[NSUserDefaults.standardUserDefaults dictionaryForKey:prefsKey];
            @try {
                NSView *piano=[(NSCustomTouchBarItem *)[normalLayoutBar itemForIdentifier:SecondPianoID] view];
                ConfigureIndependentPiano(delegate,NSSelectorFromString(@"pianoTouched:"),piano);
                [[vc valueForKey:@"channelButton"] selectItemAtIndex:6];
                ((void(*)(id,SEL,id))objc_msgSend)(vc,NSSelectorFromString(@"applySettings:"),nil);
                NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:prefsKey];
                NSCAssert([saved[@"piano2"][@"channel"] intValue]==7,@"Apply must persist the second piano's channel");
                NSCAssert([saved[@"piano"] isEqual:prior[@"piano"]],@"Applying the second piano must not modify the first piano");
                NSView *live=[(NSCustomTouchBarItem *)[normalLayoutBar itemForIdentifier:SecondPianoID] view];
                NSCAssert([[live valueForKey:@"channelNumber"] intValue]==7,@"Apply must update the actual live piano, not only saved preferences");
                Report("CONTROLS_REAL_APPLY_AND_LIVE_RELOAD_PASSED\n");
            } @finally {
                [NSUserDefaults.standardUserDefaults setObject:prior forKey:prefsKey];
                ReloadCustomizationControls(delegate,NSSelectorFromString(@"reloadTouchbar"));
                ((void(*)(id,SEL))objc_msgSend)(vc,NSSelectorFromString(@"setInitialState"));
                ConfigureIndependentPiano(delegate,NSSelectorFromString(@"pianoTouched:"),[(NSCustomTouchBarItem *)[normalLayoutBar itemForIdentifier:NativePianoID] view]);
            }
        } else if ([command isEqualToString:@"CONTROLS_TEST"]) {
            NSTouchBar *saved=normalLayoutBar;
            NSCAssert(saved && ![[delegate valueForKey:@"editCCs"] boolValue],@"Show a MIDI preset before this test");
            CustomizeControls(delegate,NSSelectorFromString(@"customizeControls:"),nil);
            id vc=[delegate valueForKey:@"settingsViewController"];
            NSCAssert(normalLayoutBar==saved,@"Editor must retain the live preset instead of the empty main shell");
            NSInteger index=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
            NSString *expectedTitle=[NSString stringWithFormat:@"Touchbar %ld",(long)index+1];
            NSCAssert([[(NSTextField *)[vc valueForKey:@"touchBarName"] stringValue] isEqual:expectedTitle],@"Title must match current preset");
            for(NSString *identifier in @[NativePianoID,SecondPianoID,ThirdPianoID]) {
                NSView *piano=[(NSCustomTouchBarItem *)[saved itemForIdentifier:identifier] view];
                NSCAssert([piano isKindOfClass:NSClassFromString(@"pianoView")],@"Each slot needs a real independent piano");
                PianoTestEvent *event=[PianoTestEvent new]; event.touch=[PianoTestTouch new]; event.touch.point=NSMakePoint(1,15); event.phase=NSTouchPhaseBegan;
                PianoBegan(piano,@selector(touchesBeganWithEvent:),(id)event);
                NSCAssert(objc_getAssociatedObject(vc,&selectedControlKey)==piano,@"Actual touch-began route must select this specific piano");
                NSCAssert(![pianoHolds objectForKey:piano] && ![[piano valueForKey:@"activeKeys"] count],@"Selection must not start notes or arrow holds");
                NSCAssert([[vc valueForKey:@"channelButton"] isEnabled],@"Piano channel must remain editable");
                for(NSString *key in @[@"numOctavesButton",@"startOctaveButton",@"behaviorButton"]) NSCAssert([[vc valueForKey:key] isHidden],@"Expanded-only controls must be hidden");
                NSLog(@"CC_SELECTED %@ namespace %@ prefs %@ channel %@",identifier,[vc valueForKey:@"controlIdentifier"],[vc valueForKey:@"prefsKey"],[[vc valueForKey:@"channelButton"] titleOfSelectedItem]);
                NSMutableDictionary *copy=[[vc valueForKey:@"currentControlPrefs"] mutableCopy];
                id previousChannel=[vc valueForKey:@"presetChannel"];
                [vc setValue:@7 forKey:@"presetChannel"];
                WriteCustomizationControl(vc,NSSelectorFromString(@"WritingToPreferences:"),copy);
                [vc setValue:previousChannel forKey:@"presetChannel"];
                NSCAssert([copy[@"channel"] intValue]==7,@"Native writer must save channel changes");
                NSCAssert([copy[@"octaves"] isEqual:[piano valueForKey:@"numOctaves"]] && [copy[@"startOctave"] isEqual:[piano valueForKey:@"startOctave"]],@"Channel editing must preserve expanded octave settings");
                NSCAssert([copy[@"type"] isEqual:PianoModeName([[piano valueForKey:@"type"] integerValue])],@"Channel editing must preserve gesture mode");
            }
            NSView *pad=[(NSCustomTouchBarItem *)[saved itemForIdentifier:@"ch.uebe.midi-touchbar.pad1"] view];
            if([pad isKindOfClass:NSClassFromString(@"padButton")]) {
                ((void(*)(id,SEL,id))objc_msgSend)(delegate,NSSelectorFromString(@"padAction:"),pad);
                NSCAssert([[vc valueForKey:@"controlIdentifier"] isEqual:@"pad1"] && [[vc valueForKey:@"valueTextField"] isEnabled],@"Pad touches must select the native CC editor too");
                Report("CONTROLS_PAD_SELECTION_PASSED\n");
            }
            StripPresetCountEditor *editor=objc_getAssociatedObject(vc,&countEditorKey);
            id prior=[NSUserDefaults.standardUserDefaults objectForKey:PresetCountPreference];
            NSUInteger total=[[delegate valueForKey:@"allUserTouchbars"] count];
            @try {
                editor.stepper.integerValue=2; [editor changeCount:nil];
                NSCAssert([[delegate valueForKey:@"allUserTouchbars"] count]==2,@"Count applies immediately");
                editor.stepper.integerValue=total; [editor changeCount:nil];
                NSCAssert([[delegate valueForKey:@"allUserTouchbars"] count]==total && normalLayoutBar==saved,@"Hidden presets restore without changing layout");
            } @finally {
                editor.stepper.integerValue=total; [editor changeCount:nil];
                if(prior) [NSUserDefaults.standardUserDefaults setObject:prior forKey:PresetCountPreference]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:PresetCountPreference];
            }
            Report("CONTROLS_TOUCH_SELECTION_AND_COUNT_PASSED\n");
        } else if ([command hasPrefix:@"APPS_STATE "]) {
            appsMenuVisible=[[command substringFromIndex:11] boolValue]; ApplyBranding();
        } else if ([command hasPrefix:@"DOWNLOADS_STATE "]) {
            downloadsEnabled=[[command substringFromIndex:16] boolValue]; ApplyBranding();
        } else if ([command hasPrefix:@"TOUCHTAB_STATE "]) {
            combinedGestureState=[command substringFromIndex:15];
            ApplyBranding();
        } else if ([command isEqualToString:@"PIANO_INSTANCES_TEST"]) {
            TestIndependentPianos();
        } else if ([command isEqualToString:@"PIANO_NATIVE_ADD_TEST"]) {
            TestNativePianoAddition();
        } else if ([command isEqualToString:@"PIANO_END_KEYS_TEST"]) {
            TestPianoEndKeys();
        } else if ([command isEqualToString:@"PIANO_DENSE_ARROW_TEST"]) {
            for(NSNumber *count in @[@2,@6,@10]) for(NSNumber *width in @[@160,@284,@540,@800]) {
                NSView *view=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),count.intValue,0);
                view.frame=NSMakeRect(0,0,width.doubleValue,30); [view viewWillDraw];
                NSRect left=[[view valueForKey:@"downKey"] bounds],right=[[view valueForKey:@"upKey"] bounds];
                if(count.intValue==10 && width.intValue==284) {
                    NSImage *preview=[[NSImage alloc] initWithSize:view.bounds.size]; [preview lockFocus]; [view drawRect:view.bounds]; [preview unlockFocus];
                    NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:preview.TIFFRepresentation];
                    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3pounds-dense-piano.png" atomically:YES];
                }
                NSCAssert(fabs(left.size.width-14)<.1 && fabs(right.size.width-14)<.1 && fabs(NSMaxX(right)-width.doubleValue)<.1,@"Compact piano arrows must stay fixed and visible");
                for(NSNumber *side in @[@NO,@YES]) {
                    PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
                    NSRect edge=side.boolValue ? right : left;
                    touch.point=NSMakePoint(NSMidX(edge),15);
                    PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
                    PianoBegan(view,@selector(touchesBeganWithEvent:),(id)event);
                    NSCAssert([pianoHolds objectForKey:view]!=nil && ![[view valueForKey:@"activeKeys"] count],@"Either dense edge must arm a hold without playing a note");
                    touch.point=NSMakePoint(touch.point.x+(side.boolValue ? 8 : -8),touch.point.y); event.phase=NSTouchPhaseMoved; PianoMoved(view,@selector(touchesMovedWithEvent:),(id)event);
                    NSCAssert(![pianoHolds objectForKey:view].cancelled,@"Natural finger drift within the edge must not lose the hold");
                    CancelPianoHold(view);
                }
                Report([[NSString stringWithFormat:@"DENSE_ARROW octaves=%@ width=%@ left=%@ right=%@\n",count,width,NSStringFromRect([[view valueForKey:@"downKey"] bounds]),NSStringFromRect([[view valueForKey:@"upKey"] bounds])] UTF8String]);
            }
        } else if ([command isEqualToString:@"PIANO_TYPE_MAP_TEST"]) {
            for(NSString *name in @[@"glissando",@"noglissando",@"pitchbend"]) {
                NSView *view=((id(*)(id,SEL,int,int))objc_msgSend)([NSClassFromString(@"pianoView") alloc],NSSelectorFromString(@"initWithOctaves:andTransposition:"),2,4);
                view.frame=NSMakeRect(0,0,600,30); [view viewWillDraw];
                NSInteger mode=[@[@"glissando",@"noglissando",@"pitchbend"] indexOfObject:name];
                [view setValue:@(mode) forKey:@"type"]; [view setValue:@1 forKey:@"kind"];
                PianoTestOutput *output=[PianoTestOutput new]; [view setValue:output forKey:@"pianoDelegate"];
                PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID; touch.point=NSMakePoint(100,5);
                PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
                PianoBegan(view,@selector(touchesBeganWithEvent:),(id)event);
                event.phase=NSTouchPhaseMoved; touch.point=NSMakePoint(180,5); PianoMoved(view,@selector(touchesMovedWithEvent:),(id)event);
                NSInteger movedNotes=output.notes.count,movedBends=output.bends.count;
                event.phase=NSTouchPhaseEnded; PianoEnded(view,@selector(touchesEndedWithEvent:),(id)event);
                NSCAssert(mode==0 ? movedNotes>1 : mode==1 ? movedNotes==1 && movedBends==0 : movedBends>0,@"Native gesture modes must really glide, hold, or pitchbend");
                Report([[NSString stringWithFormat:@"NATIVE_PIANO_TYPE %@=%ld notes=%ld bends=%ld PASSED\n",name,(long)mode,(long)movedNotes,(long)movedBends] UTF8String]);
            }
        } else if ([command isEqualToString:@"SURFACE_SCHEMA_TEST"]) {
            for(NSString *key in @[@"controlStripGroup",@"eightFaderGroup",@"controlStripItem",@"eightFaderItem"]) {
                id value=[delegate valueForKey:key];
                NSString *description=[value isKindOfClass:NSTouchBar.class] ? [[value itemIdentifiers] description] : [value respondsToSelector:@selector(identifier)] ? [value identifier] : NSStringFromClass([value class]);
                Report([[NSString stringWithFormat:@"SURFACE %@ %@ %@\n",key,NSStringFromClass([value class]),description] UTF8String]);
                if([value isKindOfClass:NSTouchBar.class]) for(NSString *identifier in [value itemIdentifiers]) {
                    NSTouchBarItem *item=[value itemForIdentifier:identifier];
                    Report([[NSString stringWithFormat:@"SURFACE_ITEM %@ %@\n",identifier,NSStringFromClass(item.class)] UTF8String]);
                }
                if([value respondsToSelector:@selector(view)]) {
                    NSMutableArray *views=[NSMutableArray arrayWithObject:[value valueForKey:@"view"]];
                    unsigned int count=0; Ivar *ivars=class_copyIvarList([[value valueForKey:@"view"] class],&count);
                    for(unsigned int i=0;i<count;i++) Report([[NSString stringWithFormat:@"SURFACE_FIELD %s %s\n",ivar_getName(ivars[i]),ivar_getTypeEncoding(ivars[i])] UTF8String]);
                    free(ivars);
                    while(views.count) {
                        NSView *view=views.lastObject; [views removeLastObject]; [views addObjectsFromArray:view.subviews];
                        Report([[NSString stringWithFormat:@"SURFACE_VIEW %@ %@ %@ %@\n",NSStringFromClass(view.class),NSStringFromRect(view.frame),[view isKindOfClass:NSButton.class] ? [(NSButton *)view title] : @"",[view isKindOfClass:NSControl.class] ? NSStringFromSelector([(NSControl *)view action]) : @""] UTF8String]);
                    }
                }
            }
        } else if ([command isEqualToString:@"ARRANGEMENT_LAYOUT_TEST"]) {
            TestArrangementLayout(NO,NO);
        } else if ([command isEqualToString:@"SURFACE_MENU_TEST"]) {
            TestArrangementLayout(YES,NO);
        } else if ([command isEqualToString:@"SURFACE_MENU_HIDDEN_TEST"]) {
            TestArrangementLayout(YES,YES);
        } else if ([command isEqualToString:@"PIANO_ARROW_SWIPE_TEST"]) {
            TestPianoArrowSwipes();
        } else if ([command isEqualToString:@"PIANO_HALF_HEIGHT_HITS_TEST"]) {
            TestPianoHalfHeightHits();
        } else if ([command isEqualToString:@"PIANO_ALL_SIDE_HOLDS_TEST"]) {
            TestAllPianoExpansion();
        } else if ([command isEqualToString:@"UPDATE_SOURCE_TEST"]) {
            Class cls=[NSApp.delegate class];
            NSCAssert(method_getImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"startUpdateCheckBackground")))==(IMP)StripUpdateBackground,@"Launch update hook");
            Report("UPDATE_SOURCE_TOUCHBAR3DY_PASSED\n");
        } else if ([command isEqualToString:@"PIANO_SCALE_TEST"]) {
            TestNativeScaleDrawing();
        } else if ([command isEqualToString:@"RECORD_OPTIONS_TEST"]) {
            [recordController showOptions]; Report("RECORD_OPTIONS_OPENED\n");
        } else if ([command isEqualToString:@"RECORD_PANEL_STATUS"]) {
            NSMutableArray *views=[NSMutableArray new];
            for(NSString *action in recordController.options) {
                NSView *view=recordController.options[action];
                if(view.window) [views addObject:@{@"action":action,@"rect":NSStringFromRect([view convertRect:view.bounds toView:nil]),@"windowWidth":@(view.window.contentView.bounds.size.width)}];
            }
            NSData *json=[NSJSONSerialization dataWithJSONObject:views options:0 error:nil];
            Report([[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"] UTF8String]);
        } else if ([command isEqualToString:@"RECORD_LOOP_OPTIONS_TEST"]) {
            [recordController showMenu:@"loop"]; Report("LOOP_OPTIONS_OPENED\n");
        } else if ([command isEqualToString:@"RECORD_MENU_BACK_TEST"]) {
            [recordController backMenu:nil]; Report("RECORD_MENU_BACK\n");
        } else if ([command isEqualToString:@"RECORD_TEMPO_OPTIONS_TEST"]) {
            [recordController showMenu:@"tempo"]; Report("TEMPO_OPTIONS_OPENED\n");
        } else if ([command isEqualToString:@"RECORD_MORE_OPTIONS_TEST"]) {
            [recordController showMenu:@"more"]; Report("MORE_OPTIONS_OPENED\n");
        } else if ([command isEqualToString:@"PIANO_FLEX_NATIVE_TEST"]) {
            TestNativeFlexiblePianos(3);
        } else if ([command isEqualToString:@"PIANO_FLEX_NATIVE_TWO_TEST"]) {
            TestNativeFlexiblePianos(2);
        } else if ([command isEqualToString:@"CUSTOMIZE_TEST"]) {
            ((void(*)(id,SEL,id))objc_msgSend)(delegate,NSSelectorFromString(@"customizeTouchbar:"),nil);
            Report("CUSTOMIZATION_OPENED\n");
        } else if ([command isEqualToString:@"NATIVE_CUSTOMIZATION_STATUS"]) {
            id preview=[nativeCustomizationController valueForKey:@"customizationRowViewController"];
            NSLog(@"NATIVE editable=%d previewEditable=%d rect=%@ items=%@",((BOOL(*)(id,SEL))objc_msgSend)(nativeCustomizationController,NSSelectorFromString(@"activeTouchBarIsCustomizable")),((BOOL(*)(id,SEL))objc_msgSend)(preview,NSSelectorFromString(@"applicationSectionIsCustomizable")),[preview valueForKey:@"applicationRect"],customizationBar.itemIdentifiers);
        } else if ([command isEqualToString:@"SHOW"]) {
            // The native system X can hide a modal without clearing this old
            // app's flag. A new hold always rebuilds and presents its bar.
            if ([[delegate valueForKey:@"touchbarShown"] boolValue]) {
                id previous = [delegate valueForKey:@"currentRootTouchbar"];
                ((void (*)(id, SEL, id))objc_msgSend)(delegate, NSSelectorFromString(@"closeTouchbar:"), previous);
            }
            // Let the original engine choose its current saved preset or DAW
            // mode. mainTouchBar is a presentation shell and becomes empty.
            ((void (*)(id, SEL))objc_msgSend)(delegate, NSSelectorFromString(@"toggleTouchbar"));
        } else if ([command isEqualToString:@"HIDE"]) {
            if ([[delegate valueForKey:@"touchbarShown"] boolValue]) {
                id bar = [delegate valueForKey:@"currentRootTouchbar"];
                ((void (*)(id, SEL, id))objc_msgSend)(delegate, NSSelectorFromString(@"closeTouchbar:"), bar);
            }
        } else if ([command isEqualToString:@"CYCLE"]) {
            Cycle(delegate, NSSelectorFromString(@"threeECycle:"), nil);
        } else if ([command isEqualToString:@"CYCLE_BACK"]) {
            Cycle(delegate, NSSelectorFromString(@"threeECycleBack:"), nil);
        } else if ([command isEqualToString:@"CLOSE_BUTTON"]) {
            [closeButton performClick:nil];
        } else if ([command hasPrefix:@"PIANO_CAPTURE_"]) {
            NSView *piano=expandedPianoView ?: PianoItemForView(nil).view;
            [piano layoutSubtreeIfNeeded]; [piano viewWillDraw];
            NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)NSWidth(piano.bounds)*2 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            NSAffineTransform *scale=[NSAffineTransform transform]; [scale scaleBy:2]; [scale concat];
            [piano drawRect:piano.bounds];
            for(NSTextField *label in [piano valueForKey:@"textFields"]) [label.stringValue drawInRect:label.frame withAttributes:@{NSFontAttributeName:label.font ?: [NSFont systemFontOfSize:10],NSForegroundColorAttributeName:label.textColor ?: NSColor.blackColor}];
            [NSGraphicsContext restoreGraphicsState];
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3e-piano-%@.png",[command substringFromIndex:14].lowercaseString]];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            Report("PIANO_CAPTURED\n");
        } else if ([command isEqualToString:@"PIANO_TEST_NOTES"]) {
            TestPianoNotes();
        } else if ([command isEqualToString:@"PIANO_HALF_UP"] || [command isEqualToString:@"PIANO_HALF_DOWN"]) {
            NSView *piano=expandedPianoView ?: PianoItemForView(nil).view;
            [piano viewWillDraw];
            NSBezierPath *path=[piano valueForKey:[command hasSuffix:@"UP"] ? @"upKey" : @"downKey"];
            PianoTestTouch *touch=[PianoTestTouch new];touch.identity=NSUUID.UUID; touch.point=NSMakePoint(NSMidX(path.bounds),NSMidY(path.bounds));
            PianoTestEvent *event=[PianoTestEvent new];event.touch=touch;event.phase=NSTouchPhaseBegan;
            PianoBegan(piano,@selector(touchesBeganWithEvent:),(NSEvent *)event);
            event.phase=NSTouchPhaseEnded;PianoEnded(piano,@selector(touchesEndedWithEvent:),(NSEvent *)event);
            [piano viewWillDraw];
        } else if ([command isEqualToString:@"PIANO_TOUCH_HOLD_UP"] || [command isEqualToString:@"PIANO_TOUCH_HOLD_DOWN"]) {
            TestPianoPhysicalHold([command hasSuffix:@"UP"]);
        } else if (([command isEqualToString:@"PIANO_HOLD_UP"] || [command isEqualToString:@"PIANO_HOLD_DOWN"])) {
            NSView *piano=PianoItemForView(nil).view;
            if (!piano) { Report("PIANO_UNAVAILABLE\n"); return; }
            NSInteger octave=[[piano valueForKey:@"startOctave"] integerValue];
            BeginPianoHold(piano,@"test",NSZeroPoint,octave);
            PianoArrowHold *hold=[pianoHolds objectForKey:piano];
            [hold fire]; [hold fire]; CancelPianoHold(piano);
        } else if ([command isEqualToString:@"PIANO_HOLD_CANCEL"]) {
            NSView *piano=PianoItemForView(nil).view;
            BeginPianoHold(piano,@"test",NSZeroPoint,[[piano valueForKey:@"startOctave"] integerValue]);
            CancelPianoHold(piano);
        } else if ([command hasPrefix:@"NAV_"] || [command hasPrefix:@"OCT_"]) {
            BOOL octave=[command hasPrefix:@"OCT_"];
            if(octave) command=[@"NAV_" stringByAppendingString:[command substringFromIndex:4]];
            MidiNavigationButton *button=octave ? octavesButton : navigationButton;
            if (!button) return;
            BOOL left=[command hasSuffix:@"LEFT"];
            if ([command hasPrefix:@"NAV_TAP_"]) {
                NSPoint point=NSMakePoint(left ? button.bounds.size.width*0.2 : button.bounds.size.width*0.8,15);
                [button beginAt:point identity:nil]; [button finishAt:point];
            } else if ([command hasPrefix:@"NAV_SWIPE_"]) {
                BOOL positive=[command containsString:@"SWIPE_RIGHT"];
                NSPoint start=NSMakePoint(positive ? 5 : button.bounds.size.width-5,15), end=NSMakePoint(positive ? button.bounds.size.width-5 : 5,15);
                if([command containsString:@"SHORT"]) { end.x=start.x+(positive ? 9 : -9); end.y+=3; }
                [button beginAt:start identity:nil]; [button moveAt:end]; [button fireHold];
                if([command containsString:@"CANCEL"]) [button cancelGesture];
                if([command containsString:@"RETURN"]) end=start;
                [button finishAt:end];
            } else if ([command isEqualToString:@"NAV_HOLD"]) {
                NSPoint point=NSMakePoint(NSMidX(button.bounds),15);
                [button beginAt:point identity:nil]; [button fireHold]; [button fireHold]; [button finishAt:point];
            } else if ([command isEqualToString:@"NAV_CANCEL"]) {
                [button beginAt:NSMakePoint(12,15) identity:nil]; [button cancelGesture]; [button fireHold]; [button finishAt:NSMakePoint(52,15)];
            } else if ([command isEqualToString:@"NAV_RELEASE"]) { [button finishAt:NSMakePoint(32,15)]; [button fireHold]; }
        } else if ([command isEqualToString:@"STATUS"]) {
            NSDictionary *status = @{@"visible": [delegate valueForKey:@"touchbarShown"] ?: @NO,
                @"preset": [delegate valueForKey:@"userTouchbarNumber"] ?: @0,
                @"presetCount": @([[delegate valueForKey:@"allUserTouchbars"] count]),
                @"registeredKeyCount": @([((id (*)(id,SEL))objc_msgSend)([delegate valueForKey:@"keyCenter"],NSSelectorFromString(@"registeredHotKeys")) count]),
                @"statusMenuTitles": MenuTitles([[delegate valueForKey:@"theItem"] menu]) ?: @[],
                @"statusIconName": [[[delegate valueForKey:@"theItem"] button] image].name ?: @"",
                @"cycleKeyCount": @(CycleKeyCount(delegate, NSEventModifierFlagOption)),
                @"backKeyCount": @(CycleKeyCount(delegate, NSEventModifierFlagControl)),
                @"presentation": presentation.itemIdentifiers ?: @[],
                @"closeIsFirst": @([presentation.itemIdentifiers.firstObject isEqualToString:CloseID]),
                @"recordIsLast": @([presentation.itemIdentifiers.lastObject isEqualToString:RecordID]),
                @"closeNavigationJoined": @(navigationButton && navigationButton.superview==closeButton.superview),
                @"navigationPresetHue": @(navigationButton.presetHue),
                @"recordLit": @(recordController.button.recordLit),
                @"pianoViews": PianoGeometry(((NSGroupTouchBarItem *)[presentation itemForIdentifier:LayoutID]).groupTouchBar),
                @"surfaceMode": [delegate valueForKey:@"controlSurfadeMode"] ?: @NO,
                @"pianoExpanded": @(pianoExpanded),
                @"presentationSerial": @(presentationSerial),
                @"pianoConfigIsFirst": @(pianoExpanded && [presentation.itemIdentifiers.firstObject isEqualToString:OctavesID]),
                @"pianoOctaveCount": [expandedPianoView ?: PianoItemForView(nil).view valueForKey:@"numOctaves"] ?: @(-1),
                @"pianoKeyCount": @([[expandedPianoView ?: PianoItemForView(nil).view valueForKey:@"pianoKeys"] count]),
                @"pianoWidth": @(expandedPianoView ? expandedPianoView.frame.size.width : PianoItemForView(nil).view.frame.size.width),
                @"pianoWindowWidth": @(expandedPianoView ? expandedPianoView.window.contentView.bounds.size.width : PianoItemForView(nil).view.window.contentView.bounds.size.width),
                @"closeWindowWidth": @(closeButton.window.contentView.bounds.size.width),
                @"pianoOctave": [expandedPianoView ?: PianoItemForView(nil).view valueForKey:@"startOctave"] ?: @(-1),
                @"pianoStartNote": @(PianoStartNote(expandedPianoView ?: PianoItemForView(nil).view)),
                @"pianoFirstPitch": [[expandedPianoView ?: PianoItemForView(nil).view valueForKey:@"pianoKeys"] valueForKeyPath:@"@min.pitch"] ?: @(-1),
                @"pianoExpansionLayout": pianoExpanded ? @[expandedPianoItem.identifier] : @[],
                @"layout": [[delegate valueForKey:@"mainTouchBar"] itemIdentifiers] ?: @[],
                @"modalLayout": [[delegate valueForKey:@"currentRootTouchbar"] itemIdentifiers] ?: @[],
                @"customization": [[delegate valueForKey:@"mainTouchBar"] customizationIdentifier] ?: @"",
                @"savedLayouts": @([NSUserDefaults.standardUserDefaults.dictionaryRepresentation.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", @"ControllerConfig:"]].count),
                @"settingsDomain": NSBundle.mainBundle.bundleIdentifier ?: @"",
                @"menuItems": @([NSApp.mainMenu numberOfItems])};
            NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
            Report([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            Report("\n");
        } else if ([command isEqualToString:@"QUIT"]) {
            midiTerminating=YES;
            // The menu belongs to the bundled MIDI helper, not the parent
            // 3E process. Quit both so no tray/helper instance remains.
            QuitThreeEParent();
            [NSApp terminate:nil];
        }
    } @catch (NSException *e) { Report("BRIDGE_ERROR\n"); NSLog(@"ThreeE MIDI bridge: %@", e); }
}
@implementation ThreeEMidiBridge
+ (void)toggleTouchTab:(id)sender { Report("TOUCHTAB_TOGGLE\n"); }
+ (void)toggleApps:(id)sender { Report("APPS_TOGGLE\n"); }
+ (void)openPhone:(id)sender { Report("PHONE_OPEN\n"); }
+ (void)copyPhone:(id)sender { Report("PHONE_COPY\n"); }
+ (void)stopPhone:(id)sender { Report("PHONE_STOP\n"); }
+ (void)togglePhoneBar:(id)sender { Report("PHONE_TOGGLE\n"); }
+ (void)hoverPhoneBar:(id)sender { Report("PHONE_HOVER\n"); }
+ (void)hidePhoneBarQR:(id)sender { Report("PHONE_HIDE_QR\n"); }
+ (void)toggleDownloads:(id)sender { Report("DOWNLOADS_TOGGLE\n"); }
// Restart quits the whole suite, checks for an update (installing it if
// newer, or if this is the wrong edition), and reopens 3E — like Windows.
+ (void)restartAll:(id)sender { StripRestart(); }
+ (void)toggleMidi:(id)sender { Command([[(id)NSApp.delegate valueForKey:@"touchbarShown"] boolValue] ? @"HIDE" : @"SHOW"); ApplyBranding(); }
+ (void)toggleAutomaticUpdates:(id)sender { StripToggleAutomaticUpdates(self,_cmd,sender); }
+ (void)toggleSurfaceMode:(id)sender { ChangeMode(NSApp.delegate,NSSelectorFromString(@"changeMode:"),sender); }
+ (BOOL)validateMenuItem:(NSMenuItem *)item {
    if(item.action==@selector(toggleApps:)) {
        item.state=appsMenuVisible&&!recordController.activeMenuBar ? NSControlStateValueOn : NSControlStateValueOff; return YES;
    }
    if(item.action==@selector(toggleTouchTab:)) {
        item.state=[combinedGestureState isEqual:@"on"] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if(item.action==@selector(toggleAutomaticUpdates:)) {
        item.state=StripAutomaticUpdatesEnabled() ? NSControlStateValueOn : NSControlStateValueOff; return YES;
    }
    if(item.action==@selector(toggleMidi:)) {
        item.title=@"Touch Bar Midi";
        item.state=[[(id)NSApp.delegate valueForKey:@"touchbarShown"] boolValue] && !recordController.activeMenuBar && !appsMenuVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return ![[(id)NSApp.delegate valueForKey:@"editTouchBar"] boolValue] && ![[(id)NSApp.delegate valueForKey:@"editCCs"] boolValue];
    }
    if(item.action==@selector(toggleDownloads:)) { item.state=downloadsEnabled?NSControlStateValueOn:NSControlStateValueOff;return YES; }
    if(item.action==@selector(toggleSurfaceMode:)) {
        item.state=recordController.activeMenuBar&&!appsMenuVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return ![[(id)NSApp.delegate valueForKey:@"editTouchBar"] boolValue] && ![[(id)NSApp.delegate valueForKey:@"editCCs"] boolValue];
    }
    return YES;
}
+ (void)closeMidi:(id)sender { if(pianoExpanded) CollapsePiano(); else Command(@"HIDE"); }
+ (void)load {
#ifdef STRIP3_RECORD_TESTING
    return; // Gesture tests never install helper hooks or add a tray item.
#endif
    @autoreleasepool {
        if(!StripInstallUpdateHooks()) NSLog(@"3E release-update hooks unavailable");
        Method tray = class_getClassMethod(NSTouchBarItem.class, NSSelectorFromString(@"addSystemTrayItem:"));
        if (tray) method_setImplementation(tray, (IMP)SuppressTray);
        Class keyCenter = NSClassFromString(@"DDHotKeyCenter");
        Method registerKey = class_getInstanceMethod(keyCenter, NSSelectorFromString(@"registerHotKeyWithKeyCode:modifierFlags:target:action:object:"));
        if (!registerKey) { Report("BRIDGE_ERROR\n"); return; }
        method_setImplementation(registerKey, (IMP)RegisterKey);
        for(NSString *name in @[@"_registerHotKey:",@"registerHotKey:"]) {
            Method method=class_getInstanceMethod(keyCenter,NSSelectorFromString(name));
            if(method) method_setImplementation(method,(IMP)BlockHotKey);
        }
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:NSApp queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            midiTerminating=YES;
            // Native menu Quit terminates this bundled helper directly and
            // does not pass through Command(@"QUIT"). Always shut down the
            // parent 3E process as part of that same user action.
            QuitThreeEParent();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            Class cls = [NSApp.delegate class];
            InstallNativeCustomizationHooks();
            originalMakeItem=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"touchBar:makeItemForIdentifier:")),(IMP)MakeIndependentPiano);
            originalPianoTouched=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"pianoTouched:")),(IMP)ConfigureIndependentPiano);
            originalPianoAlertModal=method_setImplementation(class_getInstanceMethod(NSAlert.class,@selector(runModal)),(IMP)PianoSettingsAlertModal);
            for(NSString *name in @[NSWindowDidBecomeKeyNotification,NSWindowDidUpdateNotification])
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    HidePianoGestureSetting(((NSWindow *)note.object).contentView);
                    id vc=[(id)NSApp.delegate valueForKey:@"settingsViewController"];
                    if(((NSWindow *)note.object).contentViewController==vc) HideExpandedOnlySettings(vc);
                }];
            originalExitCustomization=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"exitCustomization")),(IMP)ExitCustomization);
            method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"customizeTouchbar:")),(IMP)SafeCustomizeTouchbar);
            ExtendPianoPalette(NSApp.delegate);
            Method keyConfig=class_getInstanceMethod(cls,NSSelectorFromString(@"setKeyCommands:"));
            if(keyConfig) method_setImplementation(keyConfig,(IMP)IgnoreKeyCommands);
            id keyCenter=[(id)NSApp.delegate valueForKey:@"keyCenter"];
            ((void (*)(id,SEL))objc_msgSend)(keyCenter,NSSelectorFromString(@"unregisterAllHotKeys"));
            Method open = class_getInstanceMethod(cls, NSSelectorFromString(@"openTouchbar:fromIdentifier:"));
            Method close = class_getInstanceMethod(cls, NSSelectorFromString(@"closeTouchbar:"));
            if (!open || !close || ![NSApp.delegate respondsToSelector:NSSelectorFromString(@"showTouchbar:")]) { Report("BRIDGE_ERROR\n"); return; }
            class_addMethod(cls, NSSelectorFromString(@"threeECycle:"), (IMP)Cycle, "v@:@");
            class_addMethod(cls, NSSelectorFromString(@"threeECycleBack:"), (IMP)Cycle, "v@:@");
            originalPresetHandler=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"receivedGlobalKeyFrom:key:")),(IMP)PresetKey);
            originalChangeMode=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"changeMode:")),(IMP)ChangeMode);
            pianoHolds=[NSMapTable weakToStrongObjectsMapTable];
            Class pianoClass=NSClassFromString(@"pianoView");
            originalPianoDraw=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(drawRect:)),(IMP)DrawPianoScale);
            originalPianoLayout=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(viewWillDraw)),(IMP)PianoLayout);
            originalPianoBegan=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(touchesBeganWithEvent:)),(IMP)PianoBegan);
            originalPianoMoved=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(touchesMovedWithEvent:)),(IMP)PianoMoved);
            originalPianoEnded=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(touchesEndedWithEvent:)),(IMP)PianoEnded);
            originalPianoCancelled=method_setImplementation(class_getInstanceMethod(pianoClass,@selector(touchesCancelledWithEvent:)),(IMP)PianoCancelled);
            originalOpen = method_setImplementation(open, (IMP)Open);
            originalShow = method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"showTouchbar:")),(IMP)ShowPreset);
            originalClose = method_setImplementation(close, (IMP)Close);
            InstallControlCustomizationHooks(cls);
            dispatch_async(dispatch_get_main_queue(), ^{
                ApplyBranding();
                BrandMIDIPorts();
                [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                    BrandMIDIPorts();
                    ApplyBranding();
                }];
                InitializePresetCatalog();
                ExtendPianoPalette(NSApp.delegate);
                if([NSUserDefaults.standardUserDefaults boolForKey:DJEnabledKey]) DJActivateLayouts();
                [[ThreeEDJMIDI shared] start];
                Report("READY\n");
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    char line[128];
                    while (fgets(line, sizeof(line), stdin)) {
                        NSString *command = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                        dispatch_async(dispatch_get_main_queue(), ^{ Command(command); });
                    }
                    // Parent exited or crashed: don't leave an orphan MIDI engine.
                    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
                });
            });
        }];
    }
}
@end
