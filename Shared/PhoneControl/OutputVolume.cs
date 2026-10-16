// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

// Audio drivers never run on the pointer thread. Rapid slider input replaces
// the pending value instead of queuing a backlog of obsolete volume changes.
public sealed class OutputVolume : IDisposable {
    private readonly Func<int?> read;
    private readonly Action<int> write;
    private readonly CancellationTokenSource stop=new();
    private readonly SemaphoreSlim wake=new(0,1);
    private int pending=-1;
    private object state=new {available=false,level=(int?)null};
    public object State=>Volatile.Read(ref state);
    public OutputVolume(Func<int?> read,Action<int> write) {this.read=read;this.write=write;_=Task.Run(Run);}
    public void Set(int level) {
        if(level is <0 or >100)throw new ArgumentOutOfRangeException(nameof(level));
        if(stop.IsCancellationRequested)return;
        Interlocked.Exchange(ref pending,level);
        try { wake.Release(); } catch(SemaphoreFullException) { }
    }
    public void CancelPending()=>Interlocked.Exchange(ref pending,-1);
    private async Task Run() {
        try {
            while(!stop.IsCancellationRequested) {
                try {
                    int next=Interlocked.Exchange(ref pending,-1);
                    if(next>=0&&!stop.IsCancellationRequested)write(next);
                    var level=read();
                    bool available=level is >=0 and <=100;
                    Volatile.Write(ref state,new {available,level=available?level:null});
                } catch { Volatile.Write(ref state,new {available=false,level=(int?)null}); }
                await wake.WaitAsync(1000,stop.Token);
            }
        } catch(OperationCanceledException) { }
    }
    public void Dispose(){CancelPending();stop.Cancel();}
}
