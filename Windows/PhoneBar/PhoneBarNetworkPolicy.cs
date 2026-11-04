// SPDX-License-Identifier: MIT
using System.Text.Json;

namespace ThreeE.PhoneBar.Windows;

// A deployment policy is separate from the user's on/off preference. The menu
// cannot turn inbound access back on when the host is configured local-only.
public static class PhoneBarNetworkPolicy {
    public static string PolicyPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "network-policy.json");
    public const string RestrictedStatus = "Phone Bar is disabled by this computer's network policy.";
    public static bool AllowsInbound(string path = null) {
        path ??= PolicyPath;
        try {
            using var file = File.OpenRead(path);
            using var document = JsonDocument.Parse(file);
            return document.RootElement.GetProperty("mode").GetString() == "allow-inbound";
        } catch (FileNotFoundException) { return true; }
        catch (DirectoryNotFoundException) { return true; }
        catch { return false; }
    }
}
