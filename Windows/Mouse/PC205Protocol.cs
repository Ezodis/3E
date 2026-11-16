// SPDX-License-Identifier: MIT
// Thunderbird PC205 (Sinowealth 258A:1007, "8832" firmware, MsFw=7) configuration protocol.
// Pure encoding/decoding with no Windows dependency (tested by Windows/MouseTests).
// Specification: Shared/PC205/PROTOCOL.md. The Mac twin is TouchBar/threee/PC205/Sources/PC205Core.
using System;
using System.Collections.Generic;
using System.Linq;

namespace ThreeE.Mouse;

public static class PC205 {
    public const ushort VendorId = 0x258A, ProductId = 0x1007;
    public const ushort VendorUsagePage = 0xFF00, VendorUsage = 0x01;
    public const byte GeneralReportId = 4, MatrixReportId = 6, ModeReportId = 8;
    public const int GeneralPayload = 58, MatrixPayload = 0x478, ModePayload = 8;
    public const int Slots = 10, Modes = 3, DpiStages = 8, MacroCount = 8, MacroSize = 128;
    public const int MacroAreaSize = MacroCount * MacroSize;
    public const int LikelyExtraSideSlot = 8;
    public static readonly int[] DpiTable = { 500, 800, 1000, 1200, 1600, 2000, 2400, 3000, 3200, 3500, 4000, 4500, 5000, 5500, 6000, 7200 };
    public static readonly byte[] Signature = { 0x46, 0x52, 0x32, 0x37, 0x36, 0x33 }; // "FR2763"
    public static readonly string[] SlotNames = {
        "Slot 1 – Left", "Slot 2 – Right", "Slot 3 – Middle (wheel)", "Slot 4 – Back (MB4)", "Slot 5 – Forward (MB5)",
        "Slot 6 – DPI +", "Slot 7 – DPI −", "Slot 8 – Extra side button?", "Slot 9", "Slot 10",
    };
    public static readonly string[] EffectNames = {
        "Colorful Streaming", "Steady", "Breathing", "Tail", "Neon", "Colorful Steady", "Flicker",
        "Response", "Streaming", "Wave", "Trailing", "Off (None)",
    };
    public static readonly int[] EffectsHiddenByVendor = { 5, 6, 8, 10 }; // LedMask=0x560
    public static readonly string[] DpiColorNames = { "None", "Red", "Green", "Blue", "Cyan", "Yellow", "Magenta", "White" };
    public static readonly int[] PollingHz = { 125, 250, 500, 1000 }; // codes 1…4

    public static byte DpiCode(int dpi) {
        int best = 0;
        for (int i = 1; i < DpiTable.Length; i++) if (Math.Abs(DpiTable[i] - dpi) < Math.Abs(DpiTable[best] - dpi)) best = i;
        return (byte)(best + 1);
    }
    public static int DpiForCode(byte code) { int i = (code & 0x7F) - 1; return i >= 0 && i < DpiTable.Length ? DpiTable[i] : 0; }
}

public enum ActionKind { Mouse, DoubleClick, TripleClick, Key, Fire, Media, DpiUp, DpiDown, DpiLoop, DpiLock, SwitchPollingRate, SwitchLighting, Disabled, Macro, Raw }

public enum MediaKey { Next, Previous, Stop, PlayPause, Mute, VolumeUp, VolumeDown, MediaPlayer, MyComputer, Mail, Calculator, WebSearch, WebHome, WebBack, WebForward, WebStop, WebRefresh, WebFavorites }

/// One button function. Serialised to JSON as-is; Encode() gives the 32-bit firmware entry (PROTOCOL.md §5).
public sealed record ButtonAction {
    public ActionKind Kind { get; init; }
    /// Mouse: 0 left, 1 right, 2 middle, 3 back, 4 forward. Key/Fire: HID usage. Macro: buffer 1…8. DpiLock: DPI.
    public int Value { get; init; }
    /// Key: HID modifier bits. Fire: interval ms. Macro: repeat mode 1/2/4.
    public int Value2 { get; init; }
    /// Key: second key. Fire: count. Raw: full entry.
    public uint Value3 { get; init; }

