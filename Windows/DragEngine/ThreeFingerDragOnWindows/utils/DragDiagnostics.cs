using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ThreeFingerDragOnWindows.utils;

// Only aggregate gesture/input counts and the last target process identity.
// No coordinates, window titles, keys, screenshots or event history are stored.
internal static class DragDiagnostics {
    private static readonly bool enabled = Array.Exists(Environment.GetCommandLineArgs(), arg => arg == "--diagnose-drag");
    private static readonly object gate = new();
    private static long frames, threeFingerFrames, presses, moves, releases, rejected;
    private static long lastTargetSample;
    private static int lastError;
    private static string lastOperation;
    private static DateTime? lastGestureUtc;
    private static object target;
    public static void Contacts(int count) {
        if (!enabled) return;
        lock (gate) {
            frames++;
            if (count < 3) return;
            threeFingerFrames++;
            lastGestureUtc = DateTime.UtcNow;
            if (Environment.TickCount64 - lastTargetSample < 1000) return;
            lastTargetSample = Environment.TickCount64;
            target = TargetUnderPointer();
        }
    }
    public static void Sent(string operation, bool accepted, int error) {
        if (!enabled) return;
        lock (gate) {
            if (accepted) {
                if (operation == "down") presses++;
                else if (operation == "up") releases++;
                else moves++;
            } else rejected++;
            lastOperation = operation; lastError = accepted ? 0 : error;
        }
    }
    public static object Snapshot() {
        if (!enabled) return new { enabled = false };
        lock (gate) return new { enabled = true, frames, threeFingerFrames, presses, moves, releases,
            rejected, lastOperation, lastError, lastGestureUtc, target,
            administrator = Utils.IsAppRunningAsAdministrator(), integrity = Integrity(Environment.ProcessId) };
    }
    private static object TargetUnderPointer() {
        try {
            if (!GetCursorPos(out var point)) return null;
            var window = WindowFromPoint(point);
            GetWindowThreadProcessId(window, out uint pid);
            using var process = Process.GetProcessById((int)pid);
            return new { process = process.ProcessName, pid, integrity = Integrity((int)pid) };
        } catch { return null; }
    }
    private static int? Integrity(int pid) {
        IntPtr process = OpenProcess(0x1000, false, pid), token = IntPtr.Zero, buffer = IntPtr.Zero;
        if (process == IntPtr.Zero) return null;
        try {
            if (!OpenProcessToken(process, 8, out token)) return null;
            GetTokenInformation(token, 25, IntPtr.Zero, 0, out int size);
            if (size <= 0) return null;
            buffer = Marshal.AllocHGlobal(size);
            if (!GetTokenInformation(token, 25, buffer, size, out _)) return null;
            IntPtr sid = Marshal.ReadIntPtr(buffer);
            int count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
            return count == 0 ? null : Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
        } finally {
            if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
            if (token != IntPtr.Zero) CloseHandle(token);
            CloseHandle(process);
        }
    }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("kernel32.dll")] private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll")] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll")] private static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr info, int size, out int used);
    [DllImport("advapi32.dll")] private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("advapi32.dll")] private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
}
