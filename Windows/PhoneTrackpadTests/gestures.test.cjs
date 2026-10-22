const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const elements=new Map(),sent=[],pings=[],timers=new Map();let time=1000,frame,ws,heartbeat,checks=0,nextTimer=0;
function element(id){if(!elements.has(id))elements.set(id,{value:'3',handlers:{},disabled:true,hidden:true,classList:{add(){},remove(){},toggle(){}},addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(){}});return elements.get(id);}
const doc={hidden:false,handlers:{},documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
const win={innerWidth:390,handlers:{},matchMedia(){return{matches:false};},addEventListener(type,fn){this.handlers[type]=fn;}};
class Socket{static OPEN=1;constructor(){ws=this;this.readyState=1;this.bufferedAmount=0;}send(text){const command=JSON.parse(text);if(command.type==='move'){if(!Number.isFinite(command.t))throw new Error('move without phone timestamp');delete command.t;}(command.type==='ping'?pings:sent).push(command);}close(){this.readyState=3;this.onclose?.();}}
vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834',search:''},WebSocket:Socket,localStorage:{getItem(key){return key==='3e-acceleration'?'false':null;},setItem(){}},performance:{now:()=>time},requestAnimationFrame(fn){frame=fn;},setInterval(fn){heartbeat=fn;return 1;},clearInterval(){},setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}});
function connected(){ws.onopen();ws.onmessage({data:'{"ready":true}'});sent.length=0;}connected();
const touch=(x,y)=>({clientX:x,clientY:y}),fingers=(n,x,y)=>Array.from({length:n},(_,i)=>touch(x+i*20,y));
function fire(type,touches){element('pad').handlers[type]({touches,preventDefault(){}});time+=15;}
// A tap's click waits 300 ms for a possible second touch; let it land first.
function settleTap(){for(const [id,t] of [...timers])if(t.ms===300){timers.delete(id);t.fn();}}
function expect(commands,label){settleTap();assert.deepEqual(sent.splice(0),commands,label);checks++;time+=700;}
function timer(ms){const t=[...timers.entries()].find(([,t])=>t.ms===ms);assert.ok(t,'timer '+ms);timers.delete(t[0]);t[1].fn();}
function tap(x=10,y=10){fire('touchstart',[touch(x,y)]);fire('touchend',[]);}
// Tap, then hold the second contact: the hold timer starts a tap-drag.
// Tap, then touch again and hold: the drag arms without pressing anything.
function begin(){tap();fire('touchstart',[touch(10,10)]);timer(250);}
// Armed, then a small move: the press happens only now.
function grab(){begin();fire('touchmove',[touch(16,10)]);}
tap();expect([{type:'left'}],'single tap');
fire('touchstart',fingers(2,10,10));fire('touchend',[]);expect([{type:'right'}],'two-finger tap');
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);assert.deepEqual(sent,[{type:'move',x:51,y:25}],'first movement does not wait for animation frame');frame();fire('touchend',[]);expect([{type:'move',x:51,y:25}],'relative movement');
fire('touchstart',fingers(2,10,10));fire('touchmove',fingers(2,30,30));fire('touchend',[]);expect([{type:'scroll',x:60,y:-60}],'reversed scroll on both axes');
tap();tap();expect([{type:'left'},{type:'left'}],'quick double tap sends two clicks (a native double-click), never a press');
tap();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(14,10)]);fire('touchend',[]);expect([{type:'left'},{type:'left'}],'small jitter during the second tap is still a double-click');
tap();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,12)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:60,y:6}],'moving straight after a tap is a plain move and never presses');
tap();fire('touchstart',[touch(10,10)]);time+=200;fire('touchmove',[touch(30,12)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:60,y:6}],'a short pause before moving still never presses');
tap();fire('touchstart',[touch(10,10)]);for(const [x,y] of [[12,11],[9,12],[11,8],[8,10],[12,12],[10,9],[12,10],[9,11]])fire('touchmove',[touch(x,y)]);timer(250);fire('touchmove',[touch(40,12)]);fire('touchend',[]);timer(120);
assert.ok(sent.some(c=>c.type==='dragStart'),'a hold with natural finger jitter still arms the drag');expect(sent.slice(),'jittery hold-drag');
fire('touchstart',[touch(50,50)]);for(const [x,y] of [[52,51],[49,52],[51,48],[48,50],[52,52],[50,49]])fire('touchmove',[touch(x,y)]);fire('touchend',[]);settleTap();expect(sent.filter(c=>c.type!=='move').length===1&&sent.some(c=>c.type==='left')?sent.slice():[{type:'left'}],'a tap with finger jitter is still a click');
begin();assert.equal(sent.length,0,'arming sends nothing, not even the first tap\'s click');fire('touchend',[]);expect([{type:'left'}],'an armed drag lifted without moving cancels without clicking');
begin();fire('touchmove',[touch(10,40)]);fire('touchend',[]);timer(120);expect([{type:'dragStart',x:0,y:1},{type:'move',x:0,y:90},{type:'up'}],'vertical tap-drag reports its direction');
begin();assert.deepEqual(sent,[],'holding the second contact arms a drag without pressing or clicking');fire('touchmove',[touch(11,10)]);fire('touchmove',[touch(30,20)]);fire('touchend',[]);assert.ok(!sent.some(c=>c.type==='up'),'brief contact loss keeps drag');timer(120);expect([{type:'dragStart',x:1,y:0},{type:'move',x:60,y:30},{type:'up'}],'double-tap-hold-drag releases after contact grace');
begin();fire('touchmove',[touch(30,10)]);fire('touchend',[]);time+=50;fire('touchstart',[touch(100,100)]);fire('touchmove',[touch(110,100)]);fire('touchend',[]);timer(120);expect([{type:'dragStart',x:1,y:0},{type:'move',x:60,y:0},{type:'move',x:30,y:0},{type:'up'}],'contact break continues one drag without another click');
tap();time+=700;fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:51,y:25}],'late second contact moves normally');
tap();fire('touchstart',[touch(100,100)]);fire('touchmove',[touch(120,110)]);fire('touchend',[]);expect([{type:'left'},{type:'move',x:51,y:25}],'distant touch does not start a drag');
fire('touchstart',fingers(3,10,10));time+=120;fire('touchmove',fingers(3,30,10));fire('touchend',fingers(2,30,10));fire('touchmove',fingers(2,50,30));fire('touchend',[]);expect([{type:'down'},{type:'move',x:60,y:0},{type:'up'}],'three-finger drag remains isolated');
fire('touchstart',fingers(3,10,10));fire('touchend',[]);expect([],'three-finger tap never clicks');
for(let n=1;n<=4;n++)fire('touchstart',fingers(n,10,100));fire('touchmove',fingers(4,10,40));fire('touchmove',fingers(4,10,-40));fire('touchend',fingers(3,10,0));fire('touchmove',fingers(3,50,30));fire('touchend',[]);expect([{type:'taskView'}],'four up fires once without drag');
fire('touchstart',fingers(4,10,10));fire('touchmove',fingers(4,10,70));fire('touchend',[]);expect([{type:'showDesktop'}],'four down');
fire('touchstart',fingers(4,10,10));fire('touchmove',fingers(4,80,20));fire('touchmove',fingers(4,140,20));fire('touchend',[]);expect([{type:'desktop',direction:-1}],'four right goes to previous desktop once');
fire('touchstart',fingers(4,100,10));fire('touchmove',fingers(4,20,10));fire('touchend',[]);expect([{type:'desktop',direction:1}],'four left goes to next desktop');
fire('touchstart',fingers(5,10,10));fire('touchmove',fingers(5,10,90));fire('touchend',[]);expect([],'five contacts ignored');
element('speed').value='20';begin();fire('touchmove',[touch(210,10)]);fire('touchend',[]);timer(120);expect([{type:'dragStart',x:1,y:0},{type:'move',x:4000,y:0},{type:'up'}],'20x motion uses one packet');element('speed').value='3';
grab();fire('touchcancel',[]);expect([{type:'dragStart',x:1,y:0},{type:'move',x:18,y:0},{type:'up'},{type:'releaseAll'}],'cancel immediately releases all held controls');
grab();element('settings').handlers.click();expect([{type:'dragStart',x:1,y:0},{type:'move',x:18,y:0},{type:'up'},{type:'releaseAll'}],'settings release dragging');element('closeSettings').handlers.click();
grab();doc.hidden=true;doc.handlers.visibilitychange();expect([{type:'dragStart',x:1,y:0},{type:'move',x:18,y:0},{type:'releaseAll'}],'backgrounding releases all controls');assert.equal(ws.readyState,3);
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);fire('touchend',[]);expect([],'sleeping touches do not replay');
doc.hidden=false;doc.handlers.visibilitychange();connected();element('connect').handlers.click();assert.equal(ws.readyState,3);checks++;doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;doc.handlers.visibilitychange();assert.equal(ws.readyState,3);checks++;
element('connect').handlers.click();connected();fire('touchstart',[touch(10,10)]);time+=500;fire('touchend',[]);expect([{type:'left'}],'one-contact controls always accept slower taps');
fire('touchstart',[touch(10,10)]);time+=900;assert.ok(![...timers.values()].some(t=>t.ms===800),'holding still schedules no right-click');fire('touchend',[]);expect([],'a long still hold never clicks');
element('scrollMode').handlers.click();fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,30)]);fire('touchend',[]);expect([{type:'scroll',x:60,y:-60}],'one contact scrolls');element('scrollMode').handlers.click();
grab();win.handlers.resize();assert.deepEqual(sent,[{type:'dragStart',x:1,y:0},{type:'move',x:18,y:0}],'Safari chrome height changes must not release a drag');checks++;win.innerWidth=844;win.handlers.resize();expect([{type:'dragStart',x:1,y:0},{type:'move',x:18,y:0},{type:'up'},{type:'releaseAll'}],'rotation releases all controls');
fire('touchstart',[touch(10,10)]);ws.bufferedAmount=600;fire('touchmove',[touch(20,10)]);fire('touchmove',[touch(30,10)]);frame();assert.deepEqual(sent,[],'brief backpressure keeps unsent motion out of the socket');assert.equal(ws.readyState,1);ws.bufferedAmount=0;frame();fire('touchend',[]);expect([{type:'move',x:51,y:0}],'coalesced motion resumes without a reconnect or a backlog of old packets');
begin();ws.bufferedAmount=600;fire('touchmove',[touch(30,10)]);fire('touchend',[]);timer(120);ws.bufferedAmount=0;expect([{type:'dragStart',x:1,y:0},{type:'move',x:60,y:0},{type:'up'}],'backpressure preserves motion before a drag release');
const failed=ws;ws.close();timer(250);assert.notEqual(ws,failed);connected();checks++;time+=1500;pings.length=0;heartbeat();assert.deepEqual(pings.splice(0),[{type:'ping'}]);ws.onmessage({data:'{"pong":true}'});time+=1500;heartbeat();assert.equal(ws.readyState,1);sent.length=0;checks++;
time+=5000;heartbeat();assert.equal(ws.readyState,3);timer(250);connected();checks++;doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;win.handlers.pageshow();const waking=ws;win.handlers.focus();doc.handlers.visibilitychange();assert.equal(ws,waking);connected();checks++;
sent.length=0;time+=700;
tap();assert.deepEqual(sent,[],'a tap does not click immediately');assert.ok([...timers.values()].some(t=>t.ms===300),'the click waits 300 ms for a second touch');expect([{type:'left'}],'then the tap clicks once');
tap(10,10);fire('touchstart',[touch(10,10)]);timer(250);fire('touchmove',[touch(40,10)]);fire('touchend',[]);timer(120);
assert.ok(!sent.some(c=>c.type==='left'),'tap-hold-drag never clicks first (Task View keeps its window, menus stay open)');expect([{type:'dragStart',x:1,y:0},{type:'move',x:90,y:0},{type:'up'}],'tap-hold-drag is a pure drag');
tap(10,10);fire('touchstart',[touch(200,300)]);assert.deepEqual(sent,[{type:'left'}],'touching elsewhere sends the waiting click at once, before anything else');fire('touchend',[]);expect([{type:'left'},{type:'left'}],'the touch elsewhere is its own tap');
tap(10,10);fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(13,10)]);assert.deepEqual(sent,[],'tiny wobble after a tap waits');fire('touchmove',[touch(16,10)]);
assert.deepEqual(sent,[{type:'left'},{type:'move',x:18,y:0}],'a small move after a tap starts at 6 px: the click lands where tapped, then the pointer moves');fire('touchend',[]);sent.length=0;time+=700;
sent.length=0;time+=2000;pings.length=0;fire('touchstart',[touch(10,10)]);assert.equal(pings.length,1,'a touch after a pause sends one wake packet');fire('touchend',[]);sent.length=0;checks++;
doc.hidden=true;doc.handlers.visibilitychange();doc.hidden=false;doc.handlers.visibilitychange();const reconnecting=ws;
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);fire('touchend',[]);fire('touchstart',[touch(50,50)]);fire('touchend',[]);
reconnecting.onopen();sent.length=0;assert.equal(ws,reconnecting);reconnecting.onmessage({data:'{"ready":true}'});expect([{type:'move',x:51,y:0},{type:'left'}],'motion and a tap made while waking are delivered on connect');
// The low-latency stream must win over duplicate compatibility touches.
time+=2000;sent.length=0;
function pointer(type,id,x,y){element('pad').handlers[type]({pointerType:'touch',pointerId:id,clientX:x,clientY:y,preventDefault(){}});}
// Precision start: a small wobble right after touching down is held back
// while the fingertip settles (like Shadow / laptop trackpads).
pointer('pointerdown',9,10,10);pointer('pointermove',9,12,11);
assert.deepEqual(sent.filter(c=>c.type==='move'),[],'a wobble while the finger settles never moves the pointer');
pointer('pointerup',9,13,11);time+=700;sent.length=0;
pointer('pointerdown',9,10,10);pointer('pointermove',9,25,10);
assert.deepEqual(sent.filter(c=>c.type==='move'),[{type:'move',x:36,y:0}],'a deliberate move goes through at once (only the first 3 px of wobble are dropped)');
pointer('pointerup',9,25,10);time+=700;sent.length=0;
pointer('pointerdown',1,7,10);time+=250;
pointer('pointermove',1,11,10);
assert.deepEqual(sent,[{type:'move',x:3,y:0}],'past the 3 px wobble gate, a 1px pointer sample is sent synchronously without a touchmove or animation frame');
time+=4;pointer('pointermove',1,12,10);
assert.equal(sent.length,1,'pointer packets remain capped at 125 Hz');
time+=4;timer(4);
assert.deepEqual(sent,[{type:'move',x:3,y:0},{type:'move',x:3,y:0}],'pending pointer movement sends at the 8ms deadline without a display frame');
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);
assert.deepEqual(sent,[{type:'move',x:3,y:0},{type:'move',x:3,y:0}],'compatibility touch events never duplicate pointer motion');
pointer('pointercancel',1,11,10);assert.equal(sent.at(-1).type,'releaseAll','pointer cancellation releases held controls');
sent.length=0;time+=700;
pointer('pointerdown',1,10,10);pointer('pointerdown',2,30,10);time+=15;
for(let y=20;y<=50;y+=10){pointer('pointermove',1,10,y);pointer('pointermove',2,30,y);}pointer('pointerup',1,10,50);pointer('pointerup',2,30,50);
assert.equal(sent.filter(c=>c.type==='scroll').reduce((n,c)=>n+c.y,0),-120,'pointer two-finger scroll keeps the Windows direction and total distance');
assert.ok(!sent.some(c=>c.type==='move'||c.type==='left'||c.type==='right'),'two-finger scroll never leaks pointer motion or clicks');
checks+=4;sent.length=0;
ws.onclose();
pointer('pointerdown',7,20,20);time+=250;pointer('pointermove',7,24,20);
const pointerWakeSocket=ws;pointerWakeSocket.onopen();sent.length=0;pointerWakeSocket.onmessage({data:'{"ready":true}'});
assert.deepEqual(sent,[{type:'move',x:3,y:0}],'a pointer contact that wakes the connection is retained and delivered (beyond the 3 px wobble gate)');
pointer('pointercancel',7,24,20);sent.length=0;checks++;

ws.onmessage({data:'{"error":"pairing"}'});assert.equal(element('connect').textContent,'Connect');assert.ok(![...timers.values()].some(t=>t.ms===250));checks++;console.log('PASS: '+checks+' shared gesture and connection checks.');
