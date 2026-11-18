using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Threading;

// All state is transient. No typed text is logged and the clipboard is not used.
public sealed class AccentEngine {
 // Both tags keep bit 0 clear: PowerToys Keyboard Manager ignores any event with that bit set as its
 // own output, so a sticky release with it would never reach the Mac layout and Ctrl would stay down.
 public const ulong ClicksTag=0x3345434c, OutputTag=0x33454142;
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
 // Games read held keys as actions (camera pan, stop, ...): the picker never opens over League or
 // any full-screen window. The desktop itself is the size of the screen, so it is not a game.
 public static bool GameWindow(string title,string className,bool fullScreen) {
  if(title=="League of Legends (TM) Client" || className=="RiotWindowClass")return true;
  return fullScreen && className!="Progman" && className!="WorkerW" && className!="Shell_TrayWnd";
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

// Sticky Command / Shift / Alt for the Clicks keyboard. Kanata sends plain modifiers; a modifier
// tapped on its own (down then up, nothing between) stays down as a sticky. All stickies share one
// window: the first starts 7 s; one tapped in the last 2 s adds 3 s; nothing else extends it.
// The next ordinary key uses every sticky, then they all release. When the window ends they
// all release too, so a modifier can never stay stuck (Cmd+Tab always works afterwards).
public sealed class StickyEngine {
 public const int WindowMs=7000, LateMs=2000, ExtendMs=3000;
 public static readonly int[] Modifiers={0xA3,0xA0,0xA1,0xA5}; // right Ctrl (Command), Shifts, right Alt (Ctrl key)
 public Action<int[]> Release;           // inject key-ups for these modifiers (after the current event)
 readonly List<int> stickies=new List<int>();
 readonly HashSet<int> modsDown=new HashSet<int>(), keysDown=new HashSet<int>();
 int tapCandidate;                       // modifier pressed with no other key since
 bool used;                              // an ordinary key went down while stickies were on
 long deadline;
 public IList<int> Stickies { get {return stickies.AsReadOnly();} }
 public long Deadline { get {return deadline;} }
 static bool IsModifier(int vk) {return Array.IndexOf(Modifiers,vk)>=0;}
 // Returns true when this event must be swallowed (a tap's key-up that keeps the modifier down).
 public bool Key(int vk,bool down,long now) {
  if(IsModifier(vk)) {
   if(down) {
    if(modsDown.Add(vk) && keysDown.Count==0)tapCandidate=vk; // auto-repeat keeps the first press
    return false;
   }
   modsDown.Remove(vk);
   if(tapCandidate!=vk) {
    if(stickies.Contains(vk))return true; // held again over a sticky: it stays down until release
    return false;                          // held with other keys: an ordinary modifier release
   }
   tapCandidate=0;
   if(!stickies.Contains(vk)) {
    if(stickies.Count==0)deadline=now+WindowMs;
    else if(deadline-now<LateMs)deadline+=ExtendMs;
    stickies.Add(vk);
   }
   return true;
  }
  if(down) {
   tapCandidate=0;
   if(vk==0x5B || vk==0x5C) { ReleaseAll();return false; } // Windows (dictation): never Ctrl/Shift+Win
   keysDown.Add(vk);
   if(stickies.Count>0)used=true;
   return false;
  }
  keysDown.Remove(vk);
  if(used && keysDown.Count==0)ReleaseAll();
  return false;
 }
 public void Tick(long now) {
  if(stickies.Count>0 && now>=deadline && keysDown.Count==0)ReleaseAll();
 }
 public void ReleaseAll() {
  used=false;
  if(stickies.Count==0)return;
  int[] up=stickies.ToArray();stickies.Clear();
  if(Release!=null)Release(up);
 }
}

// ---------------- TypeFix: AI correction of fast, mixed-language typing ----------------
// Double-tap the red Clicks key: the paragraph just typed goes to the local AI server (llama.cpp,
// offline) with keyboard hints; a menu shows up to three readings; 1-3 replaces the paragraph.
// Typed text lives only in memory, is never logged, and is dropped on any cursor move or focus change.

// What was typed in the current field, as far as it can be known from keystrokes alone.
public sealed class TypingBuffer {
 public const int MaxChars=2000;
 readonly System.Text.StringBuilder text=new System.Text.StringBuilder();
 public string Text { get {return text.ToString();} }
 public void Reset() { text.Length=0; }
 // chars: what the key types (from the keyboard layout); shortcut: Ctrl/Alt/Win held.
 public void Key(int vk,string chars,bool shortcut) {
  if(shortcut) { Reset();return; }
  if(vk==0x08) { if(text.Length>0) { int n=text.Length>1 && char.IsLowSurrogate(text[text.Length-1]) ? 2 : 1;text.Length-=n; } return; }
  if(vk==0x0D) { Append("\n");return; }
  // Cursor moves, Tab, Delete, Escape: the field is no longer what we saw typed.
  if(vk==0x09 || vk==0x1B || vk==0x2E || (vk>=0x21 && vk<=0x28)) { Reset();return; }
  if(!string.IsNullOrEmpty(chars) && !char.IsControl(chars[0]))Append(chars);
 }
 public void ReplaceLast(string replacement) {   // the accent picker swapped the last letter
  if(text.Length>0)text.Length--;
  Append(replacement);
 }
 public void Set(string value) { Reset();Append(value); }
 public void ReplaceParagraph(string value) { string t=Text;int i=t.LastIndexOf('\n');Set((i<0 ? "" : t.Substring(0,i+1))+value); }
 // The chosen reading keeps the spaces/line breaks the writer left at the end of the paragraph.
 public static string WithTrailingSpace(string original,string chosen) {
  int i=original.Length;while(i>0 && char.IsWhiteSpace(original[i-1]))i--;
  return chosen.TrimEnd()+original.Substring(i);
 }
 void Append(string s) { text.Append(s);if(text.Length>MaxChars)text.Remove(0,text.Length-MaxChars); }
 // The paragraph being typed: everything after the last line break.
 public string Paragraph() { string t=Text;int i=t.LastIndexOf('\n');return i<0 ? t : t.Substring(i+1); }
 // Backspaces needed to remove a string (one per character the user sees).
 public static int Backspaces(string s) { int n=0;for(int i=0;i<s.Length;i++)if(!char.IsLowSurrogate(s[i]))n++;return n; }
}

// Red Clicks key: a tap is Tab (sent after a short wait), a double-tap opens TypeFix.
public sealed class RedKeyTaps {
 public const int DoubleMs=300;
 public enum Act { Pass, Swallow, Trigger }
 public Action FlushTab;               // send the delayed Tab
 bool pending, upSeen, swallowUp;
 long at;
 public Act Key(bool down,long now) {
  if(!down) {
   if(swallowUp) { swallowUp=false;return Act.Swallow; }
   if(pending) { upSeen=true;return Act.Swallow; }
   return Act.Pass;
  }
  if(pending && !upSeen) { Flush();return Act.Pass; }       // held: auto-repeat, behave as Tab
  if(pending && now-at<=DoubleMs) { pending=false;swallowUp=true;return Act.Trigger; }
  if(pending)Flush();
  pending=true;upSeen=false;at=now;
  return Act.Swallow;
 }
 public void Tick(long now) { if(pending && upSeen && now-at>DoubleMs)Flush(); }
 public void Cancel() { if(pending)Flush(); }
 void Flush() { pending=false;if(FlushTab!=null)FlushTab(); }
}

// Pulls finished option strings out of the model's streamed JSON: {"options":["...","..."]}.
public sealed class OptionStream {
 readonly System.Text.StringBuilder raw=new System.Text.StringBuilder();
 public readonly List<string> Options=new List<string>();
 public bool Add(string chunk) {
  raw.Append(chunk);
  string s=raw.ToString();int start=s.IndexOf('[');
  if(start<0)return false;
  var found=new List<string>();int i=start+1;
  while(i<s.Length) {
   while(i<s.Length && (s[i]==',' || char.IsWhiteSpace(s[i])))i++;
   if(i>=s.Length || s[i]!='"')break;
   string value;int end=JsonText.ReadString(s,i,out value);
   if(end<0)break;
   found.Add(value.Trim());i=end;
  }
  if(found.Count==Options.Count)return false;
  Options.Clear();Options.AddRange(found);
  return true;
 }
}

public static class JsonText {
 public static string Quote(string s) {
  var b=new System.Text.StringBuilder("\"");
  foreach(char c in s) {
   if(c=='"')b.Append("\\\"");else if(c=='\\')b.Append("\\\\");else if(c=='\n')b.Append("\\n");else if(c=='\r')b.Append("\\r");else if(c=='\t')b.Append("\\t");
   else if(c<0x20)b.Append("\\u").Append(((int)c).ToString("x4"));else b.Append(c);
  }
  return b.Append('"').ToString();
 }
 // Reads the JSON string starting at s[i]=='"'; returns the index after it, or -1 if incomplete.
 public static int ReadString(string s,int i,out string value) {
  var b=new System.Text.StringBuilder();value=null;
  for(int j=i+1;j<s.Length;j++) {
   char c=s[j];
   if(c=='"') { value=b.ToString();return j+1; }
   if(c!='\\') { b.Append(c);continue; }
   if(++j>=s.Length)return -1;
   switch(s[j]) {
    case 'n': b.Append('\n');break; case 't': b.Append('\t');break; case 'r': b.Append('\r');break;
    case 'b': b.Append('\b');break; case 'f': b.Append('\f');break;
    case 'u': if(j+4>=s.Length)return -1;b.Append((char)Convert.ToInt32(s.Substring(j+1,4),16));j+=4;break;
    default: b.Append(s[j]);break;
   }
  }
  return -1;
 }
 // Every "content" string in one streamed chunk (chat completion delta).
 public static string Content(string json) {
  var b=new System.Text.StringBuilder();int i=0;
  while((i=json.IndexOf("\"content\"",i,StringComparison.Ordinal))>=0) {
   i+=9;while(i<json.Length && (json[i]==':' || json[i]==' '))i++;
   if(i<json.Length && json[i]=='"') { string v;int end=ReadString(json,i,out v);if(end<0)break;b.Append(v);i=end; }
  }
  return b.ToString();
 }
}

// Keyboard hints: for typed chunks that are not known words, the English/Spanish/French words they most
// likely came from on a QWERTY keyboard (neighbour keys, extra keys hit next to the intended one, missing
// letters, a stray space). Same scoring as Shared/TypeFix/hints.py.
public sealed class KeyboardHints {
 static readonly string[] Rows={"1234567890","qwertyuiop","asdfghjkl","zxcvbnm"};
 static readonly bool[,] Near=MakeNear();
 readonly Dictionary<string,KeyValuePair<string,double>> words=new Dictionary<string,KeyValuePair<string,double>>();
 readonly Dictionary<char,List<string>> byFirst=new Dictionary<char,List<string>>();
 static bool[,] MakeNear() {
  var pos=new Dictionary<char,double[]>();
  for(int r=0;r<Rows.Length;r++)for(int i=0;i<Rows[r].Length;i++)pos[Rows[r][i]]=new double[]{r,i+(r>0 ? 0.5*r : 0)};
  var near=new bool[128,128];
  foreach(var a in pos)foreach(var b in pos)near[a.Key,b.Key]=Math.Abs(a.Value[0]-b.Value[0])<=1 && Math.Abs(a.Value[1]-b.Value[1])<=1.5;
  return near;
 }
 public static bool IsNear(char a,char b) { return a==b || (a<128 && b<128 && Near[a,b]); }
 public static string Fold(string s) {
  var b=new System.Text.StringBuilder();
  foreach(char c in s.ToLowerInvariant().Normalize(System.Text.NormalizationForm.FormD))
   if(System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c)!=System.Globalization.UnicodeCategory.NonSpacingMark)b.Append(c);
  return b.ToString();
 }
 // Cost of typing `typed` when meaning `word` (both folded).
 public static double Cost(string typed,string word) {
  int n=typed.Length,m=word.Length;
  var prev=new double[m+1];var cur=new double[m+1];
  for(int j=0;j<=m;j++)prev[j]=j*1.5;
  for(int i=1;i<=n;i++) {
   char t=typed[i-1];cur[0]=prev[0]+1.0;
   for(int j=1;j<=m;j++) {
    char w=word[j-1];
    double sub=prev[j-1]+(t==w ? 0 : IsNear(t,w) ? 0.6 : 2.0);
    double extra=prev[j]+(IsNear(t,w) || (i>1 && IsNear(t,typed[i-2])) ? 0.35 : 1.2);
    double miss=cur[j-1]+1.5;
    cur[j]=Math.Min(sub,Math.Min(extra,miss));
   }
   var swap=prev;prev=cur;cur=swap;
  }
  return prev[m];
 }
 public void Add(string word,long count) {
  string key=Fold(word);if(key.Length==0)return;
  double f=Math.Log10(count+1);KeyValuePair<string,double> old;
  if(words.TryGetValue(key,out old)) { if(old.Value<f)words[key]=new KeyValuePair<string,double>(word,f);return; }
  words[key]=new KeyValuePair<string,double>(word,f);
  List<string> list;if(!byFirst.TryGetValue(key[0],out list))byFirst[key[0]]=list=new List<string>();
  list.Add(key);
 }
 public void Load(string file) {
  foreach(string line in System.IO.File.ReadLines(file,System.Text.Encoding.UTF8)) {
   int sp=line.IndexOf(' ');long n;
   if(sp>0 && long.TryParse(line.Substring(sp+1),out n))Add(line.Substring(0,sp),n);
  }
 }
 public bool Known(string token) { return words.ContainsKey(Fold(token)); }
 public List<string> Candidates(string token,int limit) {
  var t=new System.Text.StringBuilder();foreach(char c in Fold(token))if(char.IsLetterOrDigit(c))t.Append(c);
  string typed=t.ToString();var result=new List<string>();
  if(typed.Length==0)return result;
  var scored=new List<KeyValuePair<double,string>>();
  foreach(var first in byFirst) {
   if(!IsNear(first.Key,typed[0]))continue;
   foreach(string key in first.Value) {
    if(key.Length*3<typed.Length || key.Length>typed.Length+2)continue;
    scored.Add(new KeyValuePair<double,string>(Cost(typed,key)-0.25*words[key].Value,key));
   }
  }
  scored.Sort(delegate(KeyValuePair<double,string> a,KeyValuePair<double,string> b) {return a.Key.CompareTo(b.Key);});
  for(int i=0;i<scored.Count && result.Count<limit;i++)result.Add(words[scored[i].Value].Key);
  return result;
 }
 public List<string> Hints(string text) {
  var lines=new List<string>();
  string[] tokens=text.Split(new[]{' ','\n','\t'},StringSplitOptions.RemoveEmptyEntries);
  for(int i=0;i<tokens.Length && lines.Count<40;i++) {
   string tok=tokens[i];bool letters=false;foreach(char c in tok)if(char.IsLetter(c))letters=true;
   if(!letters || Known(tok.Trim('.',',',';',':','!','?','¿','¡','"','\'','(',')')))continue;
   var c1=Candidates(tok,3);
   if(i+1<tokens.Length)foreach(string w in Candidates(tok+tokens[i+1],2))c1.Add(w+" (joined with next)");
   if(c1.Count>0)lines.Add(tok+": "+string.Join(", ",c1.ToArray()));
  }
  return lines;
 }
}

public static class TypeFixPrompt {
 // Keep identical to Shared/TypeFix/prompt.txt (the Mac app and edy.chat use that file; a test compares them).
 public const string System=@"You repair text typed fast on a tiny phone keyboard. The writer speaks Spanish (Mexican, Spain and Colombian), French and English, and often mixes two or three of them in one sentence.

Typing errors to undo: a key next to the intended one (keyboard neighbours), doubled, missing or swapped letters, letters from two words merged, and stray spaces from hitting the space bar by accident (a word split in two).

The message may end with keyboard hints: dictionary words each garbled chunk most likely came from. They are suggestions from a spell matcher, not the answer; use the sentence's meaning to choose.

Rules:
- Recover exactly what the writer meant. Never translate: every word stays in the language the writer chose for it, even mid-sentence.
- Keep their dialect, slang and tone (Mexican, Spain or Colombian Spanish; casual or formal).
- Add the accents and punctuation that language needs (á é í ó ú ñ ü ¿ ¡, é è à ç ê ô, apostrophes).
- Keep names, numbers, links and emoji as typed.
- Do not add or remove ideas.

Return three different readings, the most likely first: {""options"": [""..."", ""..."", ""...""]}.
";
 public static string UserMessage(string typed,IList<string> hints) {
  if(hints==null || hints.Count==0)return typed;
  return typed+"\n\nKeyboard hints (likely intended words per typed chunk):\n"+string.Join("\n",new List<string>(hints).ToArray());
 }
 public static string RequestBody(string typed,IList<string> hints) {
  return "{\"messages\":[{\"role\":\"system\",\"content\":"+JsonText.Quote(System)+"},{\"role\":\"user\",\"content\":"+JsonText.Quote(UserMessage(typed,hints))+"}],"+
   "\"temperature\":0.3,\"max_tokens\":700,\"stream\":true,\"cache_prompt\":true,"+
   "\"response_format\":{\"type\":\"json_object\",\"schema\":{\"type\":\"object\",\"properties\":{\"options\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":3,\"maxItems\":3}},\"required\":[\"options\"]}},"+
   "\"chat_template_kwargs\":{\"enable_thinking\":false}}";
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
 [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO {public int cbSize;public RECT rcMonitor,rcWork;public uint dwFlags;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd,System.Text.StringBuilder text,int max);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd,System.Text.StringBuilder text,int max);
 [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd,uint flags);
 [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor,ref MONITORINFO info);
 public static bool InGame(IntPtr hwnd) {
  if(hwnd==IntPtr.Zero)return false;
  var title=new System.Text.StringBuilder(256);GetWindowText(hwnd,title,256);
  var cls=new System.Text.StringBuilder(256);GetClassName(hwnd,cls,256);
  bool full=false;RECT r;
  var info=new MONITORINFO {cbSize=Marshal.SizeOf(typeof(MONITORINFO))};
  if(GetWindowRect(hwnd,out r) && GetMonitorInfo(MonitorFromWindow(hwnd,2),ref info))
   full=r.Left<=info.rcMonitor.Left && r.Top<=info.rcMonitor.Top && r.Right>=info.rcMonitor.Right && r.Bottom>=info.rcMonitor.Bottom;
  return AccentEngine.GameWindow(title.ToString(),cls.ToString(),full);
 }
 public static bool Blocked() { return GetAsyncKeyState(0x11)<0 || GetAsyncKeyState(0x12)<0 || GetAsyncKeyState(0x5B)<0 || GetAsyncKeyState(0x5C)<0 || InGame(GetForegroundWindow()); }
 public static INPUT Input(ushort vk,ushort scan,uint flags) {return new INPUT {type=1,u=new UNION {keyboard=new KI {vk=vk,scan=scan,flags=flags,extra=new UIntPtr(AccentEngine.OutputTag)}}};}
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code,uint type);
 public static void KeyUps(int[] vks) {
  var inputs=new List<INPUT>();
  foreach(int vk in vks) {
   uint extended=vk==0xA3 || vk==0xA5 ? 1u : 0u; // right Ctrl and right Alt are extended keys
   inputs.Add(Input((ushort)vk,(ushort)MapVirtualKey((uint)vk,0),2|extended));
  }
  var a=inputs.ToArray();SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)));
 }
 [DllImport("user32.dll")] static extern int ToUnicodeEx(uint vk,uint scan,byte[] state,[Out,MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder buffer,int size,uint flags,IntPtr layout);
 [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
 // What a key types in the foreground app's keyboard layout, without disturbing dead-key state.
 public static string CharsFor(uint vk,uint scan,IntPtr window) {
  var state=new byte[256];
  foreach(int k in new[]{0x10,0xA0,0xA1,0x11,0xA2,0xA3,0x12,0xA4,0xA5})if(GetAsyncKeyState(k)<0)state[k]=0x80;
  if((GetKeyState(0x14)&1)!=0)state[0x14]=1;
  var b=new System.Text.StringBuilder(8);
  int n=ToUnicodeEx(vk,scan,state,b,8,4,GetKeyboardLayout(GetWindowThreadProcessId(window,IntPtr.Zero)));
  return n>0 ? b.ToString(0,n) : "";
 }
 public static bool ShortcutHeld() {
  bool ctrl=GetAsyncKeyState(0x11)<0, alt=GetAsyncKeyState(0x12)<0;
  return (ctrl!=alt) || GetAsyncKeyState(0x5B)<0 || GetAsyncKeyState(0x5C)<0;  // Ctrl+Alt together is AltGr typing
 }
 public static bool AnyModifierHeld() { return GetAsyncKeyState(0x10)<0 || GetAsyncKeyState(0x11)<0 || GetAsyncKeyState(0x12)<0 || GetAsyncKeyState(0x5B)<0 || GetAsyncKeyState(0x5C)<0; }
 public static void Tap(ushort vk) { var a=new[]{Input(vk,(ushort)MapVirtualKey(vk,0),0),Input(vk,(ushort)MapVirtualKey(vk,0),2)};SendInput(2,a,Marshal.SizeOf(typeof(INPUT))); }
 // Remove `backspaces` characters and type `text` in their place.
 public static void ReplaceText(int backspaces,string text,IntPtr target) {
  if(GetForegroundWindow()!=target)return;
  var inputs=new List<INPUT>();
  for(int i=0;i<backspaces;i++) { inputs.Add(Input(8,0,0));inputs.Add(Input(8,0,2)); }
  foreach(char ch in text) {
   if(ch=='\n') { inputs.Add(Input(0x0D,0,0));inputs.Add(Input(0x0D,0,2));continue; }
   if(ch=='\r')continue;
   inputs.Add(Input(0,ch,4));inputs.Add(Input(0,ch,6));
  }
  var a=inputs.ToArray();SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)));
 }
 public static void ReplaceLetter(string text,IntPtr target) {
  if(GetForegroundWindow()!=target || Blocked())return;
  var inputs=new List<INPUT>();inputs.Add(Input(8,0,0));inputs.Add(Input(8,0,2));
  foreach(char ch in text) { inputs.Add(Input(0,ch,4));inputs.Add(Input(0,ch,6)); }
  var a=inputs.ToArray();SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)));
 }
}

