// SPDX-License-Identifier: MIT
using System.Text.Json;

namespace ThreeE.PhoneBar.Windows;

public enum PhoneBarAccess { Blocked, UsbOnly, Full }

// A deployment policy is separate from the user's on/off preference. The menu
// cannot turn network-wide inbound access back on when the host is configured
// local-only. Local-only still allows a phone plugged in by cable: the
// listener, firewall rule and accepted adapter are then limited to that USB link.
public static class PhoneBarNetworkPolicy {
    public static string PolicyPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "network-policy.json");
    public const string RestrictedStatus = "Track Phone is disabled by this computer's network policy.";
    public const string UsbOnlyStatus = "Waiting for USB\nConnect your iPhone with Personal Hotspot on, then scan.";
    // "allow-inbound" (or no file): any local network. "local-only"/"usb-only":
    // USB cable only. "none", anything else or an unreadable file: off.
    public static PhoneBarAccess Access(string path = null) {
        path ??= PolicyPath;
        try {
            using var file = File.OpenRead(path);
            using var document = JsonDocument.Parse(file);
            return document.RootElement.GetProperty("mode").GetString() switch {
                "allow-inbound" => PhoneBarAccess.Full,
                "local-only" or "usb-only" => PhoneBarAccess.UsbOnly,
                _ => PhoneBarAccess.Blocked
            };
        } catch (FileNotFoundException) { return PhoneBarAccess.Full; }
        catch (DirectoryNotFoundException) { return PhoneBarAccess.Full; }
        catch { return PhoneBarAccess.Blocked; }
    }
    public static bool AllowsInbound(string path = null) => Access(path) == PhoneBarAccess.Full;
}
