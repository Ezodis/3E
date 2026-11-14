// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneBar.Windows;

public static class PhonePairingLink {
    // One permanent link, wired or wireless: http://3e-win.local:17833/#secret.
    // The name responder follows the active (USB or Wi-Fi) address, so the
    // link survives replugs and IP changes. Only when no name is available is
    // the raw address shown, pinned to the wired route on USB-only hosts.
    public static string ForQr(string direct, string named, bool usbOnly) {
        if (named != null) return named;
        if (direct == null) return null;
        return usbOnly ? new UriBuilder(direct) { Query = "usb=1" }.Uri.AbsoluteUri : direct;
    }
}
