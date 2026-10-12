#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main
@interface TestSpacesDelegate : AppDelegate
@property NSMutableArray *commands;
@property BOOL requestedNative;
@end
@implementation TestSpacesDelegate
- (void)sendApps:(NSString *)command {
    [self.commands addObject:command]; self.dockPanel.visible=YES;
}
- (void)sendMidi:(NSString *)command { NSCAssert(NO,@"Do not clear the underlying bar directly"); }
- (void)presentNativeSpacesWhenReady:(NSInteger)attempts {
    NSCAssert(self.appsRequested && self.dockPanel.visible && attempts>0,@"A real app row must exist before native handoff");
    self.requestedNative=YES;
}
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    TestSpacesDelegate *delegate=[TestSpacesDelegate new];
    delegate.dockPanel=[DockPanel new]; delegate.commands=[NSMutableArray new];
    delegate.midiRequested=YES;
    [delegate openDesktops];
    NSCAssert([delegate.commands isEqual:@[@"SHOW"]] && delegate.requestedNative && !delegate.midiRequested,
              @"Keep apps underneath native Spaces instead of clearing both bars to black");
    puts("Passed native Spaces handoff with preserved app-row fallback. No native UI or keyboard events sent.");
} return 0; }
