// SPDX-License-Identifier: MIT
using System.Net;
using System.Text.Json;
using System.Security.Cryptography;
using ThreeE.PhoneControl;
using ThreeE.PhoneHost;

if(args.Contains("--bonjour-self-test")) {
    string name=$"threee-recovery-{Environment.ProcessId}.local";
    for(int attempt=0;attempt<3;attempt++) {
        using var responder=new PhoneNameResponder(IPAddress.Loopback,name);
        var addresses=await Dns.GetHostAddressesAsync(name).WaitAsync(TimeSpan.FromSeconds(8));
        if(!responder.Healthy||!addresses.Contains(IPAddress.Loopback))throw new Exception("Bonjour registration did not resolve");
    }
    Console.WriteLine("PASS: native Bonjour registers and re-registers a stable local-only name (no LAN advertisement or native input)");return;
}
if(args.Contains("--native-self-test")) {
    MacInput.ValidatePointerEvents();
    if(MacInput.ThreeEValidateScrollEvent()!=1)throw new Exception("Quartz scroll event mismatch");
    if(MacInput.ThreeEHasMultipleSpaces() is <0 or >1)throw new Exception("Space discovery mismatch");
    if(MacInput.ThreeEGetOutputVolume() is < -1 or >100)throw new Exception("Output volume probe mismatch");
    Console.WriteLine("PASS: native Quartz pointer/display/scroll ABI and read-only Space/output-volume discovery (no posted input)");return;
}
if(args.Contains("--clipboard-self-test")) {
    // Round-trips text, HTML, a picture and then a file through the real pasteboard.
    var clipboard=new MacClipboard();
    var png=Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==");
    clipboard.Write(new[]{new ClipPart{Kind="text",Data="3E clipboard ✓"u8.ToArray()},new ClipPart{Kind="html",Data="<b>3E</b> clipboard"u8.ToArray()},new ClipPart{Kind="image",Name="p.png",Data=png}});
    var back=clipboard.Read();
    if(back.Text!="3E clipboard ✓")throw new Exception("Pasteboard text mismatch: "+back.Text);
    if(back.Html==null||!back.Html.Contains("<b>3E</b>"))throw new Exception("Pasteboard HTML missing");
    if(back.Png==null||back.Width!=1||back.Height!=1)throw new Exception("Pasteboard picture missing");
    clipboard.Write(new[]{new ClipPart{Kind="file",Name="../report?.pdf",Data="%PDF-1.4"u8.ToArray()}});
    back=clipboard.Read();
    if(back.Files.Count!=1||Path.GetFileName(back.Files[0])!="report_.pdf"||File.ReadAllText(back.Files[0])!="%PDF-1.4"||back.Png!=null)throw new Exception("Pasteboard file mismatch");
    Console.WriteLine("PASS: pasteboard text, HTML, picture and file round trip");return;
}
if(args.Contains("--midi-self-test")) {
    using var midi=new MacMidi();midi.Select(0);
    if(midi.Selected!=0)throw new Exception(midi.Status);
    midi.Send(false,15,1,64);midi.Send(true,15,36,100);midi.Panic();
    if(midi.Selected!=0)throw new Exception(midi.Status);
    Console.WriteLine("PASS: CoreMIDI virtual source, CC, note and cleanup");return;
}
bool recoveryTest=args.Contains("--recovery-self-test");
bool test=args.Contains("--self-test")||recoveryTest;
// Read once per host lifetime: temporary file unavailability after sleep must
// never silently replace a valid bookmark with a random pairing secret.
if(!test)AbletonIntegration.Install();
string pairingToken=test?new string('A',48):StoredPairingToken();
ITrackpadInput input=test?new NullInput():new MacInput(action=>Report(new {media=action}),(action,direction)=>Report(new {systemAction=action,direction}));
using var receiver=new PhoneTrackpad(()=>test ? IPAddress.Loopback : PhoneTrackpad.GetLocalAddress(),input,new NoFirewall(),test?17834:17833) { AliasHost=test ? null : PhoneNameResponder.Name, TokenProvider=()=>pairingToken, FollowNetwork=!test||recoveryTest,
    PreferencesPath=test ? null : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"3E","phone-settings.json") };
