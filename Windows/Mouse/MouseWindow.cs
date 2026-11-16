// SPDX-License-Identifier: MIT
// 3£ "Mouse…" window (tray menu). Device-independent: it detects supported mice through
// MouseDevices, talks only to IMouseDriver, and builds every page from MouseCapabilities,
// so a new mouse needs a Devices/<Name>/ module and no changes here. Built in code (no XAML).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace ThreeE.Mouse;

public sealed class MouseWindow : Window {
    static MouseWindow open;
    readonly string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "Mouse");
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
    readonly TextBox log = new() { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), Height = 320 };
    readonly TabView tabs = new() { IsAddTabButtonVisible = false, TabWidthMode = TabViewWidthMode.SizeToContent };
    readonly StackPanel header = new() { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(12) };
    List<MouseDeviceEntry> detected = new();
    string selectedId;
    IMouseDriver driver;
    MouseProfile profile;
    int editingMode, selectedMacro;
    bool identifying;

    MouseCapabilities Caps => driver?.Capabilities;
    string ProfilePath => Path.Combine(folder, driver.Id + ".json");

    public static void Show() {
        if (open == null) { open = new MouseWindow(); open.Closed += (_, _) => open = null; }
        open.Activate();
    }

    MouseWindow() {
        Title = "3£ Mouse";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1000, 780));
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(header);
        Grid.SetRow(tabs, 1);
        root.Children.Add(tabs);
        Content = root;
        Closed += (_, _) => { if (identifying) StopIdentify(); };
        Connect();
    }

    void Log(string line) => log.Text += line + "\n";

    // ---------- device & profile ----------

    void Connect() {
        try {
            detected = MouseDevices.Detect();
            var entry = detected.FirstOrDefault(e => e.Id == selectedId) ?? detected.FirstOrDefault();
            if (entry == null) {
                driver = null; profile = null;
                status.Text = "No supported mouse connected. Supported: " + string.Join(", ", MouseDevices.Supported.Select(e => e.Name)) + ".";
            } else {
                selectedId = entry.Id;
                driver = entry.Create();
                driver.Log = Log;
                profile = LoadProfile();
                if (driver.Connect()) { status.Text = driver.DisplayName + " connected"; ReadFromMouse(rebuild: false); }
                else status.Text = driver.DisplayName + " found, but its configuration interface did not answer (see Device tab).";
            }
        } catch (Exception ex) { status.Text = "Connect failed: " + ex.Message; Log(ex.ToString()); }
        Rebuild();
    }

    MouseProfile LoadProfile() {
        var defaults = driver.DefaultProfile();
        try {
            if (File.Exists(ProfilePath)) return (JsonSerializer.Deserialize<MouseProfile>(File.ReadAllText(ProfilePath)) ?? defaults).Normalized(Caps, defaults);
        } catch (Exception ex) { Log("profile load failed: " + ex.Message); }
        return defaults.Normalized(Caps, defaults);
    }

    void Save() {
        if (driver == null) return;
        try { Directory.CreateDirectory(folder); File.WriteAllText(ProfilePath, JsonSerializer.Serialize(profile, new JsonSerializerOptions { WriteIndented = true })); }
        catch (Exception ex) { Log("profile save failed: " + ex.Message); }
    }

    void ReadFromMouse(bool rebuild = true) {
        if (driver?.Ready != true) return;
        try { status.Text = driver.DisplayName + " – " + driver.Read(profile); }
        catch (Exception ex) { status.Text = "Read failed: " + ex.Message; }
        if (rebuild) Rebuild();
    }

    void Apply(MouseParts parts) {
        if (driver == null) return;
        Save();
        if (!driver.Ready) { status.Text = "Saved. The mouse is not connected – press Reconnect."; return; }
        try {
            if (Caps.HasDpi && !profile.Stages.Any(s => s.Enabled)) profile.Stages[0].Enabled = true;
            driver.Apply(profile, parts);
            status.Text = "Applied to " + driver.DisplayName + " at " + DateTime.Now.ToLongTimeString();
        } catch (Exception ex) { status.Text = "Apply failed: " + ex.Message; }
    }

    void SetSideKey(byte usage) {
        for (int m = 0; m < profile.Buttons.Count; m++) profile.Buttons[m][Caps.ExtraSideSlot - 1] = ButtonAction.KeyPress(usage);
        Apply(MouseParts.Buttons);
        Rebuild();
    }

    // ---------- layout ----------

    void Rebuild() {
        header.Children.Clear();
        if (detected.Count > 1)
            header.Children.Add(Combo(detected.Select(e => e.Name), detected.FindIndex(e => e.Id == selectedId), i => { selectedId = detected[i].Id; Connect(); }, 200));
        header.Children.Add(status);
        if (Caps?.ExtraSideSlot > 0 && Caps.Actions.Contains(ActionKind.Key)) {
            var menu = new MenuFlyout();
            menu.Items.Add(Item("F13 (3£ Kalista kite)", () => SetSideKey(HidKeys.F13)));
            menu.Items.Add(Item("Pause", () => SetSideKey(HidKeys.Pause)));
            header.Children.Add(new DropDownButton { Content = "Side button", Flyout = menu });
        }
        header.Children.Add(ButtonOf("Reconnect", Connect));
        if (driver != null) {
            header.Children.Add(ButtonOf("Read from mouse", () => ReadFromMouse()));
            var apply = new Button { Content = "Apply", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
            apply.Click += (_, _) => Apply(MouseParts.All);
            header.Children.Add(apply);
        }

        int selected = Math.Max(0, tabs.SelectedIndex);
        tabs.TabItems.Clear();
        if (driver != null) {
            if (Caps.HasButtons) tabs.TabItems.Add(Tab("Buttons", ButtonsPage()));
            if (Caps.HasDpi) tabs.TabItems.Add(Tab("DPI", DpiPage()));
            if (Caps.HasLighting) tabs.TabItems.Add(Tab("Lighting", LightingPage()));
            if (Caps.HasPolling) tabs.TabItems.Add(Tab(Caps.Modes > 1 ? "Polling / Modes" : "Polling rate", PollingPage()));
            if (Caps.HasMacros) tabs.TabItems.Add(Tab("Macros", MacrosPage()));
        }
        tabs.TabItems.Add(Tab("Device", DevicePage()));
        tabs.SelectedIndex = Math.Min(selected, tabs.TabItems.Count - 1);
    }

    // ---------- pages ----------

    UIElement ButtonsPage() {
        var page = Page();
        var top = Row(8);
        if (Caps.Modes > 1) {
            top.Children.Add(Label("Key mode"));
            top.Children.Add(Combo(Enumerable.Range(1, Caps.Modes).Select(i => "Mode " + i), editingMode, i => { editingMode = i; Rebuild(); }));
            top.Children.Add(ButtonOf("Copy this mode to all modes", () => { for (int m = 0; m < profile.Buttons.Count; m++) if (m != editingMode) profile.Buttons[m] = profile.Buttons[editingMode].ToList(); }));
        }
        top.Children.Add(ButtonOf("Defaults", () => { profile.Buttons = driver.DefaultProfile().Buttons; Rebuild(); }));
        page.Children.Add(top);
        if (Caps.ExtraSideSlot > 0)
            page.Children.Add(Note($"Every slot takes any function, including the extra side button ({Caps.SlotNames[Caps.ExtraSideSlot - 1]}) that the vendor app limits to macros. For 3£ LoL kiting set it to Key → F13 (or Pause). Not sure which slot a button is? Use Identify buttons below."));
        int mode = Math.Min(editingMode, profile.Buttons.Count - 1);
        for (int s = 0; s < Caps.Slots; s++) {
            int slot = s;
            var editor = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            BuildActionEditor(editor, () => profile.Buttons[mode][slot], a => profile.Buttons[mode][slot] = a);
            page.Children.Add(Row(8, new TextBlock { Text = Caps.SlotNames.ElementAtOrDefault(s) ?? "Slot " + (s + 1), Width = 200, VerticalAlignment = VerticalAlignment.Center }, editor));
        }
        var actions = Row(8);
        if (Caps.IdentifySlots.Length > 0 && Caps.Actions.Contains(ActionKind.Key)) {
            var input = new TextBox { PlaceholderText = "Click here, then press a mouse button", Width = 300, Visibility = identifying ? Visibility.Visible : Visibility.Collapsed };
            var result = new TextBlock { VerticalAlignment = VerticalAlignment.Center };
            input.KeyDown += (_, e) => {
                int index = (int)e.Key - (int)VirtualKey.F13;
                if (index >= 0 && index < Caps.IdentifySlots.Length) {
                    int slot = Caps.IdentifySlots[index];
                    result.Text = $"That button is {Caps.SlotNames.ElementAtOrDefault(slot - 1) ?? "slot " + slot}.";
                    e.Handled = true;
                }
            };
            actions.Children.Add(ButtonOf(identifying ? "Stop identifying & restore" : "Identify buttons…", () => { if (identifying) StopIdentify(); else StartIdentify(); Rebuild(); }));
            actions.Children.Add(input);
            actions.Children.Add(result);
        }
        actions.Children.Add(ButtonOf("Apply buttons" + (Caps.HasMacros ? " & macros" : ""), () => Apply(MouseParts.Buttons)));
        page.Children.Add(actions);
        return Scroll(page);
    }

    void StartIdentify() {
        if (driver?.Ready != true) { status.Text = "Connect the mouse first."; return; }
        var temp = profile.Clone();
        for (int i = 0; i < Caps.IdentifySlots.Length && i < 12; i++)
            foreach (var row in temp.Buttons) row[Caps.IdentifySlots[i] - 1] = ButtonAction.KeyPress((byte)(HidKeys.F13 + i)); // F13…
        try {
            driver.Apply(temp, MouseParts.Buttons); identifying = true;
            status.Text = $"Identify: {Caps.IdentifySlots.Length} slots temporarily send F13–F{12 + Caps.IdentifySlots.Length}.";
        } catch (Exception ex) { status.Text = "Identify failed: " + ex.Message; }
    }

    void StopIdentify() {
        identifying = false;
        Apply(MouseParts.Buttons);
        status.Text += " Original mapping restored.";
    }

    static readonly Dictionary<ActionKind, string> KindNames = new() {
        [ActionKind.Mouse] = "Mouse button", [ActionKind.DoubleClick] = "Double click", [ActionKind.TripleClick] = "Triple click",
        [ActionKind.Key] = "Key / combo", [ActionKind.Fire] = "Fire key (auto-repeat)", [ActionKind.Media] = "Multimedia",
        [ActionKind.DpiUp] = "DPI +", [ActionKind.DpiDown] = "DPI −", [ActionKind.DpiLoop] = "DPI loop", [ActionKind.DpiLock] = "DPI lock",
        [ActionKind.SwitchPollingRate] = "Switch polling rate", [ActionKind.SwitchLighting] = "Switch lighting effect",
        [ActionKind.Disabled] = "Disabled", [ActionKind.Macro] = "Macro", [ActionKind.Raw] = "Raw value",
    };

    ButtonAction DefaultFor(ActionKind k) => k switch {
        ActionKind.Mouse => ButtonAction.MouseButton(0),
        ActionKind.Key => ButtonAction.KeyPress(HidKeys.F13),
        ActionKind.Fire => ButtonAction.Fire(0xF0, 50, 3),
        ActionKind.Media => ButtonAction.Media(Caps.MediaKeys.FirstOrDefault()),
        ActionKind.DpiLock => ButtonAction.DpiLock(Caps.DpiValues.FirstOrDefault()),
        ActionKind.Macro => ButtonAction.Macro(1),
        ActionKind.Raw => ButtonAction.Raw(0),
        _ => ButtonAction.Simple(k),
    };

    void BuildActionEditor(StackPanel panel, Func<ButtonAction> get, Action<ButtonAction> set) {
        panel.Children.Clear();
        var a = get();
        var kinds = Caps.Actions.ToList();
        if (!kinds.Contains(a.Kind)) kinds.Add(a.Kind);
        panel.Children.Add(Combo(kinds.Select(k => KindNames[k]), kinds.IndexOf(a.Kind), i => { set(DefaultFor(kinds[i])); BuildActionEditor(panel, get, set); }, 200));
        switch (a.Kind) {
            case ActionKind.Mouse:
                panel.Children.Add(Combo(ButtonAction.MouseButtonNames.Take(Caps.MouseButtons), a.Value, i => set(get() with { Value = i }), 150));
                break;
            case ActionKind.Key:
                foreach (var (name, bit) in new[] { ("Ctrl", 0x01), ("Shift", 0x02), ("Alt", 0x04), ("Win", 0x08) }) {
                    var box = new CheckBox { Content = name, IsChecked = (a.Value2 & bit) != 0, MinWidth = 60 };
                    box.Click += (_, _) => set(get() with { Value2 = box.IsChecked == true ? get().Value2 | bit : get().Value2 & ~bit });
                    panel.Children.Add(box);
                }
                panel.Children.Add(KeyCombo((byte)a.Value, true, u => set(get() with { Value = u })));
                panel.Children.Add(new TextBlock { Text = "+", VerticalAlignment = VerticalAlignment.Center });
                panel.Children.Add(KeyCombo((byte)a.Value3, true, u => set(get() with { Value3 = u })));
                break;
            case ActionKind.Fire:
                panel.Children.Add(KeyCombo((byte)a.Value, false, u => set(get() with { Value = u })));
                panel.Children.Add(Number("Times", a.Value3, 1, 255, v => set(get() with { Value3 = (uint)v })));
                panel.Children.Add(Number("Interval ms", a.Value2, 5, 255, v => set(get() with { Value2 = v })));
                break;
            case ActionKind.Media:
                panel.Children.Add(Combo(Caps.MediaKeys.Select(m => m.ToString()), Array.IndexOf(Caps.MediaKeys, (MediaKey)a.Value), i => set(ButtonAction.Media(Caps.MediaKeys[i])), 170));
                break;
            case ActionKind.DpiLock:
                panel.Children.Add(Combo(Caps.DpiValues.Select(d => d + " DPI"), Array.IndexOf(Caps.DpiValues, a.Value), i => set(ButtonAction.DpiLock(Caps.DpiValues[i])), 130));
                break;
            case ActionKind.Macro:
                panel.Children.Add(Combo(Enumerable.Range(1, Caps.MacroCount).Select(i => i + ": " + profile.Macros[i - 1].Name), a.Value - 1, i => set(get() with { Value = i + 1 }), 170));
                var repeats = Enum.GetValues<MacroRepeat>();
                panel.Children.Add(Combo(new[] { "Repeat N times", "Loop while held", "Loop until any key" }, Array.IndexOf(repeats, (MacroRepeat)a.Value2), i => set(get() with { Value2 = (int)repeats[i] }), 170));
                break;
            case ActionKind.Raw:
                var hex = new TextBox { Text = a.Value3.ToString("X8"), Width = 110, FontFamily = new FontFamily("Consolas") };
                hex.TextChanged += (_, _) => { if (uint.TryParse(hex.Text, System.Globalization.NumberStyles.HexNumber, null, out var v)) set(get() with { Value3 = v }); };
                panel.Children.Add(hex);
                break;
        }
    }

    UIElement DpiPage() {
        var page = Page();
        if (Caps.DpiXy) page.Children.Add(Toggle("Independent X / Y DPI", profile.XyIndependent, v => { profile.XyIndependent = v; Rebuild(); }));
        page.Children.Add(Row(8, Label("Current stage"), Combo(Enumerable.Range(1, Caps.DpiStages).Select(i => "Stage " + i), profile.CurrentStage, i => profile.CurrentStage = i)));
        var values = Caps.DpiValues.Select(d => d.ToString()).ToArray();
        for (int i = 0; i < Caps.DpiStages; i++) {
            var s = profile.Stages[i];
            var enabled = new CheckBox { Content = "Stage " + (i + 1), IsChecked = s.Enabled, Width = 110 };
            enabled.Click += (_, _) => s.Enabled = enabled.IsChecked == true;
            bool xy = Caps.DpiXy && profile.XyIndependent;
            var row = Row(8, enabled, Label(xy ? "X" : "DPI"), Combo(values, Array.IndexOf(Caps.DpiValues, s.X), k => { s.X = Caps.DpiValues[k]; if (!xy) s.Y = s.X; }, 110));
            if (xy) { row.Children.Add(Label("Y")); row.Children.Add(Combo(values, Array.IndexOf(Caps.DpiValues, s.Y), k => s.Y = Caps.DpiValues[k], 110)); }
            if (Caps.DpiColorNames.Length > 0) { row.Children.Add(Label("Colour")); row.Children.Add(Combo(Caps.DpiColorNames, s.Color, k => s.Color = k, 120)); }
            page.Children.Add(row);
        }
        page.Children.Add(ButtonOf("Apply DPI", () => Apply(MouseParts.Dpi)));
        return Scroll(page);
    }

    UIElement LightingPage() {
        var page = Page();
        page.Children.Add(Row(8, Label("Effect"), Combo(Caps.LightingEffects.Select((n, i) => Caps.LightingEffectsHidden.Contains(i) ? n + " (hidden in vendor app)" : n), profile.Effect, i => profile.Effect = i, 280)));
        if (Caps.LightingLevelMax > 0) page.Children.Add(Number("Speed / brightness level", profile.Level, 1, Caps.LightingLevelMax, v => profile.Level = v));
        if (Caps.LightingRandom) page.Children.Add(Toggle("Random / colourful variant", profile.LightingRandom, v => profile.LightingRandom = v));
        if (Caps.LightingColors > 0) page.Children.Add(Number("Colours used", profile.LightingColorCount, 0, Caps.LightingColors, v => profile.LightingColorCount = v));
        for (int i = 0; i < Caps.LightingColors; i++) {
            int index = i;
            var swatch = new Border { Width = 40, Height = 20, CornerRadius = new CornerRadius(3), Background = Brush(profile.Colors[i]) };
            var picker = new ColorPicker { Color = ColorOf(profile.Colors[i]), IsAlphaEnabled = false };
            picker.ColorChanged += (_, e) => { profile.Colors[index] = e.NewColor.R << 16 | e.NewColor.G << 8 | e.NewColor.B; swatch.Background = Brush(profile.Colors[index]); };
            page.Children.Add(Row(8, new TextBlock { Text = "Colour " + (i + 1), Width = 80, VerticalAlignment = VerticalAlignment.Center },
                new Button { Content = swatch, Flyout = new Flyout { Content = picker } }));
        }
        page.Children.Add(ButtonOf("Apply lighting", () => Apply(MouseParts.Lighting)));
        return Scroll(page);
    }

    UIElement PollingPage() {
        var page = Page();
        if (Caps.Modes > 1) page.Children.Add(Row(8, Label("Active key mode"), Combo(Enumerable.Range(1, Caps.Modes).Select(i => "Mode " + i), profile.ActiveMode, i => profile.ActiveMode = i)));
        for (int m = 0; m < Math.Max(1, Caps.Modes); m++) {
            int mode = m;
            page.Children.Add(Row(8, Label(Caps.Modes > 1 ? "Polling rate – mode " + (m + 1) : "Polling rate"),
                Combo(Caps.PollingRatesHz.Select(h => h + " Hz"), Array.IndexOf(Caps.PollingRatesHz, profile.RatesHz[m]), i => profile.RatesHz[mode] = Caps.PollingRatesHz[i])));
        }
        page.Children.Add(ButtonOf("Apply polling rate", () => Apply(MouseParts.Polling)));
        return Scroll(page);
    }

    UIElement MacrosPage() {
        var page = Page();
        selectedMacro = Math.Clamp(selectedMacro, 0, Caps.MacroCount - 1);
        page.Children.Add(Row(8, Label("Macro"), Combo(profile.Macros.Take(Caps.MacroCount).Select((m, i) => (i + 1) + ". " + m.Name), selectedMacro, i => { selectedMacro = i; Rebuild(); }, 220)));
        var macro = profile.Macros[selectedMacro];
        var name = new TextBox { Text = macro.Name, Width = 220 };
        name.TextChanged += (_, _) => macro.Name = name.Text;
        page.Children.Add(Row(8, Label("Name"), name));
        page.Children.Add(Number("Repeat count (for “Repeat N times”)", macro.RepeatCount, 1, 65535, v => macro.RepeatCount = (ushort)v));
        var list = new ListView { Height = 260, SelectionMode = ListViewSelectionMode.None };
        foreach (var e in macro.Events) list.Items.Add($"{HidKeys.Name(e.Key),-14} {(e.Press ? "press ↓" : "release ↑"),-10} then {e.DelayMs} ms");
        page.Children.Add(list);
        byte key = 0x04; int delay = 20;
        page.Children.Add(Row(6, KeyCombo(key, false, u => key = u), Number("Delay ms", delay, 0, Caps.MacroMaxDelayMs, v => delay = v),
            ButtonOf("+ Tap", () => { macro.Events.AddRange(Macro.Tap(key, delay, delay)); Rebuild(); }),
            ButtonOf("+ Press", () => { macro.Events.Add(new MacroEvent { Key = key, Press = true, DelayMs = delay }); Rebuild(); }),
            ButtonOf("+ Release", () => { macro.Events.Add(new MacroEvent { Key = key, Press = false, DelayMs = delay }); Rebuild(); }),
            ButtonOf("Remove last", () => { if (macro.Events.Count > 0) macro.Events.RemoveAt(macro.Events.Count - 1); Rebuild(); }),
            ButtonOf("Clear", () => { macro.Events.Clear(); Rebuild(); })));
        page.Children.Add(Note($"Up to {Caps.MacroCount} macros of {Caps.MacroBytes} bytes. Assign a macro to a button in the Buttons tab, then Apply."));
        return Scroll(page);
    }

    UIElement DevicePage() {
        var page = Page();
        page.Children.Add(Note("Supported mice: " + string.Join(", ", MouseDevices.Supported.Select(e => $"{e.Name} ({e.VendorId:X4}:{e.ProductId:X4})"))));
        if (driver != null) {
            page.Children.Add(Row(8,
                ButtonOf("Reset to defaults", () => { profile = driver.DefaultProfile().Normalized(Caps, driver.DefaultProfile()); Rebuild(); }),
                ButtonOf("Show profile file", () => { Save(); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", "/select,\"" + ProfilePath + "\"") { UseShellExecute = true })?.Dispose(); })));
            foreach (var line in driver.Diagnostics())
                page.Children.Add(new TextBlock { Text = line, TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), IsTextSelectionEnabled = true });
        }
        page.Children.Add(new TextBlock { Text = "Log", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        if (log.Parent is Panel old) old.Children.Remove(log);
        page.Children.Add(log);
        return Scroll(page);
    }

    // ---------- helpers ----------

    static TabViewItem Tab(string header, UIElement content) => new() { Header = header, Content = content, IsClosable = false };
    static StackPanel Page() => new() { Spacing = 8, Padding = new Thickness(16) };
    static ScrollViewer Scroll(UIElement e) => new() { Content = e, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    static TextBlock Label(string t) => new() { Text = t, VerticalAlignment = VerticalAlignment.Center };
    static TextBlock Note(string t) => new() { Text = t, TextWrapping = TextWrapping.Wrap, Opacity = 0.7 };
    static SolidColorBrush Brush(int rgb) => new(ColorOf(rgb));
    static Windows.UI.Color ColorOf(int rgb) => Windows.UI.Color.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
    static MenuFlyoutItem Item(string text, Action click) { var i = new MenuFlyoutItem { Text = text }; i.Click += (_, _) => click(); return i; }

    static StackPanel Row(double spacing, params UIElement[] children) {
        var p = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var c in children) p.Children.Add(c);
        return p;
    }

    static Button ButtonOf(string text, Action click) { var b = new Button { Content = text }; b.Click += (_, _) => click(); return b; }

    static ComboBox Combo(IEnumerable<string> items, int selected, Action<int> changed, double width = 160) {
        var c = new ComboBox { Width = width };
        foreach (var i in items) c.Items.Add(i);
        c.SelectedIndex = c.Items.Count == 0 ? -1 : Math.Clamp(selected, 0, c.Items.Count - 1);
        c.SelectionChanged += (_, _) => { if (c.SelectedIndex >= 0) changed(c.SelectedIndex); };
        return c;
    }

    static ComboBox KeyCombo(byte usage, bool allowNone, Action<byte> changed) {
        var keys = (allowNone ? new[] { ((byte)0, "—") } : Array.Empty<(byte, string)>()).Concat(HidKeys.All).ToList();
        return Combo(keys.Select(k => k.Item2), Math.Max(0, keys.FindIndex(k => k.Item1 == usage)), i => changed(keys[i].Item1), 150);
    }

    static NumberBox Number(string header, double value, double min, double max, Action<int> changed) {
        var n = new NumberBox { Header = header, Value = value, Minimum = min, Maximum = max, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, Width = 170 };
        n.ValueChanged += (_, e) => { if (!double.IsNaN(e.NewValue)) changed((int)Math.Clamp(e.NewValue, min, max)); };
        return n;
    }

    static ToggleSwitch Toggle(string header, bool value, Action<bool> changed) {
        var t = new ToggleSwitch { Header = header, IsOn = value };
        t.Toggled += (_, _) => changed(t.IsOn);
        return t;
    }
}
