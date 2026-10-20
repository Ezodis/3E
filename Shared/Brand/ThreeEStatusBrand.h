// Keep only explicitly branded suite status buttons on the 3E mark, including
// legacy helper updates after launch and the highlighted/alternate image.
#import "ThreeEBrand.h"
#import <objc/runtime.h>

static char threeEStatusBrandKey;
static void (*threeEOriginalButtonImage)(id,SEL,NSImage *);
static void (*threeEOriginalAlternateImage)(id,SEL,NSImage *);
static void ThreeEStatusSetImage(id button,SEL selector,NSImage *image) {
    threeEOriginalButtonImage(button,selector,objc_getAssociatedObject(button,&threeEStatusBrandKey) ? ThreeEBrandMenuImage() : image);
}
static void ThreeEStatusSetAlternateImage(id button,SEL selector,NSImage *image) {
    threeEOriginalAlternateImage(button,selector,objc_getAssociatedObject(button,&threeEStatusBrandKey) ? ThreeEBrandMenuImage() : image);
}
static void ThreeEBrandStatusButton(NSButton *button) {
    if(!button) return;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        threeEOriginalButtonImage=(void *)method_setImplementation(class_getInstanceMethod(NSButton.class,@selector(setImage:)),(IMP)ThreeEStatusSetImage);
        threeEOriginalAlternateImage=(void *)method_setImplementation(class_getInstanceMethod(NSButton.class,@selector(setAlternateImage:)),(IMP)ThreeEStatusSetAlternateImage);
    });
    objc_setAssociatedObject(button,&threeEStatusBrandKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.image=ThreeEBrandMenuImage();
    button.alternateImage=ThreeEBrandMenuImage();
    button.title=@"";
    button.toolTip=@"3E";
}
