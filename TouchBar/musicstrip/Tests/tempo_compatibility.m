#define STRIP3_RECORD_TESTING 1
#import "../Source/MidiBridge.m"
@interface TempoTestController : StripRecordController
@end
@implementation TempoTestController
- (BOOL)connected { return YES; }
@end
static void SaveJSON(NSDictionary *value,NSString *path) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    NSCAssert([data writeToFile:path atomically:YES],@"Write isolated test data");
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:[directory stringByAppendingPathComponent:@"responses"] withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("STRIP_RECORD_TEST_DIRECTORY",directory.UTF8String,1);
    NSMutableDictionary *state=[@{@"performance":@1,@"session_id":@"test-only",@"tempo":@120.93} mutableCopy];
    NSString *statePath=[directory stringByAppendingPathComponent:@"state.json"];
    SaveJSON(state,statePath);
    TempoTestController *controller=[TempoTestController new]; [controller.pollTimer invalidate];
    [controller setTempoFromDrag:130.93];
    NSCAssert(controller.legacyTempoTokens.count==10,@"A ten-BPM drag becomes ten operations in one bounded batch, not a one-BPM gesture");
    [controller setTempoFromDrag:115.93];
    NSCAssert(controller.legacyTempoTokens.count==10 && controller.queuedTempo.doubleValue==115.93,@"Reversal coalesces while the first batch is awaiting Live");
    for(NSInteger iteration=0;iteration<6 && controller.pending;iteration++) {
        double tempo=[state[@"tempo"] doubleValue];
        for(NSString *token in controller.legacyTempoTokens) {
            NSString *name=[token stringByAppendingString:@".json"];
            NSString *path=[[directory stringByAppendingPathComponent:@"commands"] stringByAppendingPathComponent:name];
            NSDictionary *command=RecordJSON(path);
            NSString *action=command[@"action"];
            NSCAssert(![action isEqual:@"tempo-set"] && [command[@"session"] isEqual:@"test-only"],@"Older scripts receive only supported actions scoped to this session");
            double delta=[action hasSuffix:@"fine"] ? .1 : 1;
            tempo=round((tempo+([action containsString:@"down"] ? -delta : delta))*100)/100;
            SaveJSON(@{@"ok":@YES},[[directory stringByAppendingPathComponent:@"responses"] stringByAppendingPathComponent:name]);
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        }
        state[@"tempo"]=@(tempo); SaveJSON(state,statePath); [controller refresh];
    }
    NSCAssert(fabs([state[@"tempo"] doubleValue]-115.93)<.05 && !controller.pending,@"Distance-based reversal reaches its real target without a script reload");
    [controller setTempoFromDrag:500];
    NSCAssert(controller.legacyTempoTokens.count==32,@"Large drags stay bounded per acknowledgment");
    state[@"session_id"]=@"different-session"; SaveJSON(state,statePath); [controller refresh];
    NSCAssert(!controller.queuedTempo,@"Targets must never continue into a different Live session");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil]; unsetenv("STRIP_RECORD_TEST_DIRECTORY");
    puts("PROPORTIONAL_LEGACY_TEMPO_BATCHES_REVERSAL_LIMIT_AND_SESSION_TESTS_PASSED_NO_LIVE_COMMANDS");
} return 0; }
