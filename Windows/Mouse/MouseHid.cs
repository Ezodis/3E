// SPDX-License-Identifier: MIT
// Generic HID access for 3£ Mouse device drivers, plus the device registry.
// Uses only the in-box hid.dll / setupapi.dll (no driver, no service).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace ThreeE.Mouse;

/// A supported mouse model: matched by USB VID/PID, created on demand.
public sealed record MouseDeviceEntry(string Id, string Name, ushort VendorId, ushort ProductId, Func<IMouseDriver> Create);

public static class MouseDevices {
    /// Every supported mouse. Adding a mouse = adding its Devices/<Name>/ module and one line here.
    public static readonly MouseDeviceEntry[] Supported = {
        Devices.PC205.PC205Driver.Entry,
    };

    /// Supported mice that are currently plugged in.
    public static List<MouseDeviceEntry> Detect() {
        var present = HidDevices.PresentVidPids();
        return Supported.Where(e => present.Contains((e.VendorId, e.ProductId))).ToList();
    }
}

public sealed record HidCollection(string Path, ushort UsagePage, ushort Usage, int InputLength, int OutputLength, int FeatureLength) {
    public override string ToString() => $"UsagePage=0x{UsagePage:X4} Usage=0x{Usage:X2} in={InputLength} out={OutputLength} feature={FeatureLength}";
}

public static class HidDevices {
    static SafeFileHandle Open(string path) {
        var h = CreateFile(path, 0xC0000000 /* GENERIC_READ|WRITE */, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) {
            h.Dispose();
            h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); // feature reports work without read/write access
        }
        if (h.IsInvalid) throw new IOException($"Cannot open the mouse's HID collection (error {Marshal.GetLastWin32Error()}).");
        return h;
    }

    /// `report[0]` is the report ID. Retries 3× with 200 ms between tries, like the vendor tools.
    public static void SetFeature(HidCollection c, byte[] report) {
        var buf = new byte[Math.Max(report.Length, c.FeatureLength)];
        Array.Copy(report, buf, report.Length);
        using var h = Open(c.Path);
        for (int attempt = 0; ; attempt++) {
            if (HidD_SetFeature(h, buf, buf.Length)) return;
            if (attempt == 2) throw new IOException($"SetFeature(0x{report[0]:X2}) failed (error {Marshal.GetLastWin32Error()}).");
            Thread.Sleep(200);
        }
    }

    /// Returns `length` bytes starting with the report ID.
    public static byte[] GetFeature(HidCollection c, byte id, int length) {
        var buf = new byte[Math.Max(length, c.FeatureLength)];
        using var h = Open(c.Path);
        for (int attempt = 0; ; attempt++) {
            buf[0] = id;
            if (HidD_GetFeature(h, buf, buf.Length)) return buf.Take(length).ToArray();
            if (attempt == 2) throw new IOException($"GetFeature(0x{id:X2}) failed (error {Marshal.GetLastWin32Error()}).");
            Thread.Sleep(200);
        }
    }

    public static HashSet<(ushort, ushort)> PresentVidPids() {
        var set = new HashSet<(ushort, ushort)>();
        foreach (var path in Paths()) {
            int v = path.IndexOf("vid_", StringComparison.OrdinalIgnoreCase), p = path.IndexOf("pid_", StringComparison.OrdinalIgnoreCase);
            if (v >= 0 && p >= 0 && v + 8 <= path.Length && p + 8 <= path.Length &&
                ushort.TryParse(path.AsSpan(v + 4, 4), System.Globalization.NumberStyles.HexNumber, null, out var vid) &&
                ushort.TryParse(path.AsSpan(p + 4, 4), System.Globalization.NumberStyles.HexNumber, null, out var pid))
                set.Add((vid, pid));
        }
        return set;
    }

    public static IEnumerable<HidCollection> Enumerate(ushort vid, ushort pid) {
        string tag = $"vid_{vid:x4}&pid_{pid:x4}";
        foreach (var path in Paths()) {
            if (path.IndexOf(tag, StringComparison.OrdinalIgnoreCase) < 0) continue;
            var c = Describe(path);
            if (c != null) yield return c;
        }
    }

    static List<string> Paths() {
        var list = new List<string>();
        HidD_GetHidGuid(out var guid);
        var set = SetupDiGetClassDevs(ref guid, null, IntPtr.Zero, 0x12 /* PRESENT|DEVICEINTERFACE */);
        if (set == new IntPtr(-1)) return list;
        try {
            var data = new SP_DEVICE_INTERFACE_DATA { cbSize = Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>() };
            for (uint i = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data); i++) {
                SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out int size, IntPtr.Zero);
                if (size <= 0) continue;
                var detail = Marshal.AllocHGlobal(size);
                try {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(set, ref data, detail, size, out _, IntPtr.Zero)) {
                        var path = Marshal.PtrToStringUni(detail + 4);
                        if (path != null) list.Add(path);
                    }
                } finally { Marshal.FreeHGlobal(detail); }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }

    static HidCollection Describe(string path) {
        using var h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) return null;
        if (!HidD_GetPreparsedData(h, out var pre)) return null;
        try {
            if (HidP_GetCaps(pre, out var caps) != 0x00110000 /* HIDP_STATUS_SUCCESS */) return null;
            return new HidCollection(path, caps.UsagePage, caps.Usage, caps.InputReportByteLength, caps.OutputReportByteLength, caps.FeatureReportByteLength);
        } finally { HidD_FreePreparsedData(pre); }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices,
            NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices,
            NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid guid);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetFeature(SafeFileHandle h, byte[] buffer, int length);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buffer, int length);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern IntPtr SetupDiGetClassDevs(ref Guid guid, string enumerator, IntPtr parent, int flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, uint index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int size, out int required, IntPtr info);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
}
