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

namespace ThreeFingerDragOnWindows;

// Optional, session-only LAN receiver. It is never started by normal app startup.
public sealed class PhoneTrackpad : IDisposable {
    public const int Port = 17833;
    public const string FirewallName = "3EWindows Phone Trackpad";
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
    public string DesktopUrl { get { lock (gate) return session == null ? null : session.Origin + "/pair"; } }

    private sealed class Session {
        public readonly CancellationTokenSource Cancel = new();
        public readonly SemaphoreSlim Slots = new(4);
        public readonly HttpListener Listener = new();
        public readonly string Token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        public readonly string Origin;
        public readonly IPAddress Address;
        public WebSocket Controller;
        public Session(IPAddress address, int port) { Address = address; Origin = $"http://{address}:{port}"; }
    }

    public PhoneTrackpad() : this(GetLocalAddress, new NativeTrackpadInput(), new TrackpadFirewall(), Port) { }
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
                candidate = new Session(address, port);
                candidate.Listener.Prefixes.Add(candidate.Origin + "/");
                candidate.Listener.Start();
                firewall.Open(address, port);
                session = candidate;
                status = "Ready — scan the QR code on your iPhone.";
                _ = Task.Run(() => ListenAsync(candidate));
                _ = Task.Run(() => MonitorAsync(candidate));
                return true;
            } catch (Exception ex) {
                candidate?.Listener.Close();
                try { firewall.Close(); } catch { }
                status = "Trackpad unavailable: " + ex.Message + " Other 3£Windows features are unaffected.";
                return false;
            }
        }
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
        try { input.Release(); } catch { }
        try { firewall.Close(); } catch { status += " — Windows could not remove the trackpad firewall rule."; }
    }

    private async Task MonitorAsync(Session owner) {
        try {
            while (!owner.Cancel.IsCancellationRequested) {
                await Task.Delay(1500, owner.Cancel.Token);
                lock (gate) {
                    if (session != owner) return;
                    var address = addressProvider();
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
            if (request.HttpMethod != "GET" || request.Headers["Host"] != new Uri(owner.Origin).Authority) {
                context.Response.StatusCode = 403; context.Response.Close(); return;
            }
            if (request.Url.AbsolutePath == "/ws" && request.IsWebSocketRequest) {
                if (request.Headers["Origin"] != owner.Origin || request.Url.Query.Length != 0) {
                    context.Response.StatusCode = 403; context.Response.Close(); return;
                }
                using var ws = (await context.AcceptWebSocketAsync(null)).WebSocket;
                await ControlAsync(owner, ws);
                return;
            }
            bool pairing = request.Url.AbsolutePath == "/pair";
            if (pairing && !CanShowPairing(request.RemoteEndPoint.Address, owner.Address)) {
                context.Response.StatusCode = 403; context.Response.Close(); return;
            }
            var resource = request.Url.AbsolutePath switch { "/" => "PhoneTrackpad.html", "/pad.js" => "PhoneTrackpad.js", "/pair" => "pair", _ => null };
            if (resource == null) { context.Response.StatusCode = 404; context.Response.Close(); return; }
            var response = context.Response;
            response.ContentType = resource.EndsWith(".js") ? "text/javascript; charset=utf-8" : "text/html; charset=utf-8";
            response.Headers["Cache-Control"] = "no-store";
            response.Headers["Referrer-Policy"] = "no-referrer";
            response.Headers["X-Content-Type-Options"] = "nosniff";
            response.Headers["Content-Security-Policy"] = "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src " + owner.Origin.Replace("http:", "ws:") + "; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
            using var stream = pairing
                ? new MemoryStream(Encoding.UTF8.GetBytes(PairingPage(owner.Origin + "/#" + owner.Token)))
                : typeof(PhoneTrackpad).Assembly.GetManifestResourceStream("ThreeFingerDragOnWindows." + resource);
            response.ContentLength64 = stream.Length;
            await stream.CopyToAsync(response.OutputStream, owner.Cancel.Token);
            response.Close();
        } catch { try { context.Response.Abort(); } catch { } }
        finally { owner.Slots.Release(); }
    }

    public static bool CanShowPairing(IPAddress remote, IPAddress local) => IPAddress.IsLoopback(remote) || remote.Equals(local);

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
            if (!CryptographicOperations.FixedTimeEquals(supplied, Encoding.UTF8.GetBytes(owner.Token))) return;
            lock (gate) {
                if (session != owner || owner.Controller != null) return;
                owner.Controller = ws; acquired = true; status = "Connected to your iPhone";
            }
            await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes("{\"ready\":true}")), WebSocketMessageType.Text, true, owner.Cancel.Token);
            var rateStart = Environment.TickCount64;
            var count = 0;
            while (ws.State == WebSocketState.Open) {
                using var message = await ReceiveAsync(ws, owner.Cancel.Token, 6);
                var now = Environment.TickCount64;
                if (now - rateStart >= 1000) { rateStart = now; count = 0; }
                if (++count > 300) throw new InvalidDataException("Too many commands.");
                lock (gate) {
                    if (session != owner) return;
                    Apply(message.RootElement, input);
                }
            }
        } catch { /* Disconnects, sleep and malformed packets affect only this controller. */ }
        finally {
            lock (gate) {
                if (acquired && session == owner && owner.Controller == ws) {
                    try { input.Release(); } catch { }
                    owner.Controller = null;
                    status = "Phone disconnected — reopen the trackpad to reconnect.";
                }
            }
            ws.Abort();
        }
    }

    public static void Apply(JsonElement command, ITrackpadInput sink) {
        if (command.ValueKind != JsonValueKind.Object || !command.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Invalid command.");
        int Number(string name) {
            if (!command.TryGetProperty(name, out var value) || !value.TryGetInt32(out var number) || number < -1000 || number > 1000)
                throw new InvalidDataException("Invalid movement.");
            return number;
        }
        switch (type.GetString()) {
            case "move": sink.Move(Number("x"), Number("y")); break;
            case "scroll": sink.Scroll(Number("x"), Number("y")); break;
            case "left": sink.Click(false); break;
            case "right": sink.Click(true); break;
            case "down": sink.Down(); break;
            case "up": sink.Release(); break;
            case "ping": break;
            default: throw new InvalidDataException("Unknown command.");
        }
    }

    public void Dispose() { lock (gate) { StopLocked("Off"); disposed = true; } }
}

