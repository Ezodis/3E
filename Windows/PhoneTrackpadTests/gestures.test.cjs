const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../DragEngine/ThreeFingerDragOnWindows/PhoneTrackpad.js'), 'utf8');
const elements = new Map(), sent = [];
let time = 1000, frame, ws;
function element(id) {
  if (!elements.has(id)) elements.set(id, { value: '1.4', handlers: {}, disabled: true,
    classList: { add(){}, remove(){}, toggle(){} },
    addEventListener(type, fn) { this.handlers[type] = fn; }, setAttribute(){} });
  return elements.get(id);
}
const doc = { hidden:false, handlers:{}, getElementById:element, addEventListener(type,fn){this.handlers[type]=fn;} };
const win = { handlers:{}, addEventListener(type,fn){this.handlers[type]=fn;} };
class Socket {
  static OPEN=1;
  constructor(){ws=this;this.readyState=1;this.bufferedAmount=0;}
  send(text){sent.push(JSON.parse(text));}
  close(){this.readyState=3;this.onclose?.();}
}
vm.runInNewContext(source, { document:doc, window:win, location:{hash:'#'+'A'.repeat(48),host:'127.0.0.1:17834'},
  WebSocket:Socket, localStorage:{getItem(){return null;},setItem(){}},
  performance:{now:()=>time}, requestAnimationFrame(fn){frame=fn;}, setInterval(){return 1;}, clearInterval(){} });
ws.onopen(); ws.onmessage({data:'{"ready":true}'}); sent.length=0;
const touch=(x,y)=>({clientX:x,clientY:y});
function fire(type,touches){element('pad').handlers[type]({touches,preventDefault(){}});time+=15;}
function take(){return sent.splice(0);}
fire('touchstart',[touch(10,10)]);fire('touchend',[]);
assert.deepEqual(take(),[{type:'left'}]);
fire('touchstart',[touch(10,10),touch(30,10)]);fire('touchend',[touch(10,10)]);fire('touchend',[]);
assert.deepEqual(take(),[{type:'right'}]);
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,20)]);frame();fire('touchend',[]);
assert.deepEqual(take(),[{type:'move',x:28,y:14}]);
fire('touchstart',[touch(10,10),touch(30,10)]);fire('touchmove',[touch(10,30),touch(30,30)]);frame();fire('touchend',[]);
assert.deepEqual(take(),[{type:'scroll',x:0,y:60}]);
fire('touchstart',[touch(10,10),touch(30,10),touch(50,10)]);
fire('touchmove',[touch(30,10),touch(50,10),touch(70,10)]);frame();
fire('touchend',[touch(30,10),touch(50,10)]);fire('touchmove',[touch(50,30),touch(70,30)]);fire('touchend',[]);
assert.deepEqual(take(),[{type:'down'},{type:'move',x:28,y:0},{type:'up'}]);
element('drag').handlers.click();fire('touchstart',[touch(10,10)]);fire('touchcancel',[]);
assert.deepEqual(take(),[{type:'down'},{type:'up'}]);
element('drag').handlers.click();doc.hidden=true;doc.handlers.visibilitychange();
assert.deepEqual(take(),[{type:'down'},{type:'up'}]);
assert.equal(ws.readyState,3);
fire('touchstart',[touch(10,10)]);fire('touchmove',[touch(30,10)]);frame();fire('touchend',[]);
assert.deepEqual(take(),[]);
assert.equal(element('left').disabled,true);
console.log('PASS: tap, right-click, movement, natural scroll, three-finger drag, touch cancellation, background release, disconnected input.');
