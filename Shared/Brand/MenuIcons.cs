// SPDX-License-Identifier: MIT
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text.Json;

namespace ThreeE.Brand;

// Both platforms render this same vector artwork. Edit menu-icons.json once.
public static class MenuIcons {
    private static readonly JsonDocument Artwork = Load();
    private static JsonDocument Load() {
        using var stream = typeof(MenuIcons).Assembly.GetManifestResourceStream("ThreeE.Brand.menu-icons.json")
            ?? throw new InvalidOperationException("Shared menu icons were not packaged.");
        return JsonDocument.Parse(stream);
    }

    public static bool Contains(string name) => Artwork.RootElement.GetProperty("icons").TryGetProperty(name, out _);

    public static void Draw(Graphics graphics, string name, RectangleF bounds, Color color) {
        var root = Artwork.RootElement;
        var icon = root.GetProperty("icons").GetProperty(name);
        var state = graphics.Save();
        try {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TranslateTransform(bounds.X, bounds.Y);
            graphics.ScaleTransform(bounds.Width / root.GetProperty("viewBox").GetSingle(), bounds.Height / root.GetProperty("viewBox").GetSingle());
            using var pen = new Pen(color, root.GetProperty("strokeWidth").GetSingle()) {
                StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round
            };
            foreach (var commands in icon.GetProperty("paths").EnumerateArray()) {
                using var path = new GraphicsPath();
                PointF current = default;
                foreach (var command in commands.EnumerateArray()) {
                    PointF Point(int index) => new(command[index].GetSingle(), command[index + 1].GetSingle());
                    switch (command[0].GetString()) {
                        case "M": current = Point(1); path.StartFigure(); break;
                        case "L": var end = Point(1); path.AddLine(current, end); current = end; break;
                        case "C": var last = Point(5); path.AddBezier(current, Point(1), Point(3), last); current = last; break;
                        case "Z": path.CloseFigure(); break;
                        default: throw new InvalidOperationException("Unknown shared icon command.");
                    }
                }
                graphics.DrawPath(pen, path);
            }
            if (icon.TryGetProperty("circles", out var circles)) foreach (var circle in circles.EnumerateArray()) {
                float x = circle[0].GetSingle(), y = circle[1].GetSingle(), r = circle[2].GetSingle();
                graphics.DrawEllipse(pen, x - r, y - r, 2 * r, 2 * r);
            }
        } finally { graphics.Restore(state); }
    }
}
