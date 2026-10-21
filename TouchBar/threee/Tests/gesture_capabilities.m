#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/message.h>
#import <dlfcn.h>
static BOOL trusted,posting,canStart,running;
static BOOL moduleInstalled=YES;
static BOOL StripHasModule(NSString *module) { return moduleInstalled; }
static BOOL AccessibilityTrusted(BOOL prompt) { return trusted; }
static BOOL TestPosting(void) { return posting; }
#define CGPreflightPostEventAccess TestPosting
#define STRIP_COMBINED_TOUCHTAB 1
#import "../Source/TouchTabIntegration.h"
@interface TestGestureEngine : NSObject
+ (BOOL)start;
+ (BOOL)running;
+ (void)stop;
@end
@implementation TestGestureEngine
+ (BOOL)start { running=canStart; return running; }
+ (BOOL)running { return running; }
+ (void)stop { running=NO; }
@end
int main(void) { @autoreleasepool {
    StripGestureClass=TestGestureEngine.class;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"TouchTabGesturesEnabled"];
    trusted=NO; posting=YES; canStart=YES;
    NSCAssert([StripRefreshGestures() isEqual:@"on"],@"Actual gesture capabilities must not be blocked by an unrelated AX result");
    posting=NO;
    NSCAssert([StripRefreshGestures() isEqual:@"permission"] && !running,@"Never show a working check without permission to post events");
    trusted=YES; posting=YES; canStart=NO;
    NSCAssert([StripRefreshGestures() isEqual:@"unavailable"],@"Approval alone cannot claim the listener is working");
    canStart=YES;
    NSCAssert([StripRefreshGestures() isEqual:@"on"],@"Approval recovery starts the actual listener");
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"TouchTabGesturesEnabled"];
    NSCAssert([StripRefreshGestures() isEqual:@"off"] && !running,@"Disable shuts the listener down");
    moduleInstalled=NO; running=YES;
    NSCAssert([StripRefreshGestures() isEqual:@"not installed"] && !running,@"Removed modules cannot restart");
    puts("Passed gesture capability checks, permission recovery and disabled cleanup. No real event taps or keyboard events.");
} return 0; }
