// SPDX-License-Identifier: MIT
// Thunderbird PC205 (Sinowealth 258A:1007, "8832" firmware, MsFw=7): capabilities and encoding.
// Pure code (tested by Windows/MouseTests). Specification: Shared/PC205/PROTOCOL.md.
using System;
using System.Collections.Generic;
using System.Linq;

namespace ThreeE.Mouse.Devices.PC205;

public static class PC205 {
    public const string Id = "pc205", Name = "Thunderbird PC205";
    public const ushort VendorId = 0x258A, ProductId = 0x1007;
    public const ushort VendorUsagePage = 0xFF00;
    public const byte GeneralReportId = 4, MatrixReportId = 6, ModeReportId = 8;
    public const int GeneralPayload = 58, MatrixPayload = 0x478, ModePayload = 8;
    public const int Slots = 10, Modes = 3, DpiStages = 8, MacroCount = 8, MacroSize = 128, MacroMaxDelay = 0x641B;
    public const int MacroAreaSize = MacroCount * MacroSize;
    public static readonly int[] DpiTable = { 500, 800, 1000, 1200, 1600, 2000, 2400, 3000, 3200, 3500, 4000, 4500, 5000, 5500, 6000, 7200 };
    public static readonly byte[] Signature = { 0x46, 0x52, 0x32, 0x37, 0x36, 0x33 }; // "FR2763"
    public static readonly int[] PollingHz = { 125, 250, 500, 1000 }; // codes 1…4

    public static readonly MouseCapabilities Capabilities = new() {
        Slots = Slots,
        SlotNames = new[] { "Slot 1 – Left", "Slot 2 – Right", "Slot 3 – Middle (wheel)", "Slot 4 – Back (MB4)", "Slot 5 – Forward (MB5)",
            "Slot 6 – DPI +", "Slot 7 – DPI −", "Slot 8 – Extra side button?", "Slot 9", "Slot 10" },
        Modes = Modes,
        Actions = Enum.GetValues<ActionKind>(),
        MediaKeys = Enum.GetValues<MediaKey>(),
        MouseButtons = 5,
        ExtraSideSlot = 8,
        IdentifySlots = new[] { 4, 5, 6, 7, 8, 9, 10 },
        DpiStages = DpiStages,
        DpiValues = DpiTable,
        DpiXy = true,
        DpiColorNames = new[] { "None", "Red", "Green", "Blue", "Cyan", "Yellow", "Magenta", "White" },
        LightingEffects = new[] { "Colorful Streaming", "Steady", "Breathing", "Tail", "Neon", "Colorful Steady", "Flicker",
            "Response", "Streaming", "Wave", "Trailing", "Off (None)" },
        LightingEffectsHidden = new[] { 5, 6, 8, 10 }, // LedMask=0x560
        LightingColors = 7,
        LightingLevelMax = 8,
        LightingRandom = true,
        PollingRatesHz = PollingHz,
        MacroCount = MacroCount,
        MacroMaxDelayMs = MacroMaxDelay,
        MacroBytes = MacroSize,
    };

    public static byte DpiCode(int dpi) {
        int best = 0;
        for (int i = 1; i < DpiTable.Length; i++) if (Math.Abs(DpiTable[i] - dpi) < Math.Abs(DpiTable[best] - dpi)) best = i;
        return (byte)(best + 1);
    }
    public static int DpiForCode(byte code) { int i = (code & 0x7F) - 1; return i >= 0 && i < DpiTable.Length ? DpiTable[i] : 0; }

