using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Timers;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using ThreeFingerDragEngine.utils;
using ThreeFingerDragOnWindows.threefingerdrag;
using ThreeFingerDragOnWindows.utils;

namespace ThreeFingerDragOnWindows.touchpad;

public sealed partial class HandlerWindow : Window {
    public Microsoft.UI.Xaml.Controls.MenuFlyout HubMenu => MenuFlyout1;
    private readonly App _app;
    private readonly ContactsManager _contactsManager;
    private readonly ThreeFingerDrag _threeFingersDrag;
    private readonly DispatcherTimer _iconTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private System.Drawing.Icon _trayArtwork;
    private bool? _lightTaskbar;
    public string TrayIconForeground => _lightTaskbar == true ? "black" : "white";

    public bool TouchpadInitialized; // Became true when the touchpad check is done, but does not confirm that the touchpad has been registered
    public bool TouchpadExists;
    public bool InputReceiverInstalled;

    public HandlerWindow(App app){
        Logger.Log("Starting HandlerWindow...");
        InitializeComponent();

        _app = app;
        UpdateTrayIcon();
        TaskbarIcon.ForceCreate(false);
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        _iconTimer.Tick += (_, _) => UpdateTrayIcon();
        _iconTimer.Start();
        Closed += (_, _) => {
            _iconTimer.Stop();
            Microsoft.Win32.SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            TaskbarIcon.Dispose();
            _trayArtwork?.Dispose();
        };
        _contactsManager = new ContactsManager(this);
        _threeFingersDrag = new ThreeFingerDrag();

        // Let the _handlerWindow to be defined in App.xaml.cs before initializing the source
        Utils.runOnMainThreadAfter(100, () => {
            _contactsManager.InitializeSource();
        });

    }

    // TaskbarIcon Actions
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out System.Drawing.Point point);

    private void ShowMenu(Microsoft.UI.Xaml.Controls.MenuFlyout menu) {
        TaskbarIcon.ContextFlyout = menu;
        GetCursorPos(out var point);
        TaskbarIcon.ShowContextMenu(point);
    }

    private void OpenLauncher(object sender, ExecuteRequestedEventArgs e) {
        if (_app.Hub != null) ShowMenu(_app.Hub.CreateLauncher(ShowAllControls));
    }

    private void OpenAllControls(object sender, ExecuteRequestedEventArgs e) => ShowAllControls();

    private void ShowAllControls() {
        _app.Hub?.RefreshControls();
        ShowMenu(HubMenu);
    }

    private void OnUserPreferenceChanged(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs e) {
        _app.DispatcherQueue.TryEnqueue(UpdateTrayIcon);
    }

    private void UpdateTrayIcon() {
        using var preferences = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        // System theme controls the taskbar, independently of the apps theme.
        bool light = Convert.ToInt32(preferences?.GetValue("SystemUsesLightTheme", 1)) != 0;
        if (_lightTaskbar == light) return;
        var artwork = TrayIconArtwork.Create(light);
        var previous = _trayArtwork;
        TaskbarIcon.Icon = artwork;
        _trayArtwork = artwork;
        _lightTaskbar = light;
        previous?.Dispose();
    }

    private void OpenSettingsWindow(object sender, ExecuteRequestedEventArgs e){
        Logger.Log("Opening SettingsWindow from HandlerWindow TaskbarIcon");
        _app.OpenSettingsWindow();
    }

    private void QuitApp(object sender, ExecuteRequestedEventArgs e){
        Logger.Log("Quitting App from HandlerWindow TaskbarIcon");
        _app.Quit();
    }


    // Touchpad
    // Called when the touchpad is detected and the events handlers are registered (or not)
    public void OnTouchpadInitialized(bool touchpadExists, bool inputReceiverInstalled){
        TouchpadExists = touchpadExists;
        InputReceiverInstalled = inputReceiverInstalled;
        if(!touchpadExists) Logger.Log("Touchpad is not detected.");
        else if(!inputReceiverInstalled) Logger.Log("Touchpad is detected but the input receiver couldn't be installed.");
        else Logger.Log("Touchpad is detected and registered.");

        TouchpadInitialized = true;
        _app.OnTouchpadInitialized();
    }

    // Called when a new set of contacts has been registered

    private TouchpadContact[] _oldContacts = Array.Empty<TouchpadContact>();
    private long _lastContactCtms = Ctms();

    public void OnTouchpadContact(IntPtr currentDevice, List<TouchpadContact> contacts){
        if(App.SettingsData.ThreeFingerDrag){
            _threeFingersDrag.OnTouchpadContact(currentDevice, _oldContacts, contacts.ToArray(), Ctms() - _lastContactCtms);
        }

        _app.OnTouchpadContact(currentDevice, contacts.ToArray()); // Transfer to App for displaying contacts in SettingsWindow
        _lastContactCtms = Ctms();
        _oldContacts = contacts.ToArray();
    }

    private static long Ctms(){
        return new DateTimeOffset(DateTime.UtcNow).ToUnixTimeMilliseconds();
    }
}
