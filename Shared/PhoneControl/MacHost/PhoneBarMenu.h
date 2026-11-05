// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import "MenuRowHighlight.h"

@interface ThreeEPhoneBarMenuRow : NSView
@property (weak) NSMenuItem *menuItem;
@property (weak) id actionTarget;
@property SEL hoverAction;
@property SEL leaveAction;
@property BOOL selectionBackgroundProvidedByParent;
@end

@implementation ThreeEPhoneBarMenuRow
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];ThreeEMenuRowObserve(self.menuItem.menu);
    for(NSTrackingArea *area in self.trackingAreas)[self removeTrackingArea:area];
    NSTrackingArea *area=[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:area];
}
- (void)mouseEntered:(NSEvent *)event { ThreeEMenuRowRefresh(self.menuItem);if(self.hoverAction)[NSApp sendAction:self.hoverAction to:self.actionTarget from:self]; }
- (void)mouseExited:(NSEvent *)event { ThreeEMenuRowRefresh(self.menuItem);if(self.leaveAction)[NSApp sendAction:self.leaveAction to:self.actionTarget from:self]; }
- (void)mouseDown:(NSEvent *)event {
    self.menuItem.state=self.menuItem.state==NSControlStateValueOn?NSControlStateValueOff:NSControlStateValueOn;
    [self setNeedsDisplay:YES];
    if(self.menuItem.action)[NSApp sendAction:self.menuItem.action to:self.menuItem.target from:self.menuItem];
    [self.menuItem.menu cancelTracking];
}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL highlighted=ThreeEMenuRowHighlighted(self.menuItem);
    if(highlighted && !self.selectionBackgroundProvidedByParent) {
        [NSColor.selectedContentBackgroundColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,5,1) xRadius:4 yRadius:4] fill];
    }
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont menuFontOfSize:0],NSForegroundColorAttributeName:highlighted?NSColor.selectedMenuItemTextColor:NSColor.labelColor};
    // NSMenu's custom-view origin starts at the menu's left edge, while native
    // item titles start after the standard checkmark gutter. Match that gutter.
    [self.menuItem.title drawAtPoint:NSMakePoint(30,3) withAttributes:attributes];
    if(self.menuItem.state==NSControlStateValueOn)[@"✓" drawAtPoint:NSMakePoint(12,3) withAttributes:attributes];
}
@end

static NSMenuItem *ThreeEPhoneBarMenu(id target) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Phone Bar" action:NSSelectorFromString(@"togglePhoneBar:") keyEquivalent:@""];
    item.identifier=@"local.musicstrip.phone";item.target=target;item.state=NSControlStateValueOn;
    ThreeEPhoneBarMenuRow *row=[[ThreeEPhoneBarMenuRow alloc] initWithFrame:NSMakeRect(0,0,210,24)];
    row.menuItem=item;row.actionTarget=target;row.hoverAction=NSSelectorFromString(@"hoverPhoneBar:");row.leaveAction=NSSelectorFromString(@"hidePhoneBarQR:");
    item.view=row;
    return item;
}
