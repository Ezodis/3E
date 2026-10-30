// SPDX-License-Identifier: MIT
#pragma once
#import <AppKit/AppKit.h>

static NSMenuItem *ThreeECarViewMenu(id target,BOOL enabled) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Car View…" action:NSSelectorFromString(@"openCarView:") keyEquivalent:@""];
    item.identifier=@"local.musicstrip.carView";item.target=target;
    item.state=enabled?NSControlStateValueOn:NSControlStateValueOff;
    item.toolTip=@"Larger controls, neon pointer and a mirror for window reflections";
    return item;
}