    public static ButtonAction MouseButton(int b) => new() { Kind = ActionKind.Mouse, Value = b };
    public static ButtonAction KeyPress(byte usage, byte modifiers = 0, byte key2 = 0) => new() { Kind = ActionKind.Key, Value = usage, Value2 = modifiers, Value3 = key2 };
    public static ButtonAction Simple(ActionKind k) => new() { Kind = k };
    public static ButtonAction Macro(int index, int repeatMode = 1) => new() { Kind = ActionKind.Macro, Value = index, Value2 = repeatMode };
    public static ButtonAction Fire(byte key, byte intervalMs, byte count) => new() { Kind = ActionKind.Fire, Value = key, Value2 = intervalMs, Value3 = count };
    public static ButtonAction Media(MediaKey m) => new() { Kind = ActionKind.Media, Value = (int)m };
    public static ButtonAction DpiLock(int dpi) => new() { Kind = ActionKind.DpiLock, Value = dpi };

    static readonly (int Byte, byte Bit)[] MediaBits = {
        (1, 0x01), (1, 0x02), (1, 0x04), (1, 0x08), (1, 0x10), (1, 0x40), (1, 0x80),
        (2, 0x01), (2, 0x02), (2, 0x10), (2, 0x20),
        (3, 0x01), (3, 0x02), (3, 0x04), (3, 0x08), (3, 0x10), (3, 0x20), (3, 0x40),
    };

    public uint Encode() => Kind switch {
        ActionKind.Mouse => 0xF010u | (uint)(Value & 0x0F) << 8,
        ActionKind.DoubleClick => 0x0232F020u,
        ActionKind.TripleClick => 0x0130u,
        ActionKind.Key => 0x60u | (uint)(Value2 & 0xFF) << 8 | (uint)(Value & 0xFF) << 16 | (Value3 & 0xFF) << 24,
        ActionKind.Fire => 0x20u | (uint)(Value & 0xFF) << 8 | (uint)(Value2 & 0xFF) << 16 | (Value3 & 0xFF) << 24,
        ActionKind.Media => 0x70u | (uint)MediaBits[Value].Bit << (8 * MediaBits[Value].Byte),
        ActionKind.DpiLoop => 0x0040u,
        ActionKind.DpiUp => 0x2040u,
        ActionKind.DpiDown => 0x4040u,
        ActionKind.DpiLock => 0x8040u | (uint)(PC205.DpiCode(Value) & 0x0F) << 8,
        ActionKind.Disabled => 0x0150u,
        ActionKind.SwitchPollingRate => 0x0250u,
        ActionKind.SwitchLighting => 0x0750u,
        ActionKind.Macro => 0x90u | (uint)(Value2 & 0x0F) << 8 | (uint)(Value & 0x0F) << 12,
        _ => Value3 & 0xFFFFFFF0u,
    };

    /// Matrix entry: action with the slot number (1…10) in the low nibble (KeyCodeHasIndex=1).
    public uint Entry(int slot) => (Encode() & 0xFFFFFFF0u) | (uint)(slot & 0x0F);

    public static ButtonAction Decode(uint entry) {
        uint v = entry & 0xFFFFFFF0u;
        byte b0 = (byte)(v & 0xF0), b1 = (byte)(v >> 8), b2 = (byte)(v >> 16), b3 = (byte)(v >> 24);
        switch (b0) {
            case 0x10 when b2 == 0 && b3 == 0 && (b1 & 0xF0) == 0xF0 && (b1 & 0x0F) <= 4: return MouseButton(b1 & 0x0F);
            case 0x20: return v == 0x0232F020u ? Simple(ActionKind.DoubleClick) : Fire(b1, b2, b3);
            case 0x30 when v == 0x0130u: return Simple(ActionKind.TripleClick);
            case 0x40:
                if (v == 0x0040u) return Simple(ActionKind.DpiLoop);
                if (v == 0x2040u) return Simple(ActionKind.DpiUp);
                if (v == 0x4040u) return Simple(ActionKind.DpiDown);
                if ((b1 & 0x80) != 0 && PC205.DpiForCode((byte)(b1 & 0x0F)) != 0) return DpiLock(PC205.DpiForCode((byte)(b1 & 0x0F)));
                break;
            case 0x50:
                if (v == 0x0150u) return Simple(ActionKind.Disabled);
                if (v == 0x0250u) return Simple(ActionKind.SwitchPollingRate);
                if (v == 0x0750u) return Simple(ActionKind.SwitchLighting);
                break;
            case 0x60: return KeyPress(b2, b1, b3);
            case 0x70:
                for (int i = 0; i < MediaBits.Length; i++) if (Media((MediaKey)i).Encode() == v) return Media((MediaKey)i);
                break;
            case 0x90 when (b1 & 0x0F) is 1 or 2 or 4: return Macro(b1 >> 4, b1 & 0x0F);
        }
        return new ButtonAction { Kind = ActionKind.Raw, Value3 = v };
    }

