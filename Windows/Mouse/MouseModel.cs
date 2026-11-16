// SPDX-License-Identifier: MIT
// Generic 3£ Mouse model: device-independent settings, capabilities and the driver interface.
// A device module (Windows/Mouse/Devices/<Name>/) turns a MouseProfile into that mouse's
// reports. The window (MouseWindow.cs) only shows what MouseCapabilities says the device has.
// No Windows dependency here (tested by Windows/MouseTests). Mac twin: TouchBar/threee/Mouse.
using System;
using System.Collections.Generic;
using System.Linq;

namespace ThreeE.Mouse;

public enum ActionKind { Mouse, DoubleClick, TripleClick, Key, Fire, Media, DpiUp, DpiDown, DpiLoop, DpiLock, SwitchPollingRate, SwitchLighting, Disabled, Macro, Raw }

public enum MediaKey { Next, Previous, Stop, PlayPause, Mute, VolumeUp, VolumeDown, MediaPlayer, MyComputer, Mail, Calculator, WebSearch, WebHome, WebBack, WebForward, WebStop, WebRefresh, WebFavorites }

public enum MacroRepeat { Count = 1, WhileHeld = 2, UntilKeyPress = 4 }

/// What one button does, independent of any device's encoding.
public sealed record ButtonAction {
    public ActionKind Kind { get; init; }
    /// Mouse: 0 left, 1 right, 2 middle, 3 back, 4 forward. Key/Fire: HID usage. Macro: macro number (1-based). DpiLock: DPI. Media: MediaKey.
    public int Value { get; init; }
    /// Key: HID modifier bits. Fire: interval ms. Macro: MacroRepeat.
    public int Value2 { get; init; }
    /// Key: second key. Fire: count. Raw: device-specific value.
    public uint Value3 { get; init; }

    public static ButtonAction MouseButton(int b) => new() { Kind = ActionKind.Mouse, Value = b };
    public static ButtonAction KeyPress(byte usage, byte modifiers = 0, byte key2 = 0) => new() { Kind = ActionKind.Key, Value = usage, Value2 = modifiers, Value3 = key2 };
    public static ButtonAction Simple(ActionKind k) => new() { Kind = k };
    public static ButtonAction Macro(int number, MacroRepeat repeat = MacroRepeat.Count) => new() { Kind = ActionKind.Macro, Value = number, Value2 = (int)repeat };
    public static ButtonAction Fire(byte key, byte intervalMs, byte count) => new() { Kind = ActionKind.Fire, Value = key, Value2 = intervalMs, Value3 = count };
    public static ButtonAction Media(MediaKey m) => new() { Kind = ActionKind.Media, Value = (int)m };
    public static ButtonAction DpiLock(int dpi) => new() { Kind = ActionKind.DpiLock, Value = dpi };
    public static ButtonAction Raw(uint value) => new() { Kind = ActionKind.Raw, Value3 = value };

    public static readonly string[] MouseButtonNames = { "Left click", "Right click", "Middle click", "Back (MB4)", "Forward (MB5)" };

    public string Label => Kind switch {
        ActionKind.Mouse => MouseButtonNames[Math.Clamp(Value, 0, MouseButtonNames.Length - 1)],
        ActionKind.Key => "Key: " + HidKeys.ComboName((byte)Value2, (byte)Value, (byte)Value3),
        ActionKind.Fire => $"Fire {HidKeys.Name((byte)Value)} ×{Value3} every {Value2} ms",
        ActionKind.Media => "Media: " + (MediaKey)Value,
        ActionKind.DpiLock => $"DPI lock {Value}",
        ActionKind.Macro => $"Macro {Value} ({(MacroRepeat)Value2})",
        ActionKind.Raw => $"Raw 0x{Value3:X8}",
        _ => Kind.ToString(),
    };
}

public sealed class MacroEvent {
    /// HID usage (0x04…0xE7) or 0xF0…0xF4 = left/right/middle/back/forward mouse button.
    public byte Key { get; set; }
    public bool Press { get; set; }
    /// Delay after this event in ms.
    public int DelayMs { get; set; }
}

public sealed class Macro {
    public string Name { get; set; } = "Macro";
    public List<MacroEvent> Events { get; set; } = new();
    /// Used when a button runs the macro with MacroRepeat.Count.
    public ushort RepeatCount { get; set; } = 1;

    public static IEnumerable<MacroEvent> Tap(byte key, int holdMs = 20, int gapMs = 20) => new[] {
        new MacroEvent { Key = key, Press = true, DelayMs = holdMs }, new MacroEvent { Key = key, Press = false, DelayMs = gapMs } };
}

public sealed class DpiStage {
    public bool Enabled { get; set; } = true;
    public int X { get; set; } = 1200;
    public int Y { get; set; } = 1200;
    /// Index into MouseCapabilities.DpiColorNames.
    public int Color { get; set; } = 1;
}

