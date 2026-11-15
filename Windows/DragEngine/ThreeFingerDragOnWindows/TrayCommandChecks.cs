using System;
using System.IO;
using System.Text.Json;
using H.NotifyIcon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace ThreeFingerDragOnWindows;

// Exercise the actual WinUI dependency-property boundary, not just ICommand in
// managed code. Creates/disposes one tray icon, without hooks, tasks or networking.
internal static class TrayCommandChecks {
    internal static int Result = 1;
    public static int Run(string report) {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(_ => new App(report));
        return Result;
    }

    public static void Check(Application app, string report) {
        string stage = "load actual tray window";
        void Write(bool passed, string error = null) {
            Result = passed ? 0 : 1;
            File.WriteAllText(report, JsonSerializer.Serialize(new { passed, stage, error, version = WindowsHub.Version }));
        }
        app.UnhandledException += (_, e) => { Write(false, e.Exception.ToString()); e.Handled = true; app.Exit(); };
        DispatcherQueue.GetForCurrentThread().TryEnqueue(() => {
            try {
                var window = new touchpad.HandlerWindow((App)app, verifyTrayOnly: true);
                window.Close();
                stage = "create icon";
                using var icon = new TaskbarIcon();
                int calls = 0;
                stage = "assign left command";
                icon.LeftClickCommand = TrayCommandBridge.Create(() => calls++);
                stage = "assign right command";
                icon.RightClickCommand = TrayCommandBridge.Create(() => calls++);
                stage = "execute commands";
                for (int i = 0; i < 100; i++) {
                    icon.LeftClickCommand.Execute(null);
                    icon.RightClickCommand.Execute(null);
                }
                GC.Collect();
                GC.WaitForPendingFinalizers();
                if (calls != 200) throw new Exception("Tray command invocation failed.");
                Write(true);
            } catch (Exception e) { Write(false, e.ToString()); }
            app.Exit();
        });
    }
}
