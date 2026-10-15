// SPDX-License-Identifier: MIT
using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using QRCoder;

namespace ThreeFingerDragOnWindows;

// Small native tray popup. It shares the app's UI message loop without creating
// another XAML window or an additional process. Dismissing it keeps pairing active.
public sealed class PhoneTrackpadPopup : IDisposable {
    private const string ClassName = "3EWindows.PhoneTrackpadPopup";
    private readonly PhoneTrackpad receiver;
    private readonly WindowProc callback;
    private IntPtr window, title, instructions, status, stop, close, font, headingFont;
    private Bitmap qr;
    private string displayedLink;
    private float scale = 1;
    private int width, height, qrTop;
    private bool visible;
    public PhoneTrackpadPopup(PhoneTrackpad receiver) { this.receiver = receiver; callback = HandleMessage; }
    private int Px(int value) => (int)Math.Round(value * scale);

    public void Show() {
        GetCursorPos(out var point);
        EnsureWindow(point);
        scale = Math.Max(1, GetDpiForWindow(window) / 96f);
        Refresh();
        var monitor = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        GetMonitorInfo(MonitorFromPoint(point, 2), ref monitor);
        int x = Math.Clamp(point.X - width / 2, monitor.Work.Left, Math.Max(monitor.Work.Left, monitor.Work.Right - width));
        int y = Math.Clamp(point.Y - height - Px(12), monitor.Work.Top, Math.Max(monitor.Work.Top, monitor.Work.Bottom - height));
        SetWindowPos(window, new IntPtr(-1), x, y, width, height, 0x0040);
        visible = true;
        SetForegroundWindow(window);
        SetFocus(close);
        SetTimer(window, new UIntPtr(1), 1000, IntPtr.Zero);
    }

