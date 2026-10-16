// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
static NSMenuItem *ThreeEPhoneBarMenu(id target) {
    NSMenuItem *module=[[NSMenuItem alloc] initWithTitle:@"Phone Bar" action:nil keyEquivalent:@""];
    module.identifier=@"local.musicstrip.phone";
    module.submenu=[[NSMenu alloc] initWithTitle:@"Phone Bar"];
    for(NSArray *row in @[@[@"Show pairing QR…",@"openPhone:"],
                          @[@"Copy pairing link",@"copyPhone:"],
                          @[@"Stop Phone Bar",@"stopPhone:"]]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:row[0] action:NSSelectorFromString(row[1]) keyEquivalent:@""];
        item.target=target;[module.submenu addItem:item];
    }
    return module;
}
