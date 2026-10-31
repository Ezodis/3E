// SPDX-License-Identifier: MIT
using System.Text.Json;
namespace ThreeE.PhoneControl;
// The installed Live surface writes this small, local snapshot. It never
// exposes an audio-file path or modifies a Set while gathering feedback.
public sealed class LiveClipTelemetry {
    public static LiveClipTelemetry Default {get;}=new(Path.Combine(
        OperatingSystem.IsMacOS()?Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"Library","Application Support"):Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"3E","phone-live.json"));
    readonly string path;readonly object gate=new();long polled;JsonElement? cached;
    public LiveClipTelemetry(string path){this.path=path;}
    public JsonElement? Read(){lock(gate){
        long now=Environment.TickCount64;if(now-polled<250)return cached;polled=now;
        try{
            var file=new FileInfo(path);if(!file.Exists||file.Length>65536){cached=null;return null;}
            using var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
            var data=new byte[65537];int count=0,read;while(count<data.Length&&(read=input.Read(data,count,data.Length-count))>0)count+=read;
            if(count>65536){cached=null;return null;}
            using var json=JsonDocument.Parse(data.AsMemory(0,count),new JsonDocumentOptions{MaxDepth=16});var root=json.RootElement;
            double age=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0-root.GetProperty("updated").GetDouble();
            if(root.GetProperty("schema").GetInt32()!=1||!double.IsFinite(age)||age< -5||age>2.5||root.GetProperty("decks").GetArrayLength()!=2){cached=null;return null;}
            cached=root.Clone();return cached;
        }catch(Exception error)when(error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException){cached=null;return null;}
    }}
}
