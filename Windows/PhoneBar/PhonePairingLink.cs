// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneBar.Windows;

public static class PhonePairingLink {
    // USB name discovery is not reliable on every iPhone/Windows combination.
    // Use the active receiver address and keep the web page from promoting it
    // back to .local. Keep the saved pairing identity visible while waiting
    // for USB; the popup explains that the cable must connect before scanning.
    public static string ForQr(string direct, string named, bool usbOnly) {
        if (!usbOnly) return named ?? direct;
        var link = direct ?? named;
        return link == null ? null : new UriBuilder(link) { Query = "usb=1" }.Uri.AbsoluteUri;
    }
}
