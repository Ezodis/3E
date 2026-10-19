using System;
using System.Drawing;
using System.IO;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ThreeFingerDragOnWindows;

public static class TrayIconArtwork {
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);

    // The 3£ butterfly mark (Shared/Brand/make-icons.py writes this white mask).
    private const string MaskPng = /*brand:mask*/"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";

    // Transparent artwork with an opposite-colour outline also stays legible on
    // accented taskbars. Native icons avoid asynchronous ms-appx image loading.
    public static Bitmap CreateBitmap(bool lightTaskbar) {
        using var stream = new MemoryStream(Convert.FromBase64String(MaskPng));
        using var mask = new Bitmap(stream);
        var bitmap = new Bitmap(64, 64, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        using var outline = Tinted(mask, lightTaskbar ? Color.White : Color.Black);
        using var fill = Tinted(mask, lightTaskbar ? Color.Black : Color.White);
        foreach (var (dx, dy) in new[] { (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1) })
            graphics.DrawImage(outline, dx, dy, 64, 64);
        graphics.DrawImage(fill, 0, 0, 64, 64);
        return bitmap;
    }

    // Recolours the mask, keeping its alpha (anti-aliased edges).
    private static Bitmap Tinted(Bitmap mask, Color color) {
        var result = new Bitmap(mask.Width, mask.Height, PixelFormat.Format32bppArgb);
        for (int y = 0; y < mask.Height; y++)
            for (int x = 0; x < mask.Width; x++)
                result.SetPixel(x, y, Color.FromArgb(mask.GetPixel(x, y).A, color));
        return result;
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