public interface ITrackpadInput {
    void Move(int x, int y); void Scroll(int x, int y); void Click(bool right); void Down(); void Release();
}
public interface ITrackpadFirewall { void Open(IPAddress address, int port); void Close(); }

public sealed class TrackpadFirewall : ITrackpadFirewall {
    public void Open(IPAddress address, int port) {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        dynamic rule = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FWRule"));
        try {
            policy.Rules.Remove(PhoneTrackpad.FirewallName);
            rule.Name = PhoneTrackpad.FirewallName;
            rule.Description = "Optional local iPhone trackpad. Open only during a manually started session.";
            rule.Protocol = 6; rule.LocalPorts = port.ToString();
            rule.LocalAddresses = address.ToString(); rule.RemoteAddresses = "LocalSubnet";
            rule.Direction = 1; rule.Action = 1; rule.Profiles = int.MaxValue;
            rule.EdgeTraversal = false; rule.Enabled = true;
            policy.Rules.Add(rule);
        } finally { Marshal.FinalReleaseComObject(rule); Marshal.FinalReleaseComObject(policy); }
    }
    public void Close() {
        dynamic policy = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2"));
        try { policy.Rules.Remove(PhoneTrackpad.FirewallName); } finally { Marshal.FinalReleaseComObject(policy); }
    }
}

public sealed class NativeTrackpadInput : ITrackpadInput {
    [StructLayout(LayoutKind.Sequential)] private struct Mouse { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public Mouse Mouse; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    private bool held;
    private static void Send(uint flags, int x = 0, int y = 0, int data = 0) {
        var inputs = new[] { new Input { Mouse = new Mouse { X = x, Y = y, Data = unchecked((uint)data), Flags = flags } } };
        if (SendInput(1, inputs, Marshal.SizeOf<Input>()) != 1) throw new InvalidOperationException("Windows could not accept trackpad input.");
    }
    public void Move(int x, int y) { if (x != 0 || y != 0) Send(0x0001, x, y); }
    public void Scroll(int x, int y) { if (y != 0) Send(0x0800, data: y); if (x != 0) Send(0x1000, data: x); }
    public void Click(bool right) {
        if (held) return;
        uint down = right ? 0x0008u : 0x0002u, up = right ? 0x0010u : 0x0004u;
        try { Send(down); } finally { Send(up); }
    }
    public void Down() { if (!held) { Send(0x0002); held = true; } }
    public void Release() { if (held) { try { Send(0x0004); } finally { held = false; } } }
}
