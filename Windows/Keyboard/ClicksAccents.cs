using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Threading;

// All state is transient. No typed text is logged and the clipboard is not used.
public sealed class AccentEngine {
 public const ulong ClicksTag=0x3345434c, OutputTag=0x33454143;
 public const int HoldMs=650, ChoiceMs=6000;
 public static readonly Dictionary<int,string[]> ChoicesByKey=MakeChoices();
 public static readonly string[] NumberCategories={"Emoji","Currencies","Math","Useful + fun","Arrows","Punctuation","Brackets","Symbols","Superscripts","Subscripts"};
 public Action<string,string[],IntPtr> Show;
 public Action Hide;
 public Action<string,IntPtr> Insert;
 public bool Enabled=true, Active;
 public string[] Choices;
 int candidate, suppressedLetter;
 bool held, upper;
 long started, opened;
 IntPtr focus;
 readonly HashSet<int> swallowUps=new HashSet<int>();
 static Dictionary<int,string[]> MakeChoices() {
  string[] rows={"a á à â ä ã å ā ą æ","b ḃ ḅ ḇ","c ç ć č ĉ ċ","d ď đ ð ḋ ḍ","e é è ê ë ē ė ę ě ĕ","f ḟ","g ğ ģ ǵ ĝ ġ","h ĥ ħ ḧ ḥ","i í ì î ï ī į ı","j ĵ","k ķ ḱ ǩ","l ł ĺ ľ ļ","m ḿ ṁ ṃ","n ñ ń ň ņ ŋ","o ó ò ô ö õ ō ø œ ő","p ṕ ṗ","r ř ŕ ŗ","s ś š ş ș ß","t ť ţ ț þ","u ú ù û ü ū ů ű ų ŭ","v ṽ ṿ","w ŵ ẁ ẃ ẅ","x ẋ ẍ","y ý ÿ ŷ","z ź ż ž"};
  var result=new Dictionary<int,string[]>();
  foreach(string row in rows) { string[] parts=row.Split(' ');var values=new string[parts.Length-1];Array.Copy(parts,1,values,0,values.Length);result.Add(char.ToUpperInvariant(parts[0][0]),values); }
  string[] numbers={
   "🙂 😂 ❤️ 👍 🙏 🎉 🔥 ✅ 👀",
   "$ € £ ¥ ¢ ₹ ₩ ₽ ₿",
   "± × ÷ ≈ ≠ ≤ ≥ ∞ √",
   "✓ ✗ ★ ♥ ☀ ☂ ☕ ⌘ ⚡",
   "← → ↑ ↓ ↔ ↕ ↗ ↘ ⇒",
   "¿ ¡ … — – • · « »",
   "[ ] { } < > ‹ › ⟨⟩",
   "© ® ™ ° § ¶ † ✓ ✗",
   "¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹",
   "₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉"
  };
  for(int i=0;i<numbers.Length;i++)result.Add(0x30+i,numbers[i].Split(' '));
  return result;
 }
 public void Cancel() { if(Active && Hide!=null)Hide();Active=false;Choices=null;candidate=0;held=false; }
 public void Tick(long now,IntPtr currentFocus,bool blocked) {
  if(!Enabled || currentFocus!=focus || blocked) { Cancel();return; }
  if(Active) { if(now-opened>=ChoiceMs)Cancel();return; }
  if(candidate==0 || !held || now-started<HoldMs)return;
  Choices=(string[])ChoicesByKey[candidate].Clone();
  if(upper && candidate>=0x41 && candidate<=0x5A)for(int i=0;i<Choices.Length;i++)Choices[i]=Choices[i]=="ß" ? "ẞ" : Choices[i].ToUpperInvariant();
  Active=true;opened=now;
  if(Show!=null)Show(((char)candidate).ToString().ToLowerInvariant(),Choices,focus);
 }
 public bool Key(int vk,bool down,ulong tag,long now,IntPtr currentFocus,bool blocked,bool capital) {
  if(tag==OutputTag)return false;
  if(tag!=ClicksTag) { if(down)Cancel();return false; }
  if(!down) {
   if(swallowUps.Remove(vk))return true;
   if(vk==suppressedLetter)suppressedLetter=0;
   if(vk==candidate) { held=false;if(!Active)Cancel(); }
   return false;
  }
  if(vk==suppressedLetter || swallowUps.Contains(vk))return true;
  if(!Enabled) { Cancel();return false; }
  if(currentFocus!=focus && candidate!=0)Cancel();
  if(Active) {
   if(vk==candidate && held)return true;
   if(blocked) { Cancel();return false; }
   int index=vk>=0x31 && vk<=0x39 ? vk-0x31 : (vk>=0x61 && vk<=0x69 ? vk-0x61 : -1);
   if(index>=0 && index<Choices.Length) {
    string text=Choices[index];IntPtr target=focus;
    if(held)suppressedLetter=candidate;
    swallowUps.Add(vk);Cancel();if(Insert!=null)Insert(text,target);return true;
   }
   if(vk==0x1B) { if(held)suppressedLetter=candidate;swallowUps.Add(vk);Cancel();return true; }
   Cancel();
  }
  if(vk==candidate && held)return true; // suppress typematic repeats before the picker opens
  if(blocked || !ChoicesByKey.ContainsKey(vk)) { Cancel();return false; }
  Cancel();candidate=vk;held=true;upper=capital;focus=currentFocus;started=now;
  return false; // the normal character appears immediately, with no typing delay
 }
}