    public string Label => Kind switch {
        ActionKind.Mouse => new[] { "Left click", "Right click", "Middle click", "Back (MB4)", "Forward (MB5)" }[Math.Clamp(Value, 0, 4)],
        ActionKind.Key => "Key: " + HidKeys.ComboName((byte)Value2, (byte)Value, (byte)Value3),
        ActionKind.Fire => $"Fire {HidKeys.Name((byte)Value)} ×{Value3} every {Value2} ms",
        ActionKind.Media => "Media: " + Value switch { _ => ((MediaKey)Value).ToString() },
        ActionKind.DpiLock => $"DPI lock {Value}",
        ActionKind.Macro => $"Macro {Value} ({(Value2 == 2 ? "while held" : Value2 == 4 ? "until any key" : "repeat N times")})",
        ActionKind.Raw => $"Raw 0x{Value3:X8}",
        _ => Kind.ToString(),
    };
}

public sealed class MacroEvent {
    /// HID usage (0x04…0xE7) or 0xF0/0xF1/0xF2 = left/right/middle mouse button.
    public byte Key { get; set; }
    public bool Press { get; set; }
    /// Delay after this event in ms (0…25627).
    public int DelayMs { get; set; }
}

public sealed class Macro {
    public const int MaxDelay = 0x641B;
    public string Name { get; set; } = "Macro";
    public List<MacroEvent> Events { get; set; } = new();
    public ushort RepeatCount { get; set; } = 1;

    public static IEnumerable<MacroEvent> Tap(byte key, int holdMs = 20, int gapMs = 20) => new[] {
        new MacroEvent { Key = key, Press = true, DelayMs = holdMs }, new MacroEvent { Key = key, Press = false, DelayMs = gapMs } };

    /// 128-byte buffer, MacProtocol=2 (PROTOCOL.md §5).
    public byte[] Encode() {
        var o = new byte[PC205.MacroSize];
        ushort rc = RepeatCount == 0 ? (ushort)1 : RepeatCount;
        o[0] = (byte)(rc >> 8); o[1] = (byte)rc;
        int i = 2;
        foreach (var e in Events) {
            int d = Math.Clamp(e.DelayMs, 0, MaxDelay);
            bool longForm = d > 0x7F;
            if (i >= (longForm ? PC205.MacroSize - 5 : PC205.MacroSize - 3)) break;
            byte flag = e.Press ? (byte)0x80 : (byte)0;
            if (longForm) { o[i] = (byte)(flag | d % 100); o[i + 1] = e.Key; o[i + 2] = (byte)(d / 100); o[i + 3] = 3; i += 4; }
            else { o[i] = (byte)(flag | (d == 0 ? 1 : d)); o[i + 1] = e.Key; i += 2; }
        }
        return o;
    }

    public static Macro Decode(byte[] b, string name) {
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
}

public sealed class DpiStage {
    public bool Enabled { get; set; } = true;
    public int X { get; set; } = 1200;
    public int Y { get; set; } = 1200;
    /// 0 none, 1 red, 2 green, 3 blue, 4 cyan, 5 yellow, 6 magenta, 7 white.
    public int Color { get; set; } = 1;
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
        set { for (int i = 0; i < 7; i++) { int c = i < value.Length ? value[i] : 0; Bytes[22 + 3 * i] = (byte)(c >> 16); Bytes[23 + 3 * i] = (byte)(c >> 8); Bytes[24 + 3 * i] = (byte)c; } }
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

/// Everything the vendor app configures. Stored as JSON in %LOCALAPPDATA%\3EWindows\Mouse\profile.json.
public sealed class MouseProfile {
    public List<List<ButtonAction>> Buttons { get; set; } = new();
    public List<Macro> Macros { get; set; } = new();
    public List<DpiStage> Stages { get; set; } = new();
    public int CurrentStage { get; set; } = 1;
    public bool XyIndependent { get; set; }
    public int Effect { get; set; } = 2;
    public int Level { get; set; } = 4;
    public byte LightingFlags { get; set; }
    public int[] Colors { get; set; } = { 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0xFFFFFF };
    public int ActiveMode { get; set; }
    public int[] RatesHz { get; set; } = { 500, 500, 500 };

