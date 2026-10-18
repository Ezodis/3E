// SPDX-License-Identifier: MIT
using System.Net;
using System.Text.Json;
using System.Security.Cryptography;
using ThreeE.PhoneControl;
using ThreeE.PhoneHost;

if(args.Contains("--native-self-test")) {
    if(MacInput.ThreeEValidateScrollEvent()!=1)throw new Exception("Quartz scroll event mismatch");
    if(MacInput.ThreeEHasMultipleSpaces() is <0 or >1)throw new Exception("Space discovery mismatch");
    if(MacInput.ThreeEGetOutputVolume() is < -1 or >100)throw new Exception("Output volume probe mismatch");
    Console.WriteLine("PASS: native Quartz scroll event ABI and read-only Space/output-volume discovery (no posted input)");return;
}
if(args.Contains("--midi-self-test")) {
    using var midi=new MacMidi();midi.Select(0);
    if(midi.Selected!=0)throw new Exception(midi.Status);
    midi.Send(false,15,1,64);midi.Send(true,15,36,100);midi.Panic();
    if(midi.Selected!=0)throw new Exception(midi.Status);
    Console.WriteLine("PASS: CoreMIDI virtual source, CC, note and cleanup");return;
}
bool test=args.Contains("--self-test");
ITrackpadInput input=test?new NullInput():new MacInput(action=>Report(new {media=action}),(action,direction)=>Report(new {systemAction=action,direction}));
using var receiver=new PhoneTrackpad(()=>test ? IPAddress.Loopback : PhoneTrackpad.GetLocalAddress(),input,new NoFirewall(),test?17834:17833) { AliasHost=test ? null : PhoneNameResponder.Name, TokenProvider=test ? null : StoredPairingToken };
PhoneNameResponder nameResponder=null;
void RefreshName() {
    if(!receiver.Running || receiver.Address==null) { nameResponder?.Dispose(); nameResponder=null; return; }
    if(nameResponder?.Address.Equals(receiver.Address)==true)return;
    nameResponder?.Dispose();
    try { nameResponder=new PhoneNameResponder(receiver.Address); } catch { /* The IP pairing link remains available without mDNS. */ }
}
void Announce(){Report(receiver.Running ? new {url=receiver.NamedUrl ?? receiver.PairingUrl,error=(string)null} : new {url=(string)null,error=receiver.Status});}
// Publish the alias before HttpListener validates its host prefix on macOS.
if(!test) {
    var initialAddress=PhoneTrackpad.GetLocalAddress();
    if(initialAddress!=null)try{nameResponder=new PhoneNameResponder(initialAddress);}catch{ /* The receiver can still pair by IP. */ }
}
receiver.Start();RefreshName();Announce();
if(test){if(!receiver.Running)throw new Exception(receiver.Status);using var http=new HttpClient();var html=await http.GetStringAsync(receiver.PairingUrl.Split('#')[0]);if(!html.Contains("surface.js"))throw new Exception("Shared surface missing");Console.WriteLine("PASS: shared receiver and resources on this platform");return;}
string line;
while((line=await Console.In.ReadLineAsync())!=null){
    if(line=="STOP")break;
    if(line=="START"){receiver.Start();RefreshName();Announce();}
    else if(line.StartsWith("{"))try{using var json=JsonDocument.Parse(line);if(json.RootElement.TryGetProperty("controls",out var state)&&input is MacInput mac)mac.SetControls(state.Clone());}catch(JsonException){}
}
nameResponder?.Dispose();
static void Report(object data){lock(Console.Out)Console.WriteLine(JsonSerializer.Serialize(data));}
static string StoredPairingToken() {
    try {
        var directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"3E");
        var path=Path.Combine(directory,"phone-link.txt");
        if(File.Exists(path)) {
            var saved=File.ReadAllText(path).Trim();
            if(saved.Length==48 && saved.All(Uri.IsHexDigit))return saved.ToUpperInvariant();
        }
        Directory.CreateDirectory(directory);
        var token=Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        var temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        File.WriteAllText(temporary,token);
        try { File.Move(temporary,path,true); } finally { if(File.Exists(temporary))File.Delete(temporary); }
        return token;
    } catch { return null; }
}
sealed class NoFirewall:ITrackpadFirewall{public void Open(IPAddress address,int port){}public void Close(){}}
sealed class NullInput:ITrackpadInput{
    public string Platform=>"macos";
    public void Move(int x,int y){}public void Scroll(int x,int y){}public void Click(bool right){}public void Down(){}public void Release(){}public void TaskView(){}public void ShowDesktop(){}
}
