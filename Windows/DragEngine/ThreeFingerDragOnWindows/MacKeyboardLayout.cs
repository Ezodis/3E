using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace ThreeFingerDragOnWindows;

// A temporary PowerToys profile. Neither the user's profiles nor Scancode Map
// are edited. The journal survives forced updates/crashes and is written first.
public sealed class MacKeyboardLayout {
    public interface IEngine {
        bool Running { get; }
        void Validate();
        Task StopAsync();
        Task StartAsync(bool owned);
        void Watch(string lease);
    }

    public sealed class Lease {
        public string Id { get; set; }
        public string Profile { get; set; }
        public byte[] Settings { get; set; }
        public bool EngineWasRunning { get; set; }
    }

    private readonly string keyboardDirectory, journal, template;
    private readonly IEngine engine;
    private readonly Func<bool> legacySwap;
    private string SettingsPath => Path.Combine(keyboardDirectory, "settings.json");
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly string owner = Guid.NewGuid().ToString("N");
    private bool watching;
    public bool Active => File.Exists(journal) && engine.Running;
    public bool HasLease => File.Exists(journal);

    public MacKeyboardLayout(string keyboardDirectory, string dataDirectory, string template, IEngine engine, Func<bool> legacySwap) {
        this.keyboardDirectory = keyboardDirectory;
        journal = Path.Combine(dataDirectory, "mac-keyboard-lease.json");
        this.template = template;
        this.engine = engine;
        this.legacySwap = legacySwap;
    }

    public static MacKeyboardLayout Create() => new(
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "PowerToys", "Keyboard Manager"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows"),
        Path.Combine(AppContext.BaseDirectory, "MacKeyboard.json"), new NativeEngine(), HasLegacySwap);

    private static void Write(string path, byte[] contents) {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllBytes(path + ".3e.tmp", contents);
        File.Move(path + ".3e.tmp", path, true);
    }
    private static void WriteJson(string path, JsonNode value) => Write(path, System.Text.Encoding.UTF8.GetBytes(value.ToJsonString()));
    private Lease ReadLease() {
        if (!File.Exists(journal)) return null;
        var lease = JsonSerializer.Deserialize<Lease>(File.ReadAllBytes(journal));
        if (lease?.Profile == null || !lease.Profile.StartsWith("3e-mac-", StringComparison.Ordinal) ||
            !Guid.TryParseExact(lease.Profile.Substring(7), "N", out _) || !Guid.TryParseExact(lease.Id, "N", out _))
            throw new IOException("The keyboard recovery record is invalid; keep it for recovery before trying again.");
        return lease;
    }
    private async Task<FileStream> LockAsync() {
        Directory.CreateDirectory(Path.GetDirectoryName(journal));
        for (int attempt = 0; ; attempt++) {
            try { return new FileStream(journal + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) when (attempt < 200) { await Task.Delay(100).ConfigureAwait(false); }
        }
    }

    public static JsonObject Profile(string json, bool legacySwap) {
        var profile = JsonNode.Parse(json).AsObject();
        // Match logical Command (Ctrl) after the device-specific modifier
        // translation, and accept either Shift. PowerToys distinguishes sides
        // even when exactMatch is false. Keep explicit sides on generated
        // output and deduplicate the old pair of Shift redo bindings.
        var shortcuts = profile["remapShortcuts"]["global"].AsArray();
        var seen = new System.Collections.Generic.HashSet<string>(StringComparer.Ordinal);
        foreach (var shortcut in shortcuts.ToArray()) {
            string source = string.Join(";", shortcut["originalKeys"].GetValue<string>().Split(';')
                .Select(key => key is "160" or "161" ? "16" : key is "162" or "163" ? "17" : key));
            if (!seen.Add(source)) { shortcuts.Remove(shortcut); continue; }
            shortcut["originalKeys"] = source;
        }
        var keys = profile["remapKeys"]["inProcess"].AsArray();
        void Key(string source, string target) => keys.Add(new JsonObject { ["originalKeys"] = source, ["newRemapKeys"] = target });
        // Left Alt occupies Command's position on a PC keyboard. Existing
        // installations already have the old OS swap; never swap them twice.
        if (!legacySwap) { Key("164", "162"); Key("162", "164"); }
        // Clicks emits right Ctrl so its Command bypasses the PC modifier swap.
        Key("163", "162");
        return profile;
    }

    public async Task EnableAsync() {
        await gate.WaitAsync().ConfigureAwait(false);
        try {
            using var fileLock = await LockAsync().ConfigureAwait(false);
            engine.Validate();
            var profile = Profile(File.ReadAllText(template), legacySwap());
            var lease = ReadLease();
            if (lease == null) {
                lease = new Lease { Id = Guid.NewGuid().ToString("N"), Profile = "3e-mac-" + Guid.NewGuid().ToString("N"),
                    Settings = File.Exists(SettingsPath) ? File.ReadAllBytes(SettingsPath) : null, EngineWasRunning = engine.Running };
                Write(journal, JsonSerializer.SerializeToUtf8Bytes(lease));
            }
            // Replace the watcher on adoption after an update, without replacing
            // the original snapshot with our active profile.
            lease.Id = owner;
            Write(journal, JsonSerializer.SerializeToUtf8Bytes(lease));
            try {
                if (!watching) { engine.Watch(lease.Id); watching = true; }
                await engine.StopAsync().ConfigureAwait(false);
                WriteJson(Path.Combine(keyboardDirectory, lease.Profile + ".json"), profile);
                var settings = File.Exists(SettingsPath) ? JsonNode.Parse(File.ReadAllText(SettingsPath)).AsObject() : new JsonObject();
                settings["name"] = "Keyboard Manager";
                settings["version"] ??= "1.0";
                settings["properties"] ??= new JsonObject();
                settings["properties"]["activeConfiguration"] = new JsonObject { ["value"] = lease.Profile };
                WriteJson(SettingsPath, settings);
                await engine.StartAsync(true).ConfigureAwait(false);
            } catch {
                await RestoreCoreAsync(lease).ConfigureAwait(false);
                throw;
            }
        } finally { gate.Release(); }
    }

    public async Task EnsureAsync() {
        if (!Active) { await EnableAsync(); return; }
        var lease = ReadLease();
        var active = File.Exists(SettingsPath) ? JsonNode.Parse(File.ReadAllText(SettingsPath))?["properties"]?["activeConfiguration"]?["value"]?.GetValue<string>() : null;
        if (lease == null || lease.Id != owner || active != lease.Profile || !File.Exists(Path.Combine(keyboardDirectory, lease.Profile + ".json"))) await EnableAsync();
    }

    public async Task DisableAsync(string expectedLease = null) {
        await gate.WaitAsync().ConfigureAwait(false);
        try {
            using var fileLock = await LockAsync().ConfigureAwait(false);
            var lease = ReadLease();
            if (lease != null && (expectedLease == null || expectedLease == lease.Id)) await RestoreCoreAsync(lease).ConfigureAwait(false);
        } finally { gate.Release(); }
    }

    private async Task RestoreCoreAsync(Lease lease) {
        await engine.StopAsync().ConfigureAwait(false);
        if (lease.Settings == null) File.Delete(SettingsPath); else Write(SettingsPath, lease.Settings);
        File.Delete(Path.Combine(keyboardDirectory, lease.Profile + ".json"));
        // Keep the journal until restoration succeeds, so failure is retryable.
        if (lease.EngineWasRunning) await engine.StartAsync(false).ConfigureAwait(false);
        File.Delete(journal);
    }

    public static bool ContainsLegacySwap(byte[] map) {
        bool alt = false, ctrl = false;
        if (map != null) for (int i = 12; i <= map.Length - 8; i += 4) {
            uint entry = BitConverter.ToUInt32(map, i);
            alt |= entry == 0x0038001D; ctrl |= entry == 0x001D0038;
        }
        if (alt != ctrl) throw new InvalidOperationException("A partial Alt/Ctrl system remap is already installed. Restore that remap before enabling Mac keyboard layout.");
        return alt && ctrl;
    }
    private static bool HasLegacySwap() {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        using var key = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Keyboard Layout");
        return ContainsLegacySwap(key?.GetValue("Scancode Map") as byte[]);
    }

    public static string PowerToysPath => new[] {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PowerToys", "PowerToys.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "PowerToys", "PowerToys.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerToys", "PowerToys.exe")
    }.FirstOrDefault(File.Exists);

