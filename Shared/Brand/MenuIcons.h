// SPDX-License-Identifier: MIT
#pragma once
#import <AppKit/AppKit.h>

// Both platforms render this same vector artwork. Edit menu-icons.json once.
static NSImage *ThreeEMenuIcon(NSString *name) {
    static NSDictionary *artwork;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path=[NSBundle.mainBundle pathForResource:@"menu-icons" ofType:@"json"];
#ifdef THREEE_MENU_ICON_TESTS
        path=[[[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"menu-icons.json"];
#endif
        NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
        artwork=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSCAssert(artwork,@"Shared menu icons were not packaged");
    });
    NSDictionary *icon=artwork[@"icons"][name];
    if(!icon)return nil;
    NSImage *image=[NSImage imageWithSize:NSMakeSize(16,16) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform=[NSAffineTransform transform];
        [transform translateXBy:rect.origin.x yBy:rect.origin.y];
        [transform scaleXBy:rect.size.width/[artwork[@"viewBox"] doubleValue] yBy:rect.size.height/[artwork[@"viewBox"] doubleValue]];
        [transform concat];[NSColor.blackColor setStroke];
        for(NSArray *commands in icon[@"paths"]) {
            NSBezierPath *path=[NSBezierPath bezierPath];
            path.lineWidth=[artwork[@"strokeWidth"] doubleValue];path.lineCapStyle=NSLineCapStyleRound;path.lineJoinStyle=NSLineJoinStyleRound;
            for(NSArray *command in commands) {
                NSString *kind=command[0];
                if([kind isEqual:@"M"])[path moveToPoint:NSMakePoint([command[1] doubleValue],[command[2] doubleValue])];
                else if([kind isEqual:@"L"])[path lineToPoint:NSMakePoint([command[1] doubleValue],[command[2] doubleValue])];
                else if([kind isEqual:@"C"])[path curveToPoint:NSMakePoint([command[5] doubleValue],[command[6] doubleValue]) controlPoint1:NSMakePoint([command[1] doubleValue],[command[2] doubleValue]) controlPoint2:NSMakePoint([command[3] doubleValue],[command[4] doubleValue])];
                else if([kind isEqual:@"Z"])[path closePath];
                else NSCAssert(NO,@"Unknown shared icon command");
            }
            [path stroke];
        }
        for(NSArray *circle in icon[@"circles"]) {
            CGFloat x=[circle[0] doubleValue],y=[circle[1] doubleValue],r=[circle[2] doubleValue];
            NSBezierPath *path=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x-r,y-r,2*r,2*r)];
            path.lineWidth=[artwork[@"strokeWidth"] doubleValue];[path stroke];
        }
        [NSGraphicsContext restoreGraphicsState];return YES;
    }];
    image.template=YES;image.accessibilityDescription=name;return image;
}
