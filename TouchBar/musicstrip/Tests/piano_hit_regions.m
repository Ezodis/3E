#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface HitTestKey : NSObject
@property NSInteger pitch;
@property NSBezierPath *drawPath;
@property NSBezierPath *touchPath;
@end
@implementation HitTestKey
@end
@interface HitTestPiano : NSView
@property NSArray *pianoKeys;
@end
@implementation HitTestPiano
@end
int main(void) { @autoreleasepool {
    HitTestPiano *piano=[[HitTestPiano alloc] initWithFrame:NSMakeRect(0,0,92,30)];
    NSMutableArray *keys=[NSMutableArray new];
    NSArray *rects=@[[NSValue valueWithRect:NSMakeRect(14,0,20,30)],
                    [NSValue valueWithRect:NSMakeRect(28,10,12,35)],
                    [NSValue valueWithRect:NSMakeRect(36,0,20,30)],
                    [NSValue valueWithRect:NSMakeRect(50,10,12,35)],
                    [NSValue valueWithRect:NSMakeRect(58,0,20,30)]];
    for(NSUInteger i=0;i<rects.count;i++) {
        HitTestKey *key=[HitTestKey new]; key.pitch=i;
        key.drawPath=[NSBezierPath bezierPathWithRect:[rects[i] rectValue]];
        key.touchPath=[NSBezierPath bezierPathWithRect:NSMakeRect(NSMinX(key.drawPath.bounds),0,NSWidth(key.drawPath.bounds),30)];
        [keys addObject:key];
    }
    piano.pianoKeys=keys;
    NSArray *drawing=[keys valueForKey:@"drawPath"];
    for(NSInteger repeat=0;repeat<3;repeat++) {
        SetPianoHitRegions(piano);
        for(NSNumber *height in @[@1,@7.5,@14.9]) for(CGFloat x=14.371;x<78;x+=.37) {
            NSInteger hits=0;
            for(HitTestKey *key in keys) if([key.touchPath containsPoint:NSMakePoint(x,height.doubleValue)]) {
                hits++; NSCAssert(!PianoKeyIsBlack(key),@"Every lower-half touch must be a white key, even beneath black keys");
            }
            NSCAssert(hits==1,@"The lower white-key lane has no overlap or gutter gaps");
        }
        for(CGFloat x=14.371;x<78;x+=.37) {
            NSInteger hits=0; BOOL black=NO;
            for(HitTestKey *key in keys) if([key.touchPath containsPoint:NSMakePoint(x,23)]) { hits++; black=PianoKeyIsBlack(key); }
            BOOL expected=(x>28 && x<40) || (x>50 && x<62);
            NSCAssert(hits==1 && black==expected,@"The upper half preserves black keys without competing white hits");
        }
        for(HitTestKey *key in keys) NSCAssert(![key.touchPath containsPoint:NSMakePoint(7,8)] && ![key.touchPath containsPoint:NSMakePoint(85,23)],@"Piano keys never consume the edge arrows");
        NSCAssert([drawing isEqual:[keys valueForKey:@"drawPath"]],@"Hit-box changes leave drawing geometry untouched");
    }
    puts("Passed upper-half black hits, continuous lower-half white hits, edge exclusion and repeat-safe unchanged drawing.");
} return 0; }
