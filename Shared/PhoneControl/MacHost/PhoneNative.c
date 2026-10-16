// SPDX-License-Identifier: MIT
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
static int (*phoneConnection)(void);
static CFArrayRef (*phoneSpaces)(int);
static uint64_t (*phoneActiveSpace)(int);
static pthread_once_t phoneSpaceOnce=PTHREAD_ONCE_INIT;
static void LoadPhoneSpaces(void) {
    void *sky=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
    if(!sky)return;
    phoneConnection=dlsym(sky,"CGSMainConnectionID");
    phoneSpaces=dlsym(sky,"CGSCopyManagedDisplaySpaces");
    phoneActiveSpace=dlsym(sky,"CGSGetActiveSpace");
}
// Same read-only Space discovery used by the Touch Bar's DesktopSupport.
// Private APIs may disappear; fall back to the native app switcher in that case.
int ThreeEHasMultipleSpaces(void) {
    pthread_once(&phoneSpaceOnce,LoadPhoneSpaces);
    if(!phoneConnection||!phoneSpaces)return 0;
    int cid=phoneConnection();uint64_t active=phoneActiveSpace?phoneActiveSpace(cid):0;
    CFArrayRef displays=phoneSpaces(cid);if(!displays)return 0;
    int result=0;
    if(CFGetTypeID(displays)==CFArrayGetTypeID())for(CFIndex i=0;i<CFArrayGetCount(displays);i++) {
        CFDictionaryRef display=CFArrayGetValueAtIndex(displays,i);
        if(CFGetTypeID(display)!=CFDictionaryGetTypeID())continue;
        CFArrayRef spaces=CFDictionaryGetValue(display,CFSTR("Spaces"));
        if(!spaces||CFGetTypeID(spaces)!=CFArrayGetTypeID())continue;
        if(i==0)result=CFArrayGetCount(spaces)>1;
        for(CFIndex j=0;j<CFArrayGetCount(spaces);j++) {
            CFDictionaryRef space=CFArrayGetValueAtIndex(spaces,j);
            if(CFGetTypeID(space)!=CFDictionaryGetTypeID())continue;
            CFNumberRef value=CFDictionaryGetValue(space,CFSTR("id64"));
            if(!value)value=CFDictionaryGetValue(space,CFSTR("ManagedSpaceID"));
            int64_t sid=0;
            if(value&&CFGetTypeID(value)==CFNumberGetTypeID()&&CFNumberGetValue(value,kCFNumberSInt64Type,&sid)&&active&&(uint64_t)sid==active) {
                result=CFArrayGetCount(spaces)>1;CFRelease(displays);return result;
            }
        }
    }
    CFRelease(displays);return result;
}
// The variadic Quartz API uses a different calling convention on Apple Silicon.
// Keep that call in native C and expose a fixed signature to the shared host.
CGEventRef ThreeECreateScrollEvent(int y, int x) {
    return CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, y, x);
}
int ThreeEValidateScrollEvent(void) {
    CGEventRef event = ThreeECreateScrollEvent(17, -9);
    if (!event) return 0;
    int valid = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1) == 17 &&
        CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2) == -9;
    CFRelease(event);
    return valid;
}
