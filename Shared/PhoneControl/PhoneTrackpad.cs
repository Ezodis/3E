// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using QRCoder;

namespace ThreeE.PhoneControl;

// Optional, session-only LAN receiver. It is never started by normal app startup.
public sealed class PhoneTrackpad : IDisposable {
    public const int Port = 17833;
    public const string FirewallName = "3EWindows Phone Trackpad";
    // Shortcut ids are a fixed palette shared with Web/dock.js; hosts map each id
    // to a native key combination. The protocol never carries arbitrary keys.
    public const int ShortcutCount = 18;
    private readonly object gate = new();
    private readonly Func<IPAddress> addressProvider;
    private readonly ITrackpadInput input;
    private readonly ITrackpadFirewall firewall;
    private readonly int port;
    private Session session;
    private string status = "Off";
    private bool disposed;
    public string Status { get { lock (gate) return status; } }
    public bool Running { get { lock (gate) return session != null; } }
    public string PairingUrl { get { lock (gate) return session == null ? null : session.Origin + "/#" + session.Token; } }
    // Stable name link (for example http://3e-win.local:17833/#token) when an alias is served.
    public string NamedUrl { get { lock (gate) return session?.AliasOrigin == null ? null : session.AliasOrigin + "/#" + session.Token; } }
    public IPAddress Address { get { lock (gate) return session?.Address; } }
    // Optional: a persisted pairing secret keeps the phone's link valid across
    // restarts and updates. It must return 48 hex characters; anything else
    // falls back to a fresh random secret for this session.
    public Func<string> TokenProvider { get; init; }
    // Optional host name (for example "3e-win.local") also accepted for the
    // page, WebSocket and control requests. Name resolution is the host's job.
    public string AliasHost { get; init; }
    public string DesktopUrl { get { lock (gate) return session == null ? null : session.Origin + "/pair"; } }

    private sealed class Session {
        public readonly CancellationTokenSource Cancel = new();
        public readonly SemaphoreSlim Slots = new(4);
        public readonly HttpListener Listener = new();
        public readonly string Token;
        public readonly string Origin, AliasOrigin;
        public readonly IPAddress Address;
        public WebSocket Controller;
        public string ControllerClient;
        public string HttpController;
        public long HttpLastSeen, HttpSequence, HttpRateStart;
        public int HttpCount;
        public Session(IPAddress address, int port, string token, string alias) {
            Address = address; Origin = $"http://{address}:{port}"; Token = token;
            AliasOrigin = string.IsNullOrEmpty(alias) ? null : $"http://{alias}:{port}";
        }
        public bool IsOrigin(string origin) => origin != null && (origin == Origin || origin == AliasOrigin);
        public bool IsHost(string host) => host != null && (host == new Uri(Origin).Authority || AliasOrigin != null && host.Equals(new Uri(AliasOrigin).Authority, StringComparison.OrdinalIgnoreCase));
    }

    // Injectable boundaries let tests exercise network loss without disabling Wi-Fi or moving the user's mouse.
    public PhoneTrackpad(Func<IPAddress> addressProvider, ITrackpadInput input, ITrackpadFirewall firewall, int port) {
        this.addressProvider = addressProvider; this.input = input; this.firewall = firewall; this.port = port;
    }

