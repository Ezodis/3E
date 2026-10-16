using ThreeE.PhoneControl;
using System.Text.Json;

static class MediaRouterTests {
    public static async Task Run(Action<bool,string> check) {
        long now=10000;bool accepted=true;
        var actual=new Dictionary<string,int>{{"spotify",1},{"browser",0}};
        var sent=new List<(string,MediaAction)>();object preferred="spotify";
        MediaSources Read()=>new(actual.Select(p=>new MediaSession(p.Key,p.Key,p.Value,(action,token)=> {
            sent.Add((p.Key,action));return Task.FromResult(accepted);
        })).ToArray(),preferred);
        var router=new MediaRouter(Read,app=>"icon:"+app,()=>now);
        JsonElement View()=>JsonSerializer.SerializeToElement(router.State);
        string Icon()=>View().GetProperty("artwork").GetString();
        bool Playing()=>View().GetProperty("playing").GetBoolean();
        await router.RefreshAsync();
        check(Icon()=="icon:spotify"&&Playing(),"Media icon and Pause action share the selected playing source");
        actual["browser"]=1;preferred="browser";await router.RefreshAsync();
        check(Icon()=="icon:browser","Most recently playing source takes priority");
        await router.SendAsync(0);
        check(sent.Last()==("browser",MediaAction.Pause)&&Icon()=="icon:spotify"&&Playing(),"Pausing the displayed browser hands off to still-playing Spotify");
        await router.RefreshAsync();
        check(Icon()=="icon:spotify","A stale browser report cannot undo an acknowledged pause");
        await router.SendAsync(0);
        check(sent.Last()==("spotify",MediaAction.Pause)&&!Playing(),"After both sources pause the next action is Play");
        await router.SendAsync(0);
        check(sent.Last()==("spotify",MediaAction.Play)&&Playing(),"Play resumes the last controlled source");
        now+=1100;actual["browser"]=0;await router.RefreshAsync();
        preferred="browser";actual["browser"]=1; // OS changes between display and tap.
        await router.SendAsync(2);
        check(sent.Last()==("spotify",MediaAction.Next),"Next targets the displayed source even when OS preference changes");
        await router.SendAsync(1);
        check(sent.Last()==("browser",MediaAction.Previous),"Previous follows the new displayed source after handoff");
        accepted=false;await router.SendAsync(0);
        check(Icon()=="icon:browser"&&Playing(),"A rejected pause never fabricates a Play icon");
        accepted=true;int count=sent.Count;actual.Remove("browser");await router.SendAsync(0);
        check(sent.Count==count&&Icon()=="icon:spotify","An exited displayed source never redirects its tap to a different app");
        actual.Clear();await router.RefreshAsync();
        check(View().GetProperty("playing").ValueKind==JsonValueKind.Null&&Icon()=="","No media clears stale artwork and state");
        actual["ableton"]=1;await router.RefreshAsync();await router.SendAsync(0);
        check(sent.Last()==("ableton",MediaAction.Stop)&&!Playing(),"Ableton uses Stop and then Play for its acknowledged transport state");

        // Two sessions from one app must keep separate identities and transport.
        var ids=new List<string>();var sessions=new[]{
            new MediaSession("tab1","browser",1,(a,t)=>{ids.Add("tab1");return Task.FromResult(true);}),
            new MediaSession("tab2","browser",1,(a,t)=>{ids.Add("tab2");return Task.FromResult(true);})};
        var tabs=new MediaRouter(()=>new(sessions,"tab2"),_=>"");
        await tabs.RefreshAsync();await tabs.SendAsync(0);await tabs.SendAsync(0);
        check(ids.SequenceEqual(new[]{"tab2","tab1"}),"Distinct sessions in the same media app pause separately");
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);int slowCalls=0;
        var slow=new MediaSession("slow","browser",1,async(a,t)=>{slowCalls++;entered.SetResult();return await release.Task.WaitAsync(t);});
        var blocked=new MediaRouter(()=>new(new[]{slow},"slow"),_=>"");await blocked.RefreshAsync();
        var pending=blocked.SendAsync(0);await entered.Task;
        await blocked.SendAsync(0);
        check(slowCalls==1&&JsonSerializer.SerializeToElement(blocked.State).GetProperty("playing").GetBoolean(),"A pending provider keeps cached state responsive and ignores duplicate taps");
        release.SetResult(false);await pending;
    }
}