// The local AI server (llama.cpp) described by %LOCALAPPDATA%\3EWindows\AI\typefix.json, which
// Setup-TypeFix.ps1 writes. Nothing leaves the PC: the server listens on 127.0.0.1 only.
sealed class TypeFixService {
 public static readonly string Root=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"3EWindows","AI");
 public string Url="http://127.0.0.1:8089", Server, Arguments;
 public bool Configured;
 KeyboardHints hints;
 readonly object gate=new object();
 public TypeFixService() {
  string config=System.IO.Path.Combine(Root,"typefix.json");
  if(!System.IO.File.Exists(config))return;
  string json=System.IO.File.ReadAllText(config);
  Url=Field(json,"url") ?? Url;Server=Field(json,"server");Arguments=Field(json,"arguments") ?? "";
  Configured=Server!=null && System.IO.File.Exists(Server);
 }
 static string Field(string json,string name) {
  int i=json.IndexOf("\""+name+"\"",StringComparison.Ordinal);if(i<0)return null;
  i=json.IndexOf('"',json.IndexOf(':',i)+1);if(i<0)return null;
  string v;return JsonText.ReadString(json,i,out v)<0 ? null : v;
 }
 public bool Healthy() {
  try {
   var r=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(Url+"/health");r.Timeout=1500;r.Proxy=null;
   using(var resp=(System.Net.HttpWebResponse)r.GetResponse())return resp.StatusCode==System.Net.HttpStatusCode.OK;
  } catch { return false; }
 }
 // Start the server hidden if it is not answering (it keeps running for later corrections).
 public void EnsureStarted() {
  if(!Configured || Healthy())return;
  foreach(var p in Process.GetProcessesByName("llama-server")) { p.Dispose();return; }  // already loading
  var info=new ProcessStartInfo(Server,Arguments) {UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=System.IO.Path.GetDirectoryName(Server)};
  try { using(Process.Start(info)) {} } catch {}
 }
 public void LoadHints() {
  var h=new KeyboardHints();
  foreach(string lang in new[]{"en","es","fr"}) {
   string file=System.IO.Path.Combine(Root,"words",lang+".txt");
   if(System.IO.File.Exists(file))h.Load(file);
  }
  lock(gate)hints=h;
 }
 // Streams options for `typed`; calls update with every new set of finished options.
 public void Fix(string typed,Func<bool> cancelled,Action<List<string>,string> update) {
  try {
   KeyboardHints h;lock(gate)h=hints;
   var found=h==null ? new List<string>() : h.Hints(typed);
   if(!Healthy())EnsureStarted();
   for(int i=0;i<180 && !Healthy();i++) { if(cancelled())return;if(i==0)update(null,"Starting the AI… (first use takes about 30 s)");Thread.Sleep(1000); }
   var r=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(Url+"/v1/chat/completions");
   r.Method="POST";r.ContentType="application/json";r.Proxy=null;r.Timeout=120000;r.ReadWriteTimeout=120000;
   byte[] body=System.Text.Encoding.UTF8.GetBytes(TypeFixPrompt.RequestBody(typed,found));
   using(var s=r.GetRequestStream())s.Write(body,0,body.Length);
   var options=new OptionStream();
   using(var resp=r.GetResponse())using(var reader=new System.IO.StreamReader(resp.GetResponseStream(),System.Text.Encoding.UTF8)) {
    string line;
    while((line=reader.ReadLine())!=null && !cancelled()) {
     if(!line.StartsWith("data:"))continue;
     string data=line.Substring(5).Trim();if(data=="[DONE]")break;
     if(options.Add(JsonText.Content(data)))update(new List<string>(options.Options),null);
    }
   }
   if(options.Options.Count==0 && !cancelled())update(null,"The AI gave no answer. Try again.");
  } catch(Exception) { if(!cancelled())update(null,Configured ? "The AI is not reachable. Try again in a moment." : "TypeFix is not set up. Run Setup-TypeFix.ps1."); }
 }
}

