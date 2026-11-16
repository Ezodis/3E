// SPDX-License-Identifier: MIT
// "Mouse (PC205)" window opened from the 3£ tray menu: DPI, polling rate, lighting,
// button mapping (every slot, including the extra side button) and macros.
// Built in code so it needs no XAML compilation; protocol in Shared/PC205/PROTOCOL.md.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace ThreeE.Mouse;

public sealed class MouseWindow : Window {
    static MouseWindow open;
    readonly PC205Device device = new();
    readonly string store = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "Mouse", "profile.json");
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 460 };
    readonly TextBox log = new() { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), Height = 360 };
    readonly TabView tabs = new() { IsAddTabButtonVisible = false, TabWidthMode = TabViewWidthMode.SizeToContent };
    MouseProfile profile;
    int editingMode;
    GeneralReport lastGeneral;
    bool identifying;

    public static void Show() {
        if (open == null) { open = new MouseWindow(); open.Closed += (_, _) => open = null; }
        open.Activate();
    }

    MouseWindow() {
        Title = "3£ Mouse – PC205";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(980, 780));
        profile = LoadProfile();
        device.Log = line => log.Text += line + "\n";
        var apply = new Button { Content = "Apply", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        apply.Click += (_, _) => Apply(PC205Device.Parts.All);
        var side = new DropDownButton { Content = "Side button" };
        var sideMenu = new MenuFlyout();
        sideMenu.Items.Add(Item("F13 (3£ Kalista kite)", () => SetSideKey(HidKeys.F13)));
        sideMenu.Items.Add(Item("Pause", () => SetSideKey(HidKeys.Pause)));
        side.Flyout = sideMenu;
        var header = Row(10, status, new Grid { Width = 8 }, side, ButtonOf("Reconnect", Connect), ButtonOf("Read from mouse", ReadFromMouse), apply);
        header.Margin = new Thickness(12);
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(header);
        Grid.SetRow(tabs, 1);
        root.Children.Add(tabs);
        Content = root;
        Closed += (_, _) => { if (identifying) StopIdentify(); };
        Connect();
        Rebuild();
    }

    // ---------- state ----------

    MouseProfile LoadProfile() {
        try { if (File.Exists(store)) return (JsonSerializer.Deserialize<MouseProfile>(File.ReadAllText(store)) ?? MouseProfile.LolDefault()).Normalized(); }
        catch (Exception ex) { log.Text += "profile load failed: " + ex.Message + "\n"; }
        return MouseProfile.LolDefault();
    }

    void Save() {
        try { Directory.CreateDirectory(Path.GetDirectoryName(store)); File.WriteAllText(store, JsonSerializer.Serialize(profile, new JsonSerializerOptions { WriteIndented = true })); }
        catch (Exception ex) { log.Text += "profile save failed: " + ex.Message + "\n"; }
    }

    void Connect() {
        try {
            if (device.Connect()) { status.Text = "Connected"; ReadFromMouse(); }
            else status.Text = device.Collections.Count > 0 ? "PC205 found, but its configuration interface did not answer (see Device tab)." : "PC205 not found – plug it in and press Reconnect.";
        } catch (Exception ex) { status.Text = "Connect failed: " + ex.Message; }
    }

    void ReadFromMouse() {
        if (!device.Ready) return;
        try {
            lastGeneral = device.ReadGeneral();
            profile.LoadFrom(lastGeneral);
            var m = device.ReadMode();
            if (m != null) profile.LoadFrom(m);
            status.Text = $"Connected – sensor code {lastGeneral.SensorCode}, signature {(lastGeneral.SignatureOk ? "OK" : "unexpected")}. Buttons/macros come from the saved profile (the mouse can't report them).";
            Rebuild();
        } catch (Exception ex) { status.Text = "Read failed: " + ex.Message; }
    }

    void Apply(PC205Device.Parts parts) {
        Save();
        if (!device.Ready) { status.Text = "Saved. PC205 not connected – press Reconnect."; return; }
        try {
            if (!profile.Stages.Any(s => s.Enabled)) profile.Stages[0].Enabled = true;
            device.Apply(profile, parts);
            status.Text = "Applied to mouse at " + DateTime.Now.ToLongTimeString();
        } catch (Exception ex) { status.Text = "Apply failed: " + ex.Message; }
    }

    void SetSideKey(byte usage) {
        for (int m = 0; m < PC205.Modes; m++) profile.Buttons[m][PC205.LikelyExtraSideSlot - 1] = ButtonAction.KeyPress(usage);
        Apply(PC205Device.Parts.Matrix);
        Rebuild();
    }

    void Rebuild() {
        int selected = Math.Max(0, tabs.SelectedIndex);
        tabs.TabItems.Clear();
        tabs.TabItems.Add(Tab("Buttons", ButtonsPage()));
        tabs.TabItems.Add(Tab("DPI", DpiPage()));
        tabs.TabItems.Add(Tab("Lighting", LightingPage()));
        tabs.TabItems.Add(Tab("Polling / Modes", PollingPage()));
        tabs.TabItems.Add(Tab("Macros", MacrosPage()));
        tabs.TabItems.Add(Tab("Device", DevicePage()));
        tabs.SelectedIndex = Math.Min(selected, tabs.TabItems.Count - 1);
    }

    // ---------- pages ----------

    UIElement ButtonsPage() {
        var page = Page();
        var mode = Combo(Enumerable.Range(1, PC205.Modes).Select(i => "Mode " + i), editingMode, i => { editingMode = i; Rebuild(); });
        page.Children.Add(Row(8, Label("Key mode"), mode,
            ButtonOf("Copy this mode to all modes", () => { for (int m = 0; m < PC205.Modes; m++) if (m != editingMode) profile.Buttons[m] = profile.Buttons[editingMode].ToList(); }),
            ButtonOf("Vendor defaults", () => { profile.Buttons = MouseProfile.VendorDefault().Buttons; Rebuild(); })));
        page.Children.Add(Note("Every slot takes any function, including the extra side button the Windows vendor app limits to macros. For 3£ LoL kiting set it to Key → F13 (or Pause). Not sure which slot it is? Use Identify buttons below."));
        for (int s = 0; s < PC205.Slots; s++) {
            int slot = s;
            var editor = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            BuildActionEditor(editor, () => profile.Buttons[editingMode][slot], a => profile.Buttons[editingMode][slot] = a);
            page.Children.Add(Row(8, new TextBlock { Text = PC205.SlotNames[s], Width = 200, VerticalAlignment = VerticalAlignment.Center }, editor));
        }
        var identifyInput = new TextBox { PlaceholderText = "Click here, then press a side/top button", Width = 300, Visibility = identifying ? Visibility.Visible : Visibility.Collapsed };
        var identifyResult = new TextBlock { VerticalAlignment = VerticalAlignment.Center };
        identifyInput.KeyDown += (_, e) => {
            int key = (int)e.Key;
            if (key >= (int)VirtualKey.F13 && key <= (int)VirtualKey.F19) {
                int slot = 4 + key - (int)VirtualKey.F13;
                identifyResult.Text = $"That button is slot {slot} ({PC205.SlotNames[slot - 1]}).";
                e.Handled = true;
            }
        };
        var identify = ButtonOf(identifying ? "Stop identifying & restore" : "Identify buttons…", () => { if (identifying) StopIdentify(); else StartIdentify(); Rebuild(); });
        page.Children.Add(Row(8, identify, identifyInput, identifyResult, ButtonOf("Apply buttons & macros", () => Apply(PC205Device.Parts.Matrix))));
        return Scroll(page);
    }

    void StartIdentify() {
        if (!device.Ready) { status.Text = "Connect the PC205 first."; return; }
        var temp = JsonSerializer.Deserialize<MouseProfile>(JsonSerializer.Serialize(profile)).Normalized();
        for (int slot = 4; slot <= 10; slot++)
            for (int m = 0; m < PC205.Modes; m++) temp.Buttons[m][slot - 1] = ButtonAction.KeyPress((byte)(HidKeys.F13 + slot - 4)); // F13…F19
        try { device.Apply(temp, PC205Device.Parts.Matrix); identifying = true; status.Text = "Identify: slots 4–10 temporarily send F13–F19."; }
        catch (Exception ex) { status.Text = "Identify failed: " + ex.Message; }
    }

    void StopIdentify() {
        identifying = false;
        Apply(PC205Device.Parts.Matrix);
        status.Text += " Original mapping restored.";
    }

    static readonly string[] KindNames = {
        "Mouse button", "Double click", "Triple click", "Key / combo", "Fire key (auto-repeat)", "Multimedia", "DPI +", "DPI −",
        "DPI loop", "DPI lock", "Switch polling rate", "Switch lighting effect", "Disabled", "Macro", "Raw value" };

    static ButtonAction DefaultFor(ActionKind k) => k switch {
        ActionKind.Mouse => ButtonAction.MouseButton(0),
        ActionKind.Key => ButtonAction.KeyPress(HidKeys.F13),
        ActionKind.Fire => ButtonAction.Fire(0xF0, 50, 3),
        ActionKind.Media => ButtonAction.Media(MediaKey.PlayPause),
        ActionKind.DpiLock => ButtonAction.DpiLock(800),
        ActionKind.Macro => ButtonAction.Macro(1, 1),
        ActionKind.Raw => new ButtonAction { Kind = ActionKind.Raw, Value3 = 0x150 },
        _ => ButtonAction.Simple(k),
    };

    void BuildActionEditor(StackPanel panel, Func<ButtonAction> get, Action<ButtonAction> set) {
        panel.Children.Clear();
        var a = get();
        panel.Children.Add(Combo(KindNames, (int)a.Kind, i => { set(DefaultFor((ActionKind)i)); BuildActionEditor(panel, get, set); }, 200));
        switch (a.Kind) {
            case ActionKind.Mouse:
                panel.Children.Add(Combo(new[] { "Left click", "Right click", "Middle click", "Back (MB4)", "Forward (MB5)" }, a.Value, i => set(get() with { Value = i }), 150));
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
                panel.Children.Add(Combo(Enum.GetNames<MediaKey>(), a.Value, i => set(ButtonAction.Media((MediaKey)i)), 170));
                break;
            case ActionKind.DpiLock:
                panel.Children.Add(Combo(PC205.DpiTable.Select(d => d + " DPI"), Math.Max(0, Array.IndexOf(PC205.DpiTable, a.Value)), i => set(ButtonAction.DpiLock(PC205.DpiTable[i])), 130));
                break;
            case ActionKind.Macro:
                panel.Children.Add(Combo(Enumerable.Range(1, PC205.MacroCount).Select(i => i + ": " + profile.Macros[i - 1].Name), Math.Clamp(a.Value - 1, 0, 7), i => set(get() with { Value = i + 1 }), 170));
                int[] modes = { 1, 2, 4 };
                panel.Children.Add(Combo(new[] { "Repeat N times", "Loop while held", "Loop until any key" }, Math.Max(0, Array.IndexOf(modes, a.Value2)), i => set(get() with { Value2 = modes[i] }), 170));
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
        page.Children.Add(Toggle("Independent X / Y DPI", profile.XyIndependent, v => { profile.XyIndependent = v; Rebuild(); }));
        page.Children.Add(Row(8, Label("Current stage"), Combo(Enumerable.Range(1, PC205.DpiStages).Select(i => "Stage " + i), profile.CurrentStage, i => profile.CurrentStage = i)));
        for (int i = 0; i < PC205.DpiStages; i++) {
            var s = profile.Stages[i];
            var enabled = new CheckBox { Content = "Stage " + (i + 1), IsChecked = s.Enabled, Width = 110 };
            enabled.Click += (_, _) => s.Enabled = enabled.IsChecked == true;
            var row = Row(8, enabled, Label(profile.XyIndependent ? "X" : "DPI"),
                Combo(PC205.DpiTable.Select(d => d.ToString()), Math.Max(0, Array.IndexOf(PC205.DpiTable, s.X)), k => { s.X = PC205.DpiTable[k]; if (!profile.XyIndependent) s.Y = s.X; }, 110));
            if (profile.XyIndependent) { row.Children.Add(Label("Y")); row.Children.Add(Combo(PC205.DpiTable.Select(d => d.ToString()), Math.Max(0, Array.IndexOf(PC205.DpiTable, s.Y)), k => s.Y = PC205.DpiTable[k], 110)); }
            row.Children.Add(Label("Colour"));
            row.Children.Add(Combo(PC205.DpiColorNames, s.Color, k => s.Color = k, 120));
            page.Children.Add(row);
        }
        page.Children.Add(ButtonOf("Apply DPI & lighting", () => Apply(PC205Device.Parts.General)));
        return Scroll(page);
    }

    UIElement LightingPage() {
        var page = Page();
        page.Children.Add(Row(8, Label("Effect"), Combo(PC205.EffectNames.Select((n, i) => PC205.EffectsHiddenByVendor.Contains(i) ? n + " (hidden in vendor app)" : n), profile.Effect, i => { profile.Effect = i; Rebuild(); }, 280)));
        page.Children.Add(Number(profile.Effect == 1 ? "Brightness level" : "Speed level", profile.Level, 1, 8, v => profile.Level = v));
        page.Children.Add(Toggle("Random / colourful variant", (profile.LightingFlags & 0x80) != 0, v => profile.LightingFlags = (byte)((v ? 0x80 : 0) | (profile.LightingFlags & 0x7F))));
        page.Children.Add(Number("Colours used", profile.LightingFlags & 0x07, 0, 7, v => profile.LightingFlags = (byte)((profile.LightingFlags & 0xF8) | v)));
        for (int i = 0; i < 7; i++) {
            int index = i;
            var swatch = new Border { Width = 40, Height = 20, CornerRadius = new CornerRadius(3), Background = Brush(profile.Colors[i]) };
            var picker = new ColorPicker { Color = ColorOf(profile.Colors[i]), IsAlphaEnabled = false };
            picker.ColorChanged += (_, e) => { profile.Colors[index] = e.NewColor.R << 16 | e.NewColor.G << 8 | e.NewColor.B; swatch.Background = Brush(profile.Colors[index]); };
            page.Children.Add(Row(8, new TextBlock { Text = "Colour " + (i + 1), Width = 80, VerticalAlignment = VerticalAlignment.Center },
                new Button { Content = swatch, Flyout = new Flyout { Content = picker } }));
        }
        page.Children.Add(ButtonOf("Apply DPI & lighting", () => Apply(PC205Device.Parts.General)));
        return Scroll(page);
    }

    UIElement PollingPage() {
        var page = Page();
        page.Children.Add(Row(8, Label("Active key mode"), Combo(Enumerable.Range(1, PC205.Modes).Select(i => "Mode " + i), profile.ActiveMode, i => profile.ActiveMode = i)));
        for (int m = 0; m < PC205.Modes; m++) {
            int mode = m;
            page.Children.Add(Row(8, Label("Polling rate – mode " + (m + 1)), Combo(PC205.PollingHz.Select(h => h + " Hz"), Math.Max(0, Array.IndexOf(PC205.PollingHz, profile.RatesHz[m])), i => profile.RatesHz[mode] = PC205.PollingHz[i])));
        }
        if (device.Ready && device.Mode == null) page.Children.Add(Note("The mode/polling-rate collection (feature report 8) was not found, so these settings can't be applied."));
        page.Children.Add(ButtonOf("Apply polling rate & mode", () => Apply(PC205Device.Parts.Mode)));
        return Scroll(page);
    }

    int selectedMacro;
    UIElement MacrosPage() {
        var page = Page();
        page.Children.Add(Row(8, Label("Macro"), Combo(profile.Macros.Select((m, i) => (i + 1) + ". " + m.Name), selectedMacro, i => { selectedMacro = i; Rebuild(); }, 220)));
        var macro = profile.Macros[selectedMacro];
        var name = new TextBox { Text = macro.Name, Width = 220 };
        name.TextChanged += (_, _) => macro.Name = name.Text;
        page.Children.Add(Row(8, Label("Name"), name));
        page.Children.Add(Number("Repeat count (for “Repeat N times”)", macro.RepeatCount, 1, 65535, v => macro.RepeatCount = (ushort)v));
        var list = new ListView { Height = 260, SelectionMode = ListViewSelectionMode.None };
        foreach (var e in macro.Events) list.Items.Add($"{HidKeys.Name(e.Key),-14} {(e.Press ? "press ↓" : "release ↑"),-10} then {e.DelayMs} ms");
        page.Children.Add(list);
        byte key = 0x04; int delay = 20;
        page.Children.Add(Row(6, KeyCombo(key, false, u => key = u), Number("Delay ms", delay, 0, Macro.MaxDelay, v => delay = v),
            ButtonOf("+ Tap", () => { macro.Events.AddRange(Macro.Tap(key, delay, delay)); Rebuild(); }),
            ButtonOf("+ Press", () => { macro.Events.Add(new MacroEvent { Key = key, Press = true, DelayMs = delay }); Rebuild(); }),
            ButtonOf("+ Release", () => { macro.Events.Add(new MacroEvent { Key = key, Press = false, DelayMs = delay }); Rebuild(); }),
            ButtonOf("Remove last", () => { if (macro.Events.Count > 0) macro.Events.RemoveAt(macro.Events.Count - 1); Rebuild(); }),
            ButtonOf("Clear", () => { macro.Events.Clear(); Rebuild(); })));
        page.Children.Add(Note("128 bytes per macro, up to 8. Assign a macro to a button in the Buttons tab, then Apply."));
        return Scroll(page);
    }

    UIElement DevicePage() {
        var page = Page();
        page.Children.Add(Row(8,
            ButtonOf("Reset to vendor defaults", () => { profile = MouseProfile.VendorDefault(); Rebuild(); }),
            ButtonOf("LoL preset (side = F13)", () => { profile = MouseProfile.LolDefault(); Rebuild(); }),
            ButtonOf("Show profile file", () => { Save(); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", "/select,\"" + store + "\"") { UseShellExecute = true })?.Dispose(); })));
        if (lastGeneral != null) page.Children.Add(new TextBlock { Text = "General report (ID 4): " + BitConverter.ToString(lastGeneral.Feature).Replace("-", " "), TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), IsTextSelectionEnabled = true });
        page.Children.Add(new TextBlock { Text = "Log", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
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
        c.SelectedIndex = Math.Clamp(selected, 0, Math.Max(0, c.Items.Count - 1));
        c.SelectionChanged += (_, _) => { if (c.SelectedIndex >= 0) changed(c.SelectedIndex); };
        return c;
    }

    static ComboBox KeyCombo(byte usage, bool allowNone, Action<byte> changed) {
        var keys = (allowNone ? new[] { ((byte)0, "—") } : Array.Empty<(byte, string)>()).Concat(HidKeys.All).ToList();
        int index = Math.Max(0, keys.FindIndex(k => k.Item1 == usage));
        return Combo(keys.Select(k => HidKeys.InVendorTable(k.Item1) || k.Item1 == 0 ? k.Item2 : k.Item2 + " *"), index, i => changed(keys[i].Item1), 150);
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
