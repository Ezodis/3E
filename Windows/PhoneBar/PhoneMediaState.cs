// SPDX-License-Identifier: MIT
using Windows.Media.Control;
using Windows.ApplicationModel;
using Windows.Storage.Streams;
using System.Drawing;
using System.Drawing.Imaging;
using ThreeE.PhoneControl;

namespace ThreeE.PhoneBar.Windows;

// All provider calls and commands run off the pointer input thread.
internal sealed class PhoneMediaState : IDisposable {
    private readonly CancellationTokenSource stop = new();
    private readonly Dictionary<string,Task<string>> icons = new(StringComparer.Ordinal);
    private readonly MediaRouter router;
    private GlobalSystemMediaTransportControlsSessionManager manager;
    public object State => router.State;
    public PhoneMediaState() {
        router=new(ReadSources,AppIcon);
        _=Task.Run(Poll);
    }
    private MediaSources ReadSources() {
        if(manager==null)return new(Array.Empty<MediaSession>(),null);
        var sessions=new List<MediaSession>();
        foreach(var session in manager.GetSessions()) {
            try {
                var status=session.GetPlaybackInfo().PlaybackStatus;
                int state=status==GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing?1:
                    status is GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused or GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped?0:-1;
                sessions.Add(new(session,session.SourceAppUserModelId??"",state,(action,token)=>Send(session,action,token)));
            } catch { /* An exited provider cannot receive commands. */ }
        }
        return new(sessions,manager.GetCurrentSession());
    }
    private static async Task<bool> Send(GlobalSystemMediaTransportControlsSession session,MediaAction action,CancellationToken token) {
        var request=action switch {
            MediaAction.Play=>session.TryPlayAsync(),
            MediaAction.Pause=>session.TryPauseAsync(),
            MediaAction.Stop=>session.TryStopAsync(),
            MediaAction.Previous=>session.TrySkipPreviousAsync(),
            MediaAction.Next=>session.TrySkipNextAsync(),
            _=>session.TryTogglePlayPauseAsync()
        };
        return await request.AsTask(token);
    }
    public void Send(int action) {
        _=SendCommand(action);
    }
    private async Task SendCommand(int action) {
        try {
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
            timeout.CancelAfter(2000);
            await router.SendAsync(action,timeout.Token);
        } catch { /* Never fall back to a broadcast key that controls a different source. */ }
    }
    private async Task Poll() {
        try {
            manager=await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            while(!stop.IsCancellationRequested) {
                try { await router.RefreshAsync(stop.Token); } catch { }
                await Task.Delay(500,stop.Token);
            }
        } catch { /* No media provider leaves only the playback icon. */ }
    }
    private string AppIcon(string app) {
        if(string.IsNullOrEmpty(app))return "";
        // The router serializes this dictionary. Lookup tasks cache success/failure,
        // and never delay media commands or pointer input. No process/network scan.
        if(!icons.TryGetValue(app,out var task)) {
            if(icons.Count>=32)return "";
            icons[app]=task=Task.Run(()=>LoadIcon(app));
        }
        return task.IsCompletedSuccessfully?task.Result:"";
    }
    private async Task<string> LoadIcon(string app) {
        try {
            var info=AppInfo.GetFromAppUserModelId(app);
            if(info==null)return ""; // Classic apps may not expose a registered logo.
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
            timeout.CancelAfter(1500);
            using var stream=await info.DisplayInfo.GetLogo(new global::Windows.Foundation.Size(48,48)).OpenReadAsync().AsTask(timeout.Token);
            if(stream.Size==0||stream.Size>256*1024)return "";
            using var reader=new DataReader(stream);
            uint count=(uint)stream.Size;
            if(await reader.LoadAsync(count).AsTask(timeout.Token)!=count)return "";
            var bytes=new byte[count];reader.ReadBytes(bytes);
            using var input=new MemoryStream(bytes);
            using var original=Image.FromStream(input);
            using var thumbnail=new Bitmap(48,48);
            using(var graphics=Graphics.FromImage(thumbnail)) {
                double scale=Math.Min(48d/original.Width,48d/original.Height);
                int width=Math.Max(1,(int)(original.Width*scale)),height=Math.Max(1,(int)(original.Height*scale));
                graphics.DrawImage(original,(48-width)/2,(48-height)/2,width,height);
            }
            using var output=new MemoryStream();thumbnail.Save(output,ImageFormat.Png);
            string value="data:image/png;base64,"+Convert.ToBase64String(output.ToArray());
            if(value.Length<32768)return value;
        } catch { /* An unavailable logo is optional, and is cached as absent. */ }
        return "";
    }
    public void Dispose() => stop.Cancel();
}
