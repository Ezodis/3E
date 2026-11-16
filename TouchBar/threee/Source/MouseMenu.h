// "Mouse…" opens the bundled 3£ Mouse helper (TouchBar/threee/Mouse): gaming-mouse settings for
// every supported mouse (first device: Thunderbird PC205, Shared/PC205/PROTOCOL.md).
// Used by both the base menu (main process) and the full menu (MIDI helper process).
#import <AppKit/AppKit.h>

static NSString *const ThreeEMouseMenuIdentifier=@"local.musicstrip.mouse";

// Finds Contents/Helpers/3£ Mouse.app in the enclosing 3£ bundle, whichever
// nested helper app this code is running from.
static NSURL *ThreeEMouseHelperURL(void) {
    NSURL *url=NSBundle.mainBundle.bundleURL;
    for(int depth=0;depth<6 && url.path.length>1;depth++) {
        if([url.pathExtension isEqual:@"app"]) {
            NSURL *helper=[url URLByAppendingPathComponent:@"Contents/Helpers/3£ Mouse.app"];
            if([NSFileManager.defaultManager fileExistsAtPath:helper.path]) return helper;
        }
        url=url.URLByDeletingLastPathComponent;
    }
    return nil;
}

@interface ThreeEMouseActions : NSObject
+ (void)openMouse:(id)sender;
@end

@implementation ThreeEMouseActions
+ (void)openMouse:(id)sender {
    NSURL *helper=ThreeEMouseHelperURL();
    if(!helper) {
        NSAlert *alert=[NSAlert new];alert.messageText=@"3£ Mouse is not installed";
        alert.informativeText=@"Reinstall 3£ to add the mouse settings.";[alert runModal];return;
    }
    NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
    configuration.activates=YES;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:helper configuration:configuration completionHandler:nil];
}
@end

static NSMenuItem *ThreeEMouseMenu(void) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Mouse…" action:@selector(openMouse:) keyEquivalent:@""];
    item.identifier=ThreeEMouseMenuIdentifier;item.target=ThreeEMouseActions.class;
    item.toolTip=@"Gaming-mouse settings: DPI, polling rate, lighting, buttons (side button → F13) and macros";
    return item;
}
