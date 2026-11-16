using System.Text.Json;
using ThreeE.Mouse;
using ThreeE.Mouse.Devices.PC205;

// 3£ Mouse checks: generic model + PC205 protocol (Shared/PC205/PROTOCOL.md). No device access.
int failures = 0;
void Check(bool ok, string what) { if (!ok) { failures++; Console.Error.WriteLine("FAIL: " + what); } }
string Hex(IEnumerable<byte> b) => string.Join(" ", b.Select(x => x.ToString("X2")));

// Vendor Cfg.ini defaults with KeyCodeHasIndex=1.
var row = PC205.DefaultProfile(lolSideKey: false).Buttons[0];
var entries = row.Select((a, i) => PC205Codec.Entry(a, i + 1)).ToArray();
Check(entries.SequenceEqual(new uint[] { 0xF011, 0xF112, 0xF213, 0xF314, 0xF415, 0x2046, 0x4047, 0x0138, 0x0759, 0x075A }), "vendor default entries " + string.Join(",", entries.Select(e => e.ToString("X"))));

// Extra side button → F13 / Pause, combos.
Check(PC205Codec.Entry(ButtonAction.KeyPress(HidKeys.F13), 8) == 0x00680068, "F13 entry");
Check(PC205Codec.Entry(ButtonAction.KeyPress(HidKeys.Pause), 8) == 0x00480068, "Pause entry");
Check(PC205Codec.Encode(ButtonAction.KeyPress(0x04, 0x03)) == 0x00040360, "Ctrl+Shift+A");

// Round trips.
var actions = new[] {
    ButtonAction.MouseButton(0), ButtonAction.MouseButton(4), ButtonAction.Simple(ActionKind.DoubleClick), ButtonAction.Simple(ActionKind.TripleClick),
    ButtonAction.KeyPress(0x68), ButtonAction.Fire(0xF0, 40, 3), ButtonAction.Media(MediaKey.VolumeUp), ButtonAction.Media(MediaKey.WebSearch),
    ButtonAction.Simple(ActionKind.DpiUp), ButtonAction.Simple(ActionKind.DpiDown), ButtonAction.Simple(ActionKind.DpiLoop), ButtonAction.DpiLock(800),
    ButtonAction.Simple(ActionKind.Disabled), ButtonAction.Simple(ActionKind.SwitchPollingRate), ButtonAction.Simple(ActionKind.SwitchLighting),
    ButtonAction.Macro(3, MacroRepeat.WhileHeld),
};
foreach (var a in actions) Check(PC205Codec.Decode(PC205Codec.Entry(a, 5)) == a, "round trip " + a.Label);

// Media bitmaps.
Check(PC205Codec.Encode(ButtonAction.Media(MediaKey.PlayPause)) == 0x0870, "play/pause");
Check(PC205Codec.Encode(ButtonAction.Media(MediaKey.Calculator)) == 0x200070, "calculator");
Check(PC205Codec.Encode(ButtonAction.Media(MediaKey.WebRefresh)) == 0x20000070, "web refresh");

// Macro buffer.
var macro = new Macro { RepeatCount = 0x0102, Events = {
    new MacroEvent { Key = 0x04, Press = true, DelayMs = 0 }, new MacroEvent { Key = 0x04, Press = false, DelayMs = 50 },
    new MacroEvent { Key = 0x05, Press = true, DelayMs = 350 } } };
var mb = PC205Codec.EncodeMacro(macro);
Check(mb.Length == 128, "macro size");
Check(mb.Take(12).SequenceEqual(new byte[] { 0x01, 0x02, 0x81, 0x04, 0x32, 0x04, 0x80 | 50, 0x05, 3, 0x03, 0, 0 }), "macro bytes " + Hex(mb.Take(12)));
var decoded = PC205Codec.DecodeMacro(mb, "t");
Check(decoded.Events.Select(e => e.DelayMs).SequenceEqual(new[] { 1, 50, 350 }) && decoded.Events.Select(e => e.Press).SequenceEqual(new[] { true, false, true }), "macro decode");

