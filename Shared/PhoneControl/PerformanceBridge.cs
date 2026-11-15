// SPDX-License-Identifier: MIT
using System.Text.Json;
namespace ThreeE.PhoneControl;

// Both clients submit to the same Live-thread command processor. The phone
// never synthesizes keyboard shortcuts, accepts paths, or executes code.
public sealed class PerformanceBridge {
    public static PerformanceBridge Default {get;}=new(Path.Combine(
        OperatingSystem.IsMacOS()?Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Library","Application Support"):
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Strip3","AbletonRecord"));
    readonly string root;
    static readonly HashSet<string> actions=LoadActions();
    public PerformanceBridge(string root){this.root=root;}
    static HashSet<string> LoadActions(){
        var result=new HashSet<string>{"record","session","play","stop","loop","click","overdub","piano-mode-set"};
        using var stream=typeof(PerformanceBridge).Assembly.GetManifestResourceStream("ThreeE.PhoneControl.Workspaces");
        using var doc=JsonDocument.Parse(stream!);
        foreach(var space in doc.RootElement.EnumerateArray())foreach(var action in space[2].EnumerateArray())result.Add(action[0].GetString()!);
        return result;
    }
    public JsonElement? Read(){
        try {
            var path=Path.Combine(root,"state.json");var file=new FileInfo(path);
            if(!file.Exists||file.Length>262144)return null;
            using var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            var bytes=new byte[262145];int count=0,n;while(count<bytes.Length&&(n=input.Read(bytes,count,bytes.Length-count))>0)count+=n;
            if(count>262144)return null;
            using var doc=JsonDocument.Parse(bytes.AsMemory(0,count));var state=doc.RootElement;
            double age=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0-state.GetProperty("time").GetDouble();
            if(!double.IsFinite(age)||age< -1||age>2.5||state.GetProperty("protocol").GetInt32()!=1)return null;
            return state.Clone();
        } catch(Exception e) when(e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException){return null;}
    }
    public void Send(JsonElement command){
        string action=command.GetProperty("action").GetString()!;
        if(!actions.Contains(action))throw new InvalidDataException("Unknown performance action");
        string id=command.GetProperty("id").GetString()!;
        if(!Guid.TryParseExact(id,"D",out _))throw new InvalidDataException("Invalid command identity");
        var state=Read();if(state is null)return;
        string session=command.GetProperty("session").GetString()!;
        if(session!=state.Value.GetProperty("session_id").GetString())return;
        int track=command.GetProperty("track_index").GetInt32();
        if(track!=state.Value.GetProperty("track_index").GetInt32())return;
        var payload=new Dictionary<string,object>{{"action",action},{"session",session},{"track_index",track},{"time",DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0}};
        if(action.StartsWith("clip-")) {
            string token=command.GetProperty("clip_token").GetString()!;
            if(token!=state.Value.GetProperty("selected_clip").GetProperty("token").GetString())return;
            payload["clip_token"]=token;
        }
        if(action=="piano-mode-set") {
            string channel=command.GetProperty("channel").GetString()!;int mode=command.GetProperty("mode").GetInt32();
            if(!int.TryParse(channel,out int ch)||ch<1||ch>15||mode<0||mode>3)throw new InvalidDataException("Invalid piano mode");
            payload["channel"]=channel;payload["mode"]=mode;
        }
        string directory=Path.Combine(root,"commands");Directory.CreateDirectory(directory);
        string temporary=Path.Combine(directory,id+".tmp"),target=Path.Combine(directory,id+".json");
        // A phone UUID is single-use, including after Live consumes the file.
        if(File.Exists(target)||File.Exists(Path.Combine(root,"responses",id+".json")))return;
        try {using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))JsonSerializer.Serialize(output,payload);File.Move(temporary,target);}
        finally {if(File.Exists(temporary))File.Delete(temporary);}
    }
}
