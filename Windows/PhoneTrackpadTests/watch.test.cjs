const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const elements = new Map(), requests = [], timers = new Map();
let frame, time=1000, timerId=0, failNext=false, replaceNext=false, waitCommands=false, finishCommand;
const idle = () => new Promise(resolve => setImmediate(resolve));
function element(id) {
  if (!elements.has(id)) elements.set(id,{value:'3',handlers:{},disabled:true,
    classList:{add(){},remove(){},toggle(){}},setAttribute(){},addEventListener(type,fn){this.handlers[type]=fn;}});
  return elements.get(id);
}
const doc={hidden:false,handlers:{},documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
const win={handlers:{},matchMedia(){return {matches:true};},addEventListener(type,fn){this.handlers[type]=fn;}};
var prefsRequests=0;
vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,AbortController,
  location:{protocol:'http:',host:'127.0.0.1:17834',search:'',hash:'#'+'A'.repeat(48)},
  localStorage:{getItem(key){return key==='3e-acceleration'?'false':null;},setItem(){}},performance:{now:()=>time},requestAnimationFrame(fn){frame=fn;},
  setInterval(fn,ms){const id=++timerId;timers.set(id,{fn,ms});return id;},clearInterval(id){timers.delete(id);},
  setTimeout(fn,ms){const id=++timerId;timers.set(id,{fn,ms,once:true});return id;},clearTimeout(id){timers.delete(id);},
  async fetch(url,options){
    // Settings sync is separate from the control channel under test.
    if(url==='/prefs'){prefsRequests++;return {ok:true,status:200,json:async()=>({prefs:{acceleration:false}})};}
    const payload=JSON.parse(options.body);requests.push({url,options,payload});
    if(failNext){failNext=false;return {ok:false,status:409};}
    if(replaceNext&&payload.type!=='disconnect'){replaceNext=false;return {ok:false,status:403,json:async()=>({ready:false,error:'replaced'})};}
    if(waitCommands&&payload.type==='commands'){waitCommands=false;await new Promise(resolve=>finishCommand=resolve);}
    return {ok:true,status:200};
  }
});
const touch=(x,y)=>({clientX:x,clientY:y});
function fire(type,touches){element('pad').handlers[type]({touches,preventDefault(){}});time+=15;}
async function pump(){await idle();await idle();}
function commands(){return requests.filter(r=>r.payload.type==='commands').flatMap(r=>r.payload.commands).filter(c=>c.type!=='ping');}
(async()=>{
  await idle();
  assert.equal(requests[0].payload.type,'connect');
  assert.equal(requests[0].payload.takeover,true,'opening the watch page takes control');
  assert.ok(prefsRequests>=1,'the page loads its saved settings from the computer once connected');
  assert.match(requests[0].payload.client,/^[a-f0-9]{32}$/);
  assert.equal(requests[0].options.headers['X-Trackpad-Token'],'A'.repeat(48));
  assert.equal(requests[0].options.referrerPolicy,'same-origin');
  assert.equal(element('apps').disabled,false);
  fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);frame();fire('touchend',[]);
  time+=600;element('pad').handlers.click();await pump();
  assert.deepEqual(commands(),[{type:'move',x:60,y:30},{type:'left'}]);
  requests.length=0;
  element('scrollMode').handlers.click();
  fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,30)]);frame();fire('touchend',[]);
  fire('touchstart',[touch(10,10)]);fire('touchend',[]);
  element('stepDown').handlers.click();await pump();
  assert.deepEqual(commands(),[{type:'scroll',x:60,y:-60},{type:'scroll',x:0,y:-120}]);
  requests.length=0;
  element('scrollMode').handlers.click();element('stepRight').handlers.click();win.ThreeEControl.send('down');await pump();
  assert.deepEqual(commands(),[{type:'move',x:24,y:0},{type:'down'}]);
  waitCommands=true;element('stepRight').handlers.click();
  time+=600;element('pad').handlers.click(); // Queued input must disappear when the watch sleeps.
  doc.hidden=true;doc.handlers.visibilitychange();await idle();
  assert.equal(requests.at(-1).payload.type,'disconnect');
  assert.equal(element('apps').disabled,true);
  finishCommand();await pump();assert.equal(timers.size,0);
  assert.ok(!commands().some(c=>c.type==='left'));
  const previousClient=requests.at(-1).payload.client;
  doc.hidden=false;doc.handlers.visibilitychange();await idle();
  assert.equal(requests.at(-1).payload.type,'connect');
  assert.equal(requests.at(-1).payload.client,previousClient,'wake reuses the page identity to reclaim its lease');
  assert.equal(requests.at(-1).payload.takeover,false,'waking only resumes; it never takes control from a newer device');
  const before=requests.length;
  element('connect').handlers.click();await idle();
  assert.equal(element('apps').disabled,true);
  doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;doc.handlers.visibilitychange();await idle();
  assert.equal(element('apps').disabled,true,'explicit pause does not auto-resume');
  element('connect').handlers.click();await idle();
  assert.deepEqual(requests.slice(before).map(r=>r.payload.type),['disconnect','connect']);
  failNext=true;time+=600;element('pad').handlers.click();await pump();
  assert.equal(element('apps').disabled,true);
  assert.match(element('status').textContent,/reconnecting/);
  const retry=[...timers.entries()].find(([,t])=>t.once&&t.ms===250);assert.ok(retry);
  timers.delete(retry[0]);retry[1].fn();await pump();
  assert.equal(element('apps').disabled,false,'transient failure reconnects without reloading');
  replaceNext=true;time+=600;element('pad').handlers.click();await pump();
  assert.match(element('status').textContent,/Another device took control/);
  assert.equal(element('apps').disabled,true);
  assert.ok(![...timers.values()].some(t=>t.once&&t.ms<=2500),'a replaced watch stops reconnecting');
  element('connect').handlers.click();await pump();
  assert.equal(requests.at(-1).payload.type,'connect');assert.equal(requests.at(-1).payload.takeover,true,'tapping Connect takes control back');
  assert.equal(element('apps').disabled,false);
  console.log('PASS: normal-link watch detection, HTTP-only connection, pad click fallback, ordered batches, scrolling, arrows, sleep release, discarded input, pause/reconnect, conflict recovery and newest-device handoff.');
})().catch(error=>{console.error(error);process.exitCode=1;});
