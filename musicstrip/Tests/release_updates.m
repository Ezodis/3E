#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "../Source/ReleaseUpdates.h"
int main(void) { @autoreleasepool {
    NSMutableDictionary *release=[@{@"tag_name":@"v2.7.2",@"draft":@NO,@"prerelease":@NO,@"assets":@[@{@"name":@"Strip3.zip",@"browser_download_url":@"https://github.com/Ezodis/Touchbar3DY/releases/download/v2.7.2/Strip3.zip"}]} mutableCopy];
    NSCAssert([StripValidRelease(release)[@"version"] isEqual:@"2.7.2"],@"Valid current repository asset");
    release[@"draft"]=@YES; NSCAssert(!StripValidRelease(release),@"Ignore drafts"); release[@"draft"]=@NO;
    release[@"prerelease"]=@YES; NSCAssert(!StripValidRelease(release),@"Ignore prereleases"); release[@"prerelease"]=@NO;
    release[@"tag_name"]=@"v../../bad"; NSCAssert(!StripValidRelease(release),@"Reject malformed tags"); release[@"tag_name"]=@"v2.7.2";
    release[@"assets"]=@[@{@"name":@"Strip3.zip",@"browser_download_url":@"https://github.com/Ezodis/instagram-grill-bot/releases/download/v2.7.2/Strip3.zip"}];
    NSCAssert(!StripValidRelease(release),@"Never download the old repository asset");
    release[@"assets"]=@{}; NSCAssert(!StripValidRelease(release),@"Reject malformed assets");
    NSCAssert(!StripValidRelease(@[]),@"Reject malformed response");
    puts("Passed release validation, stable version and new-repository-only downloads. No network or UI actions.");
} return 0; }
