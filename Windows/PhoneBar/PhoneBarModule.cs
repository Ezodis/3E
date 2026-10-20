// SPDX-License-Identifier: MIT
using ThreeE.PhoneControl;

namespace ThreeE.PhoneBar.Windows;

// Included in the base suite; native input, network and popup lifetime belong
// to this module. Merely constructing the module opens no listener or MIDI port.
public sealed class PhoneBarModule : IDisposable {
    private PhoneTrackpad receiver;
    private PhoneTrackpadPopup popup;
    private PhoneNameResponder name;
    private bool disposed;
    private readonly object nameGate = new();
    private PhoneMediaState media;
    private OutputVolume volume;
    public bool Running => receiver?.Running ?? false;
    public string Status => receiver?.Status ?? "Off";
    public string NamedUrl => receiver?.NamedUrl;
    private static string LinkPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "phone-link.txt");

    // The pairing secret is kept in the user's local profile so a phone's saved
    // link keeps working after restarts and updates. ResetLink() revokes it.
    private static string StoredToken() {
        try {
            if (File.Exists(LinkPath)) {
                var stored = File.ReadAllText(LinkPath).Trim();
                if (stored.Length == 48 && stored.All(Uri.IsHexDigit)) return stored;
            }
            var token = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(24));
            Directory.CreateDirectory(Path.GetDirectoryName(LinkPath));
            File.WriteAllText(LinkPath, token);
            return token;
        } catch { return null; }
    }

    private void EnsureReceiver() {
        ObjectDisposedException.ThrowIf(disposed, this);
        if(receiver==null)AbletonIntegration.Install();
        media ??= new();
        volume ??= new(WindowsOutputVolume.Read,WindowsOutputVolume.Write);
        receiver ??= new(PhoneTrackpad.GetLocalAddress,
            new NativeTrackpadInput(()=>new {media=media?.State},action=>media?.Send(action),()=>volume?.State,level=>volume?.Set(level),()=>volume?.CancelPending(),()=>volume?.Refresh()),
            new TrackpadFirewall(), PhoneTrackpad.Port) { TokenProvider = StoredToken, AliasHost = PhoneNameResponder.Name, FollowNetwork = true,
              PreferencesPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows", "phone-settings.json") };
        // The link stays http://3e-win.local:17833/#secret; when DHCP or a new
        // Wi-Fi changes the IP, the receiver rebinds and the name follows it.
        receiver.AddressChanged -= OnAddressChanged;
        receiver.AddressChanged += OnAddressChanged;
    }

    // Starts (or restarts after a network change) without showing the popup.
    public bool EnsureRunning() {
        EnsureReceiver();
        media ??= new();
        volume ??= new(WindowsOutputVolume.Read,WindowsOutputVolume.Write);
        bool running = receiver.Running || receiver.Start();
        if (running) PhonePowerTuning.Begin(); else PhonePowerTuning.End();
        UpdateName(running ? receiver.Address : null);
        return running;
    }

    private void OnAddressChanged() {
        var current = receiver;
        if (current == null || disposed) return;
        if (current.Running) PhonePowerTuning.Begin();
        UpdateName(current.Running ? current.Address : null);
    }

    private void UpdateName(System.Net.IPAddress address) {
        lock (nameGate) {
            if (address != null && name?.Address?.Equals(address) == true) return;
            name?.Dispose(); name = null;
            if (address == null) return;
            try { new TrackpadFirewall().OpenName(); } catch { }
            try { name = new PhoneNameResponder(address); } catch { /* The IP link keeps working without the name. */ }
        }
    }

    public void Show() {
        EnsureRunning();
        popup ??= new(receiver);
        popup.Show();
    }

    // Revokes the saved phone link; the next start issues a new QR code.
    public void ResetLink() {
        try { if (File.Exists(LinkPath)) File.Delete(LinkPath); } catch { }
        bool wasRunning = Running;
        Stop();
        if (wasRunning) EnsureRunning();
    }

    public void Stop() {
        popup?.Dispose(); popup = null;
        lock (nameGate) { name?.Dispose(); name = null; }
        receiver?.Stop();
        PhonePowerTuning.End();
        media?.Dispose(); media=null;
        volume?.Dispose(); volume=null;
    }

    public void Dispose() {
        if (disposed) return;
        disposed = true;
        Stop();
        receiver?.Dispose(); receiver = null;
        PhonePowerTuning.End();
    }
}
