// A USB QR must stay on its literal address, even if .local answers once.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../Shared/PhoneControl/Web/PhoneTrackpad.js'), 'utf8');
const secret = 'A'.repeat(48);
function page(search) {
  const elements = new Map(), requests = [], sockets = [], redirects = [];
  const element = id => {
    if (!elements.has(id)) elements.set(id, { id, value:'3', handlers:{}, dataset:{}, disabled:true, hidden:true,
      classList:{add(){},remove(){},toggle(){}}, addEventListener(type, fn){this.handlers[type]=fn;},setAttribute(){} });
    return elements.get(id);
  };
  const document = { hidden:false,documentElement:element('html'),getElementById:element,addEventListener(){} };
  const window = { innerWidth:390,ThreeEHost:{platform:'windows',alias:'3e-win.local:17833'},matchMedia(){return {matches:false};},addEventListener(){} };
  class Socket {
    static OPEN=1;
    constructor(url){this.url=url;this.readyState=1;this.bufferedAmount=0;this.sent=[];sockets.push(this);}
    send(text){this.sent.push(JSON.parse(text));} close(){this.readyState=3;}
  }
  vm.runInNewContext(source, { document,window,URLSearchParams,Uint8Array,AbortController,WebSocket:Socket,
    crypto:require('node:crypto').webcrypto,
    location:{host:'172.20.10.5:17833',hash:'#'+secret,search,replace(url){redirects.push(url);}},
    localStorage:{getItem(){return null;},setItem(){}},performance:{now:()=>1000},
    requestAnimationFrame(){},setInterval(){return 1;},clearInterval(){},setTimeout(){return 1;},clearTimeout(){},
    async fetch(url){requests.push(url);return {ok:true,status:204,json:async()=>({prefs:{}})};}
  });
  return {requests,sockets,redirects,element};
}
(async()=>{
  const usb=page('?usb=1');
  assert.equal(usb.sockets[0].url,'ws://172.20.10.5:17833/ws');
  usb.sockets[0].onopen();
  assert.equal(usb.sockets[0].sent[0].token,secret,'pairing keeps the complete QR secret');
  usb.sockets[0].onmessage({data:JSON.stringify({ready:true,host:{connection:{kind:'usb'}}})});
  await new Promise(setImmediate);
  assert.equal(usb.element('status').textContent,'Connected · USB cable · wired');
  assert.equal(usb.element('status').dataset.link,'usb');
  assert.ok(!usb.requests.some(url=>url.includes('3e-win.local')),'USB does not attempt name discovery');
  assert.equal(usb.redirects.length,0,'USB never leaves its working cable address');
  const lan=page('');
  await new Promise(setImmediate);
  assert.ok(lan.requests.includes('http://3e-win.local:17833/alive'));
  assert.deepEqual(lan.redirects,['http://3e-win.local:17833/#'+secret],'permitted LAN retains stable-name bookmarks');
  console.log('PASS: 8 USB pairing, route, authentication and LAN compatibility checks.');
})().catch(error=>{console.error(error);process.exitCode=1;});
