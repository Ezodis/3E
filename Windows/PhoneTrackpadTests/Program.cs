using ThreeE.PhoneControl;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Collections.Concurrent;
using System.Text.Json;
using ThreeE.PhoneBar.Windows;

var results = new List<string>();
void Check(bool value, string name) { if (!value) throw new Exception("FAIL: " + name); results.Add(name); Console.WriteLine("PASS: " + name); }
int FreePort() { var socket = new TcpListener(IPAddress.Loopback, 0); socket.Start(); int port = ((IPEndPoint)socket.LocalEndpoint).Port; socket.Stop(); return port; }
async Task Until(Func<bool> condition) { for (int i=0;i<100;i++) { if (condition()) return; await Task.Delay(50); } throw new Exception("Timed out waiting for state."); }
async Task<ClientWebSocket> Connect(string url, string token = null, string origin = null, string controller = null) {
    var ws = new ClientWebSocket(); var uri = new Uri(url);
    ws.Options.SetRequestHeader("Origin", origin ?? uri.GetLeftPart(UriPartial.Authority));
    await ws.ConnectAsync(new Uri("ws://" + uri.Authority + "/ws"), CancellationToken.None);
    await ws.SendAsync(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { token = token ?? uri.Fragment[1..], client = controller })), WebSocketMessageType.Text, true, CancellationToken.None);
    return ws;
}
async Task Send(ClientWebSocket ws, string text) => await ws.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, CancellationToken.None);
async Task<string> Receive(ClientWebSocket ws) { using var timeout = new CancellationTokenSource(3000); var buffer = new byte[2048]; var result = await ws.ReceiveAsync(buffer, timeout.Token); return Encoding.UTF8.GetString(buffer, 0, result.Count); }

// Preview mode exercises the real server and resource delivery, but never injects input or opens the firewall.
if (args.Length == 2 && args[0] == "--preview") {
    using var preview = new PhoneTrackpad(() => IPAddress.Loopback, new FakeInput(), new FakeFirewall(), 17834);
    if (!preview.Start()) throw new Exception(preview.Status);
    File.WriteAllText(args[1], preview.PairingUrl);
    await Task.Delay(Timeout.Infinite);
    return;
}
if (args.Length == 1 && args[0] == "--firewall-smoke") {
    using var smoke = new PhoneTrackpad(PhoneTrackpad.GetLocalAddress, new FakeInput(), new TrackpadFirewall(), PhoneTrackpad.Port);
    if (!smoke.Start()) throw new Exception(smoke.Status);
    using var http = new HttpClient();
    if (!(await http.GetStringAsync(new Uri(smoke.PairingUrl).GetLeftPart(UriPartial.Path))).Contains("Trackpad")) throw new Exception("Page missing");
    using var socket = await Connect(smoke.PairingUrl);
    if (!(await Receive(socket)).Contains("ready")) throw new Exception("Pairing failed");
    smoke.Stop();
    Console.WriteLine("PASS: real Windows listener, local address, temporary firewall rule, pairing and cleanup (simulated input).");
    return;
}