    private sealed class NativeEngine : IEngine {
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        private const string Name = "PowerToys.KeyboardManagerEngine";
        private static Process[] Processes() {
            int session = Process.GetCurrentProcess().SessionId;
            return Process.GetProcessesByName(Name).Where(p => { if (p.SessionId == session) return true; p.Dispose(); return false; }).ToArray();
        }
        private string PathName => PowerToysPath == null ? null : Path.Combine(Path.GetDirectoryName(PowerToysPath), "KeyboardManagerEngine", Name + ".exe");
        public bool Running { get { var ps = Processes(); foreach (var p in ps) p.Dispose(); return ps.Length > 0; } }
        public void Validate() { if (!File.Exists(PathName)) throw new FileNotFoundException("PowerToys Keyboard Manager is missing. Run the 3e installer to repair it."); }
        public async Task StopAsync() {
            if (!Running) return;
            // Let a held Command/Alt/Shift finish before taking its hook away.
            // Otherwise its synthetic modifier-up could never be delivered.
            for (int i = 0; new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0); i++) {
                if (i == 100) throw new IOException("Release Command, Ctrl, Alt, Shift and Windows, then try the keyboard toggle again.");
                await Task.Delay(30).ConfigureAwait(false);
            }
            var processes = Processes();
            // PowerToys' public engine termination event allows normal cleanup.
            if (EventWaitHandle.TryOpenExisting(@"Local\TerminateKBMSharedEvent-a787c967-55b6-47de-94d9-56f39fed839e", out var signal))
                using (signal) signal.Set();
            foreach (var p in processes) using (p) {
                if (!await Task.Run(() => p.WaitForExit(2000)).ConfigureAwait(false)) {
                    p.Kill();
                    if (!await Task.Run(() => p.WaitForExit(5000)).ConfigureAwait(false)) throw new IOException("Keyboard Manager did not stop; try again.");
                }
            }
        }
        public async Task StartAsync(bool owned) {
            Validate();
            using var p = Process.Start(new ProcessStartInfo(PathName, owned ? Environment.ProcessId.ToString() : "") { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden });
            await Task.Delay(700).ConfigureAwait(false);
            if (p.HasExited || !Running) throw new InvalidOperationException("Keyboard Manager could not start. Check PowerToys policy and permissions, then try again.");
        }
        public void Watch(string lease) {
            Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "ThreeE.KeyboardRecovery.exe"), Environment.ProcessId + " " + lease) {
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
            })?.Dispose();
        }
    }
}
