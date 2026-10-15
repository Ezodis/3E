// Keyboard-only adaptation of the symlink workaround by Hygor Ostrowskij de Morais.
// Reference: https://github.com/hygorostrowskij/interception-driver-fix (BSD-3-Clause).
// Keeps temporary NT object links open. Does not replace existing objects or change ACLs.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public static class ClicksReconnectGuard {
 [StructLayout(LayoutKind.Sequential)] struct US { public ushort Length, MaximumLength; public IntPtr Buffer; }
 [StructLayout(LayoutKind.Sequential)] struct OA { public int Length; public IntPtr RootDirectory,ObjectName; public uint Attributes; public IntPtr SecurityDescriptor,SecurityQos; }
 [DllImport("ntdll.dll")] static extern int NtCreateSymbolicLinkObject(out IntPtr h,uint access,ref OA oa,ref US target);
 [DllImport("ntdll.dll")] static extern int NtClose(IntPtr h);
 static List<IntPtr> handles = new List<IntPtr>();
 static int Make(string name,string target) {
  IntPtr n=Marshal.StringToHGlobalUni(name), t=Marshal.StringToHGlobalUni(target), p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(US)));
  try {
   US ns=new US { Length=(ushort)(name.Length*2),MaximumLength=(ushort)(name.Length*2+2),Buffer=n };
   US ts=new US { Length=(ushort)(target.Length*2),MaximumLength=(ushort)(target.Length*2+2),Buffer=t };
   Marshal.StructureToPtr(ns,p,false);
   OA oa=new OA { Length=Marshal.SizeOf(typeof(OA)),ObjectName=p,Attributes=0x40 };
   IntPtr h; int s=NtCreateSymbolicLinkObject(out h,1,ref oa,ref ts);
   if(s>=0) handles.Add(h);
   else if(unchecked((uint)s)!=0xC0000035 && unchecked((uint)s)!=0xC0000024) throw new Exception(name+": NTSTATUS 0x"+unchecked((uint)s).ToString("X8"));
   return s>=0 ? 1 : 0;
  } finally { Marshal.FreeHGlobal(n);Marshal.FreeHGlobal(t);Marshal.FreeHGlobal(p); }
 }
 public static int Run(string stateDir) {
  Directory.CreateDirectory(stateDir); string ready=Path.Combine(stateDir,"ready"),stop=Path.Combine(stateDir,"stop");
  bool first; using(var mutex=new Mutex(true,"Global\\3EWindows.ClicksReconnectGuard",out first)) {
   if(!first) return 0;
   try {
    if(File.Exists(ready))File.Delete(ready);
    int made=0;
    for(int i=10;i<1000;i++) made+=Make("\\Device\\KeyboardClass"+i,"\\Device\\KeyboardClass"+(i%10));
    File.WriteAllText(ready,"Created="+made+" PID="+System.Diagnostics.Process.GetCurrentProcess().Id);
    while(!File.Exists(stop)) Thread.Sleep(250);
    return 0;
   } catch(Exception e) { File.WriteAllText(Path.Combine(stateDir,"error.txt"),e.ToString()); return 1; }
   finally { foreach(var h in handles)NtClose(h); if(File.Exists(ready))File.Delete(ready); }
  }
 }
 public static int Main(string[] args) { return args.Length==1 ? Run(args[0]) : 2; }
}
