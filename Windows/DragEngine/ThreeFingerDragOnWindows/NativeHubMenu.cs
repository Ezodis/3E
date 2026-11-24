using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Runtime.InteropServices;
using ThreeE.Brand;

namespace ThreeFingerDragOnWindows;

// Windows owns selection, dismissal and keyboard navigation. We paint complete
// rows only when WM_DRAWITEM requests them, never over a live menu on a timer.
internal sealed class NativeHubMenu : IDisposable {
    internal sealed record Row(string Text, bool Enabled = true, bool Checked = false, string Icon = null, bool Accent = false, bool Separator = false, Row[] Children = null);
    internal readonly record struct Choice(int Index, bool Accessory);
    private readonly Row[] rows;
    private readonly uint dpi;
    private readonly bool dark;
    private readonly Font font;
    private readonly SubclassProc callback;
    private readonly IntPtr menu;
    private readonly Rectangle[] rowBounds;
    private readonly List<(Row Row, IntPtr Menu, uint Position, int Width)> entries = new();
    private IntPtr nativeBrush;
    private readonly int width;
    private bool disposed;
    private bool mouseSelection;
    private Exception paintError;
    private static readonly UIntPtr SubclassId = (UIntPtr)0x3E42;
    private int Px(float value) => (int)Math.Round(value * dpi / 96f);
    internal int RowHeight => Px(24);
    internal int Width => width;
    internal Rectangle IconBounds(int rowWidth, int height) => new(rowWidth - Px(32), (height - Px(16)) / 2, Px(16), Px(16));
    internal bool AccessoryHit(Row row, Point point, Rectangle bounds, bool mouse) => mouse && row.Enabled && row.Icon != null && row.Children == null &&
        bounds.Contains(point) && point.X >= bounds.Right - Px(44);

    internal NativeHubMenu(Row[] rows, uint dpi, bool dark, int maxWidth = int.MaxValue) {
        this.rows = rows; this.dpi = Math.Max(96u, dpi); this.dark = dark;
        font = new Font(SystemFonts.MenuFont.FontFamily, SystemFonts.MenuFont.SizeInPoints * this.dpi / 72f, FontStyle.Regular, GraphicsUnit.Pixel);
        width = MeasureWidth(rows, maxWidth);
        callback = WindowMessage;
        nativeBrush = CreateSolidBrush(ToColorRef(Background));
        try { menu = BuildMenu(rows, maxWidth, customRows: true); }
        catch { DeleteObject(nativeBrush); nativeBrush = IntPtr.Zero; font.Dispose(); throw; }
        rowBounds = new Rectangle[entries.Count];
    }

    private int MeasureWidth(Row[] items, int maxWidth) {
        using (var sample = new Bitmap(1, 1)) using (var graphics = Graphics.FromImage(sample)) {
            using var format = TextFormat();
            int text = (int)Math.Ceiling(items.Where(r => !r.Separator).Select(r => graphics.MeasureString(r.Text, font, int.MaxValue, format).Width).DefaultIfEmpty(0).Max());
            return Math.Min(Math.Max(Px(240), text + Px(88)), maxWidth);
        }
    }

