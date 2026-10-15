using System;
public static class AccentTests {
 static IntPtr window=new IntPtr(123);
 static int shown,hidden;static string inserted;
 static AccentEngine New() { shown=hidden=0;inserted=null;return new AccentEngine { Show=delegate{shown++;},Hide=delegate{hidden++;},Insert=delegate(string s,IntPtr p){inserted=s;} }; }
 static void Check(bool value,string message) {if(!value)throw new Exception(message);Console.WriteLine("PASS "+message);}
 static bool Key(AccentEngine e,int vk,bool down,int ms,bool upper=false,bool blocked=false,ulong tag=AccentEngine.ClicksTag) { return e.Key(vk,down,tag,ms,window,blocked,upper); }
 public static void Main() {
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
 }
}