    private void EnsureWindow(Point point) {
        if (window != IntPtr.Zero) return;
        var wc = new WindowClass {
            Size = (uint)Marshal.SizeOf<WindowClass>(), Procedure = callback,
            Instance = GetModuleHandle(null), Cursor = LoadCursor(IntPtr.Zero, new IntPtr(32512)),
            Background = new IntPtr(6), ClassName = ClassName
        };
        if (RegisterClassEx(ref wc) == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        window = CreateWindowEx(0x00000080, ClassName, "3£Windows — iPhone trackpad", 0x80800000,
            point.X, point.Y, 300, 400, IntPtr.Zero, IntPtr.Zero, wc.Instance, IntPtr.Zero);
        if (window == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        title = Child("STATIC", "iPhone trackpad", 0, 0);
        instructions = Child("STATIC", "Scan with Camera, then open in Safari.\r\nUse the same Wi-Fi as this laptop.", 0, 0);
        status = Child("STATIC", "", 0, 0);
        stop = Child("BUTTON", "Stop trackpad", 0x00010000, 1);
        close = Child("BUTTON", "Close", 0x00010000, 2);
    }

    private IntPtr Child(string kind, string text, uint style, int id) =>
        CreateWindowEx(0, kind, text, 0x50000000 | style, 0, 0, 0, 0, window, new IntPtr(id), GetModuleHandle(null), IntPtr.Zero);

    private void Refresh() {
        displayedLink = receiver.PairingUrl;
        qr?.Dispose(); qr = null;
        if (displayedLink != null) {
            using var data = QRCodeGenerator.GenerateQrCode(displayedLink, QRCodeGenerator.ECCLevel.M);
            using var code = new QRCode(data);
            qr = code.GetGraphic(Math.Max(3, Px(216) / data.ModuleMatrix.Count), Color.Black, Color.White, true);
        }
        width = Px(300); height = Px(qr == null ? 230 : 408); qrTop = Px(88);
        var oldFont = font; var oldHeading = headingFont;
        font = CreateFont(-Px(13), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, "Segoe UI");
        headingFont = CreateFont(-Px(18), 0, 0, 0, 600, 0, 0, 0, 1, 0, 0, 5, 0, "Segoe UI");
        foreach (var control in new[] { instructions, status, stop, close }) SendMessage(control, 0x0030, font, new IntPtr(1));
        SendMessage(title, 0x0030, headingFont, new IntPtr(1));
        if (oldFont != IntPtr.Zero) DeleteObject(oldFont);
        if (oldHeading != IntPtr.Zero) DeleteObject(oldHeading);
        Place(title, 18, 14, 264, 28);
        Place(instructions, 18, 47, 264, 40);
        Place(status, 18, qr == null ? 98 : 310, 264, 52);
        Place(stop, 18, qr == null ? 184 : 362, 144, 30);
        Place(close, 172, qr == null ? 184 : 362, 110, 30);
        EnableWindow(stop, receiver.Running);
        SetWindowText(status, receiver.Status);
        SetWindowPos(window, IntPtr.Zero, 0, 0, width, height, 0x0006);
        InvalidateRect(window, IntPtr.Zero, true);
    }

    private void Place(IntPtr handle, int x, int y, int w, int h) => MoveWindow(handle, Px(x), Px(y), Px(w), Px(h), true);
    private void Hide() {
        visible = false;
        KillTimer(window, new UIntPtr(1));
        ShowWindow(window, 0);
    }
    private IntPtr HandleMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam) {
        // Never let a managed exception cross the native window-procedure boundary.
        try {
            switch (message) {
                case 0x0006: if ((wParam.ToInt64() & 0xffff) == 0 && visible) Hide(); break;
                case 0x0010: Hide(); return IntPtr.Zero;
                case 0x0100: if (wParam.ToInt32() == 27) { Hide(); return IntPtr.Zero; } break;
                case 0x0111:
                    int id = (int)(wParam.ToInt64() & 0xffff);
                    if (id == 1) { receiver.Stop(); Hide(); return IntPtr.Zero; }
                    if (id == 2) { Hide(); return IntPtr.Zero; }
                    break;
                case 0x0113:
                    if (displayedLink != receiver.PairingUrl) Refresh();
                    else SetWindowText(status, receiver.Status);
                    return IntPtr.Zero;
                case 0x000F:
                    var dc = BeginPaint(hwnd, out var paint);
                    try {
                        using var graphics = Graphics.FromHdc(dc);
                        graphics.Clear(Color.White);
                        if (qr != null) graphics.DrawImageUnscaled(qr, (width - qr.Width) / 2, qrTop);
                    } finally { EndPaint(hwnd, ref paint); }
                    return IntPtr.Zero;
            }
        } catch { if (visible) Hide(); }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    public void Dispose() {
        if (window != IntPtr.Zero) { Hide(); DestroyWindow(window); window = IntPtr.Zero; }
        qr?.Dispose(); qr = null;
        if (font != IntPtr.Zero) { DeleteObject(font); font = IntPtr.Zero; }
        if (headingFont != IntPtr.Zero) { DeleteObject(headingFont); headingFont = IntPtr.Zero; }
        UnregisterClass(ClassName, GetModuleHandle(null));
    }

    private delegate IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct WindowClass {
        public uint Size, Style; public WindowProc Procedure; public int ClassExtra, WindowExtra;
        public IntPtr Instance, Icon, Cursor, Background;
        public string MenuName, ClassName; public IntPtr SmallIcon;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] private struct PaintStruct {
        public IntPtr Hdc; public int Erase; public Rect Paint; public int Restore, IncUpdate;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Reserved;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern ushort RegisterClassEx(ref WindowClass wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool UnregisterClass(string name, IntPtr instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr CreateWindowEx(uint ex, string cls, string text, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll")] private static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] private static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SetWindowText(IntPtr hwnd, string text);
    [DllImport("user32.dll")] private static extern bool EnableWindow(IntPtr hwnd, bool enable);
    [DllImport("user32.dll")] private static extern UIntPtr SetTimer(IntPtr hwnd, UIntPtr id, uint ms, IntPtr callback);
    [DllImport("user32.dll")] private static extern bool KillTimer(IntPtr hwnd, UIntPtr id);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr hwnd, out PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr hwnd, ref PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr hwnd, IntPtr rect, bool erase);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CreateFont(int height, int width, int angle, int orientation, int weight, uint italic, uint underline, uint strike, uint charset, uint outPrecision, uint clipPrecision, uint quality, uint pitch, string face);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
}