sealed class TypeFixPopup : Form {
 readonly Font titleFont=new Font("Segoe UI",9), textFont=new Font("Segoe UI",11), numberFont=new Font("Segoe UI Semibold",11);
 public TypeFixPopup() { Text="TypeFix";FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;BackColor=Color.FromArgb(30,33,40);ForeColor=Color.White;StartPosition=FormStartPosition.Manual;AutoScaleMode=AutoScaleMode.Dpi; }
 protected override bool ShowWithoutActivation { get {return true;} }
 protected override CreateParams CreateParams { get {var cp=base.CreateParams;cp.ExStyle|=0x08000000|0x80;return cp;} }
 public void Display(IList<string> options,string status,IntPtr target) {
  SuspendLayout();while(Controls.Count>0)Controls[0].Dispose();
  const int width=560;int y=10;
  string title=options==null || options.Count==0 ? (status ?? "Fixing what you typed…") : "TypeFix  ·  Pick 1–"+options.Count+"  ·  Esc to cancel";
  Controls.Add(new Label {Text=title,AutoSize=false,Location=new Point(14,y),Size=new Size(width-28,20),Font=titleFont,ForeColor=Color.FromArgb(185,194,209)});
  y+=26;
  if(options!=null)for(int i=0;i<options.Count;i++) {
   Size need=TextRenderer.MeasureText(options[i],textFont,new Size(width-70,1000),TextFormatFlags.WordBreak);
   var box=new Panel {Location=new Point(12,y),Size=new Size(width-24,need.Height+14),BackColor=Color.FromArgb(47,52,63)};
   box.Controls.Add(new Label {Text=(i+1).ToString(),Location=new Point(8,7),Size=new Size(24,need.Height),Font=numberFont,ForeColor=Color.FromArgb(118,183,255)});
   box.Controls.Add(new Label {Text=options[i],Location=new Point(36,7),Size=new Size(width-70,need.Height),Font=textFont});
   Controls.Add(box);y+=box.Height+6;
  }
  if(options!=null && options.Count>0 && options.Count<3)Controls.Add(new Label {Text="More readings coming…",AutoSize=false,Location=new Point(14,y),Size=new Size(width-28,18),Font=titleFont,ForeColor=Color.FromArgb(140,150,165)});
  ClientSize=new Size(width,y+(options!=null && options.Count>0 && options.Count<3 ? 26 : 6));
  Rectangle area=Screen.FromHandle(target).WorkingArea;Point? caretPoint=null;
  Native.RECT targetRect;Rectangle anchor=Native.GetWindowRect(target,out targetRect) ? Rectangle.FromLTRB(targetRect.Left,targetRect.Top,targetRect.Right,targetRect.Bottom) : area;
  Native.GUITHREADINFO info=new Native.GUITHREADINFO();info.cbSize=(uint)Marshal.SizeOf(typeof(Native.GUITHREADINFO));
  if(Native.GetGUIThreadInfo(Native.GetWindowThreadProcessId(target,IntPtr.Zero),ref info) && info.hwndCaret!=IntPtr.Zero) {
   Native.POINT caret=new Native.POINT {x=info.rcCaret.Left,y=info.rcCaret.Bottom+10};
   if(Native.ClientToScreen(info.hwndCaret,ref caret))caretPoint=new Point(caret.x,caret.y);
  }
  Bounds=AccentPlacement.Place(Size,area,anchor,caretPoint);
  ResumeLayout(true);
  if(target!=IntPtr.Zero)Native.SetWindowLongPtr(Handle,-8,target);
  Native.ShowWindow(Handle,4);
  Native.SetWindowPos(Handle,new IntPtr(-1),Left,Top,Width,Height,0x10|0x40);
  Refresh();
 }
 public void HideMenu() { if(!IsHandleCreated)return;Native.ShowWindow(Handle,0);Native.SetWindowLongPtr(Handle,-8,IntPtr.Zero); }
 protected override void Dispose(bool disposing) {base.Dispose(disposing);if(disposing){titleFont.Dispose();textFont.Dispose();numberFont.Dispose();}}
}

