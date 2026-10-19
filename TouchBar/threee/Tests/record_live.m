// Explicit opt-in integration diagnostic. Does not create a tray item/app copy.
#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=2) { fprintf(stderr,"Usage: record_live record|arm-on|arm-off|punch-in|punch-out|overdub|loop|click|quantization\n"); return 2; }
        NSApplication *app=NSApplication.sharedApplication;
        app.activationPolicy=NSApplicationActivationPolicyProhibited;
        StripRecordController *controller=[StripRecordController new];
        NSCAssert([controller connected],@"Live control surface must be connected before testing");
        NSString *action=[NSString stringWithUTF8String:argv[1]];
        if([@[@"record",@"arm-on",@"arm-off"] containsObject:action]) {
            PianoTestTouch *touch=[PianoTestTouch new]; touch.identity=NSUUID.UUID;
            touch.point=NSMakePoint(22,15);
            PianoTestEvent *event=[PianoTestEvent new]; event.touch=touch; event.phase=NSTouchPhaseBegan;
            [controller.button touchesBeganWithEvent:(NSEvent *)event];
            touch.point=NSMakePoint([action isEqual:@"arm-on"] ? 50 : [action isEqual:@"arm-off"] ? -5 : 22,15);
            event.phase=NSTouchPhaseMoved; [controller.button touchesMovedWithEvent:(NSEvent *)event];
            event.phase=NSTouchPhaseEnded; [controller.button touchesEndedWithEvent:(NSEvent *)event];
        } else [controller send:action];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
        while(controller.pending && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        [controller refresh];
        NSCAssert(!controller.pending && !controller.messageUntil,@"Live must acknowledge the real gesture without error");
        NSData *data=[NSJSONSerialization dataWithJSONObject:controller.state options:0 error:nil];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
