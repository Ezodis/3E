// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

// Choose once per contact, so a gesture cannot change modes halfway through.
public sealed class NavigationGesture(Func<bool> multipleDesktops, Action<int> desktop,
    Action<int> beginWindows, Action<int> stepWindows, Action endWindows) {
    private bool? desktops;
    public void Step(int direction, bool swipe = false) {
        if (direction == 0) return;
        bool first = desktops == null;
        if (first) { try { desktops = multipleDesktops(); } catch { desktops = false; } }
        // Desktop surfaces move opposite the finger; app selection follows it.
        if (desktops == true) desktop(swipe ? -direction : direction);
        else if (first) beginWindows(direction);
        else stepWindows(direction);
    }
    public void End() { desktops = null; endWindows(); }
}
