// Actual phone DOM/CSS and clipboard logic; all native input and clipboard I/O
// are simulated. No keystrokes or clipboard writes reach the user's desktop.
const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const root=path.join(__dirname,'../../Shared/PhoneControl/Web'),out=process.argv[2]||'.';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1kAAAAASUVORK5CYII=','base64');
let platform='windows',clipboard={text:'Hello from the computer',html:'<b>Hello</b> from the computer'},uploads=[];
const server=http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/host.js'){res.setHeader('Content-Type','text/javascript');return res.end(`window.ThreeEHost={platform:${JSON.stringify(platform)},keyboard:true,keyboardModifiers:true,clipboard:true};window.testConnected=true;window.sent=[];window.ThreeEControl={connected:()=>window.testConnected,release(){},send(type,data){window.sent.push({type,...data});return true;}};`);}
 if(['/pad.js','/surface.js','/dj.js'].includes(url.pathname)){res.setHeader('Content-Type','text/javascript');return res.end('');}
 if(url.pathname==='/clipboard/read'){res.setHeader('Content-Type','application/json');return res.end(JSON.stringify(clipboard));}
 if(url.pathname==='/clipboard/item'){res.setHeader('Content-Type','image/png');return res.end(png);}
 if(url.pathname==='/clipboard/write'){const chunks=[];for await(const part of req)chunks.push(part);uploads.push({manifest:JSON.parse(Buffer.from(req.headers['x-clip-manifest'],'base64').toString()),body:Buffer.concat(chunks)});res.setHeader('Content-Type','application/json');return res.end('{"ok":true}');}
 const name=url.pathname==='/'?'PhoneTrackpad.html':url.pathname.slice(1),file=path.join(root,name);
 if(!/^[\w.-]+$/.test(name)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'text/html');res.end(fs.readFileSync(file));
});
const press=async(page,selector)=>{await page.locator(selector).dispatchEvent('pointerdown',{pointerId:1});await page.locator(selector).dispatchEvent('pointerup',{pointerId:1});};
let checks=0;function check(condition,label){assert.ok(condition,label);checks++;}
(async()=>{
 fs.mkdirSync(out,{recursive:true});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url=`http://127.0.0.1:${server.address().port}/#${'A'.repeat(48)}`;
 for(const [name,engine] of [['chromium',chromium],['webkit',webkit]]){
  const browser=await engine.launch({headless:true,executablePath:process.env['PLAYWRIGHT_'+name.toUpperCase()+'_PATH']||undefined});
  try{for(platform of ['windows','macos']){
   clipboard={text:'Hello from the computer',html:'<b>Hello</b> from the computer'};uploads=[];
   const ctx=await browser.newContext({viewport:{width:390,height:600},hasTouch:true,isMobile:true,acceptDownloads:true}),page=await ctx.newPage(),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{Object.defineProperty(window,'isSecureContext',{value:false});document.execCommand=command=>{window.lastCopy={command,text:getSelection()?.toString(),value:document.activeElement?.value};return true;};});
   await page.goto(url);await page.locator('#commands').evaluate(b=>{b.disabled=false;});
   check(await page.locator('#commandsPane [data-tool]').count()===0,'shortcuts contain no keyboard entry');
   await page.locator('#commands').tap();await page.waitForSelector('#keyboardCopyActions button');
   check(await page.locator('#typeSink').isVisible(),'visible native type/paste field');
   check((await page.locator('#keyboardCopyActions button').allTextContents()).join('|')==='Aa|T','formatted and plain copy share the same row');
   await page.locator('#typeSink').fill('Hello 👋');
   check(await page.evaluate(()=>sent.some(c=>c.type==='text'&&c.text==='Hello 👋')),'Unicode typing');
   const modifier=platform==='macos'?8:2;await press(page,`[data-modifier="${modifier}"]`);await page.locator('#typeSink').fill('Hello 👋c');
   check(await page.evaluate(mask=>sent.some(c=>c.type==='key'&&c.id===14&&c.modifiers===mask),modifier),'native copy chord');
   check(await page.locator('[data-modifier][aria-pressed="true"]').count()===0,'one-shot modifier clears');
   await press(page,'[data-modifier="1"]');await press(page,'[data-modifier="2"]');await press(page,'[data-key="4"]');
   check(await page.evaluate(()=>sent.some(c=>c.type==='key'&&c.id===4&&c.modifiers===3)),'combined Ctrl+Shift+Left');
   await press(page,'[data-modifier="16"]');check(await page.locator('#functionKeys button').first().isVisible(),'Fn reveals F1–F12');await page.locator('[data-key="53"]').click();
   check(await page.evaluate(()=>sent.some(c=>c.type==='key'&&c.id===53&&c.modifiers===16)),'F5 with Fn');
   const before=await page.evaluate(()=>sent.filter(c=>c.type==='text').length);
   await page.locator('#typeSink').evaluate(node=>{const data=new DataTransfer();data.setData('text/plain','Pasted once');data.setData('text/html','<b>Pasted once</b>');node.dispatchEvent(new ClipboardEvent('paste',{clipboardData:data,bubbles:true,cancelable:true}));});
   await page.waitForFunction(()=>sent.some(c=>c.type==='shortcut'&&c.id===1));
   check(uploads.length===1&&uploads[0].manifest.map(p=>p.kind).join()==='text,html','native paste transfers text and formatting once');
   check(await page.evaluate(()=>sent.filter(c=>c.type==='text').length)===before,'paste is not also typed');
   check(await page.locator('#keyBar').isVisible(),'paste leaves keyboard panel open');
   await page.locator('#typeSink').evaluate(async node=>{
    const canvas=document.createElement('canvas');canvas.width=8;canvas.height=6;canvas.getContext('2d').fillRect(0,0,8,6);
    const photo=await new Promise(resolve=>canvas.toBlob(resolve,'image/png')),data=new DataTransfer();
    data.items.add(new File([photo],'Photo.png',{type:'image/png'}));data.items.add(new File(['%PDF-1.4 test'],'Notes.pdf',{type:'application/pdf'}));
    node.dispatchEvent(new ClipboardEvent('paste',{clipboardData:data,bubbles:true,cancelable:true}));
   });
   await page.waitForFunction(()=>sent.filter(c=>c.type==='shortcut'&&c.id===1).length===2);
   check(uploads.length===2&&uploads[1].manifest.map(p=>p.kind).join()==='image,file,file','native field accepts a photo and a file together');
   await page.locator('#keyboardCopyActions button').last().click();
   check(await page.evaluate(()=>lastCopy?.value==='Hello from the computer'),'plain copy uses the full text');
   clipboard={text:'https://example.com/watch?v=3'};await page.locator('#keyboardRefresh').click();await page.waitForSelector('#keyboardCopyActions button:text("Link")');
   check(await page.locator('#keyboardPreview').getAttribute('title')==='https://example.com/watch?v=3','link preview stays local');
   clipboard={image:{width:1,height:1,size:png.length}};await page.locator('#keyboardRefresh').click();await page.waitForSelector('#keyboardPreview img');
   const downloaded=page.waitForEvent('download');await page.locator('#keyboardCopyActions button').click();check((await downloaded).suggestedFilename()===(platform==='macos'?'Mac':'PC')+' picture.png','picture downloads with a preview');
   for(const file of ['Voice memo.m4a','Clip.mp4','Document.pdf']){
    clipboard={files:[{name:file,size:100,folder:false}]};await page.locator('#keyboardRefresh').click();await page.waitForFunction(()=>!document.getElementById('keyboardRefresh').disabled);
    check((await page.locator('#keyboardCopyActions button').allTextContents()).join()==='↓',file+' uses the same download action');
    if(file.endsWith('.m4a')||file.endsWith('.mp4')){
     const mime=await page.locator('#keyboardPreview audio,#keyboardPreview video').evaluate(async node=>(await (await fetch(node.src)).blob()).type);
     check(mime===(file.endsWith('.m4a')?'audio/mp4':'video/mp4'),'media preview has the correct MIME type');
    }
   }
   clipboard={text:'Select and copy this',html:'<b>Select</b> and copy this'};await page.locator('#keyboardRefresh').click();await page.waitForFunction(()=>!document.getElementById('keyboardRefresh').disabled);
   await page.locator('#keyboardPreview').click();check(await page.locator('#clipSheet').isVisible(),'preview expands');await page.locator('#clipClose').click();check(await page.locator('#keyBar').isVisible(),'preview Done returns to keyboard');
   for(const width of [320,390,844]){
    await page.setViewportSize({width,height:width===844?390:600});await page.waitForTimeout(80);
    check(await page.evaluate(()=>{const r=document.getElementById('keyBar').getBoundingClientRect();return r.left>=-1&&r.right<=innerWidth+1&&r.top>=-1&&r.bottom<=innerHeight+1&&r.height<=74&&document.getElementById('typeSink').getBoundingClientRect().width>=innerWidth*.44;}),'two-row panel stays under 74px with a wide field at '+width+'px');
    await page.screenshot({path:path.join(out,`${name}-${platform}-${width}.png`)});
   }
   await press(page,'[data-modifier="2"]');await page.evaluate(()=>{testConnected=false;ThreeEClip.connection(false);});
   check(await page.locator('#typeSink').getAttribute('aria-disabled')==='true'&&await page.locator('[data-modifier][aria-pressed="true"]').count()===0,'disconnect clears modifiers and marks typing unavailable without dropping focus');
   const sentBeforeDisconnect=await page.evaluate(()=>sent.length);await page.locator('#typeSink').evaluate(node=>{node.value='discard offline';node.dispatchEvent(new Event('input'));});
   check(await page.evaluate(()=>sent.length)===sentBeforeDisconnect&&await page.locator('#typeSink').inputValue()==='','offline typing is discarded instead of queued');
   await page.waitForTimeout(220);check(await page.locator('#keyBar').isVisible(),'brief reconnect does not dismiss the keyboard');
   await page.locator('#typeSink').evaluate(node=>node.blur());await page.waitForTimeout(220);check(await page.locator('#keyBar').isHidden(),'native blur dismisses the controls');
   check(await page.locator('#keyBar .done,[data-action="done"]').count()===0,'no Done button');
   await page.setViewportSize({width:390,height:600});
   await page.evaluate(()=>{testConnected=true;ThreeEClip.connection(true);});
   await page.locator('#commands').tap();await page.waitForSelector('#typeSink:visible');
   await page.evaluate(()=>{
    window.testViewportHeight=600;window.testViewportScale=1;
    Object.defineProperty(visualViewport,'height',{configurable:true,get:()=>testViewportHeight});
    Object.defineProperty(visualViewport,'scale',{configurable:true,get:()=>testViewportScale});
    testViewportHeight=350;visualViewport.dispatchEvent(new Event('resize'));
   });
   check(await page.locator('#keyBar').isVisible(),'keyboard shrink keeps controls visible');
   await page.evaluate(()=>{testViewportScale=1.2;testViewportHeight=600;visualViewport.dispatchEvent(new Event('resize'));});await page.waitForTimeout(220);
   check(await page.locator('#keyBar').isVisible(),'pinch zoom is not mistaken for keyboard dismissal');
   await page.evaluate(()=>{testViewportScale=1;testViewportHeight=350;visualViewport.dispatchEvent(new Event('resize'));testViewportHeight=600;visualViewport.dispatchEvent(new Event('resize'));});await page.waitForTimeout(220);
   check(await page.locator('#keyBar').isHidden(),'iPhone hide-keyboard viewport restoration dismisses the strip even with retained focus');
   await page.waitForTimeout(720);await page.locator('#commands').tap();
   await page.locator('#typeSink').evaluate(node=>node.blur());await page.waitForTimeout(220);
   check(await page.locator('#keyBar').isHidden(),'native keyboard blur dismisses the strip');
   await page.waitForTimeout(720);await page.locator('#commands').tap();
   await page.evaluate(()=>{document.getElementById('keyboardFile').click=()=>{};});
   await page.locator('#keyboardAttach').click();await page.locator('#typeSink').evaluate(node=>node.blur());await page.waitForTimeout(220);
   check(await page.locator('#keyBar').isVisible(),'file chooser does not prematurely dismiss the panel');
   await page.locator('#keyboardFile').dispatchEvent('cancel');
   check(await page.evaluate(()=>document.activeElement.id==='typeSink'),'cancelling file chooser restores typing');
   await page.evaluate(()=>ThreeEClip.close());await page.waitForTimeout(720);
   await page.locator('#commands').dispatchEvent('pointerdown',{pointerId:42});await page.waitForTimeout(450);
   check(await page.locator('#commandsPane').isVisible()&&await page.locator('#keyBar').isHidden(),'holding command opens shortcuts without a keyboard');
   await page.locator('#commands').dispatchEvent('pointerup',{pointerId:42});await page.waitForTimeout(60);
   check(await page.locator('#commandsPane').isVisible(),'lifting after a hold keeps shortcuts open');
   await page.locator('#commandsPane [data-shortcut="0"]').click();
   check(await page.evaluate(()=>sent.some(c=>c.type==='shortcut'&&c.id===0)),'held menu still sends shortcuts');

   check(errors.length===0,'no script errors: '+errors.join(';'));await ctx.close();
  }}finally{await browser.close();}
 }
 console.log(`PASS: ${checks} keyboard, clipboard, modifier, disconnect and responsive checks in Chromium and WebKit.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>server.close());
