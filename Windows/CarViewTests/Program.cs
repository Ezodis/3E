using ThreeE.CarView;
if(args.Length==2&&args[0]=="--car-view-guard"){CarViewWindows.RunGuard(args[1]);return;}
if(args.Length==1&&args[0]=="--crash-live"){CarViewWindows.CrashProbe();return;}
if(args.Length==1&&args[0]=="--live"){CarViewWindows.LiveSelfTest();Console.WriteLine("PASS: Windows live Car View, independent mirror toggle, normal off and forced-exit recovery restore the original mode and pointer.");return;}
CarViewWindows.RecoverySelfTest();
void Check(bool good,string text){if(!good)throw new Exception(text);}
Check(CarViewWindows.ModeScore(1080,675,60,1440,900)<CarViewWindows.ModeScore(1280,800,60,1440,900),"Larger controls prefer useful workspace size");
Check(CarViewWindows.ModeScore(800,500,60,1440,900)==double.MaxValue,"Workspace remains usable");
Check(CarViewWindows.ModeScore(1280,720,60,1440,900)==double.MaxValue,"Aspect ratio is preserved");
Check(CarViewWindows.ModeScore(1080,675,30,1440,900)==double.MaxValue,"Slow display modes are rejected");
Check(CarViewWindows.ModeScore(1440,900,60,1440,900)==double.MaxValue,"Same-sized mode is not a larger-control mode");
foreach(int left in new[]{-1920,0,1280})foreach(int x in new[]{left,left+100,left+1919})
 Check(CarViewWindows.PresentedX(CarViewWindows.PresentedX(x,left,1920,true),left,1920,true)==x,"Image, pointer and native/phone click agree through reflection");
using(var car=new CarViewWindows()){Check(!car.Enabled&&!car.Mirrored,"Creating Car View changes no display settings");car.Stop();car.Stop();}
Console.WriteLine("PASS: Windows Car View display selection, reflected input geometry and idle cleanup.");
if(OperatingSystem.IsWindows()){
 CarViewWindows.NativeSelfTest();
 Console.WriteLine("PASS: native Windows mirrored pixels, capture exclusion, click-through styles and exact saved-mode serialization. No resolution, pointer or input changes.");
}
