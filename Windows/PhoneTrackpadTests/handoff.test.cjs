// Newest device wins: a phone page takes control when opened or when Connect is
// tapped, but its automatic reconnects only resume, and it stops (instead of
// fighting) once the laptop says another phone or watch took control.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Shared/PhoneControl/Web/PhoneTrackpad.js'),'utf8');
const elements=new Map(),sockets=[],timers=new Map();let time=1000,nextTimer=0;
function element(id){if(!elements.has(id))elements.set(id,{value:'3',handlers:{},disabled:true,hidden:true,textContent:'',classList:{add(){},remove(){},toggle(){}},addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(){}});return elements.get(id);}
const doc={hidden:false,handlers:{},documentElement:element('html'),getElementById:element,addEventListener(type,fn){this.handlers[type]=fn;}};
const win={innerWidth:390,handlers:{},matchMedia(){return{matches:false};},addEventListener(type,fn){this.handlers[type]=fn;}};
class Socket{static OPEN=1;constructor(){sockets.push(this);this.readyState=1;this.bufferedAmount=0;this.sent=[];}send(text){this.sent.push(JSON.parse(text));}close(){this.readyState=3;}}
vm.runInNewContext(source,{document:doc,window:win,URLSearchParams,Uint8Array,crypto:require('node:crypto').webcrypto,location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834',search:''},WebSocket:Socket,localStorage:{getItem(){return null;},setItem(){}},performance:{now:()=>time},requestAnimationFrame(){},setInterval(){return 1;},clearInterval(){},setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,ms});return id;},clearTimeout(id){timers.delete(id);}});
const last=()=>sockets.at(-1);
function open(){const s=last();s.onopen();return s.sent[0];}
function reply(data){last().onmessage({data:JSON.stringify(data)});}
function runRetry(){const t=[...timers.entries()].find(([,t])=>t.ms<=2500&&t.ms!==4000);assert.ok(t,'a reconnect is scheduled');timers.delete(t[0]);t[1].fn();}

const first=open();
assert.equal(first.takeover,true,'opening the page takes control from any other device');
reply({ready:true});
assert.equal(element('status').textContent,'Connected');

// The laptop drops this phone (for example Wi-Fi blip): the retry only resumes.
last().onclose();runRetry();
const resume=open();
assert.equal(resume.takeover,false,'automatic reconnects never take control from a newer device');
assert.equal(resume.client,first.client,'the reconnect keeps the page identity');

// Another device took control meanwhile: stop retrying and say so.
const count=sockets.length;
reply({error:'replaced'});
assert.match(element('status').textContent,/Another device took control/);
assert.equal(element('connect').textContent,'Connect','the button offers to take control back');
assert.ok(![...timers.values()].some(t=>t.ms<=2500),'a replaced phone does not keep reconnecting');
doc.handlers.visibilitychange();win.handlers.focus();
assert.equal(sockets.length,count,'waking the page does not take control back');

// Tapping Connect makes this phone the newest device again.
element('connect').handlers.click();
const again=open();
assert.equal(again.takeover,true,'tapping Connect takes control');
reply({ready:true});
assert.equal(element('status').textContent,'Connected');
console.log('PASS: page open and Connect take over, automatic reconnects only resume, a replaced phone stops until Connect is tapped.');