    /// Cfg.ini defaults (K1…K10, DPI, DC, DR).
    public static MouseProfile VendorDefault() {
        var p = new MouseProfile();
        for (int m = 0; m < PC205.Modes; m++) p.Buttons.Add(new List<ButtonAction> {
            ButtonAction.MouseButton(0), ButtonAction.MouseButton(1), ButtonAction.MouseButton(2), ButtonAction.MouseButton(3), ButtonAction.MouseButton(4),
            ButtonAction.Simple(ActionKind.DpiUp), ButtonAction.Simple(ActionKind.DpiDown), ButtonAction.Simple(ActionKind.TripleClick),
            ButtonAction.Simple(ActionKind.SwitchLighting), ButtonAction.Simple(ActionKind.SwitchLighting) });
        for (int i = 1; i <= PC205.MacroCount; i++) p.Macros.Add(new Macro { Name = "Macro " + i });
        int[] dpi = { 1200, 2400, 3500, 5500, 7200, 7200, 7200, 7200 }, col = { 1, 3, 2, 6, 5, 7, 7, 7 };
        for (int i = 0; i < PC205.DpiStages; i++) p.Stages.Add(new DpiStage { Enabled = i < 5, X = dpi[i], Y = dpi[i], Color = col[i] });
        return p;
    }

    /// Default plus the extra side button sending F13 (3£ LoL Kalista kite key) in every mode.
    public static MouseProfile LolDefault() {
        var p = VendorDefault();
        for (int m = 0; m < PC205.Modes; m++) p.Buttons[m][PC205.LikelyExtraSideSlot - 1] = ButtonAction.KeyPress(HidKeys.F13);
        return p;
    }

    /// Repairs a profile loaded from an older/partial JSON file.
    public MouseProfile Normalized() {
        var d = VendorDefault();
        while (Buttons.Count < PC205.Modes) Buttons.Add(new List<ButtonAction>(d.Buttons[0]));
        foreach (var row in Buttons) while (row.Count < PC205.Slots) row.Add(ButtonAction.Simple(ActionKind.Disabled));
        while (Macros.Count < PC205.MacroCount) Macros.Add(new Macro { Name = "Macro " + (Macros.Count + 1) });
        while (Stages.Count < PC205.DpiStages) Stages.Add(d.Stages[Stages.Count]);
        if (Colors == null || Colors.Length < 7) Colors = d.Colors;
        if (RatesHz == null || RatesHz.Length < PC205.Modes) RatesHz = d.RatesHz;
        return this;
    }

    public byte[] MatrixPayload() {
        var o = new byte[PC205.MatrixPayload];
        var used = Buttons.SelectMany(r => r).Where(a => a.Kind == ActionKind.Macro).Select(a => a.Value).Distinct();
        foreach (var i in used) {
            if (i < 1 || i > PC205.MacroCount || i > Macros.Count) continue;
            Array.Copy(Macros[i - 1].Encode(), 0, o, (i - 1) * PC205.MacroSize, PC205.MacroSize);
        }
        int off = PC205.MacroAreaSize;
        for (int m = 0; m < PC205.Modes; m++)
            for (int s = 0; s < PC205.Slots; s++) {
                var a = m < Buttons.Count && s < Buttons[m].Count ? Buttons[m][s] : ButtonAction.Simple(ActionKind.Disabled);
                BitConverter.TryWriteBytes(o.AsSpan(off, 4), a.Entry(s + 1)); // little-endian on every Windows target
                off += 4;
            }
        return o;
    }

    public byte[] MatrixFeature() => new[] { PC205.MatrixReportId }.Concat(MatrixPayload()).ToArray();

    public void ApplyTo(GeneralReport g) {
        g.XyIndependent = XyIndependent; g.Stages = Stages; g.CurrentStage = CurrentStage;
        g.Effect = Effect; g.Level = Level; g.LightingFlags = LightingFlags; g.Colors = Colors;
    }

