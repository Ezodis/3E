// SPDX-License-Identifier: MIT
using ThreeE.PhoneControl;

namespace ThreeE.PhoneBar.Windows;

// Included in the base suite; native input, network and popup lifetime belong
// to this module. Merely constructing the module opens no listener or MIDI port.
public sealed class PhoneBarModule : IDisposable {
    private PhoneTrackpad receiver;
    private PhoneTrackpadPopup popup;
    private bool disposed;
    public bool Running => receiver?.Running ?? false;
    public string Status => receiver?.Status ?? "Off";

    public void Show() {
        ObjectDisposedException.ThrowIf(disposed, this);
        receiver ??= new(PhoneTrackpad.GetLocalAddress,
            new NativeTrackpadInput(), new TrackpadFirewall(), PhoneTrackpad.Port);
        receiver.Start();
        popup ??= new(receiver);
        popup.Show();
    }

    public void Stop() {
        popup?.Dispose(); popup = null;
        receiver?.Stop();
    }

    public void Dispose() {
        if (disposed) return;
        disposed = true;
        Stop();
        receiver?.Dispose(); receiver = null;
    }
}
