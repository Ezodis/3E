#import "AbletonRecordControl.h"

@implementation AbletonRecordControl {
    NSPoint _startPoint;
    BOOL _tracking;
    BOOL _held;
    NSTimer *_holdTimer;
}
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame])) { self.wantsLayer=YES; self.allowedTouchTypes=NSTouchTypeMaskDirect; } return self; }
- (BOOL)isFlipped { return YES; }
- (void)setAbletonActive:(BOOL)active { _abletonActive=active; self.accessibilityLabel=active ? @"Ableton Record: tap to toggle, swipe right to record, swipe left to stop, hold for recording options" : @"Ableton Record unavailable"; [self setNeedsDisplay:YES]; }
- (void)setRecording:(BOOL)recording { _recording=recording; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *background=!self.abletonActive ? [NSColor colorWithWhite:.18 alpha:1] : self.recording ? [NSColor colorWithCalibratedRed:.85 green:.04 blue:.04 alpha:1] : [NSColor colorWithWhite:.24 alpha:1];
    [background setFill]; NSRectFill(self.bounds);
    [[NSColor whiteColor] setFill]; NSRect dot=NSInsetRect(self.bounds,NSWidth(self.bounds)*.32,NSHeight(self.bounds)*.28); [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
}
- (void)beginAt:(NSPoint)point { if(!self.abletonActive) return; _startPoint=point; _tracking=YES; _held=NO; [_holdTimer invalidate]; __weak AbletonRecordControl *weakSelf=self; _holdTimer=[NSTimer scheduledTimerWithTimeInterval:.65 repeats:NO block:^(NSTimer *timer){ AbletonRecordControl *strongSelf=weakSelf; if(!strongSelf) return; strongSelf->_held=YES; if(strongSelf.action) strongSelf.action(@"options"); }]; }
- (void)moveAt:(NSPoint)point { if(!_tracking || _held) return; CGFloat dx=point.x-_startPoint.x; if(fabs(dx)>=16) { [_holdTimer invalidate]; if(self.action) self.action(dx>0 ? @"record-on" : @"record-off"); _tracking=NO; } }
- (void)endAt:(NSPoint)point { if(!_tracking) return; [_holdTimer invalidate]; if(!_held && self.action) { CGFloat dx=point.x-_startPoint.x; self.action(fabs(dx)>=16 ? (dx>0 ? @"record-on" : @"record-off") : @"toggle"); } _tracking=NO; _held=NO; }
- (void)mouseDown:(NSEvent *)event { [self beginAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseDragged:(NSEvent *)event { [self moveAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseUp:(NSEvent *)event { [self endAt:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)touchesBeganWithEvent:(NSEvent *)event { NSTouch *touch=[event touchesMatchingPhase:NSTouchPhaseBegan inView:self].anyObject; if(touch) [self beginAt:[touch locationInView:self]]; }
- (void)touchesMovedWithEvent:(NSEvent *)event { NSTouch *touch=[event touchesMatchingPhase:NSTouchPhaseTouching inView:self].anyObject; if(touch) [self moveAt:[touch locationInView:self]]; }
- (void)touchesEndedWithEvent:(NSEvent *)event { [self endAt:NSZeroPoint]; }
- (void)touchesCancelledWithEvent:(NSEvent *)event { [_holdTimer invalidate]; _tracking=NO; _held=NO; }
@end
