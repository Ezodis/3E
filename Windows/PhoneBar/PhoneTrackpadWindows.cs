// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using QRCoder;

using ThreeE.PhoneControl;
namespace ThreeE.PhoneBar.Windows;

public sealed class TrackpadFirewall : ITrackpadFirewall {
    public void Open(IPAddress address, int port) {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        dynamic rule = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FWRule"));
        try {
            policy.Rules.Remove(PhoneTrackpad.FirewallName);
            rule.Name = PhoneTrackpad.FirewallName;
            rule.Description = "Optional local iPhone trackpad. Open only during a manually started session.";
            rule.Protocol = 6; rule.LocalPorts = port.ToString();
            rule.LocalAddresses = address.ToString(); rule.RemoteAddresses = "LocalSubnet";
            rule.Direction = 1; rule.Action = 1; rule.Profiles = int.MaxValue;
            rule.EdgeTraversal = false; rule.Enabled = true;
            policy.Rules.Add(rule);
        } finally { Marshal.FinalReleaseComObject(rule); Marshal.FinalReleaseComObject(policy); }
    }
    public const string NameRule = "3EWindows Phone Bar name (mDNS)";
    public void OpenName() {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        dynamic rule = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FWRule"));
        try {
            policy.Rules.Remove(NameRule);
            rule.Name = NameRule;
            rule.Description = "Answers 3e-win.local for the Phone Bar receiver while it runs.";
            rule.Protocol = 17; rule.LocalPorts = "5353"; rule.RemoteAddresses = "LocalSubnet";
            rule.Direction = 1; rule.Action = 1; rule.Profiles = int.MaxValue; rule.EdgeTraversal = false; rule.Enabled = true;
            policy.Rules.Add(rule);
        } finally { Marshal.FinalReleaseComObject(rule); Marshal.FinalReleaseComObject(policy); }
    }
    public void Close() {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        try { policy.Rules.Remove(PhoneTrackpad.FirewallName); try { policy.Rules.Remove(NameRule); } catch { } } finally { Marshal.FinalReleaseComObject(policy); }
    }
}