    /// Vendor Cfg.ini defaults (K1…K10, DPI, DC, DR) plus the extra side button sending F13 (3£ LoL Kalista kite key).
    public static MouseProfile DefaultProfile(bool lolSideKey = true) {
        var p = new MouseProfile { CurrentStage = 1, Effect = 2, Level = 4,
            Colors = new[] { 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0xFFFFFF }, RatesHz = new[] { 500, 500, 500 } };
        for (int m = 0; m < Modes; m++) p.Buttons.Add(new List<ButtonAction> {
            ButtonAction.MouseButton(0), ButtonAction.MouseButton(1), ButtonAction.MouseButton(2), ButtonAction.MouseButton(3), ButtonAction.MouseButton(4),
            ButtonAction.Simple(ActionKind.DpiUp), ButtonAction.Simple(ActionKind.DpiDown),
            lolSideKey ? ButtonAction.KeyPress(HidKeys.F13) : ButtonAction.Simple(ActionKind.TripleClick),
            ButtonAction.Simple(ActionKind.SwitchLighting), ButtonAction.Simple(ActionKind.SwitchLighting) });
        for (int i = 1; i <= MacroCount; i++) p.Macros.Add(new Macro { Name = "Macro " + i });
        int[] dpi = { 1200, 2400, 3500, 5500, 7200, 7200, 7200, 7200 }, col = { 1, 3, 2, 6, 5, 7, 7, 7 };
        for (int i = 0; i < DpiStages; i++) p.Stages.Add(new DpiStage { Enabled = i < 5, X = dpi[i], Y = dpi[i], Color = col[i] });
        return p;
    }
}

/// ButtonAction / Macro ⇄ PC205 firmware bytes (PROTOCOL.md §5).
public static class PC205Codec {
    static readonly (int Byte, byte Bit)[] MediaBits = {
        (1, 0x01), (1, 0x02), (1, 0x04), (1, 0x08), (1, 0x10), (1, 0x40), (1, 0x80),
        (2, 0x01), (2, 0x02), (2, 0x10), (2, 0x20),
        (3, 0x01), (3, 0x02), (3, 0x04), (3, 0x08), (3, 0x10), (3, 0x20), (3, 0x40),
    };

    public static uint Encode(ButtonAction a) => a.Kind switch {
        ActionKind.Mouse => 0xF010u | (uint)(a.Value & 0x0F) << 8,
        ActionKind.DoubleClick => 0x0232F020u,
        ActionKind.TripleClick => 0x0130u,
        ActionKind.Key => 0x60u | (uint)(a.Value2 & 0xFF) << 8 | (uint)(a.Value & 0xFF) << 16 | (a.Value3 & 0xFF) << 24,
        ActionKind.Fire => 0x20u | (uint)(a.Value & 0xFF) << 8 | (uint)(a.Value2 & 0xFF) << 16 | (a.Value3 & 0xFF) << 24,
        ActionKind.Media => 0x70u | (uint)MediaBits[a.Value].Bit << (8 * MediaBits[a.Value].Byte),
        ActionKind.DpiLoop => 0x0040u,
        ActionKind.DpiUp => 0x2040u,
        ActionKind.DpiDown => 0x4040u,
        ActionKind.DpiLock => 0x8040u | (uint)(PC205.DpiCode(a.Value) & 0x0F) << 8,
        ActionKind.Disabled => 0x0150u,
        ActionKind.SwitchPollingRate => 0x0250u,
        ActionKind.SwitchLighting => 0x0750u,
        ActionKind.Macro => 0x90u | (uint)(a.Value2 & 0x0F) << 8 | (uint)(a.Value & 0x0F) << 12,
        _ => a.Value3 & 0xFFFFFFF0u,
    };

    /// Matrix entry: action with the slot number (1…10) in the low nibble (KeyCodeHasIndex=1).
    public static uint Entry(ButtonAction a, int slot) => (Encode(a) & 0xFFFFFFF0u) | (uint)(slot & 0x0F);

