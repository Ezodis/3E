using System.Runtime.InteropServices;
using System.Text.Json;

// Opt-in integration test, never run by build.ps1 or at app startup. Tests the
// installed PowerToys engine, not a fake IEngine or the JSON's contents. All
// generated shortcut key-downs are intercepted, so no app is closed, no search
// opens, and no screenshot is taken. Requires the unlocked interactive desktop.
sealed class ShortcutProbe : Form {
    const ulong SourceTag = 0x3E003E00, ShortcutTag = 0x101, SuppressTag = 0x111;
    [StructLayout(LayoutKind.Sequential)] struct KeyboardEvent { public uint Vk, Scan, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort Vk, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] struct InputData { [FieldOffset(0)] public KeyboardInput Key; [FieldOffset(0)] public MouseInput Mouse; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputData Data; }
    delegate IntPtr Hook(int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, Hook callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from, uint to, bool attach);

    readonly List<object> checks = new();
    readonly List<(uint Key, uint Modifiers)> output = new();
    readonly HashSet<uint> injectedModifiers = new();
    readonly string report;
    readonly Hook callback;
    IntPtr hook;
    bool testing, interrupted;
    public int Result = 1;

    ShortcutProbe(string report) {
        this.report = report;
        Text = "3£ shortcut verification"; Width = 440; Height = 140;
        StartPosition = FormStartPosition.CenterScreen;
        Controls.Add(new Label { Dock = DockStyle.Fill,
            Text = "Checking Command shortcuts. Please leave keys released.\nGenerated system actions are intercepted.",
            TextAlign = System.Drawing.ContentAlignment.MiddleCenter });
        callback = Observe;
        Shown += async (_, _) => await Run();
    }

