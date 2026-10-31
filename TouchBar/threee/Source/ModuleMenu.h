// SPDX-License-Identifier: MIT
#pragma once
#import <AppKit/AppKit.h>

@interface ThreeEModuleMenuRow : NSView
@property (weak) NSMenuItem *item;
@property NSView *originalView;
@property NSButton *mainButton;
@property NSButton *gear;
@property NSString *module;
@property NSString *moduleName;
@property BOOL installed;
@property BOOL hovered;
- (NSMenu *)settingsMenu;
- (void)update;
@end
@implementation ThreeEModuleMenuRow
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.autoresizingMask=NSViewWidthSizable;
        self.gear=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Module settings"] target:self action:@selector(openSettings:)];
        self.gear.bordered=NO;self.gear.imageScaling=NSImageScaleProportionallyDown;self.gear.contentTintColor=NSColor.secondaryLabelColor;[self addSubview:self.gear];
    }return self;
}
- (BOOL)isFlipped{return YES;}
- (void)setFrameSize:(NSSize)size{[super setFrameSize:size];[self layout];}
- (void)layout {
    [super layout];CGFloat width=self.bounds.size.width;
    self.originalView.frame=NSMakeRect(0,0,MAX(0,width-44),self.bounds.size.height);
    self.mainButton.frame=NSMakeRect(38,0,MAX(0,width-84),self.bounds.size.height);
    self.gear.frame=NSMakeRect(width-39,2,30,self.bounds.size.height-4);
}
- (void)update {
    self.mainButton.title=self.item.title;self.mainButton.enabled=self.item.enabled&&self.item.action!=NULL;
    self.mainButton.toolTip=self.item.toolTip;
    self.gear.accessibilityLabel=[self.moduleName stringByAppendingString:@" settings"];
    self.gear.toolTip=[NSString stringWithFormat:@"%@ %@…",self.installed?@"Uninstall":@"Install",self.moduleName];
    self.needsDisplay=YES;self.originalView.needsDisplay=YES;[self layout];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];for(NSTrackingArea *area in self.trackingAreas)[self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event{self.hovered=YES;self.needsDisplay=YES;}
- (void)mouseExited:(NSEvent *)event{self.hovered=NO;self.needsDisplay=YES;}
- (void)drawRect:(NSRect)dirty {
    if(self.hovered){[NSColor.selectedContentBackgroundColor setFill];[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,5,1) xRadius:4 yRadius:4] fill];}
    self.mainButton.contentTintColor=self.hovered?NSColor.selectedMenuItemTextColor:NSColor.labelColor;
    if(!self.originalView&&self.item.state==NSControlStateValueOn)[@"✓" drawAtPoint:NSMakePoint(20,4) withAttributes:@{NSFontAttributeName:[NSFont menuFontOfSize:0],NSForegroundColorAttributeName:self.hovered?NSColor.selectedMenuItemTextColor:NSColor.labelColor}];
}
- (void)performMain:(id)sender {
    if(!self.item.enabled||!self.item.action)return;
    [self.item.menu cancelTracking];[NSApp sendAction:self.item.action to:self.item.target from:self.item];
}
- (NSMenu *)settingsMenu {
    NSMenu *menu=[NSMenu new];NSMenuItem *action=[[NSMenuItem alloc] initWithTitle:self.gear.toolTip action:NSSelectorFromString(@"changeModule:") keyEquivalent:@""];
    action.representedObject=self.module;action.target=NSClassFromString(@"ThreeEModuleActions");[menu addItem:action];return menu;
}
- (void)openSettings:(id)sender {
    NSPoint anchor=[self.window convertPointToScreen:[self convertPoint:NSMakePoint(NSMinX(self.gear.frame),NSMaxY(self.gear.frame)) toView:nil]];
    NSMenu *settings=[self settingsMenu];[self.item.menu cancelTracking];
    [settings popUpMenuPositioningItem:nil atLocation:anchor inView:nil];
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    if(NSPointInRect(point,self.gear.frame))[self openSettings:self];else [self performMain:self];
}
@end

static void StripAttachModuleGear(NSMenuItem *item,NSString *module,NSString *name,BOOL installed) {
    ThreeEModuleMenuRow *row=[item.view isKindOfClass:ThreeEModuleMenuRow.class]?(id)item.view:nil;
    if(!row) {
        NSView *original=item.view;
        row=[[ThreeEModuleMenuRow alloc] initWithFrame:NSMakeRect(0,0,230,26)];row.item=item;
        // NSMenuItem detaches its previous view when replaced. Reattach that
        // original row only after installing the wrapper, preserving QR hover.
        item.view=row;
        if(original){row.originalView=original;[row addSubview:original positioned:NSWindowBelow relativeTo:row.gear];}
        else {row.mainButton=[NSButton buttonWithTitle:item.title target:row action:@selector(performMain:)];row.mainButton.bordered=NO;row.mainButton.alignment=NSTextAlignmentLeft;row.mainButton.font=[NSFont menuFontOfSize:0];[row addSubview:row.mainButton];}
    }
    row.module=module;row.moduleName=name;row.installed=installed;[row update];
}