await MediaRouterTests.Run(Check);
await OutputVolumeTests.Run(Check);
var fake = new FakeInput(); var firewall = new FakeFirewall();
using(var volumeCommand=JsonDocument.Parse("{\"type\":\"volume\",\"level\":37}"))PhoneTrackpad.Apply(volumeCommand.RootElement,fake);
Check(fake.Commands.Contains("volume:37"),"Volume commands reach the native boundary");
foreach(int invalidVolume in new[]{-1,101}) {
    bool rejected=false;try{using var command=JsonDocument.Parse(JsonSerializer.Serialize(new{type="volume",level=invalidVolume}));PhoneTrackpad.Apply(command.RootElement,fake);}catch(InvalidDataException){rejected=true;}
    Check(rejected,"Out-of-range volume command is rejected");
}
var navigationLog=new List<string>(); bool multiple=true;
var navigation=new NavigationGesture(()=>multiple,d=>navigationLog.Add("desktop:"+d),d=>navigationLog.Add("begin:"+d),d=>navigationLog.Add("step:"+d),()=>navigationLog.Add("end"));
navigation.Step(1);multiple=false;navigation.Step(-1);navigation.End();
Check(navigationLog.SequenceEqual(new[]{"desktop:1","desktop:-1","end"}),"Desktop navigation keeps its mode until the contact ends");
navigationLog.Clear();navigation.Step(-1);navigation.Step(1);navigation.End();
Check(navigationLog.SequenceEqual(new[]{"begin:-1","step:1","end"}),"Single-desktop navigation starts in the requested direction without an extra forward step");
navigationLog.Clear();var unknownNavigation=new NavigationGesture(()=>throw new Exception("OS unavailable"),d=>navigationLog.Add("desktop"),d=>navigationLog.Add("begin:"+d),d=>{},()=>{});unknownNavigation.Step(1);
Check(navigationLog.SequenceEqual(new[]{"begin:1"}),"Unavailable desktop discovery falls back to window switching");
Check(!NativeTrackpadInput.HasMultipleDesktopIds(null)&&!NativeTrackpadInput.HasMultipleDesktopIds(new byte[16])&&!NativeTrackpadInput.HasMultipleDesktopIds(new byte[33])&&NativeTrackpadInput.HasMultipleDesktopIds(new byte[32]),"Desktop discovery handles missing, single and malformed Explorer data");
using (var unblockProbe = new ManualResetEventSlim(false)) {
    var probeEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    int probes = 0;
    var probeInput = new FakeInput();
    using var slowProbe = new PhoneTrackpad(() => {
        if (Interlocked.Increment(ref probes) > 1) { probeEntered.TrySetResult(); unblockProbe.Wait(TimeSpan.FromSeconds(8)); }
        return IPAddress.Loopback;
    }, probeInput, new FakeFirewall(), FreePort());
    Check(slowProbe.Start(), "Receiver starts before adapter-monitor test");
    try {
        using var ws = await Connect(slowProbe.PairingUrl);
        await Receive(ws);
        await probeEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await Send(ws,"{\"type\":\"move\",\"x\":27,\"y\":-9}");
        await Send(ws,"{\"type\":\"ping\"}");
        var firstPong = await Receive(ws);
        Check(firstPong.Contains("pong") && probeInput.Commands.Contains("move:27,-9"), "A stalled network-adapter check cannot freeze pointer input or heartbeat replies");
        Check(firstPong == "{\"pong\":true}", "Heartbeat replies omit unchanged host state");
        await Send(ws,"{\"type\":\"volume\",\"level\":12}");
        await Send(ws,"{\"type\":\"ping\"}");
        Check((await Receive(ws)).Contains("\"level\":12"), "Heartbeat replies resend host state after it changes");
    } finally { unblockProbe.Set(); }
}
var keyFactory=typeof(NativeTrackpadInput).GetMethod("KeyEvent",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Static);
bool marked=true;
foreach(ushort key in new ushort[]{0x12,0x09,0x10,0x11,0x5B,0x25,0x27,0xB3,0x2C,0x43,0x73}) foreach(bool up in new[]{false,true}) {
    object native=keyFactory.Invoke(null,new object[]{key,up});
    object data=native.GetType().GetField("Data").GetValue(native),keyboard=data.GetType().GetField("Keyboard").GetValue(data);
    marked &= ((UIntPtr)keyboard.GetType().GetField("Extra").GetValue(keyboard)).ToUInt64()==0x101;
}
Check(marked,"Fixed shortcut presses and releases bypass the suite's PowerToys remappings without injecting test input");
void ApplyText(string command) { using var parsed=JsonDocument.Parse(command); PhoneTrackpad.Apply(parsed.RootElement,fake); }
ApplyText("{\"type\":\"appsBegin\"}"); ApplyText("{\"type\":\"appsStep\",\"direction\":-1}");
Check(fake.Switching && fake.Commands.Contains("appsStep:-1"),"App switcher begins and steps through the native boundary");
ApplyText("{\"type\":\"midiNote\",\"channel\":15,\"number\":36,\"value\":127}");
ApplyText("{\"type\":\"releaseAll\"}");
Check(!fake.Switching && fake.MidiNotes==0,"Release-all clears app modifiers and MIDI notes");
ApplyText("{\"type\":\"desktop\",\"direction\":1}");ApplyText("{\"type\":\"media\",\"action\":2}");
Check(fake.Commands.Contains("desktop:1") && fake.Commands.Contains("media:2"),"Desktop and media commands use fixed whitelisted actions");
ApplyText("{\"type\":\"shortcut\",\"id\":0}");ApplyText("{\"type\":\"shortcut\",\"id\":17}");
Check(fake.Commands.Contains("shortcut:0") && fake.Commands.Contains("shortcut:17"),"Shortcut palette ids reach the native boundary");
ApplyText("{\"type\":\"volumeStep\",\"direction\":-1}");Check(fake.Commands.Contains("volumeStep:-1"),"Volume buttons reach the native volume keys");
{
    var saved = "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
    using var named = new PhoneTrackpad(() => IPAddress.Loopback, new FakeInput(), new FakeFirewall(), FreePort()) { TokenProvider = () => saved, AliasHost = "localhost" };
    Check(named.Start() && named.PairingUrl.EndsWith("#" + saved), "A saved pairing secret is reused for the phone link");
    named.Stop();
    Check(named.Start() && named.PairingUrl.EndsWith("#" + saved) && named.NamedUrl.EndsWith("#" + saved), "The same link works after the receiver restarts");
    var nameOrigin = new Uri(named.NamedUrl).GetLeftPart(UriPartial.Authority);
    var ipOrigin = new Uri(named.PairingUrl).GetLeftPart(UriPartial.Authority);
    using var web = new HttpClient();
    Check((await web.GetStringAsync(nameOrigin + "/")).Contains("Trackpad"), "The page is served at the stable name");
    using var probe = new HttpRequestMessage(HttpMethod.Get, nameOrigin + "/alive");
    probe.Headers.Add("Origin", ipOrigin);
    using var alive = await web.SendAsync(probe);
    Check((int)alive.StatusCode == 204 && alive.Headers.GetValues("Access-Control-Allow-Origin").Single() == ipOrigin, "A page opened by IP can confirm the stable name before switching");
    using var foreign = new HttpRequestMessage(HttpMethod.Get, nameOrigin + "/alive");
    foreign.Headers.Add("Origin", "http://evil.example");
    using var refused = await web.SendAsync(foreign);
    Check(!refused.Headers.Contains("Access-Control-Allow-Origin"), "Other sites cannot probe the receiver");
    using var badToken = new PhoneTrackpad(() => IPAddress.Loopback, new FakeInput(), new FakeFirewall(), FreePort()) { TokenProvider = () => "short" };
    Check(badToken.Start() && badToken.PairingUrl.Split('#')[1].Length == 48, "An invalid saved secret falls back to a fresh one");
}
{
    static byte[] Query(string name, ushort type, ushort klass, ushort id = 0) {
        var q = new List<byte> { (byte)(id >> 8), (byte)id, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        foreach (var label in name.Split('.')) { q.Add((byte)label.Length); q.AddRange(System.Text.Encoding.ASCII.GetBytes(label)); }
        q.Add(0); q.Add((byte)(type >> 8)); q.Add((byte)type); q.Add((byte)(klass >> 8)); q.Add((byte)klass);
        return q.ToArray();
    }
    var here = IPAddress.Parse("192.168.1.42");
    var reply = ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(Query("phonebar.local", 1, 1), here, 5353);
    Check(reply != null && !reply.Value.unicast && reply.Value.packet[^4..].SequenceEqual(here.GetAddressBytes()) && (reply.Value.packet[2] & 0x84) == 0x84, "phonebar.local answers with the receiver's address");
    var upper = ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(Query("PhoneBar.LOCAL", 255, 0x8001), here, 5353);
    Check(upper != null && upper.Value.unicast, "Name matching is case-insensitive and honours unicast-response questions");
    var legacy = ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(Query("phonebar.local", 1, 1, 0x1234), here, 53000);
    Check(legacy != null && legacy.Value.unicast && legacy.Value.packet[0] == 0x12 && legacy.Value.packet[1] == 0x34, "One-shot resolvers get a direct reply with their query id");
    Check(ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(Query("otherpc.local", 1, 1), here, 5353) == null, "Other names are never answered");
    Check(ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(new byte[] { 0, 0, 0x84, 0, 0, 1 }, here, 5353) == null && ThreeE.PhoneBar.Windows.PhoneNameResponder.Answer(new byte[3], here, 5353) == null, "Responses and malformed packets are ignored");
}
ApplyText("{\"type\":\"dragStart\",\"x\":-1,\"y\":0}");
Check(fake.Held && fake.Commands.Contains("dragStart:-1,0"),"Tap-drag start presses through the host's double-click-safe path");ApplyText("{\"type\":\"up\"}");
foreach(string invalid in new[]{"{\"type\":\"midiCC\",\"channel\":16,\"number\":1,\"value\":64}","{\"type\":\"midiCC\",\"channel\":0,\"number\":120,\"value\":64}","{\"type\":\"midiNote\",\"channel\":0,\"number\":1,\"value\":128}","{\"type\":\"desktop\",\"direction\":2}","{\"type\":\"shortcut\",\"id\":18}","{\"type\":\"shortcut\",\"id\":-1}","{\"type\":\"dragStart\",\"x\":2,\"y\":0}","{\"type\":\"volumeStep\",\"direction\":2}"}) {
    bool refused=false;try{ApplyText(invalid);}catch(InvalidDataException){refused=true;}Check(refused,"Out-of-range MIDI/shortcut control rejected");
}
using(var midi=new TestMidi()) {midi.Select(0);midi.Send(false,15,1,64);midi.Send(true,15,36,100);midi.Panic();Check(midi.Messages.SequenceEqual(new[]{"191,1,64","159,36,100","143,36,0"}),"MIDI CC and note bytes are correct; panic releases only its own held note");}
fake.Commands.Clear();
using (var gesture = JsonDocument.Parse("{\"type\":\"taskView\"}")) {
    fake.Down(); PhoneTrackpad.Apply(gesture.RootElement, fake);
    Check(!fake.Held && fake.Commands.Contains("taskView"), "Task View releases any held drag before opening windows");
}
using (var gesture = JsonDocument.Parse("{\"type\":\"showDesktop\"}")) {
    fake.Down(); PhoneTrackpad.Apply(gesture.RootElement, fake);
    Check(!fake.Held && fake.Commands.Contains("showDesktop"), "Show Desktop releases dragging before its fixed shortcut");
}
using (var unknown = JsonDocument.Parse("{\"type\":\"key\",\"key\":\"A\"}")) {
    bool rejected = false;
    try { PhoneTrackpad.Apply(unknown.RootElement, fake); } catch (InvalidDataException) { rejected = true; }
    Check(rejected, "Arbitrary keyboard input remains unsupported");
}
fake.Commands.Clear();
IPAddress address = null;
using var pad = new PhoneTrackpad(() => address, fake, firewall, FreePort());
Check(!pad.Running && pad.PairingUrl == null, "Startup is off with no listener or pairing key");
Check(!pad.Start() && pad.Status.Contains("No local network") && firewall.OpenCount == 0, "No Wi-Fi returns a status without touching the firewall");
address = IPAddress.Loopback;
Check(pad.Start(), "Start on a local network");
string firstUrl = pad.PairingUrl;
using var client = new HttpClient();
string page = await client.GetStringAsync(new Uri(firstUrl).GetLeftPart(UriPartial.Path));
Check(page.Contains("Trackpad") && !page.Contains(new Uri(firstUrl).Fragment[1..]), "Public page does not disclose the pairing secret");
Check((await client.GetStringAsync(pad.DesktopUrl)).Contains("<svg"), "Desktop pairing page renders a local QR code");
Check(!PhoneTrackpad.CanShowPairing(IPAddress.Parse("192.168.1.5"), IPAddress.Parse("192.168.1.4")), "Other LAN devices cannot request the desktop pairing secret");
using (var headers = await client.GetAsync(new Uri(firstUrl).GetLeftPart(UriPartial.Path))) Check(headers.Headers.GetValues("Content-Security-Policy").Single().Contains("img-src data:;"), "Browser resource allows embedded app icons without remote image access");
Check((await client.GetAsync(new Uri(new Uri(firstUrl), "/not-a-file"))).StatusCode == HttpStatusCode.NotFound, "No arbitrary file access");
using (var forged = new HttpRequestMessage(HttpMethod.Get, new Uri(firstUrl).GetLeftPart(UriPartial.Path))) {
    forged.Headers.Host = "attacker.example";
    Check((await client.SendAsync(forged)).StatusCode != HttpStatusCode.OK, "Forged Host is rejected");
}
bool originBlocked = false;
try { using var ws = await Connect(firstUrl, origin: "https://attacker.example"); } catch (WebSocketException) { originBlocked = true; }
Check(originBlocked, "Cross-origin WebSocket is rejected");
using (var wrong = await Connect(firstUrl, "wrong")) {
    try { await Send(wrong, "{\"type\":\"down\"}"); await Receive(wrong); } catch (WebSocketException) { }
    Check(!fake.Held && fake.Commands.IsEmpty, "Wrong pairing token cannot inject input");
}
fake.FailMidiDiscovery = true;
using (var ws = await Connect(firstUrl)) {
    Check((await Receive(ws)).Contains("ready"), "Valid QR pairing authorizes a controller");
    await Send(ws,"{\"type\":\"ping\"}");
    Check((await Receive(ws)).Contains("pong"), "Heartbeat confirms the server is receiving input");
    await Send(ws,"{\"type\":\"move\",\"x\":1,\"y\":2}");
    await Until(() => fake.Commands.Contains("move:1,2"));
    Check(fake.FailMidiDiscovery,"Phone pairs and moves without calling an unavailable MIDI driver");
    fake.FailMidiDiscovery = false;
    await Send(ws,"{\"type\":\"info\"}");
    Check((await Receive(ws)).Contains("Test MIDI"),"MIDI discovery is available on demand after pairing");
    using (var other = await Connect(firstUrl)) {
        bool secondReady = false;
        try { secondReady = (await Receive(other)).Contains("ready"); } catch (WebSocketException) { }
        Check(!secondReady, "Only one controller can hold input");
    }
    await Send(ws, "{\"type\":\"move\",\"x\":13,\"y\":-8}");
    await Send(ws, "{\"type\":\"scroll\",\"x\":2,\"y\":30}");
    await Send(ws, "{\"type\":\"right\"}");
    await Send(ws, "{\"type\":\"down\"}");
    await Until(() => fake.Held);
    Check(fake.Commands.Contains("move:13,-8") && fake.Commands.Contains("scroll:2,30") && fake.Commands.Contains("right"), "Movement, scrolling and right-click reach the input boundary");
    await Send(ws,"{\"type\":\"appsBegin\"}");await Send(ws,"{\"type\":\"midiNote\",\"channel\":15,\"number\":36,\"value\":127}");await Until(()=>fake.Switching&&fake.MidiNotes>0);
    ws.Abort(); await Until(() => !fake.Held && !fake.Switching && fake.MidiNotes==0);
    Check(!fake.Held && !fake.Switching && fake.MidiNotes==0, "Unexpected disconnect releases drag, app switcher and MIDI notes");
}
using (var sleeping = await Connect(firstUrl, controller:"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")) {
    await Receive(sleeping); await Send(sleeping,"{\"type\":\"down\"}"); await Until(() => fake.Held);
    using var resumed = await Connect(firstUrl, controller:"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC");
    Check((await Receive(resumed)).Contains("ready") && !fake.Held, "The same phone reclaims its sleeping socket without waiting for timeout");
    await Send(resumed,"{\"type\":\"down\"}"); await Until(() => fake.Held);
    sleeping.Abort(); await Task.Delay(100);
    Check(fake.Held,"Old socket cleanup cannot release the resumed phone's drag");
    await Send(resumed,"{\"type\":\"move\",\"x\":8000,\"y\":-8000}");
    await Until(() => fake.Commands.Contains("move:8000,-8000"));
    Check(fake.Held,"Fast movement fits one bounded packet without dropping the controller");
}
await Until(() => !fake.Held);
using (var ws = await Connect(firstUrl)) {
    await Receive(ws); await Send(ws, "{\"type\":\"down\"}"); await Until(() => fake.Held);
    await Send(ws, "{\"type\":\"move\",\"x\":999999,\"y\":0}");
    await Until(() => !fake.Held);
    Check(pad.Running && !fake.Commands.Contains("move:999999,0"), "Malformed movement releases drag without stopping the host");
}
using (var ws = await Connect(firstUrl)) {
    await Receive(ws); await Send(ws, "{\"type\":\"down\"}"); await Until(() => fake.Held);
    address = null;
    await Until(() => !pad.Running);
    Check(!fake.Held && !firewall.IsOpen && pad.PairingUrl == null, "Wi-Fi loss stops only the trackpad, releases drag and closes its firewall rule");
}
address = IPAddress.Loopback;
Check(pad.Start() && pad.PairingUrl != firstUrl, "Restart after reconnect rotates the pairing secret");
using (var old = await Connect(pad.PairingUrl, new Uri(firstUrl).Fragment[1..])) {
    bool accepted = false; try { accepted = (await Receive(old)).Contains("ready"); } catch (WebSocketException) { }
    Check(!accepted, "A prior session's link is revoked");
}
using (var ws = await Connect(pad.PairingUrl)) {
    await Receive(ws); await Send(ws, "{\"type\":\"down\"}"); await Until(() => fake.Held);
    await Task.Delay(6500);
    Check(!fake.Held && pad.Running, "A suspended phone releases drag after the heartbeat timeout");
}
// Exercise watchOS HTTP control without sending native mouse input.
const string watch = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", otherWatch = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
string httpReply = null;
async Task<HttpStatusCode> Post(object payload, string origin = null, string key = null) {
    var uri = new Uri(pad.PairingUrl);
    using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(uri, "/control"));
    request.Headers.Add("Origin", origin ?? uri.GetLeftPart(UriPartial.Authority));
    request.Headers.Add("X-Trackpad-Token", key ?? uri.Fragment[1..]);
    request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
    using var response = await client.SendAsync(request);
    httpReply = await response.Content.ReadAsStringAsync();
    return response.StatusCode;
}
Check(await Post(new { client=watch,type="connect",sequence=1 }, origin:"https://other.example") == HttpStatusCode.Forbidden, "Watch POST rejects cross-site origins");
Check(await Post(new { client=watch,type="connect",sequence=1 }, key:"wrong") == HttpStatusCode.Unauthorized, "Watch POST distinguishes an expired pairing link from a dropped lease");
fake.FailMidiDiscovery = true;
Check(await Post(new { client=watch,type="connect",sequence=1 }) == HttpStatusCode.OK, "Watch connects over HTTP without WebSockets");
Check(httpReply.Contains("platform") && !httpReply.Contains("midi"), "Watch pairing returns platform information without MIDI driver discovery");
fake.FailMidiDiscovery = false;
Check(await Post(new { client=otherWatch,type="connect",sequence=1 }) == HttpStatusCode.Conflict, "A second watch cannot take over");
using (var ws = await Connect(pad.PairingUrl)) {
    bool accepted = false; try { accepted = (await Receive(ws)).Contains("ready"); } catch (WebSocketException) { }
    Check(!accepted, "Phone WebSocket cannot take over an active watch");
}
fake.Commands.Clear();
Check(await Post(new { client=watch,type="commands",sequence=2,commands=new object[]{new {type="down"},new {type="move",x=12,y=7},new {type="up"},new {type="left"},new {type="info"}} }) == HttpStatusCode.OK && !fake.Held && fake.Commands.ToArray().SequenceEqual(new[]{"down","move:12,7","up","left"}), "Watch command batches preserve drag and click order");
Check(httpReply.Contains("Test MIDI"), "Watch MIDI controls can request output discovery after pairing");
int beforeDuplicate = fake.Commands.Count;
Check(await Post(new { client=watch,type="commands",sequence=2,commands=new[]{new {type="left"}} }) == HttpStatusCode.Conflict && fake.Commands.Count == beforeDuplicate, "Retried watch requests never replay clicks");
await Post(new { client=watch,type="commands",sequence=3,commands=new[]{new {type="down"}} });
Check(await Post(new { client=watch,type="disconnect",sequence=5 }) == HttpStatusCode.OK && !fake.Held, "Watch handoff releases held dragging immediately");
Check(await Post(new { client=watch,type="commands",sequence=4,commands=new[]{new {type="down"}} }) == HttpStatusCode.Forbidden && !fake.Held, "In-flight input cannot arrive after a watch disconnect");
using (var ws = await Connect(pad.PairingUrl)) {
    await Receive(ws);
    Check(await Post(new { client=watch,type="connect",sequence=6 }) == HttpStatusCode.Conflict, "Watch cannot take over a connected phone");
}
await Until(() => pad.Status.Contains("disconnected"));
await Post(new { client=watch,type="connect",sequence=7 });
await Post(new { client=watch,type="commands",sequence=8,commands=new[]{new {type="down"}} });
Check(await Post(new { client=watch,type="commands",sequence=9,commands=new[]{new {type="move",x=999999,y=0}} }) == HttpStatusCode.BadRequest && !fake.Held, "Malformed watch input revokes control and releases dragging");
await Post(new { client=watch,type="connect",sequence=10 });
await Post(new { client=watch,type="commands",sequence=11,commands=new[]{new {type="down"}} });
await Task.Delay(6500); await Until(() => !fake.Held);
Check(!fake.Held && pad.Running, "Sleeping watch releases dragging after its heartbeat expires");
await Post(new { client=watch,type="connect",sequence=20 });
await Post(new { client=watch,type="commands",sequence=21,commands=new[]{new {type="down"}} });
Check(await Post(new { client=watch,type="connect",sequence=23 }) == HttpStatusCode.OK && !fake.Held, "The same watch resumes immediately and releases old dragging");
int beforeLate = fake.Commands.Count;
Check(await Post(new { client=watch,type="commands",sequence=22,commands=new[]{new {type="down"}} }) == HttpStatusCode.Conflict && fake.Commands.Count == beforeLate, "Commands from before wake cannot reach the resumed watch session");
Check(await Post(new { client=watch,type="disconnect",sequence=22 }) == HttpStatusCode.Conflict, "A late sleep disconnect cannot close the resumed watch session");
await Post(new { client=watch,type="disconnect",sequence=24 });
await Post(new { client=watch,type="connect",sequence=12 });
await Post(new { client=watch,type="commands",sequence=13,commands=new[]{new {type="down"}} });
address = null; await Until(() => !pad.Running);
Check(!fake.Held && !firewall.IsOpen, "Network loss releases watch control and closes only the receiver");
address = IPAddress.Loopback; pad.Start();
pad.Stop(); Check(!firewall.IsOpen && !pad.Running, "Explicit stop closes the optional service");
using var failing = new PhoneTrackpad(() => throw new NetworkInformationExceptionForTest(), fake, firewall, FreePort());
Check(!failing.Start(), "Network enumeration failure is contained");
var failingFirewall = new FakeFirewall { FailOpen = true };
using var blocked = new PhoneTrackpad(() => IPAddress.Loopback, fake, failingFirewall, FreePort());
Check(!blocked.Start() && !blocked.Running && !failingFirewall.IsOpen, "Firewall policy failure rolls back listener startup");
Check(!PhoneTrackpad.IsPrivateAddress(IPAddress.Parse("8.8.8.8")) && !PhoneTrackpad.IsPrivateAddress(IPAddress.Parse("169.254.1.2")) && PhoneTrackpad.IsPrivateAddress(IPAddress.Parse("172.20.10.2")), "Public and self-assigned IPs are excluded; hotspot LAN is accepted");
Console.WriteLine($"All {results.Count} checks passed.");

