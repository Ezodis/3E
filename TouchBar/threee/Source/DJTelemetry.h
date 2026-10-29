// Read-only, bounded accessibility adapter for rekordbox's displayed deck data.
#import <ApplicationServices/ApplicationServices.h>
static double DJSeconds(NSString *text) {
    NSArray *parts=[[text stringByReplacingOccurrencesOfString:@"-" withString:@""] componentsSeparatedByString:@":"];
    return parts.count==2 ? [parts[0] doubleValue]*60+[parts[1] doubleValue] : -1;
}
static NSString *DJTime(double seconds) {
    NSInteger n=MAX(0,(NSInteger)lround(seconds)); return [NSString stringWithFormat:@"%02ld:%02ld",(long)n/60,(long)n%60];
}
static NSArray *DJParseDecks(NSArray<NSDictionary *> *nodes) {
    NSMutableArray *decks=[NSMutableArray new];
    NSRegularExpression *time=[NSRegularExpression regularExpressionWithPattern:@"^-?[0-9]{1,3}:[0-9]{2}$" options:0 error:nil];
    for(NSUInteger i=0;i<nodes.count && decks.count<2;i++) {
        if(![nodes[i][@"help"] hasPrefix:@"Beat Sync:"]) continue;
        NSInteger image=-1;
        for(NSInteger j=(NSInteger)i-1;j>=MAX(0,(NSInteger)i-10);j--) if([nodes[j][@"role"] isEqual:@"AXImage"]) { image=j;break; }
        if(image<1) return @[];
        NSString *title=nodes[image-1][@"text"];
        if(!title.length || ![nodes[image-1][@"role"] isEqual:@"AXStaticText"]) return @[];
        NSMutableArray *times=[NSMutableArray new];
        for(NSUInteger j=i+1;j<MIN(nodes.count,i+20);j++) {
            if([nodes[j][@"help"] hasPrefix:@"Sync Master:"]) break;
            NSString *text=nodes[j][@"text"] ?: @"";
            if([time numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)]) {
                if(j+1<nodes.count && [nodes[j+1][@"text"] hasPrefix:@"."]) text=[text stringByAppendingString:nodes[j+1][@"text"]];
                [times addObject:text];
            }
        }
        if(times.count!=2) return @[]; // Never infer a deck from the library's track list.
        double first=DJSeconds(times[0]),second=DJSeconds(times[1]);
        // rekordbox displays remaining first, elapsed second.
        [decks addObject:@{@"title":title,@"elapsed":@(second),@"duration":@(first+second),@"time":[NSString stringWithFormat:@"%@ / %@",DJTime(second),DJTime(first+second)],@"sync":@([nodes[i][@"text"] isEqual:@"1"] || [nodes[i][@"text"] isEqual:@"On"])}];
    }
    return decks;
}
static id DJAX(AXUIElementRef element,CFStringRef key) {
    CFTypeRef result=NULL; if(AXUIElementCopyAttributeValue(element,key,&result)!=kAXErrorSuccess) return nil; return CFBridgingRelease(result);
}
static void DJCollectAX(AXUIElementRef element,NSMutableArray *nodes,NSInteger depth,CFAbsoluteTime deadline) {
    if(depth>6 || nodes.count>=300 || CFAbsoluteTimeGetCurrent()>deadline) return;
    NSString *role=DJAX(element,kAXRoleAttribute);
    if([role isEqual:@"AXStaticText"] || [role isEqual:@"AXButton"] || [role isEqual:@"AXImage"]) {
        id value=DJAX(element,kAXValueAttribute); NSString *text=[value isKindOfClass:NSString.class] ? value : [value respondsToSelector:@selector(stringValue)] ? [value stringValue] : @"";
        [nodes addObject:@{@"role":role ?: @"",@"text":text ?: @"",@"help":DJAX(element,kAXHelpAttribute) ?: @""}];
    }
    for(id child in DJAX(element,kAXChildrenAttribute)) DJCollectAX((__bridge AXUIElementRef)child,nodes,depth+1,deadline);
}
@interface ThreeEDJTelemetry : NSObject
@property NSArray *decks;
@property double updated;
@property BOOL busy;
@property double lastPoll;
+ (instancetype)shared;
- (void)poll;
- (NSDictionary *)deck:(NSInteger)deck;
@end
@implementation ThreeEDJTelemetry
+ (instancetype)shared { static id instance; static dispatch_once_t once;dispatch_once(&once,^{instance=[self new];});return instance; }
- (NSDictionary *)deck:(NSInteger)deck { return NSProcessInfo.processInfo.systemUptime-self.updated<2.5 && deck>=0 && (NSUInteger)deck<self.decks.count ? self.decks[deck] : nil; }
- (void)poll {
#ifndef THREEE_DJ_STANDALONE_TEST
    if(self.busy || !AXIsProcessTrusted() || NSProcessInfo.processInfo.systemUptime-self.lastPoll<.65) return;
    self.lastPoll=NSProcessInfo.processInfo.systemUptime;
    NSRunningApplication *app=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.pioneerdj.rekordboxdj"].firstObject;
    if(!app) { self.decks=nil;return; }
    self.busy=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,.08);
        NSArray *windows=DJAX(root,kAXWindowsAttribute); NSMutableArray *nodes=[NSMutableArray new];
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.35;
        for(id window in windows) if([DJAX((__bridge AXUIElementRef)window,kAXTitleAttribute) isEqual:@"rekordbox"]) { DJCollectAX((__bridge AXUIElementRef)window,nodes,0,deadline);break; }
        CFRelease(root); NSArray *decks=DJParseDecks(nodes);
        dispatch_async(dispatch_get_main_queue(),^{self.decks=decks;self.updated=NSProcessInfo.processInfo.systemUptime;self.busy=NO;});
    });
#endif
}
@end