/// Everything 3£ can configure on a mouse. Saved per device as %LOCALAPPDATA%\3EWindows\Mouse\<device id>.json.
public sealed class MouseProfile {
    /// [mode][slot]
    public List<List<ButtonAction>> Buttons { get; set; } = new();
    public List<Macro> Macros { get; set; } = new();
    public List<DpiStage> Stages { get; set; } = new();
    public int CurrentStage { get; set; }
    public bool XyIndependent { get; set; }
    /// Index into MouseCapabilities.LightingEffects.
    public int Effect { get; set; }
    public int Level { get; set; } = 4;
    public bool LightingRandom { get; set; }
    public int LightingColorCount { get; set; }
    /// 0xRRGGBB
    public int[] Colors { get; set; } = Array.Empty<int>();
    public int ActiveMode { get; set; }
    /// Polling rate per mode (one entry when the device has no modes).
    public int[] RatesHz { get; set; } = Array.Empty<int>();

    public MouseProfile Clone() => System.Text.Json.JsonSerializer.Deserialize<MouseProfile>(System.Text.Json.JsonSerializer.Serialize(this));

    /// Pads a profile from an older/partial file to the shape the device needs.
    public MouseProfile Normalized(MouseCapabilities caps, MouseProfile defaults) {
        int modes = Math.Max(1, caps.Modes);
        Buttons ??= new(); Macros ??= new(); Stages ??= new();
        while (Buttons.Count < modes) Buttons.Add(new List<ButtonAction>(defaults.Buttons.ElementAtOrDefault(Buttons.Count) ?? defaults.Buttons.FirstOrDefault() ?? new()));
        foreach (var row in Buttons) while (row.Count < caps.Slots) row.Add(ButtonAction.Simple(ActionKind.Disabled));
        while (Macros.Count < caps.MacroCount) Macros.Add(new Macro { Name = "Macro " + (Macros.Count + 1) });
        while (Stages.Count < caps.DpiStages) Stages.Add(defaults.Stages.ElementAtOrDefault(Stages.Count) ?? new DpiStage());
        if (Colors == null || Colors.Length < caps.LightingColors) Colors = defaults.Colors;
        if (RatesHz == null || RatesHz.Length < modes) RatesHz = defaults.RatesHz;
        return this;
    }
}

/// What a device supports. The window builds its pages from this, so a new mouse needs no UI changes.
public sealed class MouseCapabilities {
    public int Slots { get; init; }
    public string[] SlotNames { get; init; } = Array.Empty<string>();
    /// Hardware key modes (button layers). 0 or 1 = no mode switching.
    public int Modes { get; init; } = 1;
    public ActionKind[] Actions { get; init; } = Array.Empty<ActionKind>();
    public MediaKey[] MediaKeys { get; init; } = Array.Empty<MediaKey>();
    /// Mouse buttons usable as an action (indices into ButtonAction.MouseButtonNames).
    public int MouseButtons { get; init; } = 5;
    /// Slot of the extra side button (1-based), offered "→ F13 / Pause" in one click. 0 = none.
    public int ExtraSideSlot { get; init; }
    /// Slots that "Identify buttons" may temporarily remap to F13… (1-based).
    public int[] IdentifySlots { get; init; } = Array.Empty<int>();

    public int DpiStages { get; init; }
    public int[] DpiValues { get; init; } = Array.Empty<int>();
    public bool DpiXy { get; init; }
    public string[] DpiColorNames { get; init; } = Array.Empty<string>();

    public string[] LightingEffects { get; init; } = Array.Empty<string>();
    /// Effects the vendor UI hides (still selectable, marked in the list).
    public int[] LightingEffectsHidden { get; init; } = Array.Empty<int>();
    public int LightingColors { get; init; }
    public int LightingLevelMax { get; init; }
    public bool LightingRandom { get; init; }

    public int[] PollingRatesHz { get; init; } = Array.Empty<int>();

    public int MacroCount { get; init; }
    public int MacroMaxDelayMs { get; init; }
    public int MacroBytes { get; init; }

    public bool HasButtons => Slots > 0;
    public bool HasDpi => DpiStages > 0;
    public bool HasLighting => LightingEffects.Length > 0;
    public bool HasPolling => PollingRatesHz.Length > 0;
    public bool HasMacros => MacroCount > 0 && Actions.Contains(ActionKind.Macro);
}

[Flags] public enum MouseParts { Dpi = 1, Lighting = 2, Polling = 4, Buttons = 8, All = 15 }

/// One supported mouse model. Implementations live in Windows/Mouse/Devices/<Name>/.
public interface IMouseDriver {
    string Id { get; }
    string DisplayName { get; }
    MouseCapabilities Capabilities { get; }
    MouseProfile DefaultProfile();
    Action<string> Log { get; set; }
    bool Ready { get; }
    /// Finds the device's configuration interface(s).
    bool Connect();
    /// Loads whatever the device can report into the profile; returns a one-line status.
    string Read(MouseProfile profile);
    void Apply(MouseProfile profile, MouseParts parts);
    /// Lines for the Device page (interfaces, raw reports).
    IEnumerable<string> Diagnostics();
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
}
