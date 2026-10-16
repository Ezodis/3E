using ThreeE.PhoneBar.Windows;
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
    public const string Version = "1.0.19";
    private const string ReleasesUrl = "https://api.github.com/repos/Ezodis/3E/releases";
    private readonly string root = AppContext.BaseDirectory;
    private readonly string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows");
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly MenuFlyout menu;
    private readonly PhoneBarModule phoneBar = new();
    private HubSettings settings;
    private bool busy, disposed;
    private int lastTheme = -1;
    private DateTime nextRecovery = DateTime.MinValue;
    private DateTime lastTick = DateTime.Now;
    private string updateTag;
    private int ssmsThemeProfiles;
    private string ssmsRotationPeriod;
    private static readonly HttpClient http = CreateHttpClient();

    public sealed class HubSettings {
        public bool Keyboard { get; set; } = true;
        public bool PowerToys { get; set; } = true;
        public bool AutoDark { get; set; } = true;
        public bool SsmsTheme { get; set; } = true;
        public bool Wallpaper { get; set; } = true;
        public DateTime LastUpdateCheckUtc { get; set; }
        // Phone Bar keeps one saved link and stays reachable unless stopped from the menu.
        public bool PhoneBarAlwaysOn { get; set; } = true;
    }

    public WindowsHub(MenuFlyout menu) {
        this.menu = menu;
        Directory.CreateDirectory(data);
        try { settings = JsonSerializer.Deserialize<HubSettings>(File.ReadAllText(Path.Combine(data, "settings.json"))) ?? new(); }
        catch { settings = new(); }
        menu.Opening += (_, _) => RefreshMenu();
        RefreshMenu();
        timer.Tick += (_, _) => Tick();
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
        try { ConfigureHiddenIcons(); await EnsureComponentsAsync(); ApplyTheme(); KeepPhoneBar(); WriteDiagnostics(); }
        catch (Exception ex) { Log(ex); }
        if ((DateTime.UtcNow - settings.LastUpdateCheckUtc).TotalHours >= 24) await CheckUpdatesAsync(false);
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

    private string PowerToysPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PowerToys", "PowerToys.exe");
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
        var powerToysSettings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "PowerToys", "settings.json");
        EditJson(powerToysSettings, json => {
            json["show_tray_icon"] = false;
            json["startup"] = false;
            json["run_elevated"] = false;
            if (json["enabled"] is JsonObject enabled) enabled["LightSwitch"] = false;
        });
        EditJson(Path.Combine(Path.GetDirectoryName(WallpaperPath), "settings.json"), json => json["hideTrayIcon"] = true);
    }

    private async Task EnsureComponentsAsync() {
        if (disposed) return;
        UpdateSsmsTheme();
        if (settings.PowerToys) {
            if (!IsRunning("PowerToys")) Start(PowerToysPath);
            await Task.Delay(1500);
            if (!disposed && settings.PowerToys && !IsRunning("PowerToys.KeyboardManagerEngine"))
                Start(Path.Combine(Path.GetDirectoryName(PowerToysPath), "KeyboardManagerEngine", "PowerToys.KeyboardManagerEngine.exe"));
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
            if ((now - lastTick).TotalSeconds > 90) {
                StopKeyboard(); Stop("PowerToys.KeyboardManagerEngine");
                lastTheme = -1;
            }
            lastTick = now;
            ApplyTheme();
            KeepPhoneBar();
            if (now >= nextRecovery) {
                await EnsureComponentsAsync();
                nextRecovery = now.AddSeconds(60);
            }
            if ((DateTime.UtcNow - settings.LastUpdateCheckUtc).TotalHours >= 24) await CheckUpdatesAsync(false);
        } catch (Exception ex) { Log(ex); }
        finally { busy = false; WriteDiagnostics(); }
    }

    private void WriteDiagnostics() {
        try {
            var handler = App.Instance.HandlerWindow;
            File.WriteAllText(Path.Combine(data, "status.json"), JsonSerializer.Serialize(new {
                version = Version, timestampUtc = DateTime.UtcNow,
                trayIconForeground = handler.TrayIconForeground,
                trayLeftClick = "Phone Bar QR popup", trayRightClick = "all controls and Phone Bar QR",
                ssmsThemeSync = settings.SsmsTheme, ssmsThemeProfiles,
                ssmsThemes = SsmsTheme.CurrentThemeNames,
                touchpadDetected = handler.TouchpadExists, inputReceiverInstalled = handler.InputReceiverInstalled,
                keyboardInstalled = File.Exists(KeyboardPath), keyboardRunning = IsRunning("3EWindows.Keyboard"),
                powerToysRunning = IsRunning("PowerToys"), shortcutsRunning = IsRunning("PowerToys.KeyboardManagerEngine"),
                wallpaperRunning = IsRunning("WinDynamicDesktop"), autoDark = settings.AutoDark,
                phoneTrackpadRunning = phoneBar.Running, phoneTrackpadStatus = phoneBar.Status,
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

    // The tray shows these flyouts in H.NotifyIcon's default PopupMenu mode,
    // which runs each item's Command and never raises Click. Items therefore
    // use commands; toggles flip their own state because the native popup
    // does not update IsChecked.
    private sealed class MenuCommand : System.Windows.Input.ICommand {
        private readonly Action action;
        public MenuCommand(Action action) => this.action = action;
        public event EventHandler CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object parameter) => true;
        public void Execute(object parameter) => action();
    }

    private MenuFlyoutItem ActionMenuItem(string label, Action click) => new() {
        Text = label,
        Command = new MenuCommand(() => { try { click(); } catch (Exception ex) { Log(ex); MessageBox(IntPtr.Zero, ex.Message, "3£Windows", 0x10); } })
    };

    private ToggleMenuFlyoutItem ToggleMenuItem(string label, bool value, Action<bool> change) {
        var item = new ToggleMenuFlyoutItem { Text = label, IsChecked = value };
        item.Command = new MenuCommand(() => {
            try { value = !value; item.IsChecked = value; change(value); Save(); } catch (Exception ex) { Log(ex); }
        });
        return item;
    }

    private void Item(string label, Action click) => menu.Items.Add(ActionMenuItem(label, click));

    private void Toggle(string label, bool value, Action<bool> change) => menu.Items.Add(ToggleMenuItem(label, value, change));

    public void RefreshControls() => RefreshMenu();

    // Restarts the receiver after sleep or a network change so the saved link works.
    private void KeepPhoneBar() {
        if (!settings.PhoneBarAlwaysOn || disposed) return;
        try { phoneBar.EnsureRunning(); } catch (Exception ex) { Log(ex); }
    }

    public void OpenPhoneTrackpad() {
        try {
            if (!settings.PhoneBarAlwaysOn) { settings.PhoneBarAlwaysOn = true; Save(); }
            phoneBar.Show();
            WriteDiagnostics();
        } catch (Exception ex) { Log(ex); }
    }

    private void RefreshMenu() {
        menu.Items.Clear();
        menu.Items.Add(new MenuFlyoutItem { Text = "3£Windows " + Version, IsEnabled = false });
        Toggle("Three-finger drag", App.SettingsData.ThreeFingerDrag, enabled => { App.SettingsData.ThreeFingerDrag = enabled; App.SettingsData.save(); });
        Item("Drag settings…", () => App.Instance.OpenSettingsWindow());
        Item("3£ Phone Bar — show QR…", OpenPhoneTrackpad);
        if (phoneBar.Running) Item("Stop Phone Bar", () => { settings.PhoneBarAlwaysOn = false; Save(); phoneBar.Stop(); });
        Item("Phone Bar — new link (old one stops working)", () => { phoneBar.ResetLink(); OpenPhoneTrackpad(); });
        Toggle(File.Exists(KeyboardPath) ? "Clicks keyboard — " + (IsRunning("3EWindows.Keyboard") ? "running" : "stopped") : "Clicks keyboard — connect and run setup", settings.Keyboard, enabled => {
            settings.Keyboard = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else StopKeyboard();
        });
        Toggle("PowerToys shortcuts and Workspaces", settings.PowerToys, enabled => {
            settings.PowerToys = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else { Stop("PowerToys"); Stop("PowerToys.KeyboardManagerEngine"); }
        });
        Item("PowerToys settings…", () => {
            Start(Path.Combine(Path.GetDirectoryName(PowerToysPath), "WinUI3Apps", "PowerToys.Settings.exe"), "", true);
        });
        menu.Items.Add(new MenuFlyoutSeparator());
        Toggle("Auto dark — light 12 PM–8 PM", settings.AutoDark, enabled => { settings.AutoDark = enabled; lastTheme = -1; ApplyTheme(); });
        Toggle("Rotate SSMS themes", settings.SsmsTheme, enabled => { settings.SsmsTheme = enabled; if (enabled) UpdateSsmsTheme(true); });
        Item("Rotate SSMS theme now", () => { settings.SsmsTheme = true; UpdateSsmsTheme(true); Save(); });
        Item("Use light theme", () => { settings.AutoDark = false; Save(); SetTheme(1); });
        Item("Use dark theme", () => { settings.AutoDark = false; Save(); SetTheme(0); });
        Toggle("Dynamic wallpaper", settings.Wallpaper, enabled => {
            settings.Wallpaper = enabled;
            if (enabled) _ = EnsureComponentsAsync(); else Stop("WinDynamicDesktop");
        });
        Item("Show wallpaper controls…", () => Start(WallpaperPath, "", true));
        menu.Items.Add(new MenuFlyoutSeparator());
        Item("Restart input engines", () => { StopKeyboard(); Stop("PowerToys.KeyboardManagerEngine"); _ = EnsureComponentsAsync(); });
        Item(updateTag == null ? "Check for updates…" : "Update available: " + updateTag + "…", () => _ = CheckUpdatesAsync(true));
        Item("Open portable installer", () => Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + Path.Combine(root, "3£Windows.ps1") + "\"") { UseShellExecute = true }));
        Item("Quit 3£Windows", () => App.Instance.Quit());
    }

    public MenuFlyout CreateLauncher(Action showAllControls) {
        var launcher = new MenuFlyout();
        launcher.Items.Add(new MenuFlyoutItem { Text = "3£Windows — choose controls", IsEnabled = false });
        MenuFlyoutItem ActionItem(string text, Action action) => ActionMenuItem(text, action);
        ToggleMenuFlyoutItem Switch(string text, bool value, Action<bool> change) => ToggleMenuItem(text, value, change);
        void OpenPowerToys() => Start(Path.Combine(Path.GetDirectoryName(PowerToysPath), "WinUI3Apps", "PowerToys.Settings.exe"), "", true);
        launcher.Items.Add(ActionItem("Drag settings…", () => App.Instance.OpenSettingsWindow()));
        launcher.Items.Add(ActionItem("Phone Bar…", OpenPhoneTrackpad));
        launcher.Items.Add(ActionItem("PowerToys settings…", OpenPowerToys));
        var keyboard = new MenuFlyoutSubItem { Text = "Keyboard controls" };
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
        themes.Items.Add(Switch("Rotate SSMS themes", settings.SsmsTheme, enabled => { settings.SsmsTheme = enabled; if (enabled) UpdateSsmsTheme(true); }));
        themes.Items.Add(ActionItem("Rotate SSMS theme now", () => { settings.SsmsTheme = true; UpdateSsmsTheme(true); Save(); }));
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
    public async Task CheckUpdatesAsync(bool interactive) {
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
            if (!interactive) { RefreshMenu(); return; }
            if (newest == null) { MessageBox(IntPtr.Zero, "3£Windows " + Version + " is up to date.", "3£Windows", 0x40 | ForegroundDialog); return; }
            if (MessageBox(IntPtr.Zero, "Install 3£Windows " + newestVersion + "?\n\nThe portable installer will be downloaded, its SHA-256 checksum verified, and Windows will request administrator approval.", "3£Windows update", 0x24 | ForegroundDialog) != 6) return;
            await InstallUpdateAsync(newest.Value);
        } catch (Exception ex) {
            Log(ex);
            // Throttle failures too, so an offline device never polls every 20 seconds.
            settings.LastUpdateCheckUtc = DateTime.UtcNow;
            Save();
            if (interactive) MessageBox(IntPtr.Zero, "Could not check or install the update.\n\n" + ex.Message, "3£Windows", 0x10 | ForegroundDialog);
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

    private async Task InstallUpdateAsync(JsonElement release) {
        const string name = "3£Windows.ps1";
        var contents = await ReadVerifiedInstallerAsync(release);
        var folder = Path.Combine(data, "Updates", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var installer = Path.Combine(folder, name);
        await File.WriteAllBytesAsync(installer, contents);
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
        phoneBar.Dispose();
        Save();
        StopKeyboard(); Stop("PowerToys"); Stop("PowerToys.KeyboardManagerEngine"); Stop("WinDynamicDesktop");
    }
}
