// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;

namespace ThreeE.PhoneBar.Windows;

// Equivalent of macOS Command+`: cycle top-level windows of the foreground
// application. Stable handle order avoids bouncing between only two windows.
public static class WindowsAppWindows {
    public static IntPtr Next(IEnumerable<IntPtr> windows, IntPtr current, int direction) {
        var ordered=windows.Distinct().OrderBy(h=>h.ToInt64()).ToArray();
        int index=Array.IndexOf(ordered,current);
        return direction==0 || index<0 || ordered.Length<2 ? IntPtr.Zero : ordered[(index+Math.Sign(direction)+ordered.Length)%ordered.Length];
    }
    public static void Cycle(int direction) {
        if(direction==0)return;
        var current=GetAncestor(GetForegroundWindow(),3); // Root owner, including modal dialogs.
        GetWindowThreadProcessId(current,out uint pid);
        string executable=Executable(pid);
        if(current==IntPtr.Zero || executable==null)return;
        // Shared OS hosts do not identify a single application.
        if(System.IO.Path.GetFileName(executable).Equals("ApplicationFrameHost.exe",StringComparison.OrdinalIgnoreCase))return;
        var windows=new List<IntPtr>();
        EnumWindows((hwnd,_)=> {
            if(!IsWindowVisible(hwnd) || GetWindow(hwnd,4)!=IntPtr.Zero || (GetWindowLongPtr(hwnd,-20).ToInt64()&0x80)!=0)return true;
            if(DwmGetWindowAttribute(hwnd,14,out int cloaked,4)!=0 || cloaked!=0)return true;
            GetWindowThreadProcessId(hwnd,out uint owner);
            if(owner==pid || string.Equals(Executable(owner),executable,StringComparison.OrdinalIgnoreCase))windows.Add(hwnd);
            return true;
        },IntPtr.Zero);
        var target=Next(windows,current,direction);
        if(target==IntPtr.Zero)return;
        if(IsIconic(target))ShowWindowAsync(target,9);
        var popup=GetLastActivePopup(target);
        // Respect Windows' foreground restrictions; never attach input queues
        // or alter the foreground lock timeout to force a protected window.
        SetForegroundWindow(IsWindowVisible(popup)?popup:target);
    }
    private static string Executable(uint pid) {
        try { using var process=Process.GetProcessById((int)pid);return process.MainModule?.FileName; } catch {return null;}
    }
    private delegate bool EnumWindow(IntPtr window,IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback,IntPtr state);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window,uint flags);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window,uint command);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtrW(IntPtr window,int index);
    [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr window,int index);
    private static IntPtr GetWindowLongPtr(IntPtr window,int index)=>IntPtr.Size==8?GetWindowLongPtrW(window,index):(IntPtr)GetWindowLongW(window,index);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window,int command);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window,int attribute,out int value,int size);
}
