#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(void) {
    @autoreleasepool {
        NSDictionary *major=@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@0,@"scale_intervals":@[@0,@2,@4,@5,@7,@9,@11]};
        NSUInteger mask=ScaleMaskForState(major,YES);
        UpdateLiveScale(major,YES);
        NSCAssert([ScaleDegreeForNote(60) isEqual:@"I"] && [ScaleDegreeForNote(64) isEqual:@"iii"] && !ScaleDegreeForNote(61),@"Only actual scale notes have degrees with the correct triad quality");
        NSArray *majorDegrees=@[@"I",@"ii",@"iii",@"IV",@"V",@"vi",@"vii°"];
        for(NSUInteger i=0;i<7;i++) NSCAssert([ScaleDegreeForNote([major[@"scale_intervals"][i] integerValue]+60) isEqual:majorDegrees[i]],@"Major-scale triads require major, minor and diminished labels");
        NSDictionary *aMinor=@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@9,@"scale_intervals":@[@0,@2,@3,@5,@7,@8,@10,@12]};
        UpdateLiveScale(aMinor,YES);
        NSCAssert(liveScaleMask==mask && [ScaleDegreeForNote(60) isEqual:@"III"] && [ScaleDegreeForNote(69) isEqual:@"i"],@"Relative scales share colors but must update their degrees; octave duplicates must not relabel the root");
        NSDictionary *harmonic=@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@9,@"scale_intervals":@[@0,@2,@3,@5,@7,@8,@11]};
        UpdateLiveScale(harmonic,YES);
        NSArray *harmonicDegrees=@[@"i",@"ii°",@"III+",@"iv",@"V",@"VI",@"vii°"];
        for(NSUInteger i=0;i<7;i++) NSCAssert([ScaleDegreeForNote([harmonic[@"scale_intervals"][i] integerValue]+57) isEqual:harmonicDegrees[i]],@"Harmonic minor must include augmented III, major V and diminished leading-tone triads");
        UpdateLiveScale(@{@"scale_supported":@YES,@"scale_mode":@YES,@"root_note":@0,@"scale_intervals":@[@0,@2,@4,@7,@9]},YES);
        NSCAssert([ScaleDegreeForNote(64) isEqual:@"III"],@"Non-diatonic scales retain neutral labels rather than inventing triads");
        NSBezierPath *key=[NSBezierPath bezierPathWithRect:NSMakeRect(0,0,30,30)];
        NSBezierPath *exposed=[NSBezierPath bezierPathWithRect:NSMakeRect(5,0,12,30)];
        NSRect label=PianoDegreeLabelRegion(key.bounds,key,exposed,NO);
        NSCAssert(fabs(label.origin.x-5)<=.5 && fabs(label.size.width-12)<=1 && NSMaxY(label)==30,@"White-key numerals use the exposed upper stem without shifting their top alignment (allow path-edge sampling tolerance)");
        NSView *first=[NSView new],*second=[NSView new],*replacement=[NSView new];
        SetPianoShowsDegrees(first,YES); TransferPianoInstance(first,replacement);
        NSCAssert(PianoShowsDegrees(first) && PianoShowsDegrees(replacement) && !PianoShowsDegrees(second),@"Degree display is independent and survives octave replacement");
        UpdateLiveScale(@{},NO); NSCAssert(!ScaleDegreeForNote(60),@"Disconnected feedback clears degrees");
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
