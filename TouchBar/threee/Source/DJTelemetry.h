// Read-only, bounded adapter for rekordbox's visible deck and mixer fields.
#import <ApplicationServices/ApplicationServices.h>
#import "DJTracking.h"
static double DJSeconds(NSString *text) {
    NSArray *parts=[[text stringByReplacingOccurrencesOfString:@"-" withString:@""] componentsSeparatedByString:@":"];
    return parts.count==2 ? [parts[0] doubleValue]*60+[parts[1] doubleValue] : -1;
}
static NSString *DJTime(double seconds) {
    NSInteger n=MAX(0,(NSInteger)lround(seconds)); return [NSString stringWithFormat:@"%02ld:%02ld",(long)n/60,(long)n%60];
}
static NSNumber *DJNumericText(NSString *text) {
    if(![text isKindOfClass:NSString.class]) return nil;
    NSScanner *scanner=[NSScanner scannerWithString:text];double number;
    return [scanner scanDouble:&number] && scanner.isAtEnd && isfinite(number) ? @(number) : nil;
}
static NSArray *DJDeckVitals(NSArray *decks,NSArray<NSDictionary *> *nodes) {
    NSMutableArray *result=[NSMutableArray new],*loaded=[NSMutableArray new],*fields=[NSMutableArray new];
    for(NSUInteger i=0;i<decks.count;i++) { [result addObject:[decks[i] mutableCopy]];if([decks[i][@"duration"] doubleValue]>0) [loaded addObject:@(i)]; }
    for(NSUInteger i=0;i<nodes.count;i++) if([nodes[i][@"help"] hasPrefix:@"Deck BPM display:"]) [fields addObject:@(i)];
    NSArray *order=nil;
    // Keep unloaded slots in place when exposed; otherwise require exactly
    // one tempo panel per loaded deck. Partial reads never shift Deck B to A.
    if(fields.count==decks.count) { NSMutableArray *all=[NSMutableArray new];for(NSUInteger i=0;i<decks.count;i++) [all addObject:@(i)];order=all; }
    else if(fields.count==loaded.count) order=loaded;
    for(NSUInteger i=0;order && i<fields.count;i++) {
        NSUInteger at=[fields[i] unsignedIntegerValue],deckIndex=[order[i] unsignedIntegerValue];
        NSMutableDictionary *deck=result[deckIndex];NSNumber *bpm=DJNumericText(nodes[at][@"text"]);
        if([deck[@"duration"] doubleValue]<=0 || !bpm || bpm.doubleValue<=0 || bpm.doubleValue>1000) continue;
        deck[@"bpm"]=bpm;
        NSUInteger end=MIN(nodes.count,at+12);if(i+1<fields.count) end=MIN(end,[fields[i+1] unsignedIntegerValue]);
        for(NSUInteger j=at+1;j<end;j++) {
            NSString *help=nodes[j][@"help"] ?: @"",*text=nodes[j][@"text"] ?: @"";
            if([help hasPrefix:@"Playing speed display"] || [text hasPrefix:@"Playing speed display"]) {
                for(NSInteger back=1;back<=2 && j>at+(NSUInteger)back;back++) {
                    NSNumber *pitch=DJNumericText([nodes[j-back][@"text"] stringByReplacingOccurrencesOfString:@"%" withString:@""]);
                    if(pitch && pitch.doubleValue>=-100 && pitch.doubleValue<=1000) { deck[@"tempo"]=pitch;break; }
                }
            }
            if([help hasPrefix:@"Tempo Range"]) {
                NSString *range=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""].uppercaseString;
                if([@[@"±6",@"±10",@"±16",@"WIDE"] containsObject:range]) deck[@"tempoRange"]=range;
            }
        }
    }
    // Browse renders BPM as separate whole/fraction text, followed by pitch.
    // Accept that exact pattern only in the known compact layout.
    BOOL browse=NO;for(NSDictionary *node in nodes) if([node[@"help"] hasPrefix:@"Change layout:"] && [node[@"text"] isEqual:@"Browse"]) browse=YES;
    if(!fields.count && browse) {
        NSMutableArray *pairs=[NSMutableArray new];
        for(NSUInteger i=2;i<nodes.count;i++) {
            NSString *pitchText=nodes[i][@"text"] ?: @"",*fraction=nodes[i-1][@"text"] ?: @"";
            if(![pitchText hasSuffix:@"%"] || ![fraction hasPrefix:@"."] || fraction.length!=3) continue;
            NSNumber *whole=DJNumericText(nodes[i-2][@"text"]),*part=DJNumericText(fraction),*pitch=DJNumericText([pitchText substringToIndex:pitchText.length-1]);
            double bpm=whole.doubleValue+part.doubleValue;
            if(whole && part && pitch && whole.doubleValue==floor(whole.doubleValue) && bpm>0 && bpm<=1000 && pitch.doubleValue>=-100 && pitch.doubleValue<=1000)
                [pairs addObject:@{@"bpm":@(bpm),@"tempo":pitch}];
        }
        if(pairs.count==loaded.count) for(NSUInteger i=0;i<pairs.count;i++) [result[[loaded[i] unsignedIntegerValue]] addEntriesFromDictionary:pairs[i]];
    }
    NSMutableArray *loops=[NSMutableArray new];
    for(NSDictionary *node in nodes) if([node[@"help"] hasPrefix:@"Auto Beat Loop:"]) [loops addObject:node];
    if(loops.count==decks.count) for(NSUInteger i=0;i<loops.count;i++) {
        NSNumber *beats=DJNumericText(loops[i][@"text"]);
        if([result[i][@"duration"] doubleValue]>0 && beats.doubleValue>0 && beats.doubleValue<=512) result[i][@"loopBeats"]=beats;
    }
    return result;
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
        NSMutableDictionary *deck=[@{@"title":title,@"elapsed":@(second),@"duration":@(first+second),@"time":[NSString stringWithFormat:@"%@ / %@",DJTime(second),DJTime(first+second)],@"sync":@([nodes[i][@"text"] isEqual:@"1"] || [nodes[i][@"text"] isEqual:@"On"])} mutableCopy];
        if(nodes[image][@"artworkRect"]) deck[@"artworkRect"]=nodes[image][@"artworkRect"];
        [decks addObject:deck];
    }
    return DJDeckVitals(decks,nodes);
}
static id DJAX(AXUIElementRef element,CFStringRef key) {
    CFTypeRef result=NULL; if(AXUIElementCopyAttributeValue(element,key,&result)!=kAXErrorSuccess) return nil; return CFBridgingRelease(result);
}
#import "DJArtwork.h"
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
    if([@[@"AXStaticText",@"AXTextField",@"AXTextArea",@"AXButton",@"AXImage",@"AXSlider",@"AXPopUpButton"] containsObject:role]) {
        id value=attributes[1];NSString *text=[value isKindOfClass:NSString.class] ? value : [value respondsToSelector:@selector(stringValue)] ? [value stringValue] : [attributes[4] isKindOfClass:NSString.class] ? attributes[4] : @"";
        NSString *help=[attributes[2] isKindOfClass:NSString.class] ? attributes[2] : [attributes[3] isKindOfClass:NSString.class] ? attributes[3] : @"";
        if(!help.length && [attributes[3] isKindOfClass:NSString.class]) help=attributes[3];
        if([role isEqual:@"AXPopUpButton"] && ![help hasPrefix:@"Change layout:"] && ![help hasPrefix:@"Tempo Range"]) return;
        if([role isEqual:@"AXTextArea"] && ![help hasPrefix:@"Deck BPM display:"] && ![help hasPrefix:@"Tempo Range"] && ![help hasPrefix:@"Playing speed display"]) return;
        NSMutableDictionary *node=[@{@"role":role,@"text":text,@"help":help} mutableCopy];
#ifndef THREEE_DJ_STANDALONE_TEST
        if([role isEqual:@"AXImage"]) { NSArray *frame=DJAXFrame(element);if(frame) node[@"artworkRect"]=frame; }
#endif
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
@property NSMutableDictionary<NSNumber *,NSImage *> *artworks;
@property NSMutableDictionary<NSNumber *,NSString *> *artworkKeys;
@property NSMutableDictionary<NSNumber *,NSString *> *artworkDataURLs;
@property BOOL artworkBusy;
@property double artworkStarted;
@property NSUInteger artworkGeneration;
+ (instancetype)shared;
- (void)poll;
- (NSDictionary *)deck:(NSInteger)deck;
- (void)updateDecks:(NSArray *)decks at:(double)time;
- (NSImage *)artworkForDeck:(NSInteger)deck;
- (void)refreshArtwork:(pid_t)pid;
- (void)acceptArtwork:(NSDictionary *)images keys:(NSArray *)keys generation:(NSUInteger)generation;
@end
@implementation ThreeEDJTelemetry
+ (instancetype)shared { static id instance; static dispatch_once_t once;dispatch_once(&once,^{instance=[self new];});return instance; }
- (NSDictionary *)deck:(NSInteger)deck { return NSProcessInfo.processInfo.systemUptime-self.updated<2.5 && deck>=0 && (NSUInteger)deck<self.decks.count ? self.decks[deck] : nil; }
- (NSImage *)artworkForDeck:(NSInteger)deck {
    NSString *key=DJArtworkKey([self deck:deck]);
    return key && [key isEqual:self.artworkKeys[@(deck)]] ? self.artworks[@(deck)] : nil;
}
- (void)refreshArtwork:(pid_t)pid {
#ifndef THREEE_DJ_STANDALONE_TEST
    double now=NSProcessInfo.processInfo.systemUptime;
    if(self.artworkBusy && now-self.artworkStarted<5) return;
    if(now-self.artworkStarted<3) return;
    self.artworkBusy=YES;self.artworkStarted=now;NSUInteger generation=++self.artworkGeneration;
    NSMutableArray *rects=[NSMutableArray new],*keys=[NSMutableArray new];
    for(NSDictionary *deck in self.decks) { [rects addObject:deck[@"artworkRect"] ?: @[]];[keys addObject:DJArtworkKey(deck) ?: @""]; }
    DJCaptureCovers(pid,rects,^(NSDictionary *images) { [self acceptArtwork:images keys:keys generation:generation]; });
#endif
}
- (void)acceptArtwork:(NSDictionary *)images keys:(NSArray *)keys generation:(NSUInteger)generation {
    if(generation!=self.artworkGeneration) return;
    self.artworkBusy=NO;
    for(NSNumber *index in images) if(index.unsignedIntegerValue<keys.count && [keys[index.unsignedIntegerValue] isEqual:DJArtworkKey([self deck:index.integerValue])]) {
        self.artworks[index]=images[index];self.artworkKeys[index]=keys[index.unsignedIntegerValue];
        NSImage *cover=images[index];NSData *tiff=cover.representations.count ? cover.TIFFRepresentation : nil;
        NSBitmapImageRep *bitmap=tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
        NSData *jpeg=[bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor:@.7}];
        if(jpeg.length && jpeg.length<=24576) self.artworkDataURLs[index]=[@"data:image/jpeg;base64," stringByAppendingString:[jpeg base64EncodedStringWithOptions:0]];
    }
}
- (void)updateDecks:(NSArray *)decks at:(double)time {
    if(!self.artworkDataURLs) self.artworkDataURLs=[NSMutableDictionary new];if(!self.artworks) self.artworks=[NSMutableDictionary new];if(!self.artworkKeys) self.artworkKeys=[NSMutableDictionary new];
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
    for(NSNumber *index in self.artworkKeys.allKeys) if(![self.artworkKeys[index] isEqual:DJArtworkKey([self deck:index.integerValue])]) { [self.artworks removeObjectForKey:index];[self.artworkKeys removeObjectForKey:index];[self.artworkDataURLs removeObjectForKey:index]; }
}
- (void)poll {
#ifndef THREEE_DJ_STANDALONE_TEST
    if(self.busy || !AXIsProcessTrusted() || NSProcessInfo.processInfo.systemUptime-self.lastPoll<.65) return;
    self.lastPoll=NSProcessInfo.processInfo.systemUptime;
    NSRunningApplication *app=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.pioneerdj.rekordboxdj"].firstObject;
    if(!app) { [self updateDecks:@[] at:NSProcessInfo.processInfo.systemUptime];self.controlValues=nil;self.artworkGeneration++;self.artworkBusy=NO;return; }
    self.busy=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,.08);
        NSArray *windows=DJAX(root,kAXWindowsAttribute);NSArray *decks=@[];NSDictionary *controls=@{};
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.8;double sampled=NSProcessInfo.processInfo.systemUptime;NSUInteger checked=0;NSInteger best=0;
        // Split Screen can put a separate browser window first. Select the
        // window containing actual deck anchors, rather than the first title.
        for(id window in windows) {
            if(checked++>=4 || CFAbsoluteTimeGetCurrent()>deadline) break;
            if(![DJAX((__bridge AXUIElementRef)window,kAXTitleAttribute) isEqual:@"rekordbox"]) continue;
            NSMutableArray *nodes=[NSMutableArray new];
            DJCollectAX((__bridge AXUIElementRef)window,nodes,0,MIN(deadline,CFAbsoluteTimeGetCurrent()+.35));
            NSArray *candidate=DJParseDecks(nodes);
            NSDictionary *mixer=DJParseMixerValues(nodes);NSInteger vitals=0,loaded=0;
            for(NSDictionary *deck in candidate) { loaded+=[deck[@"duration"] doubleValue]>0;vitals+=(deck[@"bpm"]!=nil)+(deck[@"tempo"]!=nil)+(deck[@"tempoRange"]!=nil); }
            NSInteger quality=candidate.count*100+mixer.count+vitals;
            if(candidate.count && quality>best) { best=quality;decks=candidate;controls=mixer; }
            if(candidate.count==2 && mixer.count>=9 && vitals>=loaded*3) break;
        }
        CFRelease(root);
        DJRunOnMain(^{self.controlValues=controls;self.controlsUpdated=sampled;[self updateDecks:decks at:NSProcessInfo.processInfo.systemUptime];[self refreshArtwork:app.processIdentifier];self.busy=NO;});
    });
#endif
}
@end
