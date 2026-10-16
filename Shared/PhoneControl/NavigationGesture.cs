// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

// Choose once per contact, so a gesture cannot change modes halfway through.
public sealed class NavigationGesture(Func<bool> multipleDesktops, Action<int> desktop,
    Action<int> beginWindows, Action<int> stepWindows, Action endWindows) {
    private bool? desktops;
    public void Step(int direction) {
        if (direction == 0) return;
        bool first = desktops == null;
        if (first) { try { desktops = multipleDesktops(); } catch { desktops = false; } }
        if (desktops == true) desktop(direction);
        else if (first) beginWindows(direction);
        else stepWindows(direction);
    }
    public void End() { desktops = null; endWindows(); }
}