public sealed class NativeTrackpadInput : ITrackpadInput, IDisposable {
    // PowerToys uses this marker to avoid remapping already-generated shortcuts.
    // Required because the suite swaps left Alt+Tab and Ctrl+Tab.
    // microsoft/PowerToys: src/modules/keyboardmanager/common/KeyboardManagerConstants.h
    private const uint ShortcutMarker = 0x101;
    private readonly PhoneMidiWindows midi = new();
    private bool switching;
    private readonly NavigationGesture navigation;
    private readonly Func<object> controls;
    private readonly Action<int> media,volume;
    private readonly Func<object> volumeState;
    private readonly Action cancelVolume, refreshVolume;
    public NativeTrackpadInput(Func<object> controls = null, Action<int> media = null, Func<object> volumeState = null, Action<int> volume = null, Action cancelVolume = null, Action refreshVolume = null) {
        this.controls=controls;this.media=media;this.volumeState=volumeState;this.volume=volume;this.cancelVolume=cancelVolume;this.refreshVolume=refreshVolume;
        navigation=new(HasMultipleDesktops,SendDesktopShortcut,BeginApps,AppsStep,AppsEnd);
    }
    public object GetConnectionInfo() => new {platform="windows",volume=volumeState?.Invoke(),controls=controls?.Invoke()};
    public object GetInfo() => new {platform="windows",volume=volumeState?.Invoke(),controls=controls?.Invoke(),midi=midi.Info()};
    public static bool HasMultipleDesktops() {
        // Explorer's list includes empty desktops that cannot be found by
        // enumerating windows. Missing/changed OS data falls back to windows.
        using var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops");
        return HasMultipleDesktopIds(key?.GetValue("VirtualDesktopIDs") as byte[]);
    }
    public static bool HasMultipleDesktopIds(byte[] ids) => ids != null && ids.Length>=32 && ids.Length%16==0;
    public void MidiPort(int id) => midi.Select(id);
    public void Midi(bool note,int channel,int number,int value) => midi.Send(note,channel,number,value);
    public void MidiPanic() => midi.Panic();
    public void ReleaseAll() { cancelVolume?.Invoke(); try { Release(); } finally { try { navigation.End(); } finally { midi.Panic(); } } }
    public void Dispose() { try { ReleaseAll(); } finally { midi.Dispose(); } }
    [StructLayout(LayoutKind.Sequential)] private struct Mouse { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Keyboard { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] private struct InputData { [FieldOffset(0)] public Mouse Mouse; [FieldOffset(0)] public Keyboard Keyboard; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputData Data; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    private bool held;
    private static void Send(uint flags, int x = 0, int y = 0, int data = 0) {
        var inputs = new[] { new Input { Data = new InputData { Mouse = new Mouse { X = x, Y = y, Data = unchecked((uint)data), Flags = flags } } } };
        if (SendInput(1, inputs, Marshal.SizeOf<Input>()) != 1) throw new InvalidOperationException("Windows could not accept trackpad input.");
    }
    // Exact-pixel moves: absolute positioning is not reshaped by Windows'
    // "Enhance pointer precision", which shrank small phone movements to
    // nothing and then jumped. The phone's speed/acceleration sets the feel.
    public void Move(int x, int y) {
        if (x == 0 && y == 0) return;
        if (!GetCursorPos(out var point)) { Send(0x0001, x, y); return; }
        int left = GetSystemMetrics(76), top = GetSystemMetrics(77), width = Math.Max(2, GetSystemMetrics(78)), height = Math.Max(2, GetSystemMetrics(79));
        long tx = Math.Clamp((long)point.X + x, left, left + width - 1), ty = Math.Clamp((long)point.Y + y, top, top + height - 1);
        int ax = (int)(((tx - left) * 65535L + (width - 1) / 2) / (width - 1)), ay = (int)(((ty - top) * 65535L + (height - 1) / 2) / (height - 1));
        Send(0x0001 | 0x8000 | 0x4000, ax, ay); // MOVE | ABSOLUTE | VIRTUALDESK
    }
    public void Scroll(int x, int y) { if (y != 0) Send(0x0800, data: y); if (x != 0) Send(0x1000, data: x); }
    public void Click(bool right) {
        if (held) return;
        uint down = right ? 0x0008u : 0x0002u, up = right ? 0x0010u : 0x0004u;
        try { Send(down); } finally { Send(up); }
        if (!right && GetCursorPos(out var point)) { lastClick = point; lastClickTick = Environment.TickCount64; }
    }
    [StructLayout(LayoutKind.Sequential)] private struct CursorPoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out CursorPoint point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern uint GetDoubleClickTime();
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    private CursorPoint lastClick; private long lastClickTick = long.MinValue / 2;
    // Tap then drag: Windows would treat a press at the tap's position within
    // the double-click time as a double-click (opening files, maximising title
    // bars, selecting words). Step just outside the double-click rectangle,
    // in the drag direction, so the press is an ordinary drag start.
    public void DragStart(int x, int y) {
        if (held) return;
        if (GetCursorPos(out var point) && Environment.TickCount64 - lastClickTick <= GetDoubleClickTime() + 100) {
            int halfWidth = Math.Max(2, GetSystemMetrics(36) / 2 + 2), halfHeight = Math.Max(2, GetSystemMetrics(37) / 2 + 2);
            if (Math.Abs(point.X - lastClick.X) < halfWidth && Math.Abs(point.Y - lastClick.Y) < halfHeight) {
                if (x == 0 && y == 0) x = 1;
                SetCursorPos(lastClick.X + x * halfWidth, lastClick.Y + y * halfHeight);
            }
        }
        Down();
    }
    public void Down() { if (!held) { Send(0x0002); held = true; } }
    public void Release() { if (held) { try { Send(0x0004); } finally { held = false; } } }
    // The protocol exposes fixed actions, never arbitrary keyboard input.
    private static void WindowsShortcut(ushort key) {
        static Input Key(ushort code, bool up) => KeyEvent(code,up);
        var inputs = new[] { Key(0x5B,false), Key(key,false), Key(key,true), Key(0x5B,true) };
        if (SendInput(4, inputs, Marshal.SizeOf<Input>()) == 4) return;
        // A partial injection must never leave Windows or Tab held down.
        SendInput(2, new[] { Key(key,true), Key(0x5B,true) }, Marshal.SizeOf<Input>());
        throw new InvalidOperationException("Windows could not open the requested view.");
    }
    public void TaskView() => WindowsShortcut(0x09); // Windows + Tab
    public void ShowDesktop() => WindowsShortcut(0x44); // Windows + D
    private static Input KeyEvent(ushort key,bool up=false) => new() { Type=1,Data=new InputData { Keyboard=new Keyboard { Key=key,Extra=(UIntPtr)ShortcutMarker,Flags=(up?2u:0u) | (key==0x5B || key==0x25 || key==0x27 || key==0x2C || key==0xAE || key==0xAF || key==0xB0 || key==0xB1 ? 1u:0u) } } };
    private static void Keys(params Input[] keys) { if(SendInput((uint)keys.Length,keys,Marshal.SizeOf<Input>())!=keys.Length) throw new InvalidOperationException("Windows could not accept the shortcut."); }
    private static void ReleaseKeys(params ushort[] keys) { foreach(var key in keys) SendInput(1,new[]{KeyEvent(key,true)},Marshal.SizeOf<Input>()); }
    public void AppsBegin() => BeginApps(1);
    private void BeginApps(int direction) {
        if(switching) return;
        switching=true;
        try { Keys(KeyEvent(0x12)); AppsStep(direction); } catch { AppsEnd(); throw; }
    }
    public void AppsStep(int direction) {
        if(!switching || direction==0) return;
        try { if(direction<0) Keys(KeyEvent(0x10)); Keys(KeyEvent(0x09)); }
        finally { ReleaseKeys(0x09); if(direction<0) ReleaseKeys(0x10); }
    }
    public void AppsEnd() { if(switching) { switching=false; ReleaseKeys(0x09,0x12); } }
    public void Desktop(int direction) {
        if(direction==0) return;
        ReleaseAll(); SendDesktopShortcut(direction);
    }
    public void Navigate(int direction) => navigation.Step(direction);
    public void NavigateEnd() => navigation.End();
    private void SendDesktopShortcut(int direction) {
        ushort arrow=direction<0?(ushort)0x25:(ushort)0x27;
        try { Keys(KeyEvent(0x5B),KeyEvent(0x11),KeyEvent(arrow),KeyEvent(arrow,true)); }
        finally { ReleaseKeys(arrow,0x11,0x5B); }
    }
    // Fixed Mac-style palette (ids match Web/dock.js). Command maps to Ctrl, and
    // the screenshot trio maps to the Windows capture shortcuts.
    private static readonly ushort[][] shortcuts = {
        new ushort[]{0x11,0x43},      // 0  ⌘C  copy
        new ushort[]{0x11,0x56},      // 1  ⌘V  paste
        new ushort[]{0x11,0x58},      // 2  ⌘X  cut
        new ushort[]{0x11,0x41},      // 3  ⌘A  select all
        new ushort[]{0x11,0x5A},      // 4  ⌘Z  undo
        new ushort[]{0x11,0x59},      // 5  ⌘⇧Z redo (Ctrl+Y)
        new ushort[]{0x11,0x54},      // 6  ⌘T  new tab
        new ushort[]{0x11,0x10,0x54}, // 7  ⌘⇧T reopen closed tab
        new ushort[]{0x11,0x57},      // 8  ⌘W  close tab
        new ushort[]{0x11,0x4E},      // 9  ⌘N  new window
        new ushort[]{0x11,0x46},      // 10 ⌘F  find
        new ushort[]{0x11,0x53},      // 11 ⌘S  save
        new ushort[]{0x74},           // 12 ⌘R  refresh (F5)
        new ushort[]{0x5B,0x2C},      // 13 ⌘⇧3 full screenshot (Win+PrtSc)
        new ushort[]{0x5B,0x10,0x53}, // 14 ⌘⇧4 area screenshot (Win+Shift+S)
        new ushort[]{0x5B,0x10,0x52}, // 15 ⌘⇧5 screen recording (Win+Shift+R)
        new ushort[]{0x5B,0x53},      // 16 ⌘Space search (Win+S)
        new ushort[]{0x12,0x73},      // 17 ⌘Q  quit app (Alt+F4)
    };
    public void Shortcut(int id) {
        if ((uint)id >= (uint)shortcuts.Length) return;
        // A held drag button or app switcher must never combine with a shortcut.
        Release(); AppsEnd();
        var keys = shortcuts[id];
        var sequence = keys.Select(k => KeyEvent(k)).Concat(keys.Reverse().Select(k => KeyEvent(k, true))).ToArray();
        // A rejected injection (for example a secure desktop) must not drop the
        // phone connection or leave a modifier held.
        if (SendInput((uint)sequence.Length, sequence, Marshal.SizeOf<Input>()) != sequence.Length) ReleaseKeys(keys.Reverse().ToArray());
    }
    // Browser Back/Forward keys work in Chrome, Edge, Firefox and File Explorer.
    public void History(int direction) {
        if (direction == 0) return;
        Release();
        ushort key = direction < 0 ? (ushort)0xA6 : (ushort)0xA7;
        SendInput(2, new[] { KeyEvent(key), KeyEvent(key, true) }, Marshal.SizeOf<Input>());
    }
    // Ctrl + one wheel notch: the standard zoom step in browsers and most apps.
    public void Zoom(int direction) {
        if (direction == 0) return;
        var wheel = new Input { Data = new InputData { Mouse = new Mouse { Data = unchecked((uint)(direction > 0 ? 120 : -120)), Flags = 0x0800 } } };
        var inputs = new[] { KeyEvent(0x11), wheel, KeyEvent(0x11, true) };
        if (SendInput(3, inputs, Marshal.SizeOf<Input>()) != 3) ReleaseKeys(0x11);
    }
    // Hardware Next/Previous media keys (used as a skip fallback).
    internal static bool MediaKey(bool next) {
        ushort key = next ? (ushort)0xB0 : (ushort)0xB1;
        return SendInput(2, new[] { KeyEvent(key), KeyEvent(key, true) }, Marshal.SizeOf<Input>()) == 2;
    }
    public void Media(int action) => media?.Invoke(action);
    public void Volume(int level) => volume?.Invoke(level);
    // The real Windows volume keys: same 2% steps and on-screen volume flyout as the keyboard.
    public void VolumeStep(int direction) {
        if (direction == 0) return;
        ushort key = direction > 0 ? (ushort)0xAF : (ushort)0xAE;
        cancelVolume?.Invoke();
        SendInput(2, new[] { KeyEvent(key), KeyEvent(key, true) }, Marshal.SizeOf<Input>());
        // Windows applies the key asynchronously; re-read after it lands.
        _ = Task.Delay(150).ContinueWith(_ => refreshVolume?.Invoke());
    }
}

// While the receiver runs, Windows must not throttle this background tray
// process or let the Wi-Fi adapter doze between packets: both add a visible
// delay to the first touch after a pause and cause stutter during motion.
// Original values are saved to disk first, so a crash is repaired next start.
internal static class PhonePowerTuning {
    private static readonly Guid WirelessGroup = new("19cadd1a-b7ca-4b0f-8dfa-cf6b0a1e5ea1");
    private static readonly Guid WirelessPowerSaving = new("12bbebe6-58d6-4636-95bb-3217ef867c1a");
    private static readonly object gate = new();
    private static bool active;
    private static string StatePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "phone-wifi-power.txt");
    [StructLayout(LayoutKind.Sequential)] private struct Throttling { public uint Version, ControlMask, StateMask; }
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetProcessInformation(IntPtr process, int cls, ref Throttling info, int size);
    [DllImport("powrprof.dll")] private static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
    [DllImport("powrprof.dll")] private static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
    [DllImport("powrprof.dll")] private static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, out uint value);
    [DllImport("powrprof.dll")] private static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, out uint value);
    [DllImport("powrprof.dll")] private static extern uint PowerWriteACValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, uint value);
    [DllImport("powrprof.dll")] private static extern uint PowerWriteDCValueIndex(IntPtr root, ref Guid scheme, ref Guid group, ref Guid setting, uint value);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);

    private static void ProcessThrottling(bool allow) {
        // EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION. ControlMask 0 returns control to Windows.
        var state = new Throttling { Version = 1, ControlMask = allow ? 0u : 0x5u, StateMask = 0 };
        SetProcessInformation(GetCurrentProcess(), 4, ref state, Marshal.SizeOf<Throttling>());
    }
    private static bool ActiveScheme(out Guid scheme) {
        scheme = Guid.Empty;
        if (PowerGetActiveScheme(IntPtr.Zero, out var pointer) != 0 || pointer == IntPtr.Zero) return false;
        try { scheme = Marshal.PtrToStructure<Guid>(pointer); return true; } finally { LocalFree(pointer); }
    }
    private static void Write(Guid scheme, uint ac, uint dc) {
        Guid group = WirelessGroup, setting = WirelessPowerSaving;
        PowerWriteACValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, ac);
        PowerWriteDCValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, dc);
        PowerSetActiveScheme(IntPtr.Zero, ref scheme);
    }
    private static void RestoreSaved() {
        var text = File.Exists(StatePath) ? File.ReadAllText(StatePath).Split(' ') : null;
        if (text is { Length: 3 } && Guid.TryParse(text[0], out var scheme) && uint.TryParse(text[1], out var ac) && uint.TryParse(text[2], out var dc) && ac <= 3 && dc <= 3)
            Write(scheme, ac, dc);
        File.Delete(StatePath);
    }
    public static void Begin() {
        lock (gate) {
            if (active) return;
            active = true;
            try { ProcessThrottling(false); } catch { }
            try {
                RestoreSaved(); // Repairs a previous session that ended without cleanup.
                if (!ActiveScheme(out var scheme)) return;
                Guid group = WirelessGroup, setting = WirelessPowerSaving;
                if (PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, out var ac) != 0 ||
                    PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref group, ref setting, out var dc) != 0) return;
                if (ac == 0 && dc == 0) return; // Already Maximum Performance.
                Directory.CreateDirectory(Path.GetDirectoryName(StatePath));
                File.WriteAllText(StatePath, $"{scheme} {ac} {dc}");
                Write(scheme, 0, 0); // 0 = Maximum Performance
            } catch { /* Power tuning is best effort; the trackpad works without it. */ }
        }
    }
    public static void End() {
        lock (gate) {
            if (!active) return;
            active = false;
            try { RestoreSaved(); } catch { }
            try { ProcessThrottling(true); } catch { }
        }
    }
}
