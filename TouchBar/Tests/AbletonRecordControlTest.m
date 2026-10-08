#import <AppKit/AppKit.h>
#import "../Strip3/AbletonRecordControl.h"

@interface AbletonRecordControl (TestOnly)
- (void)beginAt:(NSPoint)point;
- (void)moveAt:(NSPoint)point;
- (void)endAt:(NSPoint)point;
@end

int main(void) {
    @autoreleasepool {
        AbletonRecordControl *control=[[AbletonRecordControl alloc] initWithFrame:NSMakeRect(0,0,55,30)]; control.abletonActive=YES;
        NSMutableArray *actions=[NSMutableArray array]; control.action=^(NSString *action){ [actions addObject:action]; };
        [control beginAt:NSMakePoint(10,15)]; [control moveAt:NSMakePoint(35,15)];
        NSCAssert([actions.lastObject isEqualToString:@"record-on"], @"Right swipe must enable recording");
        [control beginAt:NSMakePoint(35,15)]; [control moveAt:NSMakePoint(10,15)];
        NSCAssert([actions.lastObject isEqualToString:@"record-off"], @"Left swipe must disable recording");
        [control beginAt:NSMakePoint(20,15)]; [control endAt:NSMakePoint(20,15)];
        NSCAssert([actions.lastObject isEqualToString:@"toggle"], @"Tap must toggle recording");
        puts("Passed Ableton record gesture test");
    }
    return 0;
}
