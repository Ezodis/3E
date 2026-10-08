#import <Foundation/Foundation.h>
#import "../Strip3/KeyboardConfiguration.h"

int main(void) {
    @autoreleasepool {
        KeyboardConfigurationStore *store=[KeyboardConfigurationStore new];
        [store restore];
        NSCAssert(store.keyboards.count==3, @"There must always be three keyboard slots");
        NSCAssert(store.keyboards[0].midiChannel!=store.keyboards[1].midiChannel && store.keyboards[1].midiChannel!=store.keyboards[2].midiChannel, @"Keyboard mappings must be independent");
        KeyboardConfiguration *updated=[store.keyboards[1] copy]; updated.baseNote=36; updated.transpose=7; [store setConfiguration:updated atIndex:1];
        updated.octaveCount=3; updated.velocity=80; [store setConfiguration:updated atIndex:1];
        NSCAssert([store configurationAtIndex:1].baseNote==36 && [store configurationAtIndex:1].transpose==7 && [store configurationAtIndex:1].octaveCount==3 && [store configurationAtIndex:1].velocity==80, @"Keyboard 2 mapping must persist independently");
        puts("Passed three-keyboard configuration persistence test");
    }
    return 0;
}
