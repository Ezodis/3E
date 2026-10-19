// Auto-reload after the computer updates: the page reloads once when the
// receiver it reconnects to serves a different build, only when it is safe.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const idle=()=>new Promise(resolve=>setImmediate(resolve));
let checks=0;const check=(value,label)=>{assert.ok(value,label);checks++;};

function page({watch=false,build='aaaa',storage=new Map()}={}){
  const elements=new Map(),timers=new Map(),sent=[];let time=1000,clock=1_000_000,nextTimer=0,ws=null,reloads=0,hostBuild=build;
  const element=id=>{if(!elements.has(id))elements.set(id,{id,value:'3',handlers:{},disabled:true,hidden:true,textContent:'',classList:{add(){},remove(){},toggle(){}},addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(){}});return elements.get(id);};
  const doc={hidden:false,handlers:{},activeElement:null,documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
  const dock={held:false},surface={held:false};
  const win={innerWidth:390,handlers:{},ThreeEHost:{platform:'windows',build},matchMedia(){return{matches:watch};},addEventListener(type,fn){this.handlers[type]=fn;},
    ThreeEDock:{busy:()=>dock.held,commands(){},overviewEnded(){},describe(){}},ThreeESurface:{busy:()=>surface.held,cancel(){},state(){},describe(){}}};
  class Socket{static OPEN=1;constructor(){ws=this;this.readyState=1;this.bufferedAmount=0;}send(text){sent.push(JSON.parse(text));}close(){this.readyState=3;this.onclose?.();}}
  const sessionStorage={getItem:key=>storage.has(key)?storage.get(key):null,setItem:(key,value)=>storage.set(key,String(value))};
  vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,AbortController,
    location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834',search:'',reload(){reloads++;}},WebSocket:Socket,sessionStorage,
    localStorage:{getItem(){return null;},setItem(){}},performance:{now:()=>time},Date:{now:()=>clock},requestAnimationFrame(){},
    setInterval(){return 0;},clearInterval(){},setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);},
    async fetch(url,options){const payload=JSON.parse(options.body);sent.push(payload);
      return {ok:true,status:200,json:async()=>payload.type==='connect'?{ready:true,build:hostBuild,host:{platform:'windows'}}:{ready:true}};}});
  const p={sent,storage,dock,surface,doc,element,win,
    get reloads(){return reloads;},
    advance(ms){time+=ms;clock+=ms;},
    // Run every pending timer once per step; enough to model polling.
    run(steps=1){for(let i=0;i<steps;i++){time+=400;clock+=400;const due=[...timers.entries()];for(const [id,t] of due){timers.delete(id);t.fn();}}},
    status:()=>element('status').textContent,
    // A receiver restart: the socket drops, the page reconnects, the new receiver reports its build.
    async restart(next){hostBuild=next;if(watch){win.handlers.offline();p.run();await idle();await idle();return;}
      ws.close();p.run();ws.onopen();ws.onmessage({data:JSON.stringify({ready:true,build:next,host:{platform:'windows'}})});},
    touch(type,n){element('pad').handlers[type]({touches:Array.from({length:n},(_,i)=>({clientX:100+i*20,clientY:200})),preventDefault(){}});time+=15;}
  };
  return p;
}

(async()=>{
  {// Phone (WebSocket): a different build reloads exactly once, after releasing input.
    const p=page();p.restart('aaaa');p.run(3);
    check(p.reloads===0,'the same build never reloads');
    await p.restart('bbbb');
    check(p.status()==='Updating…','a new build shows Updating… before reloading');
    check(p.sent.some(c=>c.type==='releaseAll'),'releaseAll is sent before reloading');
    p.run();check(p.reloads===1,'the page reloads once after a short pause');
    check(JSON.parse(p.storage.get('3e-update')).build==='bbbb','the attempted build is remembered for this tab');
    p.run(5);check(p.reloads===1,'it reloads only once');
    // The reloaded page somehow still has the old build (a cached copy): never loop.
    const again=page({storage:p.storage});again.run(100);await again.restart('bbbb');again.run(5);
    check(again.reloads===0&&again.status()==='Connected','a build already attempted in this tab is never reloaded again');
  }
  {// Never twice within 30 s, even for a newer build; it reloads once the gap passes.
    const storage=new Map([['3e-update',JSON.stringify({build:'old',at:1_000_000})]]);
    const p=page({storage});await p.restart('cccc');p.run(10);
    check(p.reloads===0,'a second update within 30 s waits');
    p.run(75);check(p.reloads===1,'it reloads once 30 s have passed');
  }
  {// Deferred while a touch, a drag, the keyboard, the clipboard sheet or a dock/MIDI control is in use.
    for(const [label,hold,free] of [
      ['a finger on the pad',p=>p.touch('touchstart',1),p=>p.touch('touchend',0)],
      ['a three-finger drag',p=>{p.touch('touchstart',3);p.advance(150);p.touch('touchmove',3);},p=>p.touch('touchend',0)],
      ['the keyboard',p=>{p.doc.activeElement=p.element('typeSink');},p=>{p.doc.activeElement=null;}],
      ['the clipboard sheet',p=>{p.element('clipSheet').hidden=false;},p=>{p.element('clipSheet').hidden=true;}],
      ['the app switcher or volume slider',p=>{p.dock.held=true;},p=>{p.dock.held=false;}],
      ['a MIDI note or the studio',p=>{p.surface.held=true;},p=>{p.surface.held=false;}],
    ]){
      const p=page();p.run();hold(p);await p.restart('dddd');p.run(10);
      check(p.reloads===0&&p.status()==='Connected','no reload while '+label+' is in use');
      free(p);p.run(3);check(p.reloads===1,'reloads once '+label+' is released');
    }
  }
  {// A receiver without build ids (older version) or a page without one never reloads.
    const p=page({build:null});await p.restart('eeee');p.run(10);check(p.reloads===0,'a page that predates build ids never reloads');
  }
  {// Apple Watch (HTTP /control): the connect reply carries the build.
    const p=page({watch:true});await idle();await idle();
    check(p.sent[0].type==='connect'&&p.reloads===0,'the watch connects over HTTP');
    await p.restart('ffff');p.run();await idle();await idle();p.run(3);await idle();
    check(p.sent.some(c=>c.type==='commands'&&c.commands.some(x=>x.type==='releaseAll')),'the watch releases input before reloading');
    check(p.reloads===1,'the watch reloads once after the computer updates');
  }
  console.log('PASS: '+checks+' update auto-reload checks.');
})().catch(error=>{console.error(error);process.exitCode=1;});
