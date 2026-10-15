using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Dispatching;
using Microsoft.Windows.AppLifecycle;
using ThreeFingerDragOnWindows.utils;
using Application = Microsoft.UI.Xaml.Application;
using Utils = ThreeFingerDragOnWindows.utils.Utils;

namespace ThreeFingerDragOnWindows;

public class Program {
    private static bool openPhoneTrackpad;
    [STAThread]
    static Task<int> Main(string[] args){
        openPhoneTrackpad = Array.Exists(args, arg => arg == "--phone-trackpad");
        if (args.Length == 2 && args[0] == "--preview-tray-icons") {
            System.IO.Directory.CreateDirectory(args[1]);
            foreach (bool light in new[] { true, false }) {
                using var artwork = TrayIconArtwork.CreateBitmap(light);
                using var preview = new System.Drawing.Bitmap(64, 64);
                using var graphics = System.Drawing.Graphics.FromImage(preview);
                graphics.Clear(light ? System.Drawing.Color.White : System.Drawing.Color.FromArgb(25, 25, 25));
                graphics.DrawImage(artwork, 0, 0);
                preview.Save(System.IO.Path.Combine(args[1], light ? "light-taskbar.png" : "dark-taskbar.png"));
            }
            return Task.FromResult(0);
        }
        if (args.Length == 3 && args[0] == "--verify-release") return VerifyRelease(args[1], args[2]);
        if (args.Length == 2 && args[0] == "--self-test") {
            var cases = new[] {
                WindowsHub.ScheduledTheme(new DateTime(2026, 1, 1, 11, 59, 59)) == 0,
                WindowsHub.ScheduledTheme(new DateTime(2026, 1, 1, 12, 0, 0)) == 1,
                WindowsHub.ScheduledTheme(new DateTime(2026, 1, 1, 19, 59, 59)) == 1,
                WindowsHub.ScheduledTheme(new DateTime(2026, 1, 1, 20, 0, 0)) == 0,
                WindowsHub.WindowsReleaseVersion("combined-v99.0.0") == null,
                WindowsHub.WindowsReleaseVersion("windows-vinvalid") == null,
                WindowsHub.WindowsReleaseVersion("windows-v1.2.3") == new Version(1, 2, 3),
                SsmsTheme.FollowSystem("/* keep comment */ {\"other\":true,\"environment.visualExperience.colorTheme\":\"dark\"}") == "/* keep comment */ {\"other\":true,\"environment.visualExperience.colorTheme\":\"system\"}",
                SsmsTheme.FollowSystem("{\"environment.visualExperience.colorTheme\":\"system\"}") == "{\"environment.visualExperience.colorTheme\":\"system\"}",
                SsmsTheme.FollowSystem("{/* UTF-8: £ */\"other\":true,}").Contains("\"environment.visualExperience.colorTheme\": \"system\""),
                SsmsTheme.Choose(new[] { new SsmsTheme.Theme("a", "A", true), new SsmsTheme.Theme("b", "B", true), new SsmsTheme.Theme("c", "C", false) }, true, "a").Id == "b",
                SsmsTheme.RotationPeriod(new DateTime(2026, 10, 12, 21, 0, 0), false) == SsmsTheme.RotationPeriod(new DateTime(2026, 10, 13, 1, 0, 0), false),
            };
            bool passed = Array.TrueForAll(cases, item => item);
            System.IO.File.WriteAllText(args[1], System.Text.Json.JsonSerializer.Serialize(new { passed, cases, version = WindowsHub.Version }));
            return Task.FromResult(passed ? 0 : 1);
        }
        WinRT.ComWrappersSupport.InitializeComWrappers();

        (AppInstance existingInstance, bool existingInstanceIsAdmin) = FindExistingInstance();

        if(existingInstance != null){
            if(Utils.IsAppRunningAsAdministrator() && !existingInstanceIsAdmin && TerminateOldInstance(existingInstance.ProcessId)){
                Logger.Log("Unelevated instance found and killed. Starting the app");
                StartApp();
            } else{
                Logger.Log("Instance found, redirecting activation.");
                RedirectActivation(existingInstance);
            }
        } else{
            Logger.Log("No instance found, starting the app.");
            StartApp();
        }
        return Task.FromResult(0);
    }

    private static async Task<int> VerifyRelease(string metadata, string report) {
        try { await WindowsHub.VerifyReleaseAsync(metadata, report); return 0; }
        catch (Exception ex) { System.IO.File.WriteAllText(report, ex.ToString()); return 1; }
    }

    private static void RedirectActivation(AppInstance instance){
        AppActivationArguments args = AppInstance.GetCurrent().GetActivatedEventArgs();
        _ = instance.RedirectActivationToAsync(args);
    }

    private static void StartApp(){
        AppInstance.FindOrRegisterForKey("ThreeFingerDragOnWindows-SingleInstance-" + (Utils.IsAppRunningAsAdministrator() ? "Admin" : "User"));
        AppInstance.GetCurrent().Activated += OnActivated;

        Application.Start((p) => {
            var context = new DispatcherQueueSynchronizationContext(
                DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            new App();
            if (openPhoneTrackpad) App.Instance.Hub.OpenPhoneTrackpad();
        });
    }

    private static (AppInstance, bool) FindExistingInstance(){
        foreach(AppInstance appInstance in AppInstance.GetInstances()){
            if(appInstance.IsCurrent) continue;
            if(appInstance.Key.Equals("ThreeFingerDragOnWindows-SingleInstance-User")){
                return (appInstance, false);
            }

            if(appInstance.Key.Equals("ThreeFingerDragOnWindows-SingleInstance-Admin")){
                return (appInstance, true);
            }
        }

        return (null, false);
    }

    private static void OnActivated(object sender, AppActivationArguments args){
        bool phone = args.Data is Windows.ApplicationModel.Activation.ILaunchActivatedEventArgs launch && launch.Arguments.Contains("--phone-trackpad", StringComparison.Ordinal);
        (Application.Current as App)?.DispatcherQueue.TryEnqueue(() => {
            if (phone) (Application.Current as App)?.Hub.OpenPhoneTrackpad();
            else (Application.Current as App)?.OpenSettingsWindow();
        });
    }

    private static bool TerminateOldInstance(uint processId){
        try{
            Process oldInstance = Process.GetProcessById((int) processId);
            oldInstance.Kill();
        } catch(Exception ex){
            Logger.Log(ex.ToString());
            return false;
        }

        return true;
    }
}
