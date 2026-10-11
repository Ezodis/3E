#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <float.h>
static NSString *postedName;
static BOOL deliveredImmediately;
@interface TestSpacesNotificationCenter : NSObject
+ (instancetype)defaultCenter;
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)info deliverImmediately:(BOOL)immediate;
@end
@implementation TestSpacesNotificationCenter
+ (instancetype)defaultCenter { static id center; if(!center) center=[self new]; return center; }
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)info deliverImmediately:(BOOL)immediate {
    NSCAssert(!object && !info,@"Native launch request has no synthetic desktop selection payload");
    postedName=name; deliveredImmediately=immediate;
}
@end
#define NSDistributedNotificationCenter TestSpacesNotificationCenter
#import "../Source/DesktopSupport.h"
int main(void) { @autoreleasepool {
    ShowNativeSpacesPicker();
    NSCAssert([postedName isEqual:@"com.apple.SpacesTouchBarAgent.showPopover"] && deliveredImmediately,
              @"Use Apple's registered Spaces picker event, not on-screen Mission Control");
    puts("Passed native Spaces launch-notification routing. No UI, desktop switches or keyboard events triggered.");
} return 0; }
