// Check this app's public releases, never the vendor engine's old XML feed.
static NSString *const StripReleaseVersion=@"3.0.7";
static NSString *const StripReleasesAPI=@"https://api.github.com/repos/Ezodis/3E/releases?per_page=100";
static NSString *const StripReleasesPage=@"https://github.com/Ezodis/3E/releases";
static BOOL stripUpdateChecking;
static BOOL StripCombinedRelease(void) { return [NSProcessInfo.processInfo.environment[@"STRIP_COMBINED_TOUCHTAB"] isEqual:@"1"]; }
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
        if([url isKindOfClass:NSString.class] && [url isEqual:expected]) return @{@"version":version,@"url":url};
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
static void StripCheckRelease(BOOL foreground) {
    if(stripUpdateChecking) return;
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
            BOOL newer=release && [release[@"version"] compare:StripReleaseVersion options:NSNumericSearch]==NSOrderedDescending;
            if(!foreground && !newer) return;
            NSAlert *alert=[NSAlert new];
            alert.messageText=newer ? @"A 3£ update is available" : (release ? @"3£ is up to date" : @"Could not check for updates");
            alert.informativeText=newer ? [NSString stringWithFormat:@"Version %@ is available from Ezodis/3E. Download it when you're ready; your current app and Ableton session will not be interrupted.",release[@"version"]] : (release ? [NSString stringWithFormat:@"Installed version: %@. TouchBar updates come from Ezodis/3E.",StripReleaseVersion] : @"Check your connection and try again. No app files were changed.");
            [alert addButtonWithTitle:newer ? @"Download" : @"OK"];
            if(newer) [alert addButtonWithTitle:@"Later"];
            [alert addButtonWithTitle:@"View Releases"];
            [NSApp activateIgnoringOtherApps:YES];
            NSModalResponse choice=[alert runModal];
            if(newer && choice==NSAlertFirstButtonReturn)
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:release[@"url"]]];
            else if(choice==(newer ? NSAlertThirdButtonReturn : NSAlertSecondButtonReturn))
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:StripReleasesPage]];
        });
    }] resume];
}
static void StripUpdateForeground(id self,SEL selector) { StripCheckRelease(YES); }
static void StripUpdateMenu(id self,SEL selector,id sender) { StripCheckRelease(YES); }
static void StripUpdateBackground(id self,SEL selector) { StripCheckRelease(NO); }
static BOOL StripInstallUpdateHooks(void) {
    Class cls=NSClassFromString(@"AppDelegate");
    Method menu=class_getInstanceMethod(cls,NSSelectorFromString(@"checkForUpdate:"));
    Method background=class_getInstanceMethod(cls,NSSelectorFromString(@"startUpdateCheckBackground"));
    Method foreground=class_getInstanceMethod(cls,NSSelectorFromString(@"startUpdateCheckForeground"));
    if(!menu || !background || !foreground) return NO;
    method_setImplementation(menu,(IMP)StripUpdateMenu);
    method_setImplementation(background,(IMP)StripUpdateBackground);
    method_setImplementation(foreground,(IMP)StripUpdateForeground);
    return YES;
}
