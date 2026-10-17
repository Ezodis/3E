// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

public enum MediaAction { Play, Pause, Stop, Toggle, Previous, Next }
public sealed record MediaSession(object Id, string App, int Playback, Func<MediaAction,CancellationToken,Task<bool>> Send);
public sealed record MediaSources(IReadOnlyList<MediaSession> Sessions, object Preferred);

// Mirrors TouchBar's PlaybackBook: newest playing source, then the last player.
// Only acknowledged commands override a provider's briefly stale state.
public sealed class MediaRouter {
    private sealed class Entry { public int State=-1; public long Order,Settle; }
    private sealed record Display(MediaSession Session,int Playback,object View);
    private readonly Dictionary<object,Entry> sources=new();
    private readonly SemaphoreSlim gate=new(1,1);
    private readonly Func<MediaSources> read;
    private readonly Func<string,string> icon;
    private readonly Func<long> clock;
    private long sequence;
    private object last,preferred;
    private int pending;
    // Skips are cumulative: swipes made while a slow provider is still answering
    // are queued (a few at most) instead of dropped. Play/pause taps that arrive
    // while one is pending are still ignored so a source never toggles twice.
    private readonly System.Collections.Concurrent.ConcurrentQueue<int> queuedSkips=new();
    private Display display=new(null,-1,new {playing=(bool?)null,artwork="",stop=false});
    public object State=>Volatile.Read(ref display).View;
    public MediaRouter(Func<MediaSources> read,Func<string,string> icon,Func<long> clock=null) {
        this.read=read;this.icon=icon;this.clock=clock??(()=>Environment.TickCount64);
    }
    private void Refresh() {
        var snapshot=read();var sessions=snapshot.Sessions;
        var alive=sessions.Select(s=>s.Id).ToHashSet();
        foreach(var id in sources.Keys.Where(id=>!alive.Contains(id)).ToArray())sources.Remove(id);
        foreach(var session in sessions) {
            if(!sources.TryGetValue(session.Id,out var entry))sources[session.Id]=entry=new();
            if(session.Playback<0||(entry.Settle>clock()&&entry.State!=session.Playback))continue;
            if(session.Playback==1&&entry.State!=1)entry.Order=++sequence;
            entry.State=session.Playback;
        }
        if(!Equals(preferred,snapshot.Preferred)) {
            preferred=snapshot.Preferred;
            if(preferred!=null&&sources.TryGetValue(preferred,out var p)&&p.State==1)p.Order=++sequence;
        }
        var target=sessions.Where(s=>sources[s.Id].State==1).OrderByDescending(s=>sources[s.Id].Order).FirstOrDefault()
            ?? sessions.FirstOrDefault(s=>Equals(s.Id,last))
            ?? sessions.FirstOrDefault(s=>Equals(s.Id,preferred)) ?? sessions.FirstOrDefault();
        if(target==null){last=null;Volatile.Write(ref display,new(null,-1,new {playing=(bool?)null,artwork="",stop=false}));return;}
        last=target.Id;int playback=sources[target.Id].State;
        bool stop=target.App.Contains("ableton",StringComparison.OrdinalIgnoreCase);
        Volatile.Write(ref display,new(target,playback,new {playing=playback<0?(bool?)null:playback==1,artwork=icon(target.App),stop}));
    }
    public async Task RefreshAsync(CancellationToken token=default) {
        await gate.WaitAsync(token);
        try { Refresh(); } finally { gate.Release(); }
    }
    public async Task SendAsync(int action,CancellationToken token=default) {
        // Capture the displayed source before scheduling; never route to a different
        // player just because the OS's preferred session changed during this tap.
        var selected=Volatile.Read(ref display);
        if(action<0||action>2||selected.Session==null)return;
        if(Interlocked.CompareExchange(ref pending,1,0)!=0) { if(action!=0&&queuedSkips.Count<4)queuedSkips.Enqueue(action); return; }
        try {
            await Task.Yield(); // Native providers must never run inside the input lock.
            await gate.WaitAsync(token);
            try {
                if(!read().Sessions.Any(s=>Equals(s.Id,selected.Session.Id))) { Refresh();return; }
                bool stop=selected.Session.App.Contains("ableton",StringComparison.OrdinalIgnoreCase);
                var command=action==1?MediaAction.Previous:action==2?MediaAction.Next:
                    selected.Playback==1?(stop?MediaAction.Stop:MediaAction.Pause):selected.Playback==0?MediaAction.Play:MediaAction.Toggle;
                bool sent=await selected.Session.Send(command,token);
                if(sent&&action==0&&selected.Playback>=0&&sources.TryGetValue(selected.Session.Id,out var entry)) {
                    entry.State=selected.Playback==1?0:1;entry.Settle=clock()+1000;
                    if(entry.State==1)entry.Order=++sequence;
                    last=selected.Session.Id;
                }
                Refresh();
            } finally { gate.Release(); }
        } finally {
            Volatile.Write(ref pending,0);
            if(queuedSkips.TryDequeue(out var next))_=SendAsync(next,token);
        }
    }
}
