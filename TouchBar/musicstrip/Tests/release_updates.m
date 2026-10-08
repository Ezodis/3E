#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "../Source/ReleaseUpdates.h"
int main(void) { @autoreleasepool {
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
