#import <AppKit/AppKit.h>

@class StripDownloadsAddon;
static StripDownloadsAddon *downloadsAddon;

@interface StripDownloadsAddon : NSObject
@property NSTimer *timer;
@property NSMutableDictionary<NSString *,NSString *> *snapshots;
+ (void)install;
+ (BOOL)isEnabled;
+ (BOOL)toggleFromMenu;
@end

@implementation StripDownloadsAddon

+ (void)install {
    if(!downloadsAddon) downloadsAddon=[StripDownloadsAddon new];
}
- (instancetype)init {
    if((self=[super init])) {
        NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
        if([defaults objectForKey:@"MoveDownloadsToDesktop"]==nil) [defaults setBool:NO forKey:@"MoveDownloadsToDesktop"];
        self.snapshots=[NSMutableDictionary dictionary];
        __weak StripDownloadsAddon *weakSelf=self;
        self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){ [weakSelf processDownloads]; }];
    }
    return self;
}
+ (BOOL)isEnabled {
    [self install];
    return [NSUserDefaults.standardUserDefaults boolForKey:@"MoveDownloadsToDesktop"];
}
+ (BOOL)toggleFromMenu {
    [self install];
    return [downloadsAddon toggle];
}
- (BOOL)toggle {
    BOOL enabled=![NSUserDefaults.standardUserDefaults boolForKey:@"MoveDownloadsToDesktop"];
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"MoveDownloadsToDesktop"];
    [self.snapshots removeAllObjects];
    if(enabled) [self processDownloads];
    return enabled;
}
- (NSString *)snapshotForURL:(NSURL *)url {
    NSFileManager *fm=NSFileManager.defaultManager;
    BOOL isDirectory=NO;
    if(![fm fileExistsAtPath:url.path isDirectory:&isDirectory]) return nil;
    unsigned long long total=0; NSUInteger count=0; NSTimeInterval newest=0;
    NSMutableArray<NSURL *> *items=[NSMutableArray arrayWithObject:url];
    if(isDirectory) {
        NSDirectoryEnumerator *enumerator=[fm enumeratorAtURL:url includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsDirectoryKey,NSURLFileSizeKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        for(NSURL *child in enumerator) [items addObject:child];
    }
    for(NSURL *item in items) {
        NSDictionary *attributes=[fm attributesOfItemAtPath:item.path error:nil];
        if(!attributes) continue;
        count++;
        if([attributes[NSFileType] isEqual:NSFileTypeRegular]) total += [attributes[NSFileSize] unsignedLongLongValue];
        newest=MAX(newest,[attributes[NSFileModificationDate] timeIntervalSince1970]);
    }
    return [NSString stringWithFormat:@"%lu:%llu:%.3f",(unsigned long)count,total,newest];
}
- (NSURL *)desktopURLForName:(NSString *)name {
    NSURL *desktop=[NSFileManager.defaultManager URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *candidate=[desktop URLByAppendingPathComponent:name];
    if(![NSFileManager.defaultManager fileExistsAtPath:candidate.path]) return candidate;
    NSString *base=[name stringByDeletingPathExtension], *extension=name.pathExtension;
    for(NSUInteger suffix=2;;suffix++) {
        NSString *numbered=[NSString stringWithFormat:@"%@ (%lu)%@",base,(unsigned long)suffix,extension.length ? [@"." stringByAppendingString:extension] : @""];
        candidate=[desktop URLByAppendingPathComponent:numbered];
        if(![NSFileManager.defaultManager fileExistsAtPath:candidate.path]) return candidate;
    }
}
- (void)processDownloads {
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"MoveDownloadsToDesktop"]) return;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *downloads=[fm URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    NSArray<NSURL *> *entries=[fm contentsOfDirectoryAtURL:downloads includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableSet<NSString *> *present=[NSMutableSet set];
    for(NSURL *url in entries) {
        NSString *path=url.path, *name=url.lastPathComponent.lowercaseString;
        [present addObject:path];
        if([name hasSuffix:@".crdownload"] || [name hasSuffix:@".download"] || [name hasSuffix:@".part"] || [name hasSuffix:@".tmp"]) {
            [self.snapshots removeObjectForKey:path]; continue;
        }
        NSString *snapshot=[self snapshotForURL:url];
        if(!snapshot) { [self.snapshots removeObjectForKey:path]; continue; }
        NSString *previous=self.snapshots[path]; self.snapshots[path]=snapshot;
        if(previous && [previous isEqualToString:snapshot]) {
            NSError *error=nil;
            NSURL *destination=[self desktopURLForName:url.lastPathComponent];
            if([fm moveItemAtURL:url toURL:destination error:&error]) [self.snapshots removeObjectForKey:path];
            else NSLog(@"3£ Downloads add-on could not move %@: %@",url.lastPathComponent,error.localizedDescription);
        }
    }
    for(NSString *path in self.snapshots.allKeys.copy) if(![present containsObject:path]) [self.snapshots removeObjectForKey:path];
}
@end
