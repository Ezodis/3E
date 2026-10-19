// SPDX-License-Identifier: MIT
using System.Net;
using System.Runtime.InteropServices;

namespace ThreeE.PhoneHost;

// Let macOS own multicast DNS, including probing, caching, interface changes
// and wake announcements. A second private UDP socket on port 5353 competes
// with mDNSResponder and can leave the phone's saved .local link unresolved.
internal sealed class PhoneNameResponder : IDisposable {
    public const string Name="3e-mac.local";
    private const string DNS="/usr/lib/libSystem.B.dylib";
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void RegisterReply(IntPtr service,IntPtr record,uint flags,int error,IntPtr context);
    [DllImport(DNS)] private static extern int DNSServiceCreateConnection(out IntPtr service);
    [DllImport(DNS)] private static extern int DNSServiceRegisterRecord(IntPtr service,out IntPtr record,uint flags,uint index,
        [MarshalAs(UnmanagedType.LPUTF8Str)]string name,ushort type,ushort klass,ushort length,byte[] data,uint ttl,RegisterReply reply,IntPtr context);
    [DllImport(DNS)] private static extern int DNSServiceRefSockFD(IntPtr service);
    [DllImport(DNS)] private static extern int DNSServiceProcessResult(IntPtr service);
    [DllImport(DNS)] private static extern void DNSServiceRefDeallocate(IntPtr service);
    [StructLayout(LayoutKind.Sequential)] private struct PollFD { public int fd;public short events,revents; }
    [DllImport("/usr/lib/libSystem.B.dylib",SetLastError=true)] private static extern int poll(ref PollFD fd,nuint count,int timeout);
    private readonly object gate=new();
    private readonly RegisterReply reply;
    private IntPtr service;
    private volatile bool healthy=true,stopped;
    public IPAddress Address { get; }
    public bool Healthy=>healthy&&!stopped;
    public PhoneNameResponder(IPAddress address,string name=Name) {
        Address=address;
        byte[] bytes=address.GetAddressBytes();
        if(bytes.Length!=4)throw new ArgumentException("Bonjour requires the receiver's IPv4 address");
        reply=(_,_,_,error,_)=>{if(error!=0)healthy=false;};
        int error=DNSServiceCreateConnection(out service);
        if(error!=0)throw new IOException("Bonjour connection failed: "+error);
        try {
            error=DNSServiceRegisterRecord(service,out _,0x20,IPAddress.IsLoopback(address)?uint.MaxValue:0,name,1,1,4,bytes,120,reply,IntPtr.Zero);
            if(error!=0)throw new IOException("Bonjour registration failed: "+error);
            _=Task.Run(Listen);
        } catch {DNSServiceRefDeallocate(service);service=IntPtr.Zero;throw;}
    }
    private async Task Listen() {
        while(!stopped&&healthy) {
            // DNSService APIs are not thread-safe. Bounded polling lets Dispose
            // acquire this same lock before deallocating the service reference.
            lock(gate) {
                if(stopped)return;
                var fd=new PollFD {fd=DNSServiceRefSockFD(service),events=1};
                if(fd.fd<0){healthy=false;return;}
                int ready=poll(ref fd,1,100);
                if(ready<0) {if(Marshal.GetLastPInvokeError()!=4)healthy=false;}
                else if(ready>0&&(fd.revents&1)!=0)healthy=DNSServiceProcessResult(service)==0&&healthy;
                else if(ready>0&&(fd.revents&0x38)!=0)healthy=false;
            }
            await Task.Delay(10);
        }
    }
    public void Dispose() {
        lock(gate) {
            if(stopped)return;
            stopped=true;healthy=false;
            if(service!=IntPtr.Zero){DNSServiceRefDeallocate(service);service=IntPtr.Zero;}
            GC.KeepAlive(reply);
        }
    }
}
