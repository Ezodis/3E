#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <objc/message.h>
int main(int argc,char **argv) { @autoreleasepool {
    NSCAssert(argc==2,@"Supply the compiled gesture module path");
    NSCAssert(dlopen(argv[1],RTLD_NOW|RTLD_LOCAL),@"The Swift gesture engine must load directly in the host process");
    Class cls=NSClassFromString(@"ThreeEGestures");
    for(NSString *name in @[@"start",@"stop",@"running"]) NSCAssert([cls respondsToSelector:NSSelectorFromString(name)],@"Expose the in-process lifecycle API");
    NSCAssert(!((BOOL(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"running")),@"Loading alone must not start gestures or request permissions");
    for(int i=0;i<3;i++) ((void(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"stop"));
    NSCAssert(!((BOOL(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"running")),@"Disable/quit is idempotent");
    puts("Passed Swift/Objective-C in-process module loading and idempotent cleanup. No keyboard events or permissions requested.");
} return 0; }