public static class AccentPlacement {
 public static Rectangle Place(Size size,Rectangle work,Rectangle target,Point? caret) {
  Rectangle anchor=Rectangle.Intersect(work,target);
  if(anchor.Width<=0 || anchor.Height<=0)anchor=work;
  // Browsers and modern editors often have no Win32 caret. Keep the fallback
  // over the active app instead of placing it at the far bottom of the monitor.
  Point p=caret ?? new Point(anchor.Left+(anchor.Width-size.Width)/2,anchor.Top+(anchor.Height-size.Height)/2);
  if(caret.HasValue && p.Y+size.Height>work.Bottom-8)p.Y=caret.Value.Y-size.Height-24;
  return new Rectangle(Math.Max(work.Left+8,Math.Min(p.X,work.Right-size.Width-8)),Math.Max(work.Top+8,Math.Min(p.Y,work.Bottom-size.Height-8)),size.Width,size.Height);
 }
}

sealed class AccentPopup : Form {
 readonly Font titleFont=new Font("Segoe UI",9), numberFont=new Font("Segoe UI",10), symbolFont=new Font("Segoe UI",21), emojiFont=new Font("Segoe UI Emoji",21);
 public AccentPopup() { Text="Clicks accent choices";FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;BackColor=Color.FromArgb(30,33,40);ForeColor=Color.White;StartPosition=FormStartPosition.Manual;AutoScaleMode=AutoScaleMode.Dpi;Padding=new Padding(12); }
 protected override bool ShowWithoutActivation { get {return true;} }
 protected override CreateParams CreateParams { get {var cp=base.CreateParams;cp.ExStyle|=0x08000000|0x80;return cp;} }
 public void Display(string key,string[] choices,IntPtr target) {
  SuspendLayout();while(Controls.Count>0)Controls[0].Dispose();
  bool number=key.Length==1 && key[0]>='0' && key[0]<='9';
  string category=number ? AccentEngine.NumberCategories[key[0]-'0'] : "Accents";
  ClientSize=new Size(Math.Max(420,24+choices.Length*57),116);
  var title=new Label { Text=key.ToUpperInvariant()+" · "+category+"  ·  Pick 1–"+choices.Length+"  ·  Esc to cancel",AutoSize=false,Location=new Point(14,10),Size=new Size(ClientSize.Width-28,20),Font=titleFont,ForeColor=Color.FromArgb(185,194,209) };
  Controls.Add(title);
  for(int i=0;i<choices.Length;i++) {
   var box=new Panel {Location=new Point(12+i*57,36),Size=new Size(51,68),BackColor=Color.FromArgb(47,52,63)};
   box.Controls.Add(new Label {Text=choices[i],TextAlign=ContentAlignment.MiddleCenter,Location=new Point(0,0),Size=new Size(51,43),Font=key=="0" ? emojiFont : symbolFont});
   box.Controls.Add(new Label {Text=(i+1).ToString(),TextAlign=ContentAlignment.MiddleCenter,Location=new Point(0,43),Size=new Size(51,23),Font=numberFont,ForeColor=Color.FromArgb(118,183,255)});
   Controls.Add(box);
  }
  ClientSize=new Size(Math.Max(420,24+choices.Length*57),116);
  Rectangle area=Screen.FromHandle(target).WorkingArea;Point? caretPoint=null;
  Native.RECT targetRect;Rectangle anchor=Native.GetWindowRect(target,out targetRect) ? Rectangle.FromLTRB(targetRect.Left,targetRect.Top,targetRect.Right,targetRect.Bottom) : area;
  Native.GUITHREADINFO info=new Native.GUITHREADINFO();info.cbSize=(uint)Marshal.SizeOf(typeof(Native.GUITHREADINFO));
  uint tid=Native.GetWindowThreadProcessId(target,IntPtr.Zero);
  if(Native.GetGUIThreadInfo(tid,ref info) && info.hwndCaret!=IntPtr.Zero) {
   Native.POINT caret=new Native.POINT {x=info.rcCaret.Left,y=info.rcCaret.Bottom+10};
   if(Native.ClientToScreen(info.hwndCaret,ref caret))caretPoint=new Point(caret.x,caret.y);
  }
  Bounds=AccentPlacement.Place(Size,area,anchor,caretPoint);
  ResumeLayout(true);
  // Own the popup by the current app, rather than WinForms' hidden startup
  // window. Keep native no-activation showing: managed Show can focus a form
  // again on subsequent displays, which cancels the active accent selection.
  if(target!=IntPtr.Zero)Native.SetWindowLongPtr(Handle,-8,target);
  Native.ShowWindow(Handle,4);
  Native.SetWindowPos(Handle,new IntPtr(-1),Left,Top,Width,Height,0x10|0x40);
  Refresh();
 }
 public void HidePicker() {
  if(!IsHandleCreated)return;
  Native.ShowWindow(Handle,0);
  Native.SetWindowLongPtr(Handle,-8,IntPtr.Zero);
 }
 protected override void Dispose(bool disposing) {base.Dispose(disposing);if(disposing){titleFont.Dispose();numberFont.Dispose();symbolFont.Dispose();emojiFont.Dispose();}}
}

