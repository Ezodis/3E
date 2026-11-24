// SPDX-License-Identifier: MIT
// 3£ Mouse window, laid out like the vendor configurator (OemDrv.exe, "Gaming Driver") so it can be
// modified from there: 1030×662 skinned window, key list on the left, the mouse picture with
// clickable numbered buttons in the middle, an accordion (DPI / Lighting / Mouse Parameter / Polling
// Rate) on the right, Mode and driver buttons at the bottom, a function picker popup and a macro editor.
// Positions come from the vendor app (Shared/PC205/PROTOCOL.md §8). Images come from the user's own copy
// of the vendor skin (VendorSkin); without it the same layout is drawn in code.
// Device-independent: talks only to IMouseDriver and builds everything from MouseCapabilities.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Color = Windows.UI.Color;

namespace ThreeE.Mouse;

public sealed class MouseWindow : Window {
    static MouseWindow open;
    const double W = 1030, H = 662;
    // Vendor Cfg.ini colours.
    static readonly Color Text = C(180, 180, 180), TextOver = C(255, 255, 255), TextDown = C(230, 0, 18),
        ListBack = C(39, 39, 39), ListItem = C(0, 218, 233), ListDown = C(255, 232, 6), PopBack = C(6, 6, 7), PopFrame = C(100, 100, 100);
    static readonly FontFamily Font = new("Microsoft Sans Serif");

