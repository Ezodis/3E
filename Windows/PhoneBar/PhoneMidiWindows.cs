// SPDX-License-Identifier: MIT
using System;
using System.Linq;
using System.Runtime.InteropServices;
using ThreeE.PhoneControl;
namespace ThreeE.PhoneBar.Windows;

public sealed class PhoneMidiWindows : MidiOutput {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] private struct Caps {
        public ushort Manufacturer, Product; public uint Driver;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Name;
        public ushort Technology, Voices, Notes, Channels; public uint Support;
    }
    [DllImport("winmm.dll")] private static extern uint midiOutGetNumDevs();
    [DllImport("winmm.dll",CharSet=CharSet.Unicode)] private static extern uint midiOutGetDevCapsW(UIntPtr id, ref Caps caps, uint size);
    [DllImport("winmm.dll")] private static extern uint midiOutOpen(out IntPtr handle, uint id, IntPtr callback, IntPtr instance, uint flags);
    [DllImport("winmm.dll")] private static extern uint midiOutShortMsg(IntPtr handle, uint message);
    [DllImport("winmm.dll")] private static extern uint midiOutClose(IntPtr handle);
    private IntPtr handle;
    public override MidiPort[] Ports() {
        try { return Enumerable.Range(0,(int)midiOutGetNumDevs()).Select(id => {
            var caps = new Caps(); return midiOutGetDevCapsW((UIntPtr)id,ref caps,(uint)Marshal.SizeOf<Caps>()) == 0 ? new MidiPort(id,caps.Name) : null;
        }).Where(p=>p!=null).ToArray(); } catch { return Array.Empty<MidiPort>(); }
    }
    protected override void Open(int id) { if (midiOutOpen(out handle,(uint)id,IntPtr.Zero,IntPtr.Zero,0)!=0) throw new InvalidOperationException("Cannot open MIDI output. Check the port and try again."); }
    protected override void Close() { if(handle!=IntPtr.Zero) { midiOutClose(handle); handle=IntPtr.Zero; } }
    protected override void Write(byte status,byte number,byte value) {
        if(handle==IntPtr.Zero || midiOutShortMsg(handle,(uint)(status | number<<8 | value<<16))!=0) throw new InvalidOperationException("MIDI output disconnected");
    }
}
