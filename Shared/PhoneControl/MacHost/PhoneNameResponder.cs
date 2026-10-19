// SPDX-License-Identifier: MIT
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ThreeE.PhoneHost;

// Advertise the same stable mDNS host name as the Windows Phone Bar.
internal sealed class PhoneNameResponder : IDisposable {
    // Keep the Mac and Windows endpoints distinct when both are online on
    // the same LAN; advertising 3e.local from both makes QR links ambiguous.
    public const string Name = "3e-mac.local";
    private static readonly IPAddress Group = IPAddress.Parse("224.0.0.251");
    private readonly IPAddress address;
    private readonly UdpClient udp;
    private readonly CancellationTokenSource stop = new();
    public IPAddress Address => address;
    private volatile bool healthy=true;
    public bool Healthy=>healthy&&!stop.IsCancellationRequested;
    private readonly Timer announcement;

    public PhoneNameResponder(IPAddress address) {
        this.address = address;
        udp = new UdpClient(AddressFamily.InterNetwork) { ExclusiveAddressUse = false };
        try {
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            udp.Client.Bind(new IPEndPoint(IPAddress.Any, 5353));
            udp.JoinMulticastGroup(Group, address);
            udp.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, address.GetAddressBytes());
            udp.MulticastLoopback = false;
            _ = Task.Run(Listen);
            Announce();
            announcement=new Timer(_=>Announce(),null,TimeSpan.FromSeconds(30),TimeSpan.FromSeconds(30));
        } catch {udp.Dispose();stop.Dispose();throw;}
    }

    private void Announce() {
        try {
            byte[] packet = BuildResponse(address, 0);
            udp.Send(packet, packet.Length, new IPEndPoint(Group, 5353));
        } catch { healthy=false; }
    }

    private async Task Listen() {
        while (!stop.IsCancellationRequested) {
            try {
                var received = await udp.ReceiveAsync(stop.Token);
                var answer = Answer(received.Buffer, address, received.RemoteEndPoint.Port);
                if (answer == null) continue;
                var target = answer.Value.unicast ? received.RemoteEndPoint : new IPEndPoint(Group, 5353);
                await udp.SendAsync(answer.Value.packet, target, stop.Token);
            } catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (SocketException) { healthy=false;return; }
            catch { /* Ignore malformed and unrelated multicast traffic. */ }
        }
    }

    private static (byte[] packet, bool unicast)? Answer(byte[] query, IPAddress address, int sourcePort) {
        if (query.Length < 12 || (query[2] & 0x80) != 0) return null;
        int questions = query[4] << 8 | query[5], offset = 12;
        bool matched = false, unicast = sourcePort != 5353;
        for (int i = 0; i < questions && i < 16; i++) {
            var name = ReadName(query, ref offset);
            if (name == null || offset + 4 > query.Length) return null;
            int type = query[offset] << 8 | query[offset + 1], klass = query[offset + 2] << 8 | query[offset + 3];
            offset += 4;
            if (name.Equals(Name, StringComparison.OrdinalIgnoreCase) && (type == 1 || type == 255) && (klass & 0x7FFF) == 1) {
                matched = true;
                if ((klass & 0x8000) != 0) unicast = true;
            }
        }
        if (!matched) return null;
        ushort id = sourcePort == 5353 ? (ushort)0 : (ushort)(query[0] << 8 | query[1]);
        return (BuildResponse(address, id, sourcePort != 5353), unicast);
    }

    private static byte[] BuildResponse(IPAddress address, ushort id, bool legacy = false) {
        var packet = new List<byte> { (byte)(id >> 8), (byte)id, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0 };
        foreach (var label in Name.Split('.')) { packet.Add((byte)label.Length); packet.AddRange(Encoding.ASCII.GetBytes(label)); }
        packet.Add(0);
        packet.AddRange(new byte[] { 0, 1, (byte)(legacy ? 0 : 0x80), 1, 0, 0, 0, 120, 0, 4 });
        packet.AddRange(address.GetAddressBytes());
        return packet.ToArray();
    }

    private static string ReadName(byte[] data, ref int offset) {
        var labels = new List<string>();
        int position = offset, jumps = 0;
        bool jumped = false;
        while (position < data.Length) {
            int length = data[position];
            if ((length & 0xC0) == 0xC0) {
                if (position + 1 >= data.Length || ++jumps > 8) return null;
                int pointer = (length & 0x3F) << 8 | data[position + 1];
                if (pointer >= data.Length) return null;
                if (!jumped) offset = position + 2;
                jumped = true; position = pointer; continue;
            }
            if ((length & 0xC0) != 0 || length > 63) return null;
            position++;
            if (length == 0) { if (!jumped) offset = position; return string.Join('.', labels); }
            if (position + length > data.Length) return null;
            labels.Add(Encoding.ASCII.GetString(data, position, length)); position += length;
        }
        return null;
    }

    public void Dispose() {
        healthy=false;announcement?.Dispose();stop.Cancel();
        udp.Dispose();
        stop.Dispose();
    }
}
