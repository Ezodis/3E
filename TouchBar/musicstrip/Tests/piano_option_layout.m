#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:176 pixelsHigh:180 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSAffineTransform *scale=[NSAffineTransform transform]; [scale scaleBy:2]; [scale concat];
    for(NSInteger i=0;i<3;i++) {
        PianoConfigButton *mode=[[PianoConfigButton alloc] initWithFrame:NSMakeRect(0,0,44,30)];
        mode.joinedEdge=1; mode.stackedCaption=@[@"GLISS",@"HOLD",@"BEND"][i];
        mode.image=[NSImage imageWithSystemSymbolName:@[@"pianokeys",@"hand.raised.fill",@"waveform"][i] accessibilityDescription:nil];
        MidiNavigationButton *octave=[[MidiNavigationButton alloc] initWithFrame:NSMakeRect(44,0,44,30)];
        octave.joinedEdge=2; octave.stackedCaption=@"OCT"; octave.title=@[@"2",@"5",@"10"][i]; octave.image=nil;
        NSCAssert(mode.image && NSMaxX(mode.frame)==NSMinX(octave.frame),@"Mode icon exists and joined halves have no gap");
        [NSGraphicsContext saveGraphicsState]; NSAffineTransform *row=[NSAffineTransform transform]; [row translateXBy:0 yBy:i*30]; [row concat];
        [mode drawRect:mode.bounds]; NSAffineTransform *right=[NSAffineTransform transform]; [right translateXBy:44 yBy:0]; [right concat]; [octave drawRect:octave.bounds]; [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-piano-options.png" atomically:YES];
    puts("PIANO_STACKED_OPTIONS_RENDERED");
} return 0; }
