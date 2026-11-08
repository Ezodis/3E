const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const cases=JSON.parse(fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Tests/track-tab.json'),'utf8'));
for(const test of cases) {

const source=fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const elements=new Map(),sent=[],pings=[],timers=new Map();let time=1000,frame,ws,heartbeat,checks=0,nextTimer=0;
function element(id){if(!elements.has(id))elements.set(id,{value:'3',handlers:{},dataset:{},disabled:true,hidden:true,classList:{add(){},remove(){},toggle(){}},addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(){}});return elements.get(id);}
const doc={hidden:false,handlers:{},documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
const win={innerWidth:390,handlers:{},matchMedia(){return{matches:false};},addEventListener(type,fn){this.handlers[type]=fn;}};
class Socket{static OPEN=1;constructor(){ws=this;this.readyState=1;this.bufferedAmount=0;}send(text){const command=JSON.parse(text);if(command.type==='move'){if(!Number.isFinite(command.t))throw new Error('move without phone timestamp');delete command.t;}(command.type==='ping'?pings:sent).push(command);}close(){this.readyState=3;this.onclose?.();}}
vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834',search:''},WebSocket:Socket,localStorage:{getItem(key){return key==='3e-acceleration'?'false':null;},setItem(){}},performance:{now:()=>time},requestAnimationFrame(fn){frame=fn;},setInterval(fn){heartbeat=fn;return 1;},clearInterval(){},setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}});
function connected(){ws.onopen();ws.onmessage({data:'{"ready":true}'});sent.length=0;}connected();
const touch=(x,y)=>({clientX:x,clientY:y}),fingers=(n,x,y)=>Array.from({length:n},(_,i)=>touch(x+i*20,y));
function fire(type,touches){element('pad').handlers[type]({touches,preventDefault(){}});time+=15;}

let previous=0;
for(const item of test.frames) {
  time=1000+item.t;
  const touches=item.points.map(([id,x,y])=>({identifier:id,clientX:x*390,clientY:y*390}));
  const type=touches.length>previous?'touchstart':touches.length<previous?'touchend':'touchmove';
  element('pad').handlers[type]({touches,preventDefault(){}});previous=touches.length;
}
const events=sent.map(c=>({action:c.type,value:c.direction??c.id??0}));
assert.deepEqual(events,test.events,test.name);
console.log('PASS: phone Track Tab / '+test.name);
}
console.log(cases.length+' phone Track Tab parity cases passed.');
