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
