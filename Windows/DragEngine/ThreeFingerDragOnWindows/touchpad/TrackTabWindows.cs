using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.Win32;
using ThreeE.PhoneControl;
using ThreeE.PhoneBar.Windows;
using ThreeFingerDragEngine.utils;
using ThreeFingerDragOnWindows.utils;

namespace ThreeFingerDragOnWindows.touchpad;

public sealed class TrackTabWindows : IDisposable {
    private readonly NativeTrackpadInput input = new();
    private readonly TrackTabGesture gesture;
    private readonly DispatcherTimer timer = new() { Interval=TimeSpan.FromMilliseconds(100) };
    private readonly TrackTabSettingsLease settings = new();
    private IntPtr device;
    private long lastContact;
    private bool suspended;
    // Like macOS: with several desktops a horizontal swipe switches desktop
    // (once per swipe) instead of opening the app switcher.
    private bool desktopSwipe;
    public bool Enabled { get; private set; }
    public string Error { get; private set; }
    public TrackTabWindows() {
        gesture=new((action,direction)=> {
            switch(action) {
                case "appsBegin":
                    try { desktopSwipe=NativeTrackpadInput.HasMultipleDesktops(); } catch { desktopSwipe=false; }
                    // Desktop surfaces move opposite the finger, as in NavigationGesture.
                    if(desktopSwipe)input.Desktop(-direction);else input.AppsBegin(direction);
                    break;
                case "appsStep": if(!desktopSwipe)input.AppsStep(direction); break;
                case "appsEnd": desktopSwipe=false; input.AppsEnd(); break;
                case "shortcut": input.Shortcut(direction); break;
                case "appWindow": input.AppWindow(direction); break;
                case "taskView": input.TaskView(); break;
                case "showDesktop": input.ShowDesktop(); break;
            }
        });
        timer.Tick+=(_,_)=> { if(Environment.TickCount64-lastContact>300)Cancel(); };
        SystemEvents.SessionSwitch+=SessionChanged;
        SystemEvents.PowerModeChanged+=PowerChanged;
    }
    public bool SetEnabled(bool enabled) {
        Cancel();
        try {
            if(enabled)settings.Enable();else settings.Restore();
            Enabled=enabled; Error=null;
            if(enabled)timer.Start();else timer.Stop();
            return true;
        } catch(Exception ex) { Enabled=false; Error=ex.Message; timer.Stop(); return false; }
    }
    public bool Process(IntPtr currentDevice, TouchpadContact[] contacts) {
        if(!Enabled || suspended)return false;
        long now=Environment.TickCount64;
        if(currentDevice!=device || now-lastContact>300)Cancel();
        device=currentDevice;lastContact=now;
        var info=TouchpadHelper.GetDeivceInfo(currentDevice);
        if(info==null || info.XMax<=info.XMin || info.YMax<=info.YMin)return false;
        bool claimed=gesture.Claimed || contacts.Length>=4;
        try {
            gesture.Update(contacts.Select(p=>new TrackTabGesture.Contact(p.ContactId,
                (double)(p.X-info.XMin)/(info.XMax-info.XMin),(double)(p.Y-info.YMin)/(info.YMax-info.YMin))).ToArray(),now);
        } catch(Exception ex) { Error=ex.Message; Cancel(); }
        return claimed || gesture.Claimed;
    }
    public void Cancel() { try {gesture.Cancel();} finally {desktopSwipe=false;input.AppsEnd();} }
    private void SessionChanged(object sender,SessionSwitchEventArgs e) {
        App.Instance.DispatcherQueue.TryEnqueue(()=> { suspended=e.Reason is not (SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect);Cancel(); });
    }
    private void PowerChanged(object sender,PowerModeChangedEventArgs e) {
        App.Instance.DispatcherQueue.TryEnqueue(()=> { suspended=e.Mode==PowerModes.Suspend;Cancel(); });
    }
    public void Dispose() {
        timer.Stop();SystemEvents.SessionSwitch-=SessionChanged;SystemEvents.PowerModeChanged-=PowerChanged;
        Cancel();input.Dispose();try{settings.Restore();}catch(Exception ex){Logger.Log(ex.Message);}
    }
}

// The existing installer uses these same Precision Touchpad preferences.
// Lease only four-finger actions, retaining absent values and recovering the
// original preferences after an interrupted run. Never change three-finger,
// pointer, scroll, or network settings here.
internal sealed class TrackTabSettingsLease {
    private const string Key=@"Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad";
    private static readonly string[] Names={"FourFingerSlideEnabled","FourFingerTapEnabled"};
    private readonly string path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"3EWindows","track-tab-settings.json");
    public void Enable() {
        using var key=Registry.CurrentUser.CreateSubKey(Key);
        if(!File.Exists(path)) {
            var snapshot=Names.ToDictionary(n=>n,n=>key.GetValue(n) is int value?(int?)value:null);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path+".tmp",JsonSerializer.Serialize(snapshot));File.Move(path+".tmp",path,true);
        }
        try { foreach(string name in Names)key.SetValue(name,0,RegistryValueKind.DWord);Notify(); }
        catch {Restore();throw;}
    }
    public void Restore() {
        if(!File.Exists(path))return;
        var snapshot=JsonSerializer.Deserialize<Dictionary<string,int?>>(File.ReadAllText(path));
        using var key=Registry.CurrentUser.CreateSubKey(Key);
        foreach(string name in Names) {
            // Preserve changes made explicitly in Windows Settings during use.
            if(key.GetValue(name) is not int value || value!=0 || !snapshot.TryGetValue(name,out var original))continue;
            if(original.HasValue)key.SetValue(name,original.Value,RegistryValueKind.DWord);else key.DeleteValue(name,false);
        }
        Notify();File.Delete(path);
    }
    private static void Notify()=>SendMessageTimeout(new IntPtr(0xffff),0x1a,IntPtr.Zero,"PrecisionTouchPad",2,100,out _);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern IntPtr SendMessageTimeout(IntPtr window,uint message,IntPtr wParam,string lParam,uint flags,uint timeout,out IntPtr result);
}