static class Native {
 public delegate IntPtr Hook(int code,IntPtr wp,IntPtr lp);
 public delegate void WinEvent(IntPtr hook,uint ev,IntPtr hwnd,int obj,int child,uint thread,uint time);
 [StructLayout(LayoutKind.Sequential)] public struct KEY {public uint vk,scan,flags,time;public UIntPtr extra;}
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {public uint cbSize,flags;public IntPtr hwndActive,hwndFocus,hwndCapture,hwndMenuOwner,hwndMoveSize,hwndCaret;public RECT rcCaret;}
 [StructLayout(LayoutKind.Sequential)] public struct KI {public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
 [StructLayout(LayoutKind.Explicit,Size=32)] public struct UNION {[FieldOffset(0)] public KI keyboard;}
 [StructLayout(LayoutKind.Sequential)] public struct INPUT {public uint type;public UNION u;}
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetWindowsHookEx(int kind,Hook cb,IntPtr module,uint thread);
 [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
 [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr wp,IntPtr lp);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string name);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
 [DllImport("user32.dll")] public static extern short GetKeyState(int key);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,IntPtr pid);
 [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid,ref GUITHREADINFO info);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd,ref POINT point);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
 [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW",SetLastError=true)] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd,int index,IntPtr value);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int cx,int cy,uint flags);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd,int cmd);
 [DllImport("user32.dll",SetLastError=true)] public static extern uint SendInput(uint count,INPUT[] inputs,int size);
 [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,WinEvent cb,uint pid,uint tid,uint flags);
 [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr h);
 public static bool Blocked() { return GetAsyncKeyState(0x11)<0 || GetAsyncKeyState(0x12)<0 || GetAsyncKeyState(0x5B)<0 || GetAsyncKeyState(0x5C)<0; }
 public static INPUT Input(ushort vk,ushort scan,uint flags) {return new INPUT {type=1,u=new UNION {keyboard=new KI {vk=vk,scan=scan,flags=flags,extra=new UIntPtr(AccentEngine.OutputTag)}}};}
 public static void ReplaceLetter(string text,IntPtr target) {
  if(GetForegroundWindow()!=target || Blocked())return;
  var inputs=new List<INPUT>();inputs.Add(Input(8,0,0));inputs.Add(Input(8,0,2));
  foreach(char ch in text) { inputs.Add(Input(0,ch,4));inputs.Add(Input(0,ch,6)); }
  var a=inputs.ToArray();SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)));
 }
}

