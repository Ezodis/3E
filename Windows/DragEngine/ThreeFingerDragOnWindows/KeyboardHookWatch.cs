using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Threading;

namespace ThreeFingerDragOnWindows;

// Windows silently removes a low-level hook that answers too slowly, and the
// Keyboard Manager engine keeps running without it. This hook is installed
// before the engine, so the engine (newer, called first) swallows every Command
// shortcut it remaps. A remapped shortcut reaching this hook as real hardware
// input proves the engine's hook is gone.
public sealed class KeyboardHookWatch : IDisposable {
    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] private struct KeyInfo { public uint Vk, Scan, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Msg { public IntPtr Hwnd; public uint Message; public IntPtr WParam, LParam; public uint Time; public int X, Y; }
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern int GetMessage(out Msg msg, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool PostThreadMessage(uint thread, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string name);

    private const uint Injected = 0x10, WmQuit = 0x12;
    private readonly HashSet<uint> triggers;
    private readonly Action dead;
    private readonly HookProc proc;
    private readonly Thread thread;
    private uint threadId;
    private IntPtr hook;
    private readonly HashSet<uint> others = new();
    private bool ctrl;
    private long lastReport;

    public KeyboardHookWatch(string template, Action dead) {
        this.dead = dead;
        proc = Callback;
        // Only plain Command+key shortcuts: those are always swallowed whole.
        triggers = JsonNode.Parse(File.ReadAllText(template))["remapShortcuts"]["global"].AsArray()
            .Select(s => s["originalKeys"].GetValue<string>().Split(';'))
            .Where(k => k.Length == 2 && k[0] is "162" or "163" or "17")
            .Select(k => uint.Parse(k[1])).ToHashSet();
        thread = new Thread(Run) { IsBackground = true, Name = "3E keyboard hook watch", Priority = ThreadPriority.Highest };
        thread.Start();
    }

    private void Run() {
        threadId = GetCurrentThreadId();
        hook = SetWindowsHookEx(13, proc, GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) return;
        while (GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }
        UnhookWindowsHookEx(hook);
    }

    private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam) {
        if (code >= 0) {
            var key = Marshal.PtrToStructure<KeyInfo>(lParam);
            bool down = wParam == 0x100 || wParam == 0x104;
            switch (key.Vk) {
                case 0xA2: case 0xA3: case 0x11: ctrl = down; break;
                case 0xA0: case 0xA1: case 0x10: case 0xA4: case 0xA5: case 0x12: case 0x5B: case 0x5C: if (down) others.Add(key.Vk); else others.Remove(key.Vk); break;
                default:
                    if (down && ctrl && others.Count == 0 && (key.Flags & Injected) == 0 && triggers.Contains(key.Vk) &&
                        Environment.TickCount64 - lastReport > 5000) {
                        lastReport = Environment.TickCount64;
                        ThreadPool.QueueUserWorkItem(_ => dead());
                    }
                    break;
            }
        }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    public void Dispose() { if (threadId != 0) PostThreadMessage(threadId, WmQuit, IntPtr.Zero, IntPtr.Zero); }
}