    readonly string folder = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "Mouse");
    readonly Canvas root = new() { Width = W, Height = H };
    readonly Canvas page = new() { Width = W, Height = H };
    readonly Grid overlay = new() { Width = W, Height = H, Visibility = Visibility.Collapsed, Background = new SolidColorBrush(C(0, 0, 0, 140)) };
    readonly TextBlock status = Label("", 11, Text);
    readonly List<string> log = new();
    List<MouseDeviceEntry> detected = new();
    string selectedId;
    IMouseDriver driver;
    MouseProfile profile;
    VendorSkin skin;
    int mode, selectedSlot = -1, openPanel = 0;
    bool identifying;
    string identifyResult;
    nint hwnd;

    MouseCapabilities Caps => driver?.Capabilities;
    string ProfilePath => System.IO.Path.Combine(folder, driver.Id + ".json");
    int VisibleSlots => Caps == null ? 0 : Math.Min(Caps.Slots, Caps.VisibleSlots > 0 ? Caps.VisibleSlots : Caps.Slots);

    public static void Show() {
        if (open == null) { open = new MouseWindow(); open.Closed += (_, _) => open = null; }
        open.Activate();
    }

    public static void CloseSettings() => open?.Close();

    MouseWindow() {
        Title = "3£ Mouse";
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        if (AppWindow.Presenter is OverlappedPresenter p) { p.SetBorderAndTitleBar(false, false); p.IsResizable = false; p.IsMaximizable = false; }
        double scale = GetDpiForWindow(hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(W * scale), (int)(H * scale)));
        root.Children.Add(page);
        root.Children.Add(overlay);
        Content = new Grid { Background = new SolidColorBrush(Colors.Black), Children = { root } };
        Closed += (_, _) => { if (identifying) StopIdentify(); };
        Connect();
    }

    // ================= device & profile =================

    void Log(string line) { log.Add(line); if (log.Count > 400) log.RemoveAt(0); }

    void Connect() {
        try {
            detected = MouseDevices.Detect();
            var entry = detected.FirstOrDefault(e => e.Id == selectedId) ?? detected.FirstOrDefault();
            if (entry == null) {
                driver = null; profile = null; skin = null;
                status.Text = "No supported mouse connected. Supported: " + string.Join(", ", MouseDevices.Supported.Select(e => e.Name)) + ".";
            } else {
                selectedId = entry.Id;
                driver = entry.Create();
                driver.Log = Log;
                profile = LoadProfile();
                skin = LoadSkin();
                mode = Math.Clamp(profile.ActiveMode, 0, Math.Max(0, profile.Buttons.Count - 1));
                if (driver.Connect()) { status.Text = driver.DisplayName + " connected"; ReadFromMouse(false); }
                else status.Text = driver.DisplayName + " found, but its configuration interface did not answer.";
            }
        } catch (Exception ex) { status.Text = "Connect failed: " + ex.Message; Log(ex.ToString()); }
        Build();
    }

    VendorSkin LoadSkin() {
        if (string.IsNullOrEmpty(Caps.SkinProbe)) return null;
        var s = VendorSkin.Load(driver.Id, Caps.SkinProbe);
        if (s != null) return s;
        try { s = VendorSkin.AutoImport(driver.Id, Caps.SkinProbe, Caps.SkinSources); if (s != null) Log("vendor skin imported automatically"); }
        catch (Exception ex) { Log("skin auto-import: " + ex.Message); }
        return s;
    }

    MouseProfile LoadProfile() {
        var defaults = driver.DefaultProfile();
        try { if (File.Exists(ProfilePath)) return (JsonSerializer.Deserialize<MouseProfile>(File.ReadAllText(ProfilePath)) ?? defaults).Normalized(Caps, defaults); }
        catch (Exception ex) { Log("profile load failed: " + ex.Message); }
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
        if (rebuild) Build();
    }

    void Apply(MouseParts parts) {
        if (driver == null) return;
        Save();
        if (!driver.Ready) { status.Text = "Saved. The mouse is not connected – click the 3£ logo to reconnect."; return; }
        try {
            if (Caps.HasDpi && !profile.Stages.Any(s => s.Enabled)) profile.Stages[0].Enabled = true;
            driver.Apply(profile, parts);
            status.Text = "Applied to " + driver.DisplayName + " at " + DateTime.Now.ToLongTimeString();
        } catch (Exception ex) { status.Text = "Apply failed: " + ex.Message; }
    }

    // ================= layout =================

    void Build() {
        page.Children.Clear();
        // Background (main_nr.png 1030×662) or the drawn look-alike.
        if (Img("main_nr.png") is Image bg) page.Children.Add(bg);
        else DrawBackground();

        // Drag strip and the min / close buttons (Cfg.ini ptMinBtn=940,21).
        var drag = new Rectangle { Width = W - 120, Height = 36, Fill = new SolidColorBrush(Colors.Transparent) };
        drag.PointerPressed += (_, _) => { ReleaseCapture(); SendMessage(hwnd, 0xA1, 2, 0); };
        Place(drag, 20, 4);
        Place(Label("3£ Mouse" + (driver != null ? " – " + driver.DisplayName : ""), 14, Text, FontWeights.SemiBold), 40, 14);
        Place(SkinButton("min_nr.png", "min_ov.png", "min_ov.png", "–", 15, 15, () => (AppWindow.Presenter as OverlappedPresenter)?.Minimize()), 940, 21);
        Place(SkinButton("exit_nr.png", "exit_ov.png", "exit_ov.png", "×", 15, 15, Close), 965, 21);

        if (driver == null) {
            Place(Label("No supported mouse connected.", 16, TextOver, FontWeights.SemiBold), 340, 260);
            Place(Wrap("Supported: " + string.Join(", ", MouseDevices.Supported.Select(e => $"{e.Name} ({e.VendorId:X4}:{e.ProductId:X4})")) + ". Plug the mouse in and click Reconnect.", 360), 340, 290);
            Place(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "Reconnect", 92, 27, Connect), 340, 340);
            return;
        }
        if (Caps.HasButtons) BuildKeyList();
        BuildMousePicture();
        BuildAccordion();
        BuildBottom();
        status.MaxWidth = 640; status.TextWrapping = TextWrapping.Wrap;
        Place(status, 300, 626);
    }

    void DrawBackground() {
        var back = new Rectangle { Width = W, Height = H, Fill = new SolidColorBrush(C(85, 85, 85)), RadiusX = 6, RadiusY = 6 };
        Place(back, 0, 0);
        var inner = new Rectangle { Width = W - 20, Height = H - 16, Fill = new LinearGradientBrush { StartPoint = new(0, 0), EndPoint = new(0, 1), GradientStops = { new GradientStop { Color = C(14, 15, 17), Offset = 0 }, new GradientStop { Color = C(6, 7, 8), Offset = 1 } } }, RadiusX = 10, RadiusY = 10 };
        Place(inner, 10, 8);
        foreach (var (x, flip) in new[] { (10.0, false), (W - 32, true) })
            foreach (var y in new[] { 108.0, 498.0 })
                for (int i = 0; i < 4; i++) {
                    var stripe = new Polygon { Fill = new SolidColorBrush(C(230, 0, 18)), Points = flip
                        ? new PointCollection { new(22, 0), new(0, 6), new(0, 10), new(22, 4) }
                        : new PointCollection { new(0, 0), new(22, 6), new(22, 10), new(0, 4) } };
                    Place(stripe, x, y + i * 14);
                }
    }

    // ----- left: key list (window rect 30,40–270,300; buttons button2 179×25 at x=75, y=50+31·i) -----
    void BuildKeyList() {
        for (int s = 0; s < VisibleSlots; s++) {
            int slot = s;
            var a = profile.Buttons[mode][s];
            bool selected = s == selectedSlot;
            var b = SkinButton("button2_nr.png", "button2_ov.png", "button2_ov.png", (s + 1) + "   " + Short(a), 179, 25, () => { selectedSlot = slot; Build(); ShowPicker(slot); }, selected);
            ToolTipService.SetToolTip(b, (Caps.SlotNames.ElementAtOrDefault(s) ?? "Slot " + (s + 1)) + ": " + a.Label);
            Place(b, 75, 50 + 31 * s);
        }
        if (Caps.ExtraSideSlot > 0 && Caps.ExtraSideSlot <= VisibleSlots) {
            var side = profile.Buttons[mode][Caps.ExtraSideSlot - 1];
            bool f13 = side.Kind == ActionKind.Key && side.Value == HidKeys.F13;
            Place(Wrap($"Button {Caps.ExtraSideSlot} (extra side button) can do anything here, not only macros. 3£ Kalista kite = F13" + (f13 ? " ✓" : " – click to set it."), 200, f13 ? ListItem : ListDown), 75, 60 + 31 * VisibleSlots);
            if (!f13) {
                var set = SkinButton("btn_nr.png", "btn_ov.png", "btn_nr.png", "Set F13", 100, 24, () => SetSideKey(HidKeys.F13));
                Place(set, 75, 106 + 31 * VisibleSlots);
            }
        }
    }

    static string Short(ButtonAction a) => a.Kind switch {
        ActionKind.Key => HidKeys.ComboName((byte)a.Value2, (byte)a.Value, (byte)a.Value3),
        ActionKind.Mouse => ButtonAction.MouseButtonNames[Math.Clamp(a.Value, 0, 4)],
        ActionKind.Macro => "Macro " + a.Value,
        _ => a.Label.Length > 22 ? a.Label[..22] : a.Label,
    };

    void SetSideKey(byte usage) {
        for (int m = 0; m < profile.Buttons.Count; m++) profile.Buttons[m][Caps.ExtraSideSlot - 1] = ButtonAction.KeyPress(usage);
        Apply(MouseParts.Buttons);
        Build();
    }

    // ----- centre: mouse picture at (340,80), 280×440, numbered hotspots -----
    void BuildMousePicture() {
        const double px = 340, py = 80;
        if (Img(Caps.MousePicture) is Image pic) Place(pic, px, py);
        else DrawMouse(px, py);
        for (int s = 0; s < VisibleSlots && s < Caps.ButtonHotspots.Length; s++) {
            if (Caps.ButtonHotspots[s] is not (int hx, int hy)) continue;
            int slot = s;
            bool sel = s == selectedSlot;
            var ring = new Ellipse { Width = 26, Height = 26, StrokeThickness = sel ? 2.5 : 0, Stroke = new SolidColorBrush(TextDown), Fill = new SolidColorBrush(skin == null ? C(235, 235, 235) : Colors.Transparent) };
            var hit = new Grid { Width = 26, Height = 26, Children = { ring } };
            if (skin == null) hit.Children.Add(new TextBlock { Text = (s + 1).ToString(), FontSize = 13, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(C(20, 20, 20)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            hit.PointerEntered += (_, _) => { ring.StrokeThickness = 2.5; };
            hit.PointerExited += (_, _) => { ring.StrokeThickness = sel ? 2.5 : 0; };
            hit.Tapped += (_, _) => { selectedSlot = slot; Build(); ShowPicker(slot); };
            ToolTipService.SetToolTip(hit, (Caps.SlotNames.ElementAtOrDefault(s) ?? "Slot " + (s + 1)) + ": " + profile.Buttons[mode][s].Label);
            Place(hit, px + hx - 13, py + hy - 13);
        }
    }

    void DrawMouse(double x, double y) {
        var body = new Microsoft.UI.Xaml.Shapes.Path {
            Fill = new SolidColorBrush(C(48, 48, 50)), Stroke = new LinearGradientBrush { StartPoint = new(0, 0), EndPoint = new(0, 1), GradientStops = {
                new GradientStop { Color = C(0, 120, 255), Offset = 0 }, new GradientStop { Color = C(0, 220, 80), Offset = 0.45 }, new GradientStop { Color = C(255, 200, 0), Offset = 0.7 }, new GradientStop { Color = C(230, 0, 18), Offset = 1 } } },
            StrokeThickness = 3,
            Data = (Geometry)Microsoft.UI.Xaml.Markup.XamlBindingHelper.ConvertValue(typeof(Geometry), "M140,20 C70,20 40,60 38,120 C30,200 30,260 55,330 C75,390 110,420 140,420 C170,420 205,390 225,330 C250,260 250,200 242,120 C240,60 210,20 140,20 Z"),
        };
        Place(body, x, y);
        Place(new Rectangle { Width = 2, Height = 110, Fill = new SolidColorBrush(C(20, 20, 20)) }, x + 139, y + 22);
        Place(new Rectangle { Width = 16, Height = 44, RadiusX = 8, RadiusY = 8, Fill = new SolidColorBrush(C(150, 30, 30)) }, x + 131, y + 86);
    }

    // ----- right: accordion at x=743, headers 245×25 at y=41+30·i, open panel below its header -----
    void BuildAccordion() {
        var panels = new List<(string Title, Func<double, double, double> Build)>();
        if (Caps.HasDpi) panels.Add(("DPI Setting", DpiPanel));
        if (Caps.HasLighting) panels.Add(("Lighting", LightingPanel));
        panels.Add(("Mouse Parameter", ParameterPanel));
        if (Caps.HasPolling) panels.Add(("Polling Rate", PollingPanel));
        openPanel = Math.Clamp(openPanel, -1, panels.Count - 1);
        double y = 41;
        for (int i = 0; i < panels.Count; i++) {
            int index = i;
            Place(SkinButton("header_nr.png", "header_ov.png", "header_ov2.png", (openPanel == i ? "▾  " : "▸  ") + panels[i].Title, 245, 25,
                () => { openPanel = openPanel == index ? -1 : index; Build(); }, openPanel == i, leftAlign: true), 743, y);
            y += 30;
            if (openPanel == i) y += panels[i].Build(743, y) + 6;
        }
    }

    double DpiPanel(double x, double y) {
        bool xy = Caps.DpiXy && profile.XyIndependent;
        double cy = y + 4;
        if (Caps.DpiXy) { Place(Check("XY Independent", profile.XyIndependent, v => { profile.XyIndependent = v; Build(); }), x + 8, cy); cy += 22; }
        for (int i = 0; i < Caps.DpiStages; i++) {
            var s = profile.Stages[i];
            int stage = i;
            Place(Radio("", profile.CurrentStage == i, () => { profile.CurrentStage = stage; Build(); }), x + 6, cy + 3);
            Place(Check("", s.Enabled, v => s.Enabled = v), x + 26, cy + 5);
            var value = Label(xy ? $"{s.X}/{s.Y}" : s.X.ToString(), 11, profile.CurrentStage == i ? ListDown : Text);
            Place(DpiSlider(s.X, v => { s.X = v; if (!xy) s.Y = v; value.Text = xy ? $"{s.X}/{s.Y}" : s.X.ToString(); }), x + 42, cy + 1);
            Place(value, x + 160, cy + 3);
            if (Caps.DpiColorNames.Length > 1) {
                var sw = new Rectangle { Width = 22, Height = 14, RadiusX = 2, RadiusY = 2, Fill = new SolidColorBrush(DpiColor(s.Color)), Stroke = new SolidColorBrush(PopFrame) };
                ToolTipService.SetToolTip(sw, "Colour: " + Caps.DpiColorNames[s.Color] + " (click to change)");
                sw.Tapped += (_, _) => { s.Color = s.Color % (Caps.DpiColorNames.Length - 1) + 1; sw.Fill = new SolidColorBrush(DpiColor(s.Color)); };
                Place(sw, x + 214, cy + 3);
            }
            cy += 24;
            if (xy) {
                Place(Label("Y", 11, Text), x + 30, cy + 2);
                Place(DpiSlider(s.Y, v => { s.Y = v; value.Text = $"{s.X}/{s.Y}"; }), x + 42, cy);
                cy += 22;
            }
        }
        Place(SkinButton("btn_nr.png", "btn_ov.png", "btn_nr.png", "Apply DPI", 100, 24, () => Apply(MouseParts.Dpi)), x + 140, cy + 4);
        return cy + 30 - y;
    }

    UIElement DpiSlider(int value, Action<int> changed) {
        var slider = new Slider { Width = 112, Minimum = 0, Maximum = Caps.DpiValues.Length - 1, StepFrequency = 1, Value = Math.Max(0, Array.IndexOf(Caps.DpiValues, value)), IsThumbToolTipEnabled = false, Height = 20, Padding = new Thickness(0) };
        slider.Resources["SliderTrackValueFill"] = new SolidColorBrush(TextDown);
        slider.Resources["SliderThumbBackground"] = new SolidColorBrush(TextDown);
        slider.ValueChanged += (_, e) => changed(Caps.DpiValues[(int)e.NewValue]);
        return slider;
    }

    Color DpiColor(int index) {
        string n = Caps.DpiColorNames.ElementAtOrDefault(index) ?? "";
        return n switch { "Red" => C(255, 0, 0), "Green" => C(0, 255, 0), "Blue" => C(0, 80, 255), "Cyan" => C(0, 255, 255), "Yellow" => C(255, 255, 0), "Magenta" => C(255, 0, 255), "White" => C(255, 255, 255), _ => C(40, 40, 40) };
    }

    double LightingPanel(double x, double y) {
        double cy = y + 6;
        Place(Label("Effect", 11, Text), x + 8, cy + 4);
        var visible = Enumerable.Range(0, Caps.LightingEffects.Length).Where(i => !Caps.LightingEffectsHidden.Contains(i) || i == profile.Effect).ToList();
        Place(SkinCombo(visible.Select(i => Caps.LightingEffects[i]).ToList(), visible.IndexOf(profile.Effect), k => profile.Effect = visible[k], 160), x + 70, cy);
        cy += 32;
        if (Caps.LightingLevelMax > 0) {
            Place(Label("Speed / Brightness", 11, Text), x + 8, cy + 2);
            var level = new Slider { Width = 120, Minimum = 1, Maximum = Caps.LightingLevelMax, StepFrequency = 1, Value = Math.Clamp(profile.Level, 1, Caps.LightingLevelMax) };
            level.ValueChanged += (_, e) => profile.Level = (int)e.NewValue;
            Place(level, x + 115, cy - 6);
            cy += 30;
        }
        if (Caps.LightingRandom) { Place(Check("Random colour", profile.LightingRandom, v => profile.LightingRandom = v), x + 8, cy); cy += 22; }
        if (Caps.LightingColors > 0) {
            Place(Label("Colour", 11, Text), x + 8, cy + 2);
            for (int i = 0; i < Caps.LightingColors; i++) {
                int index = i;
                var sw = new Rectangle { Width = 22, Height = 18, RadiusX = 2, RadiusY = 2, Fill = new SolidColorBrush(Rgb(profile.Colors[i])), Stroke = new SolidColorBrush(i < profile.LightingColorCount ? TextOver : PopFrame) };
                var picker = new ColorPicker { Color = Rgb(profile.Colors[i]), IsAlphaEnabled = false };
                picker.ColorChanged += (_, e) => { profile.Colors[index] = e.NewColor.R << 16 | e.NewColor.G << 8 | e.NewColor.B; sw.Fill = new SolidColorBrush(e.NewColor); };
                var b = new Button { Content = sw, Padding = new Thickness(1), MinWidth = 0, MinHeight = 0, Background = new SolidColorBrush(Colors.Transparent), BorderThickness = new Thickness(0), Flyout = new Flyout { Content = picker } };
                Place(b, x + 56 + 26 * i, cy - 2);
            }
            cy += 24;
            Place(Label("Colours used", 11, Text), x + 8, cy + 2);
            for (int n = 0; n <= Caps.LightingColors; n++) {
                int count = n;
                Place(Radio(n.ToString(), profile.LightingColorCount == n, () => { profile.LightingColorCount = count; Build(); }), x + 90 + 20 * n, cy + 2);
            }
            cy += 24;
        }
        Place(SkinButton("btn_nr.png", "btn_ov.png", "btn_nr.png", "Apply Lighting", 100, 24, () => Apply(MouseParts.Lighting)), x + 140, cy + 4);
        return cy + 30 - y;
    }

    // Vendor "Mouse Parameter": Windows pointer settings for the current user (tc_sys_str1–5).
    double ParameterPanel(double x, double y) {
        double cy = y + 6;
        int speed = 10; SystemParametersInfo(0x0070 /* SPI_GETMOUSESPEED */, 0, ref speed, 0);
        int lines = 3; SystemParametersInfo(0x0068 /* SPI_GETWHEELSCROLLLINES */, 0, ref lines, 0);
        int dbl = (int)GetDoubleClickTime();
        int[] accel = new int[3]; SystemParametersInfoArray(0x0003 /* SPI_GETMOUSE */, 0, accel, 0);
        Place(Label("Pointer speed", 11, Text), x + 8, cy + 2);
        var sp = new Slider { Width = 120, Minimum = 1, Maximum = 20, StepFrequency = 1, Value = speed };
        sp.ValueChanged += (_, e) => { int v = (int)e.NewValue; SystemParametersInfoPtr(0x0071 /* SPI_SETMOUSESPEED */, 0, v, 3); };
        Place(sp, x + 115, cy - 6); cy += 30;
        Place(Check("Enhance pointer precision", accel[2] != 0, v => { accel[2] = v ? 1 : 0; if (v) { accel[0] = 6; accel[1] = 10; } SystemParametersInfoArray(0x0004 /* SPI_SETMOUSE */, 0, accel, 3); }), x + 8, cy); cy += 24;
        Place(Label("Scroll lines", 11, Text), x + 8, cy + 2);
        var sl = new Slider { Width = 120, Minimum = 1, Maximum = 20, StepFrequency = 1, Value = Math.Clamp(lines, 1, 20) };
        sl.ValueChanged += (_, e) => SystemParametersInfoPtr(0x0069 /* SPI_SETWHEELSCROLLLINES */, (int)e.NewValue, 0, 3);
        Place(sl, x + 115, cy - 6); cy += 30;
        Place(Label("Double-click speed", 11, Text), x + 8, cy + 2);
        var dc = new Slider { Width = 120, Minimum = 200, Maximum = 900, StepFrequency = 50, Value = Math.Clamp(dbl, 200, 900), IsDirectionReversed = true };
        dc.ValueChanged += (_, e) => SetDoubleClickTime((uint)e.NewValue);
        Place(dc, x + 115, cy - 6); cy += 30;
        return cy - y;
    }

    double PollingPanel(double x, double y) {
        double cy = y + 6;
        int m = Math.Clamp(mode, 0, profile.RatesHz.Length - 1);
        if (Caps.Modes > 1) { Place(Label($"USB polling rate (Hz) – Mode {m + 1}", 11, Text), x + 8, cy); cy += 20; }
        for (int i = 0; i < Caps.PollingRatesHz.Length; i++) {
            int hz = Caps.PollingRatesHz[i];
            Place(Radio(hz.ToString(), profile.RatesHz[m] == hz, () => { profile.RatesHz[m] = hz; Build(); }), x + 8 + 58 * i, cy);
        }
        cy += 26;
        Place(SkinButton("btn_nr.png", "btn_ov.png", "btn_nr.png", "Apply Rate", 100, 24, () => Apply(MouseParts.Polling)), x + 140, cy);
        return cy + 28 - y;
    }

    // ----- bottom: Mode (ProfileGpY=500) and driver buttons (DrvGpY=570) -----
    void BuildBottom() {
        if (Caps.Modes > 1) {
            Place(Label("Mode", 12, Text, FontWeights.SemiBold), 45, 478);
            for (int m = 0; m < Caps.Modes; m++) {
                int index = m;
                var b = SkinButton("btn_nr.png", "btn_ov.png", "btn_ov.png", $"Mode {m + 1}" + (profile.ActiveMode == m ? " ●" : ""), 100, 24,
                    () => { mode = index; profile.ActiveMode = index; selectedSlot = -1; Build(); }, mode == m);
                ToolTipService.SetToolTip(b, "Edit Mode " + (m + 1) + " and make it the active mode on Apply");
                Place(b, 45 + 106 * m, 500);
            }
        }
        double x = 45;
        void Btn(string text, Action click, string tip) {
            var b = SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", text, 92, 27, click);
            ToolTipService.SetToolTip(b, tip);
            Place(b, x, 570); x += 98;
        }
        if (Caps.HasMacros) Btn("Macro", ShowMacroEditor, "Macro Editor");
        if (Caps.IdentifySlots.Length > 0 && Caps.Actions.Contains(ActionKind.Key))
            Btn(identifying ? "Stop" : "Identify", () => { if (identifying) StopIdentify(); else StartIdentify(); Build(); }, "Find out which number a physical button is");
        Btn("Restore", () => { profile = driver.DefaultProfile().Normalized(Caps, driver.DefaultProfile()); Build(); }, "Restore the default settings (press Apply to write them)");
        Btn("Read", () => ReadFromMouse(), "Read the current settings from the mouse");
        Btn("Apply", () => Apply(MouseParts.All), "Write all settings to the mouse");
        Btn("Info", ShowInfo, "Device, skin and log");
        if (identifying) Place(Wrap(identifyResult ?? "Press a side/top button on the mouse…", 300, ListDown), 640, 540);
    }

    // ================= function picker (pickfundlg.png 540×340) =================

    void ShowPicker(int slot) {
        var current = profile.Buttons[mode][slot];
        var draft = current;
        var panel = new Canvas { Width = 540, Height = 340 };
        if (Img("pickfundlg.png") is Image bg) panel.Children.Add(bg);
        else { var r = new Rectangle { Width = 540, Height = 340, Fill = new SolidColorBrush(PopBack), Stroke = new SolidColorBrush(PopFrame), RadiusX = 4, RadiusY = 4 }; panel.Children.Add(r); }
        void P(UIElement e, double x, double y) { Canvas.SetLeft(e, x); Canvas.SetTop(e, y); panel.Children.Add(e); }
        P(Label($"{slot + 1}. {Caps.SlotNames.ElementAtOrDefault(slot) ?? "Slot " + (slot + 1)}  –  Mode {mode + 1}", 13, TextOver, FontWeights.SemiBold), 20, 12);
        var detail = new Canvas { Width = 300, Height = 220 };
        P(detail, 220, 44);
        var kinds = Caps.Actions.Where(k => k != ActionKind.Raw || current.Kind == ActionKind.Raw).ToList();
        void Refresh() {
            detail.Children.Clear();
            BuildDetail(detail, slot, () => draft, a => draft = a);
        }
        var radios = new StackPanel { Spacing = 1 };
        foreach (var k in kinds) {
            var kind = k;
            radios.Children.Add(Radio(KindName(k), draft.Kind == k, () => {
                if (draft.Kind != kind) draft = DefaultFor(kind);
                foreach (var child in radios.Children.OfType<FrameworkElement>()) SetRadio(child, child.Tag as string == KindName(kind));
                Refresh();
            }));
        }
        P(new ScrollViewer { Content = radios, Height = 250, Width = 190 }, 20, 44);
        if (slot + 1 == Caps.ExtraSideSlot)
            P(Wrap("Extra side button: the vendor app only allows macros here – 3£ allows anything. For the 3£ Kalista kite choose Key / combo → F13 (or Pause).", 300, ListDown), 220, 262);
        P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "OK", 92, 27, () => {
            profile.Buttons[mode][slot] = draft; HideOverlay(); Build();
            status.Text = $"Button {slot + 1}: {draft.Label} – press Apply to write it to the mouse.";
        }), 330, 300);
        P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "Cancel", 92, 27, HideOverlay), 430, 300);
        Refresh();
        ShowOverlay(panel);
    }

    static string KindName(ActionKind k) => k switch {
        ActionKind.Mouse => "Mouse button", ActionKind.DoubleClick => "Double Click", ActionKind.TripleClick => "Three Click",
        ActionKind.Key => "Key / Key Combination", ActionKind.Fire => "Fire key", ActionKind.Media => "Multimedia",
        ActionKind.DpiUp => "DPI+", ActionKind.DpiDown => "DPI-", ActionKind.DpiLoop => "DPI Loop", ActionKind.DpiLock => "DPI Lock",
        ActionKind.SwitchPollingRate => "Switch Polling Rate", ActionKind.SwitchLighting => "Switch Effect",
        ActionKind.Disabled => "Disable", ActionKind.Macro => "Macro", _ => "Raw value",
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

    void BuildDetail(Canvas c, int slot, Func<ButtonAction> get, Action<ButtonAction> set) {
        void P(UIElement e, double x, double y) { Canvas.SetLeft(e, x); Canvas.SetTop(e, y); c.Children.Add(e); }
        var a = get();
        switch (a.Kind) {
            case ActionKind.Mouse:
                for (int i = 0; i < Caps.MouseButtons; i++) { int b = i; P(Radio(ButtonAction.MouseButtonNames[i], a.Value == i, () => { set(get() with { Value = b }); Refresh(); }), 0, 22 * i); }
                break;
            case ActionKind.Key: {
                P(Label("Click the box and press the key or combination:", 11, Text), 0, 0);
                var box = new TextBox { Width = 280, IsReadOnly = true, Text = HidKeys.ComboName((byte)a.Value2, (byte)a.Value, (byte)a.Value3), FontFamily = Font };
                box.PreviewKeyDown += (_, e) => {
                    byte u = HidKeys.FromVirtualKey((int)e.Key); e.Handled = true;
                    if (u == 0) return;
                    var cur = get(); byte bit = HidKeys.ModifierBit(u);
                    cur = bit != 0 ? cur with { Value2 = cur.Value2 | bit } : cur.Value == 0 || cur.Value3 != 0 ? cur with { Value = u, Value3 = 0 } : cur with { Value3 = u };
                    set(cur); box.Text = HidKeys.ComboName((byte)cur.Value2, (byte)cur.Value, (byte)cur.Value3);
                };
                P(box, 0, 20);
                P(Mini("Clear", () => { set(ButtonAction.KeyPress(0)); box.Text = "(none)"; }), 0, 58);
                P(Mini("F13", () => { set(ButtonAction.KeyPress(HidKeys.F13)); box.Text = "F13"; }), 70, 58);
                P(Mini("Pause", () => { set(ButtonAction.KeyPress(HidKeys.Pause)); box.Text = "Pause"; }), 140, 58);
                P(Label("Or pick from the list:", 11, Text), 0, 94);
                P(SkinCombo(HidKeys.All.Select(k => k.Name).ToList(), HidKeys.All.ToList().FindIndex(k => k.Usage == a.Value), i => { set(get() with { Value = HidKeys.All[i].Usage, Value3 = 0 }); box.Text = HidKeys.ComboName((byte)get().Value2, (byte)get().Value, 0); }, 189), 0, 114);
                break;
            }
            case ActionKind.Fire: {
                P(Label("Key", 11, Text), 0, 4);
                P(SkinCombo(HidKeys.All.Select(k => k.Name).ToList(), HidKeys.All.ToList().FindIndex(k => k.Usage == a.Value), i => set(get() with { Value = HidKeys.All[i].Usage }), 189), 60, 0);
                P(Label("Loop (1-255)", 11, Text), 0, 40);
                P(Number(a.Value3, 1, 255, v => set(get() with { Value3 = (uint)v })), 120, 34);
                P(Label("Interval (5-255 ms)", 11, Text), 0, 76);
                P(Number(a.Value2, 5, 255, v => set(get() with { Value2 = v })), 120, 70);
                P(Wrap("The smaller the interval, the faster the key repeats.", 280), 0, 110);
                break;
            }
            case ActionKind.Media:
                for (int i = 0; i < Caps.MediaKeys.Length; i++) { var mk = Caps.MediaKeys[i]; P(Radio(mk.ToString(), (MediaKey)a.Value == mk, () => { set(ButtonAction.Media(mk)); Refresh(); }), 150 * (i / 10), 21 * (i % 10)); }
                break;
            case ActionKind.DpiLock:
                for (int i = 0; i < Caps.DpiValues.Length; i++) { int d = Caps.DpiValues[i]; P(Radio(d + " DPI", a.Value == d, () => { set(ButtonAction.DpiLock(d)); Refresh(); }), 100 * (i / 8), 22 * (i % 8)); }
                break;
            case ActionKind.Macro: {
                P(Label("Macro", 11, Text), 0, 4);
                P(SkinCombo(Enumerable.Range(1, Caps.MacroCount).Select(i => i + ". " + profile.Macros[i - 1].Name).ToList(), a.Value - 1, i => set(get() with { Value = i + 1 }), 189), 60, 0);
                var repeats = Enum.GetValues<MacroRepeat>();
                string[] names = { "Specified cycle times", "Cycle until the key released", "Cycle until any key pressed" };
                for (int i = 0; i < repeats.Length; i++) { var r = repeats[i]; P(Radio(names[i], (MacroRepeat)a.Value2 == r, () => { set(get() with { Value2 = (int)r }); Refresh(); }), 0, 40 + 22 * i); }
                P(Mini("Macro Editor…", () => { HideOverlay(); ShowMacroEditor(); }), 0, 120);
                break;
            }
            case ActionKind.Raw: {
                var hex = new TextBox { Text = a.Value3.ToString("X8"), Width = 110, FontFamily = new FontFamily("Consolas") };
                hex.TextChanged += (_, _) => { if (uint.TryParse(hex.Text, System.Globalization.NumberStyles.HexNumber, null, out var v)) set(get() with { Value3 = v }); };
                P(hex, 0, 0);
                break;
            }
            default:
                P(Wrap(KindName(a.Kind) + " – no options.", 280), 0, 0);
                break;
        }
        void Refresh() { c.Children.Clear(); BuildDetail(c, slot, get, set); }
    }

    // ================= macro editor (macro_nr.png 767×418) =================

    int macroIndex;
    bool recording;
    Stopwatch recordClock;

    void ShowMacroEditor() {
        macroIndex = Math.Clamp(macroIndex, 0, Caps.MacroCount - 1);
        var panel = new Canvas { Width = 767, Height = 418 };
        if (Img("macro_nr.png") is Image bg) panel.Children.Add(bg);
        else panel.Children.Add(new Rectangle { Width = 767, Height = 418, Fill = new SolidColorBrush(PopBack), Stroke = new SolidColorBrush(PopFrame), RadiusX = 4, RadiusY = 4 });
        void P(UIElement e, double x, double y) { Canvas.SetLeft(e, x); Canvas.SetTop(e, y); panel.Children.Add(e); }
        var macro = profile.Macros[macroIndex];
        P(Label("Macro Editor", 13, TextOver, FontWeights.SemiBold), 20, 12);
        P(SkinButton("exit_nr.png", "exit_ov.png", "exit_ov.png", "×", 15, 15, () => { recording = false; HideOverlay(); Build(); }), 735, 14);

        P(Label("Macro list", 11, Text), 20, 44);
        var list = new StackPanel { Spacing = 2 };
        for (int i = 0; i < Caps.MacroCount; i++) {
            int index = i;
            list.Children.Add(ListRow((i + 1) + ". " + profile.Macros[i].Name, i == macroIndex, () => { macroIndex = index; recording = false; ShowMacroEditor(); }, 170));
        }
        P(new ScrollViewer { Content = list, Width = 180, Height = 250 }, 20, 64);
        var name = new TextBox { Text = macro.Name, Width = 170, FontFamily = Font };
        name.TextChanged += (_, _) => macro.Name = name.Text;
        P(name, 20, 324);

        P(Label("Key list", 11, Text), 220, 44);
        var events = new StackPanel { Spacing = 1 };
        int n = 0;
        foreach (var e in macro.Events) {
            events.Children.Add(ListRow($"{++n,3}  {(e.Press ? "↓" : "↑")} {HidKeys.Name(e.Key)}", false, null, 300));
            events.Children.Add(Label($"        Delay {e.DelayMs} ms", 10, Text));
        }
        P(new ScrollViewer { Content = events, Width = 320, Height = 290, Background = new SolidColorBrush(ListBack) }, 220, 64);

        double rx = 560;
        var capture = new TextBox { Width = 180, IsReadOnly = true, PlaceholderText = recording ? "Recording – press keys here" : "Click Start record", FontFamily = Font };
        capture.PreviewKeyDown += (_, e) => Record(macro, (int)e.Key, true, e);
        capture.PreviewKeyUp += (_, e) => Record(macro, (int)e.Key, false, e);
        var rec = SkinButton(recording ? "recbtn_dn.png" : "recbtn_nr.png", "recbtn_dn.png", "recbtn_dn.png", recording ? "Stop record" : "Start record", 128, 30, () => {
            recording = !recording; recordClock = Stopwatch.StartNew(); ShowMacroEditor();
        });
        P(rec, rx, 64);
        P(capture, rx, 100);
        if (recording) capture.Loaded += (_, _) => capture.Focus(FocusState.Programmatic);
        P(Label("Insert event", 11, Text), rx, 140);
        P(Mini("+ Left", () => { AddClick(macro, 0xF0); ShowMacroEditor(); }), rx, 160);
        P(Mini("+ Right", () => { AddClick(macro, 0xF1); ShowMacroEditor(); }), rx + 62, 160);
        P(Mini("+ Middle", () => { AddClick(macro, 0xF2); ShowMacroEditor(); }), rx + 124, 160);
        P(Mini("+ Delay 50", () => { if (macro.Events.Count > 0) macro.Events[^1].DelayMs += 50; ShowMacroEditor(); }), rx, 192);
        P(Mini("Delete last", () => { if (macro.Events.Count > 0) macro.Events.RemoveAt(macro.Events.Count - 1); ShowMacroEditor(); }), rx + 92, 192);
        P(Mini("Clear", () => { macro.Events.Clear(); ShowMacroEditor(); }), rx, 224);
        P(Label("Specified cycle times", 11, Text), rx, 260);
        P(Number(macro.RepeatCount, 1, 65535, v => macro.RepeatCount = (ushort)v), rx, 280);
        P(Wrap($"Max {Caps.MacroBytes} bytes per macro, {Caps.MacroCount} macros. Assign it to a button with the function picker, then Apply.", 190), rx, 320);
        P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "OK", 92, 27, () => { recording = false; Save(); HideOverlay(); Build(); }), 655, 376);
        ShowOverlay(panel);
    }

    void Record(Macro macro, int vk, bool press, KeyRoutedEventArgs e) {
        e.Handled = true;
        if (!recording) return;
        byte u = HidKeys.FromVirtualKey(vk);
        if (u == 0) return;
        if (press && macro.Events.Count > 0 && macro.Events[^1].Key == u && macro.Events[^1].Press) return; // key repeat
        int ms = (int)recordClock.ElapsedMilliseconds; recordClock.Restart();
        if (macro.Events.Count > 0) macro.Events[^1].DelayMs = Math.Clamp(ms, 1, Caps.MacroMaxDelayMs);
        macro.Events.Add(new MacroEvent { Key = u, Press = press, DelayMs = 20 });
        ShowMacroEditor();
    }

    static void AddClick(Macro m, byte button) { m.Events.Add(new MacroEvent { Key = button, Press = true, DelayMs = 20 }); m.Events.Add(new MacroEvent { Key = button, Press = false, DelayMs = 20 }); }

    // ================= identify / info =================

    void StartIdentify() {
        if (driver?.Ready != true) { status.Text = "Connect the mouse first."; return; }
        var temp = profile.Clone();
        for (int i = 0; i < Caps.IdentifySlots.Length && i < 12; i++)
            foreach (var row in temp.Buttons) row[Caps.IdentifySlots[i] - 1] = ButtonAction.KeyPress((byte)(HidKeys.F13 + i));
        try {
            driver.Apply(temp, MouseParts.Buttons); identifying = true; identifyResult = null;
            Content.KeyDown += IdentifyKey;
            status.Text = "Identify: press a side/top button on the mouse (this window must be focused).";
        } catch (Exception ex) { status.Text = "Identify failed: " + ex.Message; }
    }

    void IdentifyKey(object sender, KeyRoutedEventArgs e) {
        int index = (int)e.Key - 0x7C; // VK_F13
        if (!identifying || index < 0 || index >= Caps.IdentifySlots.Length) return;
        int slot = Caps.IdentifySlots[index];
        identifyResult = $"That button is number {slot} ({Caps.SlotNames.ElementAtOrDefault(slot - 1) ?? "slot " + slot}).";
        selectedSlot = slot - 1;
        e.Handled = true;
        Build();
    }

    void StopIdentify() {
        identifying = false;
        Content.KeyDown -= IdentifyKey;
        Apply(MouseParts.Buttons);
        status.Text += " Original mapping restored.";
    }

    void ShowInfo() {
        var panel = new Canvas { Width = 530, Height = 360 };
        panel.Children.Add(new Rectangle { Width = 530, Height = 360, Fill = new SolidColorBrush(PopBack), Stroke = new SolidColorBrush(PopFrame), RadiusX = 4, RadiusY = 4 });
        void P(UIElement e, double x, double y) { Canvas.SetLeft(e, x); Canvas.SetTop(e, y); panel.Children.Add(e); }
        P(Label("Device", 13, TextOver, FontWeights.SemiBold), 20, 12);
        var lines = new List<string> { "Supported: " + string.Join(", ", MouseDevices.Supported.Select(e => $"{e.Name} ({e.VendorId:X4}:{e.ProductId:X4})")) };
        lines.Add(skin != null ? "Vendor skin: " + skin.Folder : "Vendor skin: not imported – showing the drawn look-alike.");
        if (driver != null) lines.AddRange(driver.Diagnostics());
        lines.Add("Profile: " + (driver != null ? ProfilePath : "-"));
        lines.Add("— log —");
        lines.AddRange(log.TakeLast(40));
        var text = new TextBox { Text = string.Join("\n", lines), IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), FontSize = 11, Width = 490, Height = 250 };
        P(text, 20, 40);
        if (driver != null && !string.IsNullOrEmpty(Caps.SkinProbe)) P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "Import skin…", 92, 27, ImportSkin), 20, 310);
        P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "Reconnect", 92, 27, () => { HideOverlay(); Connect(); }), 120, 310);
        P(SkinButton("button3_nr.png", "button3_ov.png", "button3_nr.png", "Close", 92, 27, HideOverlay), 418, 310);
        ShowOverlay(panel);
    }

    async void ImportSkin() {
        try {
            var picker = new Windows.Storage.Pickers.FileOpenPicker();
            picker.FileTypeFilter.Add(".zip");
            picker.FileTypeFilter.Add(".png");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
            var file = await picker.PickSingleFileAsync();
            if (file == null) return;
            // A .zip of the vendor app, or any image inside its skins folder.
            string source = file.Path.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) ? file.Path : System.IO.Path.GetDirectoryName(file.Path);
            if (System.IO.Path.GetFileName(source).Equals("mouse", StringComparison.OrdinalIgnoreCase)) source = System.IO.Path.GetDirectoryName(source);
            skin = VendorSkin.Import(driver.Id, source, Caps.SkinProbe);
            HideOverlay();
            Build();
            status.Text = "Vendor skin imported.";
        } catch (Exception ex) { status.Text = "Import failed: " + ex.Message; }
    }

    // ================= skinned controls =================

    Image Img(string relative) {
        var path = relative == null ? null : skin?.PathOf(relative);
        if (path == null) return null;
        return new Image { Source = new BitmapImage(new Uri(path)), Stretch = Stretch.None, IsHitTestVisible = false };
    }

    ImageSource Src(string relative) { var p = relative == null ? null : skin?.PathOf(relative); return p == null ? null : new BitmapImage(new Uri(p)); }

    /// Vendor-style button: normal / hover / down images with centred caption (Btn_txt_clr_nr/ov/dn).
    FrameworkElement SkinButton(string nr, string ov, string dn, string text, double w, double h, Action click, bool down = false, bool leftAlign = false) {
        var grid = new Grid { Width = w, Height = h, Background = new SolidColorBrush(Colors.Transparent) };
        var img = Src(down ? dn : nr);
        Rectangle face = null;
        if (img != null) grid.Children.Add(new Image { Source = img, Stretch = Stretch.Fill });
        else {
            face = new Rectangle { RadiusX = 3, RadiusY = 3, StrokeThickness = 1, Fill = new SolidColorBrush(down ? C(60, 8, 10) : C(26, 27, 30)), Stroke = new SolidColorBrush(down ? TextDown : C(70, 70, 74)) };
            grid.Children.Add(face);
        }
        var label = new TextBlock { Text = text, FontFamily = Font, FontSize = h <= 16 ? 12 : 12.5, Foreground = new SolidColorBrush(down ? TextDown : Text),
            HorizontalAlignment = leftAlign ? HorizontalAlignment.Left : HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(leftAlign ? 12 : 2, 0, 2, 0), TextTrimming = TextTrimming.CharacterEllipsis };
        grid.Children.Add(label);
        grid.PointerEntered += (_, _) => { label.Foreground = new SolidColorBrush(down ? TextDown : TextOver); if (Src(ov) is ImageSource o && grid.Children[0] is Image i) i.Source = o; else if (face != null) face.Stroke = new SolidColorBrush(TextOver); };
        grid.PointerExited += (_, _) => { label.Foreground = new SolidColorBrush(down ? TextDown : Text); if (img != null && grid.Children[0] is Image i) i.Source = img; else if (face != null) face.Stroke = new SolidColorBrush(down ? TextDown : C(70, 70, 74)); };
        grid.PointerPressed += (_, _) => label.Foreground = new SolidColorBrush(TextDown);
        grid.Tapped += (_, _) => { try { click(); } catch (Exception ex) { status.Text = ex.Message; Log(ex.ToString()); } };
        return grid;
    }

    FrameworkElement Mini(string text, Action click) => SkinButton("dot_nr.png", "dot_ov.png", "dot_nr.png", text, Math.Max(56, text.Length * 7 + 14), 20, click);

    FrameworkElement SkinCombo(List<string> items, int selected, Action<int> changed, double w) {
        var grid = new Grid { Width = w, Height = 25 };
        if (Src(w < 170 ? "combo2_nr.png" : "combo_nr.png") is ImageSource s) grid.Children.Add(new Image { Source = s, Stretch = Stretch.Fill });
        else grid.Children.Add(new Rectangle { RadiusX = 3, RadiusY = 3, Fill = new SolidColorBrush(C(26, 27, 30)), Stroke = new SolidColorBrush(C(70, 70, 74)) });
        var combo = new ComboBox { Width = w, Height = 25, MinHeight = 0, Padding = new Thickness(8, 0, 0, 0), FontFamily = Font, FontSize = 12, Background = new SolidColorBrush(Colors.Transparent), BorderThickness = new Thickness(0), Foreground = new SolidColorBrush(Text) };
        foreach (var i in items) combo.Items.Add(i);
        combo.SelectedIndex = items.Count == 0 ? -1 : Math.Clamp(selected, 0, items.Count - 1);
        combo.SelectionChanged += (_, _) => { if (combo.SelectedIndex >= 0) changed(combo.SelectedIndex); };
        grid.Children.Add(combo);
        return grid;
    }

    FrameworkElement Check(string text, bool value, Action<bool> changed) {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Background = new SolidColorBrush(Colors.Transparent) };
        var box = new Grid { Width = 11, Height = 11, VerticalAlignment = VerticalAlignment.Center };
        void Paint() {
            box.Children.Clear();
            if (Src(value ? "check_dn.png" : "check_nr.png") is ImageSource s) box.Children.Add(new Image { Source = s });
            else { box.Children.Add(new Rectangle { Stroke = new SolidColorBrush(Text), Fill = new SolidColorBrush(value ? TextDown : C(20, 20, 20)) }); }
        }
        Paint();
        row.Children.Add(box);
        if (text.Length > 0) row.Children.Add(Label(text, 11, Text));
        row.Tapped += (_, _) => { value = !value; Paint(); changed(value); };
        return row;
    }

    FrameworkElement Radio(string text, bool value, Action chosen) {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Tag = text, Background = new SolidColorBrush(Colors.Transparent) };
        row.Children.Add(new Grid { Width = 15, Height = 15, VerticalAlignment = VerticalAlignment.Center });
        if (text.Length > 0) row.Children.Add(Label(text, 11.5, value ? ListDown : Text));
        SetRadio(row, value);
        row.Tapped += (_, _) => chosen();
        return row;
    }

    void SetRadio(FrameworkElement row, bool on) {
        if (row is not StackPanel p || p.Children[0] is not Grid g) return;
        g.Children.Clear();
        if (Src(on ? "radio_dn.png" : "radio_nr.png") is ImageSource s) g.Children.Add(new Image { Source = s });
        else { g.Children.Add(new Ellipse { Stroke = new SolidColorBrush(Text), StrokeThickness = 1 }); if (on) g.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(TextDown) }); }
        if (p.Children.Count > 1 && p.Children[1] is TextBlock t) t.Foreground = new SolidColorBrush(on ? ListDown : Text);
    }

    static FrameworkElement ListRow(string text, bool selected, Action click, double w) {
        var b = new Border { Width = w, Height = 20, Background = new SolidColorBrush(selected ? ListItem : ListBack), Padding = new Thickness(6, 0, 0, 0),
            Child = new TextBlock { Text = text, FontFamily = Font, FontSize = 11.5, Foreground = new SolidColorBrush(selected ? C(0, 0, 0) : Text), VerticalAlignment = VerticalAlignment.Center } };
        if (click != null) b.Tapped += (_, _) => click();
        return b;
    }

    static NumberBox Number(double value, double min, double max, Action<int> changed) {
        var n = new NumberBox { Value = value, Minimum = min, Maximum = max, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, Width = 110, FontFamily = Font };
        n.ValueChanged += (_, e) => { if (!double.IsNaN(e.NewValue)) changed((int)Math.Clamp(e.NewValue, min, max)); };
        return n;
    }

    static TextBlock Label(string t, double size, Color color, Windows.UI.Text.FontWeight? weight = null) =>
        new() { Text = t, FontFamily = Font, FontSize = size, Foreground = new SolidColorBrush(color), FontWeight = weight ?? FontWeights.Normal };

    static TextBlock Wrap(string t, double width, Color? color = null) =>
        new() { Text = t, FontFamily = Font, FontSize = 11, Foreground = new SolidColorBrush(color ?? Text), TextWrapping = TextWrapping.Wrap, Width = width };

    void Place(UIElement e, double x, double y) { Canvas.SetLeft(e, x); Canvas.SetTop(e, y); page.Children.Add(e); }

    void ShowOverlay(FrameworkElement panel) {
        overlay.Children.Clear();
        panel.HorizontalAlignment = HorizontalAlignment.Center; panel.VerticalAlignment = VerticalAlignment.Center;
        overlay.Children.Add(panel);
        overlay.Visibility = Visibility.Visible;
    }

    void HideOverlay() { overlay.Children.Clear(); overlay.Visibility = Visibility.Collapsed; }

    static Color C(byte r, byte g, byte b, byte a = 255) => Color.FromArgb(a, r, g, b);
    static Color Rgb(int rgb) => C((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    // ================= Win32 =================
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern nint SendMessage(nint hwnd, int msg, int wParam, int lParam);
    [DllImport("user32.dll")] static extern uint GetDoubleClickTime();
    [DllImport("user32.dll")] static extern bool SetDoubleClickTime(uint ms);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] static extern bool SystemParametersInfo(uint action, uint param, ref int value, uint ini);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] static extern bool SystemParametersInfoPtr(uint action, int param, nint value, uint ini);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] static extern bool SystemParametersInfoArray(uint action, uint param, int[] value, uint ini);
}
