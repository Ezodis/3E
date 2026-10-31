using ThreeE.PhoneControl;
using System.Text.Json;
static class LiveClipTelemetryTests {
    public static void Run(Action<bool,string> check){
        string folder=Directory.CreateTempSubdirectory("3e-live-test-").FullName,path=Path.Combine(folder,"live.json");
        try{
            string Snapshot(double updated,int count=2)=>JsonSerializer.Serialize(new{schema=1,updated,decks=Enumerable.Range(0,count).Select(i=>new{title="Clip "+i,positionBeats=2.5,loopStart=0,loopEnd=16})});
            double now=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0;
            check(new LiveClipTelemetry(path).Read()==null,"Missing Live feedback stays unavailable");
            File.WriteAllText(path,Snapshot(now));var live=new LiveClipTelemetry(path).Read();
            check(live?.GetProperty("decks")[0].GetProperty("title").GetString()=="Clip 0","Actual Live clip feedback is read from the bounded local snapshot");
            File.WriteAllText(path,Snapshot(now-10));check(new LiveClipTelemetry(path).Read()==null,"Stale Live feedback is cleared");
            File.WriteAllText(path,Snapshot(now+60));check(new LiveClipTelemetry(path).Read()==null,"Future feedback timestamps are rejected");
            File.WriteAllText(path,Snapshot(now,3));check(new LiveClipTelemetry(path).Read()==null,"Live feedback requires the two-deck schema");
            File.WriteAllText(path,new string('x',65537));check(new LiveClipTelemetry(path).Read()==null,"Oversized Live feedback cannot block the receiver");
            File.WriteAllText(path,"{\"schema\":99999999999999999999,\"updated\":1,\"decks\":[]}");check(new LiveClipTelemetry(path).Read()==null,"Invalid numeric feedback cannot crash the receiver");
            File.WriteAllText(path,"{\"schema\":1}");check(new LiveClipTelemetry(path).Read()==null,"Incomplete feedback does not fabricate clip state");
        }finally{Directory.Delete(folder,true);}
    }
}
