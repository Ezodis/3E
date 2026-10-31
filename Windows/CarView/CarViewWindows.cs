// SPDX-License-Identifier: MIT
using System.ComponentModel;
using System;
using System.IO;
using System.Threading;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace ThreeE.CarView;

// Native click-through presentation only: neither hardware nor Phone Bar input
// is intercepted or reversed. Glass reflects the picture and pointer together.
public sealed class CarViewWindows : IDisposable {
    private readonly WndProc callback;
    private readonly string className="3E.CarView."+Guid.NewGuid().ToString("N");
    private nint pointerWindow,mirrorWindow;
    private Surface source,reflected,pointer,reversePointer;
    private bool registered,magInitialized,stopping;
    private int width,height;
    private long lastFrame;
    private string nonce;
    public bool Enabled {get;private set;}
    public bool Mirrored {get;private set;}
    public string Status {get;private set;}="Off";
    public event Action Changed;
    private const uint TransparentWindow=0x00080000|0x20|0x80|0x08000000; // layered, transparent, tool, no-activate
    private const uint CopyPixels=0x00CC0020, CapturePixels=CopyPixels|0x40000000;
    private static readonly nint Topmost=new(-1);
    private static readonly Lazy<string> statePath=new(()=>{using var process=Process.GetCurrentProcess();return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"3EWindows","CarView","active-"+process.SessionId+".json");});
    private static string StatePath=>statePath.Value;
    public CarViewWindows(){callback=WindowMessage;}
    public static int PresentedX(int x,int left,int width,bool mirror)=>mirror?left+width-1-(x-left):x;
    public static double ModeScore(int w,int h,int hz,int originalW,int originalH)=>
        w<1024||h<640||w>=originalW||Math.Abs((double)w/h-(double)originalW/originalH)>.025||(hz>0&&hz<50)?double.MaxValue:Math.Abs(w/Math.Max(1024.0,originalW*.75)-1)*100;

    public void SetEnabled(bool enabled){if(enabled&&!Enabled)Enable();else if(!enabled)Stop();}
    private void Enable(){
        try {
            using(var gate=LockState()) {
                var old=ReadRecovery();
                if(old!=null){if(OwnerAlive(old))throw new InvalidOperationException("Car View is already active in another 3£ process.");RestoreLocked(old);}
                var original=CurrentMode();
                var recovery=new Recovery{Nonce=Guid.NewGuid().ToString("N"),Owner=Environment.ProcessId,Started=Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks,Mode=Encode(original),CursorVisible=CursorVisible()};
                Directory.CreateDirectory(Path.GetDirectoryName(StatePath));WriteRecovery(recovery);nonce=recovery.Nonce;
                using var ready=new EventWaitHandle(false,EventResetMode.ManualReset,@"Local\3E.CarGuard."+nonce);
                using var guard=Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory,"ThreeE.KeyboardRecovery.exe")){UseShellExecute=false,CreateNoWindow=true,ArgumentList={"--car-view-guard",nonce}});
                if(guard==null||!ready.WaitOne(5000)||guard.HasExited)throw new InvalidOperationException("Car View recovery could not start.");
                var best=original;double score=double.MaxValue;
                for(int index=0;;index++){var mode=NewMode();if(!EnumDisplaySettings(null,index,ref mode))break;mode.Extra=0;
                    if(mode.BitsPerPixel!=original.BitsPerPixel||mode.Orientation!=original.Orientation)continue;
                    double next=ModeScore(mode.Width,mode.Height,mode.Frequency,original.Width,original.Height);if(next<score){best=mode;score=next;}}
                if(score<double.MaxValue){recovery.DisplayChanged=true;WriteRecovery(recovery);if(ChangeDisplaySettingsEx(null,ref best,0,4,0)!=0)throw new InvalidOperationException("Windows could not select the larger display size.");}
            }
            var applied=CurrentMode();width=applied.Width;height=applied.Height;
            if(!MagInitialize())throw Error("Initialize pointer visibility");magInitialized=true;
            EnsureClass();pointer=DrawPointer(false);reversePointer=DrawPointer(true);
            pointerWindow=CreateOverlay("3£ Neon Pointer",88,88);
            if(!SetWindowDisplayAffinity(pointerWindow,0x11))throw Error("Exclude pointer from capture");
            using(var gate=LockState()){var recovery=ReadRecovery();if(recovery?.Nonce!=nonce)throw new InvalidOperationException("Car View recovery state changed.");recovery.PointerChanged=true;WriteRecovery(recovery);}
            if(!MagShowSystemCursor(false))throw Error("Hide native pointer");
            Enabled=true;Status="Larger controls and neon pointer are on.";
            WTSRegisterSessionNotification(pointerWindow,0);
            RegisterHotKey(pointerWindow,0x3EC,0x4000|1|2|8,0x30); // Ctrl+Alt+Win+0
            SetTimer(pointerWindow,1,16,0);Tick();Changed?.Invoke();
        }catch{Stop();throw;}
    }
    public void ToggleMirror(){
        if(Mirrored){StopMirror();Changed?.Invoke();return;}
        if(!Enabled)Enable();
        try {
            source=new Surface(width,height);reflected=new Surface(width,height);
            mirrorWindow=CreateOverlay("3£ Window Reflection",width,height);
            if(!SetWindowDisplayAffinity(mirrorWindow,0x11))throw Error("Exclude mirror from capture");
            if(!SetLayeredWindowAttributes(mirrorWindow,0,255,2))throw Error("Set mirror opacity");
            Capture(source,new Rect(0,0,width,height));Flip(source,reflected);
            Mirrored=true;Status="Mirror on — view through the glass reflection.";lastFrame=0;Tick();Changed?.Invoke();
        }catch{StopMirror();Changed?.Invoke();throw;}
    }
    private void StopMirror(){
        Mirrored=false;if(mirrorWindow!=0){DestroyWindow(mirrorWindow);mirrorWindow=0;}
        source?.Dispose();source=null;reflected?.Dispose();reflected=null;
        Status=Enabled?"Mirror off. Car View stays on.":"Off";
    }
    public void Stop(){
        if(stopping)return;stopping=true;
        try {
            Enabled=false;StopMirror();
            if(pointerWindow!=0){KillTimer(pointerWindow,1);UnregisterHotKey(pointerWindow,0x3EC);WTSUnRegisterSessionNotification(pointerWindow);DestroyWindow(pointerWindow);pointerWindow=0;}
            pointer?.Dispose();pointer=null;reversePointer?.Dispose();reversePointer=null;
            if(nonce!=null)using(var gate=LockState()){var state=ReadRecovery();if(state!=null&&state.Nonce==nonce){state.StopRequested=true;WriteRecovery(state);RestoreLocked(state,magInitialized);}}
            if(magInitialized){MagUninitialize();magInitialized=false;}
            nonce=null;Status="Off — previous resolution and pointer restored.";Changed?.Invoke();
        }finally{stopping=false;}
    }
    public void Dispose(){Stop();if(registered){UnregisterClass(className,GetModuleHandle(null));registered=false;}}
    private void Tick(){
        if(!Enabled)return;
        var mode=CurrentMode();if(mode.Width!=width||mode.Height!=height){Stop();return;}
        if(Mirrored&&Environment.TickCount64-lastFrame>=33){
            Capture(source,new Rect(0,0,width,height));Flip(source,reflected);
            SetWindowPos(mirrorWindow,Topmost,0,0,width,height,0x10|0x40);
            InvalidateRect(mirrorWindow,0,false);UpdateWindow(mirrorWindow);lastFrame=Environment.TickCount64;
        }
        if(GetCursorPos(out var point)){
            bool reverse=Mirrored&&point.X>=0&&point.X<width&&point.Y>=0&&point.Y<height;
            var image=reverse?reversePointer:pointer;
            var target=new Point(PresentedX(point.X,0,width,reverse)-(reverse?79:8),point.Y-8);
            var size=new Size(88,88);var origin=new Point(0,0);var blend=new Blend{SourceConstantAlpha=255,AlphaFormat=1};
            if(!UpdateLayeredWindow(pointerWindow,0,ref target,ref size,image.DC,ref origin,0,ref blend,2))throw Error("Present neon pointer");
            SetWindowPos(pointerWindow,Topmost,0,0,0,0,0x10|0x40|1|2);
        }
    }
    private nint WindowMessage(nint window,uint message,nint w,nint l){
        try {
            if(message==0x113&&window==pointerWindow){Tick();return 0;}
            if(message==0x312){Stop();return 0;}
            if((message==0x2B1&&(w==7||w==2))||(message==0x218&&w==4)){Stop();return 0;}
            if(message==0x84)return -1; // HTTRANSPARENT
            if(message==0x21)return 3; // MA_NOACTIVATE
            if(message==0xF&&window==mirrorWindow&&reflected!=null){
                nint dc=GetDC(window);try{if(!BitBlt(dc,0,0,width,height,reflected.DC,0,0,CopyPixels))throw Error("Paint mirror");}finally{ReleaseDC(window,dc);ValidateRect(window,0);}return 0;
            }
        }catch(Exception error){try{Stop();}catch{}Status=error.Message;try{Changed?.Invoke();}catch{}}
        return DefWindowProc(window,message,w,l);
    }
    private void EnsureClass(){
        if(registered)return;var wc=new WindowClass{Size=(uint)Marshal.SizeOf<WindowClass>(),Instance=GetModuleHandle(null),Proc=callback,Name=className};
        if(RegisterClassEx(ref wc)==0)throw Error("Register Car View");registered=true;
    }
    private nint CreateOverlay(string title,int w,int h){
        var window=CreateWindowEx(TransparentWindow,className,title,0x80000000,0,0,w,h,0,0,GetModuleHandle(null),0);
        if(window==0)throw Error("Create Car View overlay");return window;
    }
    private static Surface DrawPointer(bool flip){
        using var image=new Bitmap(88,88,PixelFormat.Format32bppPArgb);using(var g=Graphics.FromImage(image)){
            g.SmoothingMode=SmoothingMode.AntiAlias;g.TranslateTransform(8,8);g.ScaleTransform(1.25f,1.25f);
            using var path=new GraphicsPath();path.AddPolygon(new PointF[]{new(0,0),new(0,37),new(9,28),new(18,46),new(25,42),new(16,25),new(30,25)});
            using var fill=new SolidBrush(Color.FromArgb(255,4,4,4));g.FillPath(fill,path);
            foreach(var stroke in new[]{(10f,30),(6f,70),(3f,255)}){using var pen=new Pen(Color.FromArgb(stroke.Item2,0,255,194),stroke.Item1){LineJoin=LineJoin.Round};g.DrawPath(pen,path);}
            using var rim=new Pen(Color.White,.75f);g.DrawPath(rim,path);
        }
        if(flip)image.RotateFlip(RotateFlipType.RotateNoneFlipX);
        var surface=new Surface(88,88);var data=image.LockBits(new Rectangle(0,0,88,88),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
        try{var bytes=new byte[88*4];for(int y=0;y<88;y++){Marshal.Copy(nint.Add(data.Scan0,y*data.Stride),bytes,0,bytes.Length);Marshal.Copy(bytes,0,nint.Add(surface.Bits,y*bytes.Length),bytes.Length);}}finally{image.UnlockBits(data);}return surface;
    }
    private static void Capture(Surface target,Rect area){nint screen=GetDC(0);try{if(!BitBlt(target.DC,0,0,target.Width,target.Height,screen,area.Left,area.Top,CapturePixels))throw Error("Capture desktop");}finally{ReleaseDC(0,screen);}}
    private static void Flip(Surface source,Surface target){if(!StretchBlt(target.DC,target.Width-1,0,-target.Width,target.Height,source.DC,0,0,source.Width,source.Height,CopyPixels))throw Error("Reflect desktop");}
    private sealed class Surface : IDisposable {
        public readonly nint DC,Bits;private readonly nint bitmap,old;public readonly int Width,Height;
        public Surface(int width,int height){Width=width;Height=height;DC=CreateCompatibleDC(0);var info=new BitmapInfo{Size=40,Width=width,Height=-height,Planes=1,BitCount=32};bitmap=CreateDIBSection(DC,ref info,0,out var bits,0,0);Bits=bits;
            if(DC==0||bitmap==0){if(bitmap!=0)DeleteObject(bitmap);if(DC!=0)DeleteDC(DC);throw Error("Allocate Car View frame");}old=SelectObject(DC,bitmap);}
        public void Dispose(){SelectObject(DC,old);DeleteObject(bitmap);DeleteDC(DC);}
    }
    // The existing recovery helper restores the exact saved mode
    // and visibility if the owner crashes. It exits as soon as normal off
    // removes the journal. No registry display/cursor preferences are changed.
    public sealed class Recovery {public string Nonce{get;set;}public int Owner{get;set;}public long Started{get;set;}public string Mode{get;set;}public bool CursorVisible{get;set;}public bool PointerChanged{get;set;}public bool DisplayChanged{get;set;}public bool StopRequested{get;set;}}
    private sealed class StateLock : IDisposable {
        private readonly Mutex mutex=new(false,@"Local\3EWindows.CarView");
        public StateLock(){try{if(!mutex.WaitOne(5000))throw new TimeoutException("Car View recovery is busy.");}catch(AbandonedMutexException){}}
        public void Dispose(){mutex.ReleaseMutex();mutex.Dispose();}
    }
    private static StateLock LockState()=>new();
    private static Recovery ReadRecovery()=>File.Exists(StatePath)?JsonSerializer.Deserialize<Recovery>(File.ReadAllText(StatePath)):null;
    private static void WriteRecovery(Recovery state){var temp=StatePath+".tmp";File.WriteAllText(temp,JsonSerializer.Serialize(state));File.Move(temp,StatePath,true);}
    private static bool OwnerAlive(Recovery recovery){try{using var p=Process.GetProcessById(recovery.Owner);return !p.HasExited&&p.StartTime.ToUniversalTime().Ticks==recovery.Started;}catch{return false;}}
    private static void RestoreLocked(Recovery recovery,bool hasMagContext=false){
        var mode=Decode(recovery.Mode);int restored=recovery.DisplayChanged?ChangeDisplaySettingsEx(null,ref mode,0,4,0):0;
        if(restored!=0)restored=ResetDisplaySettingsEx(null,0,0,0,0); // saved monitor may have disconnected
        bool pointerRestored=!recovery.PointerChanged;
        if(recovery.PointerChanged){bool mag=hasMagContext||MagInitialize();pointerRestored=mag&&MagShowSystemCursor(recovery.CursorVisible);if(mag&&!hasMagContext)MagUninitialize();}
        if(restored!=0||!pointerRestored)throw new InvalidOperationException("Windows could not restore Car View's saved display or pointer.");
        File.Delete(StatePath);
    }
    public static void RunGuard(string expectedNonce){
        if(!Guid.TryParseExact(expectedNonce,"N",out _))return;
        try{using var ready=EventWaitHandle.OpenExisting(@"Local\3E.CarGuard."+expectedNonce);ready.Set();}catch{return;}
        for(;;){try{using(var gate=LockState()){var state=ReadRecovery();if(state==null||state.Nonce!=expectedNonce)return;if(state.StopRequested||!OwnerAlive(state)){RestoreLocked(state);return;}}}catch{Thread.Sleep(500);}Thread.Sleep(250);}
    }
    public static void RecoverAbandoned(){using var gate=LockState();var state=ReadRecovery();if(state!=null&&!OwnerAlive(state))RestoreLocked(state);}
    private static string Encode(DevMode mode){nint memory=Marshal.AllocHGlobal(Marshal.SizeOf<DevMode>());try{Marshal.StructureToPtr(mode,memory,false);var bytes=new byte[Marshal.SizeOf<DevMode>()];Marshal.Copy(memory,bytes,0,bytes.Length);return Convert.ToBase64String(bytes);}finally{Marshal.FreeHGlobal(memory);}}
    private static DevMode Decode(string text){var bytes=Convert.FromBase64String(text);if(bytes.Length!=Marshal.SizeOf<DevMode>())throw new InvalidDataException("Invalid saved display mode.");nint memory=Marshal.AllocHGlobal(bytes.Length);try{Marshal.Copy(bytes,0,memory,bytes.Length);var mode=Marshal.PtrToStructure<DevMode>(memory);if((mode.Size<188||mode.Size>Marshal.SizeOf<DevMode>())||mode.Width<320||mode.Height<200||mode.Width>32768||mode.Height>32768)throw new InvalidDataException($"Invalid saved display bounds: size={mode.Size}, width={mode.Width}, height={mode.Height}, fields={mode.Fields:X}, ABI={Marshal.SizeOf<DevMode>()}.");return mode;}finally{Marshal.FreeHGlobal(memory);}}
    private static DevMode NewMode()=>new(){Size=(ushort)Marshal.SizeOf<DevMode>(),Device="",Form=""};
    private static DevMode CurrentMode(){var mode=NewMode();if(!EnumDisplaySettings(null,-1,ref mode))throw Error("Read primary display");mode.Extra=0;return mode;}
    private static bool CursorVisible(){var info=new CursorInfo{Size=Marshal.SizeOf<CursorInfo>()};return !GetCursorInfo(ref info)||(info.Flags&1)!=0;}
    private static Win32Exception Error(string action)=>new(Marshal.GetLastWin32Error(),action);

    public static void RecoverySelfTest(){foreach(ushort size in new ushort[]{188,220}){var mode=NewMode();mode.Size=size;mode.Width=1920;mode.Height=1080;mode.BitsPerPixel=32;mode.Frequency=60;if(Encode(Decode(Encode(mode)))!=Encode(mode))throw new Exception("Saved display mode round trip differs.");}}
    public static void CrashProbe(){using var car=new CarViewWindows();car.SetEnabled(true);car.ToggleMirror();Console.WriteLine("CAR_VIEW_READY");Console.Out.Flush();Thread.Sleep(Timeout.Infinite);}
    public static void LiveSelfTest(){
        string before=Encode(CurrentMode());bool pointerBefore=CursorVisible();
        using(var car=new CarViewWindows()){
            try{car.SetEnabled(true);if(!car.Enabled)throw new Exception("Car View did not enable");car.ToggleMirror();if(!car.Mirrored)throw new Exception("Mirror did not enable");Thread.Sleep(100);car.Tick();car.ToggleMirror();if(car.Mirrored||!car.Enabled)throw new Exception("Mirror off changed Car View");}
            finally{car.Stop();}
        }
        if(Encode(CurrentMode())!=before||CursorVisible()!=pointerBefore||File.Exists(StatePath))throw new Exception("Normal off did not restore original state");
        using var child=Process.Start(new ProcessStartInfo(Environment.ProcessPath){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,ArgumentList={"--crash-live"}});
        try{
            var ready=child.StandardOutput.ReadLineAsync();if(!ready.Wait(TimeSpan.FromSeconds(12))||ready.Result!="CAR_VIEW_READY")throw new Exception("Crash probe did not become ready: "+(child.HasExited?child.StandardError.ReadToEnd():"timeout"));
            child.Kill();child.WaitForExit(5000);
            var deadline=Environment.TickCount64+10000;while(File.Exists(StatePath)&&Environment.TickCount64<deadline)Thread.Sleep(100);
            if(File.Exists(StatePath)||Encode(CurrentMode())!=before||CursorVisible()!=pointerBefore)throw new Exception("Crash recovery did not restore the original display and pointer");
        }finally{if(!child.HasExited)child.Kill();}
    }
    // Native pixel and exclusion checks use only small windows owned by this
    // probe. They never resize the desktop, hide the cursor or post input.
    public static void NativeSelfTest(){
        if(Marshal.SizeOf<DevMode>()!=220)throw new Exception("DEVMODE ABI mismatch");
        var original=CurrentMode();var roundTrip=Decode(Encode(original));if(Encode(roundTrip)!=Encode(original))throw new Exception("Display recovery round trip failed");
        using(var normal=DrawPointer(false))using(var reverse=DrawPointer(true)){
            if((uint)Marshal.ReadInt32(normal.Bits,(8*88+8)*4)>>24==0)throw new Exception("Neon pointer is invisible");
            for(int y=0;y<88;y++)for(int x=0;x<88;x++)if(Marshal.ReadInt32(normal.Bits,(y*88+x)*4)!=Marshal.ReadInt32(reverse.Bits,(y*88+87-x)*4))throw new Exception("Pointer reflection pixels differ");
        }
        using var src=new Surface(16,8);using var dst=new Surface(16,8);
        for(int y=0;y<8;y++)for(int x=0;x<16;x++)SetPixel(src.DC,x,y,x<8?0x000000FFu:0x00FF0000u);
        Flip(src,dst);for(int y=0;y<8;y++)for(int x=0;x<16;x++)if(GetPixel(dst.DC,x,y)!=GetPixel(src.DC,15-x,y))throw new Exception($"Native reflection pixel {x},{y} is {GetPixel(dst.DC,x,y):X}, expected {GetPixel(src.DC,15-x,y):X}.");
        using var owner=new CarViewWindows();owner.EnsureClass();nint window=owner.CreateOverlay("3£ Capture Exclusion Test",16,8);
        try{if(!SetWindowDisplayAffinity(window,0x11)||!GetWindowDisplayAffinity(window,out uint affinity)||affinity!=0x11)throw new Exception("Desktop capture exclusion unavailable");
            long style=GetWindowLongPtr(window,-20).ToInt64();if((style&0x08000020)!=0x08000020)throw new Exception("Overlay intercepts native input");}
        finally{DestroyWindow(window);}
        foreach(int x in new[]{-50,0,99,1234})if(PresentedX(PresentedX(x,-50,2000,true),-50,2000,true)!=x)throw new Exception("Pointer reflection does not match native input");
        NativeCaptureExclusionTest(owner,src);
    }
    private static void NativeCaptureExclusionTest(CarViewWindows owner,Surface pattern){
        nint backing=CreateWindowEx(0x08000080,owner.className,"3£ Test Pattern",0x80000000,100,100,16,8,0,0,GetModuleHandle(null),0);
        nint overlay=owner.CreateOverlay("3£ Test Excluded Overlay",16,8);
        if(backing==0||overlay==0)throw Error("Create capture test");
        using var captured=new Surface(16,8);using var cover=new Surface(16,8);
        void Paint(nint window,Surface image){nint dc=GetDC(window);try{if(!BitBlt(dc,0,0,16,8,image.DC,0,0,CopyPixels))throw Error("Draw test pattern");}finally{ReleaseDC(window,dc);}GdiFlush();DwmFlush();}
        try {
            SetWindowPos(backing,Topmost,100,100,16,8,0x10|0x40);Paint(backing,pattern);
            Capture(captured,new Rect(100,100,116,108));
            if(GetPixel(captured.DC,4,4)!=0x000000FF||GetPixel(captured.DC,12,4)!=0x00FF0000)throw new Exception("Native desktop test pattern was not captured.");
            if(!SetWindowDisplayAffinity(overlay,0x11)||!SetLayeredWindowAttributes(overlay,0,255,2))throw Error("Exclude test overlay");
            SetWindowPos(overlay,Topmost,100,100,16,8,0x10|0x40);
            for(int y=0;y<8;y++)for(int x=0;x<16;x++)SetPixel(cover.DC,x,y,0x0000FF00);
            Paint(overlay,cover);Capture(captured,new Rect(100,100,116,108));
            if(GetPixel(captured.DC,4,4)!=0x000000FF||GetPixel(captured.DC,12,4)!=0x00FF0000)throw new Exception("Mirror capture does not exclude its own overlay.");
        }finally{DestroyWindow(overlay);DestroyWindow(backing);}
    }

    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct DevMode {
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string Device;public ushort Spec,Driver,Size,Extra;public uint Fields;
        public int X,Y,Orientation,FixedOutput;public short Color,Duplex,YResolution,TTOption,Collate;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string Form;public ushort LogPixels;public int BitsPerPixel,Width,Height,Flags,Frequency;public uint ICMMethod,ICMIntent,Media,Dither,Reserved1,Reserved2,PanningWidth,PanningHeight;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Rect {public int Left,Top,Right,Bottom;public Rect(int l,int t,int r,int b){Left=l;Top=t;Right=r;Bottom=b;}}
    [StructLayout(LayoutKind.Sequential)] private struct CursorInfo {public int Size,Flags;public nint Cursor;public Point Position;}
    [StructLayout(LayoutKind.Sequential)] private struct Blend {public byte Operation,Flags,SourceConstantAlpha,AlphaFormat;}
    [StructLayout(LayoutKind.Sequential)] private struct BitmapInfo {public uint Size;public int Width,Height;public ushort Planes,BitCount;public uint Compression,SizeImage;public int XPixels,YPixels;public uint Used,Important;}
    private delegate nint WndProc(nint window,uint message,nint w,nint l);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] private struct WindowClass {public uint Size,Style;public WndProc Proc;public int ClassExtra,WindowExtra;public nint Instance,Icon,Cursor,Background;public string Menu,Name;public nint SmallIcon;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]private static extern nint GetModuleHandle(string name);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]private static extern ushort RegisterClassEx(ref WindowClass value);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]private static extern bool UnregisterClass(string cls,nint instance);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]private static extern nint CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int w,int h,nint parent,nint menu,nint instance,nint param);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]private static extern nint DefWindowProc(nint window,uint message,nint w,nint l);
    [DllImport("user32.dll")]private static extern bool DestroyWindow(nint window);
    [DllImport("user32.dll")]private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")]private static extern bool GetCursorInfo(ref CursorInfo info);
    [DllImport("user32.dll",SetLastError=true)]private static extern bool SetWindowDisplayAffinity(nint window,uint affinity);
    [DllImport("user32.dll")]private static extern bool GetWindowDisplayAffinity(nint window,out uint affinity);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]private static extern nint GetWindowLongPtr(nint window,int index);
    [DllImport("user32.dll")]private static extern bool SetWindowPos(nint window,nint after,int x,int y,int w,int h,uint flags);
    [DllImport("user32.dll")]private static extern nuint SetTimer(nint window,nuint id,uint ms,nint callback);
    [DllImport("user32.dll")]private static extern bool KillTimer(nint window,nuint id);
    [DllImport("user32.dll")]private static extern bool RegisterHotKey(nint window,int id,uint modifiers,uint key);
    [DllImport("user32.dll")]private static extern bool UnregisterHotKey(nint window,int id);
    [DllImport("wtsapi32.dll")]private static extern bool WTSRegisterSessionNotification(nint window,uint flags);
    [DllImport("wtsapi32.dll")]private static extern bool WTSUnRegisterSessionNotification(nint window);
    [DllImport("user32.dll",SetLastError=true)]private static extern bool UpdateLayeredWindow(nint window,nint screen,ref Point point,ref Size size,nint source,ref Point sourcePoint,uint key,ref Blend blend,uint flags);
    [DllImport("user32.dll",SetLastError=true)]private static extern bool SetLayeredWindowAttributes(nint window,uint key,byte alpha,uint flags);
    [DllImport("user32.dll")]private static extern bool InvalidateRect(nint window,nint rect,bool erase);
    [DllImport("user32.dll")]private static extern bool ValidateRect(nint window,nint rect);
    [DllImport("user32.dll")]private static extern bool UpdateWindow(nint window);
    [DllImport("user32.dll")]private static extern nint GetDC(nint window);
    [DllImport("user32.dll")]private static extern int ReleaseDC(nint window,nint dc);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]private static extern bool EnumDisplaySettings(string device,int index,ref DevMode mode);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]private static extern int ChangeDisplaySettingsEx(string device,ref DevMode mode,nint window,uint flags,nint param);
    [DllImport("user32.dll",EntryPoint="ChangeDisplaySettingsExW",CharSet=CharSet.Unicode)]private static extern int ResetDisplaySettingsEx(string device,nint mode,nint window,uint flags,nint param);
    [DllImport("Magnification.dll")]private static extern bool MagInitialize();
    [DllImport("Magnification.dll")]private static extern bool MagUninitialize();
    [DllImport("Magnification.dll")]private static extern bool MagShowSystemCursor(bool show);
    [DllImport("gdi32.dll")]private static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll")]private static extern bool DeleteDC(nint dc);
    [DllImport("gdi32.dll")]private static extern bool DeleteObject(nint value);
    [DllImport("gdi32.dll")]private static extern nint SelectObject(nint dc,nint value);
    [DllImport("gdi32.dll",SetLastError=true)]private static extern nint CreateDIBSection(nint dc,ref BitmapInfo info,uint usage,out nint bits,nint section,uint offset);
    [DllImport("gdi32.dll",SetLastError=true)]private static extern bool BitBlt(nint dest,int x,int y,int w,int h,nint src,int sx,int sy,uint op);
    [DllImport("gdi32.dll",SetLastError=true)]private static extern bool StretchBlt(nint dest,int x,int y,int w,int h,nint src,int sx,int sy,int sw,int sh,uint op);
    [DllImport("gdi32.dll")]private static extern uint GetPixel(nint dc,int x,int y);
    [DllImport("gdi32.dll")]private static extern uint SetPixel(nint dc,int x,int y,uint color);
    [DllImport("gdi32.dll")]private static extern bool GdiFlush();
    [DllImport("dwmapi.dll")]private static extern int DwmFlush();
}
