// Exercise the shipped phone page, including preferences from older releases.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../Shared/PhoneControl/Web/PhoneTrackpad.js'), 'utf8');
function phone(local = {}, remote = {}) {
  const elements = new Map(), sent = [], saved = new Map(), timers = new Map();
  let time = 1000, socket, nextTimer = 0;
  function element(id) {
    if (!elements.has(id)) elements.set(id, { value:'3', handlers:{}, classList:{add(){},remove(){},toggle(){}},
      addEventListener(type, fn){this.handlers[type]=fn;}, setAttribute(){} });
    return elements.get(id);
  }
  const viewport = {scale:1,offsetLeft:0,offsetTop:0};
  const win = {innerWidth:390,visualViewport:viewport,matchMedia(){return {matches:false};},addEventListener(){}};
  class Socket {
    static OPEN = 1;
    constructor(){socket=this;this.readyState=1;this.bufferedAmount=0;}
    send(text){const c=JSON.parse(text);if(c.type!=='ping')sent.push(c);}
    close(){this.readyState=3;}
  }
  vm.runInNewContext(source, {
    document:{hidden:false,documentElement:element('html'),getElementById:element,addEventListener(){}},window:win,
    URLSearchParams,Uint8Array,AbortController,crypto:require('node:crypto').webcrypto,
    location:{hash:'#'+'A'.repeat(48),host:'localhost:17834',search:''},WebSocket:Socket,
    localStorage:{getItem(key){return key==='3e-prefs'?JSON.stringify(local):null;},setItem(key,value){saved.set(key,value);}},
    fetch:async()=>({ok:true,json:async()=>({prefs:remote})}),performance:{now:()=>time},requestAnimationFrame(){},
    setInterval(){return 1;},clearInterval(){},setTimeout(fn,ms){timers.set(++nextTimer,{fn,ms});return nextTimer;},clearTimeout(id){timers.delete(id);}
  });
  socket.onopen();socket.onmessage({data:'{"ready":true}'});sent.length=0;
  function fire(type, data){element('pad').handlers[type]({preventDefault(){},cancelable:true,...data});time+=15;}
  return {win,viewport,sent,saved,fire};
}
function pinch(p, direction, {pointer=false,scaled=false,screen=true,diagonal=false}={}) {
  const gaps = direction>0?[80,110,150,190,240,290,340]:[340,300,250,210,160,120,80];
  function contacts(gap, step) {
    const scale=scaled?Math.pow(2, direction>0?step:gaps.length-1-step):1;
    Object.assign(p.viewport,{scale,offsetLeft:200-200/scale,offsetTop:350-350/scale});
    const angle=diagonal?Math.PI/4:0;
    return [-1,1].map((sign,id)=>{
      const dx=sign*gap/2*Math.cos(angle),dy=sign*gap/2*Math.sin(angle);
      return {pointerType:'touch',pointerId:id+1,clientX:200+dx/scale,clientY:350+dy/scale,
        ...(screen?{screenX:200+dx,screenY:350+dy}:{})};
    });
  }
  gaps.forEach((gap,step)=>{
    const touches=contacts(gap,step);
    if(pointer)for(const t of touches)p.fire(step?'pointermove':'pointerdown',t);
    else p.fire(step?'touchmove':'touchstart',{touches});
  });
  if(pointer)for(const t of contacts(gaps.at(-1),gaps.length-1))p.fire('pointerup',t);
  else p.fire('touchend',{touches:[]});
  const zoom=p.sent.filter(c=>c.type==='zoom');
  assert.ok(zoom.length>=2, 'must emit zoom steps: '+JSON.stringify(p.sent));
  assert.ok(zoom.every(c=>c.direction===direction),'wrong direction: '+JSON.stringify(zoom));
  assert.ok(!p.sent.some(c=>['scroll','history','right'].includes(c.type)),'pinch must not scroll/navigate/click');
}
(async()=>{
  let checks=0;
  for(const origin of ['local','remote','both'])for(const direction of [1,-1]) {
    const p=phone(origin!=='remote'?{swapZoom:true,speed:5}:{},origin!=='local'?{swapZoom:true}:{});
    await p.win.ThreeEPrefs.sync();
    pinch(p,direction);
    assert.equal(p.win.ThreeEPrefs.get('swapZoom'),false,'retire saved reversal '+origin);
    assert.equal(JSON.parse(p.saved.get('3e-prefs')).swapZoom,false);
    checks++;
  }
  for(const pointer of [false,true])for(const screen of [false,true])for(const diagonal of [false,true])for(const direction of [1,-1]) {
    const p=phone();
    pinch(p,direction,{pointer,screen,diagonal,scaled:true});checks++;
  }
  const p=phone({speed:5},{swapZoom:false});await p.win.ThreeEPrefs.sync();
  assert.equal(p.win.ThreeEPrefs.get('speed'),5,'migration preserves unrelated phone preferences');checks++;
  for(const type of ['gesturestart','gesturechange','gestureend']) {
    let prevented=false;p.fire(type,{preventDefault(){prevented=true;}});
    assert.ok(prevented,'Safari '+type+' must not zoom the control page');checks++;
  }
  console.log('PASS: '+checks+' pinch direction/migration checks (touch, pointer, screen, scaled viewport, diagonal).');
})().catch(error=>{console.error(error);process.exitCode=1;});
