// SPDX-License-Identifier: MIT
#include <CoreGraphics/CoreGraphics.h>
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