sealed class FakeInput : ITrackpadInput {
    public readonly ConcurrentQueue<string> Commands = new(); public volatile bool Held;
    public volatile bool Switching;public int MidiNotes;private int selected=-1;
    public bool FailMidiDiscovery;
    private int outputVolume=50;
    public object GetConnectionInfo()=>new {platform="windows",volume=new {available=true,level=outputVolume}};
    public void Volume(int level){outputVolume=level;Commands.Enqueue($"volume:{level}");}
    public object GetInfo(){if(FailMidiDiscovery)throw new InvalidOperationException("MIDI driver unavailable");return new {platform="windows",volume=new {available=true,level=outputVolume},midi=new {ports=new[]{new MidiPort(0,"Test MIDI (no hardware)")},selected,status="Test MIDI"}};}
    public void ReleaseAll(){Release();AppsEnd();MidiPanic();}
    public void AppsBegin(){Switching=true;Commands.Enqueue("appsBegin");}
    public void AppsStep(int direction)=>Commands.Enqueue($"appsStep:{direction}");
    public void AppsEnd(){if(Switching)Commands.Enqueue("appsEnd");Switching=false;}
    public void Desktop(int direction)=>Commands.Enqueue($"desktop:{direction}");
    public void Navigate(int direction){Switching=true;Commands.Enqueue($"navigate:{direction}");}
    public void NavigateEnd(){Commands.Enqueue("navigateEnd");AppsEnd();}
    public void Media(int action)=>Commands.Enqueue($"media:{action}");
    public void Shortcut(int id)=>Commands.Enqueue($"shortcut:{id}");
    public void VolumeStep(int direction)=>Commands.Enqueue($"volumeStep:{direction}");
    public void DragStart(int x,int y){Commands.Enqueue($"dragStart:{x},{y}");Held=true;}
    public void MidiPort(int id){selected=id;Commands.Enqueue($"midiPort:{id}");}
    public void Midi(bool note,int channel,int number,int value){if(note)MidiNotes=value>0?1:0;Commands.Enqueue($"midi:{note},{channel},{number},{value}");}
    public void MidiPanic(){MidiNotes=0;}
    public void Move(int x,int y) => Commands.Enqueue($"move:{x},{y}");
    public void Scroll(int x,int y) => Commands.Enqueue($"scroll:{x},{y}");
    public void Click(bool right) => Commands.Enqueue(right ? "right" : "left");
    public void Down() { Commands.Enqueue("down"); Held=true; }
    public void Release() { Commands.Enqueue("up"); Held=false; }
    public void TaskView() => Commands.Enqueue("taskView");
    public void ShowDesktop() => Commands.Enqueue("showDesktop");
}
sealed class FakeFirewall : ITrackpadFirewall {
    public int OpenCount; public bool IsOpen, FailOpen;
    public void Open(IPAddress address,int port) { OpenCount++; if(FailOpen) throw new Exception("Policy denied"); IsOpen=true; }
    public void Close() { IsOpen=false; }
}
sealed class NetworkInformationExceptionForTest : Exception { }
sealed class TestMidi:MidiOutput {
    public readonly List<string> Messages=new();
    public override MidiPort[] Ports()=>new[]{new MidiPort(0,"test")};
    protected override void Open(int id){}protected override void Close(){}
    protected override void Write(byte status,byte number,byte value)=>Messages.Add($"{status},{number},{value}");
}
