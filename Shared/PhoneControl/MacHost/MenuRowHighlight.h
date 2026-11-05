// SPDX-License-Identifier: MIT
#pragma once
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static BOOL ThreeEMenuRowHighlighted(NSMenuItem *item) {
    return item.menu && item.menu.highlightedItem==item;
}
static void ThreeEMenuRowRedraw(NSView *view) {
    view.needsDisplay=YES;
    for(NSView *child in view.subviews) ThreeEMenuRowRedraw(child);
}
static void ThreeEMenuRowsRedraw(NSMenu *menu) {
    // Native and custom items share one selection. Repaint nested labels too,
    // rather than leaving independent hover flags or old blue backgrounds.
    for(NSMenuItem *other in menu.itemArray) if(other.view) ThreeEMenuRowRedraw(other.view);
}

// Preserve the menu's existing delegate while observing native selection
// changes, including movement onto ordinary items and closing/reopening.
@interface ThreeEMenuRowObserver : NSObject <NSMenuDelegate>
@property (weak) id<NSMenuDelegate> original;
@end
@implementation ThreeEMenuRowObserver
- (BOOL)respondsToSelector:(SEL)selector { return [super respondsToSelector:selector] || [self.original respondsToSelector:selector]; }
- (id)forwardingTargetForSelector:(SEL)selector { return self.original; }
- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item {
    ThreeEMenuRowsRedraw(menu);
    if([self.original respondsToSelector:_cmd]) [self.original menu:menu willHighlightItem:item];
}
- (void)menuWillOpen:(NSMenu *)menu {
    ThreeEMenuRowsRedraw(menu);
    if([self.original respondsToSelector:_cmd]) [self.original menuWillOpen:menu];
}
- (void)menuDidClose:(NSMenu *)menu {
    ThreeEMenuRowsRedraw(menu);
    if([self.original respondsToSelector:_cmd]) [self.original menuDidClose:menu];
}
@end
static void ThreeEMenuRowObserve(NSMenu *menu) {
    if(!menu || [menu.delegate isKindOfClass:ThreeEMenuRowObserver.class]) return;
    ThreeEMenuRowObserver *observer=[ThreeEMenuRowObserver new];observer.original=menu.delegate;
    objc_setAssociatedObject(menu,@selector(ThreeEMenuRowObserve),observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    menu.delegate=observer;
}
static void ThreeEMenuRowRefresh(NSMenuItem *item) {
    ThreeEMenuRowObserve(item.menu);ThreeEMenuRowsRedraw(item.menu);
}
