// SPDX-License-Identifier: MIT
using System.Diagnostics;
using System.Net.NetworkInformation;
using ThreeE.PhoneControl;

namespace ThreeE.PhoneBar.Windows;

// iPhone USB tethering is a wired link, so Windows would otherwise prefer it
// over Wi-Fi and send the computer's Internet traffic through cellular data.
// Track Phone only needs the cable for the phone itself: give each USB phone
// link the lowest route priority, once per appearance (needs administrator).
public static class UsbRoutePriority {
    public const int Metric = 9000;
    private static readonly HashSet<string> applied = new();
    private static readonly object gate = new();

    public static void Ensure() {
        try {
            var usb = PhoneNetwork.Paths.Where(p => p.Kind == "usb").Select(p => p.Address).ToHashSet();
            var current = new HashSet<string>();
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) {
                if (n.OperationalStatus != OperationalStatus.Up) continue;
                var properties = n.GetIPProperties();
                if (!properties.UnicastAddresses.Any(a => usb.Contains(a.Address))) continue;
                current.Add(n.Id);
                lock (gate) if (!applied.Add(n.Id)) continue;
                int index;
                try { index = properties.GetIPv4Properties().Index; } catch { continue; }
                foreach (var family in new[] { "ipv4", "ipv6" }) Run($"interface {family} set interface {index} metric={Metric}");
            }
            // A replugged phone may come back as a new interface; forget gone ones.
            lock (gate) applied.IntersectWith(current);
        } catch { }
    }

    private static void Run(string arguments) {
        try {
            using var process = Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "netsh.exe"), arguments) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
            if (process != null && !process.WaitForExit(3000)) process.Kill();
        } catch { }
    }
}