sealed class AccentContext : ApplicationContext {
 readonly AccentEngine engine=new AccentEngine();readonly StickyEngine sticky=new StickyEngine();readonly AccentPopup popup=new AccentPopup();readonly Control dispatcher=new Control();
 readonly Stopwatch clock=Stopwatch.StartNew();readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
 readonly NotifyIcon tray=new NotifyIcon();readonly Native.Hook keyCb,mouseCb;readonly Native.WinEvent focusCb;
 IntPtr keyHook,mouseHook,focusHook;
 // TypeFix (all touched only on this UI thread: the hook runs on it too).
 readonly TypingBuffer typed=new TypingBuffer();readonly RedKeyTaps red=new RedKeyTaps();readonly TypeFixService fix=new TypeFixService();readonly TypeFixPopup fixPopup=new TypeFixPopup();
 readonly HashSet<int> fixSwallowUps=new HashSet<int>();
 bool fixActive;int fixId;IntPtr fixTarget,lastForeground;string fixText;List<string> fixOptions=new List<string>();
 public AccentContext() {
  // Keep dispatch independent of the popup's current owner closing its window.
  IntPtr window=dispatcher.Handle;
  engine.Show=delegate(string s,string[] c,IntPtr h) { dispatcher.BeginInvoke((Action)delegate {if(engine.Active)popup.Display(s,c,h);}); };
  engine.Hide=delegate {dispatcher.BeginInvoke((Action)delegate {popup.HidePicker();});};
  engine.Insert=delegate(string s,IntPtr h) {typed.ReplaceLast(s);dispatcher.BeginInvoke((Action)delegate {Native.ReplaceLetter(s,h);});};
  red.FlushTab=delegate {typed.Reset();dispatcher.BeginInvoke((Action)delegate {Native.Tap(0x09);});};
  if(fix.Configured) { var warm=new Thread(delegate() {fix.LoadHints();fix.EnsureStarted();}) {IsBackground=true,Priority=ThreadPriority.BelowNormal};warm.Start(); }
  // Key-ups go out after the hook returns, so the ordinary key's own release comes first.
  sticky.Release=delegate(int[] vks) {dispatcher.BeginInvoke((Action)delegate {Native.KeyUps(vks);});};
  keyCb=OnKey;mouseCb=OnMouse;focusCb=delegate {engine.Cancel();};
  keyHook=Native.SetWindowsHookEx(13,keyCb,Native.GetModuleHandle(null),0);
  mouseHook=Native.SetWindowsHookEx(14,mouseCb,Native.GetModuleHandle(null),0);
  focusHook=Native.SetWinEventHook(3,3,IntPtr.Zero,focusCb,0,0,0);
  if(keyHook==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
  timer.Interval=30;timer.Tick+=delegate {
   long now=clock.ElapsedMilliseconds;IntPtr fg=Native.GetForegroundWindow();
   sticky.Tick(now);red.Tick(now);engine.Tick(now,fg,Native.Blocked());
   if(fg!=lastForeground) { lastForeground=fg;typed.Reset();if(fixActive && fg!=fixTarget)CancelFix(); }
  };timer.Start();
  var menu=new ContextMenuStrip();var pause=new ToolStripMenuItem("Pause accent picker") {CheckOnClick=true};
  pause.CheckedChanged+=delegate {engine.Enabled=!pause.Checked;engine.Cancel();};menu.Items.Add(pause);
  menu.Items.Add("Exit accent picker",null,delegate {ExitThread();});
  tray.Icon=Logo();tray.Text="Clicks: hold a letter or number, then pick 1–9";tray.ContextMenuStrip=menu;tray.Visible=true;
 }
 [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr handle);
 // The 3£ butterfly logo (Shared/Brand/make-icons.py writes this 32px PNG).
 const string LogoPng=/*brand:logo*/"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";
 static Icon Logo() {
  using(var stream=new System.IO.MemoryStream(Convert.FromBase64String(LogoPng)))
  using(var bitmap=new Bitmap(stream)) {
   var handle=bitmap.GetHicon();
   try {using(var borrowed=Icon.FromHandle(handle))return (Icon)borrowed.Clone();} finally {DestroyIcon(handle);}
  }
 }
 IntPtr OnKey(int code,IntPtr wp,IntPtr lp) {
  try {if(code>=0) {
   Native.KEY key=(Native.KEY)Marshal.PtrToStructure(lp,typeof(Native.KEY));
   bool down=wp.ToInt64()==0x100 || wp.ToInt64()==0x104;
   bool capital=(Native.GetAsyncKeyState(0x10)<0)^((Native.GetKeyState(0x14)&1)!=0);
   ulong tag=key.extra.ToUInt64();int vk=(int)key.vk;long now=clock.ElapsedMilliseconds;IntPtr fg=Native.GetForegroundWindow();
   if(tag!=AccentEngine.OutputTag) {
    if(FixKey(vk,down,fg))return new IntPtr(1);
    if(tag==AccentEngine.ClicksTag && vk==0x09 && fix.Configured) {
     if(sticky.Stickies.Count==0 && !Native.AnyModifierHeld() && !Native.InGame(fg)) {
      var act=red.Key(down,now);
      if(act==RedKeyTaps.Act.Trigger) { StartFix(fg);return new IntPtr(1); }
      if(act==RedKeyTaps.Act.Swallow)return new IntPtr(1);
     } else red.Cancel();
    }
   }
   if(tag==AccentEngine.ClicksTag && sticky.Key(vk,down,now))return new IntPtr(1);
   if(engine.Key(vk,down,tag,now,fg,Native.Blocked(),capital))return new IntPtr(1);
   if(down && tag!=AccentEngine.OutputTag)typed.Key(vk,Native.CharsFor(key.vk,key.scan,fg),Native.ShortcutHeld());
  }} catch {engine.Cancel();sticky.ReleaseAll();CancelFix();typed.Reset();} // fail open: a UI error must never disable ordinary typing
  return Native.CallNextHookEx(keyHook,code,wp,lp);
 }
 // Keys while the TypeFix menu is open: 1-3 pick, Esc cancels, anything else closes it and types.
 bool FixKey(int vk,bool down,IntPtr fg) {
  if(!down)return fixSwallowUps.Remove(vk);
  if(!fixActive)return false;
  if(fg!=fixTarget) { CancelFix();return false; }
  int index=vk>=0x31 && vk<=0x33 ? vk-0x31 : (vk>=0x61 && vk<=0x63 ? vk-0x61 : -1);
  if(index>=0 && !Native.AnyModifierHeld()) {
   fixSwallowUps.Add(vk);
   if(index<fixOptions.Count) {
    string chosen=TypingBuffer.WithTrailingSpace(fixText,fixOptions[index]);int backspaces=TypingBuffer.Backspaces(fixText);IntPtr target=fixTarget;
    CancelFix();typed.ReplaceParagraph(chosen);
    dispatcher.BeginInvoke((Action)delegate {Native.ReplaceText(backspaces,chosen,target);});
   }
   return true;  // a reading that is still being written: wait for it
  }
  if(vk==0x1B) { fixSwallowUps.Add(vk);CancelFix();return true; }
  if(vk==0x10 || vk==0x11 || vk==0x12 || (vk>=0xA0 && vk<=0xA5))return false;
  CancelFix();
  return false;
 }
 void StartFix(IntPtr target) {
  CancelFix();
  string text=typed.Paragraph();
  fixActive=true;fixTarget=target;fixText=text;fixOptions=new List<string>();int id=++fixId;
  if(text.Trim().Length==0) { fixPopup.Display(null,"Nothing typed here yet to fix. Type, then double-tap the red key.",target);return; }
  fixPopup.Display(null,null,target);
  var worker=new Thread(delegate() {
   fix.Fix(text,delegate {return id!=fixId || !fixActive;},delegate(List<string> options,string status) {
    dispatcher.BeginInvoke((Action)delegate {
     if(id!=fixId || !fixActive)return;
     if(options!=null)fixOptions=options;
     fixPopup.Display(fixOptions,status,fixTarget);
    });
   });
  }) {IsBackground=true};
  worker.Start();
 }
 void CancelFix() { if(!fixActive)return;fixActive=false;fixId++;fixOptions=new List<string>();fixPopup.HideMenu(); }
 IntPtr OnMouse(int code,IntPtr wp,IntPtr lp) {
  long msg=wp.ToInt64();if(code>=0 && (msg==0x201||msg==0x204||msg==0x207||msg==0x20A||msg==0x20B||msg==0x20E)) {engine.Cancel();if(msg!=0x20A && msg!=0x20E) {typed.Reset();CancelFix();}}  // a click can move the caret; scrolling cannot
  return Native.CallNextHookEx(mouseHook,code,wp,lp);
 }
 protected override void ExitThreadCore() {timer.Stop();if(keyHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(keyHook);if(mouseHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(mouseHook);if(focusHook!=IntPtr.Zero)Native.UnhookWinEvent(focusHook);tray.Dispose();popup.Dispose();fixPopup.Dispose();dispatcher.Dispose();base.ExitThreadCore();}
}

static class AccentProgram {
 [STAThread] public static void Main(string[] args) {
  bool first;using(var mutex=new Mutex(true,"Local\\3EWindows.ClicksAccents",out first)) {
   if(!first)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   Application.Run(new AccentContext());
  }
 }
}
