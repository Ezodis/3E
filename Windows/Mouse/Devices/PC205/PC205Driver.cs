// SPDX-License-Identifier: MIT
// PC205 driver: picks the HID collections like the vendor's CDrv8832::FindDev and sends the
// same feature reports in the same order as Apply_M_AJ_8832_3 (PROTOCOL.md).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace ThreeE.Mouse.Devices.PC205;

public sealed class PC205Driver : IMouseDriver {
    public static readonly MouseDeviceEntry Entry = new(PC205.Id, PC205.Name, PC205.VendorId, PC205.ProductId, () => new PC205Driver());

    HidCollection general, matrix, mode;
    List<HidCollection> collections = new();
    GeneralReport lastGeneral;

    public string Id => PC205.Id;
    public string DisplayName => PC205.Name;
    public MouseCapabilities Capabilities => PC205.Capabilities;
    public MouseProfile DefaultProfile() => PC205.DefaultProfile();
    public Action<string> Log { get; set; } = _ => { };
    public bool Ready => general != null && matrix != null;

    public bool Connect() {
        collections = HidDevices.Enumerate(PC205.VendorId, PC205.ProductId).ToList();
        foreach (var c in collections) Log("found " + c);
        var vendor = collections.Where(c => c.UsagePage == PC205.VendorUsagePage).ToList();
        if (vendor.Count == 0) vendor = collections;
        general = vendor.FirstOrDefault(c => c.FeatureLength == PC205.GeneralPayload + 1);
        matrix = vendor.FirstOrDefault(c => c.FeatureLength == PC205.MatrixPayload + 1);
        mode = vendor.FirstOrDefault(c => c.FeatureLength == PC205.ModePayload + 1);
        Log($"general: {general?.ToString() ?? "none"}; matrix: {matrix?.ToString() ?? "none"}; mode: {mode?.ToString() ?? "none"}");
        return Ready;
    }

    GeneralReport ReadGeneral() => GeneralReport.FromFeature(HidDevices.GetFeature(general, PC205.GeneralReportId, PC205.GeneralPayload + 1));
    ModeReport ReadMode() => mode == null ? null : ModeReport.FromFeature(HidDevices.GetFeature(mode, PC205.ModeReportId, PC205.ModePayload + 1));

    public string Read(MouseProfile profile) {
        if (!Ready) throw new IOException("PC205 not connected.");
        lastGeneral = ReadGeneral();
        PC205Codec.LoadFrom(profile, lastGeneral);
        var m = ReadMode();
        if (m != null) PC205Codec.LoadFrom(profile, m);
        // The vendor app never reads the matrix back either; buttons and macros come from the saved profile.
        return $"sensor code {lastGeneral.SensorCode}, signature {(lastGeneral.SignatureOk ? "OK" : "unexpected")}; buttons and macros come from the saved profile (the mouse can't report them)";
    }

    public void Apply(MouseProfile p, MouseParts parts) {
        if (!Ready) throw new IOException("PC205 configuration interface not found.");
        if ((parts & (MouseParts.Dpi | MouseParts.Lighting)) != 0) {
            var g = ReadGeneral();
            if (!g.SignatureOk) Log("warning: general report signature is not FR2763 – writing anyway");
            PC205Codec.ApplyTo(p, g, parts);
            Thread.Sleep(20);
            HidDevices.SetFeature(general, g.Feature);
            lastGeneral = g;
            Log("SetFeature(4) ok");
        }
        if (parts.HasFlag(MouseParts.Polling) && mode != null) {
            Thread.Sleep(20);
            var m = ReadMode();
            PC205Codec.ApplyTo(p, m);
            Thread.Sleep(20);
            HidDevices.SetFeature(mode, m.Feature);
            Log("SetFeature(8) ok");
        }
        if (parts.HasFlag(MouseParts.Buttons)) {
            Thread.Sleep(20);
            HidDevices.SetFeature(matrix, PC205Codec.MatrixFeature(p));
            Log("SetFeature(6) ok");
        }
    }

    public IEnumerable<string> Diagnostics() {
        foreach (var c in collections) yield return c.ToString();
        if (mode == null && Ready) yield return "Mode / polling-rate collection (feature 8) not found: polling rate can't be applied.";
        if (lastGeneral != null) yield return "General report (ID 4): " + BitConverter.ToString(lastGeneral.Feature).Replace("-", " ");
    }
}