PhoneNameResponder nameResponder=null;
object nameGate=new();
// The link stays http://3e-mac.local:17833/#secret: when the Mac's IP changes
// the receiver rebinds with the same secret and the mDNS name follows it.
receiver.AddressChanged+=()=>{RefreshName();Announce();};
void RefreshName() { lock(nameGate) RefreshNameLocked(); }
void ForgetName() { lock(nameGate) { nameResponder?.Dispose();nameResponder=null; } }
void RefreshNameLocked() {
    if(test)return;
    if(!receiver.Running || receiver.Address==null) { nameResponder?.Dispose(); nameResponder=null; return; }
    if(nameResponder?.Address.Equals(receiver.Address)==true&&nameResponder.Healthy)return;
    nameResponder?.Dispose();nameResponder=null;
    try { nameResponder=new PhoneNameResponder(receiver.Address); } catch { /* The IP pairing link remains available without mDNS. */ }
}
void Announce(){Report(receiver.Running ? new {url=receiver.NamedUrl ?? receiver.PairingUrl,error=(string)null} : new {url=(string)null,error=receiver.Status});}
// Publish the alias before HttpListener validates its host prefix on macOS.
if(!test) {
    var initialAddress=PhoneTrackpad.GetLocalAddress();
    if(initialAddress!=null)try{nameResponder=new PhoneNameResponder(initialAddress);}catch{ /* The receiver can still pair by IP. */ }
}
receiver.Start();RefreshName();Announce();
if(test&&!recoveryTest){if(!receiver.Running)throw new Exception(receiver.Status);using var http=new HttpClient();var html=await http.GetStringAsync(receiver.PairingUrl.Split('#')[0]);if(!html.Contains("surface.js"))throw new Exception("Shared surface missing");Console.WriteLine("PASS: shared receiver and resources on this platform");return;}
// Recover failed multicast sockets even when DHCP kept the same IP.
using var nameMaintenance=new Timer(_=>{try{RefreshName();}catch{}},null,TimeSpan.FromSeconds(5),TimeSpan.FromSeconds(5));
string line;
while((line=await Console.In.ReadLineAsync())!=null){
    if(line=="STOP")break;
    if(line=="SLEEP"){receiver.Stop();ForgetName();}
    else if(line=="WAKE"){
        // Even with the same IP, sockets/multicast memberships can be stale.
        // Recreate both using the persisted token, then resume Wi-Fi retries.
        receiver.Stop();ForgetName();
        var address=test?null:PhoneTrackpad.GetLocalAddress();
        if(address!=null)lock(nameGate)try{nameResponder=new PhoneNameResponder(address);}catch{}
        receiver.Start();RefreshName();Announce();
    }
    else if(line=="START"){receiver.Start();RefreshName();Announce();}
    else if(line.StartsWith("{"))try{using var json=JsonDocument.Parse(line);if(json.RootElement.TryGetProperty("controls",out var state)&&input is MacInput mac)mac.SetControls(state.Clone());}catch(JsonException){}
}
receiver.Stop();nameMaintenance.Dispose();ForgetName();
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
    } catch(Exception error) { throw new IOException("Cannot read or preserve the saved phone pairing link.",error); }
}
sealed class NoFirewall:ITrackpadFirewall{public void Open(IPAddress address,int port){}public void Close(){}}
sealed class NullInput:ITrackpadInput{
    public string Platform=>"macos";
    public void Move(int x,int y){}public void Scroll(int x,int y){}public void Click(bool right){}public void Down(){}public void Release(){}public void TaskView(){}public void ShowDesktop(){}
}
