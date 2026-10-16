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
// Laptop-trackpad behaviour: two-finger swipes, glide, pinch and acceleration.
const pair=(x,y,gap=60)=>[touch(x,y),touch(x+gap,y)];
const types=()=>sent.map(c=>c.type);
const sum=(type,key)=>sent.filter(c=>c.type===type).reduce((n,c)=>n+c[key],0);
function check(value,label){assert.ok(value,label);checks++;}
function settle(){sent.length=0;time+=700;}

// Quick sideways swipe (fingers move right) = Back, with no scrolling.
fire('touchstart',pair(100,200));for(let i=1;i<=6;i++)fire('touchmove',pair(100+i*16,200));fire('touchend',[]);
check(sent.filter(c=>c.type==='history').length===1&&sent.find(c=>c.type==='history').direction===-1&&!types().includes('scroll'),'quick two-finger swipe right goes back once, without scrolling');
check(!types().includes('right'),'a swipe is never a two-finger right-click');settle();
fire('touchstart',pair(200,200));for(let i=1;i<=6;i++)fire('touchmove',pair(200-i*16,200));fire('touchend',[]);
check(sent.find(c=>c.type==='history')?.direction===1,'quick two-finger swipe left goes forward');settle();

// Slow sideways slide = horizontal scroll, never navigation.
fire('touchstart',pair(100,200));for(let i=1;i<=30;i++){fire('touchmove',pair(100+i*3,200));}frame();fire('touchend',[]);
check(!types().includes('history')&&sum('scroll','x')>=250&&sum('scroll','y')===0,'slow two-finger sideways slide scrolls horizontally, axis-locked');settle();

// Vertical scroll keeps gliding after lifting, then stops by itself.
fire('touchstart',pair(100,300));for(let i=1;i<=8;i++)fire('touchmove',pair(101,300-i*12));fire('touchend',[]);frame();
const beforeGlide=sum('scroll','y');for(let i=0;i<40;i++){time+=16;frame();}
const glided=sum('scroll','y')-beforeGlide;
check(beforeGlide>0&&glided>0,'two-finger scroll keeps gliding after lifting');
const afterGlide=sum('scroll','y');for(let i=0;i<200;i++){time+=16;frame();}const tail=sum('scroll','y')-afterGlide;
for(let i=0;i<30;i++){time+=16;frame();}check(sum('scroll','y')-afterGlide===tail,'the glide slows to a stop');
check(sum('scroll','x')===0,'small sideways drift during a vertical scroll is ignored');settle();
fire('touchstart',pair(100,300));for(let i=1;i<=8;i++)fire('touchmove',pair(100,300-i*12));fire('touchend',[]);sent.length=0;
fire('touchstart',[touch(50,50)]);time+=16;frame();time+=16;frame();check(!types().includes('scroll'),'touching the pad stops a glide immediately');fire('touchend',[]);settle();

// Pinch apart = zoom in, pinch together = zoom out; no right-click afterwards.
fire('touchstart',pair(150,300,60));for(let i=1;i<=6;i++)fire('touchmove',[touch(150-i*10,300),touch(210+i*10,300)]);fire('touchend',[]);
check(sent.filter(c=>c.type==='zoom').length>=2&&sent.every(c=>c.type!=='zoom'||c.direction===1)&&!types().includes('right')&&!types().includes('scroll'),'pinching apart zooms in without scrolling or right-clicking');settle();
fire('touchstart',[touch(90,300),touch(270,300)]);for(let i=1;i<=6;i++)fire('touchmove',[touch(90+i*10,300),touch(270-i*10,300)]);fire('touchend',[]);
check(sent.some(c=>c.type==='zoom')&&sent.every(c=>c.type!=='zoom'||c.direction===-1),'pinching together zooms out');settle();

// After a two-finger gesture, the finger left on the glass does not move the pointer.
fire('touchstart',pair(100,300));for(let i=1;i<=6;i++)fire('touchmove',pair(100,300-i*12));fire('touchend',[touch(100,228)]);sent.length=0;
fire('touchmove',[touch(160,260)]);fire('touchend',[]);check(!types().includes('move'),'no pointer jump from the remaining finger after scrolling');settle();

// Two-finger tap is still a right-click.
fire('touchstart',pair(100,300));fire('touchend',[]);check(types().join()==='right','two-finger tap right-clicks');settle();

// Acceleration: the same finger distance moves the pointer further when fast.
fire('touchstart',[touch(10,400)]);for(let i=1;i<=20;i++){time+=35;fire('touchmove',[touch(10+i*3,400)]);}fire('touchend',[]);const slow=sum('move','x');settle();
fire('touchstart',[touch(10,400)]);for(let i=1;i<=3;i++){fire('touchmove',[touch(10+i*20,400)]);}fire('touchend',[]);const fast=sum('move','x');settle();
check(slow<60*3&&fast>60*3,'slow motion is finer and quick flicks travel further for the same finger distance ('+slow+' vs '+fast+')');

console.log('PASS: '+checks+' trackpad gesture checks.');
