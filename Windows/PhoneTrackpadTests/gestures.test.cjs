const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const elements=new Map(),sent=[],pings=[],timers=new Map();let time=1000,frame,ws,heartbeat,checks=0,nextTimer=0;
function element(id){if(!elements.has(id))elements.set(id,{value:'3',handlers:{},disabled:true,hidden:true,classList:{add(){},remove(){},toggle(){}},addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(){}});return elements.get(id);}
const doc={hidden:false,handlers:{},documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
const win={innerWidth:390,handlers:{},matchMedia(){return{matches:false};},addEventListener(type,fn){this.handlers[type]=fn;}};
class Socket{static OPEN=1;constructor(){ws=this;this.readyState=1;this.bufferedAmount=0;}send(text){const command=JSON.parse(text);(command.type==='ping'?pings:sent).push(command);}close(){this.readyState=3;this.onclose?.();}}
vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834',search:''},WebSocket:Socket,localStorage:{getItem(){return null;},setItem(){}},performance:{now:()=>time},requestAnimationFrame(fn){frame=fn;},setInterval(fn){heartbeat=fn;return 1;},clearInterval(){},setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}});
function connected(){ws.onopen();ws.onmessage({data:'{"ready":true}'});sent.length=0;}connected();
const touch=(x,y)=>({clientX:x,clientY:y}),fingers=(n,x,y)=>Array.from({length:n},(_,i)=>touch(x+i*20,y));
function fire(type,touches){element('pad').handlers[type]({touches,preventDefault(){}});time+=15;}
function expect(commands,label){assert.deepEqual(sent.splice(0),commands,label);checks++;time+=700;}
function timer(ms){const t=[...timers.entries()].find(([,t])=>t.ms===ms);assert.ok(t,'timer '+ms);timers.delete(t[0]);t[1].fn();}
function tap(x=10,y=10){fire('touchstart',[touch(x,y)]);fire('touchend',[]);}
// Tap, then hold the second contact: the hold timer starts a tap-drag.
function begin(){tap();fire('touchstart',[touch(10,10)]);timer(300);}
tap();expect([{type:'left'}],'single tap');
fire('touchstart',fingers(2,10,10));fire('touchend',[]);expect([{type:'right'}],'two-finger tap');
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);assert.deepEqual(sent,[{type:'move',x:60,y:30}],'first movement does not wait for animation frame');frame();fire('touchend',[]);expect([{type:'move',x:60,y:30}],'relative movement');
fire('touchstart',fingers(2,10,10));fire('touchmove',fingers(2,30,30));fire('touchend',[]);expect([{type:'scroll',x:60,y:-60}],'reversed scroll on both axes');
tap();tap();expect([{type:'left'},{type:'left'}],'quick double tap sends two clicks (a native double-click), never a press');
tap();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(14,10)]);fire('touchend',[]);expect([{type:'left'},{type:'left'}],'small jitter during the second tap is still a double-click');
tap();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,12)]);assert.deepEqual(sent,[{type:'left'},{type:'dragStart',x:1,y:0},{type:'move',x:60,y:6}],'moving the second contact starts a drag at once with all its motion');fire('touchend',[]);timer(120);expect([{type:'left'},{type:'dragStart',x:1,y:0},{type:'move',x:60,y:6},{type:'up'}],'tap-drag drops on lift');checks++;
tap();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(10,40)]);fire('touchend',[]);timer(120);expect([{type:'left'},{type:'dragStart',x:0,y:1},{type:'move',x:0,y:90},{type:'up'}],'vertical tap-drag reports its direction');
begin();assert.deepEqual(sent,[{type:'left'},{type:'dragStart',x:0,y:0}],'holding the second contact starts a drag');fire('touchmove',[touch(11,10)]);fire('touchmove',[touch(30,20)]);fire('touchend',[]);assert.ok(!sent.some(c=>c.type==='up'),'brief contact loss keeps drag');timer(120);expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'move',x:3,y:0},{type:'move',x:57,y:30},{type:'up'}],'double-tap drag releases after contact grace');
begin();fire('touchmove',[touch(30,10)]);fire('touchend',[]);time+=50;fire('touchstart',[touch(100,100)]);fire('touchmove',[touch(110,100)]);fire('touchend',[]);timer(120);expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'move',x:60,y:0},{type:'move',x:30,y:0},{type:'up'}],'contact break continues one drag without another click');
tap();time+=600;fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:60,y:30}],'late second contact moves normally');
tap();fire('touchstart',[touch(100,100)]);fire('touchmove',[touch(120,110)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:60,y:30}],'distant touch does not start a drag');
fire('touchstart',fingers(3,10,10));time+=120;fire('touchmove',fingers(3,30,10));fire('touchend',fingers(2,30,10));fire('touchmove',fingers(2,50,30));fire('touchend',[]);expect([{type:'down'},{type:'move',x:60,y:0},{type:'up'}],'three-finger drag remains isolated');
fire('touchstart',fingers(3,10,10));fire('touchend',[]);expect([],'three-finger tap never clicks');
for(let n=1;n<=4;n++)fire('touchstart',fingers(n,10,100));fire('touchmove',fingers(4,10,40));fire('touchmove',fingers(4,10,-40));fire('touchend',fingers(3,10,0));fire('touchmove',fingers(3,50,30));fire('touchend',[]);expect([{type:'taskView'}],'four up fires once without drag');
fire('touchstart',fingers(4,10,10));fire('touchmove',fingers(4,10,70));fire('touchend',[]);expect([{type:'showDesktop'}],'four down');
fire('touchstart',fingers(4,10,10));fire('touchmove',fingers(4,80,20));fire('touchmove',fingers(4,140,20));fire('touchend',[]);expect([{type:'desktop',direction:-1}],'four right goes to previous desktop once');
fire('touchstart',fingers(4,100,10));fire('touchmove',fingers(4,20,10));fire('touchend',[]);expect([{type:'desktop',direction:1}],'four left goes to next desktop');
fire('touchstart',fingers(5,10,10));fire('touchmove',fingers(5,10,90));fire('touchend',[]);expect([],'five contacts ignored');
element('speed').value='20';begin();fire('touchmove',[touch(210,10)]);fire('touchend',[]);timer(120);expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'move',x:4000,y:0},{type:'up'}],'20x motion uses one packet');element('speed').value='3';
begin();fire('touchcancel',[]);expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'up'},{type:'releaseAll'}],'cancel immediately releases all held controls');
begin();element('settings').handlers.click();expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'up'},{type:'releaseAll'}],'settings release dragging');element('closeSettings').handlers.click();
begin();doc.hidden=true;doc.handlers.visibilitychange();expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'releaseAll'}],'backgrounding releases all controls');assert.equal(ws.readyState,3);
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);fire('touchend',[]);expect([],'sleeping touches do not replay');
doc.hidden=false;doc.handlers.visibilitychange();connected();element('connect').handlers.click();assert.equal(ws.readyState,3);checks++;doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;doc.handlers.visibilitychange();assert.equal(ws.readyState,3);checks++;
element('connect').handlers.click();connected();element('tongueMode').handlers.click();fire('touchstart',[touch(10,10)]);time+=500;fire('touchend',[]);expect([{type:'left'}],'tongue mode accepts slower taps');
fire('touchstart',[touch(10,10)]);time+=800;timer(800);fire('touchend',[]);expect([{type:'right'}],'hold right-clicks once');
element('scrollMode').handlers.click();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,30)]);fire('touchend',[]);expect([{type:'scroll',x:60,y:-60}],'one contact scrolls');element('scrollMode').handlers.click();
begin();win.handlers.resize();assert.deepEqual(sent,[{type:'left'},{type:'dragStart',x:0,y:0}],'Safari chrome height changes must not release a drag');checks++;win.innerWidth=844;win.handlers.resize();expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'up'},{type:'releaseAll'}],'rotation releases all controls');
fire('touchstart',[touch(10,10)]);ws.bufferedAmount=600;fire('touchmove',[touch(20,10)]);fire('touchmove',[touch(30,10)]);frame();assert.deepEqual(sent,[],'brief backpressure keeps unsent motion out of the socket');assert.equal(ws.readyState,1);ws.bufferedAmount=0;frame();fire('touchend',[]);expect([{type:'move',x:60,y:0}],'coalesced motion resumes without a reconnect or a backlog of old packets');
begin();ws.bufferedAmount=600;fire('touchmove',[touch(30,10)]);fire('touchend',[]);timer(120);ws.bufferedAmount=0;expect([{type:'left'},{type:'dragStart',x:0,y:0},{type:'move',x:60,y:0},{type:'up'}],'backpressure preserves motion before a drag release');
const failed=ws;ws.close();timer(250);assert.notEqual(ws,failed);connected();checks++;time+=1500;pings.length=0;heartbeat();assert.deepEqual(pings.splice(0),[{type:'ping'}]);ws.onmessage({data:'{"pong":true}'});time+=1500;heartbeat();assert.equal(ws.readyState,1);sent.length=0;checks++;
time+=5000;heartbeat();assert.equal(ws.readyState,3);timer(250);connected();checks++;doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;win.handlers.pageshow();const waking=ws;win.handlers.focus();doc.handlers.visibilitychange();assert.equal(ws,waking);connected();checks++;
sent.length=0;time+=2000;pings.length=0;fire('touchstart',[touch(10,10)]);assert.equal(pings.length,1,'a touch after a pause sends one wake packet');fire('touchend',[]);sent.length=0;checks++;
doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;doc.handlers.visibilitychange();const reconnecting=ws;
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);fire('touchend',[]);fire('touchstart',[touch(50,50)]);fire('touchend',[]);
reconnecting.onopen();sent.length=0;assert.equal(ws,reconnecting);reconnecting.onmessage({data:'{"ready":true}'});expect([{type:'move',x:60,y:0},{type:'left'}],'motion and a tap made while waking are delivered on connect');
ws.onmessage({data:'{"error":"pairing"}'});assert.equal(element('connect').textContent,'Connect');assert.ok(![...timers.values()].some(t=>t.ms===250));checks++;console.log('PASS: '+checks+' shared gesture and connection checks.');
