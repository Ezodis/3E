// SPDX-License-Identifier: MIT
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ThreeE.PhoneBar.Windows;

// Minimal multicast-DNS responder so phones on the same network can open the
// receiver as http://phonebar.local:17833 instead of a changing IP address.
// It answers only A (and ANY) questions for its single name with the
// receiver's current address, and stops with the receiver.
public sealed class PhoneNameResponder : IDisposable {
    public const string Name = "phonebar.local";
    private static readonly IPAddress Group = IPAddress.Parse("224.0.0.251");
    private readonly IPAddress address;
    private readonly UdpClient udp;
    private readonly CancellationTokenSource stop = new();
    public IPAddress Address => address;

    public PhoneNameResponder(IPAddress address) {
        this.address = address;
        udp = new UdpClient(AddressFamily.InterNetwork) { ExclusiveAddressUse = false };
        udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, 5353));
        udp.JoinMulticastGroup(Group, address);
        udp.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, address.GetAddressBytes());
        udp.MulticastLoopback = false;
        _ = Task.Run(Listen);
        Announce();
    }

    private void Announce() {
        try { var packet = Response(0, false); udp.Send(packet, packet.Length, new IPEndPoint(Group, 5353)); } catch { }
    }

    private async Task Listen() {
        while (!stop.IsCancellationRequested) {
            try {
                var received = await udp.ReceiveAsync(stop.Token);
                var answer = Answer(received.Buffer, address, received.RemoteEndPoint.Port);
                if (answer == null) continue;
                // Legacy/unicast-response questions get a direct reply; others go to the group.
                var target = answer.Value.unicast ? received.RemoteEndPoint : new IPEndPoint(Group, 5353);
                await udp.SendAsync(answer.Value.packet, target, stop.Token);
            } catch (OperationCanceledException) { return; }
            catch { /* Malformed or foreign packets never stop the responder. */ }
        }
    }

    // Returns a response packet when the query asks for our name, otherwise null.
    public static (byte[] packet, bool unicast)? Answer(byte[] query, IPAddress address, int sourcePort) {
        if (query.Length < 12 || (query[2] & 0x80) != 0) return null; // responses are ignored
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
        var id = sourcePort != 5353 ? (ushort)(query[0] << 8 | query[1]) : (ushort)0;
        return (new PhoneNameResponder.Builder(address).Build(id, sourcePort != 5353), unicast);
    }

    private byte[] Response(ushort id, bool legacy) => new Builder(address).Build(id, legacy);

    private sealed class Builder {
        private readonly IPAddress address;
        public Builder(IPAddress address) => this.address = address;
        public byte[] Build(ushort id, bool legacy) {
            var packet = new List<byte> { (byte)(id >> 8), (byte)id, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0 };
            foreach (var label in Name.Split('.')) { packet.Add((byte)label.Length); packet.AddRange(Encoding.ASCII.GetBytes(label)); }
            packet.Add(0);
            packet.AddRange(new byte[] { 0, 1, (byte)(legacy ? 0x00 : 0x80), 1, 0, 0, 0, 120, 0, 4 }); // A, IN (+cache flush), TTL 120
            packet.AddRange(address.GetAddressBytes());
            return packet.ToArray();
        }
    }

    private static string ReadName(byte[] data, ref int offset) {
        var labels = new List<string>();
        int position = offset, jumps = 0;
        bool jumped = false;
        while (position < data.Length) {
            int length = data[position];
            if (length == 0) { if (!jumped) offset = position + 1; return string.Join('.', labels); }
            if ((length & 0xC0) == 0xC0) {
                if (position + 1 >= data.Length || ++jumps > 8) return null;
                if (!jumped) offset = position + 2;
                position = (length & 0x3F) << 8 | data[position + 1]; jumped = true; continue;
            }
            if (position + 1 + length > data.Length) return null;
            labels.Add(Encoding.ASCII.GetString(data, position + 1, length));
            position += 1 + length;
        }
        return null;
    }

    public void Dispose() { stop.Cancel(); try { udp.Dispose(); } catch { } }
}
