using ThreeE.PhoneControl;
// SPDX-License-Identifier: MIT
using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using QRCoder;

namespace ThreeE.PhoneBar.Windows;

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

    // Prefer the stable name link (same QR on every network/IP); fall back to
    // the direct IP link only when no name is served.
    private string Link => receiver.NamedUrl ?? receiver.PairingUrl;

    private void Refresh() {
        displayedLink = Link;
        displayedStatus = receiver.Status;
        var next = RenderCard(displayedLink, displayedStatus, scale);
        card?.Dispose(); card = next;
        width = card.Width; height = card.Height;
        SetWindowPos(window, IntPtr.Zero, 0, 0, width, height, 0x0006);
        InvalidateRect(window, IntPtr.Zero, false);
    }

    // The 3£ butterfly mark in the label's grey (Shared/Brand/make-icons.py writes this PNG).
    private const string MarkPng = /*brand:popup*/"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";
    private static Bitmap LoadMark() {
        try { using var stream = new MemoryStream(Convert.FromBase64String(MarkPng)); return new Bitmap(stream); }
        catch { return null; }
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
            // Label with the 3£ butterfly mark in front of it.
            var labelTop = qr == null ? Px(10) : qr.Height + Px(10);
            var textWidth = graphics.MeasureString("3£ Phone Bar", font).Width;
            using (var mark = LoadMark()) {
                int markHeight = Px(12), markWidth = mark == null ? 0 : markHeight * mark.Width / mark.Height, spacing = mark == null ? 0 : Px(5);
                float left = (width - (markWidth + spacing + textWidth)) / 2f;
                if (mark != null) {
                    graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    graphics.DrawImage(mark, new RectangleF(left, labelTop + (Px(26) - markHeight) / 2f, markWidth, markHeight));
                }
                using var leftAligned = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center };
                graphics.DrawString("3£ Phone Bar", font, ink, new RectangleF(left + markWidth + spacing, labelTop, textWidth + Px(4), Px(26)), leftAligned);
            }
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
                    if (displayedLink != Link || displayedLink == null && displayedStatus != receiver.Status) Refresh();
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
