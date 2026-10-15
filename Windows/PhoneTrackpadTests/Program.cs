using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Collections.Concurrent;
using ThreeFingerDragOnWindows;

var results = new List<string>();
void Check(bool value, string name) { if (!value) throw new Exception("FAIL: " + name); results.Add(name); Console.WriteLine("PASS: " + name); }
int FreePort() { var socket = new TcpListener(IPAddress.Loopback, 0); socket.Start(); int port = ((IPEndPoint)socket.LocalEndpoint).Port; socket.Stop(); return port; }
async Task Until(Func<bool> condition) { for (int i=0;i<100;i++) { if (condition()) return; await Task.Delay(50); } throw new Exception("Timed out waiting for state."); }
async Task<ClientWebSocket> Connect(string url, string token = null, string origin = null) {
    var ws = new ClientWebSocket(); var uri = new Uri(url);
    ws.Options.SetRequestHeader("Origin", origin ?? uri.GetLeftPart(UriPartial.Authority));
    await ws.ConnectAsync(new Uri("ws://" + uri.Authority + "/ws"), CancellationToken.None);
    await ws.SendAsync(Encoding.UTF8.GetBytes("{\"token\":\"" + (token ?? uri.Fragment[1..]) + "\"}"), WebSocketMessageType.Text, true, CancellationToken.None);
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

var fake = new FakeInput(); var firewall = new FakeFirewall();
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
using (var headers = await client.GetAsync(new Uri(firstUrl).GetLeftPart(UriPartial.Path))) Check(headers.Headers.Contains("Content-Security-Policy"), "Browser resource has origin restrictions");
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
using (var ws = await Connect(firstUrl)) {
    Check((await Receive(ws)).Contains("ready"), "Valid QR pairing authorizes a controller");
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
    ws.Abort(); await Until(() => !fake.Held);
    Check(!fake.Held, "Unexpected phone disconnect releases a held drag");
}
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
    public void Move(int x,int y) => Commands.Enqueue($"move:{x},{y}");
    public void Scroll(int x,int y) => Commands.Enqueue($"scroll:{x},{y}");
    public void Click(bool right) => Commands.Enqueue(right ? "right" : "left");
    public void Down() { Commands.Enqueue("down"); Held=true; }
    public void Release() { Commands.Enqueue("up"); Held=false; }
}
sealed class FakeFirewall : ITrackpadFirewall {
    public int OpenCount; public bool IsOpen, FailOpen;
    public void Open(IPAddress address,int port) { OpenCount++; if(FailOpen) throw new Exception("Policy denied"); IsOpen=true; }
    public void Close() { IsOpen=false; }
}
sealed class NetworkInformationExceptionForTest : Exception { }
