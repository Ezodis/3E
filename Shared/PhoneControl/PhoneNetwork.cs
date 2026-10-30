// SPDX-License-Identifier: MIT
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
namespace ThreeE.PhoneControl;

// Interface identity is used, never the hotspot subnet: Wi-Fi hotspots can use
// exactly the same IP range as USB. Snapshots are refreshed by network recovery.
public static class PhoneNetwork {
    public sealed record PathInfo(IPAddress Address,string Kind,string Name,bool Gateway);
    private static PathInfo[] paths=Array.Empty<PathInfo>();
    public static IReadOnlyList<PathInfo> Paths=>Volatile.Read(ref paths);
    public static string Kind(string name,NetworkInterfaceType type) {
        string n=(name??"").ToLowerInvariant();
        if(new[]{"iphone usb","apple mobile device","remote ndis","usb tether","android usb","rndis"}.Any(n.Contains))return "usb";
        return type==NetworkInterfaceType.Wireless80211?"wifi":"ethernet";
    }
    public static IPAddress Choose(IEnumerable<PathInfo> candidates)=>candidates
        .OrderBy(p=>p.Kind=="usb"?0:p.Kind=="wifi"?1:2).ThenBy(p=>p.Gateway?0:1).Select(p=>p.Address).FirstOrDefault();
    public static IPAddress Refresh() {
        try {
            var names=OperatingSystem.IsMacOS()?MacNames():new Dictionary<string,string>();
            var found=new List<PathInfo>();
            foreach(var n in NetworkInterface.GetAllNetworkInterfaces()) {
                if(n.OperationalStatus!=OperationalStatus.Up || n.NetworkInterfaceType is not (NetworkInterfaceType.Ethernet or NetworkInterfaceType.Wireless80211))continue;
                var properties=n.GetIPProperties();string label=names.GetValueOrDefault(n.Name,n.Description+" "+n.Name);
                string kind=Kind(label,n.NetworkInterfaceType);
                bool gateway=properties.GatewayAddresses.Any(g=>g.Address.AddressFamily==AddressFamily.InterNetwork&&!g.Address.Equals(IPAddress.Any));
                // A direct USB/Ethernet link can be local-only, without a gateway.
                foreach(var a in properties.UnicastAddresses.Where(a=>PhoneTrackpad.IsPrivateAddress(a.Address)))
                    found.Add(new(a.Address,kind,label,gateway));
            }
            Volatile.Write(ref paths,found.ToArray());return Choose(found);
        }catch{return Choose(Paths);}
    }
    public static object Describe(IPAddress local,int port) {
        var snapshot=Paths;var current=snapshot.FirstOrDefault(p=>p.Address.Equals(local));
        return new {kind=current?.Kind??"local",name=current?.Name??"Local connection",
            address=local?.ToString(),routes=snapshot.Select(p=>new {kind=p.Kind,name=p.Name,host=$"{p.Address}:{port}"}).ToArray()};
    }
    private const string SC="/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",CF="/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    [DllImport(SC)]private static extern IntPtr SCNetworkInterfaceCopyAll();
    [DllImport(SC)]private static extern IntPtr SCNetworkInterfaceGetBSDName(IntPtr item);
    [DllImport(SC)]private static extern IntPtr SCNetworkInterfaceGetLocalizedDisplayName(IntPtr item);
    [DllImport(CF)]private static extern nint CFArrayGetCount(IntPtr array);
    [DllImport(CF)]private static extern IntPtr CFArrayGetValueAtIndex(IntPtr array,nint index);
    [DllImport(CF)][return:MarshalAs(UnmanagedType.I1)]private static extern bool CFStringGetCString(IntPtr value,byte[] buffer,nint size,uint encoding);
    [DllImport(CF)]private static extern void CFRelease(IntPtr value);
    private static string Text(IntPtr value){if(value==IntPtr.Zero)return "";var bytes=new byte[1024];return CFStringGetCString(value,bytes,bytes.Length,0x08000100)?System.Text.Encoding.UTF8.GetString(bytes).TrimEnd('\0'):"";}
    private static Dictionary<string,string> MacNames(){var result=new Dictionary<string,string>();var all=SCNetworkInterfaceCopyAll();if(all==IntPtr.Zero)return result;try{for(nint i=0;i<CFArrayGetCount(all);i++){var item=CFArrayGetValueAtIndex(all,i);string bsd=Text(SCNetworkInterfaceGetBSDName(item)),label=Text(SCNetworkInterfaceGetLocalizedDisplayName(item));if(bsd.Length>0)result[bsd]=label;}}finally{CFRelease(all);}return result;}
}
