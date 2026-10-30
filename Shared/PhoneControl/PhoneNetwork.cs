// SPDX-License-Identifier: MIT
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Diagnostics;
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
            var interfaces=NetworkInterface.GetAllNetworkInterfaces();
            var usb=OperatingSystem.IsMacOS()?MacUSBInterfaces(interfaces):new HashSet<string>();
            var found=new List<PathInfo>();
            foreach(var n in interfaces) {
                if(n.OperationalStatus!=OperationalStatus.Up || !usb.Contains(n.Name) && n.NetworkInterfaceType is not (NetworkInterfaceType.Ethernet or NetworkInterfaceType.Wireless80211))continue;
                var properties=n.GetIPProperties();string label=names.GetValueOrDefault(n.Name,n.Description+" "+n.Name);
                string kind=usb.Contains(n.Name)?"usb":Kind(label,n.NetworkInterfaceType);
                if(usb.Contains(n.Name))label="iPhone USB";
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
    // Newer iPhones expose an Apple USB NCM link inside a local bridge.
    // Confirm the member's real USB ancestry; bridge names/subnets alone do
    // not distinguish a phone from a VM, dock or Internet Sharing interface.
    private static HashSet<string> MacUSBInterfaces(NetworkInterface[] interfaces) {
        var usb=new HashSet<string>(StringComparer.Ordinal);
        foreach(var item in interfaces)if(item.OperationalStatus==OperationalStatus.Up&&MacPhoneUSB(item.Name))usb.Add(item.Name);
        if(usb.Count==0)return usb;
        foreach(var item in interfaces)if(item.OperationalStatus==OperationalStatus.Up&&item.Name.StartsWith("bridge",StringComparison.Ordinal)&&item.Name.All(char.IsAsciiLetterOrDigit)) {
            var members=BridgeMembers(item.Name);
            if(members.Any(usb.Contains))usb.Add(item.Name);
        }
        return usb;
    }
    public static string[] ParseBridgeMembers(string text)=>text.Split('\n').Select(line=>line.Trim()).Where(line=>line.StartsWith("member: ",StringComparison.Ordinal)).Select(line=>line[8..].Split(' ',StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()).Where(name=>!string.IsNullOrEmpty(name)&&name.All(char.IsAsciiLetterOrDigit)).ToArray();
    private static string[] BridgeMembers(string name) {
        try {
            var start=new ProcessStartInfo("/sbin/ifconfig"){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};start.ArgumentList.Add(name);
            using var process=Process.Start(start);if(process==null)return Array.Empty<string>();
            var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
            if(!process.WaitForExit(250)){process.Kill();process.WaitForExit();return Array.Empty<string>();}
            string text=output.GetAwaiter().GetResult();error.GetAwaiter().GetResult();return process.ExitCode==0?ParseBridgeMembers(text):Array.Empty<string>();
        }catch{return Array.Empty<string>();}
    }
    private const string IOKit="/System/Library/Frameworks/IOKit.framework/IOKit";
    [DllImport(IOKit)]private static extern IntPtr IOBSDNameMatching(uint port,uint options,[MarshalAs(UnmanagedType.LPUTF8Str)]string name);
    [DllImport(IOKit)]private static extern uint IOServiceGetMatchingService(uint port,IntPtr matching);
    [DllImport(IOKit)]private static extern int IORegistryEntryGetParentEntry(uint entry,[MarshalAs(UnmanagedType.LPUTF8Str)]string plane,out uint parent);
    [DllImport(IOKit)]private static extern IntPtr IORegistryEntryCreateCFProperty(uint entry,IntPtr key,IntPtr allocator,uint options);
    [DllImport(IOKit)]private static extern int IOObjectRelease(uint entry);
    [DllImport(CF)]private static extern IntPtr CFStringCreateWithCString(IntPtr allocator,[MarshalAs(UnmanagedType.LPUTF8Str)]string text,uint encoding);
    [DllImport(CF)]private static extern nuint CFGetTypeID(IntPtr value);
    [DllImport(CF)]private static extern nuint CFStringGetTypeID();
    private static bool MacPhoneUSB(string name) {
        uint entry=IOServiceGetMatchingService(0,IOBSDNameMatching(0,0,name));if(entry==0)return false;
        IntPtr key=CFStringCreateWithCString(IntPtr.Zero,"USB Product Name",0x08000100);
        try {
            for(int depth=0;depth<16&&entry!=0;depth++) {
                var value=IORegistryEntryCreateCFProperty(entry,key,IntPtr.Zero,0);
                if(value!=IntPtr.Zero)try{if(CFGetTypeID(value)==CFStringGetTypeID()){string product=Text(value);if(product.Contains("iPhone",StringComparison.OrdinalIgnoreCase)||product.Contains("iPad",StringComparison.OrdinalIgnoreCase))return true;}}finally{CFRelease(value);}
                int result=IORegistryEntryGetParentEntry(entry,"IOService",out uint parent);IOObjectRelease(entry);entry=result==0?parent:0;
            }
            return false;
        }finally{if(entry!=0)IOObjectRelease(entry);if(key!=IntPtr.Zero)CFRelease(key);}
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
