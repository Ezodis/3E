#import "../Source/CarView.h"
@interface CarMenuTarget : NSObject
@property NSUInteger toggles;
@property NSUInteger mirrors;
@end
@implementation CarMenuTarget
- (void)toggleCarView:(id)sender{self.toggles++;}
- (void)toggleCarMirror:(id)sender{self.mirrors++;}
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    CarMenuTarget *target=[CarMenuTarget new];NSMenuItem *item=ThreeECarViewMenu(target,NO);ThreeECarMenuRow *row=(id)item.view;
    NSCAssert([item.title isEqual:@"Car View"] && !item.submenu,@"Car View stays in one menu row");
    for(NSNumber *width in @[@230,@360]){row.frame=NSMakeRect(0,0,width.doubleValue,26);[row layout];NSCAssert(NSMaxX(row.toggle.frame)<NSMinX(row.mirror.frame)&&NSMaxX(row.mirror.frame)==width.doubleValue-9,@"Reverse button stays at the right without overlapping the main target");}
    [row.toggle performClick:nil];NSCAssert(target.toggles==1&&target.mirrors==0,@"Main target toggles only Car View");
    [row.mirror performClick:nil];NSCAssert(target.toggles==1&&target.mirrors==1,@"Reverse target toggles only mirroring");
    ThreeECarMenuUpdate(item,YES,YES,NO,@"Mirror is on.");NSCAssert(item.state==NSControlStateValueOn&&row.mirror.state==NSControlStateValueOn&&row.mirror.enabled,@"Both independent states are visible");
    ThreeECarMenuUpdate(item,YES,NO,YES,nil);NSCAssert(!row.mirror.enabled&&item.state==NSControlStateValueOn,@"Pending mirror does not disable Car View's off control");
    ThreeECarMenuUpdate(item,NO,NO,NO,nil);NSCAssert(item.state==NSControlStateValueOff&&row.mirror.state==NSControlStateValueOff,@"Restored mode clears both checks");
    // Multiple screen origins, corners and subpixel positions. Reflection must
    // put the visible cursor exactly over the original native input target.
    for(NSValue *value in @[[NSValue valueWithRect:NSMakeRect(0,0,1440,900)],[NSValue valueWithRect:NSMakeRect(-1920,120,1920,1080)]]) {
        NSRect screen=value.rectValue;
        for(NSValue *target in @[[NSValue valueWithPoint:screen.origin],[NSValue valueWithPoint:NSMakePoint(NSMaxX(screen)-1,NSMaxY(screen)-1)],[NSValue valueWithPoint:NSMakePoint(NSMinX(screen)+123.25,NSMinY(screen)+456.75)]]) {
            NSPoint point=target.pointValue;
            NSCAssert(NSEqualPoints(ThreeECarPresentedPoint(point,screen,NO),point),@"Regular view is identity");
            NSCAssert(NSEqualPoints(ThreeECarPresentedPoint(ThreeECarPresentedPoint(point,screen,YES),screen,YES),point),@"Image and neon cursor match a native/phone click through reflection");
        }
    }
    NSCAssert(ThreeECarModeScore(1080,675,2160,60,1440,900,60)<ThreeECarModeScore(1280,800,2560,60,1440,900,60),@"Prefer a useful size increase");
    NSCAssert(ThreeECarModeScore(1080,675,2160,60,1440,900,60)<ThreeECarModeScore(1080,675,1080,60,1440,900,60),@"Prefer Retina output");
    NSCAssert(ThreeECarModeScore(800,500,1600,60,1440,900,60)==DBL_MAX,@"Do not shrink workspace below usable bounds");
    NSCAssert(ThreeECarModeScore(1280,720,2560,60,1440,900,60)==DBL_MAX,@"Do not distort aspect ratio");
    NSCAssert(ThreeECarModeScore(1440,900,2880,60,1440,900,60)==DBL_MAX,@"Do not select a same-size mode");
    NSCAssert(ThreeECarModeScore(1080,675,2160,30,1440,900,60)==DBL_MAX,@"Reject slow display modes");
    ThreeECarOverlay *window=ThreeECarOverlayWindow(NSMakeRect(0,0,100,100),1000);
    NSCAssert(window.ignoresMouseEvents && !window.canBecomeKeyWindow && !window.canBecomeMainWindow,@"Mirror and pointer cannot steal clicks, drags or focus");
    [window close];
    ThreeECarView *car=[ThreeECarView new];
    NSCAssert(!car.enabled && !car.mirrored && !car.pointerTimer && !car.originalMode,@"Installing/launching never changes the display");
    CGDisplayModeRef current=CGDisplayCopyDisplayMode(CGMainDisplayID());
    car.display=CGMainDisplayID();car.expectedWidth=CGDisplayModeGetWidth(current);car.expectedHeight=CGDisplayModeGetHeight(current);car.enabled=YES;
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidChangeScreenParametersNotification object:nil];
    NSCAssert(car.enabled,@"Late notifications for our applied size must not switch Car View off");
    car.enabled=NO;if(current)CFRelease(current);
    [car stop];[car stop];
    NSCAssert(!car.cursorHidden&&!car.exitKey&&!car.keyHandler&&!car.originalMode,@"Repeated cleanup owns no hide count, mode or shortcut");
    puts("Passed Car View reflection/input coordinates, display selection, transparent overlays and idempotent cleanup. No display changes or posted input.");
}return 0;}