    private IntPtr BuildMenu(Row[] items, int maxWidth, bool customRows = false) {
        var handle = CreatePopupMenu();
        if (handle == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        int menuWidth = MeasureWidth(items, maxWidth);
        var appearance = new MenuInfo { Size = (uint)Marshal.SizeOf<MenuInfo>(), Mask = 2, Background = nativeBrush };
        if (customRows) SetMenuInfo(handle, ref appearance);
        try {
            for (int index = 0; index < items.Length; index++) {
                var row = items[index];
                uint id = (uint)entries.Count + 1;
                entries.Add((row, handle, (uint)index, menuWidth));
                var submenu = row.Children is { Length: > 0 } ? BuildMenu(row.Children, maxWidth) : IntPtr.Zero;
                // Real native submenus provide hover, arrows, dismissal and keyboard
                // navigation. Text stays accessible even though we draw the rows.
                var item = new MenuItemInfo { Size = (uint)Marshal.SizeOf<MenuItemInfo>(), Mask = 0x100 | 0x40 | 0x20 | 2 | 1 | 4,
                    // Child menus contain plain installation commands. Let Windows
                    // measure and draw them, including themed submenu buffering.
                    Type = row.Separator ? 0x800u : customRows ? 0x100u : 0u, State = (row.Enabled ? 0u : 3u) | (row.Checked ? 8u : 0u),
                    Id = id, Data = (UIntPtr)id, Text = row.Text, Submenu = submenu };
                if (!InsertMenuItemW(handle, (uint)index, true, ref item)) {
                    if (submenu != IntPtr.Zero) DestroyMenu(submenu);
                    throw new System.ComponentModel.Win32Exception();
                }
            }
            return handle;
        } catch {
            DestroyMenu(handle); // also destroys every attached submenu
            throw;
        }
    }

    private Color Background => HighContrast ? SystemColors.Menu : dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(249, 249, 249);
    private static uint ToColorRef(Color color) => (uint)(color.R | color.G << 8 | color.B << 16);
    private static bool HighContrast {
        get { var info = new HighContrastInfo { Size = (uint)Marshal.SizeOf<HighContrastInfo>() }; return SystemParametersInfoW(0x42, info.Size, ref info, 0) && (info.Flags & 1) != 0; }
    }
    private static StringFormat TextFormat() => new(StringFormat.GenericTypographic) {
        Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center,
        Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap,
        HotkeyPrefix = System.Drawing.Text.HotkeyPrefix.None
    };

    // This exact renderer also produces the DPI/theme/hover regression previews.
    internal Bitmap Render(Row row, int rowWidth, int height, bool selected) {
        var bitmap = new Bitmap(rowWidth, height);
        using var g = Graphics.FromImage(bitmap);
        bool contrast = HighContrast;
        var background = selected && row.Enabled ? contrast ? SystemColors.Highlight : dark ? Color.FromArgb(57, 57, 57) : Color.FromArgb(229, 229, 229) : Background;
        var foreground = !row.Enabled ? SystemColors.GrayText : contrast ? selected ? SystemColors.HighlightText : SystemColors.MenuText : dark ? Color.WhiteSmoke : Color.FromArgb(32, 32, 32);
        g.Clear(background);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        using var textBrush = new SolidBrush(foreground);
        using var format = TextFormat();
        g.DrawString(row.Text, font, textBrush, new RectangleF(Px(32), 0, Math.Max(1, rowWidth - Px(84)), height), format);
        if (row.Checked) {
            using var pen = new Pen(foreground, Math.Max(1, Px(1.2f))) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
            float cy = height / 2f;
            g.DrawLines(pen, new[] { new PointF(Px(10), cy), new PointF(Px(13), cy + Px(3)), new PointF(Px(19), cy - Px(3)) });
        }
        if (row.Icon != null) MenuIcons.Draw(g, row.Icon, IconBounds(rowWidth, height), row.Accent && row.Enabled && !contrast ? dark ? Color.FromArgb(0, 255, 194) : Color.FromArgb(0, 120, 80) : foreground);
        return bitmap;
    }

    internal Choice? Show(IntPtr owner, Point point) {
        if (!SetWindowSubclass(owner, callback, SubclassId, UIntPtr.Zero)) throw new System.ComponentModel.Win32Exception();
        try {
            SetForegroundWindow(owner);
            uint command = TrackPopupMenuEx(menu, 0x0100 | 0x0002, point.X, point.Y, owner, IntPtr.Zero); // return command, either mouse button
            PostMessageW(owner, 0, IntPtr.Zero, IntPtr.Zero);
            if (paintError != null) throw new InvalidOperationException("Could not draw the controls menu.", paintError);
            if (command == 0 || command > entries.Count) return null;
            int index = (int)command - 1;
            bool accessory = false;
            if (GetCursorPos(out var cursor)) {
                bool mouse = mouseSelection && GetKeyState(13) >= 0 && GetKeyState(32) >= 0;
                accessory = AccessoryHit(entries[index].Row, cursor, rowBounds[index], mouse);
            }
            return new Choice(index, accessory);
        } finally { RemoveWindowSubclass(owner, callback, SubclassId); }
    }

    private IntPtr WindowMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr data) {
        try {
            if (message == 0x0125 && entries.Any(entry => entry.Menu == lParam)) { // WM_MENUSELECT
                mouseSelection = ((wParam.ToInt64() >> 16) & 0x8000) != 0;
                // Refresh every row in this popup, including checked rows and rows
                // restored after a child submenu closes. Rectangles are screen pixels.
                for (int index = 0; index < entries.Count; index++) {
                    var entry = entries[index];
                    if (entry.Menu == lParam && GetMenuItemRect(IntPtr.Zero, entry.Menu, entry.Position, out var rect))
                        rowBounds[index] = rect.Rectangle;
                }
            }
            if (message == 0x002C) { // WM_MEASUREITEM
                var measure = Marshal.PtrToStructure<MeasureItem>(lParam);
                if (measure.ControlType == 1 && measure.ItemData.ToUInt64() >= 1 && measure.ItemData.ToUInt64() <= (ulong)entries.Count) {
                    measure.Width = (uint)entries[(int)measure.ItemData.ToUInt64() - 1].Width; measure.Height = (uint)RowHeight;
                    Marshal.StructureToPtr(measure, lParam, false); return (IntPtr)1;
                }
            }
            if (message == 0x002B) { // WM_DRAWITEM
                var draw = Marshal.PtrToStructure<DrawItem>(lParam);
                if (draw.ControlType == 1 && draw.ItemId >= 1 && draw.ItemId <= entries.Count && draw.Window == entries[(int)draw.ItemId - 1].Menu) {
                    var entry = entries[(int)draw.ItemId - 1];
                    var rect = draw.Bounds.Rectangle;
                    using var buffer = Render(entry.Row, rect.Width, rect.Height, (draw.State & 1) != 0);
                    // Commit the completed row in one blit. Hovering never wipes
                    // just the icon square or samples a previous paint's pixels.
                    Blit(buffer, draw.Dc, rect.X, rect.Y);
                    if (GetMenuItemRect(IntPtr.Zero, entry.Menu, entry.Position, out var screen)) rowBounds[draw.ItemId - 1] = screen.Rectangle;
                    return (IntPtr)1;
                }
            }
        } catch (Exception ex) { paintError = ex; }
        return DefSubclassProc(window, message, wParam, lParam);
    }

