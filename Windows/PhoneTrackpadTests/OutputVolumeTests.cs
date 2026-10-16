using ThreeE.PhoneControl;
using System.Collections.Concurrent;
using System.Text.Json;

static class OutputVolumeTests {
    public static async Task Run(Action<bool,string> check) {
        async Task Until(Func<bool> condition){for(int i=0;i<100;i++){if(condition())return;await Task.Delay(10);}throw new Exception("Volume worker timeout");}
        using var release=new ManualResetEventSlim(false);
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var writes=new ConcurrentQueue<int>();int current=35,reads=0;
        using var volume=new OutputVolume(()=>{if(Interlocked.Increment(ref reads)==1){entered.SetResult();release.Wait();}return current;},value=>{current=value;writes.Enqueue(value);});
        await entered.Task;
        volume.Set(10);volume.Set(40);volume.Set(72);
        check(!JsonSerializer.SerializeToElement(volume.State).GetProperty("available").GetBoolean(),"Slow audio discovery never blocks cached connection information");
        release.Set();await Until(()=>writes.Count==1&&JsonSerializer.SerializeToElement(volume.State).GetProperty("level").GetInt32()==72);
        check(writes.SequenceEqual(new[]{72}),"Fast slider changes coalesce to the newest requested volume");
        bool invalid=false;try{volume.Set(101);}catch(ArgumentOutOfRangeException){invalid=true;}
        check(invalid,"Output volume rejects values outside its range");
        using var releaseCancel=new ManualResetEventSlim(false);
        var enteredCancel=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);int cancelledWrites=0;
        using var cancelled=new OutputVolume(()=>{enteredCancel.TrySetResult();releaseCancel.Wait();return 20;},_=>Interlocked.Increment(ref cancelledWrites));
        await enteredCancel.Task;cancelled.Set(80);cancelled.CancelPending();releaseCancel.Set();
        await Until(()=>JsonSerializer.SerializeToElement(cancelled.State).GetProperty("available").GetBoolean());
        await Task.Delay(50);check(cancelledWrites==0,"Disconnect drops unsent volume changes");
        using var missing=new OutputVolume(()=>null,_=>throw new Exception("No device"));
        check(!JsonSerializer.SerializeToElement(missing.State).GetProperty("available").GetBoolean(),"A missing output reports volume unavailable");
        volume.Dispose();int count=writes.Count;volume.Set(90);await Task.Delay(30);
        check(writes.Count==count,"Stopping Phone Bar prevents later volume writes");
    }
}
