#define main StripApplicationMain
#import "../Source/main.m"
#undef main
@interface ExtensionTestDelegate : AppDelegate
@property NSMutableArray *commands;
@end
@implementation ExtensionTestDelegate
- (void)sendApps:(NSString *)command { [self.commands addObject:[@"APPS " stringByAppendingString:command]]; }
- (void)sendMidi:(NSString *)command { [self.commands addObject:[@"MIDI " stringByAppendingString:command]]; }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyProhibited;
    ExtensionTestDelegate *delegate=[ExtensionTestDelegate new]; delegate.commands=[NSMutableArray new];
    DockLauncher *launcher=[[DockLauncher alloc] initWithFrame:NSMakeRect(0,0,14,30)];
    launcher.performCommand=^(int command){ [delegate appsLauncherCommand:command]; };
    for(NSInteger i=0;i<2;i++) {
        [launcher beginAt:NSMakePoint(7,15) identity:nil]; [launcher moveAt:NSMakePoint(-8,15)]; [launcher fireHold]; [launcher finishAt:NSMakePoint(-8,15)];
    }
    NSCAssert(([delegate.commands isEqual:@[@"MIDI HIDE",@"APPS SHOW",@"MIDI HIDE",@"APPS SHOW"]]),@"Left swipes open explicitly, never toggle closed");
    [delegate.commands removeAllObjects];
    [launcher beginAt:NSMakePoint(7,15) identity:nil]; [launcher moveAt:NSMakePoint(22,15)]; [launcher finishAt:NSMakePoint(22,15)];
    NSCAssert([delegate.commands isEqual:@[@"APPS HIDE"]],@"Right swipe explicitly closes apps without media commands");
    NSMutableArray *pixels=[NSMutableArray new];
    for(NSNumber *open in @[@NO,@YES]) {
        launcher.panelOpen=open.boolValue;
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:14 pixelsHigh:30 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]]; [launcher drawRect:launcher.bounds]; [NSGraphicsContext restoreGraphicsState];
        [pixels addObject:[NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow*rep.pixelsHigh]];
        for(NSInteger y=0;y<30;y++) for(NSInteger x=0;x<14;x++) {
            NSColor *color=[[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            NSCAssert(color.redComponent>=.07 && color.redComponent<=.22 && fabs(color.redComponent-color.greenComponent)<.01,@"Extension has only a neutral fade, no dots, X or bright border");
        }
        CGFloat previous=0;
        for(NSInteger x=0;x<14;x++) {
            CGFloat value=[[[rep colorAtX:x y:15] colorUsingColorSpace:NSColorSpace.sRGBColorSpace] redComponent];
            NSCAssert(value>=previous-.005 && (x==0 || value-previous<.035),@"Arrow-side fade is monotonic with no hard internal seam"); previous=value;
        }
        NSCAssert([[[rep colorAtX:0 y:15] colorUsingColorSpace:NSColorSpace.sRGBColorSpace] redComponent]<.11 && previous>.18,@"Fade blends a dark native edge into the control background");
        if(!open.boolValue) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/3e-apps-extension-fade.png" atomically:YES];
    }
    NSCAssert([pixels[0] isEqual:pixels[1]],@"Invisible extension remains visually identical when open");
    LauncherPairView *pair=[[LauncherPairView alloc] initWithFrame:NSMakeRect(0,0,70,30)]; pair.apps=launcher; pair.music=[[MusicView alloc] initWithFrame:NSZeroRect]; [pair layout];
    NSCAssert(NSMaxX(pair.apps.frame)==NSMinX(pair.music.frame),@"No extra app/music gap");
    puts("APPS_EXTENSION_LEFT_OPEN_RIGHT_CLOSE_AND_BORDERLESS_DRAWING_PASSED");
} return 0; }
