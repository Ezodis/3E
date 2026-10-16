// SPDX-License-Identifier: MIT
using System.Runtime.InteropServices;
using ThreeE.PhoneControl;
namespace ThreeE.PhoneHost;

public sealed class MacInput : ITrackpadInput, IDisposable {
    private const string CG="/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics";
    private const string CF="/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    [StructLayout(LayoutKind.Sequential)] private struct Point { public double X,Y; }
    [DllImport(CG)] private static extern IntPtr CGEventCreate(IntPtr source);
    [DllImport(CG)] private static extern Point CGEventGetLocation(IntPtr e);
    [DllImport(CG)] private static extern IntPtr CGEventCreateMouseEvent(IntPtr source,uint type,Point position,uint button);
    [DllImport(CG)] private static extern IntPtr CGEventCreateKeyboardEvent(IntPtr source,ushort key,[MarshalAs(UnmanagedType.I1)] bool down);
    [DllImport("ThreeEPhoneNative")] private static extern IntPtr ThreeECreateScrollEvent(int y,int x);
    [DllImport("ThreeEPhoneNative")] public static extern int ThreeEValidateScrollEvent();
    [DllImport(CG)] private static extern void CGEventSetFlags(IntPtr e,ulong flags);
    [DllImport(CG)] private static extern void CGEventSetIntegerValueField(IntPtr e,uint field,long value);
    [DllImport(CG)] private static extern void CGEventPost(uint tap,IntPtr e);
    [DllImport(CG)][return:MarshalAs(UnmanagedType.I1)] public static extern bool CGPreflightPostEventAccess();
    [DllImport(CF)] private static extern void CFRelease(IntPtr reference);
    private readonly MacMidi midi = new();
    private readonly Action<int> media;
    private bool held,switching;
    private long lastClick; private Point lastClickPoint; private int clicks;
    public MacInput(Action<int> media) { this.media=media; midi.Select(0); }
    public string Platform => "macos";
    public object GetConnectionInfo() => new {platform=Platform,inputPermission=CGPreflightPostEventAccess()};
    public object GetInfo() => new {platform=Platform,inputPermission=CGPreflightPostEventAccess(),midi=midi.Info()};
    private static Point Location() { var e=CGEventCreate(IntPtr.Zero);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS pointer event unavailable");try{return CGEventGetLocation(e);}finally{if(e!=IntPtr.Zero)CFRelease(e);} }
    private static void Post(IntPtr e) { if(e==IntPtr.Zero)throw new InvalidOperationException("macOS event unavailable");try{CGEventPost(0,e);}finally{CFRelease(e);} }
    private static void Key(ushort key,bool down,ulong flags=0) { var e=CGEventCreateKeyboardEvent(IntPtr.Zero,key,down);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS keyboard event unavailable");CGEventSetFlags(e,flags);Post(e); }
    private static void Control(ushort key) { try{Key(59,true,1UL<<18);Key(key,true,1UL<<18);Key(key,false,1UL<<18);}finally{Key(59,false);} }
    public void Move(int x,int y) { var p=Location();p.X+=x;p.Y+=y;Post(CGEventCreateMouseEvent(IntPtr.Zero,held?6u:5u,p,0)); }
    public void Scroll(int x,int y) => Post(ThreeECreateScrollEvent(y,-x));
    public void Down() {
        if(held)return;var p=Location();long now=Environment.TickCount64;
        clicks=now-lastClick<550 && Math.Abs(p.X-lastClickPoint.X)<5 && Math.Abs(p.Y-lastClickPoint.Y)<5 ? Math.Min(2,clicks+1):1;
        lastClick=now;lastClickPoint=p;var e=CGEventCreateMouseEvent(IntPtr.Zero,1,p,0);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS mouse event unavailable");CGEventSetIntegerValueField(e,1,clicks);held=true;Post(e);
    }
    public void Release() { if(held){held=false;var e=CGEventCreateMouseEvent(IntPtr.Zero,2,Location(),0);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS mouse event unavailable");CGEventSetIntegerValueField(e,1,clicks);Post(e);} }
    public void Click(bool right) { if(held)return;if(!right){Down();Release();}else{var p=Location();Post(CGEventCreateMouseEvent(IntPtr.Zero,3,p,1));Post(CGEventCreateMouseEvent(IntPtr.Zero,4,p,1));} }
    public void TaskView(){ReleaseAll();Control(126);}
    public void ShowDesktop(){ReleaseAll();Control(125);}
    public void Desktop(int direction){if(direction!=0){ReleaseAll();Control(direction<0?(ushort)123:(ushort)124);}}
    public void AppsBegin(){if(switching)return;switching=true;try{Key(55,true,1UL<<20);AppsStep(1);}catch{AppsEnd();throw;}}
    public void AppsStep(int direction){if(!switching||direction==0)return;ulong flags=(1UL<<20)|(direction<0?1UL<<17:0);Key(48,true,flags);Key(48,false,flags);}
    public void AppsEnd(){if(switching){switching=false;Key(55,false);}}
    public void Media(int action)=>media(action);
    public void MidiPort(int id)=>midi.Select(id);
    public void Midi(bool note,int channel,int number,int value)=>midi.Send(note,channel,number,value);
    public void MidiPanic()=>midi.Panic();
    public void ReleaseAll(){try{Release();}finally{try{AppsEnd();}finally{midi.Panic();}}}
    public void Dispose(){try{ReleaseAll();}finally{midi.Dispose();}}
}

public sealed class MacMidi : MidiOutput {
    private const string MIDI="/System/Library/Frameworks/CoreMIDI.framework/CoreMIDI",CF="/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    [DllImport(CF)] private static extern IntPtr CFStringCreateWithCString(IntPtr allocator,[MarshalAs(UnmanagedType.LPUTF8Str)]string text,uint encoding);
    [DllImport(CF)] private static extern void CFRelease(IntPtr reference);
    [DllImport(MIDI)] private static extern int MIDIClientCreate(IntPtr name,IntPtr notify,IntPtr context,out uint client);
    [DllImport(MIDI)] private static extern int MIDISourceCreate(uint client,IntPtr name,out uint endpoint);
    [DllImport(MIDI)] private static extern int MIDIClientDispose(uint client);
    [DllImport(MIDI)] private static extern int MIDIEndpointDispose(uint endpoint);
    [DllImport(MIDI)] private static extern IntPtr MIDIPacketListInit(IntPtr list);
    [DllImport(MIDI)] private static extern IntPtr MIDIPacketListAdd(IntPtr list,nuint size,IntPtr packet,ulong time,nuint length,byte[] data);
    [DllImport(MIDI)] private static extern int MIDIReceived(uint source,IntPtr list);
    private uint client,source;
    public override MidiPort[] Ports()=>new[]{new MidiPort(0,"3E Phone")};
    protected override void Open(int id) {
        var name=CFStringCreateWithCString(IntPtr.Zero,"3E Phone",0x08000100);
        try{if(MIDIClientCreate(name,IntPtr.Zero,IntPtr.Zero,out client)!=0 || MIDISourceCreate(client,name,out source)!=0){Close();throw new InvalidOperationException("Cannot create the 3E Phone MIDI source");}}
        finally{CFRelease(name);}
    }
    protected override void Close(){if(source!=0){MIDIEndpointDispose(source);source=0;}if(client!=0){MIDIClientDispose(client);client=0;}}
    protected override void Write(byte status,byte number,byte value){
        var list=Marshal.AllocHGlobal(1024);
        try{var packet=MIDIPacketListInit(list);if(MIDIPacketListAdd(list,1024,packet,0,3,new[]{status,number,value})==IntPtr.Zero || MIDIReceived(source,list)!=0)throw new InvalidOperationException("MIDI source unavailable");}
        finally{Marshal.FreeHGlobal(list);}
    }
}
