using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ThreeE.PhoneControl;
using ThreeE.PhoneBar.Windows;

// Phone keyboard commands, file-name safety and the Windows clipboard formats.
// Pure conversions only: nothing touches the real clipboard or injects keys.
static class ClipboardTests {
    public static void Run(Action<bool,string> check) {
        var fake = new FakeInput();
        void Apply(string json) { using var parsed = JsonDocument.Parse(json); PhoneTrackpad.Apply(parsed.RootElement, fake); }
        Apply("{\"type\":\"text\",\"text\":\"héllo 👋\"}"); Apply("{\"type\":\"key\",\"id\":0,\"n\":3}"); Apply("{\"type\":\"key\",\"id\":11}");
        check(fake.Commands.Contains("text:héllo 👋") && fake.Commands.Contains("key:0x3") && fake.Commands.Contains("key:11x1"), "Phone keyboard text and palette keys reach the native boundary");
        foreach (var bad in new[] { "{\"type\":\"text\",\"text\":\"\"}", "{\"type\":\"text\",\"text\":\"" + new string('a', 257) + "\"}", "{\"type\":\"text\",\"text\":5}",
                                    "{\"type\":\"key\",\"id\":12}", "{\"type\":\"key\",\"id\":-1}", "{\"type\":\"key\",\"id\":0,\"n\":65}", "{\"type\":\"key\",\"id\":0,\"n\":0}" }) {
            bool rejected = false; try { Apply(bad); } catch (InvalidDataException) { rejected = true; }
            check(rejected, "Invalid keyboard command rejected: " + (bad.Length > 48 ? bad[..48] + "…" : bad));
        }

        check(PhoneClipboard.SafeName("../../evil:name?.pdf") == "evil_name_.pdf" && PhoneClipboard.SafeName(@"C:\x\CON.txt") == "_CON.txt" && PhoneClipboard.SafeName("  .. ") == "Phone file",
            "Phone file names cannot leave the transfer folder or use reserved names");
        var folder = Directory.CreateTempSubdirectory().FullName;
        var first = PhoneClipboard.SaveFile(folder, "a.pdf", new byte[] { 1 }); var second = PhoneClipboard.SaveFile(folder, "a.pdf", new byte[] { 2 });
        check(Path.GetFileName(second) == "a (2).pdf" && File.ReadAllBytes(first)[0] == 1, "Repeated file names get a numbered copy instead of overwriting");

        // PNG <-> DIB, including alpha flattened onto white for CF_DIB readers.
        int w = 7, h = 5; var rgba = new byte[w * h * 4];
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { int i = (y * w + x) * 4; rgba[i] = (byte)(x * 30); rgba[i + 1] = (byte)(y * 50); rgba[i + 2] = 99; rgba[i + 3] = (byte)(x == 0 ? 0 : 255); }
        var png = WindowsPhoneClipboard.EncodePng(rgba, w, h);
        var dib = WindowsPhoneClipboard.PngToDib(png);
        int pixel = 40 + ((h - 1) * w + 3) * 4, clear = 40 + (h - 1) * w * 4;
        check(dib != null && BitConverter.ToInt32(dib, 4) == w && BitConverter.ToInt32(dib, 8) == h && dib[pixel] == 99 && dib[pixel + 2] == 90 && dib[clear] == 255 && dib[clear + 2] == 255,
            "Phone PNG becomes a bottom-up BGRA bitmap with transparency on white");
        check(WindowsPhoneClipboard.PngToDib(WindowsPhoneClipboard.DibToPng(dib)).AsSpan().SequenceEqual(dib) && PhoneClipboard.PngSize(png) == (w, h), "Windows bitmaps convert to PNG for the phone losslessly");
        var d32 = new byte[44]; BitConverter.GetBytes(40).CopyTo(d32, 0); BitConverter.GetBytes(1).CopyTo(d32, 4); BitConverter.GetBytes(1).CopyTo(d32, 8); BitConverter.GetBytes((short)32).CopyTo(d32, 14); d32[40] = 10; d32[41] = 20; d32[42] = 30;
        var p32 = WindowsPhoneClipboard.PngToDib(WindowsPhoneClipboard.DibToPng(d32));
        check(p32 != null && p32[40] == 10 && p32[42] == 30, "32-bit bitmaps whose alpha is unused stay visible");
        check(WindowsPhoneClipboard.PngToDib(Encoding.ASCII.GetBytes("not a png, definitely not a png!!")) == null, "Non-PNG picture data is refused");

        var cf = WindowsPhoneClipboard.CfHtml("<meta charset='utf-8'><b>Héllo</b> wörld");
        var header = Encoding.UTF8.GetString(cf);
        int Offset(string key) => int.Parse(Regex.Match(header, key + @":(\d+)").Groups[1].Value);
        check(Encoding.UTF8.GetString(cf, Offset("StartFragment"), Offset("EndFragment") - Offset("StartFragment")) == "<meta charset='utf-8'><b>Héllo</b> wörld"
            && Encoding.UTF8.GetString(cf, Offset("StartHTML"), 6) == "<html>" && Offset("EndHTML") == cf.Length - 1, "CF_HTML offsets count UTF-8 bytes");
        check(WindowsPhoneClipboard.HtmlFragment(cf) == "<meta charset='utf-8'><b>Héllo</b> wörld"
            && WindowsPhoneClipboard.HtmlFragment(WindowsPhoneClipboard.CfHtml("<html><body>\n<p>x</p>\n</body></html>")) == "\n<p>x</p>\n", "Copied HTML fragments are read back exactly");
        var drop = WindowsPhoneClipboard.DropFiles(new List<string> { @"C:\a.pdf", @"C:\b c.txt" });
        check(BitConverter.ToInt32(drop, 0) == 20 && BitConverter.ToInt32(drop, 16) == 1 && Encoding.Unicode.GetString(drop, 20, drop.Length - 20) == "C:\\a.pdf\0C:\\b c.txt\0\0", "Files are offered to Explorer as a wide DROPFILES list");
    }
}

// In-memory clipboard for the receiver and browser tests.
sealed class FakeClipboard : IPhoneClipboard {
    public List<ClipPart> Written;
    public ClipSnapshot Snapshot = new();
    public void Write(IReadOnlyList<ClipPart> parts) => Written = parts.ToList();
    public ClipSnapshot Read() => Snapshot;
}
