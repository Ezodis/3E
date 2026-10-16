// SPDX-License-Identifier: MIT
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreAudio/CoreAudio.h>
#include <math.h>
#include <dlfcn.h>
#include <pthread.h>
static int (*phoneConnection)(void);
static CFArrayRef (*phoneSpaces)(int);
static uint64_t (*phoneActiveSpace)(int);
static pthread_once_t phoneSpaceOnce=PTHREAD_ONCE_INIT;
static int PhoneVolumeLayout(AudioDeviceID *device,AudioObjectPropertyAddress addresses[2],Float32 levels[2]) {
    AudioObjectPropertyAddress output={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=sizeof(*device);
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&output,0,NULL,&size,device)!=noErr||!*device)return 0;
    int count=0;
    for(UInt32 channel=0;channel<=2;channel++) {
        AudioObjectPropertyAddress volume={kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyScopeOutput,channel};
        Boolean writable=false;Float32 level=0;size=sizeof(level);
        if(!AudioObjectHasProperty(*device,&volume)||AudioObjectIsPropertySettable(*device,&volume,&writable)!=noErr||!writable)continue;
        if(AudioObjectGetPropertyData(*device,&volume,0,NULL,&size,&level)!=noErr||!isfinite(level))return 0;
        addresses[count]=volume;levels[count++]=fmaxf(0,fminf(1,level));
        if(channel==0)break;
    }
    // Stereo fallback only; do not silently adjust part of a multichannel output.
    AudioObjectPropertyAddress third={kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyScopeOutput,3};
    if(count&&addresses[0].mElement!=0&&AudioObjectHasProperty(*device,&third))return 0;
    return count;
}
int ThreeEGetOutputVolume(void) {
    AudioDeviceID device;AudioObjectPropertyAddress addresses[2];Float32 levels[2];
    int count=PhoneVolumeLayout(&device,addresses,levels);if(!count)return -1;
    AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
    UInt32 muted=0,size=sizeof(muted);
    if(AudioObjectGetPropertyData(device,&mute,0,NULL,&size,&muted)==noErr&&muted)return 0;
    float maximum=0;for(int i=0;i<count;i++)maximum=fmaxf(maximum,levels[i]);
    return (int)lroundf(maximum*100);
}
int ThreeESetOutputVolume(int value) {
    if(value<0||value>100)return 0;
    AudioDeviceID device;AudioObjectPropertyAddress addresses[2];Float32 levels[2];
    int count=PhoneVolumeLayout(&device,addresses,levels);if(!count)return 0;
    float maximum=0;for(int i=0;i<count;i++)maximum=fmaxf(maximum,levels[i]);
    for(int i=0;i<count;i++) {
        Float32 level=(value/100.f)*(maximum>0?levels[i]/maximum:1);
        if(AudioObjectSetPropertyData(device,&addresses[i],0,NULL,sizeof(level),&level)!=noErr)return 0;
    }
    if(value>0) {
        AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioObjectPropertyScopeOutput,kAudioObjectPropertyElementMain};
        Boolean writable=false;UInt32 unmuted=0;
        if(AudioObjectIsPropertySettable(device,&mute,&writable)==noErr&&writable)
            if(AudioObjectSetPropertyData(device,&mute,0,NULL,sizeof(unmuted),&unmuted)!=noErr)return 0;
    }
    return 1;
}
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
