using ThreeE.PhoneBar.Windows;
using ThreeE.CarView;
using ThreeE.Brand;
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Win32;
using ThreeFingerDragOnWindows.utils;

namespace ThreeFingerDragOnWindows;

// The drag engine and the hub share this process and its single notification icon.
public sealed class WindowsHub : IDisposable {
    public const string Version = "3.0.167.7";
    private const string ReleasesUrl = "https://api.github.com/repos/Ezodis/3E/releases";
    private readonly string root = AppContext.BaseDirectory;
    private readonly string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows");
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly MenuFlyout menu;
    private readonly PhoneBarModule phoneBar = new();
    private readonly CarViewWindows carView=new();
    private readonly MacKeyboardLayout macKeyboard = MacKeyboardLayout.Create();
    private HubSettings settings;
    private bool busy, disposed, keyboardRefreshRequested;
    private int lastTheme = -1;
    private DateTime nextRecovery = DateTime.MinValue;
    private DateTime lastTick = DateTime.Now;
    // Windows silently removes a low-level hook that answers too slowly, and the
    // engine process keeps running without it. Reinstall periodically while idle.
    private const int KeyboardRefreshMinutes = 5, KeyboardRefreshIdleSeconds = 15;
    private DateTime lastKeyboardRefresh = DateTime.Now;
    private KeyboardHookWatch hookWatch;
    private string updateTag;
    private int ssmsThemeProfiles;
    private string ssmsRotationPeriod;
    private static readonly HttpClient http = CreateHttpClient();
    // The suffix identifies the shared accessory artwork; native menu rows
    // reserve and paint that column as part of their normal draw operation.
    private bool accessoryInvoked;
    private const string IconSlot = "\t\u2003\u2003";
    private const string RotateSlot = IconSlot + "\u200B";
    private const string MirrorSlot = IconSlot + "\u200C";
    private const string MirrorGlyph = "mirror";
    private const string SettingsGlyph = "settings";
    private const string RotateGlyph = "rotate";
    public sealed class HubSettings {
        public bool Keyboard { get; set; } = true;
        public bool PowerToys { get; set; } = true;
        public bool MacKeyboard { get; set; } = false;
        public bool AutoDark { get; set; } = true;
        public bool SsmsTheme { get; set; } = true;
        public bool Wallpaper { get; set; } = true;
        public DateTime LastUpdateCheckUtc { get; set; }
        // Track Phone keeps one saved link and stays reachable unless stopped from the menu.
        public bool PhoneBarAlwaysOn { get; set; } = true;
        // New releases install by themselves when the computer is idle.
        public bool AutoUpdate { get; set; } = true;
        public string AutoUpdateTag { get; set; }
        public int AutoUpdateAttempts { get; set; }
    }

    public WindowsHub(MenuFlyout menu) {
        this.menu = menu;
        carView.Changed+=RefreshMenu;
        Directory.CreateDirectory(data);
        try { settings = JsonSerializer.Deserialize<HubSettings>(File.ReadAllText(Path.Combine(data, "settings.json"))) ?? new(); }
        catch { settings = new(); }
        menu.Opening += (_, _) => RefreshMenu();
        RefreshMenu();
        timer.Tick += (_, _) => Tick();
        SystemEvents.SessionSwitch += OnSessionSwitch;
        // Must hook before StartAsync launches the engine; see KeyboardHookWatch.
        try { hookWatch = new KeyboardHookWatch(Path.Combine(root, "MacKeyboard.json"), OnKeyboardHookLost); } catch (Exception ex) { Log(ex); }
        timer.Start();
        _ = StartAsync();
    }

    private static HttpClient CreateHttpClient() {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("3EWindows/" + Version);
        return client;
    }

    private void Save() {
        var path = Path.Combine(data, "settings.json");
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(path + ".tmp", path, true);
    }

    private void Log(Exception ex) {
        try { File.AppendAllText(Path.Combine(data, "hub.log"), DateTime.Now.ToString("s") + " " + ex.Message + Environment.NewLine); } catch { }
    }

    private async Task StartAsync() {
        try {
            // Recover a lease left by an interrupted update before honoring OFF.
            if (!settings.MacKeyboard) await macKeyboard.DisableAsync();
            ConfigureHiddenIcons(); await EnsureComponentsAsync(); ApplyTheme(); KeepPhoneBar(); WriteDiagnostics();
        }
        catch (Exception ex) { Log(ex); }
        if ((DateTime.UtcNow - settings.LastUpdateCheckUtc).TotalMinutes >= UpdateCheckMinutes) await CheckUpdatesAsync(false);
    }

