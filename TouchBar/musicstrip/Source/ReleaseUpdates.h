// Check this app's public releases, never the vendor engine's old XML feed.
#import <sys/stat.h>
#import <unistd.h>
static NSString *const StripReleaseVersion=@"3.0.12";
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
static BOOL StripCombinedRelease(void) {
#ifdef STRIP_COMBINED_TOUCHTAB
    // The edition is fixed when the main executable is built. The runtime
    // environment flag is passed only to helper processes, so consulting it
    // here made the combined app look like Touch Bar-only to its updater.
    return YES;
#else
    return NO;
#endif
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
    @catch(NSException *exception) { NSLog(@"3£ update tool failed: %@",exception.reason); return NO; }
}
static void StripFinishUpdateFailure(NSString *message,BOOL foreground) {
    stripUpdateInstalling=NO;
    NSLog(@"3£ update failed: %@",message);
    if(foreground) StripNotify(@"3£ update failed",message);
}
static void StripDownloadAndInstall(NSDictionary *release,BOOL foreground) {
    if(stripUpdateInstalling) return;
    stripUpdateInstalling=YES;
    NSURL *url=[NSURL URLWithString:release[@"url"]];
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest=600; configuration.timeoutIntervalForResource=3600;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDownloadTask *task=[session downloadTaskWithURL:url completionHandler:^(NSURL *location,NSURLResponse *response,NSError *error) {
        NSString *downloadedArchive=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3£-release-%@.zip",NSUUID.UUID.UUIDString]];
        NSError *downloadCopyError=nil;
        if(!error && location && [(NSHTTPURLResponse *)response statusCode]==200 &&
           ![[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:downloadedArchive] error:&downloadCopyError]) error=downloadCopyError;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            if(error || !location || [(NSHTTPURLResponse *)response statusCode]!=200) {
                [[NSFileManager defaultManager] removeItemAtPath:downloadedArchive error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(error.localizedDescription ?: @"The release download did not complete.",foreground); }); return;
            }
            NSString *bundlePath=NSBundle.mainBundle.bundlePath;
            while(bundlePath.length>1 && ![[NSBundle bundleWithPath:bundlePath].bundleIdentifier isEqual:@"local.musicstrip.app"]) bundlePath=bundlePath.stringByDeletingLastPathComponent;
            NSString *parent=bundlePath.stringByDeletingLastPathComponent;
            NSString *work=[parent stringByAppendingPathComponent:[NSString stringWithFormat:@".3£-update-%@",NSUUID.UUID.UUIDString]];
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
            NSString *candidate=[extract stringByAppendingPathComponent:@"3£.app"];
            NSString *infoPath=[candidate stringByAppendingPathComponent:@"Contents/Info.plist"];
            NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *expectedID=StripCombinedRelease() ? @"combined-v" : @"touchbar-v";
            BOOL valid=prepared && [info[@"CFBundleIdentifier"] isEqual:@"local.musicstrip.app"] &&
                [info[@"CFBundleShortVersionString"] isEqual:release[@"version"]] &&
                [release[@"tag"] hasPrefix:expectedID] && [info[@"ThreeEIncludesTouchTab"] boolValue]==StripCombinedRelease() &&
                StripRunTool(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",candidate]);
            if(valid) {
                // Re-sign with the same Developer ID used by this install so
                // macOS permissions keep matching the app's designated requirement.
                valid=StripRunTool(@"/usr/bin/codesign",@[@"--force",@"--deep",@"--sign",@"EDA0E1C9F0DD46BE3437CD2733933E31D3A8623D",@"--timestamp=none",candidate]) &&
                    StripRunTool(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",candidate]);
            }
            if(!valid) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(fileError.localizedDescription ?: @"The downloaded app did not pass version, edition, or signature checks.",foreground); }); return;
            }
            NSString *installerSource=[candidate stringByAppendingPathComponent:@"Contents/Resources/UpdateInstaller.sh"];
            NSString *installerCopy=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"3£-update-installer-%@.sh",NSUUID.UUID.UUIDString]];
            if(![[NSFileManager defaultManager] copyItemAtPath:installerSource toPath:installerCopy error:&fileError]) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(fileError.localizedDescription ?: @"The update installer is missing.",foreground); }); return;
            }
            chmod(installerCopy.fileSystemRepresentation,0700);
            pid_t helperPID=getpid(),mainPID=0;
            for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.musicstrip.app"]) if(!app.terminated) { mainPID=app.processIdentifier; break; }
            if(!mainPID) {
                [[NSFileManager defaultManager] removeItemAtPath:work error:nil]; [[NSFileManager defaultManager] removeItemAtPath:installerCopy error:nil];
                dispatch_async(dispatch_get_main_queue(),^{ StripFinishUpdateFailure(@"The main 3£ app could not be found.",foreground); }); return;
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
                StripNotify(@"Installing 3£ update",[NSString stringWithFormat:@"Version %@ will install now. 3£ will restart when installation finishes.",release[@"version"]]);
                [NSApp terminate:nil];
            });
        });
    }];
    [task resume];
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
            BOOL newer=release && [release[@"version"] compare:installed options:NSNumericSearch]==NSOrderedDescending;
            // Background installs restart 3£, so wait until the Mac has been idle
            // for 90 seconds; the next 10-minute check tries again.
            if(newer && StripAutomaticUpdatesEnabled()) {
                if(!foreground && CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState,(CGEventType)~0u)<90) return;
                StripDownloadAndInstall(release,foreground); return;
            }
            if(!foreground) return;
            NSAlert *alert=[NSAlert new];
            alert.messageText=newer ? @"A 3£ update is available" : (release ? @"3£ is up to date" : @"Could not check for updates");
            alert.informativeText=newer ? [NSString stringWithFormat:@"Version %@ is available. Install it now? 3£ will restart after the update is ready.",release[@"version"]] : (release ? [NSString stringWithFormat:@"Installed version: %@. TouchBar updates come from Ezodis/3E.",installed] : @"Check your connection and try again. No app files were changed.");
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
