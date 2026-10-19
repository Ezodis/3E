#import "../../../Shared/PhoneControl/MacHost/PhoneControlMac.h"
@interface FakePhoneTask : NSTask
@property BOOL alive;
@end
@implementation FakePhoneTask
- (BOOL)isRunning{return self.alive;}
@end
@interface TestPhoneController : ThreeEPhoneController
@property NSInteger starts;
@property NSMutableArray *commands;
@end
@implementation TestPhoneController
- (void)startReceiver {self.starts++;self.receiverWanted=YES;}
- (void)send:(NSString *)line {[self.commands addObject:line];}
@end
int main(void){@autoreleasepool{
    TestPhoneController *phone=[TestPhoneController new];phone.commands=[NSMutableArray new];
    FakePhoneTask *task=[FakePhoneTask new];task.alive=YES;phone.task=task;phone.receiverWanted=YES;
    // Exercise the actual native-to-phone JSON, not just the playback tracker.
    phone.appsIcon=@"";
    for(NSNumber *state in @[@1,@0,@(-1)]) {
        [phone updateArtwork:nil playing:state.integerValue stop:NO];
        NSDictionary *message=[NSJSONSerialization JSONObjectWithData:[phone.commands.lastObject dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        id playing=message[@"controls"][@"media"][@"playing"];
        if(state.integerValue<0) NSCAssert(playing==NSNull.null,@"Unknown playback stays null");
        else {
            NSCAssert(CFGetTypeID((__bridge CFTypeRef)playing)==CFBooleanGetTypeID(),@"Phone requires JSON booleans; numeric 1 fails JavaScript's strict true check");
            NSCAssert([playing boolValue]==(state.integerValue==1),@"Playing maps to Pause and paused maps to Play");
        }
    }
    [phone willSleep:nil];NSCAssert(phone.sleeping&&[phone.commands.lastObject isEqual:@"SLEEP"],@"Sleep releases the receiver while preserving intent");
    [phone didWake:nil];NSCAssert(!phone.sleeping&&[phone.commands.lastObject isEqual:@"WAKE"]&&phone.starts==0,@"Wake rebinds a living receiver instead of launching duplicates");
    task.alive=NO;[phone receiverExited:task];NSCAssert(phone.retryTimer!=nil,@"An unexpected exit schedules recovery");
    [phone.retryTimer fire];NSCAssert(phone.starts==1,@"Recovery relaunches the enabled module");
    [phone willSleep:nil];[phone didWake:nil];NSCAssert(phone.starts==2,@"Wake launches a missing child");
    [phone scheduleRecovery];[phone stop];NSCAssert(!phone.receiverWanted&&phone.retryTimer==nil,@"Explicit stop cancels recovery");
    [phone didWake:nil];NSCAssert(phone.starts==2,@"Wake never enables a module the user turned off");
    puts("Passed Mac sleep/wake, unexpected-exit recovery and explicit-stop behavior. No receiver or input launched.");
}return 0;}
