#import "AbletonAccessibility.h"
#import <ApplicationServices/ApplicationServices.h>

static NSRunningApplication *Ableton(void) { return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.ableton.live"].firstObject; }
BOOL Strip3AbletonIsRunning(void) { NSRunningApplication *app=Ableton(); return app && !app.terminated; }

static NSString *AXString(AXUIElementRef element, CFStringRef attribute) { CFTypeRef value=NULL; AXUIElementCopyAttributeValue(element,attribute,&value); NSString *result=[(__bridge id)value isKindOfClass:NSString.class] ? [(__bridge NSString *)value copy] : nil; if(value) CFRelease(value); return result; }
static BOOL Contains(NSString *value, NSArray<NSString *> *tokens) { NSString *lower=value.lowercaseString; for(NSString *token in tokens) if([lower containsString:token]) return YES; return NO; }
static AXUIElementRef FindRecordElement(AXUIElementRef element, NSArray<NSString *> *tokens, int depth) {
    if(!element || depth>8) return NULL;
    NSString *role=AXString(element,kAXRoleAttribute); NSString *title=AXString(element,kAXTitleAttribute); NSString *description=AXString(element,kAXDescriptionAttribute); NSString *help=AXString(element,kAXHelpAttribute);
    if([role isEqualToString:(__bridge NSString *)kAXButtonRole] && (Contains(title,tokens)||Contains(description,tokens)||Contains(help,tokens))) { CFRetain(element); return element; }
    CFTypeRef raw=NULL; AXUIElementCopyAttributeValue(element,kAXChildrenAttribute,&raw); if(!raw) return NULL;
    for(id child in (__bridge NSArray *)raw) { AXUIElementRef found=FindRecordElement((__bridge AXUIElementRef)child,tokens,depth+1); if(found) { CFRelease(raw); return found; } }
    CFRelease(raw); return NULL;
}
static AXUIElementRef RecordElement(NSArray<NSString *> *tokens) { NSRunningApplication *app=Ableton(); if(!app || app.terminated || !AXIsProcessTrusted()) return NULL; AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,1.0); AXUIElementRef found=FindRecordElement(root,tokens,0); CFRelease(root); return found; }
static BOOL Press(NSArray<NSString *> *tokens) { AXUIElementRef element=RecordElement(tokens); if(!element) return NO; AXError error=AXUIElementPerformAction(element,kAXPressAction); CFRelease(element); return error==kAXErrorSuccess; }
BOOL Strip3AbletonSetRecord(BOOL enabled) { return Press(enabled ? @[@"record",@"arrangement record"] : @[@"record",@"stop recording"]); }
BOOL Strip3AbletonToggleRecord(void) { return Press(@[@"record",@"arrangement record"]); }
BOOL Strip3AbletonPerformOption(NSString *option) { if([option isEqualToString:@"arrangement"]) return Press(@[@"arrangement"]); if([option isEqualToString:@"session"]) return Press(@[@"session"]); if([option isEqualToString:@"punch-in"]) return Press(@[@"punch in"]); if([option isEqualToString:@"punch-out"]) return Press(@[@"punch out"]); if([option isEqualToString:@"overdub"]) return Press(@[@"overdub"]); if([option isEqualToString:@"count-in"]) return Press(@[@"count in"]); return NO; }