    public static ButtonAction Decode(uint entry) {
        uint v = entry & 0xFFFFFFF0u;
        byte b0 = (byte)(v & 0xF0), b1 = (byte)(v >> 8), b2 = (byte)(v >> 16), b3 = (byte)(v >> 24);
        switch (b0) {
            case 0x10 when b2 == 0 && b3 == 0 && (b1 & 0xF0) == 0xF0 && (b1 & 0x0F) <= 4: return ButtonAction.MouseButton(b1 & 0x0F);
            case 0x20: return v == 0x0232F020u ? ButtonAction.Simple(ActionKind.DoubleClick) : ButtonAction.Fire(b1, b2, b3);
            case 0x30 when v == 0x0130u: return ButtonAction.Simple(ActionKind.TripleClick);
            case 0x40:
                if (v == 0x0040u) return ButtonAction.Simple(ActionKind.DpiLoop);
                if (v == 0x2040u) return ButtonAction.Simple(ActionKind.DpiUp);
                if (v == 0x4040u) return ButtonAction.Simple(ActionKind.DpiDown);
                if ((b1 & 0x80) != 0 && PC205.DpiForCode((byte)(b1 & 0x0F)) != 0) return ButtonAction.DpiLock(PC205.DpiForCode((byte)(b1 & 0x0F)));
                break;
            case 0x50:
                if (v == 0x0150u) return ButtonAction.Simple(ActionKind.Disabled);
                if (v == 0x0250u) return ButtonAction.Simple(ActionKind.SwitchPollingRate);
                if (v == 0x0750u) return ButtonAction.Simple(ActionKind.SwitchLighting);
                break;
            case 0x60: return ButtonAction.KeyPress(b2, b1, b3);
            case 0x70:
                for (int i = 0; i < MediaBits.Length; i++) if (Encode(ButtonAction.Media((MediaKey)i)) == v) return ButtonAction.Media((MediaKey)i);
                break;
            case 0x90 when (b1 & 0x0F) is 1 or 2 or 4: return ButtonAction.Macro(b1 >> 4, (MacroRepeat)(b1 & 0x0F));
        }
        return ButtonAction.Raw(v);
    }

    /// 128-byte macro buffer, MacProtocol=2.
    public static byte[] EncodeMacro(Macro m) {
        var o = new byte[PC205.MacroSize];
        ushort rc = m.RepeatCount == 0 ? (ushort)1 : m.RepeatCount;
        o[0] = (byte)(rc >> 8); o[1] = (byte)rc;
        int i = 2;
        foreach (var e in m.Events) {
            int d = Math.Clamp(e.DelayMs, 0, PC205.MacroMaxDelay);
            bool longForm = d > 0x7F;
            if (i >= (longForm ? PC205.MacroSize - 5 : PC205.MacroSize - 3)) break;
            byte flag = e.Press ? (byte)0x80 : (byte)0;
            if (longForm) { o[i] = (byte)(flag | d % 100); o[i + 1] = e.Key; o[i + 2] = (byte)(d / 100); o[i + 3] = 3; i += 4; }
            else { o[i] = (byte)(flag | (d == 0 ? 1 : d)); o[i + 1] = e.Key; i += 2; }
        }
        return o;
    }

    public static Macro DecodeMacro(byte[] b, string name) {
        var m = new Macro { Name = name, RepeatCount = (ushort)(b[0] << 8 | b[1]) };
        for (int i = 2; i + 1 < b.Length;) {
            byte f = b[i], k = b[i + 1];
            if (f == 0 && k == 0) break;
            if (i + 3 < b.Length && b[i + 3] == 3 && (f & 0x7F) < 100 && b[i + 2] > 0) {
                m.Events.Add(new MacroEvent { Key = k, Press = (f & 0x80) != 0, DelayMs = (f & 0x7F) + 100 * b[i + 2] }); i += 4;
            } else { m.Events.Add(new MacroEvent { Key = k, Press = (f & 0x80) != 0, DelayMs = f & 0x7F }); i += 2; }
        }
        return m;
    }