sealed class AccentContext : ApplicationContext {
 readonly AccentEngine engine=new AccentEngine();readonly AccentPopup popup=new AccentPopup();readonly Control dispatcher=new Control();
 readonly Stopwatch clock=Stopwatch.StartNew();readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
 readonly NotifyIcon tray=new NotifyIcon();readonly Native.Hook keyCb,mouseCb;readonly Native.WinEvent focusCb;
 IntPtr keyHook,mouseHook,focusHook;
 public AccentContext() {
  // Keep dispatch independent of the popup's current owner closing its window.
  IntPtr window=dispatcher.Handle;
  engine.Show=delegate(string s,string[] c,IntPtr h) { dispatcher.BeginInvoke((Action)delegate {if(engine.Active)popup.Display(s,c,h);}); };
  engine.Hide=delegate {dispatcher.BeginInvoke((Action)delegate {popup.HidePicker();});};
  engine.Insert=delegate(string s,IntPtr h) {dispatcher.BeginInvoke((Action)delegate {Native.ReplaceLetter(s,h);});};
  keyCb=OnKey;mouseCb=OnMouse;focusCb=delegate {engine.Cancel();};
  keyHook=Native.SetWindowsHookEx(13,keyCb,Native.GetModuleHandle(null),0);
  mouseHook=Native.SetWindowsHookEx(14,mouseCb,Native.GetModuleHandle(null),0);
  focusHook=Native.SetWinEventHook(3,3,IntPtr.Zero,focusCb,0,0,0);
  if(keyHook==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
  timer.Interval=30;timer.Tick+=delegate {engine.Tick(clock.ElapsedMilliseconds,Native.GetForegroundWindow(),Native.Blocked());};timer.Start();
  var menu=new ContextMenuStrip();var pause=new ToolStripMenuItem("Pause accent picker") {CheckOnClick=true};
  pause.CheckedChanged+=delegate {engine.Enabled=!pause.Checked;engine.Cancel();};menu.Items.Add(pause);
  menu.Items.Add("Exit accent picker",null,delegate {ExitThread();});
  tray.Icon=SystemIcons.Information;tray.Text="Clicks: hold a letter or number, then pick 1–9";tray.ContextMenuStrip=menu;tray.Visible=true;
 }
 IntPtr OnKey(int code,IntPtr wp,IntPtr lp) {
  try {if(code>=0) {
   Native.KEY key=(Native.KEY)Marshal.PtrToStructure(lp,typeof(Native.KEY));
   bool down=wp.ToInt64()==0x100 || wp.ToInt64()==0x104;
   bool capital=(Native.GetAsyncKeyState(0x10)<0)^((Native.GetKeyState(0x14)&1)!=0);
   if(engine.Key((int)key.vk,down,key.extra.ToUInt64(),clock.ElapsedMilliseconds,Native.GetForegroundWindow(),Native.Blocked(),capital))return new IntPtr(1);
  }} catch {engine.Cancel();} // fail open: a UI error must never disable ordinary typing
  return Native.CallNextHookEx(keyHook,code,wp,lp);
 }
 IntPtr OnMouse(int code,IntPtr wp,IntPtr lp) {
  long msg=wp.ToInt64();if(code>=0 && (msg==0x201||msg==0x204||msg==0x207||msg==0x20A||msg==0x20B||msg==0x20E))engine.Cancel();
  return Native.CallNextHookEx(mouseHook,code,wp,lp);
 }
 protected override void ExitThreadCore() {timer.Stop();if(keyHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(keyHook);if(mouseHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(mouseHook);if(focusHook!=IntPtr.Zero)Native.UnhookWinEvent(focusHook);tray.Dispose();popup.Dispose();dispatcher.Dispose();base.ExitThreadCore();}
}

static class AccentProgram {
 [STAThread] public static void Main(string[] args) {
  bool first;using(var mutex=new Mutex(true,"Local\\3EWindows.ClicksAccents",out first)) {
   if(!first)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   Application.Run(new AccentContext());
  }
 }
}
