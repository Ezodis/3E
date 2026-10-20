#import "../../../Shared/Brand/ThreeEStatusBrand.h"
static void TestStatusBrand(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSButton *suite=[NSButton new],*other=[NSButton new];
    NSImage *legacy=[[NSImage alloc] initWithSize:NSMakeSize(16,16)];
    suite.image=legacy;suite.alternateImage=legacy;
    ThreeEBrandStatusButton(suite);
    NSCAssert(suite.image==ThreeEBrandMenuImage() && suite.alternateImage==ThreeEBrandMenuImage(),@"Replace both original and highlighted helper logos");
    suite.image=legacy;suite.alternateImage=legacy;
    NSCAssert(suite.image==ThreeEBrandMenuImage() && suite.alternateImage==ThreeEBrandMenuImage(),@"Late helper updates cannot restore vendor branding");
    other.image=legacy;other.alternateImage=legacy;
    NSCAssert(other.image==legacy && other.alternateImage==legacy,@"Other controls retain their own artwork");
    ThreeEBrandStatusButton(suite);suite.image=nil;
    NSCAssert(suite.image==ThreeEBrandMenuImage(),@"Repeated application remains safe");
    puts("PASS: suite menu branding survives normal, highlighted and late helper updates.");
} }
