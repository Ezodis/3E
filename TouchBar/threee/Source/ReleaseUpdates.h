// Check this app's public releases, never the vendor engine's old XML feed.
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
static NSString *const StripReleaseVersion=@"3.0.114";
static NSString *StripInstalledVersion(void) {
    NSString *path=NSBundle.mainBundle.bundlePath;
    while(path.length>1) {
        NSDictionary *info=[NSBundle bundleWithPath:path].infoDictionary;
        if([info[@"CFBundleIdentifier"] isEqual:@"local.musicstrip.app"] && [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class])
            return info[@"CFBundleShortVersionString"];
        path=path.stringByDeletingLastPathComponent;
    }
    return StripReleaseVersion;
}
static NSString *const StripReleasesAPI=@"https://api.github.com/repos/Ezodis/3E/releases?per_page=100";
static NSString *const StripReleasesPage=@"https://github.com/Ezodis/3E/releases";
static BOOL stripUpdateChecking;
static BOOL stripUpdateInstalling;
static int stripInstallLock=-1;
static BOOL StripAcquireInstallLock(void) {
    if(stripInstallLock>=0) return YES;
    NSString *directory=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"3E"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    int descriptor=open([[directory stringByAppendingPathComponent:@"module-operation.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_CLOEXEC,0600);
    if(descriptor<0) return NO;
    if(flock(descriptor,LOCK_EX|LOCK_NB)!=0) { close(descriptor); return NO; }
    stripInstallLock=descriptor; return YES;
}
static NSTimer *stripUpdateTimer;
static NSString *const StripAutomaticUpdatesKey=@"StripAutomaticUpdatesEnabled";
static BOOL StripAutomaticUpdatesEnabled(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if([defaults objectForKey:StripAutomaticUpdatesKey]==nil) [defaults setBool:YES forKey:StripAutomaticUpdatesKey];
    return [defaults boolForKey:StripAutomaticUpdatesKey];
}
static void StripSetAutomaticUpdates(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:StripAutomaticUpdatesKey];
}
// ---- Edition: one source of truth ------------------------------------------
// The installed 3E.app's Info.plist key ThreeEIncludesTouchTab (stamped by
// build.sh, asserted by release.py) is the ONLY authority for the edition.
//
// History: this header is compiled into three binaries — the main app (built
// with -DSTRIP_COMBINED_TOUCHTAB in the combined edition), the MIDI helper's
// bridge dylib (always built WITHOUT that flag), and tests. The updater and
// the menu run inside the bridge, so a compile-time or environment check made
// the combined app's bridge think it was Touch Bar-only: it downloaded
// TouchBar.zip and replaced the combined app, and Touch Tab vanished from the
// menu. Reading the bundle's own Info.plist gives the same answer in every
// process, whatever flags it was built with.
static NSString *const StripAppBundleID=@"local.musicstrip.app";
static NSString *const StripEditionMarkerKey=@"ThreeEEdition";
// Walk up from any process's bundle (main app, MIDI helper, Apps helper) to
// the enclosing 3E.app. Reads Info.plist directly; NSBundle caches.
static NSString *StripAppBundlePathFrom(NSString *path) {
    while(path.length>1) {
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Contents/Info.plist"]];
        if([info[@"CFBundleIdentifier"] isEqual:StripAppBundleID]) return path;
        path=path.stringByDeletingLastPathComponent;
    }
    return nil;
}
static NSString *StripAppBundlePath(void) { return StripAppBundlePathFrom(NSBundle.mainBundle.bundlePath); }
static NSArray<NSString *> *StripModulesAtPath(NSString *path) {
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if([info[@"ThreeEModules"] isKindOfClass:NSArray.class]) return info[@"ThreeEModules"];
    return [info[@"ThreeEIncludesTouchTab"] boolValue] ? @[@"touchbar",@"touchtab",@"phone"] : @[@"touchbar",@"phone"];
}
static NSArray<NSString *> *StripInstalledModules(void) {
#if defined(STRIP_TEST_EDITION_COMBINED)
    return @[@"touchbar",@"touchtab",@"phone"];
#elif defined(STRIP_TEST_EDITION_TOUCHBAR)
    return @[@"touchbar",@"phone"];
#endif
    return StripModulesAtPath(StripAppBundlePath());
}
static BOOL StripHasModule(NSString *module) { return [StripInstalledModules() containsObject:module]; }
static BOOL StripUnifiedModules(void) {
    return [[[NSDictionary dictionaryWithContentsOfFile:[StripAppBundlePath() stringByAppendingPathComponent:@"Contents/Info.plist"]] objectForKey:@"ThreeEModuleSchema"] integerValue]==1;
}
static NSArray<NSString *> *stripRequestedModules;
static BOOL StripModuleOperation;
static BOOL StripBundleIncludesTouchTab(NSString *appPath) {
    if(!appPath) return NO;
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
    return [info[@"ThreeEIncludesTouchTab"] boolValue];
}
static BOOL StripInstalledIncludesTouchTab(void) {
#if defined(STRIP_TEST_EDITION_COMBINED)
    return YES; // Tests run outside an app bundle.
#elif defined(STRIP_TEST_EDITION_TOUCHBAR)
    return NO;
#endif
    return StripBundleIncludesTouchTab(StripAppBundlePath());
}
// Read the main app's defaults from any process (helper or main) without
// relying on which NSUserDefaults domain this process owns.
static id StripAppPreference(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)StripAppBundleID));
}
// One-time recovery for installs the old bug already swapped to the Touch
// Bar-only edition: if this Mac has run the combined edition before, and the
// standalone TouchTab app is not installed (never run two gesture engines),
// the updater moves back to the combined edition.
static BOOL StripPreviouslyCombined(void) {
#if defined(STRIP_TEST_EDITION_COMBINED) || defined(STRIP_TEST_EDITION_TOUCHBAR)
    return NO; // Tests never read this Mac's real preferences.
#endif
    if([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"ris58h.Touch-Tab"]) return NO;
    return [StripAppPreference(StripEditionMarkerKey) isEqual:@"combined"] ||
        StripAppPreference(@"TouchTabGesturesEnabled")!=nil ||
        StripAppPreference(@"WindowAccessRuntimeState")!=nil;
}
static BOOL StripResolveCombined(BOOL bundleIncludesTouchTab,BOOL previouslyCombined) {
    return bundleIncludesTouchTab || previouslyCombined;
}
static BOOL StripCombinedRelease(void) {
    static BOOL combined; static dispatch_once_t once;
    dispatch_once(&once,^{ combined=StripResolveCombined(StripInstalledIncludesTouchTab(),StripPreviouslyCombined()); });
    return StripUnifiedModules() || StripModuleOperation || combined;
}
// Install when the release is newer, or when it is the same version but the
// installed bundle is the wrong edition (recovery from the old swap).
static BOOL StripShouldInstall(NSString *releaseVersion,NSString *installedVersion,BOOL installedIncludesTouchTab,BOOL wantCombined) {
    if(!releaseVersion) return NO;
    NSComparisonResult order=[releaseVersion compare:installedVersion options:NSNumericSearch];
    if(order==NSOrderedDescending) return YES;
    return order==NSOrderedSame && installedIncludesTouchTab!=wantCombined;
}
static NSDictionary *StripValidRelease(id value) {
    if(![value isKindOfClass:NSDictionary.class] || [value[@"draft"] boolValue] || [value[@"prerelease"] boolValue]) return nil;
    NSString *tag=value[@"tag_name"];
    NSString *pattern=StripCombinedRelease() ? @"^combined-v[0-9]+\\.[0-9]+\\.[0-9]+$" : @"^touchbar-v[0-9]+\\.[0-9]+\\.[0-9]+$";
    if(![tag isKindOfClass:NSString.class] || ![[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil] numberOfMatchesInString:tag options:0 range:NSMakeRange(0,tag.length)]) return nil;
    NSString *version=[tag substringFromIndex:10];
    if(![value[@"assets"] isKindOfClass:NSArray.class]) return nil;
    for(id asset in value[@"assets"]) {
        NSString *assetName=StripCombinedRelease() ? @"3E-Combined.zip" : @"TouchBar.zip";
        if(![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:assetName]) continue;
        NSString *url=asset[@"browser_download_url"];
        NSString *expected=[NSString stringWithFormat:@"https://github.com/Ezodis/3E/releases/download/%@/%@",tag,assetName];
        if([url isKindOfClass:NSString.class] && [url isEqual:expected]) return @{@"tag":tag,@"version":version,@"url":url};
    }
    return nil;
}
static NSDictionary *StripNewestRelease(id values) {
    if(![values isKindOfClass:NSArray.class]) return nil;
    NSDictionary *newest=nil;
    for(id value in values) {
        NSDictionary *release=StripValidRelease(value);
        if(release && (!newest || [release[@"version"] compare:newest[@"version"] options:NSNumericSearch]==NSOrderedDescending)) newest=release;
    }
    return newest;
}
static void StripNotify(NSString *title,NSString *message) {
    NSUserNotification *notification=[NSUserNotification new];
    notification.title=title; notification.informativeText=message;
    [NSUserNotificationCenter.defaultUserNotificationCenter deliverNotification:notification];
}
static BOOL StripRunTool(NSString *path,NSArray<NSString *> *arguments) {
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:path]; task.arguments=arguments;
    task.standardOutput=[NSFileHandle fileHandleWithNullDevice]; task.standardError=[NSFileHandle fileHandleWithNullDevice];
    @try { [task launchAndReturnError:nil]; [task waitUntilExit]; return task.terminationStatus==0; }
    @catch(NSException *exception) { NSLog(@"3E update tool failed: %@",exception.reason); return NO; }
}
static void StripFinishUpdateFailure(NSString *message,BOOL foreground) {
    if(stripInstallLock>=0) { close(stripInstallLock); stripInstallLock=-1; }
    stripUpdateInstalling=NO; StripModuleOperation=NO; stripRequestedModules=nil;
    NSLog(@"3E update failed: %@",message);
    if(foreground) StripNotify(@"3E update failed",message);
}
static void StripInstallArchive(NSString *downloadedArchive,NSDictionary *release,BOOL foreground) {
            NSString *bundlePath=NSBundle.mainBundle.bundlePath;
            while(bundlePath.length>1 && ![[NSBundle bundleWithPath:bundlePath].bundleIdentifier isEqual:@"local.musicstrip.app"]) bundlePath=bundlePath.stringByDeletingLastPathComponent;
            NSString *parent=bundlePath.stringByDeletingLastPathComponent;
            NSString *work=[parent stringByAppendingPathComponent:[NSString stringWithFormat:@".3E-update-%@",NSUUID.UUID.UUIDString]];
            NSError *fileError=nil;
            if(![NSFileManager.defaultManager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:&fileError]) {
                [[NSFileManager defaultManager] removeItemAtPath:downloadedArchive error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(fileError.localizedDescription,foreground); }); return;
            }
            NSString *archive=[work stringByAppendingPathComponent:@"release.zip"];
            NSString *extract=[work stringByAppendingPathComponent:@"extract"];
            BOOL prepared=[[NSFileManager defaultManager] copyItemAtPath:downloadedArchive toPath:archive error:&fileError] &&
                [[NSFileManager defaultManager] createDirectoryAtPath:extract withIntermediateDirectories:YES attributes:nil error:&fileError] &&
                StripRunTool(@"/usr/bin/ditto",@[@"-x",@"-k",archive,extract]);
            [[NSFileManager defaultManager] removeItemAtPath:downloadedArchive error:nil];
            NSString *candidate=[extract stringByAppendingPathComponent:@"3E.app"];
            NSString *infoPath=[candidate stringByAppendingPathComponent:@"Contents/Info.plist"];
            NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *expectedID=StripCombinedRelease() ? @"combined-v" : @"touchbar-v";
            BOOL valid=prepared && (!(StripUnifiedModules() || StripModuleOperation) || [info[@"ThreeEModuleSchema"] integerValue]==1) && [info[@"CFBundleIdentifier"] isEqual:@"local.musicstrip.app"] &&
                [info[@"CFBundleShortVersionString"] isEqual:release[@"version"]] &&
                ([release[@"local"] boolValue] || ([release[@"tag"] hasPrefix:expectedID] && [info[@"ThreeEIncludesTouchTab"] boolValue]==StripCombinedRelease())) &&
                StripRunTool(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",candidate]);
            if(valid && (StripUnifiedModules() || StripModuleOperation)) {
                // Use our installed configurator, never execute downloaded scripts
                // until the candidate has passed identity/version/signature checks.
                NSString *configure=[bundlePath stringByAppendingPathComponent:@"Contents/Resources/ConfigureModules.sh"];
                NSArray *modules=stripRequestedModules ?: StripInstalledModules();
                valid=StripRunTool(@"/bin/zsh",@[configure,candidate,[modules componentsJoinedByString:@","]]);
            }
            if(!valid) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(fileError.localizedDescription ?: @"The downloaded app did not pass version, edition, or signature checks.",foreground); }); return;
            }
            NSString *installerSource=[candidate stringByAppendingPathComponent:@"Contents/Resources/UpdateInstaller.sh"];
            NSString *installerCopy=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3E-update-installer-%@.sh",NSUUID.UUID.UUIDString]];
            if(![[NSFileManager defaultManager] copyItemAtPath:installerSource toPath:installerCopy error:&fileError]) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(fileError.localizedDescription ?: @"The update installer is missing.",foreground); }); return;
            }
            chmod(installerCopy.fileSystemRepresentation,0700);
            pid_t helperPID=getpid(),mainPID=0;
            for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.musicstrip.app"]) if(!app.terminated && [app.bundleURL.path isEqual:bundlePath]) { mainPID=app.processIdentifier; break; }
            if(!mainPID) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil]; [[NSFileManager defaultManager] removeItemAtPath:installerCopy error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(@"The main 3E app could not be found.",foreground); }); return;
            }
            NSTask *installer=[NSTask new]; installer.executableURL=[NSURL fileURLWithPath:@"/bin/zsh"];
            installer.arguments=@[installerCopy,candidate,bundlePath,work,[NSString stringWithFormat:@"%d",mainPID],[NSString stringWithFormat:@"%d",helperPID]];
            installer.standardOutput=[NSFileHandle fileHandleWithNullDevice]; installer.standardError=[NSFileHandle fileHandleWithNullDevice];
            NSError *launchError=nil;
            if(![installer launchAndReturnError:&launchError]) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil]; [[NSFileManager defaultManager] removeItemAtPath:installerCopy error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(launchError.localizedDescription ?: @"The update installer could not start.",foreground); }); return;
            }
            dispatch_async(dispatch_get_main_queue(),^{
                StripNotify(@"Installing 3E update",[NSString stringWithFormat:@"Version %@ will install now. 3E will restart when installation finishes.",release[@"version"]]);
                for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:StripAppBundleID]) if(app.processIdentifier==mainPID && mainPID!=getpid()) [app terminate];
                [NSApp terminate:nil];
            });
}
static void StripDownloadAndInstall(NSDictionary *release,BOOL foreground) {
    if(stripUpdateInstalling) return;
    if(!StripAcquireInstallLock()) { StripFinishUpdateFailure(@"Another 3E module change or update is in progress. Try again when it finishes.",foreground); return; }
    stripUpdateInstalling=YES;
    NSURL *url=[NSURL URLWithString:release[@"url"]];
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest=600; configuration.timeoutIntervalForResource=3600;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDownloadTask *task=[session downloadTaskWithURL:url completionHandler:^(NSURL *location,NSURLResponse *response,NSError *error) {
        NSString *downloadedArchive=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3E-release-%@.zip",NSUUID.UUID.UUIDString]];
        NSError *downloadCopyError=nil;
        if(!error && location && [(NSHTTPURLResponse *)response statusCode]==200 &&
           ![[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:downloadedArchive] error:&downloadCopyError]) error=downloadCopyError;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            if(error || !location || [(NSHTTPURLResponse *)response statusCode]!=200) {
                [[NSFileManager defaultManager] removeItemAtPath:downloadedArchive error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(error.localizedDescription ?: @"The release download did not complete.",foreground); }); return;
            }
            StripInstallArchive(downloadedArchive,release,foreground);
        });
    }];
    [task resume];
}
static void StripChangeModules(NSArray<NSString *> *modules,BOOL downloading) {
    if(stripUpdateInstalling || stripUpdateChecking) { StripNotify(@"3E is busy",@"Wait for the current update or module change to finish, then try again."); return; }
    if(!StripAcquireInstallLock()) { StripNotify(@"3E is busy",@"An update or module change is already in progress."); return; }
    stripRequestedModules=[modules copy]; StripModuleOperation=YES;
    if(!downloading) {
        stripUpdateInstalling=YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSString *archive=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3E-modules-%@.zip",NSUUID.UUID.UUIDString]];
            if(!StripRunTool(@"/usr/bin/ditto",@[@"-c",@"-k",@"--keepParent",StripAppBundlePath(),archive])) {
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(@"Could not stage the module change.",YES); }); return;
            }
            StripInstallArchive(archive,@{@"local":@YES,@"version":StripInstalledVersion()},YES);
        });
        return;
    }
    stripUpdateChecking=YES;
    StripNotify(@"Installing 3E module",@"Downloading modules. 3E will restart when installation finishes.");
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:StripReleasesAPI]];
    request.timeoutInterval=30;
    [request setValue:@"3E" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSDictionary *release=nil;
        if(!error && [(NSHTTPURLResponse *)response statusCode]==200 && data) release=StripNewestRelease([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        dispatch_async(dispatch_get_main_queue(),^{
            stripUpdateChecking=NO;
            if(!release || [release[@"version"] compare:StripInstalledVersion() options:NSNumericSearch]==NSOrderedAscending) {
                StripFinishUpdateFailure(@"No compatible module download is available yet. Try again after the current release is published.",YES); return;
            }
            StripDownloadAndInstall(release,YES);
        });
    }] resume];
}
static BOOL StripInstallMissingModule(NSString *module) {
    if(StripHasModule(module)) return NO;
    NSMutableArray *modules=[StripInstalledModules() mutableCopy]; [modules addObject:module];
    StripChangeModules(modules,YES); return YES;
}
@interface ThreeEModuleActions : NSObject
+ (void)changeModule:(NSMenuItem *)sender;
@end
@implementation ThreeEModuleActions
+ (void)changeModule:(NSMenuItem *)sender {
    NSString *module=sender.representedObject;
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:StripAppBundleID] && NSClassFromString(@"ThreeEMidiBridge")) {
        fprintf(stdout,"MODULE_CHANGE %s\n",module.UTF8String); fflush(stdout); return;
    }
    if(StripInstallMissingModule(module)) return;
    NSMutableArray *modules=[StripInstalledModules() mutableCopy]; [modules removeObject:module];
    StripChangeModules(modules,NO);
}
@end
static NSMenuItem *StripModuleSettingsMenu(void) {
    NSMenuItem *settings=[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    settings.identifier=@"local.musicstrip.modules";
    settings.image=[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Manage modules"];
    settings.toolTip=@"Install or uninstall 3E modules";
    NSMenu *menu=[NSMenu new];
    for(NSArray *entry in @[@[@"phone",@"Phone Bar"],@[@"touchtab",@"Touch Tab"],@[@"touchbar",@"Touch Bar"]]) {
        BOOL installed=StripHasModule(entry[0]);
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ %@…",installed?@"Uninstall":@"Install",entry[1]] action:@selector(changeModule:) keyEquivalent:@""];
        item.representedObject=entry[0]; item.target=ThreeEModuleActions.class; [menu addItem:item];
    }
    settings.submenu=menu; return settings;
}
static void StripCheckRelease(BOOL foreground) {
    if(stripUpdateChecking || stripUpdateInstalling) return;
    stripUpdateChecking=YES;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:StripReleasesAPI]];
    request.timeoutInterval=20;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"3E-TouchBar" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSDictionary *release=nil;
        if(!error && [(NSHTTPURLResponse *)response statusCode]==200)
            release=StripNewestRelease([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        dispatch_async(dispatch_get_main_queue(),^{
            stripUpdateChecking=NO;
            NSString *installed=StripInstalledVersion();
            BOOL newer=release && StripShouldInstall(release[@"version"],installed,StripUnifiedModules() ? YES : StripInstalledIncludesTouchTab(),StripCombinedRelease());
            // New releases install as soon as they are found, even while the Mac is in use.
            if(newer && StripAutomaticUpdatesEnabled()) {
                if(!foreground) StripNotify(@"Updating 3£",[NSString stringWithFormat:@"Installing version %@; 3£ will reopen in a few seconds.",release[@"version"]]);
                StripDownloadAndInstall(release,foreground); return;
            }
            if(!foreground) return;
            NSAlert *alert=[NSAlert new];
            alert.messageText=newer ? @"A 3E update is available" : (release ? @"3E is up to date" : @"Could not check for updates");
            alert.informativeText=newer ? [NSString stringWithFormat:@"Version %@ is available. Install it now? 3E will restart after the update is ready.",release[@"version"]] : (release ? [NSString stringWithFormat:@"Installed version: %@. TouchBar updates come from Ezodis/3E.",installed] : @"Check your connection and try again. No app files were changed.");
            [alert addButtonWithTitle:newer ? @"Install" : @"OK"];
            if(newer) [alert addButtonWithTitle:@"Later"];
            [alert addButtonWithTitle:@"View Releases"];
            [NSApp activateIgnoringOtherApps:YES];
            NSModalResponse choice=[alert runModal];
            if(newer && choice==NSAlertFirstButtonReturn)
                StripDownloadAndInstall(release,YES);
            else if(choice==(newer ? NSAlertThirdButtonReturn : NSAlertSecondButtonReturn))
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:StripReleasesPage]];
        });
    }] resume];
}
static void StripUpdateForeground(id self,SEL selector) { StripCheckRelease(NO); }
static void StripUpdateBackground(id self,SEL selector) { StripCheckRelease(NO); }
static void StripToggleAutomaticUpdates(id self,SEL selector,id sender) {
    BOOL enabled=!StripAutomaticUpdatesEnabled(); StripSetAutomaticUpdates(enabled);
    if(enabled) StripCheckRelease(NO);
}
// Restart: quit and reopen the same app bundle. Settings live in user
// defaults (Phone Bar and Touch Tab on/off, players, automatic updates), so
// the new instance comes back exactly as it was left.
static void StripRelaunch(void) {
    NSString *bundlePath=NSBundle.mainBundle.bundlePath;
    while(bundlePath.length>1 && ![[NSBundle bundleWithPath:bundlePath].bundleIdentifier isEqual:@"local.musicstrip.app"]) bundlePath=bundlePath.stringByDeletingLastPathComponent;
    if(bundlePath.length<=1) bundlePath=NSBundle.mainBundle.bundlePath;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/bin/sh"];
    // Restart everything: this process plus the main 3E app (when Restart is
    // chosen from the MIDI helper's menu). Wait for all of them to exit, then
    // reopen 3E.app, which starts its helpers again.
    NSMutableArray<NSRunningApplication *> *others=[NSMutableArray array];
    NSMutableString *pids=[NSMutableString stringWithFormat:@"%d",getpid()];
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:StripAppBundleID]) {
        if(app.terminated || app.processIdentifier==getpid()) continue;
        [others addObject:app]; [pids appendFormat:@" %d",app.processIdentifier];
    }
    task.arguments=@[@"-c",@"for p in $1; do while /bin/kill -0 \"$p\" 2>/dev/null; do /bin/sleep 0.2; done; done; /usr/bin/open \"$2\"",@"3E-restart",pids,bundlePath];
    task.standardOutput=[NSFileHandle fileHandleWithNullDevice]; task.standardError=[NSFileHandle fileHandleWithNullDevice];
    NSError *error=nil;
    if(![task launchAndReturnError:&error]) { StripNotify(@"3E could not restart",error.localizedDescription ?: @"The relaunch helper did not start."); return; }
    for(NSRunningApplication *app in others) {
        [app terminate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ if(!app.terminated) [app forceTerminate]; });
    }
    if(others.count) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [NSApp terminate:nil]; });
    else [NSApp terminate:nil];
}
// Restart checks for an update first: a newer release is installed (its
// installer reopens 3£); otherwise, or when offline, 3£ simply relaunches.
static void StripRestart(void) {
    if(stripUpdateInstalling || stripUpdateChecking) return;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:StripReleasesAPI]];
    request.timeoutInterval=15;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"3E-TouchBar" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSDictionary *release=nil;
        if(!error && data && [(NSHTTPURLResponse *)response statusCode]==200)
            release=StripNewestRelease([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        dispatch_async(dispatch_get_main_queue(),^{
            if(release && StripShouldInstall(release[@"version"],StripInstalledVersion(),StripUnifiedModules() ? YES : StripInstalledIncludesTouchTab(),StripCombinedRelease())) {
                StripNotify(@"Updating 3£",[NSString stringWithFormat:@"Installing version %@; 3£ will reopen when it is ready.",release[@"version"]]);
                StripDownloadAndInstall(release,YES);
                return;
            }
            StripRelaunch();
        });
    }] resume];
}
static BOOL StripInstallUpdateHooks(void) {
    Class cls=NSClassFromString(@"AppDelegate");
    Method background=class_getInstanceMethod(cls,NSSelectorFromString(@"startUpdateCheckBackground"));
    Method foreground=class_getInstanceMethod(cls,NSSelectorFromString(@"startUpdateCheckForeground"));
    if(!background || !foreground) return NO;
    method_setImplementation(background,(IMP)StripUpdateBackground);
    method_setImplementation(foreground,(IMP)StripUpdateForeground);
    StripAutomaticUpdatesEnabled();
    if(!stripUpdateTimer) {
        stripUpdateTimer=[NSTimer scheduledTimerWithTimeInterval:10*60 repeats:YES block:^(NSTimer *timer){ StripCheckRelease(NO); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{ StripCheckRelease(NO); });
    }
    return YES;
}
