using ThreeE.PhoneControl;
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
    private IntPtr window;
    private Bitmap card;
    private string displayedLink, displayedStatus;
    private float scale = 1;
    private int width, height;
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
        SetFocus(window);
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
        window = CreateWindowEx(0x00000080, ClassName, "3£ Phone Bar", 0x80000000,
            point.X, point.Y, 208, 240, IntPtr.Zero, IntPtr.Zero, wc.Instance, IntPtr.Zero);
        if (window == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        int corners = 3; // Small native rounded corners on Windows 11; older Windows ignores this.
        DwmSetWindowAttribute(window, 33, ref corners, sizeof(int));
    }

    private void Refresh() {
        displayedLink = receiver.PairingUrl;
        displayedStatus = receiver.Status;
        var next = RenderCard(displayedLink, displayedStatus, scale);
        card?.Dispose(); card = next;
        width = card.Width; height = card.Height;
        SetWindowPos(window, IntPtr.Zero, 0, 0, width, height, 0x0006);
        InvalidateRect(window, IntPtr.Zero, false);
    }

    // Render once per link/DPI change. Integer-sized QR modules retain their quiet zone.
    internal static Bitmap RenderCard(string link, string unavailable, float scale) {
        int Px(int value) => (int)Math.Round(value * scale);
        Bitmap qr = null;
        if (link != null) {
            using var data = QRCodeGenerator.GenerateQrCode(link, QRCodeGenerator.ECCLevel.M);
            using var code = new QRCode(data);
            qr = code.GetGraphic(Math.Max(3, Px(184) / data.ModuleMatrix.Count), Color.Black, Color.White, true);
        }
        using (qr) {
            int width = Math.Max(Px(192), (qr?.Width ?? 0) + Px(20));
            int height = qr == null ? Px(112) : qr.Height + Px(44);
            var bitmap = new Bitmap(width, height);
            using var graphics = Graphics.FromImage(bitmap);
            graphics.Clear(Color.White);
            using var border = new Pen(Color.FromArgb(226, 230, 232));
            graphics.DrawRectangle(border, 0, 0, width - 1, height - 1);
            if (qr != null) graphics.DrawImageUnscaled(qr, (width - qr.Width) / 2, Px(10));
            graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using var font = new Font("Segoe UI", 11 * scale, FontStyle.Regular, GraphicsUnit.Pixel);
            using var ink = new SolidBrush(Color.FromArgb(74, 84, 92));
            using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            graphics.DrawString("3£ Phone Bar", font, ink, new RectangleF(0, qr == null ? Px(10) : qr.Height + Px(10), width, Px(26)), format);
            if (qr == null) graphics.DrawString(unavailable, font, ink, new RectangleF(Px(14), Px(40), width - Px(28), height - Px(48)), format);
            return bitmap;
        }
    }

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
                case 0x0113:
                    if (displayedLink != receiver.PairingUrl || displayedLink == null && displayedStatus != receiver.Status) Refresh();
                    return IntPtr.Zero;
                case 0x02E0:
                    scale = Math.Max(1, (wParam.ToInt64() & 0xffff) / 96f);
                    Refresh();
                    var bounds = Marshal.PtrToStructure<Rect>(lParam);
                    SetWindowPos(hwnd, IntPtr.Zero, bounds.Left, bounds.Top, width, height, 0x0004);
                    return IntPtr.Zero;
                case 0x000F:
                    var dc = BeginPaint(hwnd, out var paint);
                    try {
                        using var graphics = Graphics.FromHdc(dc);
                        if (card != null) graphics.DrawImageUnscaled(card, 0, 0);
                        else graphics.Clear(Color.White);
                    } finally { EndPaint(hwnd, ref paint); }
                    return IntPtr.Zero;
            }
        } catch { if (visible) Hide(); }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    public void Dispose() {
        if (window != IntPtr.Zero) { Hide(); DestroyWindow(window); window = IntPtr.Zero; }
        card?.Dispose(); card = null;
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
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] private static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
    [DllImport("user32.dll")] private static extern UIntPtr SetTimer(IntPtr hwnd, UIntPtr id, uint ms, IntPtr callback);
    [DllImport("user32.dll")] private static extern bool KillTimer(IntPtr hwnd, UIntPtr id);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr hwnd, out PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr hwnd, ref PaintStruct paint);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr hwnd, IntPtr rect, bool erase);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
