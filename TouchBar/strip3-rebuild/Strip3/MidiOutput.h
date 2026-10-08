#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

@interface Strip3MidiOutput : NSObject
- (void)noteOn:(NSInteger)note velocity:(NSInteger)velocity channel:(NSInteger)channel;
- (void)noteOff:(NSInteger)note channel:(NSInteger)channel;
@end
