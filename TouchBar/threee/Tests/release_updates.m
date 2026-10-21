#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "../Source/ReleaseUpdates.h"
// Regression for Touch Tab disappearing: the edition must come from the
// installed bundle's Info.plist, identically in every process.
static void TestEditionSourceOfTruth(void) {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *app=[root stringByAppendingPathComponent:@"3E.app"];
    NSString *helper=[app stringByAppendingPathComponent:@"Contents/Helpers/MIDI Touchbar.app"];
    [NSFileManager.defaultManager createDirectoryAtPath:[helper stringByAppendingPathComponent:@"Contents"] withIntermediateDirectories:YES attributes:nil error:nil];
    [@{@"CFBundleIdentifier":@"com.uebe.midi-touchbar"} writeToFile:[helper stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    [@{@"CFBundleIdentifier":@"local.musicstrip.app",@"ThreeEIncludesTouchTab":@YES} writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    NSCAssert([StripAppBundlePathFrom(helper) isEqual:app],@"The MIDI helper finds its enclosing 3E.app");
    NSCAssert(StripBundleIncludesTouchTab(StripAppBundlePathFrom(helper)),@"Helper built without the combined flag still sees the combined edition");
    [@{@"CFBundleIdentifier":@"local.musicstrip.app"} writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    NSCAssert(!StripBundleIncludesTouchTab(StripAppBundlePathFrom(helper)),@"Touch Bar-only bundle reports no Touch Tab");
    for(NSArray *selection in @[@[],@[@"touchbar"],@[@"touchtab"],@[@"phone"],@[@"touchbar",@"phone",@"touchtab"]]) {
        [@{@"CFBundleIdentifier":@"local.musicstrip.app",@"ThreeEModuleSchema":@1,@"ThreeEModules":selection} writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
        NSCAssert([StripModulesAtPath(StripAppBundlePathFrom(helper)) isEqual:selection],@"Helpers and host retain the exact module selection, including empty");
    }
    NSCAssert(!StripAppBundlePathFrom(root),@"No enclosing app outside a bundle");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    NSCAssert(StripResolveCombined(YES,NO) && StripResolveCombined(NO,YES) && !StripResolveCombined(NO,NO),@"Combined bundle or prior combined use selects combined updates");
    NSCAssert(StripShouldInstall(@"3.0.77",@"3.0.76",YES,YES),@"Newer release installs");
    NSCAssert(!StripShouldInstall(@"3.0.76",@"3.0.76",YES,YES),@"Same version and edition does not reinstall");
    NSCAssert(StripShouldInstall(@"3.0.77",@"3.0.77",NO,YES),@"Same version, wrong edition reinstalls the right edition");
    NSCAssert(!StripShouldInstall(@"3.0.75",@"3.0.76",NO,YES),@"Never downgrade, even to fix the edition");
    NSCAssert(!StripShouldInstall(nil,@"3.0.76",NO,YES),@"No release, no install");
    puts("Passed edition source-of-truth checks.");
}
int main(void) { @autoreleasepool {
    TestEditionSourceOfTruth();
    if(StripCombinedRelease()) {
        NSDictionary *combined=@{@"tag_name":@"combined-v3.0.0",@"assets":@[@{@"name":@"3E-Combined.zip",@"browser_download_url":@"https://github.com/Ezodis/3E/releases/download/combined-v3.0.0/3E-Combined.zip"}]};
        NSCAssert([StripValidRelease(combined)[@"version"] isEqual:@"3.0.0"],@"Combined app accepts only its own update");
        NSCAssert(!StripValidRelease(@{@"tag_name":@"touchbar-v3.0.0",@"assets":combined[@"assets"]}),@"Never replace combined app with TouchBar-only");
        NSCAssert(!StripValidRelease(@{@"tag_name":@"touchtab-v3.0.0",@"assets":combined[@"assets"]}),@"Never replace combined app with TouchTab-only");
        puts("Passed combined-specific update selection."); return 0;
    }
    NSMutableDictionary *release=[@{@"tag_name":@"touchbar-v2.7.2",@"draft":@NO,@"prerelease":@NO,@"assets":@[@{@"name":@"TouchBar.zip",@"browser_download_url":@"https://github.com/Ezodis/3E/releases/download/touchbar-v2.7.2/TouchBar.zip"}]} mutableCopy];
    NSCAssert([StripValidRelease(release)[@"version"] isEqual:@"2.7.2"],@"Valid current repository asset");
    release[@"draft"]=@YES; NSCAssert(!StripValidRelease(release),@"Ignore drafts"); release[@"draft"]=@NO;
    release[@"prerelease"]=@YES; NSCAssert(!StripValidRelease(release),@"Ignore prereleases"); release[@"prerelease"]=@NO;
    release[@"tag_name"]=@"v../../bad"; NSCAssert(!StripValidRelease(release),@"Reject malformed tags");
    release[@"tag_name"]=@"touchtab-v2.7.2"; NSCAssert(!StripValidRelease(release),@"Never confuse apps");
    release[@"tag_name"]=@"bundle-v2.7.2"; NSCAssert(!StripValidRelease(release),@"Ignore bundle releases");
    release[@"tag_name"]=@"touchbar-v2.7.2";
    NSCAssert([StripNewestRelease(@[@{},release])[@"version"] isEqual:@"2.7.2"],@"Filter release list");
    NSMutableDictionary *older=[release mutableCopy]; older[@"tag_name"]=@"touchbar-v2.7.1"; older[@"assets"]=@[@{@"name":@"TouchBar.zip",@"browser_download_url":@"https://github.com/Ezodis/3E/releases/download/touchbar-v2.7.1/TouchBar.zip"}];
    NSCAssert([StripNewestRelease(@[release,older])[@"version"] isEqual:@"2.7.2"],@"Select newest own version regardless of order");
    release[@"assets"]=@[@{@"name":@"TouchBar.zip",@"browser_download_url":@"https://github.com/Ezodis/instagram-grill-bot/releases/download/touchbar-v2.7.2/TouchBar.zip"}];
    NSCAssert(!StripValidRelease(release),@"Never download the old repository asset");
    release[@"assets"]=@{}; NSCAssert(!StripValidRelease(release),@"Reject malformed assets");
    NSCAssert(!StripValidRelease(@[]),@"Reject malformed response");
    puts("Passed release validation, stable version and new-repository-only downloads. No network or UI actions.");
} return 0; }
