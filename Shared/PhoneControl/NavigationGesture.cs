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
    // Track Tab (four-finger swipe): with several desktops, switch exactly one
    // desktop per swipe, like macOS; otherwise drive the app switcher.
    public void Tab(int direction) {
        if (direction == 0) return;
        if (desktops == true) return;
        Step(direction, true);
    }
    public void End() { desktops = null; endWindows(); }
}
