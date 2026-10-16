// SPDX-License-Identifier: MIT
using Windows.Media.Control;

namespace ThreeE.PhoneBar.Windows;

// Cached off the input thread: a stalled media provider must not stall touch.
internal sealed class PhoneMediaState : IDisposable {
    private readonly CancellationTokenSource stop = new();
    private object state = new { playing=(bool?)null, source="music", stop=false };
    public object State => Volatile.Read(ref state);
    public PhoneMediaState() { _=Task.Run(Poll); }
    private async Task Poll() {
        try {
            var manager=await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            while(!stop.IsCancellationRequested) {
                object next=new { playing=(bool?)null,source="music",stop=false };
                try {
                    var session=manager.GetCurrentSession();
                    if(session!=null) {
                        var status=session.GetPlaybackInfo().PlaybackStatus;
                        bool? playing=status==GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing ? true :
                            status is GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused or GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped ? false : null;
                        string app=session.SourceAppUserModelId?.ToLowerInvariant() ?? "";
                        string source=app.Contains("spotify")?"spotify":app.Contains("ableton")?"ableton":app.Contains("chrome")||app.Contains("msedge")||app.Contains("firefox")?"browser":"music";
                        next=new { playing,source,stop=source=="ableton" };
                    }
                } catch { }
                Volatile.Write(ref state,next);
                await Task.Delay(750,stop.Token);
            }
        } catch { /* No media provider leaves the neutral music/play icon. */ }
    }
    public void Dispose() => stop.Cancel();
}
