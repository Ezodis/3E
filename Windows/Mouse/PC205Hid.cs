// SPDX-License-Identifier: MIT
// HID transport for the PC205: the same SetupDi + HidD_SetFeature/HidD_GetFeature calls the
// vendor's Lowerdev.dll makes. Uses only the in-box hid.dll/setupapi.dll (no driver, no service).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace ThreeE.Mouse;

public sealed record HidCollection(string Path, ushort UsagePage, ushort Usage, int InputLength, int OutputLength, int FeatureLength) {
    public override string ToString() => $"UsagePage=0x{UsagePage:X4} Usage=0x{Usage:X2} in={InputLength} out={OutputLength} feature={FeatureLength}";
}

public sealed class PC205Device {
    public HidCollection General { get; private set; }
    public HidCollection Matrix { get; private set; }
    public HidCollection Mode { get; private set; }
    public List<HidCollection> Collections { get; private set; } = new();
    public Action<string> Log { get; set; } = _ => { };
    public bool Ready => General != null && Matrix != null;

    /// Enumerates 258A:1007 collections and picks them by feature length, like CDrv8832::FindDev.
    public bool Connect() {
        Collections = Enumerate().ToList();
        foreach (var c in Collections) Log("found " + c);
        var vendor = Collections.Where(c => c.UsagePage == PC205.VendorUsagePage).ToList();
        if (vendor.Count == 0) vendor = Collections;
        General = vendor.FirstOrDefault(c => c.FeatureLength == PC205.GeneralPayload + 1);
        Matrix = vendor.FirstOrDefault(c => c.FeatureLength == PC205.MatrixPayload + 1);
        Mode = vendor.FirstOrDefault(c => c.FeatureLength == PC205.ModePayload + 1);
        Log($"general: {General?.ToString() ?? "none"}\nmatrix:  {Matrix?.ToString() ?? "none"}\nmode:    {Mode?.ToString() ?? "none"}");
        return Ready;
    }

    public GeneralReport ReadGeneral() => GeneralReport.FromFeature(GetFeature(General ?? throw new IOException("PC205 not connected"), PC205.GeneralReportId, PC205.GeneralPayload + 1));
    public ModeReport ReadMode() => Mode == null ? null : ModeReport.FromFeature(GetFeature(Mode, PC205.ModeReportId, PC205.ModePayload + 1));

    [Flags] public enum Parts { General = 1, Mode = 2, Matrix = 4, All = 7 }

    /// Vendor order (Apply_M_AJ_8832_3): GetFeature(4) → SetFeature(4) → mode (8) → SetFeature(6), 20 ms apart.
    public void Apply(MouseProfile p, Parts parts = Parts.All) {
        if (!Ready) throw new IOException("PC205 configuration interface not found.");
        if (parts.HasFlag(Parts.General)) {
            var g = ReadGeneral();
            if (!g.SignatureOk) Log("warning: general report signature is not FR2763 – writing anyway");
            p.ApplyTo(g);
            Thread.Sleep(20);
            SetFeature(General, g.Feature);
            Log("SetFeature(4) ok");
        }
        if (parts.HasFlag(Parts.Mode) && Mode != null) {
            Thread.Sleep(20);
            var m = ReadMode();
            p.ApplyTo(m);
            Thread.Sleep(20);
            SetFeature(Mode, m.Feature);
            Log("SetFeature(8) ok");
        }
        if (parts.HasFlag(Parts.Matrix)) {
            Thread.Sleep(20);
            SetFeature(Matrix, p.MatrixFeature());
            Log("SetFeature(6) ok");
        }
    }

    // ---- Win32 ----

    static SafeFileHandle Open(string path) {
        var h = CreateFile(path, 0xC0000000 /* GENERIC_READ|WRITE */, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) {
            h.Dispose();
            h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); // feature reports work without read/write access
        }
        if (h.IsInvalid) throw new IOException($"Cannot open PC205 HID collection (error {Marshal.GetLastWin32Error()}).");
        return h;
    }

    static void SetFeature(HidCollection c, byte[] report) {
        var buf = new byte[Math.Max(report.Length, c.FeatureLength)];
        Array.Copy(report, buf, report.Length);
        using var h = Open(c.Path);
        for (int attempt = 0; ; attempt++) {
            if (HidD_SetFeature(h, buf, buf.Length)) return;
            if (attempt == 2) throw new IOException($"SetFeature(0x{report[0]:X2}) failed (error {Marshal.GetLastWin32Error()}).");
            Thread.Sleep(200);
        }
    }

    static byte[] GetFeature(HidCollection c, byte id, int length) {
        var buf = new byte[Math.Max(length, c.FeatureLength)];
        using var h = Open(c.Path);
        for (int attempt = 0; ; attempt++) {
            buf[0] = id;
            if (HidD_GetFeature(h, buf, buf.Length)) return buf.Take(length).ToArray();
            if (attempt == 2) throw new IOException($"GetFeature(0x{id:X2}) failed (error {Marshal.GetLastWin32Error()}).");
            Thread.Sleep(200);
        }
    }

    public static IEnumerable<HidCollection> Enumerate() {
        HidD_GetHidGuid(out var guid);
        var set = SetupDiGetClassDevs(ref guid, null, IntPtr.Zero, 0x12 /* PRESENT|DEVICEINTERFACE */);
        if (set == new IntPtr(-1)) yield break;
        try {
            var data = new SP_DEVICE_INTERFACE_DATA { cbSize = Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>() };
            for (uint i = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data); i++) {
                SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out int size, IntPtr.Zero);
                if (size <= 0) continue;
                var detail = Marshal.AllocHGlobal(size);
                string path;
                try {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref data, detail, size, out _, IntPtr.Zero)) continue;
                    path = Marshal.PtrToStringUni(detail + 4);
                } finally { Marshal.FreeHGlobal(detail); }
                if (path == null || path.IndexOf("vid_258a&pid_1007", StringComparison.OrdinalIgnoreCase) < 0) continue;
                var c = Describe(path);
                if (c != null) yield return c;
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
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