    public void ApplyTo(ModeReport m) {
        m.ActiveMode = ActiveMode;
        for (int i = 0; i < PC205.Modes; i++) m.SetRateHz(i, RatesHz[i]);
    }

    public void LoadFrom(GeneralReport g) {
        XyIndependent = g.XyIndependent;
        var stages = g.Stages;
        for (int i = 0; i < stages.Count; i++) if (stages[i].X == 0) { stages[i].X = Stages[i].X; stages[i].Y = Stages[i].Y; }
        Stages = stages; CurrentStage = g.CurrentStage; Effect = g.Effect; Level = g.Level; LightingFlags = g.LightingFlags; Colors = g.Colors;
    }

    public void LoadFrom(ModeReport m) {
        ActiveMode = m.ActiveMode;
        RatesHz = Enumerable.Range(0, PC205.Modes).Select(m.RateHz).ToArray();
    }
}

public static class HidKeys {
    public const byte F13 = 0x68, Pause = 0x48;
    public static readonly IReadOnlyList<(byte Usage, string Name)> All = Build();

    static List<(byte, string)> Build() {
        var e = new List<(byte, string)>();
        for (int i = 0; i < 26; i++) e.Add(((byte)(0x04 + i), ((char)('A' + i)).ToString()));
        for (int i = 0; i < 10; i++) e.Add(((byte)(0x1E + i), "1234567890"[i].ToString()));
        e.AddRange(new (byte, string)[] {
            (0x28, "Enter"), (0x29, "Escape"), (0x2A, "Backspace"), (0x2B, "Tab"), (0x2C, "Space"), (0x2D, "-"), (0x2E, "="),
            (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"), (0x34, "'"), (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock") });
        for (int i = 0; i < 12; i++) e.Add(((byte)(0x3A + i), "F" + (i + 1)));
        e.AddRange(new (byte, string)[] {
            (0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4A, "Home"), (0x4B, "Page Up"),
            (0x4C, "Delete"), (0x4D, "End"), (0x4E, "Page Down"), (0x4F, "Right"), (0x50, "Left"), (0x51, "Down"), (0x52, "Up"),
            (0x53, "Num Lock"), (0x54, "Keypad /"), (0x55, "Keypad *"), (0x56, "Keypad -"), (0x57, "Keypad +"), (0x58, "Keypad Enter") });
        for (int i = 0; i < 9; i++) e.Add(((byte)(0x59 + i), "Keypad " + (i + 1)));
        e.AddRange(new (byte, string)[] { (0x62, "Keypad 0"), (0x63, "Keypad ."), (0x65, "Menu") });
        for (int i = 0; i < 12; i++) e.Add(((byte)(0x68 + i), "F" + (i + 13)));
        e.AddRange(new (byte, string)[] {
            (0xE0, "Left Ctrl"), (0xE1, "Left Shift"), (0xE2, "Left Alt"), (0xE3, "Left Win"),
            (0xE4, "Right Ctrl"), (0xE5, "Right Shift"), (0xE6, "Right Alt"), (0xE7, "Right Win"),
            (0xF0, "Mouse Left"), (0xF1, "Mouse Right"), (0xF2, "Mouse Middle"), (0xF3, "Mouse Back"), (0xF4, "Mouse Forward") });
        return e;
    }

    public static string Name(byte usage) {
        foreach (var (u, n) in All) if (u == usage) return n;
        return $"0x{usage:X2}";
    }

    public static string ComboName(byte mods, byte key, byte key2) {
        var parts = new List<string>();
        if ((mods & 0x11) != 0) parts.Add("Ctrl");
        if ((mods & 0x22) != 0) parts.Add("Shift");
        if ((mods & 0x44) != 0) parts.Add("Alt");
        if ((mods & 0x88) != 0) parts.Add("Win");
        if (key != 0) parts.Add(Name(key));
        if (key2 != 0) parts.Add(Name(key2));
        return parts.Count == 0 ? "(none)" : string.Join(" + ", parts);
    }

    /// Usages present in the vendor's own VK→HID table (others depend on the keyboard descriptor).
    public static bool InVendorTable(byte u) => u is >= 0x04 and <= 0x65 or 0x85 or 0x87 or >= 0xE0 and <= 0xE7;
}
