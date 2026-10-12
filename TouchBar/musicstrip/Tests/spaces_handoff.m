#define main ThreeEApplicationMain
#import "../Source/main.m"
#undef main
@interface TestSpacesPanel : DockPanel
@property NSInteger restores;
@end
@implementation TestSpacesPanel
- (void)restorePresentation { self.restores++; }
@end
@interface TestSpacesDelegate : AppDelegate
@property NSMutableArray *commands;
@property BOOL requestedNative;
@property BOOL simulatedNativeVisible;
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
- (BOOL)nativeSpacesPickerVisible { return self.simulatedNativeVisible; }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    TestSpacesDelegate *delegate=[TestSpacesDelegate new];
    TestSpacesPanel *panel=[TestSpacesPanel new];
    delegate.dockPanel=panel; delegate.commands=[NSMutableArray new];
    delegate.midiRequested=YES;
    [delegate openDesktops];
    NSCAssert([delegate.commands isEqual:@[@"SHOW"]] && delegate.requestedNative && !delegate.midiRequested,
              @"Keep apps underneath native Spaces instead of clearing both bars to black");
    NSUInteger generation=delegate.nativeSpacesGeneration;
    [delegate checkNativeSpaces:generation remaining:0 didShow:NO];
    NSCAssert(!delegate.nativeSpacesActive && panel.restores==1,@"Failed native launch must restore apps, not stay black");
    [delegate openDesktops];
    generation=delegate.nativeSpacesGeneration;
    [delegate checkNativeSpaces:generation remaining:5 didShow:YES];
    NSCAssert(!delegate.nativeSpacesActive && panel.restores==2,@"Native dismissal returns to app row");
    [delegate openDesktops];
    generation=delegate.nativeSpacesGeneration;
    delegate.nativeSpacesGeneration++;
    [delegate checkNativeSpaces:generation remaining:0 didShow:NO];
    NSCAssert(panel.restores==2,@"Stale callbacks cannot overwrite a newer presentation");
    delegate.midiRequested=YES;
    [delegate checkNativeSpaces:delegate.nativeSpacesGeneration remaining:0 didShow:NO];
    NSCAssert(!delegate.nativeSpacesActive && panel.restores==2,@"MIDI navigation cancels recovery without replacing MIDI");
    puts("Passed native Spaces timeout/dismissal recovery, stale callback and MIDI navigation guards. No native UI or keyboard events sent.");
} return 0; }
