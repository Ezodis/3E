using System.Text.Json;
using ThreeE.PhoneControl;
using ThreeE.PhoneBar.Windows;

static class TrackTabTests {
    public static void Run(Action<bool,string> check) {
        using var data=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"track-tab.json")));
        foreach(var test in data.RootElement.EnumerateArray()) {
            var emitted=new List<(string,int)>();
            var gesture=new TrackTabGesture((action,value)=>emitted.Add((action,value)));
            foreach(var frame in test.GetProperty("frames").EnumerateArray()) {
                var points=frame.GetProperty("points").EnumerateArray().Select(p=>new TrackTabGesture.Contact(p[0].GetInt32(),p[1].GetDouble(),p[2].GetDouble())).ToArray();
                gesture.Update(points,1000+frame.GetProperty("t").GetInt64());
            }
            var expected=test.GetProperty("events").EnumerateArray().Select(p=>(p.GetProperty("action").GetString(),p.GetProperty("value").GetInt32()));
            check(emitted.SequenceEqual(expected),"Track Tab: "+test.GetProperty("name").GetString()+" / "+string.Join(",",emitted));
            check(!gesture.Claimed,"Track Tab releases contact ownership");
        }
        var releases=new List<string>();var cancelled=new TrackTabGesture((action,_)=>releases.Add(action));
        var start=new[]{new TrackTabGesture.Contact(1,.1,.2),new(2,.2,.2),new(3,.3,.2),new(4,.4,.2)};
        cancelled.Update(start,1000);cancelled.Update(start.Select(p=>p with{X=p.X+.1}).ToArray(),1030);cancelled.Cancel();cancelled.Cancel();
        check(releases.SequenceEqual(new[]{"appsBegin","appsEnd"}),"Lock, suspend or lost contact cancels a switch exactly once without a tap");
        var windows=new[]{new IntPtr(30),new IntPtr(10),new IntPtr(20),new IntPtr(10)};
        check(WindowsAppWindows.Next(windows,(IntPtr)20,1)==(IntPtr)30 && WindowsAppWindows.Next(windows,(IntPtr)30,1)==(IntPtr)10,"Same-app cycling uses stable order and wraps through all windows");
        check(WindowsAppWindows.Next(windows,(IntPtr)10,-1)==(IntPtr)30,"Same-app cycling supports reverse direction");
        check(WindowsAppWindows.Next(windows,(IntPtr)99,1)==IntPtr.Zero && WindowsAppWindows.Next(new[]{(IntPtr)10},(IntPtr)10,1)==IntPtr.Zero,"Missing or single foreground window never switches to another application");
    }
}
