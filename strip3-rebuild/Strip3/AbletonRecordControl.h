#import <AppKit/AppKit.h>

typedef void (^Strip3AbletonRecordAction)(NSString *action);

/// Dedicated Ableton record control. Tap toggles recording; horizontal
/// swipes explicitly enable/disable it; holding opens recording options.
@interface AbletonRecordControl : NSView
@property(nonatomic) BOOL abletonActive;
@property(nonatomic) BOOL recording;
@property(nonatomic,copy) Strip3AbletonRecordAction action;
@end