    /// Matrix report (feature 6) payload: 8 macro buffers, then 3 modes × 10 little-endian key entries.
    public static byte[] MatrixPayload(MouseProfile p) {
        var o = new byte[PC205.MatrixPayload];
        foreach (var n in p.Buttons.SelectMany(r => r).Where(a => a.Kind == ActionKind.Macro).Select(a => a.Value).Distinct()) {
            if (n < 1 || n > PC205.MacroCount || n > p.Macros.Count) continue;
            Array.Copy(EncodeMacro(p.Macros[n - 1]), 0, o, (n - 1) * PC205.MacroSize, PC205.MacroSize);
        }
        int off = PC205.MacroAreaSize;
        for (int m = 0; m < PC205.Modes; m++)
            for (int s = 0; s < PC205.Slots; s++) {
                var a = m < p.Buttons.Count && s < p.Buttons[m].Count ? p.Buttons[m][s] : ButtonAction.Simple(ActionKind.Disabled);
                uint v = Entry(a, s + 1);
                o[off] = (byte)v; o[off + 1] = (byte)(v >> 8); o[off + 2] = (byte)(v >> 16); o[off + 3] = (byte)(v >> 24);
                off += 4;
            }
        return o;
    }

    public static byte[] MatrixFeature(MouseProfile p) => new[] { PC205.MatrixReportId }.Concat(MatrixPayload(p)).ToArray();

    public static void ApplyTo(MouseProfile p, GeneralReport g, MouseParts parts) {
        if (parts.HasFlag(MouseParts.Dpi)) { g.XyIndependent = p.XyIndependent; g.Stages = p.Stages; g.CurrentStage = p.CurrentStage; }
        if (parts.HasFlag(MouseParts.Lighting)) {
            g.Effect = p.Effect; g.Level = p.Level; g.Colors = p.Colors;
            g.LightingFlags = (byte)((p.LightingRandom ? 0x80 : 0) | (g.LightingFlags & 0x78) | (p.LightingColorCount & 0x07));
        }
    }

    public static void ApplyTo(MouseProfile p, ModeReport m) {
        m.ActiveMode = p.ActiveMode;
        for (int i = 0; i < PC205.Modes; i++) m.SetRateHz(i, p.RatesHz.ElementAtOrDefault(i) is int hz and > 0 ? hz : 500);
    }

    public static void LoadFrom(MouseProfile p, GeneralReport g) {
        p.XyIndependent = g.XyIndependent;
        var stages = g.Stages;
        for (int i = 0; i < stages.Count; i++) if (stages[i].X == 0 && i < p.Stages.Count) { stages[i].X = p.Stages[i].X; stages[i].Y = p.Stages[i].Y; }
        p.Stages = stages; p.CurrentStage = g.CurrentStage; p.Effect = g.Effect; p.Level = g.Level; p.Colors = g.Colors;
        p.LightingRandom = (g.LightingFlags & 0x80) != 0; p.LightingColorCount = g.LightingFlags & 0x07;
    }

    public static void LoadFrom(MouseProfile p, ModeReport m) {
        p.ActiveMode = m.ActiveMode;
        p.RatesHz = Enumerable.Range(0, PC205.Modes).Select(m.RateHz).ToArray();
    }
}

/// General report (feature 4), 58-byte payload. Read-modify-write keeps unknown bytes.
public sealed class GeneralReport {
    public byte[] Bytes { get; }
    public GeneralReport(byte[] payload) { Bytes = new byte[PC205.GeneralPayload]; Array.Copy(payload, Bytes, Math.Min(payload.Length, Bytes.Length)); }
    public static GeneralReport FromFeature(byte[] feature) => new(feature.Skip(1).ToArray());
    public byte[] Feature => new[] { PC205.GeneralReportId }.Concat(Bytes).ToArray();
    public byte SensorCode => Bytes[0];
    public bool SignatureOk => Bytes.Skip(52).Take(6).SequenceEqual(PC205.Signature);
    public int CurrentStage { get => Bytes[1] >> 4; set => Bytes[1] = (byte)((Bytes[1] & 0x0F) | (value & 0x0F) << 4); }
    public bool XyIndependent { get => (Bytes[2] & 0x0F) != 0; set => Bytes[2] = (byte)((Bytes[2] & 0xF0) | (value ? 1 : 0)); }
    /// Effect index (11 = off) ⇄ high nibble of byte 20 (index+1, 0 = off).
    public int Effect { get => Bytes[20] >> 4 == 0 ? 11 : (Bytes[20] >> 4) - 1; set => Bytes[20] = (byte)(((value >= 11 ? 0 : value + 1) << 4) | (Bytes[20] & 0x0F)); }
    public int Level { get => Bytes[20] & 0x0F; set => Bytes[20] = (byte)((Bytes[20] & 0xF0) | Math.Clamp(value, 0, 15)); }
    public byte LightingFlags { get => Bytes[21]; set => Bytes[21] = value; }