    public static IPAddress GetLocalAddress() {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                (n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 || n.NetworkInterfaceType == NetworkInterfaceType.Ethernet))
            .OrderBy(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 ? 0 : 1)
            .Where(n => n.GetIPProperties().GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any)))
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork && IsPrivateAddress(a.Address))
            .Select(a => a.Address).FirstOrDefault();
    }

    public static bool IsPrivateAddress(IPAddress address) {
        var b = address.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || b[0] == 172 && b[1] >= 16 && b[1] <= 31 || b[0] == 192 && b[1] == 168);
    }

    public bool Start() {
        lock (gate) {
            if (disposed) return false;
            if (session != null) return true;
            Session candidate = null;
            try {
                var address = addressProvider();
                if (address == null) { status = "No local network — connect to Wi-Fi, then try again."; return false; }
                var token = SessionToken();
                candidate = new Session(address, port, token, AliasHost);
                candidate.Listener.Prefixes.Add(candidate.Origin + "/");
                if (candidate.AliasOrigin != null) candidate.Listener.Prefixes.Add(candidate.AliasOrigin + "/");
                try { candidate.Listener.Start(); }
                catch (HttpListenerException) when (candidate.AliasOrigin != null) {
                    // Some macOS HttpListener builds reject a second named prefix.
                    // Listen on the wildcard socket but retain and validate both
                    // approved Host/Origin values so the stable alias URL works.
                    candidate.Listener.Close();
                    candidate = new Session(address, port, token, AliasHost);
                    candidate.Listener.Prefixes.Add($"http://*:{port}/");
                    candidate.Listener.Start();
                }
                firewall.Open(address, port);
                session = candidate;
                status = "Ready — scan the QR code on your iPhone.";
                _ = Task.Run(() => ListenAsync(candidate));
                _ = Task.Run(() => MonitorAsync(candidate));
                return true;
            } catch (Exception ex) {
                candidate?.Listener.Close();
                try { firewall.Close(); } catch { }
                status = "Trackpad unavailable: " + ex.Message + " Other 3£ features are unaffected.";
                return false;
            }
        }
    }

    private string SessionToken() {
        try {
            var stored = TokenProvider?.Invoke();
            if (stored != null && stored.Length == 48 && stored.All(Uri.IsHexDigit)) return stored.ToUpperInvariant();
        } catch { }
        return Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
    }

    public void Stop() { lock (gate) StopLocked("Off"); }
    private void StopLocked(string reason) {
        var previous = session;
        session = null;
        status = reason;
        if (previous == null) return;
        previous.Cancel.Cancel();
        previous.Listener.Close();
        previous.Controller?.Abort();
        try { input.ReleaseAll(); } catch { }
        try { firewall.Close(); } catch { status += " — Windows could not remove the trackpad firewall rule."; }
    }

    private async Task MonitorAsync(Session owner) {
        try {
            while (!owner.Cancel.IsCancellationRequested) {
                await Task.Delay(1500, owner.Cancel.Token);
                // Adapter enumeration can block on a driver. It must never hold
                // the lock used for incoming pointer/keyboard/MIDI commands.
                var address = addressProvider();
                lock (gate) {
                    if (session != owner) return;
                    if (owner.HttpController != null && Environment.TickCount64 - owner.HttpLastSeen > 6000) {
                        ReleaseHttpLocked(owner);
                        status = "Watch asleep — reconnects when its page returns.";
                    }
                    if (!owner.Address.Equals(address)) {
                        StopLocked("Network changed or disconnected — reconnect to Wi-Fi, then start again.");
                        return;
                    }
                }
            }
        } catch (OperationCanceledException) { }
        catch { lock (gate) { if (session == owner) StopLocked("No local network — reconnect to Wi-Fi, then start again."); } }
    }

    private async Task ListenAsync(Session owner) {
        try {
            while (!owner.Cancel.IsCancellationRequested) {
                var context = await owner.Listener.GetContextAsync();
                if (!owner.Slots.Wait(0)) { context.Response.StatusCode = 503; context.Response.Close(); continue; }
                _ = HandleAsync(owner, context);
            }
        } catch {
            lock (gate) { if (session == owner) StopLocked("Trackpad connection stopped — start again to reconnect."); }
        }
    }

    private async Task HandleAsync(Session owner, HttpListenerContext context) {
        try {
            var request = context.Request;
            // Literal bound host and same-origin WebSockets prevent DNS rebinding / cross-site control.
            if (!owner.IsHost(request.Headers["Host"])) {
                context.Response.StatusCode = 403; context.Response.Close(); return;
            }
            if (request.Url.AbsolutePath == "/control" && request.HttpMethod == "POST") {
                await HttpControlAsync(owner, context); return;
            }
            if (request.HttpMethod != "GET") { context.Response.StatusCode = 403; context.Response.Close(); return; }
            if (request.Url.AbsolutePath == "/ws" && request.IsWebSocketRequest) {
                if (!owner.IsOrigin(request.Headers["Origin"]) || request.Url.Query.Length != 0) {
                    context.Response.StatusCode = 403; context.Response.Close(); return;
                }
                using var ws = (await context.AcceptWebSocketAsync(null)).WebSocket;
                await ControlAsync(owner, ws);
                return;
            }
            if (request.Url.AbsolutePath == "/alive") {
                // Lets a page opened by IP check that the stable name reaches this
                // receiver before switching to it. Reveals no pairing data.
                var origin = request.Headers["Origin"];
                if (owner.IsOrigin(origin)) context.Response.Headers["Access-Control-Allow-Origin"] = origin;
                context.Response.Headers["Cache-Control"] = "no-store";
                context.Response.StatusCode = 204; context.Response.Close(); return;
            }
            bool pairing = request.Url.AbsolutePath == "/pair";
            if (pairing && !CanShowPairing(request.RemoteEndPoint.Address, owner.Address)) {
                context.Response.StatusCode = 403; context.Response.Close(); return;
            }
            var resource = request.Url.AbsolutePath switch { "/" => "PhoneTrackpad.html", "/pad.js" => "PhoneTrackpad.js", "/surface.js" => "surface.js", "/dock.js" => "dock.js", "/surface.css" => "surface.css", "/host.js" => "host.js", "/pair" => "pair", _ => null };
            if (resource == null) { context.Response.StatusCode = 404; context.Response.Close(); return; }
            var response = context.Response;
            response.ContentType = resource.EndsWith(".js") ? "text/javascript; charset=utf-8" : resource.EndsWith(".css") ? "text/css; charset=utf-8" : "text/html; charset=utf-8";
            response.Headers["Cache-Control"] = "no-store";
            response.Headers["Referrer-Policy"] = "no-referrer";
            response.Headers["X-Content-Type-Options"] = "nosniff";
            response.Headers["Content-Security-Policy"] = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src data:; connect-src " + string.Join(" ", new[] { owner.Origin, owner.AliasOrigin }.Where(o => o != null).SelectMany(o => new[] { o, o.Replace("http:", "ws:") })) + "; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
            using var stream = pairing
                ? new MemoryStream(Encoding.UTF8.GetBytes(PairingPage(owner.Origin + "/#" + owner.Token)))
                : resource == "host.js" ? new MemoryStream(Encoding.UTF8.GetBytes("window.ThreeEHost="+JsonSerializer.Serialize(new { platform=input.Platform, http=false, alias=owner.AliasOrigin == null ? null : new Uri(owner.AliasOrigin).Authority })+";"))
                : typeof(PhoneTrackpad).Assembly.GetManifestResourceStream("ThreeE.PhoneControl.Web." + resource);
            response.ContentLength64 = stream.Length;
            await stream.CopyToAsync(response.OutputStream, owner.Cancel.Token);
            response.Close();
        } catch { try { context.Response.Abort(); } catch { } }
        finally { owner.Slots.Release(); }
    }

    public static bool CanShowPairing(IPAddress remote, IPAddress local) => IPAddress.IsLoopback(remote) || remote.Equals(local);

    private void ReleaseHttpLocked(Session owner) {
        owner.HttpController = null;
        try { input.ReleaseAll(); } catch { }
    }

    // watchOS WebKit disables WebSockets by default. Short authenticated POSTs
    // share the same single-controller lock and disconnect watchdog as the phone.
    private async Task HttpControlAsync(Session owner, HttpListenerContext context) {
        var request = context.Request;
        var response = context.Response;
        response.Headers["Cache-Control"] = "no-store";
        response.Headers["X-Content-Type-Options"] = "nosniff";
        string client = null;
        int code = 200;
        bool describe = false, handshake = false;
        try {
            var supplied = Encoding.UTF8.GetBytes(request.Headers["X-Trackpad-Token"] ?? "");
            if (!owner.IsOrigin(request.Headers["Origin"]) || request.Url.Query.Length != 0 ||
                request.ContentType?.Split(';')[0] != "application/json") {
                response.StatusCode = 403; response.Close(); return;
            }
            if (!CryptographicOperations.FixedTimeEquals(supplied, Encoding.UTF8.GetBytes(owner.Token))) {
                response.StatusCode = 401; response.Close(); return;
            }
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(owner.Cancel.Token);
            timeout.CancelAfter(3000);
            var bytes = new byte[4097];
            int count = 0, read;
            while ((read = await request.InputStream.ReadAsync(bytes.AsMemory(count), timeout.Token)) > 0) {
                count += read;
                if (count > 4096) { response.StatusCode = 413; response.Close(); return; }
            }
            using var json = JsonDocument.Parse(bytes.AsMemory(0, count), new JsonDocumentOptions { MaxDepth = 5 });
            var root = json.RootElement;
            client = root.GetProperty("client").GetString();
            if (client == null || client.Length != 32 || !client.All(Uri.IsHexDigit)) throw new InvalidDataException();
            string type = root.GetProperty("type").GetString();
            long sequence = root.GetProperty("sequence").GetInt64();
            if (sequence < 0) throw new InvalidDataException();
            lock (gate) {
                if (session != owner) code = 410;
                else if (type == "connect") {
                    handshake = true;
                    if (owner.Controller != null || (owner.HttpController != null && owner.HttpController != client) ||
                        (owner.HttpController == client && sequence <= owner.HttpSequence)) code = 409;
                    else {
                        // The same page can reclaim its sleeping connection immediately.
                        // A larger sequence prevents late commands/disconnects from the old connection.
                        if (owner.HttpController == client) input.ReleaseAll();
                        owner.HttpController = client; owner.HttpSequence = sequence;
                        owner.HttpLastSeen = owner.HttpRateStart = Environment.TickCount64; owner.HttpCount = 0;
                        status = "Connected to your watch";
                    }
                } else if (owner.HttpController != client) code = 403;
                else if (sequence <= owner.HttpSequence) code = 409;
                else {
                    owner.HttpSequence = sequence;
                    if (type == "disconnect") { ReleaseHttpLocked(owner); status = "Watch disconnected — reconnects when its page returns."; }
                    else if (type == "commands") {
                        var commands = root.GetProperty("commands");
                        if (commands.ValueKind != JsonValueKind.Array || commands.GetArrayLength() > 24) throw new InvalidDataException();
                        long now = Environment.TickCount64;
                        if (now - owner.HttpRateStart >= 1000) { owner.HttpRateStart = now; owner.HttpCount = 0; }
                        owner.HttpCount += commands.GetArrayLength();
                        if (owner.HttpCount > 600) throw new InvalidDataException();
                        foreach (var command in commands.EnumerateArray()) { Apply(command, input); if(command.GetProperty("type").GetString() is "info" or "midiPort") describe=true; if(command.GetProperty("type").GetString()=="ping")handshake=true; }
                        owner.HttpLastSeen = now;
                    } else throw new InvalidDataException();
                }
            }
        } catch {
            code = 400;
            lock (gate) { if (session == owner && client != null && owner.HttpController == client) ReleaseHttpLocked(owner); }
        }
        response.StatusCode = code;
        response.ContentType = "application/json";
        byte[] result;
        lock(gate) result = Encoding.UTF8.GetBytes(code == 200 ? (describe || handshake ? JsonSerializer.Serialize(new { ready=true, host=describe ? input.GetInfo() : input.GetConnectionInfo() }) : "{\"ready\":true}") : "{\"ready\":false}");
        response.ContentLength64 = result.Length;
        await response.OutputStream.WriteAsync(result, owner.Cancel.Token);
        response.Close();
    }

    private static string PairingPage(string link) {
        using var data = QRCodeGenerator.GenerateQrCode(link, QRCodeGenerator.ECCLevel.M);
        using var qr = new SvgQRCode(data);
        return """
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>3£Windows · Pair your iPhone</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#111820;color:#eaf2f7;font:16px/1.65 system-ui,sans-serif;min-height:100vh;display:grid;place-items:center;padding:28px}
main{width:100%;max-width:620px}small{color:#a8e5cd;font-weight:600;letter-spacing:.08em}h1{font-size:38px;line-height:1.15;letter-spacing:-1.2px;margin:12px 0 20px}p{color:#b9cbd8}
.qr{background:white;padding:12px;width:280px;max-width:100%;border-radius:18px;margin:28px auto}.qr svg{display:block;width:100%;height:auto}
input{width:100%;padding:13px;border:1px solid #415260;border-radius:10px;background:#1b2b36;color:#eaf2f7;font:14px system-ui}label{display:block;font-size:14px;margin-bottom:8px}
.note{border-top:1px solid #344755;padding-top:18px;font-size:14px}.steps{color:#eaf2f7}strong{color:#eaf2f7}
</style><main><small>3£WINDOWS · LOCAL CONNECTION</small><h1>Your iPhone is<br>your trackpad.</h1>
<p class="steps">Connect your iPhone to the same trusted Wi-Fi as this laptop.<br>Open <strong>Camera</strong>, scan this code, then open the link in <strong>Safari</strong>.</p>
<div class="qr">
""" + qr.GetGraphic(4) + """
</div><label for="link">Pairing link — keep it private</label><input id="link" readonly value="
""" + link + """
">
<p>One finger to move and tap. Two fingers to scroll or right-click. Three fingers to drag. Keep Safari open while using it.</p>
<p class="note"><strong>No internet or iPhone app needed.</strong><br>To stop, open the 3£Windows tray menu and choose <strong>Stop iPhone trackpad</strong>. Closing this page keeps the session running. Wi-Fi loss stops the trackpad; start it again from the tray after reconnecting. Your other controls keep working.</p>
</main></html>
""";
    }

    private static async Task<JsonDocument> ReceiveAsync(WebSocket ws, CancellationToken stop, int seconds) {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stop);
        timeout.CancelAfter(TimeSpan.FromSeconds(seconds));
        var buffer = new byte[1024];
        var count = 0;
        WebSocketReceiveResult part;
        do {
            part = await ws.ReceiveAsync(new ArraySegment<byte>(buffer, count, buffer.Length - count), timeout.Token);
            if (part.MessageType != WebSocketMessageType.Text) throw new InvalidDataException("Text messages required.");
            count += part.Count;
            if (!part.EndOfMessage && count == buffer.Length) throw new InvalidDataException("Message too long.");
        } while (!part.EndOfMessage);
        return JsonDocument.Parse(buffer.AsMemory(0, count), new JsonDocumentOptions { MaxDepth = 4 });
    }

    private async Task ControlAsync(Session owner, WebSocket ws) {
        bool acquired = false;
        try {
            using var auth = await ReceiveAsync(ws, owner.Cancel.Token, 5);
            if (!auth.RootElement.TryGetProperty("token", out var token) || token.ValueKind != JsonValueKind.String) return;
            var supplied = Encoding.UTF8.GetBytes(token.GetString());
            if (!CryptographicOperations.FixedTimeEquals(supplied, Encoding.UTF8.GetBytes(owner.Token))) {
                await ws.SendAsync(Encoding.UTF8.GetBytes("{\"error\":\"pairing\"}"), WebSocketMessageType.Text, true, owner.Cancel.Token); return;
            }
            string client = auth.RootElement.TryGetProperty("client",out var clientProperty) ? clientProperty.GetString() : null;
            if (client != null && (client.Length != 32 || !client.All(Uri.IsHexDigit))) return;
            lock (gate) {
                if (session != owner) return;
                if (owner.HttpController == null && (owner.Controller == null || client != null && owner.ControllerClient == client)) {
                    if (owner.Controller != null) { input.ReleaseAll(); owner.Controller.Abort(); }
                    owner.Controller = ws; owner.ControllerClient = client; acquired = true; status = "Connected to your phone";
                }
            }
            if (!acquired) { await ws.SendAsync(Encoding.UTF8.GetBytes("{\"error\":\"busy\"}"), WebSocketMessageType.Text, true, owner.Cancel.Token); return; }
            // Connecting the trackpad must not wait on native MIDI driver discovery.
            // The MIDI surface requests the full description when it opens.
            string lastHost = JsonSerializer.Serialize(input.GetConnectionInfo());
            await ws.SendAsync(Encoding.UTF8.GetBytes("{\"ready\":true,\"host\":" + lastHost + "}"), WebSocketMessageType.Text, true, owner.Cancel.Token);
            var rateStart = Environment.TickCount64;
            var count = 0;
            while (ws.State == WebSocketState.Open) {
                using var message = await ReceiveAsync(ws, owner.Cancel.Token, 6);
                var now = Environment.TickCount64;
                if (now - rateStart >= 1000) { rateStart = now; count = 0; }
                if (++count > 600) throw new InvalidDataException("Too many commands.");
                lock (gate) {
                    if (session != owner || owner.Controller != ws) return;
                    Apply(message.RootElement, input);
                }
                if (message.RootElement.GetProperty("type").GetString() == "ping") {
                    // Heartbeats stay a few bytes; host state is resent only when it changed.
                    var host = JsonSerializer.Serialize(input.GetConnectionInfo());
                    var reply = host == lastHost ? "{\"pong\":true}" : "{\"pong\":true,\"host\":" + host + "}";
                    lastHost = host;
                    await ws.SendAsync(Encoding.UTF8.GetBytes(reply), WebSocketMessageType.Text, true, owner.Cancel.Token);
                }
                if (message.RootElement.GetProperty("type").GetString() is "midiPort" or "info")
                    await ws.SendAsync(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new {host=input.GetInfo()})), WebSocketMessageType.Text, true, owner.Cancel.Token);
            }
        } catch { /* Disconnects, sleep and malformed packets affect only this controller. */ }
        finally {
            lock (gate) {
                if (acquired && session == owner && owner.Controller == ws) {
                    try { input.ReleaseAll(); } catch { }
                    owner.Controller = null;
                    owner.ControllerClient = null;
                    status = "Phone disconnected — reconnects when its page returns.";
                }
            }
            ws.Abort();
        }
    }

    public static void Apply(JsonElement command, ITrackpadInput sink) {
        if (command.ValueKind != JsonValueKind.Object || !command.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Invalid command.");
        int Number(string name, int limit = 1000) {
            if (!command.TryGetProperty(name, out var value) || !value.TryGetInt32(out var number) || number < -limit || number > limit)
                throw new InvalidDataException("Invalid movement.");
            return number;
        }
        int Range(string name,int min,int max) { int n=Number(name,Math.Max(Math.Abs(min),max)); if(n<min || n>max) throw new InvalidDataException("Invalid control value."); return n; }
        switch (type.GetString()) {
            case "move": sink.Move(Number("x",8000), Number("y",8000)); break;
            case "scroll": sink.Scroll(Number("x"), Number("y")); break;
            case "left": sink.Click(false); break;
            case "right": sink.Click(true); break;
            case "down": sink.Down(); break;
            case "dragStart": sink.DragStart(Range("x",-1,1),Range("y",-1,1)); break;
            case "up": sink.Release(); break;
            case "taskView": sink.Release(); sink.TaskView(); break;
            case "showDesktop": sink.Release(); sink.ShowDesktop(); break;
            case "desktop": sink.Desktop(Range("direction",-1,1)); break;
            case "navigate": sink.Navigate(Range("direction",-1,1)); break;
            case "navigateEnd": sink.NavigateEnd(); break;
            case "appsBegin": sink.Release(); sink.AppsBegin(); break;
            case "appsStep": sink.AppsStep(Range("direction",-1,1)); break;
            case "appsEnd": sink.AppsEnd(); break;
            case "media": sink.Media(Range("action",0,2)); break;
            case "volume": sink.Volume(Range("level",0,100)); break;
            case "volumeStep": sink.VolumeStep(Range("direction",-1,1)); break;
            case "history": sink.History(Range("direction",-1,1)); break;
            case "zoom": sink.Zoom(Range("direction",-1,1)); break;
            case "midiPort": sink.MidiPort(Range("id",-1,1024)); break;
            case "midiCC": sink.Midi(false,Range("channel",0,15),Range("number",0,119),Range("value",0,127)); break;
            case "midiNote": sink.Midi(true,Range("channel",0,15),Range("number",0,127),Range("value",0,127)); break;
            case "midiPanic": sink.MidiPanic(); break;
            case "shortcut": sink.Shortcut(Range("id",0,ShortcutCount-1)); break;
            case "releaseAll": sink.ReleaseAll(); break;
            case "info": break;
            case "ping": break;
            default: throw new InvalidDataException("Unknown command.");
        }
    }

    public void Dispose() { lock (gate) { if(disposed)return; disposed = true; StopLocked("Off"); if(input is IDisposable resource) resource.Dispose(); } }
}

