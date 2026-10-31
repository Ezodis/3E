// SPDX-License-Identifier: MIT
#pragma once
#import <AppKit/AppKit.h>

@interface ThreeECarMenuRow : NSView
@property (weak) NSMenuItem *item;
@property NSButton *toggle;
@property NSButton *mirror;
@property BOOL hovered;
- (void)toggleCarView:(id)sender;
- (void)toggleCarMirror:(id)sender;
@end
@implementation ThreeECarMenuRow
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.autoresizingMask=NSViewWidthSizable;
        self.toggle=[NSButton buttonWithTitle:@"Car View" target:self action:@selector(toggleCarView:)];
        self.toggle.bordered=NO;self.toggle.alignment=NSTextAlignmentLeft;self.toggle.font=[NSFont menuFontOfSize:0];
        self.toggle.toolTip=@"Toggle larger controls and the neon pointer. Turning off restores the previous display and pointer.";
        [self addSubview:self.toggle];
        NSImage *image=[NSImage imageWithSystemSymbolName:@"arrow.left.arrow.right" accessibilityDescription:@"Mirror screen"];
        self.mirror=[NSButton buttonWithImage:image target:self action:@selector(toggleCarMirror:)];
        self.mirror.bordered=NO;self.mirror.imagePosition=NSImageOnly;self.mirror.imageScaling=NSImageScaleProportionallyDown;
        self.mirror.accessibilityLabel=@"Mirror screen";[self addSubview:self.mirror];[self layout];
    }return self;
}
- (BOOL)isFlipped{return YES;}
- (void)setFrameSize:(NSSize)size{[super setFrameSize:size];[self layout];}
- (void)layout {
    [super layout];self.toggle.frame=NSMakeRect(38,0,MAX(0,self.bounds.size.width-84),self.bounds.size.height);
    self.mirror.frame=NSMakeRect(self.bounds.size.width-39,2,30,self.bounds.size.height-4);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];for(NSTrackingArea *area in self.trackingAreas)[self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event{self.hovered=YES;self.needsDisplay=YES;}
- (void)mouseExited:(NSEvent *)event{self.hovered=NO;self.needsDisplay=YES;}
- (void)drawRect:(NSRect)dirty {
    if(self.hovered){[NSColor.selectedContentBackgroundColor setFill];[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,5,1) xRadius:4 yRadius:4] fill];}
    self.toggle.contentTintColor=self.hovered?NSColor.selectedMenuItemTextColor:NSColor.labelColor;
    if(self.item.state==NSControlStateValueOn)[@"✓" drawAtPoint:NSMakePoint(20,4) withAttributes:@{NSFontAttributeName:[NSFont menuFontOfSize:0],NSForegroundColorAttributeName:self.hovered?NSColor.selectedMenuItemTextColor:NSColor.labelColor}];
}
- (void)perform:(SEL)action {
    [self.item.menu cancelTracking];[NSApp sendAction:action to:self.item.target from:self.item];
}
- (void)toggleCarView:(id)sender{[self perform:self.item.action];}
- (void)toggleCarMirror:(id)sender{[self perform:NSSelectorFromString(@"toggleCarMirror:")];}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    if(NSPointInRect(point,self.mirror.frame)){if(self.mirror.enabled)[self toggleCarMirror:self];}
    else [self toggleCarView:self];
}
@end

static void ThreeECarMenuUpdate(NSMenuItem *item,BOOL enabled,BOOL mirrored,BOOL starting,NSString *message) {
    item.state=enabled?NSControlStateValueOn:NSControlStateValueOff;
    ThreeECarMenuRow *row=[item.view isKindOfClass:ThreeECarMenuRow.class]?(id)item.view:nil;
    row.toggle.accessibilityLabel=enabled?@"Car View, on":@"Car View, off";
    row.mirror.state=mirrored?NSControlStateValueOn:NSControlStateValueOff;row.mirror.enabled=!starting;
    row.mirror.contentTintColor=mirrored?NSColor.systemMintColor:NSColor.secondaryLabelColor;
    row.mirror.toolTip=starting?@"Starting mirror…":[NSString stringWithFormat:@"%@%@",mirrored?@"Turn mirror off. ":@"Mirror screen for a window reflection. ",message?:@""];
    row.mirror.accessibilityValue=mirrored?@"On":@"Off";row.needsDisplay=YES;
}
static NSMenuItem *ThreeECarViewMenu(id target,BOOL enabled) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Car View" action:NSSelectorFromString(@"toggleCarView:") keyEquivalent:@""];
    item.identifier=@"local.musicstrip.carView";item.target=target;
    ThreeECarMenuRow *row=[[ThreeECarMenuRow alloc] initWithFrame:NSMakeRect(0,0,230,26)];row.item=item;item.view=row;
    ThreeECarMenuUpdate(item,enabled,NO,NO,nil);
    item.toolTip=@"Larger controls, neon pointer and a mirror for window reflections";
    return item;
}