    public List<DpiStage> Stages {
        get {
            var list = new List<DpiStage>();
            for (int i = 0; i < PC205.DpiStages; i++) {
                byte x = XyIndependent ? Bytes[4 + 2 * i] : Bytes[4 + i], y = XyIndependent ? Bytes[5 + 2 * i] : x;
                list.Add(new DpiStage { Enabled = (x & 0x80) == 0, X = PC205.DpiForCode(x), Y = PC205.DpiForCode(y), Color = Bytes[43 + i] & 7 });
            }
            return list;
        }
        set {
            for (int i = 4; i <= 19; i++) Bytes[i] = 0x80;
            int enabled = 0;
            for (int i = 0; i < PC205.DpiStages && i < value.Count; i++) {
                var s = value[i]; byte flag = s.Enabled ? (byte)0 : (byte)0x80;
                if (XyIndependent) { Bytes[4 + 2 * i] = (byte)(PC205.DpiCode(s.X) | flag); Bytes[5 + 2 * i] = (byte)(PC205.DpiCode(s.Y) | flag); }
                else Bytes[4 + i] = (byte)(PC205.DpiCode(s.X) | flag);
                Bytes[43 + i] = (byte)(s.Color & 7);
                if (s.Enabled) enabled++;
            }
            Bytes[1] = (byte)((Bytes[1] & 0xF0) | (enabled & 0x0F));
        }
    }

    /// Seven lighting colours, R,G,B order, as 0xRRGGBB.
    public int[] Colors {
        get => Enumerable.Range(0, 7).Select(i => Bytes[22 + 3 * i] << 16 | Bytes[23 + 3 * i] << 8 | Bytes[24 + 3 * i]).ToArray();
        set { for (int i = 0; i < 7; i++) { int c = value != null && i < value.Length ? value[i] : 0; Bytes[22 + 3 * i] = (byte)(c >> 16); Bytes[23 + 3 * i] = (byte)(c >> 8); Bytes[24 + 3 * i] = (byte)c; } }
    }
}

/// Mode report (feature 8): [activeMode+1, rate mode1, rate mode2, rate mode3, preserved…]. Rates 1…4 = 125…1000 Hz.
public sealed class ModeReport {
    public byte[] Bytes { get; }
    public ModeReport(byte[] payload) { Bytes = new byte[PC205.ModePayload]; Array.Copy(payload, Bytes, Math.Min(payload.Length, Bytes.Length)); }
    public static ModeReport FromFeature(byte[] feature) => new(feature.Skip(1).ToArray());
    public byte[] Feature => new[] { PC205.ModeReportId }.Concat(Bytes).ToArray();
    public int ActiveMode { get => Math.Max(0, Bytes[0] - 1); set => Bytes[0] = (byte)(Math.Clamp(value, 0, PC205.Modes - 1) + 1); }
    public int RateHz(int mode) => Bytes[1 + mode] is >= 1 and <= 4 ? PC205.PollingHz[Bytes[1 + mode] - 1] : 500;
    public void SetRateHz(int mode, int hz) => Bytes[1 + mode] = (byte)(Math.Max(0, Array.IndexOf(PC205.PollingHz, hz)) + 1);
}
