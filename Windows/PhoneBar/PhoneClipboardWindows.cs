// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using ThreeE.PhoneControl;

namespace ThreeE.PhoneBar.Windows;

// Windows clipboard for Phone Bar: Unicode text, HTML (CF_HTML), pictures as
// PNG + CF_DIB, and files as CF_HDROP. Clipboard calls run on a short-lived
// thread that owns a message-only window, outside the pointer input lock.
public sealed class WindowsPhoneClipboard : IPhoneClipboard {
    private const uint CfUnicodeText = 13, CfDib = 8, CfDibV5 = 17, CfHdrop = 15;
    [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] private static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern uint RegisterClipboardFormatW(string name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string className, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalLock(IntPtr mem);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GlobalUnlock(IntPtr mem);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern UIntPtr GlobalSize(IntPtr mem);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalFree(IntPtr mem);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern uint DragQueryFileW(IntPtr drop, uint index, char[] file, uint size);

    // The clipboard needs a window owned by the calling thread; a short-lived
    // message-only window on a dedicated thread keeps the receiver threads free.
    private static T OnClipboardThread<T>(Func<T> work) {
        T result = default; Exception error = null;
        var thread = new Thread(() => {
            IntPtr hwnd = CreateWindowExW(0, "STATIC", "3EPhoneClipboard", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            try {
                bool open = false;
                for (int i = 0; i < 40 && !(open = OpenClipboard(hwnd)); i++) Thread.Sleep(25);
                if (!open) throw new IOException("The Windows clipboard is busy. Try again.");
                try { result = work(); } finally { CloseClipboard(); }
            } catch (Exception ex) { error = ex; }
            finally { if (hwnd != IntPtr.Zero) DestroyWindow(hwnd); }
        }) { IsBackground = true, Name = "3E phone clipboard" };
        if (OperatingSystem.IsWindows()) thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        if (!thread.Join(TimeSpan.FromSeconds(30))) throw new TimeoutException("The Windows clipboard did not respond.");
        if (error != null) throw error;
        return result;
    }

    private static void Put(uint format, byte[] data) {
        IntPtr mem = GlobalAlloc(0x0002, (UIntPtr)(uint)Math.Max(1, data.Length));
        if (mem == IntPtr.Zero) throw new OutOfMemoryException();
        IntPtr ptr = GlobalLock(mem);
        try { Marshal.Copy(data, 0, ptr, data.Length); } finally { GlobalUnlock(mem); }
        if (SetClipboardData(format, mem) == IntPtr.Zero) { GlobalFree(mem); throw new IOException("Windows refused the clipboard data."); }
    }

    private static byte[] Get(uint format, long limit = 256L * 1024 * 1024) {
        if (!IsClipboardFormatAvailable(format)) return null;
        IntPtr mem = GetClipboardData(format);
        if (mem == IntPtr.Zero) return null;
        long size = (long)(ulong)GlobalSize(mem);
        if (size <= 0 || size > limit) return null;
        IntPtr ptr = GlobalLock(mem);
        if (ptr == IntPtr.Zero) return null;
        try { var bytes = new byte[size]; Marshal.Copy(ptr, bytes, 0, (int)size); return bytes; } finally { GlobalUnlock(mem); }
    }

    public void Write(IReadOnlyList<ClipPart> parts) {
        string text = null, html = null; byte[] png = null, dib = null;
        var files = new List<string>(); string folder = null;
        foreach (var part in parts) {
            switch (part.Kind) {
                case "text": text = Encoding.UTF8.GetString(part.Data); break;
                case "html": html = Encoding.UTF8.GetString(part.Data); break;
                case "image":
                    dib = PngToDib(part.Data);
                    if (dib != null) png = part.Data;
                    else { folder ??= PhoneClipboard.NewDropFolder(DropRoot); files.Add(PhoneClipboard.SaveFile(folder, part.Name, part.Data)); }
                    break;
                case "file": folder ??= PhoneClipboard.NewDropFolder(DropRoot); files.Add(PhoneClipboard.SaveFile(folder, part.Name, part.Data)); break;
            }
        }
        if (text == null && html != null) text = Regex.Replace(Regex.Replace(html, "<[^>]+>", " "), @"\s+", " ").Trim();
        OnClipboardThread(() => {
            if (!EmptyClipboard()) throw new IOException("Windows could not clear the clipboard.");
            if (text != null) Put(CfUnicodeText, Encoding.Unicode.GetBytes(text.Replace("\r\n", "\n").Replace("\n", "\r\n") + "\0"));
            if (html != null) Put(RegisterClipboardFormatW("HTML Format"), CfHtml(html));
            if (png != null) Put(RegisterClipboardFormatW("PNG"), png);
            if (dib != null) Put(CfDib, dib);
            if (files.Count > 0) {
                Put(CfHdrop, DropFiles(files));
                Put(RegisterClipboardFormatW("Preferred DropEffect"), BitConverter.GetBytes(1)); // copy
            }
            return true;
        });
    }

    public ClipSnapshot Read() {
        byte[] dib = null;
        var snap = OnClipboardThread(() => {
            var s = new ClipSnapshot();
            var text = Get(CfUnicodeText, 64L * 1024 * 1024);
            if (text != null) { var t = Encoding.Unicode.GetString(text); int z = t.IndexOf('\0'); s.Text = z >= 0 ? t[..z] : t; }
            var html = Get(RegisterClipboardFormatW("HTML Format"), 64L * 1024 * 1024);
            if (html != null) s.Html = HtmlFragment(html);
            s.Png = Get(RegisterClipboardFormatW("PNG"));
            if (s.Png == null || s.Png.Length < 24) { s.Png = null; dib = Get(CfDibV5) ?? Get(CfDib); }
            if (IsClipboardFormatAvailable(CfHdrop)) {
                IntPtr drop = GetClipboardData(CfHdrop);
                if (drop != IntPtr.Zero) {
                    uint count = Math.Min(DragQueryFileW(drop, 0xFFFFFFFF, null, 0), 256u);
                    for (uint i = 0; i < count; i++) {
                        uint length = DragQueryFileW(drop, i, null, 0);
                        var buffer = new char[length + 1];
                        if (DragQueryFileW(drop, i, buffer, length + 1) > 0) s.Files.Add(new string(buffer, 0, (int)length));
                    }
                }
            }
            return s;
        });
        // Encoding happens after the clipboard is closed so other apps are not blocked.
        if (snap.Png == null && dib != null) snap.Png = DibToPng(dib);
        if (snap.Png != null && snap.Png.Length >= 24) { snap.Width = BigEndian(snap.Png, 16); snap.Height = BigEndian(snap.Png, 20); }
        if (string.IsNullOrEmpty(snap.Text)) snap.Text = null;
        if (string.IsNullOrWhiteSpace(snap.Html)) snap.Html = null;
        return snap;
    }

    // ---------- Formats ----------
    internal static byte[] CfHtml(string html) {
        const string start = "<!--StartFragment-->", end = "<!--EndFragment-->";
        string body = html;
        int s = body.IndexOf(start, StringComparison.OrdinalIgnoreCase), e = body.IndexOf(end, StringComparison.OrdinalIgnoreCase);
        if (s < 0 || e < s) {
            var match = Regex.Match(body, "<body[^>]*>(.*)</body>", RegexOptions.Singleline | RegexOptions.IgnoreCase);
            string inner = match.Success ? match.Groups[1].Value : body;
            body = "<html><body>\r\n" + start + inner + end + "\r\n</body></html>";
            s = body.IndexOf(start, StringComparison.Ordinal); e = body.IndexOf(end, StringComparison.Ordinal);
        }
        const string header = "Version:0.9\r\nStartHTML:{0:D10}\r\nEndHTML:{1:D10}\r\nStartFragment:{2:D10}\r\nEndFragment:{3:D10}\r\n";
        int headerLength = string.Format(header, 0, 0, 0, 0).Length;
        var bytes = Encoding.UTF8.GetBytes(body);
        int fragmentStart = Encoding.UTF8.GetByteCount(body[..(s + start.Length)]);
        int fragmentEnd = Encoding.UTF8.GetByteCount(body[..e]);
        var head = Encoding.ASCII.GetBytes(string.Format(header, headerLength, headerLength + bytes.Length, headerLength + fragmentStart, headerLength + fragmentEnd));
        var result = new byte[head.Length + bytes.Length + 1];
        head.CopyTo(result, 0); bytes.CopyTo(result, head.Length);
        return result;
    }

    internal static string HtmlFragment(byte[] data) {
        int length = Array.IndexOf(data, (byte)0); if (length < 0) length = data.Length;
        string header = Encoding.ASCII.GetString(data, 0, Math.Min(length, 400));
        int Offset(string name) { var m = Regex.Match(header, name + @":(-?\d+)"); return m.Success ? int.Parse(m.Groups[1].Value) : -1; }
        int fs = Offset("StartFragment"), fe = Offset("EndFragment");
        if (fs >= 0 && fe > fs && fe <= length) return Encoding.UTF8.GetString(data, fs, fe - fs);
        int sh = Offset("StartHTML");
        return sh >= 0 && sh < length ? Encoding.UTF8.GetString(data, sh, length - sh) : null;
    }

    internal static byte[] DropFiles(List<string> files) {
        var names = Encoding.Unicode.GetBytes(string.Join("\0", files) + "\0\0");
        var result = new byte[20 + names.Length];
        BitConverter.GetBytes(20).CopyTo(result, 0);  // pFiles
        BitConverter.GetBytes(1).CopyTo(result, 16);  // fWide
        names.CopyTo(result, 20);
        return result;
    }

    private static string DropRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "PhoneClipboard");

    // ---------- PNG <-> DIB ----------
    private static int BigEndian(byte[] b, int i) => b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3];
    private static readonly uint[] crcTable = Enumerable.Range(0, 256).Select(n => {
        uint c = (uint)n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; return c;
    }).ToArray();
    private static uint Crc(byte[] type, byte[] data) {
        uint c = 0xFFFFFFFF;
        foreach (var b in type) c = crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
        foreach (var b in data) c = crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFF;
    }
    private static void Chunk(Stream s, string type, byte[] data) {
        var t = Encoding.ASCII.GetBytes(type);
        void Int(uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
        Int((uint)data.Length); s.Write(t); s.Write(data); Int(Crc(t, data));
    }

    public static byte[] EncodePng(byte[] rgba, int width, int height) {
        using var output = new MemoryStream();
        output.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var ihdr = new byte[13];
        ihdr[0] = (byte)(width >> 24); ihdr[1] = (byte)(width >> 16); ihdr[2] = (byte)(width >> 8); ihdr[3] = (byte)width;
        ihdr[4] = (byte)(height >> 24); ihdr[5] = (byte)(height >> 16); ihdr[6] = (byte)(height >> 8); ihdr[7] = (byte)height;
        ihdr[8] = 8; ihdr[9] = 6;
        Chunk(output, "IHDR", ihdr);
        using var raw = new MemoryStream();
        using (var z = new ZLibStream(raw, CompressionLevel.Fastest, true))
            for (int y = 0; y < height; y++) { z.WriteByte(0); z.Write(rgba, y * width * 4, width * 4); }
        Chunk(output, "IDAT", raw.ToArray());
        Chunk(output, "IEND", Array.Empty<byte>());
        return output.ToArray();
    }

    // Decodes the 8-bit, non-interlaced PNGs a browser canvas produces, then
    // flattens transparency onto white for apps that read only CF_DIB.
    public static byte[] PngToDib(byte[] png) {
        try {
            if (png == null || png.Length < 33 || BigEndian(png, 0) != unchecked((int)0x89504E47)) return null;
            int pos = 8, width = 0, height = 0, depth = 0, color = 0, interlace = 0;
            using var idat = new MemoryStream();
            while (pos + 8 <= png.Length) {
                int length = BigEndian(png, pos); string type = Encoding.ASCII.GetString(png, pos + 4, 4);
                if (length < 0 || pos + 12 + length > png.Length) return null;
                if (type == "IHDR") { width = BigEndian(png, pos + 8); height = BigEndian(png, pos + 12); depth = png[pos + 16]; color = png[pos + 17]; interlace = png[pos + 20]; }
                else if (type == "IDAT") idat.Write(png, pos + 8, length);
                else if (type == "IEND") break;
                pos += 12 + length;
            }
            int channels = color switch { 0 => 1, 2 => 3, 4 => 2, 6 => 4, _ => 0 };
            if (depth != 8 || interlace != 0 || channels == 0 || width <= 0 || height <= 0 || (long)width * height > 64_000_000) return null;
            int stride = width * channels;
            var raw = new byte[(long)height * (stride + 1)];
            idat.Position = 0;
            using (var z = new ZLibStream(idat, CompressionMode.Decompress)) z.ReadExactly(raw);
            var prev = new byte[stride]; var row = new byte[stride];
            var dib = new byte[40 + (long)width * height * 4];
            BitConverter.GetBytes(40).CopyTo(dib, 0); BitConverter.GetBytes(width).CopyTo(dib, 4); BitConverter.GetBytes(height).CopyTo(dib, 8);
            BitConverter.GetBytes((short)1).CopyTo(dib, 12); BitConverter.GetBytes((short)32).CopyTo(dib, 14);
            BitConverter.GetBytes(width * height * 4).CopyTo(dib, 20);
            for (int y = 0; y < height; y++) {
                int src = y * (stride + 1); byte filter = raw[src];
                for (int x = 0; x < stride; x++) {
                    int a = x >= channels ? row[x - channels] : 0, b = prev[x], c = x >= channels ? prev[x - channels] : 0;
                    int v = raw[src + 1 + x];
                    v += filter switch {
                        0 => 0, 1 => a, 2 => b, 3 => (a + b) / 2,
                        4 => Paeth(a, b, c), _ => throw new InvalidDataException()
                    };
                    row[x] = (byte)v;
                }
                int dst = 40 + (height - 1 - y) * width * 4;
                for (int x = 0; x < width; x++) {
                    int i = x * channels; byte r, g, bl, al;
                    switch (channels) {
                        case 1: r = g = bl = row[i]; al = 255; break;
                        case 2: r = g = bl = row[i]; al = row[i + 1]; break;
                        case 3: r = row[i]; g = row[i + 1]; bl = row[i + 2]; al = 255; break;
                        default: r = row[i]; g = row[i + 1]; bl = row[i + 2]; al = row[i + 3]; break;
                    }
                    dib[dst++] = Over(bl, al); dib[dst++] = Over(g, al); dib[dst++] = Over(r, al); dib[dst++] = 255;
                }
                (prev, row) = (row, prev);
            }
            return dib;
        } catch { return null; }
    }
    private static byte Over(byte c, byte a) => (byte)((c * a + 255 * (255 - a) + 127) / 255);
    private static int Paeth(int a, int b, int c) { int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }

    public static byte[] DibToPng(byte[] d) {
        try {
            int headerSize = BitConverter.ToInt32(d, 0), width = BitConverter.ToInt32(d, 4), rawHeight = BitConverter.ToInt32(d, 8);
            int bpp = BitConverter.ToInt16(d, 14), compression = BitConverter.ToInt32(d, 16), used = BitConverter.ToInt32(d, 32);
            int height = Math.Abs(rawHeight); bool topDown = rawHeight < 0;
            if (headerSize < 40 || width <= 0 || height <= 0 || (long)width * height > 64_000_000) return null;
            uint rm = 0x00FF0000, gm = 0x0000FF00, bm = 0x000000FF, am = 0;
            int offset = headerSize;
            if (compression == 3 || compression == 6) {
                if (headerSize >= 52) { rm = BitConverter.ToUInt32(d, 40); gm = BitConverter.ToUInt32(d, 44); bm = BitConverter.ToUInt32(d, 48); am = headerSize >= 56 ? BitConverter.ToUInt32(d, 52) : 0; }
                else { rm = BitConverter.ToUInt32(d, offset); gm = BitConverter.ToUInt32(d, offset + 4); bm = BitConverter.ToUInt32(d, offset + 8); offset += compression == 6 ? 16 : 12; }
                if (bpp != 16 && bpp != 32) return null;
            } else if (compression != 0) return null;
            else if (bpp == 16) { rm = 0x7C00; gm = 0x03E0; bm = 0x001F; }
            else if (bpp == 32) am = 0xFF000000;
            uint[] palette = null;
            if (bpp <= 8) {
                int colors = used != 0 ? used : 1 << bpp;
                palette = new uint[colors];
                for (int i = 0; i < colors; i++) palette[i] = BitConverter.ToUInt32(d, offset + i * 4);
                offset += colors * 4;
            } else if (bpp != 16 && bpp != 24 && bpp != 32) return null;
            int stride = (width * bpp + 31) / 32 * 4;
            if (offset + (long)stride * height > d.Length) return null;
            var rgba = new byte[(long)width * height * 4];
            static byte Channel(uint v, uint mask) {
                if (mask == 0) return 0;
                int shift = System.Numerics.BitOperations.TrailingZeroCount(mask), bits = System.Numerics.BitOperations.PopCount(mask);
                uint value = (v & mask) >> shift;
                return bits >= 8 ? (byte)(value >> (bits - 8)) : (byte)(value * 255 / ((1u << bits) - 1));
            }
            bool anyAlpha = false;
            for (int y = 0; y < height; y++) {
                int src = offset + (topDown ? y : height - 1 - y) * stride, dst = y * width * 4;
                for (int x = 0; x < width; x++, dst += 4) {
                    uint b, g, r, a = 255;
                    if (bpp == 24) { b = d[src + x * 3]; g = d[src + x * 3 + 1]; r = d[src + x * 3 + 2]; }
                    else if (bpp == 32 || bpp == 16) {
                        uint v = bpp == 32 ? BitConverter.ToUInt32(d, src + x * 4) : BitConverter.ToUInt16(d, src + x * 2);
                        r = Channel(v, rm); g = Channel(v, gm); b = Channel(v, bm); a = am == 0 ? 255u : Channel(v, am);
                    } else {
                        int bit = x * bpp; int index = (d[src + bit / 8] >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1);
                        uint p = index < palette.Length ? palette[index] : 0; b = p & 0xFF; g = (p >> 8) & 0xFF; r = (p >> 16) & 0xFF;
                    }
                    if (a != 0) anyAlpha = true;
                    rgba[dst] = (byte)r; rgba[dst + 1] = (byte)g; rgba[dst + 2] = (byte)b; rgba[dst + 3] = (byte)a;
                }
            }
            // Many apps leave the alpha byte of 32-bit DIBs at zero: treat that as opaque.
            if (!anyAlpha) for (long i = 3; i < rgba.Length; i += 4) rgba[i] = 255;
            return EncodePng(rgba, width, height);
        } catch { return null; }
    }
}
