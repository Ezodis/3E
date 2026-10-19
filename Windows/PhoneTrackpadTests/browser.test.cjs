// Run against Program.cs --preview: real shared server, simulated native input.
const {webkit,chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path');
const url=require.main===module?fs.readFileSync(process.argv[2],'utf8').trim():null,out=process.argv[3]||'.';
if(require.main===module)fs.mkdirSync(out,{recursive:true});
async function drag(page,locator,dx,dy=0,hold=0){const r=await locator.boundingBox();await page.mouse.move(r.x+r.width/2,r.y+r.height/2);await page.mouse.down();if(hold)await page.waitForTimeout(hold);await page.mouse.move(r.x+r.width/2+dx,r.y+r.height/2+dy,{steps:5});await page.mouse.up();await page.waitForTimeout(150);}
async function wake(page){await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));});assert.equal(await page.locator('#apps').isDisabled(),true);await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:false});document.dispatchEvent(new Event('visibilitychange'));window.dispatchEvent(new Event('pageshow'));});await page.waitForFunction(()=>document.getElementById('status').textContent==='Connected');await page.evaluate(()=>delete document.hidden);}
// The computer installs an update and restarts (preview: <url-file>.restart):
// the page reloads itself once, never while a drag, the keyboard or the
// clipboard sheet is in use, and never twice within 30 s or for one build.
async function updateFlow(browser,name,url,urlFile,errors){
 const restart=async build=>{fs.writeFileSync(urlFile+'.restart',build);for(let i=0;i<100&&fs.readFileSync(urlFile+'.restart','utf8').trim();i++)await new Promise(r=>setTimeout(r,100));assert.equal(fs.readFileSync(urlFile+'.restart','utf8').trim(),'','preview receiver restarted');};
 async function open(viewport){
  const ctx=await browser.newContext({viewport,hasTouch:true,isMobile:true}),page=await ctx.newPage(),sent=[];
  page.on('pageerror',e=>errors.push(e.message));const net=[];
  page.on('response',r=>{if(r.status()>=300||r.request().isNavigationRequest())net.push(r.status()+' '+new URL(r.url()).pathname);});
  page.on('requestfailed',r=>net.push('failed '+new URL(r.url()).pathname+' '+r.failure()?.errorText));
  page.on('websocket',s=>s.on('framesent',f=>{try{const c=JSON.parse(f.payload);if(c.type)sent.push(c);}catch{}}));
  page.on('request',r=>{if(r.url().endsWith('/control')){try{const c=JSON.parse(r.postData());for(const x of c.commands||[])sent.push(x);}catch{}}});
  await page.addInitScript(()=>{try{sessionStorage.setItem('test-loads',String(+(sessionStorage.getItem('test-loads')||0)+1));}catch{}
   window.testSockets=[];const W=WebSocket;window.WebSocket=class extends W{constructor(...a){super(...a);window.testSockets.push(this);}};});
  const loads=async()=>{try{return await page.evaluate(()=>+sessionStorage.getItem('test-loads'));}catch{return -1;}};
  // Null-safe: right after a reload the new document may not have its DOM yet.
  const live=()=>page.waitForFunction(()=>document.getElementById('status')?.textContent==='Connected');
  const reloaded=async count=>{for(let i=0;i<100&&await loads()<count;i++)await page.waitForTimeout(100);assert.equal(await loads(),count,'the page reloaded');
   try{await live();}catch(e){throw new Error('reloaded page never connected; status: '+await page.evaluate(()=>document.getElementById('status')?.textContent).catch(()=>'?')+'; url '+page.url()+'; body '+JSON.stringify(await page.evaluate(()=>document.documentElement.outerHTML.slice(0,300)).catch(()=>'?'))+'; network '+net.slice(-12).join(', ')+'; '+e.message);}};
  await page.goto(url);await live();
  return {ctx,page,sent,loads,live,reloaded};
 }
 // Each reload in this tab starts the 30-second guard; move its clock instead of waiting.
 const backdate=page=>page.evaluate(()=>{const v=JSON.parse(sessionStorage.getItem('3e-update')||'{}');v.at=Date.now()-60000;sessionStorage.setItem('3e-update',JSON.stringify(v));});
 const {ctx,page:u,sent,loads,live,reloaded}=await open({width:390,height:844});
 const build=()=>u.evaluate(()=>window.ThreeEHost.build);
 assert.match(await build(),/^[0-9a-f]{16}$/,'the page knows the build it loaded with');
 // Update while the page stays put (something in use): it reconnects to the new receiver without reloading.
 // (Stops early if the page reloaded instead, so the caller's assertion explains why.)
 const reconnected=async()=>{const n=await loads();for(let i=0;i<150&&await loads()===n;i++){if(await u.evaluate(()=>window.testSockets?.length>=2&&window.testSockets.at(-1).readyState===1&&document.getElementById('status')?.textContent==='Connected').catch(()=>false))break;await u.waitForTimeout(100);}await u.waitForTimeout(1500);};
 const resetSockets=()=>u.evaluate(()=>{window.testSockets=window.testSockets.slice(-1);});
 const touches=(type,n,dx=0)=>u.evaluate(([type,n,dx])=>{const e=new Event(type,{bubbles:true,cancelable:true});Object.defineProperty(e,'touches',{value:Array.from({length:n},(_,i)=>({clientX:120+i*40+dx,clientY:400}))});document.getElementById('pad').dispatchEvent(e);},[type,n,dx]);
 {// A three-finger drag is held through the update.
  const first=await build();await touches('touchstart',3);await u.waitForTimeout(150);await touches('touchmove',3,12);await touches('touchmove',3,24);
  assert.ok(sent.some(c=>c.type==='down'),'three fingers hold the button down');
  await resetSockets();await restart('1111111111111111');await reconnected();
  assert.equal(await loads(),1,'no reload while a drag is held');assert.equal(await build(),first);
  const before=sent.length;await touches('touchend',0);await reloaded(2);
  assert.ok(sent.slice(before).some(c=>c.type==='releaseAll'),'releaseAll is sent before reloading');
  assert.equal(await build(),'1111111111111111','the reloaded page is the new build');
  assert.match(u.url(),/#[0-9A-F]{48}$/,'the reload keeps the pairing link');
  await u.waitForTimeout(1500);assert.equal(await loads(),2,'it reloads exactly once');}
 {// The phone keyboard is open.
  await backdate(u);await u.locator('#commands').tap();await u.locator('#commandsPane button[data-tool="keyboard"]').tap();
  assert.equal(await u.evaluate(()=>document.activeElement.id),'typeSink');
  await resetSockets();await restart('2222222222222222');await reconnected();
  assert.equal(await loads(),2,'no reload while the keyboard is open');
  await u.locator('#keyBar .done').dispatchEvent('pointerdown');await reloaded(3);}
 {// The clipboard sheet is open.
  await backdate(u);await u.locator('#commands').tap();await u.locator('#commandsPane button[data-tool="sendClip"]').tap();
  assert.equal(await u.locator('#clipSheet').isVisible(),true);
  await resetSockets();await restart('3333333333333333');await reconnected();
  assert.equal(await loads(),3,'no reload while the clipboard sheet is open');
  await u.locator('#clipClose').click();await reloaded(4);}
 {// Never twice within 30 s: the next update waits, then reloads.
  await resetSockets();await restart('4444444444444444');await reconnected();
  assert.equal(await loads(),4,'a second reload within 30 s waits');
  await backdate(u);await reloaded(5);assert.equal(await build(),'4444444444444444');}
 {// A build this tab already reloaded for is never retried (no reload loop).
  await u.evaluate(()=>sessionStorage.setItem('3e-update',JSON.stringify({build:'5555555555555555',at:0})));
  await resetSockets();await restart('5555555555555555');await reconnected();
  assert.equal(await loads(),5,'an already-attempted build never reloads again');}
 await ctx.close();
 {// Apple Watch (HTTP /control) updates the same way.
  const w=await open({width:162,height:197});
  assert.equal(await w.page.evaluate(()=>document.documentElement.classList.contains('watch')),true);
  await restart('6666666666666666');await w.reloaded(2);
  assert.ok(w.sent.some(c=>c.type==='releaseAll'),'the watch releases input before reloading');
  assert.equal(await w.page.evaluate(()=>window.ThreeEHost.build),'6666666666666666');
  await w.page.waitForTimeout(1500);assert.equal(await w.loads(),2,'the watch reloads exactly once');
  await w.ctx.close();}
 console.log('PASS '+name+': update reloads once after the computer updates; waits for drags, keyboard and clipboard; 30 s and per-build loop guards; watch too.');
}
// Real secure-context entry point: one tap reads and transfers, no staging click.
async function directClipFlow(browser,name,url){
 const ctx=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true});
 try{
  const p=await ctx.newPage(),commands=[];let writes=0;
  p.on('websocket',s=>s.on('framesent',f=>{try{const c=JSON.parse(f.payload);if(c.type)commands.push(c);}catch{}}));
  p.on('request',r=>{if(r.url().endsWith('/clipboard/write'))writes++;});
  await p.addInitScript(()=>{
   Object.defineProperty(navigator,'clipboard',{configurable:true,value:{read:async()=>{
    window.clipReadCount=(window.clipReadCount||0)+1;
    if(window.rejectClip)throw new Error('denied');
    return [{types:['text/plain','text/html'],getType:async type=>new Blob([type==='text/html'?'<b>Direct paste</b>':'Direct paste'],{type})}];
   }}});
  });
  await p.goto(url);await p.waitForFunction(()=>document.getElementById('status').textContent==='Connected');
  await p.locator('#commands').tap();await p.locator('[data-tool="sendClip"]').tap();
  for(let i=0;i<40&&!commands.some(c=>c.type==='shortcut'&&c.id===1);i++)await p.waitForTimeout(100);
  assert.equal(writes,1,'one tap uploads once');assert.equal(await p.evaluate(()=>window.clipReadCount),1);
  assert.ok(commands.some(c=>c.type==='shortcut'&&c.id===1),'one tap also pastes on the computer');
  await p.waitForFunction(()=>document.getElementById('clipSheet').hidden);
  await p.evaluate(()=>window.rejectClip=true);
  await p.locator('#commands').tap();await p.locator('[data-tool="sendClip"]').tap();
  await p.waitForSelector('.clip-paste:visible');assert.equal(writes,1,'denied access never uploads stale content');
  await p.evaluate(()=>{const d=new DataTransfer();d.setData('text/plain','Fallback paste');document.querySelector('.clip-paste').dispatchEvent(new ClipboardEvent('paste',{clipboardData:d,bubbles:true,cancelable:true}));});
  for(let i=0;i<40&&writes<2;i++)await p.waitForTimeout(100);
  assert.equal(writes,2,'native paste after denial transfers automatically');
  console.log('PASS '+name+': direct clipboard read and permission-denied automatic-paste fallback.');
 }finally{await ctx.close();}
}
if(require.main===module)(async()=>{
 for(const [name,engine] of [['webkit',webkit],['chromium',chromium]]){
  const browser=await engine.launch({headless:true});
  try{
   const errors=[],commands=[];
   const ctx=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true});
   const p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));
   p.on('websocket',s=>s.on('framesent',f=>{try{const c=JSON.parse(f.payload);if(c.type)commands.push(c);}catch{}}));
   // 127.0.0.1 is a secure context, where macOS WebKit offers Web Share instead of a
   // download. A phone reaches the computer at http://<LAN IP> (not secure) and downloads.
   await p.addInitScript(()=>{try{Object.defineProperty(navigator,'canShare',{value:undefined,configurable:true});Object.defineProperty(window,'isSecureContext',{value:false,configurable:true});}catch{}});
   await p.addInitScript(()=>{window.testSockets=[];const W=WebSocket;window.WebSocket=class extends W{constructor(...a){super(...a);window.testSockets.push(this);}};});
   const connectStart=Date.now();await p.goto(url);await p.waitForFunction(()=>document.getElementById('status').textContent==='Connected');
   console.log(name+' local page load + connection: '+(Date.now()-connectStart)+' ms (simulated input, loopback network)');
   // Real browser PointerEvent dispatch, independent of legacy touchmove.
   const moveStart=commands.length;
   await p.evaluate(()=>{const pad=document.getElementById('pad');for(const [type,x] of [['pointerdown',100],['pointermove',101],['pointercancel',101]])pad.dispatchEvent(new PointerEvent(type,{pointerType:'touch',pointerId:71,clientX:x,clientY:300,bubbles:true,cancelable:true}));});
   await p.waitForTimeout(100);
   assert.ok(commands.slice(moveStart).some(c=>c.type==='move'&&c.x>0&&c.y===0),'first small pointer sample reaches receiver without touchmove');
   assert.equal(await p.locator('#drag,#left,#right').count(),0);
   assert.deepEqual(await p.locator('#pad').boundingBox(),{x:0,y:0,width:390,height:844});
   assert.equal(await p.locator('#pad').evaluate(el=>getComputedStyle(el).boxShadow),'none','full-screen pad has no square frame');
   const dockBox=async id=>p.locator(id).boundingBox();
   const [commandsBox,appsBox,mediaBox]=[await dockBox('#commands'),await dockBox('#apps'),await dockBox('#media')];
   assert.ok(Math.abs(appsBox.x+appsBox.width/2-195)<=1,'Apps is centred in the dock');
   assert.ok(commandsBox.x<=16&&mediaBox.x+mediaBox.width>=374,'Shortcuts sit in the left corner and Media on the right');
   await p.locator('#commands').tap();assert.equal(await p.locator('#commandsPane button[data-shortcut]').count(),18);
   assert.equal(await p.locator('#commandsPane button[data-tool]:visible').count(),3,'Keyboard, Paste to and Copy from appear for a host that supports them');
   await p.locator('#commandsPane button[aria-label^="Copy ("]').tap();await p.waitForTimeout(250);
   assert.ok(commands.some(c=>c.type==='shortcut'&&c.id===0),'Copy sends its fixed shortcut id');assert.equal(await p.locator('#commandsPane').isVisible(),false);
   {const c=await p.locator('#commands').boundingBox();await p.mouse.move(c.x+c.width/2,c.y+c.height/2);await p.mouse.down();
    const target=await p.locator('#commandsPane button[aria-label^="Area shot"]').boundingBox();
    await p.mouse.move(target.x+target.width/2,target.y+target.height/2,{steps:6});await p.mouse.up();await p.waitForTimeout(250);
    assert.ok(commands.some(c=>c.type==='shortcut'&&c.id===14),'press ⌘, slide to ⇧⌘4 and release sends it');assert.equal(await p.locator('#commandsPane').isVisible(),false);}
   {// Phone keyboard: typing, autocorrect-style replacement, key bar and Done.
    await p.locator('#commands').tap();await p.locator('#commandsPane button[data-tool="keyboard"]').tap();
    assert.equal(await p.evaluate(()=>document.activeElement.id),'typeSink','Keyboard focuses the typing field (opens the phone keyboard)');
    assert.equal(await p.locator('#keyBar').isVisible(),true);
    const typed=()=>commands.filter(c=>c.type==='text').map(c=>c.text).join('');const start=commands.length;
    await p.keyboard.type('Hi é😀');await p.keyboard.press('Backspace');await p.waitForTimeout(150);
    assert.equal(typed(),'Hi é😀','typed text reaches the computer');assert.ok(commands.slice(start).some(c=>c.type==='key'&&c.id===0),'Backspace is replayed');
    await p.evaluate(()=>{const s=document.getElementById('typeSink');s.value='teh ';s.setSelectionRange(4,4);s.dispatchEvent(new Event('input'));s.value='the ';s.setSelectionRange(4,4);s.dispatchEvent(new Event('input'));});
    await p.waitForTimeout(150);
    assert.deepEqual(commands.filter(c=>c.type!=='ping').slice(-3).map(c=>c.type==='text'?'text:'+c.text:'key:'+c.id+'x'+c.n),['text:teh ','key:0x3','text:he '],'an autocorrect replacement becomes backspaces and the corrected letters');
    await p.screenshot({path:path.join(out,'keyboard-'+name+'.png')});
    for(const id of ['4','3']){await p.locator(`#keyBar button[data-key="${id}"]`).dispatchEvent('pointerdown');await p.locator(`#keyBar button[data-key="${id}"]`).dispatchEvent('pointerup');}
    await p.waitForTimeout(100);assert.ok(commands.some(c=>c.type==='key'&&c.id===4)&&commands.some(c=>c.type==='key'&&c.id===3),'key bar ← and Esc');
    assert.equal(await p.evaluate(()=>document.activeElement.id),'typeSink','the phone keyboard stays open while using the key bar');
    await p.locator('#keyBar .done').dispatchEvent('pointerdown');await p.waitForTimeout(100);
    assert.equal(await p.locator('#keyBar').isVisible(),false,'Done closes the keyboard');}
   {// Paste to: text, formatting, a photo and a PDF arrive and Ctrl/⌘+V follows.
    await p.locator('#commands').tap();await p.locator('#commandsPane button[data-tool="sendClip"]').tap();
    assert.equal(await p.locator('#clipSheet').isVisible(),true);
    const before=commands.length;
    await p.evaluate(async()=>{
     const c=document.createElement('canvas');c.width=64;c.height=48;const g=c.getContext('2d');g.fillStyle='#e33';g.fillRect(0,0,64,48);
     const jpeg=await new Promise(r=>c.toBlob(r,'image/jpeg',.9)),dt=new DataTransfer();
     dt.setData('text/plain','Meeting notes');dt.setData('text/html','<p>Meeting <b>notes</b></p>');
     dt.items.add(new File([jpeg],'IMG_0001.jpg',{type:'image/jpeg'}));dt.items.add(new File(['%PDF-1.7 x'],'Invoice März.pdf',{type:'application/pdf'}));
     document.querySelector('#clipSheet .clip-paste').dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true}));});
    assert.equal(await p.locator('#clipActions').isVisible(),false,'paste transfers immediately without a second confirmation');
    let sentClip=[];for(let i=0;i<40&&!sentClip.length;i++){await p.waitForTimeout(100);try{sentClip=JSON.parse(fs.readFileSync(process.argv[2]+'.clip','utf8')||'[]');}catch{}}
    assert.deepEqual(sentClip.map(c=>c.kind),['text','html','image','file','file'],'text, HTML, the picture and both files reach the computer clipboard');
    assert.ok(sentClip[2].head.startsWith('89504E47')&&sentClip[4].name==='Invoice März.pdf','the photo arrives as PNG and files keep their names');
    await p.waitForTimeout(200);assert.ok(commands.slice(before).some(c=>c.type==='shortcut'&&c.id===1),'then paste is pressed on the computer');}
   {// Copy from: formatted text (sanitized), text, picture and a file download.
    await p.waitForTimeout(1000);await p.locator('#commands').tap();await p.locator('#commandsPane button[data-tool="getClip"]').tap();
    await p.waitForSelector('#clipSheet .clip-image img');
    const rich=p.locator('#clipSheet .clip-rich');
    assert.equal((await rich.innerText()).trim(),'Hello from the computer');assert.equal(await rich.locator('script,style').count(),0,'copied scripts and styles are stripped');
    assert.equal(await p.evaluate(()=>window.bad),undefined,'copied HTML never runs');
    assert.equal(await p.locator('#clipSheet .clip-text').inputValue(),'Hello from the computer');
    await p.waitForFunction(()=>document.querySelector('#clipSheet .clip-image img').naturalWidth===40);
    await p.screenshot({path:path.join(out,'clipboard-get-'+name+'.png'),fullPage:true});
    const [download]=await Promise.all([p.waitForEvent('download'),p.locator('#clipSheet .clip-list button').click()]);
    assert.equal(download.suggestedFilename(),'Quarterly report.pdf');
    assert.equal(fs.readFileSync(await download.path(),'utf8'),'%PDF-1.4 preview','the copied file downloads to the phone');
    await p.locator('#clipClose').click();}
   assert.deepEqual(await p.locator('#apps').evaluate(el=>({background:getComputedStyle(el).backgroundColor,border:getComputedStyle(el).borderTopWidth})),{background:'rgba(0, 0, 0, 0)',border:'0px'},'Apps artwork has no enclosing button bezel');
   await drag(p,p.locator('#apps'),70);await drag(p,p.locator('#apps'),-70);
   assert.deepEqual(commands.filter(c=>c.type==='navigate').map(c=>c.direction),[1,-1],'swipes send finger direction for host desktop or window routing');
   assert.equal(commands.some(c=>c.type==='appsBegin'),false,'touching Apps must not switch before the swipe');
   assert.ok(commands.some(c=>c.type==='navigateEnd'));
   assert.equal((await p.locator('#apps').innerText()).trim(),'');assert.equal((await p.locator('#media').innerText()).trim(),'');
   await drag(p,p.locator('#apps'),-65,0,600);
   assert.ok(commands.some(c=>c.type==='appsBegin')&&commands.some(c=>c.type==='appsStep'&&c.direction===-1)&&commands.some(c=>c.type==='appsEnd'));
   {const before=commands.length;await drag(p,p.locator('#apps'),0,-80);await drag(p,p.locator('#apps'),0,80);
    const vertical=commands.slice(before).filter(c=>['taskView','showDesktop'].includes(c.type)).map(c=>c.type);
    assert.deepEqual(vertical,['taskView','taskView'],'Apps swipe up opens all windows and swipe down closes them');}
   const beforeVertical=commands.filter(c=>['navigate','appsBegin','media'].includes(c.type)).length;
   await drag(p,p.locator('#apps'),5,-65);await drag(p,p.locator('#media'),5,-65);
   assert.equal(commands.filter(c=>['navigate','appsBegin','media'].includes(c.type)).length,beforeVertical,'vertical motion cancels instead of switching or playing');
   assert.equal(await p.locator('#volumePane').isVisible(),true,'upward Media swipe reveals the volume slider');
   await p.locator('#outputVolume').fill('37');await p.waitForTimeout(100);
   assert.ok(commands.some(c=>c.type==='volume'&&c.level===37),'volume slider sends its absolute level');
   await p.screenshot({path:path.join(out,'volume-phone-'+name+'.png')});
   await drag(p,p.locator('#outputVolume'),0,-25);
   assert.ok(+await p.locator('#outputVolume').inputValue()>50,'moving the vertical slider upward increases output volume');
   await p.locator('#pad').click({position:{x:190,y:250}});
   assert.equal(await p.locator('#volumePane').isVisible(),false);
   await p.evaluate(()=>window.ThreeEDock.describe({controls:{media:{playing:true,source:'spotify'}}}));
   assert.equal(await p.locator('#media').getAttribute('data-icon'),'pause');
   assert.equal(await p.locator('#media .dock-glyph').count(),1,'source without artwork shows only playback');
   await p.evaluate(()=>{
    const canvas=document.createElement('canvas');canvas.width=canvas.height=48;
    canvas.getContext('2d').fillRect(0,0,48,48);
    window.ThreeEDock.describe({controls:{media:{playing:true,artwork:canvas.toDataURL()}}});
   });
   assert.equal(await p.locator('#media .dock-glyph').count(),2);
   await p.waitForFunction(()=>{const image=document.querySelector('#media img');return image?.complete&&image.naturalWidth===48;});
   await p.evaluate(()=>window.ThreeEDock.describe({controls:{media:{playing:true,source:'browser'}}}));
   assert.equal(await p.locator('#media img').count(),0,'changing to an unknown source clears its previous icon');
   assert.equal(await p.locator('#media .dock-glyph').count(),1,'browser source never substitutes a globe');
   await p.evaluate(()=>window.ThreeEDock.describe({controls:{media:{playing:true,stop:true,source:'ableton'}}}));
   assert.equal(await p.locator('#media').getAttribute('data-icon'),'stop');
   await drag(p,p.locator('#media'),0);await drag(p,p.locator('#media'),-45);await drag(p,p.locator('#media'),45);
   for(const action of [0,1,2])assert.ok(commands.some(c=>c.type==='media'&&c.action===action));
   const mediaCount=commands.filter(c=>c.type==='media').length;
   await drag(p,p.locator('#media'),0,0,900);
   assert.equal(await p.locator('#studio').isVisible(),true);
   assert.equal(await p.locator('#studio h1').innerText(),'3£ Phone Bar');
   const returnTarget=async page=>{
    const media=await page.locator('#media').boundingBox(),back=await page.locator('#closeStudio').boundingBox();
    for(const axis of ['x','y','width','height'])assert.ok(Math.abs(media[axis]-back[axis])<1,'return target matches Media '+axis);
    for(const property of ['backgroundColor','color','borderRadius','borderColor'])assert.equal(await page.locator('#closeStudio').evaluate((el,p)=>getComputedStyle(el)[p],property),await page.locator('#media').evaluate((el,p)=>getComputedStyle(el)[p],property));
    const nav=await page.locator('.studio-tabs').boundingBox();assert.ok(nav.y>400&&nav.x+nav.width<=back.x,'view buttons sit beside return at the bottom');
   };
   await returnTarget(p);
   await p.waitForFunction(()=>document.getElementById('midiOutput').options.length>1);
   assert.equal(commands.filter(c=>c.type==='media').length,mediaCount,'holding Media must not play/pause on release');
   await p.locator('#midiOutput').selectOption('0');await p.waitForFunction(()=>document.getElementById('midiStatus').textContent.startsWith('Sending to'));
   const low=p.locator('.deck-a .knob[data-cc="50"]');
   await drag(p,low,0,-30);
   assert.ok(+await low.getAttribute('aria-valuenow')>64);
   const before=+await low.getAttribute('aria-valuenow'),r=await low.boundingBox();
   await p.mouse.move(r.x+r.width*.90,r.y+r.height/2);await p.mouse.down();await p.mouse.move(r.x+r.width/2,r.y+r.height*.90,{steps:4});await p.mouse.up();await p.waitForTimeout(60);
   assert.ok(+await low.getAttribute('aria-valuenow')>before,'clockwise rim movement increases knob');
   await p.locator('.deck-a').getByRole('button',{name:'Launch',exact:true}).click();
   assert.equal(await p.locator('.deck-a .vinyl').evaluate(el=>el.classList.contains('is-spinning')),true);
   await p.locator('.deck-a .vinyl').focus();await p.keyboard.press('ArrowRight');await p.keyboard.press('ArrowLeft');
   await p.locator('#crossfader').fill('100');await p.waitForTimeout(50);
   assert.ok(commands.some(c=>c.type==='midiCC'&&c.channel===15&&c.number===50&&c.value>64));
   assert.ok(commands.some(c=>c.type==='midiNote'&&c.number===36&&c.value===127)&&commands.some(c=>c.type==='midiNote'&&c.number===36&&c.value===0));
   assert.ok(commands.some(c=>c.type==='midiCC'&&c.number===40&&c.value===65)&&commands.some(c=>c.type==='midiCC'&&c.number===40&&c.value===63));
   assert.ok(commands.some(c=>c.type==='midiCC'&&c.number===1&&c.value===100));
   await p.screenshot({path:path.join(out,'studio-decks-'+name+'.png')});
   await p.locator('#mixerTab').click();assert.equal(await p.locator('.strip').count(),8);
   await p.locator('.strip .fader').first().fill('80');await p.waitForTimeout(50);
   assert.equal(await p.locator('.deck-a .knob[data-cc="16"]').getAttribute('aria-valuenow'),'80');
   await p.screenshot({path:path.join(out,'studio-mixer-'+name+'.png')});
   await p.locator('#midiTab').click();assert.equal(await p.locator('#midiView').isVisible(),true);
   assert.equal(await p.locator('#piano .piano-key').count(),25);
   assert.equal(await p.locator('#midiChannel').inputValue(),'0','piano is separate from mixer channel 16');
   assert.equal(await p.locator('#midiChannel option[value="15"]').evaluate(option=>option.disabled),true,'piano cannot trigger control-surface notes');
   assert.equal(await p.locator('#crossfader').isVisible(),false);
   await returnTarget(p);
   const key=p.locator('#piano [data-note="60"]'),kb=await key.boundingBox(),next=await p.locator('#piano [data-note="62"]').boundingBox();
   let noteStart=commands.length;
   await p.mouse.move(kb.x+kb.width/2,kb.y+kb.height*.85);await p.mouse.down();
   await p.mouse.move(next.x+next.width/2,next.y+next.height*.85);await p.mouse.up();await p.waitForTimeout(100);
   assert.deepEqual(commands.slice(noteStart).filter(c=>c.type==='midiNote').map(c=>[c.number,c.value]),[[60,100],[60,0],[62,100],[62,0]],'piano glissando releases the previous key and final key');
   assert.ok(commands.slice(noteStart).filter(c=>c.type==='midiNote').every(c=>c.channel===0),'piano notes reach the instrument channel');
   noteStart=commands.length;await key.focus();await p.keyboard.press('Space');await p.waitForTimeout(100);
   assert.deepEqual(commands.slice(noteStart).filter(c=>c.type==='midiNote').map(c=>[c.number,c.value]),[[60,100],[60,0]],'keyboard activation plays exactly once');
   await p.mouse.move(kb.x+kb.width/2,kb.y+kb.height*.85);await p.mouse.down();
   await p.evaluate(()=>document.getElementById('mixerTab').click());await p.mouse.up();await p.waitForTimeout(100);
   assert.equal(commands.filter(c=>c.type==='midiNote').at(-1).value,0,'changing views releases held notes');
   await p.locator('#midiTab').click();await p.locator('#octaveDown').click();assert.equal(await p.locator('#piano [data-note="48"]').count(),1);
   noteStart=commands.length;
   await p.evaluate(()=>{
    const piano=document.getElementById('piano'),captured=new Set();
    const original=['setPointerCapture','hasPointerCapture','releasePointerCapture'].map(k=>piano[k]);
    piano.setPointerCapture=id=>captured.add(id);piano.hasPointerCapture=id=>captured.has(id);piano.releasePointerCapture=id=>captured.delete(id);
    const touch=(type,id,n)=>{const r=piano.querySelector('[data-note="'+n+'"]').getBoundingClientRect();piano.dispatchEvent(new PointerEvent(type,{pointerId:id,pointerType:'touch',clientX:r.x+r.width/2,clientY:r.y+r.height*.85,bubbles:true,cancelable:true}));};
    try {
     touch('pointerdown',501,48);touch('pointerdown',502,48);touch('pointerup',501,48);
     if(!piano.querySelector('[data-note="48"]').classList.contains('held'))throw new Error('lifting one finger must keep the shared note held');
     touch('pointermove',502,52);touch('pointerdown',503,55);
     document.getElementById('panic').click();
     touch('pointermove',502,53);touch('pointerup',502,53);touch('pointerup',503,55);
    } finally {['setPointerCapture','hasPointerCapture','releasePointerCapture'].forEach((k,i)=>{piano[k]=original[i];});}
   });await p.waitForTimeout(100);
   assert.deepEqual(commands.slice(noteStart).filter(c=>c.type==='midiNote').map(c=>[c.number,c.value]),[[48,100],[48,0],[52,100],[55,100],[52,0],[55,0]],'multi-touch shares held notes, plays chords and cannot restart after panic');
   await p.screenshot({path:path.join(out,'studio-midi-'+name+'.png')});
   await p.setViewportSize({width:844,height:390});await p.waitForTimeout(100);await p.screenshot({path:path.join(out,'studio-landscape-'+name+'.png')});
   const landscapeMedia=await p.locator('#media').boundingBox(),landscapeBack=await p.locator('#closeStudio').boundingBox();
   assert.deepEqual(landscapeBack,landscapeMedia,'return target follows Media after rotation');

   await wake(p);
   await p.waitForFunction(()=>document.getElementById('midiStatus').textContent.startsWith('Sending to'));
   await p.locator('#closeStudio').click();await p.evaluate(()=>window.testSockets.at(-1).close());
   await p.waitForFunction(()=>window.testSockets.length>=3&&document.getElementById('status').textContent==='Connected');
   assert.equal(await p.locator('#tongueMode').count(),0,'one-contact controls have no toggle');
   assert.equal(await p.locator('#scrollMode').isVisible(),false,'phone dock has no scroll button');
   await p.screenshot({path:path.join(out,'trackpad-landscape-'+name+'.png')});
   await p.getByRole('button',{name:'Settings',exact:true}).click();await p.locator('#connect').click();
   const watchCtx=await browser.newContext({viewport:{width:162,height:197},hasTouch:true,isMobile:true});
   const w=await watchCtx.newPage(),posts=[];w.on('pageerror',e=>errors.push(e.message));w.on('request',r=>{if(r.url().endsWith('/control'))posts.push(JSON.parse(r.postData()));});
   await w.goto(url);await w.waitForFunction(()=>document.getElementById('status').textContent==='Connected');
   assert.equal(await w.evaluate(()=>document.documentElement.classList.contains('watch')),true);
   for(const id of ['apps','scrollMode','media']){const box=await w.locator('#'+id).boundingBox();assert.ok(box.x>=0&&box.x+box.width<=162,id+' fits watch');}
   await wake(w);assert.equal(posts.filter(p=>p.type==='connect').length,2);
   await w.screenshot({path:path.join(out,'trackpad-watch-'+name+'.png')});
   await drag(w,w.locator('#media'),0,-50);
   assert.equal(await w.locator('#volumePane').isVisible(),true);
   const volumeBox=await w.locator('#volumePane').boundingBox();assert.ok(volumeBox.y>=0&&volumeBox.x+volumeBox.width<=162,'volume overlay fits Watch');
   await w.locator('#outputVolume').fill('29');await w.waitForTimeout(150);
   assert.ok(posts.filter(p=>p.type==='commands').flatMap(p=>p.commands).some(c=>c.type==='volume'&&c.level===29));
   await w.screenshot({path:path.join(out,'volume-watch-'+name+'.png')});
   await drag(w,w.locator('#apps'),34);
   await drag(w,w.locator('#media'),0,0,650);
   assert.equal(await w.locator('#studio').isVisible(),true);
   await w.locator('#midiOutput').selectOption('0');await w.waitForFunction(()=>document.getElementById('midiStatus').textContent.startsWith('Sending to'));
   await w.screenshot({path:path.join(out,'studio-watch-'+name+'.png')});
   assert.ok(posts.filter(p=>p.type==='commands').flatMap(p=>p.commands).some(c=>c.type==='navigateEnd'));
   await w.goto('about:blank');
   await directClipFlow(browser,name,url);
   await updateFlow(browser,name,url,process.argv[2],errors);
   assert.deepEqual(errors,[]);
   console.log('PASS '+name+': keyboard typing and key bar, clipboard send/receive, Apps hold/swipe/release, Media tap/swipe/hold, linear/circular knobs, MIDI notes/CC/jogs, eight-channel mixer, wake/reconnect and watch HTTP layout.');
  }finally{await browser.close();}
 }
})().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={updateFlow,directClipFlow};
