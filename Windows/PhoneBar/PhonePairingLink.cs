// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneBar.Windows;

public static class PhonePairingLink {
    // USB name discovery is not reliable on every iPhone/Windows combination.
    // Use the active receiver address and keep the web page from promoting it
    // back to .local. A saved name is not a usable USB QR while disconnected.
    public static string ForQr(string direct, string named, bool usbOnly) {
        if (!usbOnly) return named ?? direct;
        if (direct == null) return null;
        return new UriBuilder(direct) { Query = "usb=1" }.Uri.AbsoluteUri;
    }
}
