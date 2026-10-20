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
    // Optional: keep the same link alive while the local IP changes. A new
    // address rebinds the listener with the same pairing secret; losing the
    // network pauses the receiver and resumes it automatically when a local
    // network returns. Explicit Stop() always ends it. Combined with a
    // persisted TokenProvider and an mDNS AliasHost, the NamedUrl never changes.
    public bool FollowNetwork { get; init; }
    // Identifies the phone page this receiver serves. A phone page that
    // reconnects to a receiver reporting a different build reloads itself
    // once, so an update to the computer reaches the phone without a manual
    // reload. Tests may override it; hosts use the default.
    public string Build { get => build ?? PageBuild; init => build = value; }
    private readonly string build;
    private static readonly Lazy<string> pageBuild = new(() => ComputeBuild(EmbeddedPage(),
        // The module id changes whenever the receiver code that writes host.js
        // or brands the page changes, even if no Web/* file did.
        typeof(PhoneTrackpad).Assembly.ManifestModule.ModuleVersionId.ToString("N")));
    public static string PageBuild => pageBuild.Value;

    // A short, stable hash of the page resources (name and contents, in name order).
    public static string ComputeBuild(IEnumerable<KeyValuePair<string, byte[]>> resources, string salt = null) {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var (name, data) in resources.OrderBy(r => r.Key, StringComparer.Ordinal)) {
            var key = Encoding.UTF8.GetBytes(name);
            hash.AppendData(BitConverter.GetBytes(key.Length)); hash.AppendData(key);
            hash.AppendData(BitConverter.GetBytes((long)data.Length)); hash.AppendData(data);
        }
        if (salt != null) hash.AppendData(Encoding.UTF8.GetBytes(salt));
        return Convert.ToHexString(hash.GetHashAndReset(), 0, 8).ToLowerInvariant();
    }

    private static IEnumerable<KeyValuePair<string, byte[]>> EmbeddedPage() {
        const string prefix = "ThreeE.PhoneControl.Web.";
        var assembly = typeof(PhoneTrackpad).Assembly;
        foreach (var name in assembly.GetManifestResourceNames().Where(n => n.StartsWith(prefix, StringComparison.Ordinal))) {
            using var stream = assembly.GetManifestResourceStream(name);
            using var copy = new MemoryStream();
            stream.CopyTo(copy);
            yield return new(name[prefix.Length..], copy.ToArray());
        }
    }
    // Raised (outside the lock) after the receiver rebinds or resumes on a new
    // address, so hosts can re-advertise their mDNS name for that address.
    public event Action AddressChanged;
    private bool wanted;

    private sealed class Session {
        public readonly CancellationTokenSource Cancel = new();
        // Concurrent HTTP requests. A page load fetches about eight files at
        // once (page, scripts, styles, icon), so a reload must fit in full.
        public readonly SemaphoreSlim Slots = new(8);
        // Open WebSockets are bounded separately: a connected phone must not
        // hold a request slot, or reloading the page could get 503s.
        public readonly SemaphoreSlim Sockets = new(4);
        public readonly HttpListener Listener = new();
        public readonly string Token;
        public readonly string Origin, AliasOrigin;
        public readonly IPAddress Address;
        public WebSocket Controller;
        public string ControllerClient;
        public string HttpController;
        // The device that most recently took control. A newly connecting device
        // always wins; a device it replaced may only auto-reconnect (resume)
        // while it is still this one, so two pages never fight over input.
        public string LastClient;
        public long HttpLastSeen, HttpSequence, HttpRateStart;
        public int HttpCount;
        // Last computer clipboard snapshot the phone read; only its picture and
        // files can be downloaded, never an arbitrary path.
        public ClipSnapshot Clip;
        public readonly int Port;
        public Session(IPAddress address, int port, string token, string alias) {
            Address = address; Port = port; Origin = $"http://{address}:{port}"; Token = token;
            AliasOrigin = string.IsNullOrEmpty(alias) ? null : $"http://{alias}:{port}";
        }
        public bool IsOrigin(string origin) => origin != null && (origin == Origin || origin == AliasOrigin ||
            origin.StartsWith("http://", StringComparison.Ordinal) && IsLocalLiteral(origin.Substring(7)));
        public bool IsHost(string host) => host != null && (host == new Uri(Origin).Authority || AliasOrigin != null && host.Equals(new Uri(AliasOrigin).Authority, StringComparison.OrdinalIgnoreCase) ||
            IsLocalLiteral(host));
        // A computer can have more than one LAN address (Wi-Fi and Ethernet,
        // or an address that just changed). Literal private IPs that belong to
        // this computer, on this port, are as safe as the chosen one: DNS
        // rebinding needs a hostname, and these are numbers.
        private bool IsLocalLiteral(string authority) {
            var colon = authority.LastIndexOf(':');
            return colon > 0 && int.TryParse(authority.AsSpan(colon + 1), out var hostPort) && hostPort == Port &&
                IPAddress.TryParse(authority.AsSpan(0, colon), out var ip) && (ip.Equals(Address) || IsPrivateAddress(ip) && IsThisComputer(ip));
        }
    }
    private static IPAddress[] localAddresses = Array.Empty<IPAddress>();
    private static long localAddressesAt = long.MinValue;
    public static bool IsThisComputer(IPAddress ip) {
        if (Environment.TickCount64 - localAddressesAt > 5000) {
            try {
                localAddresses = NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up)
                    .SelectMany(n => n.GetIPProperties().UnicastAddresses).Select(a => a.Address).ToArray();
            } catch { }
            localAddressesAt = Environment.TickCount64;
        }
        return localAddresses.Contains(ip);
    }
    // Never answer with an empty error: iPhone Safari shows an empty error
    // response as a blank white page, which hides what went wrong.
    public static void Refuse(HttpListenerResponse response, int code, string message) {
        try {
            var page = Encoding.UTF8.GetBytes("<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>Phone Bar</title>" +
                "<body style=\"margin:0;min-height:100vh;display:grid;place-items:center;background:#141b21;color:#d6dee5;font:17px -apple-system,system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box\">" +
                "<div><p style=\"font-size:20px;font-weight:600\">Phone Bar</p><p>" + WebUtility.HtmlEncode(message) + "</p><p style=\"opacity:.6;font-size:14px\">Code " + code + "</p></div>");
            response.StatusCode = code;
            response.ContentType = "text/html; charset=utf-8";
            response.Headers["Cache-Control"] = "no-store";
            response.ContentLength64 = page.Length;
            response.OutputStream.Write(page, 0, page.Length);
        } catch { }
        try { response.Close(); } catch { }
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
        bool started, resume;
        lock (gate) {
            if (disposed) return false;
            if (session != null) return true;
            started = StartLocked();
            resume = !started && FollowNetwork && !wanted;
            if (started || FollowNetwork) wanted = FollowNetwork;
        }
        if (resume) _ = Task.Run(ResumeAsync);
        return started;
    }

    private bool StartLocked() {
        Session candidate = null;
        try {
            var address = addressProvider();
            if (address == null) { status = FollowNetwork ? "No local network — starts automatically when Wi-Fi connects." : "No local network — connect to Wi-Fi, then try again."; return false; }
            var token = SessionToken();
            candidate = new Session(address, port, token, AliasHost);
            candidate.Listener.Prefixes.Add(candidate.Origin + "/");
            if (candidate.AliasOrigin != null) candidate.Listener.Prefixes.Add(candidate.AliasOrigin + "/");
            try { candidate.Listener.Start(); }
            catch (HttpListenerException) {
                // Named prefixes can fail: Windows refuses them to a process
                // that is not running as administrator ("Access is denied"),
                // and some macOS builds reject a second named prefix. Listen on
                // the wildcard instead (on Windows the installer reserves
                // http://+:17833/ for normal users) while still validating
                // every request's Host/Origin against the approved addresses.
                candidate.Listener.Close();
                candidate = new Session(address, port, token, AliasHost);
                candidate.Listener.Prefixes.Add(OperatingSystem.IsWindows() ? $"http://+:{port}/" : $"http://*:{port}/");
                candidate.Listener.Start();
            }
            // The installer also adds a permanent local-network rule, so a
            // per-session rule that needs administrator rights is optional.
            try { firewall.Open(address, port); } catch { }
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

    private string SessionToken() {
        try {
            var stored = TokenProvider?.Invoke();
            if (stored != null && stored.Length == 48 && stored.All(Uri.IsHexDigit)) return stored.ToUpperInvariant();
        } catch { }
        return Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
    }

    public void Stop() { lock (gate) { wanted = false; StopLocked("Off"); } }

    // Waits for a local network after a loss, then restarts with the same link.
    private async Task ResumeAsync() {
        while (true) {
            try { await Task.Delay(1500); } catch { return; }
            IPAddress address;
            try { address = addressProvider(); } catch { address = null; }
            bool resumed;
            lock (gate) {
                if (disposed || !wanted || session != null) return;
                if (address == null) continue;
                resumed = StartLocked();
            }
            if (resumed) { RaiseAddressChanged(); return; }
        }
    }

    private void RaiseAddressChanged() { try { AddressChanged?.Invoke(); } catch { } }
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
                bool rebound = false, resume = false;
                lock (gate) {
                    if (session != owner) return;
                    if (owner.HttpController != null && Environment.TickCount64 - owner.HttpLastSeen > 6000) {
                        ReleaseHttpLocked(owner);
                        status = "Watch asleep — reconnects when its page returns.";
                    }
                    if (!owner.Address.Equals(address)) {
                        if (!FollowNetwork || !wanted) {
                            StopLocked("Network changed or disconnected — reconnect to Wi-Fi, then start again.");
                            return;
                        }
                        // Same link, new address: rebind now, or pause until a network returns.
                        StopLocked("Network changed — reconnecting automatically…");
                        rebound = address != null && StartLocked();
                        resume = !rebound;
                    }
                }
                if (rebound) RaiseAddressChanged();
                if (rebound || resume) { if (resume) _ = Task.Run(ResumeAsync); return; }
            }
        } catch (OperationCanceledException) { }
        catch {
            bool resume;
            lock (gate) {
                if (session != owner) return;
                StopLocked(FollowNetwork && wanted ? "No local network — reconnecting automatically when Wi-Fi returns." : "No local network — reconnect to Wi-Fi, then start again.");
                resume = FollowNetwork && wanted;
            }
            if (resume) _ = Task.Run(ResumeAsync);
        }
    }

    private async Task ListenAsync(Session owner) {
        try {
            while (!owner.Cancel.IsCancellationRequested) {
                var context = await owner.Listener.GetContextAsync();
                if (!owner.Slots.Wait(0)) { Refuse(context.Response, 503, "The computer is busy. Reload this page in a moment."); continue; }
                _ = HandleAsync(owner, context);
            }
        } catch {
            bool resume;
            lock (gate) {
                if (session != owner) return; // an intentional stop/rebind already owns recovery
                resume = FollowNetwork && wanted;
                StopLocked(resume ? "Connection interrupted — reconnecting automatically…" : "Trackpad connection stopped — start again to reconnect.");
            }
            if (resume) _ = Task.Run(ResumeAsync);
        }
    }

    private async Task HandleAsync(Session owner, HttpListenerContext context) {
        bool slotReleased = false;
        try {
            var request = context.Request;
            // Literal bound host and same-origin WebSockets prevent DNS rebinding / cross-site control.
            if (!owner.IsHost(request.Headers["Host"])) {
                Refuse(context.Response, 403, "This link points to an address this computer no longer uses. Open Phone Bar on the computer and scan its QR code again."); return;
            }
            if (request.Url.AbsolutePath == "/control" && request.HttpMethod == "POST") {
                await HttpControlAsync(owner, context); return;
            }
            if (request.HttpMethod == "POST" && request.Url.AbsolutePath.StartsWith("/clipboard/", StringComparison.Ordinal)) {
                await ClipboardAsync(owner, context); return;
            }
            if (request.HttpMethod != "GET") { Refuse(context.Response, 403, "That request is not allowed."); return; }
            if (request.Url.AbsolutePath == "/ws" && request.IsWebSocketRequest) {
                if (!owner.IsOrigin(request.Headers["Origin"]) || request.Url.Query.Length != 0) {
                    context.Response.StatusCode = 403; context.Response.Close(); return;
                }
                if (!owner.Sockets.Wait(0)) { Refuse(context.Response, 503, "Too many open Phone Bar pages. Close the extra ones."); return; }
                slotReleased = true; owner.Slots.Release();
                try {
                    using var ws = (await context.AcceptWebSocketAsync(null)).WebSocket;
                    await ControlAsync(owner, ws);
                } finally { owner.Sockets.Release(); }
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
            var resource = request.Url.AbsolutePath switch { "/" => "PhoneTrackpad.html", "/pad.js" => "PhoneTrackpad.js", "/surface.js" => "surface.js", "/dock.js" => "dock.js", "/clip.js" => "clip.js", "/surface.css" => "surface.css", "/host.js" => "host.js", "/pair" => "pair", "/icon.png" => "icon.png", _ => null };
            if (resource == null) { Refuse(context.Response, 404, "Nothing here. Open the Phone Bar link from the computer's QR code."); return; }
            var response = context.Response;
            response.ContentType = resource.EndsWith(".png") ? "image/png" : resource.EndsWith(".js") ? "text/javascript; charset=utf-8" : resource.EndsWith(".css") ? "text/css; charset=utf-8" : "text/html; charset=utf-8";
            response.Headers["Cache-Control"] = "no-store";
            response.Headers["Referrer-Policy"] = "no-referrer";
            response.Headers["X-Content-Type-Options"] = "nosniff";
            response.Headers["Content-Security-Policy"] = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' " + string.Join(" ", new[] { owner.Origin, owner.AliasOrigin }.Where(o => o != null).SelectMany(o => new[] { o, o.Replace("http:", "ws:") })) + "; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
            using var stream = pairing
                ? new MemoryStream(Encoding.UTF8.GetBytes(PairingPage(owner.Origin + "/#" + owner.Token)))
                : resource == "PhoneTrackpad.html" ? new MemoryStream(Encoding.UTF8.GetBytes(BrandedPage(input.Platform)))
                : resource == "host.js" ? new MemoryStream(Encoding.UTF8.GetBytes("window.ThreeEHost="+JsonSerializer.Serialize(new { platform=input.Platform, build=Build, http=false, keyboard=input.SupportsTyping, clipboard=input.Clipboard != null, alias=owner.AliasOrigin == null ? null : new Uri(owner.AliasOrigin).Authority })+";"))
                : typeof(PhoneTrackpad).Assembly.GetManifestResourceStream("ThreeE.PhoneControl.Web." + resource);
            response.ContentLength64 = stream.Length;
            await stream.CopyToAsync(response.OutputStream, owner.Cancel.Token);
            response.Close();
        } catch { try { context.Response.Abort(); } catch { } }
        finally { if (!slotReleased) owner.Slots.Release(); }
    }

    public static bool CanShowPairing(IPAddress remote, IPAddress local) => IPAddress.IsLoopback(remote) || remote.Equals(local);

    private void ReleaseHttpLocked(Session owner) {
        owner.HttpController = null;
        try { input.ReleaseAll(); } catch { }
    }

    // A fresh connection (a newly opened page or the Connect button) takes
    // input from whichever phone or watch held it. Automatic reconnects only
    // resume while no other device has taken over since.
    private static bool MayAcquire(Session owner, string client, bool takeover) =>
        takeover || owner.LastClient == client ||
        owner.LastClient == null && owner.Controller == null && owner.HttpController == null;

    // Drops the current phone and/or watch so `client` can become the controller.
    private void TakeOverLocked(Session owner, string client) {
        if (owner.Controller != null) {
            var previous = owner.Controller;
            owner.Controller = null; owner.ControllerClient = null;
            try { previous.Abort(); } catch { }
        }
        if (owner.HttpController != null && owner.HttpController != client) owner.HttpController = null;
        try { input.ReleaseAll(); } catch { }
        owner.LastClient = client;
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
        bool describe = false, handshake = false, replaced = false;
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
                    bool takeover = root.TryGetProperty("takeover", out var wants) && wants.ValueKind == JsonValueKind.True;
                    if (owner.HttpController == client && sequence <= owner.HttpSequence) code = 409;
                    else if (!MayAcquire(owner, client, takeover)) { code = 409; replaced = true; }
                    else {
                        // The newest device wins: the phone or watch holding input is
                        // dropped. The same page also reclaims its sleeping connection;
                        // a larger sequence prevents late commands/disconnects from it.
                        TakeOverLocked(owner, client);
                        owner.HttpController = client; owner.HttpSequence = sequence;
                        owner.HttpLastSeen = owner.HttpRateStart = Environment.TickCount64; owner.HttpCount = 0;
                        status = "Connected to your watch";
                    }
                } else if (owner.HttpController != client) { code = 403; replaced = owner.LastClient != null && owner.LastClient != client; }
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
        lock(gate) result = Encoding.UTF8.GetBytes(code == 200 ? (describe || handshake ? JsonSerializer.Serialize(new { ready=true, build=Build, host=describe ? input.GetInfo() : input.GetConnectionInfo() }) : "{\"ready\":true}") : replaced ? "{\"ready\":false,\"error\":\"replaced\"}" : "{\"ready\":false}");
        response.ContentLength64 = result.Length;
        await response.OutputStream.WriteAsync(result, owner.Cancel.Token);
        response.Close();
    }

    // Mac and Windows receivers are often open in neighbouring browser tabs;
    // the tab and home-screen title names the computer each one controls.
    public static string PageTitle(string platform) => platform == "macos" ? "3£ -mac" : "3£ -win";

    private static string BrandedPage(string platform) {
        using var stream = typeof(PhoneTrackpad).Assembly.GetManifestResourceStream("ThreeE.PhoneControl.Web.PhoneTrackpad.html");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var title = PageTitle(platform);
        return reader.ReadToEnd()
            .Replace("<title>3£ Phone Bar</title>", "<title>" + title + "</title>\n<meta name=\"apple-mobile-web-app-title\" content=\"" + title + "\">")
            .Replace("<meta property=\"og:title\" content=\"3£ Phone Bar\">", "<meta property=\"og:title\" content=\"" + title + "\">");
    }

    // Clipboard transfer uses authenticated same-origin POSTs: photos and PDFs
    // are far larger than the 1 KB control messages. Only the connected
    // controller may use it, and downloads are limited to the snapshot it read.
    private async Task ClipboardAsync(Session owner, HttpListenerContext context) {
        var request = context.Request;
        var response = context.Response;
        response.Headers["Cache-Control"] = "no-store";
        response.Headers["X-Content-Type-Options"] = "nosniff";
        async Task Reply(int code, object body) {
            var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(body));
            response.StatusCode = code; response.ContentType = "application/json"; response.ContentLength64 = bytes.Length;
            await response.OutputStream.WriteAsync(bytes, owner.Cancel.Token); response.Close();
        }
        try {
            var supplied = Encoding.UTF8.GetBytes(request.Headers["X-Trackpad-Token"] ?? "");
            if (!owner.IsOrigin(request.Headers["Origin"]) || request.Url.Query.Length != 0) { await Reply(403, new { error = "origin" }); return; }
            if (!CryptographicOperations.FixedTimeEquals(supplied, Encoding.UTF8.GetBytes(owner.Token))) { await Reply(401, new { error = "pairing" }); return; }
            bool idle;
            lock (gate) idle = session != owner || owner.Controller == null && owner.HttpController == null;
            if (idle) { await Reply(409, new { error = "Connect the trackpad first." }); return; }
            var clipboard = input.Clipboard;
            if (clipboard == null) { await Reply(501, new { error = "This computer does not support clipboard transfer." }); return; }
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(owner.Cancel.Token);
            timeout.CancelAfter(TimeSpan.FromMinutes(5));
            switch (request.Url.AbsolutePath) {
                case "/clipboard/write": {
                    long total = request.ContentLength64;
                    if (total < 0 || total > PhoneClipboard.MaxUpload) { await Reply(413, new { error = "Too large — 200 MB maximum." }); return; }
                    using var manifest = JsonDocument.Parse(Convert.FromBase64String(request.Headers["X-Clip-Manifest"] ?? ""), new JsonDocumentOptions { MaxDepth = 4 });
                    var entries = manifest.RootElement;
                    if (entries.ValueKind != JsonValueKind.Array || entries.GetArrayLength() == 0 || entries.GetArrayLength() > 64) throw new InvalidDataException();
                    var parts = new System.Collections.Generic.List<ClipPart>();
                    long sum = 0;
                    foreach (var entry in entries.EnumerateArray()) {
                        string kind = entry.GetProperty("kind").GetString();
                        if (kind is not ("text" or "html" or "image" or "file")) throw new InvalidDataException();
                        long size = entry.GetProperty("size").GetInt64();
                        if (size < 0 || size > PhoneClipboard.MaxUpload) throw new InvalidDataException();
                        sum += size;
                        string name = entry.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : "";
                        if (name.Length > 255) name = name[..255];
                        parts.Add(new ClipPart { Kind = kind, Name = name, Data = new byte[size] });
                    }
                    if (sum != total) throw new InvalidDataException();
                    foreach (var part in parts) await request.InputStream.ReadExactlyAsync(part.Data, timeout.Token);
                    await Task.Run(() => clipboard.Write(parts), timeout.Token);
                    lock (gate) { if (session == owner) status = "Phone clipboard sent to this computer"; }
                    await Reply(200, new { ok = true });
                    return;
                }
                case "/clipboard/read": {
                    var snap = await Task.Run(clipboard.Read, timeout.Token) ?? new ClipSnapshot();
                    if (snap.Png != null && (snap.Width <= 0 || snap.Height <= 0)) (snap.Width, snap.Height) = PhoneClipboard.PngSize(snap.Png);
                    lock (gate) owner.Clip = snap;
                    var files = snap.Files.Select(path => {
                        bool folder = Directory.Exists(path);
                        long size = !folder && File.Exists(path) ? new FileInfo(path).Length : -1;
                        return new { name = Path.GetFileName(path.TrimEnd('\\', '/')), size, folder };
                    }).ToArray();
                    await Reply(200, new {
                        ok = true, text = string.IsNullOrEmpty(snap.Text) ? null : snap.Text, html = string.IsNullOrWhiteSpace(snap.Html) ? null : snap.Html,
                        image = snap.Png == null ? null : new { width = snap.Width, height = snap.Height, size = snap.Png.Length },
                        files
                    });
                    return;
                }
                case "/clipboard/item": {
                    var buffer = new byte[256]; int count = 0, read;
                    while ((read = await request.InputStream.ReadAsync(buffer.AsMemory(count), timeout.Token)) > 0) { count += read; if (count >= buffer.Length) throw new InvalidDataException(); }
                    using var body = JsonDocument.Parse(buffer.AsMemory(0, count));
                    int index = body.RootElement.GetProperty("index").GetInt32();
                    ClipSnapshot snap; lock (gate) snap = owner.Clip;
                    if (snap == null) { await Reply(404, new { error = "Read the clipboard again." }); return; }
                    if (index == -1) {
                        if (snap.Png == null) { await Reply(404, new { error = "No picture." }); return; }
                        response.ContentType = "image/png"; response.ContentLength64 = snap.Png.Length;
                        await response.OutputStream.WriteAsync(snap.Png, timeout.Token); response.Close(); return;
                    }
                    if (index < 0 || index >= snap.Files.Count || !File.Exists(snap.Files[index])) { await Reply(404, new { error = "That file is no longer available." }); return; }
                    using var file = new FileStream(snap.Files[index], FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    if (file.Length > PhoneClipboard.MaxDownload) { await Reply(413, new { error = "Too large — 512 MB maximum." }); return; }
                    response.ContentType = "application/octet-stream"; response.ContentLength64 = file.Length;
                    await file.CopyToAsync(response.OutputStream, timeout.Token); response.Close(); return;
                }
                default: await Reply(404, new { error = "Unknown clipboard request." }); return;
            }
        } catch (Exception ex) when (ex is InvalidDataException or JsonException or FormatException or System.Collections.Generic.KeyNotFoundException or InvalidOperationException) {
            try { await Reply(400, new { error = "Invalid clipboard request." }); } catch { try { response.Abort(); } catch { } }
        } catch (Exception ex) {
            try { await Reply(500, new { error = ex is IOException or TimeoutException ? ex.Message : "The computer could not complete the clipboard transfer." }); } catch { try { response.Abort(); } catch { } }
        }
    }

    private static string PairingPage(string link) {
        using var data = QRCodeGenerator.GenerateQrCode(link, QRCodeGenerator.ECCLevel.M);
        using var qr = new SvgQRCode(data);
        return """
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>3£Windows · Pair your iPhone</title>
<link rel="icon" type="image/png" href="/icon.png">
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
            bool takeover = auth.RootElement.TryGetProperty("takeover", out var wants) && wants.ValueKind == JsonValueKind.True;
            string refusal = null;
            lock (gate) {
                if (session != owner) return;
                // Pages without an identity cannot be told apart, so they keep
                // the old rule: they connect only when no device holds input.
                if (client == null ? owner.Controller != null || owner.HttpController != null : !MayAcquire(owner, client, takeover))
                    refusal = client == null ? "busy" : "replaced";
                else {
                    bool switched = owner.LastClient != null && owner.LastClient != client && (owner.Controller != null || owner.HttpController != null);
                    TakeOverLocked(owner, client);
                    owner.Controller = ws; owner.ControllerClient = client; acquired = true;
                    status = switched ? "Switched to the newest phone" : "Connected to your phone";
                }
            }
            if (!acquired) { await ws.SendAsync(Encoding.UTF8.GetBytes("{\"error\":\"" + refusal + "\"}"), WebSocketMessageType.Text, true, owner.Cancel.Token); return; }
            // Connecting the trackpad must not wait on native MIDI driver discovery.
            // The MIDI surface requests the full description when it opens.
            string lastHost = JsonSerializer.Serialize(input.GetConnectionInfo());
            await ws.SendAsync(Encoding.UTF8.GetBytes("{\"ready\":true,\"build\":" + JsonSerializer.Serialize(Build) + ",\"host\":" + lastHost + "}"), WebSocketMessageType.Text, true, owner.Cancel.Token);
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
            case "navigate":
                int direction=Range("direction",-1,1);
                if(command.TryGetProperty("swipe",out var swipe)&&swipe.GetBoolean())sink.NavigateSwipe(direction);
                else sink.Navigate(direction);
                break;
            case "navigateEnd": sink.NavigateEnd(); break;
            case "appsBegin": sink.Release(); sink.AppsBegin(); break;
            case "appsStep": sink.AppsStep(Range("direction",-1,1)); break;
            case "appsEnd": sink.AppsEnd(); break;
            case "media": sink.Media(Range("action",0,2)); break;
            case "volume": sink.Volume(Range("level",0,100)); break;
            case "volumeStep": sink.VolumeStep(Range("direction",-1,1)); break;
            case "history": sink.History(Range("direction",-1,1)); break;
            case "zoom": sink.Zoom(Range("direction",-1,1)); break;
            case "text": {
                // Phone keyboard text (short chunks; the page splits longer input).
                if (!command.TryGetProperty("text", out var text) || text.ValueKind != JsonValueKind.String) throw new InvalidDataException("Invalid text.");
                var value = text.GetString();
                if (value.Length == 0 || value.Length > 256) throw new InvalidDataException("Invalid text.");
                sink.TypeText(value); break;
            }
            case "key": sink.PressKey(Range("id",0,PhoneClipboard.KeyCount-1), command.TryGetProperty("n", out _) ? Range("n",1,64) : 1); break;
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
    void NavigateSwipe(int direction) => Navigate(-direction);
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
    // Phone keyboard: Unicode text and the fixed PhoneClipboard key palette.
    // Hosts that implement them return true so the phone shows the Keyboard button.
    bool SupportsTyping => false;
    void TypeText(string text) { }
    void PressKey(int id, int repeat) { }
    // The system clipboard, or null when this host cannot transfer it.
    IPhoneClipboard Clipboard => null;
    // Press for a tap-then-drag. Hosts must not let it complete a double-click.
    void DragStart(int x, int y) => Down();
}
public interface ITrackpadFirewall { void Open(IPAddress address, int port); void Close(); }
