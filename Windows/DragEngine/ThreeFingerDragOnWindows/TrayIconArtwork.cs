using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ThreeFingerDragOnWindows;

public static class TrayIconArtwork {
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);

    // Transparent artwork with an opposite-colour outline also stays legible on
    // accented taskbars. Native icons avoid asynchronous ms-appx image loading.
    public static Bitmap CreateBitmap(bool lightTaskbar) {
        var bitmap = new Bitmap(64, 64, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var family = new FontFamily("Segoe UI");
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        using var path = new GraphicsPath();
        path.AddString("3£", family, (int)FontStyle.Bold, 38, new RectangleF(2, 2, 60, 60), format);
        using var outline = new Pen(lightTaskbar ? Color.White : Color.Black, 2) { LineJoin = LineJoin.Round };
        using var fill = new SolidBrush(lightTaskbar ? Color.Black : Color.White);
        graphics.DrawPath(outline, path);
        graphics.FillPath(fill, path);
        return bitmap;
    }

    public static Icon Create(bool lightTaskbar) {
        using var bitmap = CreateBitmap(lightTaskbar);
        var handle = bitmap.GetHicon();
        try {
            using var borrowed = Icon.FromHandle(handle);
            return (Icon)borrowed.Clone();
        } finally { DestroyIcon(handle); }
    }
}