    private static bool IsRunning(string name) {
        var processes = Process.GetProcessesByName(name);
        foreach (var process in processes) process.Dispose();
        return processes.Length > 0;
    }

    private static void Stop(string name) {
        foreach (var process in Process.GetProcessesByName(name)) {
            using (process) { try { process.Kill(); process.WaitForExit(4000); } catch { } }
        }
    }

    private static void Start(string path, string arguments = "", bool shell = false) {
        if (!File.Exists(path)) return;
        Process.Start(new ProcessStartInfo(path, arguments) {
            WorkingDirectory = Path.GetDirectoryName(path), UseShellExecute = shell,
            CreateNoWindow = !shell, WindowStyle = shell ? ProcessWindowStyle.Normal : ProcessWindowStyle.Hidden
        })?.Dispose();
    }

    private string PowerToysPath => MacKeyboardLayout.PowerToysPath;
    private static void StopKeyboard() { Stop("3EWindows.Keyboard"); Stop("ClicksAccents"); }

    private string KeyboardPath => Path.Combine(root, "Keyboard", "3EWindows.Keyboard.exe");
    private string WallpaperPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "WinDynamicDesktop", "WinDynamicDesktop.exe");

    private static void EditJson(string path, Action<JsonObject> edit) {
        if (!File.Exists(path)) return;
        var json = JsonNode.Parse(File.ReadAllText(path))?.AsObject();
        if (json == null) return;
        edit(json);
        File.WriteAllText(path + ".3e.tmp", json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(path + ".3e.tmp", path, true);
    }

    private void ConfigureHiddenIcons() {
        EditJson(Path.Combine(Path.GetDirectoryName(WallpaperPath), "settings.json"), json => json["hideTrayIcon"] = true);
    }

    private async Task EnsureComponentsAsync() {
        if (disposed) return;
        UpdateSsmsTheme();
        if (settings.PowerToys) {
            if (!IsRunning("PowerToys")) Start(PowerToysPath);
        }
        if (disposed) return;
        if (settings.MacKeyboard && !keyboardChanging) {
            try { await macKeyboard.EnsureAsync(); } catch (Exception ex) { Log(ex); }
        }
        if (disposed) return;
        if (settings.Keyboard && File.Exists(Path.Combine(root, "Keyboard", "3EWindows.kbd")) && !IsRunning("3EWindows.Keyboard"))
            Start(KeyboardPath, "--cfg \"" + Path.Combine(root, "Keyboard", "3EWindows.kbd") + "\"");
        if (settings.Wallpaper && !IsRunning("WinDynamicDesktop")) Start(WallpaperPath);
    }

    private async void Tick() {
        if (busy || disposed) return;
        busy = true;
        try {
            var now = DateTime.Now;
            bool staleHook = (settings.MacKeyboard || settings.Keyboard) && !keyboardChanging &&
                (now - lastKeyboardRefresh).TotalMinutes >= KeyboardRefreshMinutes && IdleSeconds() >= KeyboardRefreshIdleSeconds;
            if ((now - lastTick).TotalSeconds > 90 || keyboardRefreshRequested || staleHook) {
                keyboardRefreshRequested = false;
                lastKeyboardRefresh = now;
                StopKeyboard();
                if (settings.MacKeyboard && !keyboardChanging) {
                    keyboardChanging = true;
                    try { await macKeyboard.EnableAsync(); }
                    finally { keyboardChanging = false; }
                }
                nextRecovery = DateTime.MinValue;
                lastTheme = -1;
            }
            lastTick = now;
            ApplyTheme();
            KeepPhoneBar();
            if (now >= nextRecovery) {
                await EnsureComponentsAsync();
                nextRecovery = now.AddSeconds(60);
            }
            if ((DateTime.UtcNow - settings.LastUpdateCheckUtc).TotalMinutes >= UpdateCheckMinutes) await CheckUpdatesAsync(false);
            await InstallPendingUpdateAsync();
        } catch (Exception ex) { Log(ex); }
        finally { busy = false; WriteDiagnostics(); }
    }

    private void OnKeyboardHookLost() {
        App.Instance.DispatcherQueue.TryEnqueue(() => {
            if (disposed || !settings.MacKeyboard) return;
            keyboardRefreshRequested = true;
            Tick();
        });
    }

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e) {
        if (e.Reason is not (SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)) return;
        // A surviving process does not prove its low-level input hook survived a
        // desktop/session change. Reinstall it on return to the user's desktop.
        App.Instance.DispatcherQueue.TryEnqueue(() => {
            if (disposed) return;
            keyboardRefreshRequested = true;
            Tick();
        });
    }

    private void WriteDiagnostics() {
        try {
            var handler = App.Instance.HandlerWindow;
            File.WriteAllText(Path.Combine(data, "status.json"), JsonSerializer.Serialize(new {
                version = Version, timestampUtc = DateTime.UtcNow,
                trayIconForeground = handler.TrayIconForeground,
                trayLeftClick = "Track Phone QR popup", trayRightClick = "all controls and Track Phone QR",
                ssmsThemeSync = settings.SsmsTheme, ssmsThemeProfiles,
                ssmsThemes = SsmsTheme.CurrentThemeNames,
                touchpadDetected = handler.TouchpadExists, inputReceiverInstalled = handler.InputReceiverInstalled,
                threeFingerDrag = DragDiagnostics.Snapshot(),
                keyboardInstalled = File.Exists(KeyboardPath), keyboardRunning = IsRunning("3EWindows.Keyboard"),
                macKeyboardEnabled = settings.MacKeyboard, macKeyboardRunning = macKeyboard.Active,
                powerToysRunning = IsRunning("PowerToys"), shortcutsRunning = IsRunning("PowerToys.KeyboardManagerEngine"),
                wallpaperRunning = IsRunning("WinDynamicDesktop"), autoDark = settings.AutoDark,
                phoneTrackpadRunning = phoneBar.Running, phoneTrackpadStatus = phoneBar.Status,
                phoneBarNetworkAllowed = phoneBar.NetworkAllowed,
                menu = menu.Items.Select(item => item switch {
                    ToggleMenuFlyoutItem toggle => toggle.Text,
                    MenuFlyoutItem command => command.Text,
                    _ => "—"
                }).ToArray()
            }, new JsonSerializerOptions { WriteIndented = true }));
        } catch (Exception ex) { Log(ex); }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int MessageBox(IntPtr window, string text, string caption, uint type);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);

    public static int ScheduledTheme(DateTime localTime) => localTime.Hour >= 12 && localTime.Hour < 20 ? 1 : 0;

    private void ApplyTheme() {
        if (!settings.AutoDark) return;
        var theme = ScheduledTheme(DateTime.Now);
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        if (lastTheme == theme && Equals(key.GetValue("AppsUseLightTheme"), theme) && Equals(key.GetValue("SystemUsesLightTheme"), theme)) return;
        SetTheme(theme);
    }

    private void SetTheme(int theme) {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        key.SetValue("AppsUseLightTheme", theme, RegistryValueKind.DWord);
        key.SetValue("SystemUsesLightTheme", theme, RegistryValueKind.DWord);
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, "ImmersiveColorSet", 2, 1000, out _);
        lastTheme = theme;
        UpdateSsmsTheme();
    }

    private void UpdateSsmsTheme(bool rotate = false) {
        if (!settings.SsmsTheme) return;
        using var preferences = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        bool light = Convert.ToInt32(preferences?.GetValue("AppsUseLightTheme", ScheduledTheme(DateTime.Now))) != 0;
        string period = SsmsTheme.RotationPeriod(DateTime.Now, light);
        ssmsThemeProfiles = SsmsTheme.Configure(Log, light, rotate || period != ssmsRotationPeriod);
        ssmsRotationPeriod = period;
    }

    // Native menu selections invoke commands after the popup has closed.
    // Toggle commands own their checked state, including accessory actions.
    private sealed class MenuCommand : System.Windows.Input.ICommand {
        private readonly Action action;
        public MenuCommand(Action action) => this.action = action;
        public event EventHandler CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object parameter) => true;
        public void Execute(object parameter) => action();
    }

    private MenuFlyoutItem ActionMenuItem(string label, Action click) => new() {
        Text = label,
        Command = new MenuCommand(() => { try { click(); } catch (Exception ex) { Log(ex); MessageBox(IntPtr.Zero, ex.Message, "3£", 0x10); } })
    };

    private ToggleMenuFlyoutItem ToggleMenuItem(string label, bool value, Action<bool> change, Action openSettings = null, string slot = IconSlot) {
        // Keep accessory metadata on the row; the native painter allocates its column.
        var item = new ToggleMenuFlyoutItem { Text = openSettings == null ? label : label + slot, IsChecked = value };
        item.Command = new MenuCommand(() => {
            if (openSettings != null && ClickedGear()) {
                try { openSettings(); } catch (Exception ex) { Log(ex); MessageBox(IntPtr.Zero, ex.Message, "3£", 0x10); }
                return;
            }
            try { value = !value; item.IsChecked = value; change(value); Save(); } catch (Exception ex) { Log(ex); }
        });
        return item;
    }

    private bool ClickedGear() => accessoryInvoked;

    public static string MenuGlyph(string text) => text.EndsWith(MirrorSlot, StringComparison.Ordinal) ? MirrorGlyph : text.EndsWith(RotateSlot, StringComparison.Ordinal) ? RotateGlyph : text.EndsWith(IconSlot, StringComparison.Ordinal) ? SettingsGlyph : null;

    public void ShowControlsMenu(IntPtr owner, System.Drawing.Point point) {
        try { ShowControlsMenuCore(owner, point); }
        catch (Exception ex) { Log(ex); MessageBox(IntPtr.Zero, "Could not open the controls menu.\n\n" + ex.Message, "3£", 0x10 | ForegroundDialog); }
    }

    private void ShowControlsMenuCore(IntPtr owner, System.Drawing.Point point) {
        RefreshMenu();
        var items = menu.Items.ToArray();
        var rows = items.Select(item => {
            if (item is MenuFlyoutSeparator) return new NativeHubMenu.Row("", Separator: true);
            var command = (MenuFlyoutItem)item;
            string icon = MenuGlyph(command.Text);
            return new NativeHubMenu.Row(command.Text.Split('\t')[0], command.IsEnabled,
                command is ToggleMenuFlyoutItem toggle && toggle.IsChecked,
                icon, icon == MirrorGlyph && carView.Mirrored);
        }).ToArray();
        using var preferences = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        bool dark = Convert.ToInt32(preferences?.GetValue("AppsUseLightTheme", 1)) == 0;
        using var popup = new NativeHubMenu(rows, NativeHubMenu.DpiAt(point, owner), dark, NativeHubMenu.MaxWidthAt(point));
        var choice = popup.Show(owner, point);
        if (choice == null) return;
        var selected = (MenuFlyoutItem)items[choice.Value.Index];
        accessoryInvoked = choice.Value.Accessory;
        try { if (selected.Command?.CanExecute(selected.CommandParameter) == true) selected.Command.Execute(selected.CommandParameter); }
        finally { accessoryInvoked = false; }
    }

    private void Item(string label, Action click) => menu.Items.Add(ActionMenuItem(label, click));

    private void Toggle(string label, bool value, Action<bool> change, Action openSettings = null, string slot = IconSlot) => menu.Items.Add(ToggleMenuItem(label, value, change, openSettings, slot));

    private void OpenPowerToysSettings() {
        if (PowerToysPath == null) throw new FileNotFoundException("Run the 3£ installer to install PowerToys.");
        Start(Path.Combine(Path.GetDirectoryName(PowerToysPath), "WinUI3Apps", "PowerToys.Settings.exe"), "", true);
    }

    private bool keyboardChanging;
    private MenuFlyoutItem MacKeyboardToggle() {
        var item = new ToggleMenuFlyoutItem {
            Text = macKeyboard.HasLease && !macKeyboard.Active ? "Mac keyboard layout — recovery pending" : "Mac keyboard layout",
            IsChecked = settings.MacKeyboard || macKeyboard.HasLease, IsEnabled = !keyboardChanging
        };
        item.Command = new MenuCommand(async () => {
            if (keyboardChanging) return;
            keyboardChanging = true;
            bool enable = !item.IsChecked;
            settings.MacKeyboard = false; // Prevent recovery from racing an OFF request.
            try {
                if (enable) await macKeyboard.EnableAsync(); else await macKeyboard.DisableAsync();
                settings.MacKeyboard = enable;
            } catch (Exception ex) { Log(ex); MessageBox(IntPtr.Zero, ex.Message, "3£ keyboard", 0x10); }
            finally { keyboardChanging = false; Save(); RefreshMenu(); WriteDiagnostics(); }
        });
        return item;
    }

    public void RefreshControls() => RefreshMenu();

    // Restarts the receiver after sleep or a network change so the saved link works.
    private void KeepPhoneBar() {
        if (!phoneBar.Available) { if (phoneBar.Running) phoneBar.Stop(); return; }
        if (!settings.PhoneBarAlwaysOn || disposed) return;
        try { phoneBar.EnsureRunning(); } catch (Exception ex) { Log(ex); }
    }

    // Relaunches the installed executable once this process exits. Restart()
    // checks for an update before getting here.
    public static string RestartScript(int processId, string app) {
        static string Quote(string value) => "'" + value.Replace("'", "''") + "'";
        return "Wait-Process -Id " + processId + " -Timeout 30 -ErrorAction SilentlyContinue\n" +
            "if (Get-Process -Id " + processId + " -ErrorAction SilentlyContinue) { exit 1 }\n" +
            "Start-Process -FilePath " + Quote(app) + " -WorkingDirectory " + Quote(Path.GetDirectoryName(app)) + "\n";
    }

    // Restart always checks for an update first (bounded, so a slow or
    // offline network delays it by at most a few seconds). A newer release is
    // installed and its installer restarts the whole suite; otherwise, or if
    // the check/install fails, the suite restarts as is.
    public static readonly TimeSpan RestartUpdateCheckLimit = TimeSpan.FromSeconds(8);
    private bool restarting;
    private async void Restart() {
        if (restarting || installingUpdate) return;
        restarting = true;
        try {
            var check = phoneBar.NetworkAllowed ? CheckUpdatesAsync(false) : Task.FromResult<JsonElement?>(null);
            var newest = await Task.WhenAny(check, Task.Delay(RestartUpdateCheckLimit)) == check ? await check : null;
            if (newest != null) {
                installingUpdate = true;
                try { await InstallUpdateAsync(newest.Value); return; }
                catch (Exception ex) { Log(ex); installingUpdate = false; }
            }
        } catch (Exception ex) { Log(ex); }
        try { RestartSuite(); }
        catch (Exception ex) { restarting = false; Log(ex); MessageBox(IntPtr.Zero, ex.Message, "3£", 0x10 | ForegroundDialog); }
    }

    private void RestartSuite() {
        Save();
        string script = RestartScript(Environment.ProcessId, Environment.ProcessPath);
        string encoded = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(script));
        Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand " + encoded) {
            UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = root
        })?.Dispose();
        App.Instance.Quit();
    }

    private void NewPhoneLink() {
        if (ShowPhoneNetworkRestriction()) return;
        if (MessageBox(IntPtr.Zero, "Make a new Track Phone link?\n\nThe current link stops working. Scan the new QR code on your iPhone (and email it to your Watch) afterwards.", "3£ Track Phone", 0x24 | ForegroundDialog) != 6) return;
        phoneBar.ResetLink();
        OpenPhoneTrackpad();
    }

    public void OpenPhoneTrackpad() {
        try {
            if (ShowPhoneNetworkRestriction()) return;
            if (!settings.PhoneBarAlwaysOn) { settings.PhoneBarAlwaysOn = true; Save(); }
            phoneBar.Show();
            WriteDiagnostics();
        } catch (Exception ex) { Log(ex); }
    }

    private bool ShowPhoneNetworkRestriction() {
        if (phoneBar.Available) return false;
        phoneBar.Stop();
        MessageBox(IntPtr.Zero, PhoneBarNetworkPolicy.RestrictedStatus + "\n\nPhone control requires an incoming connection to this computer. Ask IT to approve a connection method before enabling it. Other 3£ controls remain available.", "3£ Track Phone", 0x40 | ForegroundDialog);
        return true;
    }

    private void RefreshMenu() {
        menu.Items.Clear();
        menu.Items.Add(new MenuFlyoutItem { Text = "3£ " + Version, IsEnabled = false });
        // One Track Phone row: click to turn it on or off; its icon makes a new link.
        // Left-clicking the tray icon shows the QR.
        Toggle(phoneBar.NetworkAllowed ? "Track Phone" : phoneBar.UsbOnly ? "Track Phone — USB cable only" : "Track Phone — network restricted", phoneBar.Running, enabled => {
            if (ShowPhoneNetworkRestriction()) return;
            settings.PhoneBarAlwaysOn = enabled;
            if (enabled) phoneBar.EnsureRunning(); else phoneBar.Stop();
        }, NewPhoneLink);
        Toggle("Car View",carView.Enabled,enabled=>carView.SetEnabled(enabled),()=>carView.ToggleMirror(),MirrorSlot);
        Toggle("Three-finger drag", App.SettingsData.ThreeFingerDrag, enabled => { App.SettingsData.ThreeFingerDrag = enabled; App.SettingsData.save(); },
            () => App.Instance.OpenSettingsWindow());
        // The check mark means the keyboard engine is running; clicking an unchecked row starts it.
        Toggle(File.Exists(KeyboardPath) ? "Clicks keyboard" : "Clicks keyboard — connect and run setup", settings.Keyboard && IsRunning("3EWindows.Keyboard"), enabled => {
            settings.Keyboard = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else StopKeyboard();
        });
        menu.Items.Add(MacKeyboardToggle());
        Toggle("PowerToys", settings.PowerToys, enabled => {
            settings.PowerToys = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else { Stop("PowerToys"); if (settings.MacKeyboard) _ = macKeyboard.EnsureAsync(); }
        }, OpenPowerToysSettings);
        menu.Items.Add(new MenuFlyoutSeparator());
        Toggle("Dynamic wallpaper", settings.Wallpaper, enabled => {
            settings.Wallpaper = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else Stop("WinDynamicDesktop");
        }, () => Start(WallpaperPath, "", true));
        Toggle("Auto dark — light 12 PM–8 PM", settings.AutoDark, enabled => { settings.AutoDark = enabled; lastTheme = -1; ApplyTheme(); });
        // SSMS and the code editors rotate together; the repeat icon rotates now.
        Toggle("Rotate themes", settings.SsmsTheme, enabled => { settings.SsmsTheme = enabled; if (enabled) UpdateSsmsTheme(true); },
            () => { settings.SsmsTheme = true; UpdateSsmsTheme(true); Save(); }, RotateSlot);
        Item("Use light theme", () => { settings.AutoDark = false; Save(); SetTheme(1); });
        Item("Use dark theme", () => { settings.AutoDark = false; Save(); SetTheme(0); });
        menu.Items.Add(new MenuFlyoutSeparator());
        Item("Restart", Restart);
        // Automatic updates make a manual check redundant; it returns only when they are off.
        if (!settings.AutoUpdate) Item(updateTag == null ? "Check for updates…" : "Update available: " + updateTag + "…", () => _ = CheckUpdatesAsync(true));
        if (phoneBar.NetworkAllowed)
            Toggle("Install updates automatically", settings.AutoUpdate, enabled => { settings.AutoUpdate = enabled; if (!enabled) pendingUpdate = null; else settings.LastUpdateCheckUtc = default; });
        else menu.Items.Add(new MenuFlyoutItem { Text = "Updates require IT review", IsEnabled = false });
        Item("Open portable installer", () => Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + Path.Combine(root, "3£Windows.ps1") + "\"") { UseShellExecute = true }));
        Item("Quit 3£", () => App.Instance.Quit());
    }

    public MenuFlyout CreateLauncher(Action showAllControls) {
        var launcher = new MenuFlyout();
        launcher.Items.Add(new MenuFlyoutItem { Text = "3£ — choose controls", IsEnabled = false });
        MenuFlyoutItem ActionItem(string text, Action action) => ActionMenuItem(text, action);
        ToggleMenuFlyoutItem Switch(string text, bool value, Action<bool> change) => ToggleMenuItem(text, value, change);
        void OpenPowerToys() => OpenPowerToysSettings();
        launcher.Items.Add(ActionItem("Drag settings…", () => App.Instance.OpenSettingsWindow()));
        launcher.Items.Add(ActionItem("Track Phone…", OpenPhoneTrackpad));
        launcher.Items.Add(ActionItem("PowerToys settings…", OpenPowerToys));
        var keyboard = new MenuFlyoutSubItem { Text = "Keyboard controls" };
        keyboard.Items.Add(MacKeyboardToggle());
        keyboard.Items.Add(Switch("Enable Clicks keyboard mapping", settings.Keyboard, enabled => {
            settings.Keyboard = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else StopKeyboard();
        }));
        keyboard.Items.Add(ActionItem("Keyboard shortcuts…", OpenPowerToys));
        launcher.Items.Add(keyboard);
        var themes = new MenuFlyoutSubItem { Text = "Theme controls" };
        themes.Items.Add(Switch("Auto light/dark schedule", settings.AutoDark, enabled => { settings.AutoDark = enabled; lastTheme = -1; ApplyTheme(); }));
        themes.Items.Add(ActionItem("Use light theme", () => { settings.AutoDark = false; Save(); SetTheme(1); }));
        themes.Items.Add(ActionItem("Use dark theme", () => { settings.AutoDark = false; Save(); SetTheme(0); }));
        themes.Items.Add(Switch("Rotate themes", settings.SsmsTheme, enabled => { settings.SsmsTheme = enabled; if (enabled) UpdateSsmsTheme(true); }));
        themes.Items.Add(ActionItem("Rotate themes now", () => { settings.SsmsTheme = true; UpdateSsmsTheme(true); Save(); }));
        launcher.Items.Add(themes);
        launcher.Items.Add(ActionItem("Wallpaper controls…", () => Start(WallpaperPath, "", true)));
        launcher.Items.Add(new MenuFlyoutSeparator());
        launcher.Items.Add(ActionItem("All controls…", showAllControls));
        return launcher;
    }

    // Windows has its own release prefix; /latest could select a macOS release.
    public static Version WindowsReleaseVersion(string tag) => tag?.StartsWith("windows-v", StringComparison.Ordinal) == true && System.Version.TryParse(tag[9..], out var version) ? version : null;

    // MB_SETFOREGROUND | MB_TOPMOST: a tray app's dialogs must not open behind other windows.
    private const uint ForegroundDialog = 0x10000 | 0x40000;
    // Returns the newest newer Windows release, or null when up to date or offline.
    public async Task<JsonElement?> CheckUpdatesAsync(bool interactive) {
        // Older public installers recreate unrestricted firewall rules and
        // logon tasks. A restricted deployment must be updated by its owner
        // after the installer has been reviewed, including on Restart.
        if (!phoneBar.NetworkAllowed) {
            pendingUpdate = null;
            if (interactive) MessageBox(IntPtr.Zero, "This computer uses a restricted 3£ installation. Ask IT to review an update before installing it; the public installer may enable incoming connections and startup tasks.", "3£ updates", 0x40 | ForegroundDialog);
            return null;
        }
        try {
            JsonElement? newest = null;
            var newestVersion = System.Version.Parse(Version);
            for (var page = 1; page <= 10; page++) {
                using var releases = JsonDocument.Parse(await http.GetStringAsync(ReleasesUrl + "?per_page=100&page=" + page));
                var count = 0;
                foreach (var release in releases.RootElement.EnumerateArray()) {
                    count++;
                    if (release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean()) continue;
                    var version = WindowsReleaseVersion(release.GetProperty("tag_name").GetString());
                    if (version != null && version > newestVersion) { newest = release.Clone(); newestVersion = version; }
                }
                if (count < 100) break;
            }
            settings.LastUpdateCheckUtc = DateTime.UtcNow;
            Save();
            updateTag = newest?.GetProperty("tag_name").GetString();
            pendingUpdate = settings.AutoUpdate && newest != null ? newest.Value.Clone() : null;
            if (!interactive) { RefreshMenu(); return newest; }
            if (newest == null) { MessageBox(IntPtr.Zero, "3£ " + Version + " is up to date.", "3£", 0x40 | ForegroundDialog); return null; }
            if (MessageBox(IntPtr.Zero, "Install 3£ " + newestVersion + "?\n\nThe portable installer will be downloaded, its SHA-256 checksum verified, and Windows will request administrator approval.", "3£ update", 0x24 | ForegroundDialog) != 6) return newest;
            await InstallUpdateAsync(newest.Value);
            return newest;
        } catch (Exception ex) {
            Log(ex);
            // Throttle failures too, so an offline device never polls every 20 seconds.
            settings.LastUpdateCheckUtc = DateTime.UtcNow;
            Save();
            if (interactive) MessageBox(IntPtr.Zero, "Could not check or install the update.\n\n" + ex.Message, "3£", 0x10 | ForegroundDialog);
            return null;
        }
    }

    private static string AssetUrl(JsonElement release, string name) {
        foreach (var asset in release.GetProperty("assets").EnumerateArray()) {
            if (asset.GetProperty("name").GetString() != name) continue;
            var url = asset.GetProperty("browser_download_url").GetString();
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Host != "github.com" || !uri.AbsolutePath.StartsWith("/Ezodis/3E/releases/download/", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Unexpected release download URL.");
            return url;
        }
        throw new InvalidDataException("The release is missing " + name + ".");
    }

    // Automatic updates: check every few minutes; install the newest release
    // once the computer has been idle briefly, so nothing restarts mid-use.
    // The app already runs elevated, so the verified installer runs without a
    // prompt. A release that fails to install twice is left for a manual update.
    private const int UpdateCheckMinutes = 10, UpdateIdleSeconds = 90, UpdateMaxAttempts = 2;
    private JsonElement? pendingUpdate;
    private bool installingUpdate;
    [StructLayout(LayoutKind.Sequential)] private struct LastInput { public uint Size, Time; }
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInput info);
    private static double IdleSeconds() {
        var info = new LastInput { Size = (uint)Marshal.SizeOf<LastInput>() };
        return GetLastInputInfo(ref info) ? unchecked((uint)Environment.TickCount - info.Time) / 1000.0 : 0;
    }
    // Permission policy: Windows asks once, when 3£Windows is installed. That
    // install retains the "3£Windows" logon task with highest privileges, so
    // starting the suite through it gives administrator rights with no prompt.
    // A copy that somehow started without them (an update, a manual launch)
    // hands over to that task instead of asking again. The time guard keeps a
    // misconfigured task from relaunching in a loop.
    public static bool StartElevatedWithoutPrompt(string marker, Func<string, string, int> run = null) {
        try {
            if (File.Exists(marker) && DateTime.UtcNow - File.GetLastWriteTimeUtc(marker) < TimeSpan.FromMinutes(2)) return false;
            Directory.CreateDirectory(Path.GetDirectoryName(marker));
            File.WriteAllText(marker, DateTime.UtcNow.ToString("O"));
            run ??= (file, arguments) => {
                using var process = Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = false, CreateNoWindow = true });
                return process != null && process.WaitForExit(10000) ? process.ExitCode : -1;
            };
            return run(Path.Combine(Environment.SystemDirectory, "schtasks.exe"), "/Run /TN \"3£Windows\"") == 0;
        } catch { return false; }
    }
    public static string ElevationMarker => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "elevation-handoff");
    // Updates without administrator rights ask at most once per release.
    public static int UpdateAttemptsAllowed(bool elevated) => elevated ? UpdateMaxAttempts : 1;
    private static bool Elevated() {
        using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        return new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    }
    private async Task InstallPendingUpdateAsync() {
        // New releases install as soon as they are found, even while the PC is in use.
        if (installingUpdate || pendingUpdate == null || !settings.AutoUpdate) return;
        var release = pendingUpdate.Value;
        var tag = release.GetProperty("tag_name").GetString();
        if (settings.AutoUpdateTag == tag && settings.AutoUpdateAttempts >= UpdateAttemptsAllowed(Elevated())) return;
        installingUpdate = true;
        try {
            settings.AutoUpdateAttempts = settings.AutoUpdateTag == tag ? settings.AutoUpdateAttempts + 1 : 1;
            settings.AutoUpdateTag = tag;
            Save();
            await InstallUpdateAsync(release, silent: true);
        } catch (Exception ex) { Log(ex); installingUpdate = false; }
    }

    private async Task InstallUpdateAsync(JsonElement release, bool silent = false) {
        const string name = "3£Windows.ps1";
        var contents = await ReadVerifiedInstallerAsync(release);
        var folder = Path.Combine(data, "Updates", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var installer = Path.Combine(folder, name);
        await File.WriteAllBytesAsync(installer, contents);
        if (Elevated()) {
            // Inherits this process's administrator token: no prompt, no window.
            Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + installer + "\" -AppOnly") { UseShellExecute = false, CreateNoWindow = true })?.Dispose();
            return;
        }
        // Only reached without administrator rights: installing into Program
        // Files requires them, so this is the one case that asks.
        Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\" -AppOnly") { UseShellExecute = true, Verb = "runas" })?.Dispose();
    }

    private static async Task<byte[]> ReadVerifiedInstallerAsync(JsonElement release) {
        const string name = "3£Windows.ps1";
        const string assetName = "3EWindows.zip";
        var sums = await http.GetStringAsync(AssetUrl(release, "SHA256SUMS.txt"));
        var checksum = sums.Split('\n').Select(line => line.Trim().Split(new[] { ' ', '\t' }, 2, StringSplitOptions.RemoveEmptyEntries))
            .FirstOrDefault(parts => parts.Length == 2 && parts[1].TrimStart('*', ' ') == assetName)?[0];
        if (checksum == null || checksum.Length != 64 || !checksum.All(Uri.IsHexDigit)) throw new InvalidDataException("Installer checksum is missing or invalid.");
        var bytes = await http.GetByteArrayAsync(AssetUrl(release, assetName));
        if (!Convert.ToHexString(SHA256.HashData(bytes)).Equals(checksum, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Installer checksum verification failed.");
        using (var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read)) {
            var entry = archive.GetEntry(name);
            if (archive.Entries.Count != 1 || entry == null || entry.Length > 128 * 1024 * 1024) throw new InvalidDataException("Invalid portable installer archive.");
            using var contents = entry.Open();
            using var output = new MemoryStream();
            await contents.CopyToAsync(output);
            return output.ToArray();
        }
    }

    // Read-only release validation uses exactly the download path used by updates.
    public static async Task VerifyReleaseAsync(string metadataPath, string reportPath) {
        using var release = JsonDocument.Parse(await File.ReadAllTextAsync(metadataPath));
        var tag = release.RootElement.GetProperty("tag_name").GetString();
        if (WindowsReleaseVersion(tag) == null) throw new InvalidDataException("Not a Windows release.");
        var installer = await ReadVerifiedInstallerAsync(release.RootElement);
        await File.WriteAllTextAsync(reportPath, JsonSerializer.Serialize(new {
            passed = true, tag, installerName = "3£Windows.ps1", bytes = installer.Length,
            sha256 = Convert.ToHexString(SHA256.HashData(installer)).ToLowerInvariant()
        }));
    }

    public void Dispose() {
        disposed = true;
        timer.Stop();
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        hookWatch?.Dispose();
        phoneBar.Dispose();
        carView.Changed-=RefreshMenu;carView.Dispose();
        Save();
        try { macKeyboard.DisableAsync().GetAwaiter().GetResult(); } catch (Exception ex) { Log(ex); }
        StopKeyboard(); Stop("WinDynamicDesktop");
    }
}
