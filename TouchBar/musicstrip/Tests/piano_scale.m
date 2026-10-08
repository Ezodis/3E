#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(void) {
    @autoreleasepool {
        NSDictionary *major=@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@0,@"scale_intervals":@[@0,@2,@4,@5,@7,@9,@11]};
        NSUInteger mask=ScaleMaskForState(major,YES);
        for(NSInteger note=0;note<128;note++) {
            BOOL expected=[@[@0,@2,@4,@5,@7,@9,@11] containsObject:@(note%12)];
            NSCAssert(NoteInLiveScale(note,mask)==expected,@"C Major highlighting must be correct at every MIDI octave");
        }
        NSMutableDictionary *minor=major.mutableCopy; minor[@"root_note"]=@6; minor[@"scale_intervals"]=@[@0,@2,@3,@5,@7,@8,@10];
        mask=ScaleMaskForState(minor,YES);
        for(NSInteger note=0;note<128;note++) NSCAssert((NoteInLiveScale(note,mask)==[@[@1,@2,@4,@6,@8,@9,@11] containsObject:@(note%12)]),@"F-sharp Minor must include the correct black and white keys");
        NSCAssert(!ScaleMaskForState(minor,NO),@"Disconnected or stale state must not highlight keys");
        minor[@"scale_mode"]=@NO; NSCAssert(!ScaleMaskForState(minor,YES),@"Scale Mode off must restore the normal piano");
        minor[@"scale_mode"]=@YES; minor[@"root_note"]=@12; NSCAssert(!ScaleMaskForState(minor,YES),@"Malformed state cannot invent a scale");
        NSCAssert(!ScaleMaskForState(@{},YES),@"Older scripts without scale feedback must preserve the normal piano");
        puts("Passed C Major and F-sharp Minor across all MIDI octaves, scale-off, stale/disconnected and malformed-state handling. No MIDI changed.");
    }
    return 0;
}