    IntPtr Observe(int code, IntPtr message, IntPtr data) {
        if (code >= 0 && testing) {
            var key = Marshal.PtrToStructure<KeyboardEvent>(data);
            ulong tag = key.Extra.ToUInt64();
            // A person typing during the probe invalidates a chord; PowerToys
            // intentionally ignores shortcuts with unrelated held keys. Report
            // interruption rather than misdiagnosing a broken remap. Never log
            // those keys or suppress them.
            if (tag != SourceTag && tag != ShortcutTag && tag != SuppressTag && tag != 0x11) interrupted = true;
            bool down = message == (IntPtr)0x100 || message == (IntPtr)0x104;
            if (tag == ShortcutTag || tag == SuppressTag) {
                if (tag == ShortcutTag) {
                    if (Modifier(key.Vk) != 0) {
                        if (down) injectedModifiers.Add(key.Vk); else injectedModifiers.Remove(key.Vk);
                    } else if (down) {
                        // Some modifiers (e.g. Shift in Command+Shift+4) are
                        // already held, so PowerToys correctly doesn't inject
                        // them again. Combine native state with the generated
                        // modifier presses we intercepted instead of insisting
                        // that every modifier be newly emitted.
                        uint modifiers = 0;
                        foreach (int vk in new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
                            if ((GetAsyncKeyState(vk) & 0x8000) != 0) modifiers |= Modifier((uint)vk);
                        foreach (uint vk in injectedModifiers) modifiers |= Modifier(vk);
                        output.Add((key.Vk, modifiers));
                    }
                }
                // Let releases clear keyboard state, but intercept generated
                // shortcut presses. Single-key remaps (tag 0x11) must pass
                // through to let Clicks' right Ctrl reach the shortcut engine.
                if (down) return (IntPtr)1;
            }
        }
        return CallNextHookEx(hook, code, message, data);
    }

    static uint Modifier(uint key) => key switch {
        0x12 or 0xA4 or 0xA5 => 1,
        0x11 or 0xA2 or 0xA3 => 2,
        0x10 or 0xA0 or 0xA1 => 4,
        0x5B or 0x5C => 8,
        _ => 0
    };

    static void Send(ushort key, bool up, ulong tag = SourceTag) {
        var input = new Input { Type = 1, Data = new InputData { Key = new KeyboardInput {
            Vk = key, Flags = (up ? 2u : 0u) | (key is 0xA3 or 0xA5 ? 1u : 0u), Extra = (UIntPtr)tag
        } } };
        if (SendInput(1, [input], Marshal.SizeOf<Input>()) != 1) throw new System.ComponentModel.Win32Exception();
    }

    async Task Check(string name, ushort[] keys, uint expectedKey, uint expectedModifiers) {
        foreach (int key in new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
            if ((GetAsyncKeyState(key) & 0x8000) != 0) throw new InvalidOperationException("Release modifiers before testing.");
        output.Clear(); injectedModifiers.Clear(); interrupted = false; testing = true;
        int pressed = 0;
        try {
            foreach (ushort key in keys) {
                if (GetForegroundWindow() != Handle) throw new InvalidOperationException("Test window is not focused. Unlock Windows and rerun; no further input was sent.");
                Send(key, false); pressed++;
                await Task.Delay(80);
            }
        } finally {
            for (int i = pressed - 1; i >= 0; i--) Send(keys[i], true);
            await Task.Delay(80);
            // Release only the keys this test pressed, bypassing remapping.
            for (int i = pressed - 1; i >= 0; i--) Send(keys[i], true, ShortcutTag);
            testing = false;
        }
        if (interrupted) throw new InvalidOperationException("Other keyboard input interrupted the live check. Leave keys released and rerun.");
        bool passed = output.Any(k => k.Key == expectedKey && k.Modifiers == expectedModifiers);
        checks.Add(new { name, passed, expectedKey, expectedModifiers, actual = output.Select(k => new { k.Key, k.Modifiers }).ToArray() });
        if (!passed) throw new InvalidOperationException(name + " did not produce the expected shortcut.");
    }

    async Task Run() {
        string error = null;
        try {
            string keyboard = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "PowerToys", "Keyboard Manager");
            using var settings = JsonDocument.Parse(File.ReadAllText(Path.Combine(keyboard, "settings.json")));
            string active = settings.RootElement.GetProperty("properties").GetProperty("activeConfiguration").GetProperty("value").GetString();
            if (active == null || !active.StartsWith("3e-mac-", StringComparison.Ordinal) ||
                !Guid.TryParseExact(active.Substring(7), "N", out _)) throw new InvalidOperationException("Enable 3£ Mac keyboard layout before running the live check.");
            using var profile = JsonDocument.Parse(File.ReadAllText(Path.Combine(keyboard, active + ".json")));
            bool swapsAlt = profile.RootElement.GetProperty("remapKeys").GetProperty("inProcess").EnumerateArray()
                .Any(k => k.GetProperty("originalKeys").GetString() == "164" && k.GetProperty("newRemapKeys").GetString() == "162");
            // On old installations the OS already converts PC Alt to left Ctrl.
            // On fresh installations exercise PowerToys' Alt -> Ctrl remap too.
            ushort pcCommand = swapsAlt ? (ushort)0xA4 : (ushort)0xA2;
            TopMost = true; ShowWindow(Handle, 5); ShowWindow(Handle, 9);
            uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out _), currentThread = GetCurrentThreadId();
            bool attached = foregroundThread != 0 && foregroundThread != currentThread && AttachThreadInput(currentThread, foregroundThread, true);
            try { Activate(); SetForegroundWindow(Handle); }
            finally { if (attached) AttachThreadInput(currentThread, foregroundThread, false); }
            await Task.Delay(300);
            if (GetForegroundWindow() != Handle) throw new InvalidOperationException("Unlock Windows and focus the test window before running this check.");
            hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            foreach (ushort command in new ushort[] { pcCommand, 0xA3 }) {
                string device = command == pcCommand ? "PC Command" : "Clicks right Ctrl Command";
                await Check(device + "+Q", [command, 0x51], 0x73, 1);
                await Check(device + "+Space", [command, 0x20], 0x53, 8);
                await Check(device + "+Tab", [command, 0x09], 0x09, 1);
                foreach (ushort shift in new ushort[] { 0xA0, 0xA1 })
                    await Check(device + "+Shift(" + shift + ")+4", [command, shift, 0x34], 0x53, 12);
            }
            Result = 0;
        } catch (Exception ex) { error = ex.Message; }
        finally {
            testing = false;
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            File.WriteAllText(report, JsonSerializer.Serialize(new { passed = Result == 0, error, checks }, new JsonSerializerOptions { WriteIndented = true }));
            Close();
        }
    }

    [STAThread] static int Main(string[] args) {
        if (args.Length != 1) return 2;
        Application.EnableVisualStyles();
        using var probe = new ShortcutProbe(Path.GetFullPath(args[0]));
        Application.Run(probe);
        return probe.Result;
    }
}
