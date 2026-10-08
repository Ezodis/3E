#import "KeyboardTouchBarView.h"

@implementation KeyboardTouchBarView {
    NSMutableSet<NSNumber *> *_activeNotes;
}
- (instancetype)initWithFrame:(NSRect)frameRect { if((self=[super initWithFrame:frameRect])) { _activeNotes=[NSMutableSet set]; self.wantsLayer=YES; self.allowedTouchTypes=NSTouchTypeMaskDirect; } return self; }
- (BOOL)isFlipped { return YES; }
- (void)setConfiguration:(KeyboardConfiguration *)configuration { _configuration=[configuration copy]; [self setNeedsDisplay:YES]; }
- (NSInteger)noteAtPoint:(NSPoint)point { NSInteger keyCount=MAX(1,self.configuration.octaveCount*12); NSInteger key=(NSInteger)floor(MAX(0,MIN(NSWidth(self.bounds)-1,point.x))*keyCount/NSWidth(self.bounds)); return self.configuration.baseNote+self.configuration.transpose+key; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:.08 alpha:1] setFill]; NSRectFill(self.bounds);
    NSInteger keyCount=MAX(1,self.configuration.octaveCount*12); CGFloat width=NSWidth(self.bounds)/keyCount;
    for(NSInteger key=0;key<keyCount;key++) { NSInteger note=self.configuration.baseNote+self.configuration.transpose+key; NSRect rect=NSMakeRect(key*width,1,MAX(1,width-1),NSHeight(self.bounds)-2); BOOL active=[_activeNotes containsObject:@(note)]; [(active ? [NSColor systemBlueColor] : [NSColor colorWithWhite:.86 alpha:1]) setFill]; NSRectFill(rect); }
}
- (void)beginAt:(NSPoint)point { NSInteger note=[self noteAtPoint:point]; if([_activeNotes containsObject:@(note)]) return; [_activeNotes addObject:@(note)]; [self.midiOutput noteOn:note velocity:self.configuration.velocity channel:self.configuration.midiChannel]; [self setNeedsDisplay:YES]; }
- (void)endAll { for(NSNumber *note in _activeNotes) [self.midiOutput noteOff:note.integerValue channel:self.configuration.midiChannel]; [_activeNotes removeAllObjects]; [self setNeedsDisplay:YES]; }
- (void)mouseDown:(NSEvent *)event { [self beginAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseDragged:(NSEvent *)event { [self beginAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self endAll]; }
- (void)touchesBeganWithEvent:(NSEvent *)event { for(NSTouch *touch in [event touchesMatchingPhase:NSTouchPhaseBegan inView:self]) [self beginAt:[touch locationInView:self]]; }
- (void)touchesEndedWithEvent:(NSEvent *)event { [self endAll]; }
- (void)touchesCancelledWithEvent:(NSEvent *)event { [self endAll]; }
@end
