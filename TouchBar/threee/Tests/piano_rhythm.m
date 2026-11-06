#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface RhythmPiano : NSView
@property NSNumber *channelNumber;
@end
@implementation RhythmPiano
@end
@interface RhythmController : StripRecordController
@property NSDictionary *sent;
@end
@implementation RhythmController
- (BOOL)connected { return YES; }
- (void)send:(NSString *)action payload:(NSDictionary *)payload { NSCAssert([action isEqual:@"piano-mode-set"],@"Dedicated command"); self.sent=payload; }
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    RhythmPiano *piano=[RhythmPiano new]; piano.channelNumber=@2; expandedPianoView=piano;
    RhythmController *controller=[RhythmController new]; [controller.pollTimer invalidate]; recordController=controller;
    pianoRhythmButton=[[PianoRhythmButton alloc] initWithFrame:NSMakeRect(0,0,32,30)]; pianoRhythmButton.octaveControl=YES;
    for(NSInteger mode=0;mode<3;mode++) {
        controller.state=@{@"piano_modes":@{@"2":@(mode)}}; UpdatePianoRhythmButton();
        NSCAssert(pianoRhythmButton.enabled && pianoRhythmButton.image,@"Available mode has an icon");
        [pianoRhythmButton beginAt:NSMakePoint(16,15) identity:nil]; [pianoRhythmButton finishAt:NSMakePoint(16,15)];
        NSCAssert([controller.sent[@"mode"] integerValue]==(mode+1)%3 && [controller.sent[@"channel"] isEqual:@"2"],@"Tap cycles the correct piano");
        NSCAssert([controller.state[@"piano_modes"][@"2"] integerValue]==mode,@"Wait for acknowledgement before displaying a new mode");
    }
    controller.state=@{@"piano_modes":@{}}; UpdatePianoRhythmButton();
    NSCAssert(!pianoRhythmButton.enabled && ![pianoRhythmButton accessibilityPerformPress],@"Missing rack cannot send a command");
    puts("Piano mode icons, tap cycling, acknowledged state and unavailable rack passed.");
} return 0; }
