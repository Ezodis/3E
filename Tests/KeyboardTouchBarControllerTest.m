#import <AppKit/AppKit.h>
#import "../Strip3/KeyboardTouchBarController.h"

int main(void) {
    @autoreleasepool {
        KeyboardTouchBarController *controller=[KeyboardTouchBarController new];
        NSCAssert(controller.touchBar.defaultItemIdentifiers.count==4, @"Touch Bar must contain record plus three keyboard items");
        NSCAssert(controller.touchBar.customizationAllowedItemIdentifiers.count==4, @"Record and all three keyboards must be customizable");
        NSCAssert([controller.touchBar.defaultItemIdentifiers[0] isEqualToString:@"com.strip3.ableton.record"], @"Ableton record identifier must be stable");
        NSCAssert([controller.touchBar.defaultItemIdentifiers[1] isEqualToString:@"com.strip3.keyboard.1"], @"Keyboard 1 identifier must be stable");
        NSCAssert([controller.touchBar.defaultItemIdentifiers[2] isEqualToString:@"com.strip3.keyboard.2"], @"Keyboard 2 identifier must be stable");
        NSCAssert([controller.touchBar.defaultItemIdentifiers[3] isEqualToString:@"com.strip3.keyboard.3"], @"Keyboard 3 identifier must be stable");
        for(NSUInteger index=1;index<4;index++) {
            NSTouchBarItem *item=[controller touchBar:controller.touchBar makeItemForIdentifier:controller.touchBar.defaultItemIdentifiers[index]];
            NSCAssert(item != nil, @"Every keyboard identifier must create a Touch Bar item");
            NSCAssert([item isKindOfClass:NSCustomTouchBarItem.class], @"Keyboard items must be customizable Touch Bar items");
        }
        puts("Passed three-keyboard Touch Bar structure test");
    }
    return 0;
}