// Matrix layout.
var p = PC205.DefaultProfile();
p.Macros[0].Events.AddRange(Macro.Tap(0x04));
p.Buttons[1][9] = ButtonAction.Macro(1);
var x = PC205Codec.MatrixPayload(p);
Check(x.Length == 0x478 && PC205.MatrixPayload + 1 == 1145, "matrix size");
Check(x.Take(4).SequenceEqual(new byte[] { 0x00, 0x01, 0x80 | 20, 0x04 }), "macro area " + Hex(x.Take(4)));
Check(x.Skip(0x400 + 7 * 4).Take(4).SequenceEqual(new byte[] { 0x68, 0x00, 0x68, 0x00 }), "mode1 slot8 F13");
Check(x.Skip(0x400 + 19 * 4).Take(4).SequenceEqual(new byte[] { 0x9A, 0x11, 0x00, 0x00 }), "mode2 slot10 macro1");

// General report.
var payload = new byte[58]; payload[0] = 8; PC205.Signature.CopyTo(payload, 52);
var g = new GeneralReport(payload);
Check(g.SignatureOk, "signature");
PC205Codec.ApplyTo(PC205.DefaultProfile(), g, MouseParts.All);
Check((g.Bytes[1] & 0x0F) == 5 && g.Bytes[1] >> 4 == 1, "stage count/current");
Check(g.Bytes.Skip(4).Take(8).SequenceEqual(new byte[] { 4, 7, 10, 14, 16, 0x90, 0x90, 0x90 }), "dpi codes " + Hex(g.Bytes.Skip(4).Take(8)));
Check(g.Bytes.Skip(43).Take(5).SequenceEqual(new byte[] { 1, 3, 2, 6, 5 }), "dpi colours");
Check(g.Bytes[20] >> 4 == 3 && g.SignatureOk && g.Stages[0].X == 1200 && g.Feature.Length == 59, "lighting/signature/feature");

// Mode report.
var mode = new ModeReport(new byte[] { 1, 3, 3, 3, 2, 3, 1, 0 });
PC205Codec.ApplyTo(PC205.DefaultProfile(), mode);
mode.SetRateHz(2, 1000);
Check(mode.Feature.SequenceEqual(new byte[] { 8, 1, 3, 3, 4, 2, 3, 1, 0 }), "mode report " + Hex(mode.Feature));

// Profile JSON survives a save/load (stored in %LOCALAPPDATA%\3EWindows\Mouse).
var json = JsonSerializer.Serialize(p);
var back = JsonSerializer.Deserialize<MouseProfile>(json).Normalized(PC205.Capabilities, PC205.DefaultProfile());
Check(PC205Codec.MatrixPayload(back).SequenceEqual(x), "profile JSON round trip");

// Generic layer: a partial profile is padded to what the device supports; the PC205 is registered by VID/PID.
var partial = new MouseProfile().Normalized(PC205.Capabilities, PC205.DefaultProfile());
Check(partial.Buttons.Count == PC205.Capabilities.Modes && partial.Buttons.All(r => r.Count == PC205.Capabilities.Slots) && partial.Macros.Count == 8 && partial.Stages.Count == 8, "profile normalization");
Check(PC205.Capabilities.ExtraSideSlot == 8 && PC205.DefaultProfile().Buttons.All(r => r[7] == ButtonAction.KeyPress(HidKeys.F13)), "default side button = F13");
Check(PC205.Capabilities.HasButtons && PC205.Capabilities.HasDpi && PC205.Capabilities.HasLighting && PC205.Capabilities.HasPolling && PC205.Capabilities.HasMacros, "PC205 capabilities");

if (failures > 0) { Console.Error.WriteLine($"{failures} PC205 check(s) failed."); return 1; }
Console.WriteLine("3£ Mouse model and PC205 protocol checks passed.");
return 0;
