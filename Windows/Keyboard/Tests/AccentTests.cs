using System;
public static class AccentTests {
 static IntPtr window=new IntPtr(123);
 static int shown,hidden;static string inserted;
 static AccentEngine New() { shown=hidden=0;inserted=null;return new AccentEngine { Show=delegate{shown++;},Hide=delegate{hidden++;},Insert=delegate(string s,IntPtr p){inserted=s;} }; }
 static void Check(bool value,string message) {if(!value)throw new Exception(message);Console.WriteLine("PASS "+message);}
 static bool Key(AccentEngine e,int vk,bool down,int ms,bool upper=false,bool blocked=false,ulong tag=AccentEngine.ClicksTag) { return e.Key(vk,down,tag,ms,window,blocked,upper); }
 public static void Main(string[] args) {
  Check((AccentEngine.OutputTag&1)==0 && (AccentEngine.ClicksTag&1)==0,"tags never look like PowerToys Keyboard Manager's own output (bit 0)");
  var e=New();Check(!Key(e,65,true,0),"normal letter is immediate");Key(e,65,false,80);e.Tick(700,window,false);Check(shown==0,"quick tap has no picker");
  e=New();Key(e,65,true,0);Check(Key(e,65,true,300),"typematic is suppressed only for an eligible Clicks letter");e.Tick(650,window,false);Check(shown==1 && e.Active,"holding opens choices");Key(e,65,false,700);Check(e.Active,"release leaves picker available for one-handed choice");Check(Key(e,49,true,800) && inserted=="á","number 1 chooses acute a");Check(Key(e,49,false,850),"selection key-up is consumed");Check(!Key(e,49,true,900),"next number types normally");
  e=New();Key(e,78,true,0,true);e.Tick(700,window,false);Key(e,78,false,710);Key(e,49,true,800);Check(inserted=="Ñ","uppercase n accents");
  e=New();Key(e,69,true,0,false,true);e.Tick(700,window,true);Check(shown==0,"Ctrl Alt and Win shortcuts cannot open picker");
  e=New();Key(e,65,true,0, false,false,0);e.Tick(700,window,false);Check(shown==0 && !Key(e,49,true,800,false,false,0),"other keyboards pass through unchanged");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);Check(!Key(e,49,true,800,false,false,0)&&inserted==null&&!e.Active,"other keyboard cancels without swallowing its number");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);Check(Key(e,27,true,800)&&inserted==null&&!e.Active,"Escape cancels and retains original letter");Check(Key(e,65,true,900),"held-letter repeats stay suppressed after cancel");Key(e,65,false,1000);Check(!Key(e,65,true,1100),"new letter press works after cancel");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);e.Tick(6700,window,false);Check(!e.Active&&inserted==null,"picker expires after six seconds");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);e.Tick(720,new IntPtr(456),false);Check(!e.Active,"focus change cancels selection");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);Check(!Key(e,66,true,800)&&!e.Active,"ordinary key cancels and types normally");
  e=New();Check(!Key(e,81,true,0)&&!Key(e,81,true,300),"letters without accent choices retain repetition");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);Key(e,49,true,800);Check(Key(e,65,true,900),"held-letter repeat suppressed after selecting");
  e=New();Key(e,65,true,0);e.Tick(700,window,false);Check(!Key(e,8,true,800,false,false,AccentEngine.OutputTag)&&e.Active,"picker output cannot recursively trigger picker");
  for(int digit=0;digit<=9;digit++) {
   int vk=48+digit;e=New();Check(!Key(e,vk,true,0),"digit "+digit+" types immediately");Key(e,vk,false,70);e.Tick(700,window,false);Check(!e.Active,"quick digit "+digit+" has no menu");
   e=New();Key(e,vk,true,0);e.Tick(650,window,false);Check(e.Active && e.Choices.Length==9,"hold "+digit+" opens nine choices");Key(e,vk,false,700);Key(e,57,true,800);Check(inserted==AccentEngine.ChoicesByKey[vk][8],"digit "+digit+" selects its ninth option");
  }
  e=New();Key(e,49,true,0);Check(Key(e,49,true,400),"held digit repeat is suppressed");e.Tick(650,window,false);Check(Key(e,49,true,680)&&inserted==null,"held digit cannot select itself by auto-repeat");Key(e,49,false,700);Key(e,49,true,800);Check(inserted=="$","release and press same digit selects currency");Key(e,49,false,850);Check(!Key(e,50,true,900),"typing resumes normally after currency choice");
  e=New();Key(e,49,true,0);e.Tick(650,window,false);Key(e,49,false,700);Key(e,50,true,800);Check(inserted=="€","hold 1 then 2 selects euro");
  e=New();Key(e,48,true,0);e.Tick(650,window,false);Key(e,48,false,700);Key(e,49,true,800);Check(inserted=="🙂" && inserted.Length==2 && char.IsSurrogatePair(inserted,0),"emoji retains the complete UTF-16 surrogate pair");
  e=New();Key(e,48,true,0);e.Tick(650,window,false);Key(e,48,false,700);Key(e,51,true,800);Check(inserted=="❤️","emoji variation selector is preserved");
  e=New();Key(e,49,true,0,true);e.Tick(650,window,false);Key(e,49,false,700);Key(e,50,true,800);Check(inserted=="€","Shift or Caps does not change symbol choices");
  e=New();Key(e,49,true,0,false,true);e.Tick(700,window,true);Check(!e.Active,"number shortcuts cannot open picker");
  e=New();Key(e,48,true,0,false,false,0);e.Tick(700,window,false);Check(!e.Active,"other keyboards do not open emoji menus");
  Check(AccentEngine.GameWindow("League of Legends (TM) Client","RiotWindowClass",false),"League game window blocks the picker");
  Check(AccentEngine.GameWindow("Some game","UnityWndClass",true),"full-screen windows block the picker");
  Check(!AccentEngine.GameWindow("Document - Word","OpusApp",false),"normal windows keep the picker");
  Check(!AccentEngine.GameWindow("","Progman",true),"the desktop keeps the picker");
  e=New();Key(e,78,true,0,false,true);e.Tick(700,window,true);Check(!e.Active,"held N in a game opens no picker");
  StickyTests();
  TypeFixTests(args.Length>0 ? args[0] : null);
 }
 static void TypeFixTests(string promptFile) {
  var b=new TypingBuffer();
  foreach(char c in "hola mundo")b.Key(c==' ' ? 0x20 : char.ToUpperInvariant(c),c.ToString(),false);
  Check(b.Paragraph()=="hola mundo","typed letters are remembered");
  b.Key(0x08,"",false);Check(b.Text=="hola mund","backspace removes one character");
  b.Key(0x0D,"",false);b.Key(0x41,"a",false);Check(b.Paragraph()=="a" && b.Text=="hola mund\na","Enter starts a new paragraph");
  b.Key(0x25,"",false);Check(b.Text=="","an arrow key forgets the text (the caret moved)");
  b.Key(0x41,"a",false);b.Key(0x43,"c",true);Check(b.Text=="","a shortcut forgets the text");
  b.Key(0x41,"e",false);b.ReplaceLast("é");Check(b.Text=="é","an accent pick replaces the last letter");
  b.Set("uno\ndos tres");b.ReplaceParagraph("Dos tres.");Check(b.Text=="uno\nDos tres.","a pick replaces only the current paragraph");
  Check(TypingBuffer.Backspaces("a😀b")==3,"emoji count as one backspace");
  Check(TypingBuffer.WithTrailingSpace("hola mundo  ","Hola, mundo.")=="Hola, mundo.  ","the reading keeps the trailing spaces");

  int tabs=0;var r=new RedKeyTaps {FlushTab=delegate{tabs++;}};
  Check(r.Key(true,0)==RedKeyTaps.Act.Swallow && r.Key(false,80)==RedKeyTaps.Act.Swallow,"red key tap waits");
  r.Tick(200);Check(tabs==0,"no Tab before the double-tap window ends");
  r.Tick(400);Check(tabs==1,"a single red tap sends Tab after 300 ms");
  r.Key(true,1000);r.Key(false,1080);Check(r.Key(true,1200)==RedKeyTaps.Act.Trigger && r.Key(false,1260)==RedKeyTaps.Act.Swallow && tabs==1,"double-tap opens TypeFix and types no Tab");
  r.Key(true,2000);Check(r.Key(true,2400)==RedKeyTaps.Act.Pass && tabs==2,"holding the red key repeats Tab");
  r.Key(false,2500);

  var o=new OptionStream();
  Check(!o.Add("{\"options\": [\"Hola, ¿qué tal?") && o.Options.Count==0,"a reading still being written is not shown");
  Check(o.Add("\", \"Ho") && o.Options.Count==1 && o.Options[0]=="Hola, ¿qué tal?","a finished reading appears at once");
  o.Add("la que tal\", \"say \\\"hi\\\"\\n\"]}");Check(o.Options.Count==3 && o.Options[2]=="say \"hi\"","escaped quotes and new lines decode");
  Check(JsonText.Content("{\"choices\":[{\"delta\":{\"content\":\"a\\u00e9\"}}]}")=="aé","streamed content decodes");
  Check(JsonText.Quote("a\"b\n")=="\"a\\\"b\\n\"","request text is escaped");
  string body=TypeFixPrompt.RequestBody("tyhe",new System.Collections.Generic.List<string>{"tyhe: the"});
  Check(body.Contains("\"stream\":true") && body.Contains("Keyboard hints") && body.Contains("\"enable_thinking\":false"),"request streams JSON readings with hints");

  var h=new KeyboardHints();
  foreach(string w in new[]{"typing","the","with","being","impossible","read","want","going","tipping","quiero","merci"})h.Add(w,1000);
  Check(h.Candidates("tyhikoloiunmg",1)[0]=="typing" || h.Candidates("tyhikoloiunmg",3).Contains("typing"),"neighbour-key mashing points to typing");
  Check(h.Candidates("wjth",1)[0]=="with","a neighbour substitution points to with");
  Check(h.Candidates("ikmpossib",1)[0]=="impossible","missing letters point to impossible");
  Check(h.Known("Quiero") && !h.Known("qwiero"),"known words need no hint");
  Check(KeyboardHints.Fold("Réunion")=="reunion","accents are folded for matching");
  var lines=h.Hints("the wjth quiero");Check(lines.Count==1 && lines[0].StartsWith("wjth: with"),"hints only for unknown chunks");
  if(promptFile!=null)
   Check(System.IO.File.ReadAllText(promptFile).Replace("\r\n","\n")==TypeFixPrompt.System.Replace("\r\n","\n"),"Windows uses the shared TypeFix prompt");
 }
 const int CMD=0xA3,SHIFT=0xA0,ALT=0xA5,N=0x4E,TAB=0x09,WIN=0x5B;
 static System.Collections.Generic.List<int> released=new System.Collections.Generic.List<int>();
 static StickyEngine Sticky() {released.Clear();return new StickyEngine {Release=delegate(int[] v){released.AddRange(v);}};}
 static bool Tap(StickyEngine s,int vk,long at) {s.Key(vk,true,at-60);return s.Key(vk,false,at);} // released at `at`
 static void StickyTests() {
  var s=Sticky();Check(Tap(s,CMD,0),"tapped Command stays down (its key-up is held back)");
  Check(s.Stickies.Count==1 && s.Deadline==7000,"first sticky opens a 7 second window");
  Tap(s,ALT,1000);Tap(s,SHIFT,2000);Check(s.Deadline==7000,"more stickies early in the window do not extend it");
  s.Key(N,true,3000);Check(released.Count==0,"stickies stay while N is down");
  s.Key(N,false,3060);Check(released.Count==3 && s.Stickies.Count==0,"Cmd+Alt+Shift+N: all three release after N");
  s=Sticky();Tap(s,CMD,0);Tap(s,SHIFT,5500);Check(s.Deadline==10000,"a sticky in the last 2 seconds adds 3 seconds");
  Tap(s,ALT,9000);Check(s.Deadline==13000,"and again in the extended window's last 2 seconds");
  s=Sticky();Tap(s,CMD,0);Tap(s,ALT,3000);s.Tick(6990);Check(released.Count==0,"stickies hold until the window ends");
  s.Tick(7000);Check(released.Count==2 && s.Stickies.Count==0,"window end releases every sticky: nothing stays stuck");
  s=Sticky();Tap(s,CMD,0);s.Key(TAB,true,500);s.Tick(8000);Check(released.Count==0,"a key still held keeps its stickies past the window");
  s.Key(TAB,false,8100);Check(released.Count==1,"Cmd+Tab releases Command right after Tab");
  s=Sticky();s.Key(CMD,true,0);s.Key(TAB,true,200);s.Key(TAB,false,260);Check(!s.Key(CMD,false,900) && s.Stickies.Count==0,"held Command is an ordinary modifier");
  s=Sticky();Tap(s,CMD,0);s.Key(WIN,true,300);Check(released.Count==1,"Windows key (dictation) releases stickies first");
  s=Sticky();Tap(s,SHIFT,0);s.Key(N,true,400);s.Key(N,false,460);s.Key(N,true,600);s.Key(N,false,660);Check(released.Count==1,"a sticky applies to one key only");
  s=Sticky();Tap(s,CMD,0);Tap(s,CMD,300);Check(s.Stickies.Count==1 && s.Deadline==7000,"tapping a sticky again keeps one sticky and the same window");
  s=Sticky();s.Key(CMD,true,0);s.Key(CMD,true,500);s.Key(CMD,true,530);Check(s.Key(CMD,false,600),"auto-repeat before release still counts as a tap");
 }
}
