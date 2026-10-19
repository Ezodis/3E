// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace ThreeE.PhoneControl;

// Two-way clipboard between the phone and the computer. Hosts that can reach
// their system clipboard return an IPhoneClipboard from ITrackpadInput.Clipboard;
// the phone shows the clipboard buttons only when one is available.
public sealed class ClipPart { public string Kind, Name; public byte[] Data; }   // Kind: text, html, image (PNG), file
public sealed class ClipSnapshot { public string Text, Html; public byte[] Png; public int Width, Height; public List<string> Files = new(); }

public interface IPhoneClipboard {
    // Replaces the clipboard with every part at once (text + HTML + picture + files).
    void Write(IReadOnlyList<ClipPart> parts);
    // Text, HTML, a PNG picture and copied file paths currently on the clipboard.
    ClipSnapshot Read();
}

public static class PhoneClipboard {
    public const long MaxUpload = 200L * 1024 * 1024;
    public const long MaxDownload = 512L * 1024 * 1024;
    // Fixed key palette shared with Web/clip.js: 0 Backspace, 1 Enter, 2 Tab,
    // 3 Esc, 4-7 Left/Up/Right/Down, 8 Delete, 9 line start, 10 line end,
    // 11 delete previous word. Hosts map each id to their native keys.
    public const int KeyCount = 12;

    // Files sent from the phone are written here, one folder per transfer.
    // Folders older than a day are removed when the next transfer arrives.
    public static string NewDropFolder(string root) {
        try {
            if (Directory.Exists(root))
                foreach (var old in Directory.GetDirectories(root))
                    if (Directory.GetCreationTimeUtc(old) < DateTime.UtcNow.AddDays(-1)) try { Directory.Delete(old, true); } catch { }
        } catch { }
        var folder = Path.Combine(root, DateTime.Now.ToString("yyyyMMdd-HHmmss-fff"));
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static readonly string[] reserved = { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };
    private static readonly HashSet<char> invalid = Path.GetInvalidFileNameChars().Concat(new[] { '/', '\\', ':', '*', '?', '"', '<', '>', '|' }).ToHashSet();

    // The phone chooses the name, so it is reduced to a plain file name that is
    // valid on Windows and macOS and cannot leave the transfer folder.
    public static string SafeName(string name) {
        name = (name ?? "").Replace('\\', '/').Split('/').Last();
        name = new string(name.Select(c => c < 32 || invalid.Contains(c) ? '_' : c).ToArray()).Trim(' ', '.');
        if (name.Length == 0) name = "Phone file";
        if (name.Length > 120) { var ext = Path.GetExtension(name); name = name[..(120 - Math.Min(ext.Length, 20))] + (ext.Length <= 20 ? ext : ""); }
        if (reserved.Contains(Path.GetFileNameWithoutExtension(name).ToUpperInvariant())) name = "_" + name;
        return name;
    }

    public static string SaveFile(string folder, string name, byte[] data) {
        name = SafeName(name);
        var path = Path.Combine(folder, name);
        for (int n = 2; File.Exists(path); n++) path = Path.Combine(folder, Path.GetFileNameWithoutExtension(name) + $" ({n})" + Path.GetExtension(name));
        File.WriteAllBytes(path, data);
        return path;
    }

    public static (int Width, int Height) PngSize(byte[] png) =>
        png == null || png.Length < 24 ? (0, 0) : (png[16] << 24 | png[17] << 16 | png[18] << 8 | png[19], png[20] << 24 | png[21] << 16 | png[22] << 8 | png[23]);

    public static bool IsPng(byte[] data) => data != null && data.Length >= 33 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47;
}
