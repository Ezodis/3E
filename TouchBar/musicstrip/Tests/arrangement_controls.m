#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:480 pixelsHigh:240 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [NSColor.blackColor setFill]; NSRectFill(NSMakeRect(0,0,480,240));
    NSAffineTransform *scale=[NSAffineTransform transform]; [scale scaleBy:2]; [scale concat];
    for(NSInteger row=0;row<4;row++) {
        StripPerformanceButton *loop=[[StripPerformanceButton alloc] initWithFrame:NSMakeRect(0,0,86,30)];
        loop.identifier=@"loop"; loop.title=@"4 bar"; loop.enabled=YES;
        loop.loopActive=row>0; loop.punchInActive=row>1; loop.punchOutActive=row>2;
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *position=[NSAffineTransform transform]; [position translateXBy:0 yBy:row*30]; [position concat];
        [loop drawRect:loop.bounds];
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-arrangement-controls.png" atomically:YES];
    puts("ARRANGEMENT_LOOP_PUNCH_STATES_RENDERED_WITHOUT_LIVE_COMMANDS");
} return 0; }
