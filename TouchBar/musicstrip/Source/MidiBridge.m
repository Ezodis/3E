#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <math.h>
#import <CoreMIDI/CoreMIDI.h>
#import "ReleaseUpdates.h"

// Change labels only on this engine's own streams. Do not recreate endpoints,
// change their unique IDs, or touch another application's MIDI connections.
static void BrandMIDIPorts(void) {
    NSDictionary *labels=@{@"virtualSurfaceInputStream":@"3£ Surface",
                           @"virtualSurfaceOutputStream":@"3£ Surface",
                           @"virtualUserInputStream":@"3£ Keyboard",
                           @"virtualUserOutputStream":@"3£ Keyboard"};
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
static void QuitMusicStripParent(void) {
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.musicstrip.app"]) {
        if(app.processIdentifier==NSProcessInfo.processInfo.processIdentifier || app.terminated) continue;
        [app terminate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.75*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if(!app.terminated) [app forceTerminate];
        });
    }
}
static IMP originalOpen, originalClose, originalPresetHandler, originalChangeMode;
static NSTouchBar *presentation;
static NSButton *closeButton;
static NSString *const CloseID = @"local.musicstrip.midi.close";
static NSString *const LayoutID = @"local.musicstrip.midi.layout";
static void Cycle(id target, SEL selector, id sender);
static void SwitchMode(void);
static void ChangeOctaves(NSInteger direction);
static void ExpandPiano(NSView *piano);
static void CollapsePiano(void);
static void ResetPianoExpansion(void);
static void CancelPianoHold(NSView *piano);
static void UpdateActivePianoSizing(void);
static void SuspendPianoSizing(NSTouchBar *bar);
static NSInteger PianoCount(NSTouchBar *bar);
static void SizePianos(NSTouchBar *bar);
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
static void SetPianoStartNote(NSView *piano,NSInteger note) {
    NSInteger octaves=[[piano valueForKey:@"numOctaves"] integerValue];
    note=MIN(MAX(0,note),MAX(0,(10-octaves)*12));
    [piano setValue:@(note/12) forKey:@"startOctave"];
    objc_setAssociatedObject(piano,&halfOctaveKey,@(note%12==6),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [piano setValue:@(-1) forKey:@"lastWidth"]; piano.needsDisplay=YES;
}
// Keep the original key shapes, touch regions, note engine and appearance.
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
    if(!PianoHalf(piano)) return;
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
@property NSInteger joinedEdge; // 1 = left half, 2 = right half; 0 = native bezel.
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
    if(!self.joinedEdge) { [super drawRect:dirtyRect]; return; }
    [NSGraphicsContext saveGraphicsState];
    NSRect whole=NSMakeRect(self.joinedEdge==2 ? -44 : 0,1,88,28);
    [[NSBezierPath bezierPathWithRoundedRect:whole xRadius:7 yRadius:7] addClip];
    NSColor *start, *end;
    if(self.joinedEdge==1) {
        start=self.recordLit ? [NSColor colorWithSRGBRed:.95 green:.12 blue:.18 alpha:1] : [NSColor colorWithWhite:.20 alpha:1];
        end=self.recordLit ? [NSColor colorWithSRGBRed:.64 green:.02 blue:.10 alpha:1] : [NSColor colorWithWhite:.11 alpha:1];
    } else {
        start=[NSColor colorWithCalibratedHue:self.presetHue saturation:.72 brightness:.82 alpha:1];
        end=[NSColor colorWithCalibratedHue:fmod(self.presetHue+.10,1) saturation:.85 brightness:.46 alpha:1];
    }
    [[[NSGradient alloc] initWithStartingColor:start endingColor:end] drawInRect:self.bounds angle:0];
    if(self.highlighted) { [[NSColor colorWithWhite:1 alpha:.16] setFill]; NSRectFillUsingOperation(self.bounds,NSCompositingOperationSourceOver); }
    if(self.joinedEdge==2) {
        [[NSColor colorWithWhite:1 alpha:.22] setFill]; NSRectFill(NSMakeRect(0,5,.5,20));
    }
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
        else Cycle(NSApp.delegate,NSSelectorFromString(direction<0 ? @"musicStripCycleBack:" : @"musicStripCycle:"),nil);
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
    // The original mode handler rebuilds the bar. Finish this gesture before
    // that happens, and never turn the eventual release into a preset change.
    dispatch_async(dispatch_get_main_queue(), ^{ SwitchMode(); });
}
- (void)finishAt:(NSPoint)point {
    [self.holdTimer invalidate]; self.holdTimer=nil;
    if (!self.tracking) return;
    [self moveAt:point];
    CGFloat dx=point.x-self.startX, dy=point.y-self.startY;
    if(!self.octaveControl && !self.didStep && !self.held && !self.cancelled && NSPointInRect(point,self.bounds) && hypot(dx,dy)<8) {
        BOOL back=self.startX<NSMidX(self.bounds);
        [self step:back ? -1 : 1];
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
- (BOOL)accessibilityPerformPress { if(!self.octaveControl) Cycle(NSApp.delegate,NSSelectorFromString(@"musicStripCycle:"),nil); return YES; }
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
static void UpdatePianoConfigControls(void) {
    NSInteger mode=[[expandedPianoView valueForKey:@"type"] integerValue]; mode=MIN(2,MAX(0,mode));
    pianoModeButton.title=@[@"GLISS",@"HOLD",@"BEND"][mode];
    pianoModeButton.image=[NSImage imageWithSystemSymbolName:@[@"pianokeys",@"hand.raised.fill",@"waveform"][mode] accessibilityDescription:nil];
    [pianoModeButton setAccessibilityLabel:[NSString stringWithFormat:@"Piano gesture: %@. Tap to cycle, swipe left or right to change.",@[@"Glissando",@"No Glissando",@"Pitchbend"][mode]]];
    pianoChannelButton.title=[NSString stringWithFormat:@"Ch %@",[expandedPianoView valueForKey:@"channelNumber"]];
    [pianoChannelButton setAccessibilityLabel:[NSString stringWithFormat:@"MIDI channel %@. Tap or swipe to change this piano only.",[expandedPianoView valueForKey:@"channelNumber"]]];
}
#import "AbletonRecord.h"
@interface StripJoinedMidiControl : NSView
@end
@implementation StripJoinedMidiControl
- (NSSize)intrinsicContentSize { return NSMakeSize(88,30); }
@end
static void UpdateNavigationColor(void) {
    if(!navigationButton) return;
    id delegate=NSApp.delegate;
    NSInteger preset=[[delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSUInteger count=[[delegate valueForKey:@"allUserTouchbars"] count];
    BOOL surface=[[delegate valueForKey:@"controlSurfadeMode"] boolValue];
    CGFloat hue=surface ? .08 : fmod(.58+MAX(0,preset)/(double)MAX(1,count),1);
    if(navigationButton.presetHue!=hue) { navigationButton.presetHue=hue; navigationButton.needsDisplay=YES; }
    navigationButton.toolTip=surface ? @"MIDI Control Surface" : [NSString stringWithFormat:@"MIDI preset %ld",(long)preset+1];
}
static void JoinRecordNavigation(StripRecordController *controller,MidiNavigationButton *navigation,NSInteger preset,NSUInteger count) {
    navigation.presetHue=fmod(.58+MAX(0,preset)/(double)MAX(1,count),1);
    navigation.joinedEdge=2; controller.button.joinedEdge=1;
    NSView *joined=[[StripJoinedMidiControl alloc] initWithFrame:NSMakeRect(0,0,88,30)];
    joined.translatesAutoresizingMaskIntoConstraints=NO;
    [joined setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [joined setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    controller.button.frame=NSMakeRect(0,0,44,30); navigation.frame=NSMakeRect(44,0,44,30);
    controller.button.translatesAutoresizingMaskIntoConstraints=NO;
    navigation.translatesAutoresizingMaskIntoConstraints=NO;
    [joined addSubview:controller.button]; [joined addSubview:navigation];
    [NSLayoutConstraint activateConstraints:@[
        [joined.widthAnchor constraintEqualToConstant:88], [joined.heightAnchor constraintEqualToConstant:30],
        [controller.button.leadingAnchor constraintEqualToAnchor:joined.leadingAnchor],
        [controller.button.topAnchor constraintEqualToAnchor:joined.topAnchor],
        [controller.button.widthAnchor constraintEqualToConstant:44],
        [controller.button.heightAnchor constraintEqualToConstant:30],
        [navigation.leadingAnchor constraintEqualToAnchor:controller.button.trailingAnchor],
        [navigation.topAnchor constraintEqualToAnchor:joined.topAnchor],
        [navigation.widthAnchor constraintEqualToConstant:44],
        [navigation.heightAnchor constraintEqualToConstant:30],
        [navigation.trailingAnchor constraintEqualToAnchor:joined.trailingAnchor]
    ]];
    controller.item.collapsedRepresentation=joined;
}
static void RemoveCycleKey(id delegate) {
    id center = [delegate valueForKey:@"keyCenter"];
    for (NSString *action in @[@"musicStripCycle:", @"musicStripCycleBack:"]) {
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(center, NSSelectorFromString(@"unregisterHotKeysWithTarget:action:"), delegate, NSSelectorFromString(action));
    }
}
static id RegisterKey(id center, SEL selector, unsigned short code, NSUInteger flags, id target, SEL action, id object) {
    // Navigation is exclusively controlled by Touch Bar gestures.
    return nil;
}
static id BlockHotKey(id self, SEL selector, id key) { return nil; }
static void IgnoreKeyCommands(id self, SEL selector, id sender) {}
static NSImage *BrandMenuIcon(void) {
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(27,18)];
    [image lockFocus];
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:16 weight:NSFontWeightBold], NSForegroundColorAttributeName:NSColor.blackColor};
    NSString *text=@"3£"; NSSize size=[text sizeWithAttributes:attributes];
    [text drawAtPoint:NSMakePoint((27-size.width)/2,(18-size.height)/2) withAttributes:attributes];
    [image unlockFocus]; image.template=YES; image.name=@"Strip3£"; return image;
}
static void CleanMenu(NSMenu *menu) {
    for(NSMenuItem *item in menu.itemArray.copy) {
        NSString *title=item.title.lowercaseString;
        if(item.action==NSSelectorFromString(@"setKeyCommands:") || [title containsString:@"key command"] || [title containsString:@"keyboard shortcut"] || [title hasPrefix:@"customize controls"]) { [menu removeItem:item]; continue; }
        if([item.title hasPrefix:@"MIDI Touchbar (v."] || [item.title hasPrefix:@"3£ (v."])
            item.title=[NSString stringWithFormat:@"3£ (v. %@)",StripReleaseVersion];
        else if([item.title containsString:@"MIDI Touchbar"]) item.title=[item.title stringByReplacingOccurrencesOfString:@"MIDI Touchbar" withString:@"3£"];
        else if([item.title containsString:@"Strip3£"]) item.title=[item.title stringByReplacingOccurrencesOfString:@"Strip3£" withString:@"3£"];
        item.keyEquivalent=@""; item.keyEquivalentModifierMask=0;
        if(item.submenu) CleanMenu(item.submenu);
    }
}
static void ApplyBranding(void) {
    NSStatusItem *item=[(id)NSApp.delegate valueForKey:@"theItem"];
    item.length=27; item.button.image=BrandMenuIcon(); item.button.title=@""; item.button.toolTip=@"3£";
    CleanMenu(item.menu); CleanMenu(NSApp.mainMenu);
}
static NSArray *MenuTitles(NSMenu *menu) {
    NSMutableArray *titles=[NSMutableArray new];
    for(NSMenuItem *item in menu.itemArray) { [titles addObject:item.title]; if(item.submenu) [titles addObjectsFromArray:MenuTitles(item.submenu)]; }
    return titles;
}

@interface MusicStripMidiBridge : NSObject
+ (void)closeMidi:(id)sender;
@end
static void SuppressTray(id cls, SEL sel, id item) { Report("TRAY_SUPPRESSED\n"); }
static void Open(id self, SEL sel, NSTouchBar *bar, id identifier) {
    if (!rebuildingPresentation) ResetPianoExpansion();
    normalLayoutBar=bar; normalIdentifier=identifier;
    // Keep the original configurable bar intact inside a seamless group.
    // The fixed outer row guarantees that saved presets cannot hide the X.
    NSTouchBar *outer = [NSTouchBar new];
    NSCustomTouchBarItem *close = [[NSCustomTouchBarItem alloc] initWithIdentifier:CloseID];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Close MIDI Touchbar"];
    closeButton = [NSButton buttonWithImage:image target:MusicStripMidiBridge.class action:@selector(closeMidi:)];
    [closeButton setAccessibilityLabel:pianoExpanded ? @"Back to normal piano layout" : @"Close MIDI Touchbar"];
    closeButton.bordered = NO;
    closeButton.imagePosition = NSImageOnly;
    [closeButton.widthAnchor constraintEqualToConstant:32].active = YES;
    close.view = closeButton;
    close.visibilityPriority = NSTouchBarItemPriorityHigh;
    BOOL multiplePianos=!pianoExpanded && PianoCount(bar)>1;
    if(!pianoExpanded) SizePianos(bar);
    // Alert-style groups let the client choose spacing rather than inserting
    // standard button-sized gutters between neighboring keyboards.
    NSGroupTouchBarItem *layout = multiplePianos
        ? [NSGroupTouchBarItem alertStyleGroupItemWithIdentifier:LayoutID]
        : [[NSGroupTouchBarItem alloc] initWithIdentifier:LayoutID];
    layout.groupTouchBar=bar;
    layout.prefersEqualWidths=multiplePianos && (NSUInteger)PianoCount(bar)==bar.itemIdentifiers.count;
    navigationButton=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
    [navigationButton.widthAnchor constraintEqualToConstant:44].active=YES;
    recordController=[StripRecordController new];
    NSInteger preset=[[(id)NSApp.delegate valueForKey:@"userTouchbarNumber"] integerValue];
    NSUInteger presets=[[(id)NSApp.delegate valueForKey:@"allUserTouchbars"] count];
    JoinRecordNavigation(recordController,navigationButton,preset,presets);
    outer.templateItems = [NSSet setWithArray:@[close, layout, recordController.item]];
    outer.defaultItemIdentifiers = multiplePianos ? @[CloseID,LayoutID,RecordID] : @[CloseID, LayoutID, NSTouchBarItemIdentifierFlexibleSpace, RecordID];
    if (pianoExpanded) {
        recordController.button.joinedEdge=0;
        recordController.item.collapsedRepresentation=recordController.button;
        NSCustomTouchBarItem *octaves=[[NSCustomTouchBarItem alloc] initWithIdentifier:OctavesID];
        octavesButton=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        octavesButton.octaveControl=YES;
        octavesButton.image=nil; octavesButton.imagePosition=NSNoImage;
        octavesButton.title=[[expandedPianoView valueForKey:@"numOctaves"] stringValue];
        octavesButton.font=[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightMedium];
        [octavesButton setAccessibilityLabel:@"Visible piano octaves: swipe right to increase or left to decrease; tapping does nothing"];
        [octavesButton.widthAnchor constraintEqualToConstant:44].active=YES;
        octaves.view=octavesButton; octaves.visibilityPriority=NSTouchBarItemPriorityHigh;
        NSMutableArray *configItems=[NSMutableArray new];
        for(NSInteger i=0;i<2;i++) {
            NSString *configID=i ? @"local.musicstrip.piano.channel" : @"local.musicstrip.piano.gesture";
            NSCustomTouchBarItem *config=[[NSCustomTouchBarItem alloc] initWithIdentifier:configID];
            PianoConfigButton *button=[[PianoConfigButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
            button.octaveControl=YES; button.channelControl=i==1;
            button.font=[NSFont systemFontOfSize:i ? 10 : 8 weight:NSFontWeightMedium];
            button.imagePosition=i ? NSNoImage : NSImageAbove;
            [button.widthAnchor constraintEqualToConstant:44].active=YES;
            if(i) { pianoChannelButton=button; button.image=nil; } else pianoModeButton=button;
            config.view=button; config.visibilityPriority=NSTouchBarItemPriorityHigh; [configItems addObject:config];
        }
        UpdatePianoConfigControls();
        outer.templateItems=[NSSet setWithArray:@[close,expandedPianoItem,configItems[0],configItems[1],octaves]];
        outer.defaultItemIdentifiers=@[CloseID,expandedPianoItem.identifier,@"local.musicstrip.piano.gesture",@"local.musicstrip.piano.channel",OctavesID];
        outer.principalItemIdentifier=expandedPianoItem.identifier;
        navigationButton=nil;
    }
    presentationSerial++;
    presentation = outer;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration=0; context.allowsImplicitAnimation=NO;
        ((void (*)(id, SEL, id, id))originalOpen)(self, sel, outer, identifier);
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
    [octavesButton cancelGesture]; octavesButton=nil;
    [pianoModeButton cancelGesture]; [pianoChannelButton cancelGesture]; pianoModeButton=nil; pianoChannelButton=nil;
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
    pianoFullWidth=available-32-44-44-44-40;
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
@property NSInteger direction;
- (void)fire;
@end
@implementation PianoArrowHold
- (void)fire {
    [self.timer invalidate]; self.timer=nil;
    NSView *piano=self.piano;
    if(self.fired || self.cancelled || !piano || [[piano valueForKey:@"activeKeys"] count]) return;
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
    NSSet<NSTouch *> *touches=[event touchesMatchingPhase:NSTouchPhaseBegan inView:piano];
    NSTouch *touch=touches.count==1 ? touches.anyObject : nil;
    NSPoint point=touch ? [touch locationInView:piano] : NSZeroPoint;
    NSBezierPath *up=[piano valueForKey:@"upKey"], *down=[piano valueForKey:@"downKey"];
    // Fixed-width edges remain usable even when many octaves compress keys.
    BOOL region=(up && NSPointInRect(point,up.bounds)) || (down && NSPointInRect(point,down.bounds));
    if(touch && touch.type==NSTouchTypeDirect && region && ![[piano valueForKey:@"activeKeys"] count]) {
        NSInteger note=PianoStartNote(piano);
        BOOL forward=up && NSPointInRect(point,up.bounds);
        BeginPianoHold(piano,touch.identity,point,note/12);
        [pianoHolds objectForKey:piano].direction=forward ? 1 : -1;
        Report("PIANO_ARROW_HOLD_ARMED\n");
        return;
    }
    ((void(*)(id,SEL,id))originalPianoBegan)(piano,selector,event);
}
static void PianoMoved(NSView *piano,SEL selector,NSEvent *event) {
    PianoArrowHold *hold=[pianoHolds objectForKey:piano];
    for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseTouching inView:piano]) {
        if(hold && [touch.identity isEqual:hold.identity]) {
            NSPoint point=[touch locationInView:piano];
            NSRect edge=[[piano valueForKey:hold.direction>0 ? @"upKey" : @"downKey"] bounds];
            if(!NSPointInRect(point,NSInsetRect(edge,-4,-4))) { hold.cancelled=YES; [hold.timer invalidate];hold.timer=nil; }
        }
    }
    if(!hold) ((void(*)(id,SEL,id))originalPianoMoved)(piano,selector,event);
}
static void PianoEnded(NSView *piano,SEL selector,NSEvent *event) {
    PianoArrowHold *hold=[pianoHolds objectForKey:piano];
    if(hold && !hold.fired && !hold.cancelled) MovePianoHalf(piano,hold.direction);
    CancelPianoHold(piano);
    ((void(*)(id,SEL,id))originalPianoEnded)(piano,selector,event);
}
static void PianoCancelled(NSView *piano,SEL selector,NSEvent *event) {
    CancelPianoHold(piano);
    ((void(*)(id,SEL,id))originalPianoCancelled)(piano,selector,event);
}
static void ChangeMode(id self,SEL selector,id sender) {
    if(pianoExpanded) { CollapsePiano(); if(pianoExpanded) return; }
    ((void(*)(id,SEL,id))originalChangeMode)(self,selector,sender);
}
static void PresetKey(id self,SEL selector,id sender,id key) {
    if(pianoExpanded) { CollapsePiano(); if(pianoExpanded) return; }
    ((void(*)(id,SEL,id,id))originalPresetHandler)(self,selector,sender,key);
}
static void Close(id self, SEL sel, id bar) {
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
    NSInteger direction = selector == NSSelectorFromString(@"musicStripCycleBack:") ? -1 : 1;
    NSInteger next = daw ? (direction < 0 ? count - 1 : 0) : (current + direction + count) % count;
    [delegate setValue:@NO forKey:@"controlSurfadeMode"];
    // Use the original preset-switch handler so all mappings, settings and
    // per-preset customization continue to resolve through the original engine.
    ((void (*)(id, SEL, id, id))objc_msgSend)(delegate,
        NSSelectorFromString(@"receivedGlobalKeyFrom:key:"), nil, @(next));
    UpdateNavigationColor();
    Report("CYCLED\n");
}
static void SwitchMode(void) {
    id delegate=NSApp.delegate;
    if (![[delegate valueForKey:@"touchbarShown"] boolValue] ||
        [[delegate valueForKey:@"editTouchBar"] boolValue] || [[delegate valueForKey:@"editCCs"] boolValue]) return;
    ((void (*)(id,SEL,id))objc_msgSend)(delegate,NSSelectorFromString(@"changeMode:"),nil);
    UpdateNavigationColor();
    Report("MODE_CHANGED\n");
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
static void UpdateActivePianoSizing(void) {
    if(!presentation || pianoExpanded || customizationBar) return;
    NSGroupTouchBarItem *layout=(NSGroupTouchBarItem *)[presentation itemForIdentifier:LayoutID];
    NSTouchBar *bar=layout.groupTouchBar;
    if(!bar) return;
    SizePianos(bar);
    NSInteger count=0; for(NSString *identifier in bar.itemIdentifiers) if(IsPianoSlot(identifier)) count++;
    NSArray *ids=count>1 ? @[CloseID,LayoutID,RecordID] : @[CloseID,LayoutID,NSTouchBarItemIdentifierFlexibleSpace,RecordID];
    if(![presentation.defaultItemIdentifiers isEqual:ids]) presentation.defaultItemIdentifiers=ids;
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
    NSTouchBar *bar=[NSTouchBar new]; bar.delegate=(id<NSTouchBarDelegate>)delegate;
    bar.defaultItemIdentifiers=[@[NativePianoID,SecondPianoID,ThirdPianoID] subarrayWithRange:NSMakeRange(0,count)];
    bar.customizationIdentifier=[@"local.musicstrip.flex-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    Close(delegate,NSSelectorFromString(@"closeTouchbar:"),presentation);
    Open(delegate,NSSelectorFromString(@"openTouchbar:fromIdentifier:"),bar,savedIdentifier);
    NSArray *firstItems=presentation.defaultItemIdentifiers.copy;
    NSCAssert(![firstItems containsObject:NSTouchBarItemIdentifierFlexibleSpace],@"Multi-piano presentation must start without a spacer, not remove it on the later refresh");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        @try {
            UpdateActivePianoSizing();
            NSCAssert([firstItems isEqual:presentation.defaultItemIdentifiers],@"Refreshing must not rebuild the visible multi-piano row");
            NSArray *geometry=PianoGeometry(bar); CGFloat width=[geometry.firstObject[@"width"] doubleValue];
            for(NSDictionary *view in geometry) {
                NSRect position=NSRectFromString(view[@"position"]);
                NSCAssert([view[@"attached"] boolValue] && fabs([view[@"width"] doubleValue]-width)<1 && position.origin.y>=0 && NSMaxX(position)<=[view[@"windowWidth"] doubleValue],@"Actual native Touch Bar must display all three keyboards at equal widths without clipping or hidden containers");
            }
            NSCAssert(width*count>480,@"Native keyboards must expand beyond the old fixed 480-point total");
            for(NSString *identifier in bar.itemIdentifiers)
                TestPianoNotesView(((NSCustomTouchBarItem *)[bar itemForIdentifier:identifier]).view);
            NSData *json=[NSJSONSerialization dataWithJSONObject:geometry options:0 error:nil];
            Report([[NSString stringWithFormat:@"NATIVE_FLEX_%ld_PIANOS_PASSED %@\n",(long)count,[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]] UTF8String]);
        } @finally {
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
        NSCAssert(![presentation.itemIdentifiers containsObject:RecordID],@"Expanded piano must not contain Record");
        for(NSInteger modeStep=0;modeStep<3;modeStep++) {
            NSInteger before=[[expandedPianoView valueForKey:@"type"] integerValue];
            [pianoModeButton beginAt:NSMakePoint(22,15) identity:NSUUID.UUID]; [pianoModeButton finishAt:NSMakePoint(22,15)];
            NSCAssert([[expandedPianoView valueForKey:@"type"] integerValue]==(before+1)%3,@"Actual gesture button must cycle the native modes");
        }
        [pianoChannelButton beginAt:NSMakePoint(22,15) identity:NSUUID.UUID]; [pianoChannelButton finishAt:NSMakePoint(22,15)];
        NSCAssert([[expandedPianoView valueForKey:@"channelNumber"] integerValue]==[channel integerValue]%16+1,@"Channel cycle affects the expanded piano");
        [pianoChannelButton beginAt:NSMakePoint(30,15) identity:NSUUID.UUID]; [pianoChannelButton moveAt:NSMakePoint(10,15)]; [pianoChannelButton finishAt:NSMakePoint(10,15)];
        NSCAssert([[expandedPianoView valueForKey:@"channelNumber"] isEqual:channel],@"Channel swipe can go back");
        for(NSView *control in @[pianoModeButton,pianoChannelButton,octavesButton]) {
            NSRect frame=[control convertRect:control.bounds toView:nil];
            NSCAssert(control.window && frame.origin.x>=0 && NSMaxX(frame)<=control.window.contentView.bounds.size.width,@"All expanded settings controls must be visible");
        }
        NSInteger octaveDirection=count<10-[[expandedPianoView valueForKey:@"startOctave"] integerValue] ? 1 : -1;
        ChangeOctaves(octaveDirection);
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
    } @finally { liveScaleMask=saved; }
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
static void Command(NSString *command) {
    id delegate = NSApp.delegate;
    @try {
        if ([command isEqualToString:@"PIANO_INSTANCES_TEST"]) {
            TestIndependentPianos();
        } else if ([command isEqualToString:@"PIANO_NATIVE_ADD_TEST"]) {
            TestNativePianoAddition();
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
        } else if ([command isEqualToString:@"PIANO_ALL_SIDE_HOLDS_TEST"]) {
            TestAllPianoExpansion();
        } else if ([command isEqualToString:@"UPDATE_SOURCE_TEST"]) {
            Class cls=[NSApp.delegate class];
            NSCAssert(method_getImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"checkForUpdate:")))==(IMP)StripUpdateMenu,@"Manual update hook");
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
            Cycle(delegate, NSSelectorFromString(@"musicStripCycle:"), nil);
        } else if ([command isEqualToString:@"CYCLE_BACK"]) {
            Cycle(delegate, NSSelectorFromString(@"musicStripCycleBack:"), nil);
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
            NSString *path=[NSString stringWithFormat:@"/Users/3du/Documents/Codex/2026-10-01/i-l/work/musicstrip/integration/piano-%@-v031.png",[command substringFromIndex:14].lowercaseString];
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
                @"navigationIsLast": @(navigationButton && [presentation.itemIdentifiers.lastObject isEqualToString:RecordID]),
                @"recordNavigationJoined": @(navigationButton && navigationButton.superview==recordController.button.superview),
                @"navigationPresetHue": @(navigationButton.presetHue),
                @"recordLit": @(recordController.button.recordLit),
                @"pianoViews": PianoGeometry(((NSGroupTouchBarItem *)[presentation itemForIdentifier:LayoutID]).groupTouchBar),
                @"surfaceMode": [delegate valueForKey:@"controlSurfadeMode"] ?: @NO,
                @"pianoExpanded": @(pianoExpanded),
                @"presentationSerial": @(presentationSerial),
                @"octavesIsLast": @([presentation.itemIdentifiers.lastObject isEqualToString:OctavesID]),
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
            // Strip3£ process. Quit both so no tray/helper instance remains.
            QuitMusicStripParent();
            [NSApp terminate:nil];
        }
    } @catch (NSException *e) { Report("BRIDGE_ERROR\n"); NSLog(@"MusicStrip MIDI bridge: %@", e); }
}
@implementation MusicStripMidiBridge
+ (void)closeMidi:(id)sender { if(pianoExpanded) CollapsePiano(); else Command(@"HIDE"); }
+ (void)load {
#ifdef STRIP3_RECORD_TESTING
    return; // Gesture tests never install helper hooks or add a tray item.
#endif
    @autoreleasepool {
        if(!StripInstallUpdateHooks()) NSLog(@"3£ release-update hooks unavailable");
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
            // parent Strip3£ process as part of that same user action.
            QuitMusicStripParent();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            Class cls = [NSApp.delegate class];
            InstallNativeCustomizationHooks();
            originalMakeItem=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"touchBar:makeItemForIdentifier:")),(IMP)MakeIndependentPiano);
            originalPianoTouched=method_setImplementation(class_getInstanceMethod(cls,NSSelectorFromString(@"pianoTouched:")),(IMP)ConfigureIndependentPiano);
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
            class_addMethod(cls, NSSelectorFromString(@"musicStripCycle:"), (IMP)Cycle, "v@:@");
            class_addMethod(cls, NSSelectorFromString(@"musicStripCycleBack:"), (IMP)Cycle, "v@:@");
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
            originalClose = method_setImplementation(close, (IMP)Close);
            dispatch_async(dispatch_get_main_queue(), ^{
                ApplyBranding();
                BrandMIDIPorts();
                [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                    BrandMIDIPorts();
                    NSStatusItem *item=[(id)NSApp.delegate valueForKey:@"theItem"];
                    CleanMenu(item.menu); CleanMenu(NSApp.mainMenu);
                }];
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