public interface ITrackpadInput {
    void Move(int x, int y); void Scroll(int x, int y); void Click(bool right); void Down(); void Release();
    void TaskView(); void ShowDesktop();
    string Platform => "windows";
    object GetConnectionInfo() => new {platform=Platform};
    object GetInfo() => new {platform=Platform,midi=new {ports=Array.Empty<MidiPort>(),selected=-1,status="No MIDI output"}};
    void ReleaseAll() => Release();
    void Desktop(int direction) { }
    void Navigate(int direction) { }
    void NavigateEnd() => AppsEnd();
    void AppsBegin() { }
    void AppsStep(int direction) { }
    void AppsEnd() { }
    void Media(int action) { }
    void Volume(int level) { }
    // One native volume step (Windows: the volume keys, which show the system OSD).
    void VolumeStep(int direction) { }
    // Two-finger sideways swipe: -1 back, 1 forward (browser/Explorer history).
    void History(int direction) { }
    // Pinch: 1 zoom in, -1 zoom out (one step).
    void Zoom(int direction) { }
    void MidiPort(int id) { }
    void Midi(bool note,int channel,int number,int value) { }
    void MidiPanic() { }
    void Shortcut(int id) { }
    // Press for a tap-then-drag. Hosts must not let it complete a double-click.
    void DragStart(int x, int y) => Down();
}
public interface ITrackpadFirewall { void Open(IPAddress address, int port); void Close(); }
