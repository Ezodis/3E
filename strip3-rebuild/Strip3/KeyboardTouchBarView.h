#import <AppKit/AppKit.h>
#import "KeyboardConfiguration.h"
#import "MidiOutput.h"

@interface KeyboardTouchBarView : NSView
@property(nonatomic, copy) KeyboardConfiguration *configuration;
@property(nonatomic, strong) Strip3MidiOutput *midiOutput;
@end