    // Submenus can receive a buffered/themed HDC that GDI+ cannot wrap. Render
    // offscreen with GDI+, then use GDI for the final copy to either popup.
    private static void Blit(Bitmap bitmap, IntPtr destination, int x, int y) {
        var source = CreateCompatibleDC(destination);
        if (source == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        IntPtr image = IntPtr.Zero, previous = IntPtr.Zero;
        try {
            image = bitmap.GetHbitmap();
            previous = SelectObject(source, image);
            if (!BitBlt(destination, x, y, bitmap.Width, bitmap.Height, source, 0, 0, 0x00CC0020))
                throw new System.ComponentModel.Win32Exception();
        } finally {
            if (previous != IntPtr.Zero) SelectObject(source, previous);
            if (image != IntPtr.Zero) DeleteObject(image);
            DeleteDC(source);
        }
    }

    internal static uint DpiAt(Point point, IntPtr owner) {
        var monitor = MonitorFromPoint(point, 2);
        if (GetDpiForMonitor(monitor, 0, out var x, out _) == 0 && x > 0) return x;
        return Math.Max(96u, GetDpiForWindow(owner));
    }
    internal static int MaxWidthAt(Point point) {
        var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
        return GetMonitorInfoW(MonitorFromPoint(point, 2), ref info) ? Math.Max(160, info.Work.Right - info.Work.Left - 16) : 1200;
    }

    internal static bool CheckRendering(string outputDirectory) {
        var checks = new List<bool>();
        if (outputDirectory != null) System.IO.Directory.CreateDirectory(outputDirectory);
        foreach (uint scale in new uint[] { 96, 120, 144, 192 }) foreach (bool dark in new[] { false, true }) {
            var rows = new[] {
                new Row("3£ 3.0.167.2", Enabled: false),
                new Row("Three-finger drag", Icon: "settings"),
                new Row("Car View", Icon: "mirror", Accent: true),
                new Row("Three-finger drag", Checked: true, Icon: "settings"),
                new Row("PowerToys", Checked: true, Icon: "settings"),
                new Row("Rotate themes", Checked: true, Icon: "rotate"),
                new Row("Track Phone — USB cable only"),
                new Row("Track Tab", Checked: true),
                new Row("Modules", Children: new[] { new Row("Uninstall Auto dark"), new Row("Install Kalista") }),
                new Row("Quit 3£")
            };
            using var popup = new NativeHubMenu(rows, scale, dark);
            var rectangle = new Rectangle(0, 0, popup.Width, popup.RowHeight);
            var icon = popup.IconBounds(rectangle.Width, rectangle.Height);
            var center = new Point(icon.X + icon.Width / 2, icon.Y + icon.Height / 2);
            checks.Add(rectangle.Contains(icon));
            checks.Add(popup.AccessoryHit(rows[1], center, rectangle, true));
            checks.Add(!popup.AccessoryHit(rows[1], center, rectangle, false));
            checks.Add(!popup.AccessoryHit(rows[1], new Point(40, center.Y), rectangle, true));
            checks.Add(!popup.AccessoryHit(rows[0], center, rectangle, true));
            checks.Add(!popup.AccessoryHit(rows[1], new Point(center.X, -1), rectangle, true));
            checks.Add(!popup.AccessoryHit(rows[6], center, rectangle, true));
            checks.Add(!popup.AccessoryHit(rows[7], center, rectangle, true));
            var item = new MenuItemInfo { Size = (uint)Marshal.SizeOf<MenuItemInfo>(), Mask = 0x100 | 2 };
            checks.Add(GetMenuItemInfoW(popup.menu, 1, true, ref item) && (item.Type & 0x100) != 0 && item.Id == 2);
            var parent = new MenuItemInfo { Size = (uint)Marshal.SizeOf<MenuItemInfo>(), Mask = 4 | 2 };
            checks.Add(GetMenuItemInfoW(popup.menu, 8, true, ref parent) && parent.Submenu != IntPtr.Zero && parent.Id == 9);
            var child = new MenuItemInfo { Size = (uint)Marshal.SizeOf<MenuItemInfo>(), Mask = 2 | 0x100 };
            checks.Add(GetMenuItemInfoW(parent.Submenu, 0, true, ref child) && child.Id == 10 && (child.Type & 0x100) == 0);
            checks.Add(GetMenuItemInfoW(parent.Submenu, 1, true, ref child) && child.Id == 11);
            checks.Add(GetMenuItemInfoW(popup.menu, 9, true, ref child) && child.Id == 12);
            checks.Add(popup.entries[9].Menu == parent.Submenu && popup.entries[9].Position == 0);
            // Exercise WM_DRAWITEM with a borrowed device context, rather than
            // only rendering detached rows. Child commands use native text.
            using (var painted = new Bitmap(popup.Width, popup.RowHeight)) {
                using var graphics = Graphics.FromImage(painted);
                var dc = graphics.GetHdc();
                var nativeDraw = Marshal.AllocHGlobal(Marshal.SizeOf<DrawItem>());
                try {
                    Marshal.StructureToPtr(new DrawItem {
                        ControlType = 1, ItemId = 2, Window = popup.menu, Dc = dc,
                        Bounds = new Rect { Right = painted.Width, Bottom = painted.Height }, ItemData = (UIntPtr)2
                    }, nativeDraw, false);
                    checks.Add(popup.WindowMessage(IntPtr.Zero, 0x002B, IntPtr.Zero, nativeDraw, UIntPtr.Zero, UIntPtr.Zero) == (IntPtr)1);
                    checks.Add(popup.paintError == null);
                } finally { Marshal.FreeHGlobal(nativeDraw); graphics.ReleaseHdc(dc); }
                checks.Add(painted.GetPixel(2, 2).ToArgb() == popup.Background.ToArgb());
            }
            using var preview = new Bitmap(popup.Width, popup.RowHeight * rows.Length);
            using var canvas = Graphics.FromImage(preview);
            for (int index = 0; index < rows.Length; index++) {
                using var row = popup.Render(rows[index], popup.Width, popup.RowHeight, index == 2 || index == 4);
                canvas.DrawImageUnscaled(row, 0, index * popup.RowHeight);
            }
            // Hover cannot leave pixels behind: each paint starts from a clean
            // full row. Shared artwork must stay entirely within its column.
            using var first = popup.Render(rows[1], popup.Width, popup.RowHeight, false);
            using var hovered = popup.Render(rows[1], popup.Width, popup.RowHeight, true);
            using var restored = popup.Render(rows[1], popup.Width, popup.RowHeight, false);
            using var noIcon = popup.Render(rows[1] with { Icon = null }, popup.Width, popup.RowHeight, false);
            bool clean = true, contained = true, drawn = false;
            for (int y = 0; y < first.Height; y++) for (int x = 0; x < first.Width; x++) {
                clean &= first.GetPixel(x, y) == restored.GetPixel(x, y);
                if (first.GetPixel(x, y) != noIcon.GetPixel(x, y)) { drawn = true; contained &= icon.Contains(x, y); }
            }
            checks.Add(clean); checks.Add(contained && drawn);
            if (outputDirectory != null) preview.Save(System.IO.Path.Combine(outputDirectory, $"menu-{scale}-{(dark ? "dark" : "light")}.png"));
        }
        bool passed = checks.All(result => result);
        if (outputDirectory != null) System.IO.File.WriteAllText(System.IO.Path.Combine(outputDirectory, "checks.json"), System.Text.Json.JsonSerializer.Serialize(new { passed, count = checks.Count, checks }));
        return passed;
    }
    public void Dispose() {
        if (disposed) return;
        disposed = true;
        if (menu != IntPtr.Zero) DestroyMenu(menu);
        if (nativeBrush != IntPtr.Zero) { DeleteObject(nativeBrush); nativeBrush = IntPtr.Zero; }
        font.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; public Rectangle Rectangle => Rectangle.FromLTRB(Left, Top, Right, Bottom); }
    [StructLayout(LayoutKind.Sequential)] private struct MeasureItem { public uint ControlType, ControlId, ItemId, Width, Height; public UIntPtr ItemData; }
    [StructLayout(LayoutKind.Sequential)] private struct DrawItem { public uint ControlType, ControlId, ItemId, Action, State; public IntPtr Window, Dc; public Rect Bounds; public UIntPtr ItemData; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct MenuItemInfo { public uint Size, Mask, Type, State, Id; public IntPtr Submenu, Checked, Unchecked; public UIntPtr Data; [MarshalAs(UnmanagedType.LPWStr)] public string Text; public uint TextLength; public IntPtr Bitmap; }
    [StructLayout(LayoutKind.Sequential)] private struct MenuInfo { public uint Size, Mask, Style, MaxHeight; public IntPtr Background; public uint HelpId; public UIntPtr Data; }
    [StructLayout(LayoutKind.Sequential)] private struct HighContrastInfo { public uint Size, Flags; public IntPtr Scheme; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public uint Size; public Rect Monitor, Work; public uint Flags; }
    private delegate IntPtr SubclassProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr data);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern bool BitBlt(IntPtr destination, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool InsertMenuItemW(IntPtr menu, uint item, bool byPosition, ref MenuItemInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMenuItemInfoW(IntPtr menu, uint item, bool byPosition, ref MenuItemInfo info);
    [DllImport("user32.dll")] private static extern bool SetMenuInfo(IntPtr menu, ref MenuInfo info);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenuEx(IntPtr menu, uint flags, int x, int y, IntPtr window, IntPtr reserved);
    [DllImport("comctl32.dll")] private static extern bool SetWindowSubclass(IntPtr window, SubclassProc callback, UIntPtr id, UIntPtr data);
    [DllImport("comctl32.dll")] private static extern bool RemoveWindowSubclass(IntPtr window, SubclassProc callback, UIntPtr id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool GetMenuItemRect(IntPtr window, IntPtr menu, uint item, out Rect rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowW(string className, string windowName);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern short GetKeyState(int key);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool PostMessageW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfoW(IntPtr monitor, ref MonitorInfo info);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] private static extern bool SystemParametersInfoW(uint action, uint size, ref HighContrastInfo info, uint flags);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateSolidBrush(uint color);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
}
