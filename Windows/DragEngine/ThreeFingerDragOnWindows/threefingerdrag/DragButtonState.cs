using System;

namespace ThreeFingerDragOnWindows.threefingerdrag;

// The caller serializes contact and timer callbacks. A rejected press is not
// a drag, and a rejected release must be retried before another press.
public sealed class DragButtonState(Func<bool> press, Func<bool> release) {
    public bool Held { get; private set; }
    public bool ReleasePending { get; private set; }
    public long ReleaseAt { get; private set; }
    public bool Begin(long now, int delay) {
        if (Held) return true;
        if (ReleasePending && !End()) return false;
        Held = press();
        if (Held) Refresh(now, delay);
        return Held;
    }
    public void Refresh(long now, int delay) {
        if (Held) ReleaseAt = now + Math.Max(1, delay);
    }
    public bool End() {
        if (!Held && !ReleasePending) return true;
        Held = false;
        ReleasePending = !release();
        return !ReleasePending;
    }
    public bool Expire(long now) {
        if (!Held || now < ReleaseAt) return false;
        End();
        return true;
    }
}
