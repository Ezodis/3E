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
    [DllImport("ThreeEPhoneNative")] public static extern int ThreeEHasMultipleSpaces();
    [DllImport(CG)] private static extern void CGEventSetFlags(IntPtr e,ulong flags);
    [DllImport(CG)] private static extern void CGEventKeyboardSetUnicodeString(IntPtr e,nuint length,ushort[] text);
    [DllImport(CG)] private static extern void CGEventSetIntegerValueField(IntPtr e,uint field,long value);
    [DllImport(CG)] private static extern void CGEventPost(uint tap,IntPtr e);
    [DllImport(CG)][return:MarshalAs(UnmanagedType.I1)] public static extern bool CGPreflightPostEventAccess();
    [DllImport(CF)] private static extern void CFRelease(IntPtr reference);
    [DllImport("ThreeEPhoneNative")] public static extern int ThreeEGetOutputVolume();
    [DllImport("ThreeEPhoneNative")] private static extern int ThreeESetOutputVolume(int level);
    private readonly OutputVolume volume=new(()=>{int level=ThreeEGetOutputVolume();return level<0?(int?)null:level;},level=>{if(ThreeESetOutputVolume(level)!=1)throw new InvalidOperationException("Output volume unavailable");});
    private readonly MacMidi midi = new();
    private readonly Action<int> media;
    private readonly Action<string,int> systemAction;
    private bool held;
    private bool appSwitcherHeld;
    private object controls;
    private long lastClick; private Point lastClickPoint; private int clicks;
    public MacInput(Action<int> media,Action<string,int> systemAction) { this.media=media;this.systemAction=systemAction;midi.Select(0); }
    public void SetControls(object snapshot) => Volatile.Write(ref controls,snapshot);
    public string Platform => "macos";
    public object GetConnectionInfo() => new {platform=Platform,volume=volume.State,inputPermission=CGPreflightPostEventAccess(),controls=Volatile.Read(ref controls)};
    public object GetInfo() => new {platform=Platform,volume=volume.State,inputPermission=CGPreflightPostEventAccess(),controls=Volatile.Read(ref controls),midi=midi.Info()};
    private static Point Location() { var e=CGEventCreate(IntPtr.Zero);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS pointer event unavailable");try{return CGEventGetLocation(e);}finally{if(e!=IntPtr.Zero)CFRelease(e);} }
    private static void Post(IntPtr e) { if(e==IntPtr.Zero)throw new InvalidOperationException("macOS event unavailable");try{CGEventPost(0,e);}finally{CFRelease(e);} }
    private static void Key(ushort key,bool down,ulong flags=0) { var e=CGEventCreateKeyboardEvent(IntPtr.Zero,key,down);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS keyboard event unavailable");CGEventSetFlags(e,flags);Post(e); }
    public void Move(int x,int y) { var p=Location();p.X+=x;p.Y+=y;Post(CGEventCreateMouseEvent(IntPtr.Zero,held?6u:5u,p,0)); }
    public void Scroll(int x,int y) => Post(ThreeECreateScrollEvent(y,-x));
    public void Down() {
        if(held)return;var p=Location();long now=Environment.TickCount64;
        clicks=now-lastClick<550 && Math.Abs(p.X-lastClickPoint.X)<5 && Math.Abs(p.Y-lastClickPoint.Y)<5 ? Math.Min(2,clicks+1):1;
        lastClick=now;lastClickPoint=p;var e=CGEventCreateMouseEvent(IntPtr.Zero,1,p,0);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS mouse event unavailable");CGEventSetIntegerValueField(e,1,clicks);held=true;Post(e);
    }
    // A fresh click count keeps tap-then-drag from becoming a double-click drag.
    public void DragStart(int x,int y){if(held)return;lastClick=0;Down();}
    public void Release() { if(held){held=false;var e=CGEventCreateMouseEvent(IntPtr.Zero,2,Location(),0);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS mouse event unavailable");CGEventSetIntegerValueField(e,1,clicks);Post(e);} }
    public void Click(bool right) { if(held)return;if(!right){Down();Release();}else{var p=Location();Post(CGEventCreateMouseEvent(IntPtr.Zero,3,p,1));Post(CGEventCreateMouseEvent(IntPtr.Zero,4,p,1));} }
    public void TaskView(){ReleaseAll();systemAction("missionControl",0);}
    // Control–Down opens App Exposé. Use the system Show Desktop key (F11
    // with the Fn modifier) so the Apps dock's downward swipe has the same
    // meaning as Windows, instead of opening Exposé a second time.
    public void ShowDesktop(){ReleaseAll();systemAction("showDesktop",0);}
    public void Desktop(int direction){if(direction!=0){ReleaseAll();systemAction("space",direction);}}
    // An unheld horizontal swipe changes Spaces when there is more than one;
    // otherwise it cycles apps. Holding Apps always opens the app switcher.
    public void Navigate(int direction){if(direction==0)return;if(ThreeEHasMultipleSpaces()!=0)Desktop(direction);else CycleApp(direction);}
    public void AppsBegin(){if(appSwitcherHeld)return;Release();Key(55,true,Cmd);appSwitcherHeld=true;CycleAppKey(1);}
    public void NavigateEnd()=>AppsEnd();
    public void AppsStep(int direction){if(direction!=0){if(!appSwitcherHeld)AppsBegin();CycleAppKey(direction);}}
    public void AppsEnd(){if(!appSwitcherHeld)return;try{Key(55,false,0);}finally{appSwitcherHeld=false;}}
    // Same palette ids as Web/dock.js and PhoneTrackpad.ShortcutCount; real Command keys on macOS.
    private const ulong Cmd=1UL<<20,Shift=1UL<<17;
    private void CycleAppKey(int direction){
        ulong flags=Cmd|(direction<0?Shift:0);bool reverse=direction<0;
        if(reverse)Key(56,true,flags);
        try{Key(48,true,flags);Key(48,false,flags);}
        finally{if(reverse)Key(56,false,Cmd);}
    }
    private void CycleApp(int direction){
        if(direction==0)return;
        Key(55,true,Cmd);
        try{CycleAppKey(direction);}
        finally{Key(55,false,0);}
    }
    private static readonly (ushort key,ulong flags)[] shortcuts={
        (8,Cmd),(9,Cmd),(7,Cmd),(0,Cmd),(6,Cmd),(6,Cmd|Shift),(17,Cmd),(17,Cmd|Shift),(13,Cmd),(45,Cmd),(3,Cmd),(1,Cmd),
        (15,Cmd),(20,Cmd|Shift),(21,Cmd|Shift),(23,Cmd|Shift),(49,Cmd),(12,Cmd)};
    public void Shortcut(int id){
        if((uint)id>=(uint)shortcuts.Length)return;
        Release();var (key,flags)=shortcuts[id];
        try{Key(key,true,flags);}finally{Key(key,false,flags);}
    }
    public void History(int direction){if(direction==0)return;Release();ushort key=direction<0?(ushort)33:(ushort)30;try{Key(key,true,Cmd);}finally{Key(key,false,Cmd);}} // Cmd+[ / Cmd+]
    public void Zoom(int direction){if(direction==0)return;ushort key=direction>0?(ushort)24:(ushort)27;try{Key(key,true,Cmd);}finally{Key(key,false,Cmd);}} // Cmd+= / Cmd+-
    // Phone keyboard: each character is posted as a Unicode key event, so the
    // text is independent of the Mac's keyboard layout (accents and emoji too).
    private readonly MacClipboard clipboard=new();
    public IPhoneClipboard Clipboard=>clipboard;
    public bool SupportsTyping=>true;
    private static void Unicode(ushort[] units){
        foreach(bool down in new[]{true,false}){
            var e=CGEventCreateKeyboardEvent(IntPtr.Zero,0,down);if(e==IntPtr.Zero)throw new InvalidOperationException("macOS keyboard event unavailable");
            CGEventSetFlags(e,0);CGEventKeyboardSetUnicodeString(e,(nuint)units.Length,units);Post(e);
        }
    }
    public void TypeText(string text){
        if(string.IsNullOrEmpty(text))return;
        Release();AppsEnd();
        for(int i=0;i<text.Length;i++){
            char c=text[i];
            if(c=='\r'){if(i+1<text.Length&&text[i+1]=='\n')continue;c='\n';}
            if(c=='\n'){try{Key(36,true);}finally{Key(36,false);}}
            else if(c=='\t'){try{Key(48,true);}finally{Key(48,false);}}
            else if(char.IsHighSurrogate(c)&&i+1<text.Length&&char.IsLowSurrogate(text[i+1])){Unicode(new[]{(ushort)c,(ushort)text[i+1]});i++;}
            else if(c>=0x20&&c!=0x7F)Unicode(new[]{(ushort)c});
        }
    }
    // Ids match PhoneClipboard.KeyCount / Web/clip.js, with Mac text-editing
    // equivalents: line start/end are ⌘← / ⌘→ and delete word is ⌥⌫.
    private const ulong Option=1UL<<19,Arrow=(1UL<<21)|(1UL<<23),Fn=1UL<<23;
    private static readonly (ushort key,ulong flags)[] phoneKeys={
        (51,0),(36,0),(48,0),(53,0),
        (123,Arrow),(126,Arrow),(124,Arrow),(125,Arrow),
        (117,Fn),(123,Arrow|Cmd),(124,Arrow|Cmd),(51,Option)};
    public void PressKey(int id,int repeat){
        if((uint)id>=(uint)phoneKeys.Length)return;
        Release();AppsEnd();var (key,flags)=phoneKeys[id];
        for(int i=0;i<Math.Clamp(repeat,1,64);i++){try{Key(key,true,flags);}finally{Key(key,false,flags);}}
    }
    public void Media(int action)=>media(action);
    public void Volume(int level)=>volume.Set(level);
    public void MidiPort(int id)=>midi.Select(id);
    public void Midi(bool note,int channel,int number,int value)=>midi.Send(note,channel,number,value);
    public void MidiPanic()=>midi.Panic();
    public void VolumeStep(int direction){if(direction==0)return;int level=ThreeEGetOutputVolume();if(level>=0)volume.Set(Math.Clamp(level+direction*6,0,100));}
    public void ReleaseAll(){volume.CancelPending();try{Release();AppsEnd();}finally{midi.Panic();}}
    public void Dispose(){try{ReleaseAll();}finally{volume.Dispose();midi.Dispose();}}
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
