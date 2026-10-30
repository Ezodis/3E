// Read-only, bounded adapter for rekordbox's visible deck and mixer fields.
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
        if(![nodes[i][@"help"] hasPrefix:@"Beat Sync:"] && ![nodes[i][@"help"] hasPrefix:@"BPM Sync:"]) continue;
        NSInteger image=-1;
        for(NSInteger j=(NSInteger)i-1;j>=MAX(0,(NSInteger)i-10);j--) if([nodes[j][@"role"] isEqual:@"AXImage"]) { image=j;break; }
        if(image<1) return @[];
        NSString *title=nodes[image-1][@"text"];
        if(!title.length || ![@[@"AXStaticText",@"AXTextField"] containsObject:nodes[image-1][@"role"]]) return @[];
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
static NSDictionary *DJParseMixerValues(NSArray<NSDictionary *> *nodes) {
    NSMutableDictionary *values=[NSMutableDictionary new],*counts=[NSMutableDictionary new];
    NSArray *prefixes=@[@"EQ/ISO (High) knob:",@"EQ/ISO (Mid) knob:",@"EQ/ISO (Low) knob:",@"Channel Fader:",@"CROSSFADER:"];
    NSArray *numbers=@[@16,@17,@18,@7,@8];
    for(NSDictionary *node in nodes) {
        if(![node[@"role"] isEqual:@"AXSlider"]) continue;
        for(NSUInteger i=0;i<prefixes.count;i++) if([node[@"help"] hasPrefix:prefixes[i]]) {
            NSInteger channel=[counts[prefixes[i]] integerValue];counts[prefixes[i]]=@(channel+1);
            if(channel>=(i==4 ? 1 : 2)) break;
            // rekordbox's Qt percentage sliders omit AXMin/Max. Only these
            // known controls use the verified EQ/crossfade -50...50 and
            // channel-level 0...100 ranges; never infer an unrelated slider.
            double low=node[@"min"] ? [node[@"min"] doubleValue] : i==3 ? 0 : -50;
            double high=node[@"max"] ? [node[@"max"] doubleValue] : i==3 ? 100 : 50,value;
            NSScanner *scanner=[NSScanner scannerWithString:node[@"text"] ?: @""];
            if(![scanner scanDouble:&value] || !scanner.isAtEnd) break;
            if(isfinite(low) && isfinite(high) && isfinite(value) && high>low && value>=low && value<=high)
                values[[NSString stringWithFormat:@"%ld:%ld:0",(long)(i==4 ? 15 : channel),[numbers[i] longValue]]]=@(lround((value-low)/(high-low)*127));
            break;
        }
    }
    return values;
}
static void DJCollectAX(AXUIElementRef element,NSMutableArray *nodes,NSInteger depth,CFAbsoluteTime deadline) {
    if(depth>6 || nodes.count>=300 || CFAbsoluteTimeGetCurrent()>deadline) return;
    NSArray *keys=@[(__bridge id)kAXRoleAttribute,(__bridge id)kAXValueAttribute,(__bridge id)kAXHelpAttribute,(__bridge id)kAXDescriptionAttribute,(__bridge id)kAXTitleAttribute,(__bridge id)kAXChildrenAttribute];
    CFArrayRef raw=NULL;
    if(AXUIElementCopyMultipleAttributeValues(element,(__bridge CFArrayRef)keys,0,&raw)!=kAXErrorSuccess || !raw) return;
    NSArray *attributes=CFBridgingRelease(raw);if(attributes.count!=keys.count) return;
    NSString *role=[attributes[0] isKindOfClass:NSString.class] ? attributes[0] : @"";
    // Never walk the library's rows or inspect its track data.
    if([@[@"AXTable",@"AXOutline"] containsObject:role]) return;
    if([@[@"AXStaticText",@"AXTextField",@"AXButton",@"AXImage",@"AXSlider"] containsObject:role]) {
        id value=attributes[1];NSString *text=[value isKindOfClass:NSString.class] ? value : [value respondsToSelector:@selector(stringValue)] ? [value stringValue] : [attributes[4] isKindOfClass:NSString.class] ? attributes[4] : @"";
        NSString *help=[attributes[2] isKindOfClass:NSString.class] ? attributes[2] : [attributes[3] isKindOfClass:NSString.class] ? attributes[3] : @"";
        if(!help.length && [attributes[3] isKindOfClass:NSString.class]) help=attributes[3];
        NSMutableDictionary *node=[@{@"role":role,@"text":text,@"help":help} mutableCopy];
        if([role isEqual:@"AXSlider"]) {
            id low=DJAX(element,kAXMinValueAttribute),high=DJAX(element,kAXMaxValueAttribute);
            if([low respondsToSelector:@selector(doubleValue)] && [high respondsToSelector:@selector(doubleValue)]) { node[@"min"]=low;node[@"max"]=high; }
        }
        [nodes addObject:node];
    }
    if([attributes[5] isKindOfClass:NSArray.class]) for(id child in attributes[5]) DJCollectAX((__bridge AXUIElementRef)child,nodes,depth+1,deadline);
}
@interface ThreeEDJTelemetry : NSObject
@property NSArray *decks;
@property double updated;
@property BOOL busy;
@property double lastPoll;
@property NSDictionary *controlValues;
@property double controlsUpdated;
+ (instancetype)shared;
- (void)poll;
- (NSDictionary *)deck:(NSInteger)deck;
- (void)updateDecks:(NSArray *)decks at:(double)time;
@end
@implementation ThreeEDJTelemetry
+ (instancetype)shared { static id instance; static dispatch_once_t once;dispatch_once(&once,^{instance=[self new];});return instance; }
- (NSDictionary *)deck:(NSInteger)deck { return NSProcessInfo.processInfo.systemUptime-self.updated<2.5 && deck>=0 && (NSUInteger)deck<self.decks.count ? self.decks[deck] : nil; }
- (void)updateDecks:(NSArray *)decks at:(double)time {
    NSMutableArray *observed=[NSMutableArray new];double dt=time-self.updated;
    for(NSUInteger i=0;i<decks.count;i++) {
        NSMutableDictionary *deck=[decks[i] mutableCopy];
        NSDictionary *previous=i<self.decks.count ? self.decks[i] : nil;
        if(dt>.15 && dt<2.5 && [previous[@"title"] isEqual:deck[@"title"]] && fabs([previous[@"duration"] doubleValue]-[deck[@"duration"] doubleValue])<.5) {
            double travel=[deck[@"elapsed"] doubleValue]-[previous[@"elapsed"] doubleValue];
            // Infer transport only from consecutive real host positions. Large seeks are unknown.
            if(fabs(travel)<.04) deck[@"playing"]=@NO;
            else if(travel>dt*.2 && travel<dt*3) deck[@"playing"]=@YES;
        }
        [observed addObject:deck];
    }
    self.decks=observed;self.updated=time;
}
- (void)poll {
#ifndef THREEE_DJ_STANDALONE_TEST
    if(self.busy || !AXIsProcessTrusted() || NSProcessInfo.processInfo.systemUptime-self.lastPoll<.65) return;
    self.lastPoll=NSProcessInfo.processInfo.systemUptime;
    NSRunningApplication *app=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.pioneerdj.rekordboxdj"].firstObject;
    if(!app) { self.decks=nil;self.controlValues=nil;return; }
    self.busy=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,.08);
        NSArray *windows=DJAX(root,kAXWindowsAttribute);NSArray *decks=@[];NSDictionary *controls=@{};
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.8;double sampled=NSProcessInfo.processInfo.systemUptime;NSUInteger checked=0;
        // Split Screen can put a separate browser window first. Select the
        // window containing actual deck anchors, rather than the first title.
        for(id window in windows) {
            if(checked++>=4 || CFAbsoluteTimeGetCurrent()>deadline) break;
            if(![DJAX((__bridge AXUIElementRef)window,kAXTitleAttribute) isEqual:@"rekordbox"]) continue;
            NSMutableArray *nodes=[NSMutableArray new];
            DJCollectAX((__bridge AXUIElementRef)window,nodes,0,MIN(deadline,CFAbsoluteTimeGetCurrent()+.35));
            NSArray *candidate=DJParseDecks(nodes);
            if(candidate.count>decks.count) { decks=candidate;controls=DJParseMixerValues(nodes); }
            if(decks.count==2) break;
        }
        CFRelease(root);
        dispatch_async(dispatch_get_main_queue(),^{self.controlValues=controls;self.controlsUpdated=sampled;[self updateDecks:decks at:NSProcessInfo.processInfo.systemUptime];self.busy=NO;});
    });
#endif
}
@end
