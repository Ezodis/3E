// SPDX-License-Identifier: MIT
using System.Net;
using System.Text.Json;
using ThreeE.PhoneControl;
using ThreeE.PhoneHost;

if(args.Contains("--native-self-test")) {
    if(MacInput.ThreeEValidateScrollEvent()!=1)throw new Exception("Quartz scroll event mismatch");
    Console.WriteLine("PASS: native Quartz scroll event ABI (no posted input)");return;
}
if(args.Contains("--midi-self-test")) {
    using var midi=new MacMidi();midi.Select(0);
    if(midi.Selected!=0)throw new Exception(midi.Status);
    midi.Send(false,15,1,64);midi.Send(true,15,36,100);midi.Panic();
    if(midi.Selected!=0)throw new Exception(midi.Status);
    Console.WriteLine("PASS: CoreMIDI virtual source, CC, note and cleanup");return;
}
bool test=args.Contains("--self-test");
ITrackpadInput input=test?new NullInput():new MacInput(action=>Report(new {media=action}));
using var receiver=new PhoneTrackpad(test?()=>IPAddress.Loopback:PhoneTrackpad.GetLocalAddress,input,new NoFirewall(),test?17834:17833);
void Announce(){Report(receiver.Running ? new {url=receiver.PairingUrl,error=(string)null} : new {url=(string)null,error=receiver.Status});}
receiver.Start();Announce();
if(test){if(!receiver.Running)throw new Exception(receiver.Status);using var http=new HttpClient();var html=await http.GetStringAsync(receiver.PairingUrl.Split('#')[0]);if(!html.Contains("surface.js"))throw new Exception("Shared surface missing");Console.WriteLine("PASS: shared receiver and resources on this platform");return;}
string line;
while((line=await Console.In.ReadLineAsync())!=null){if(line=="STOP")break;if(line=="START"){receiver.Start();Announce();}}
static void Report(object data){lock(Console.Out)Console.WriteLine(JsonSerializer.Serialize(data));}
sealed class NoFirewall:ITrackpadFirewall{public void Open(IPAddress address,int port){}public void Close(){}}
sealed class NullInput:ITrackpadInput{
    public string Platform=>"macos";
    public void Move(int x,int y){}public void Scroll(int x,int y){}public void Click(bool right){}public void Down(){}public void Release(){}public void TaskView(){}public void ShowDesktop(){}
}
