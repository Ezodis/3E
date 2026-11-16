// SPDX-License-Identifier: MIT
// Vendor skin images for the 3£ Mouse window. 3£ does not ship the vendor's artwork (the repo is
// public): it copies the skins from the user's own copy of the vendor app (installed folder,
// the vendor zip, or a skins folder) into %LOCALAPPDATA%\3EWindows\Mouse\skins\<device>.
// Without them the window draws a look-alike with the same layout.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace ThreeE.Mouse;

public sealed class VendorSkin {
    public string Folder { get; }
    VendorSkin(string folder) => Folder = folder;

    public static string Store(string deviceId) =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "Mouse", "skins", deviceId);

    /// The imported skin for this device, or null.
    public static VendorSkin Load(string deviceId, string probeFile) {
        var dir = Store(deviceId);
        return File.Exists(Path.Combine(dir, probeFile)) ? new VendorSkin(dir) : null;
    }

    public string PathOf(string relative) {
        var p = Path.Combine(Folder, relative.Replace('\\', Path.DirectorySeparatorChar));
        return File.Exists(p) ? p : null;
    }

    /// Imports from a skins folder, a vendor app folder, or a zip containing one. Returns the skin or throws.
    public static VendorSkin Import(string deviceId, string source, string probeFile) {
        var target = Store(deviceId);
        string tmp = target + ".new";
        if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
        Directory.CreateDirectory(tmp);
        try {
            if (File.Exists(source) && source.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) {
                using var zip = ZipFile.OpenRead(source);
                var probe = zip.Entries.FirstOrDefault(e => e.FullName.Replace('\\', '/').EndsWith("skins/" + probeFile, StringComparison.OrdinalIgnoreCase))
                    ?? throw new FileNotFoundException("No vendor skins (skins/" + probeFile + ") in " + Path.GetFileName(source));
                string prefix = probe.FullName.Replace('\\', '/')[..^probeFile.Length];
                foreach (var e in zip.Entries) {
                    var name = e.FullName.Replace('\\', '/');
                    if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || name.EndsWith("/")) continue;
                    var rel = name[prefix.Length..];
                    if (rel.Contains("..") || !IsImage(rel)) continue;
                    var dest = Path.Combine(tmp, rel.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    e.ExtractToFile(dest, true);
                }
            } else {
                var skins = Directory.Exists(Path.Combine(source, "skins")) ? Path.Combine(source, "skins") : source;
                if (!File.Exists(Path.Combine(skins, probeFile))) throw new FileNotFoundException("No vendor skins (" + probeFile + ") in " + source);
                foreach (var f in Directory.EnumerateFiles(skins, "*", SearchOption.AllDirectories)) {
                    var rel = Path.GetRelativePath(skins, f);
                    if (!IsImage(rel)) continue;
                    var dest = Path.Combine(tmp, rel);
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    File.Copy(f, dest, true);
                }
            }
            if (Directory.Exists(target)) Directory.Delete(target, true);
            Directory.Move(tmp, target);
            return new VendorSkin(target);
        } catch {
            try { Directory.Delete(tmp, true); } catch { }
            throw;
        }
    }

    static bool IsImage(string rel) => rel.EndsWith(".png", StringComparison.OrdinalIgnoreCase) || rel.EndsWith(".bmp", StringComparison.OrdinalIgnoreCase);

    /// Places a copy of the vendor app may already be on this PC (never installs or runs anything).
    public static IEnumerable<string> Candidates(IEnumerable<string> vendorFolderNames) {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var roots = new[] { Path.Combine(home, "source"), Path.Combine(home, "Downloads"), Path.Combine(home, "Desktop"), Path.Combine(home, "Documents") };
        foreach (var root in roots.Where(Directory.Exists)) {
            IEnumerable<string> zips;
            try { zips = Directory.EnumerateFiles(root, "*.zip", new EnumerationOptions { RecurseSubdirectories = true, MaxRecursionDepth = 2, IgnoreInaccessible = true }).ToList(); }
            catch { continue; }
            foreach (var z in zips)
                if (vendorFolderNames.Any(n => Path.GetFileNameWithoutExtension(z).Contains(n, StringComparison.OrdinalIgnoreCase))) yield return z;
        }
        foreach (var pf in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) }.Where(Directory.Exists))
            foreach (var n in vendorFolderNames) {
                var d = Path.Combine(pf, n);
                if (Directory.Exists(d)) yield return d;
            }
    }

    /// Imports the first candidate that contains the skins, or returns null.
    public static VendorSkin AutoImport(string deviceId, string probeFile, IEnumerable<string> vendorFolderNames) {
        foreach (var c in Candidates(vendorFolderNames)) {
            try { return Import(deviceId, c, probeFile); } catch { }
        }
        return null;
    }
}
