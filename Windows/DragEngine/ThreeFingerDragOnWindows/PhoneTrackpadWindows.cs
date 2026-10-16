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
namespace ThreeFingerDragOnWindows;

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
    public void Close() {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        try { policy.Rules.Remove(PhoneTrackpad.FirewallName); } finally { Marshal.FinalReleaseComObject(policy); }
    }
}

public sealed class NativeTrackpadInput : ITrackpadInput, IDisposable {
    // PowerToys uses this marker to avoid remapping already-generated shortcuts.
    // Required because the suite swaps left Alt+Tab and Ctrl+Tab.
    // microsoft/PowerToys: src/modules/keyboardmanager/common/KeyboardManagerConstants.h
    private const uint ShortcutMarker = 0x101;
    private readonly PhoneMidiWindows midi = new();
    private bool switching;
    public object GetInfo() => new {platform="windows",midi=midi.Info()};
    public void MidiPort(int id) => midi.Select(id);
    public void Midi(bool note,int channel,int number,int value) => midi.Send(note,channel,number,value);
    public void MidiPanic() => midi.Panic();
    public void ReleaseAll() { try { Release(); } finally { try { AppsEnd(); } finally { midi.Panic(); } } }
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
    public void Move(int x, int y) { if (x != 0 || y != 0) Send(0x0001, x, y); }
    public void Scroll(int x, int y) { if (y != 0) Send(0x0800, data: y); if (x != 0) Send(0x1000, data: x); }
    public void Click(bool right) {
        if (held) return;
        uint down = right ? 0x0008u : 0x0002u, up = right ? 0x0010u : 0x0004u;
        try { Send(down); } finally { Send(up); }
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
    private static Input KeyEvent(ushort key,bool up=false) => new() { Type=1,Data=new InputData { Keyboard=new Keyboard { Key=key,Extra=(UIntPtr)ShortcutMarker,Flags=(up?2u:0u) | (key==0x5B || key==0x25 || key==0x27 ? 1u:0u) } } };
    private static void Keys(params Input[] keys) { if(SendInput((uint)keys.Length,keys,Marshal.SizeOf<Input>())!=keys.Length) throw new InvalidOperationException("Windows could not accept the shortcut."); }
    private static void ReleaseKeys(params ushort[] keys) { foreach(var key in keys) SendInput(1,new[]{KeyEvent(key,true)},Marshal.SizeOf<Input>()); }
    public void AppsBegin() {
        if(switching) return;
        switching=true;
        try { Keys(KeyEvent(0x12)); AppsStep(1); } catch { AppsEnd(); throw; }
    }
    public void AppsStep(int direction) {
        if(!switching || direction==0) return;
        try { if(direction<0) Keys(KeyEvent(0x10)); Keys(KeyEvent(0x09)); }
        finally { ReleaseKeys(0x09); if(direction<0) ReleaseKeys(0x10); }
    }
    public void AppsEnd() { if(switching) { switching=false; ReleaseKeys(0x09,0x12); } }
    public void Desktop(int direction) {
        if(direction==0) return;
        ReleaseAll(); ushort arrow=direction<0?(ushort)0x25:(ushort)0x27;
        try { Keys(KeyEvent(0x5B),KeyEvent(0x11),KeyEvent(arrow),KeyEvent(arrow,true)); }
        finally { ReleaseKeys(arrow,0x11,0x5B); }
    }
    public void Media(int action) { ushort key=action==1?(ushort)0xB1:action==2?(ushort)0xB0:(ushort)0xB3; try { Keys(KeyEvent(key)); } finally { ReleaseKeys(key); } }
}
