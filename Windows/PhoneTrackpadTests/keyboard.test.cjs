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
 for(const [name,engine] of [['chromium',chromium],['webkit',webkit]].filter(([name])=>!process.env.PLAYWRIGHT_ENGINE||process.env.PLAYWRIGHT_ENGINE===name)){
  const browser=await engine.launch({headless:true,executablePath:process.env['PLAYWRIGHT_'+name.toUpperCase()+'_PATH']||undefined});
  try{for(platform of ['windows','macos']){
   clipboard={text:'Hello from the computer',html:'<b>Hello</b> from the computer'};uploads=[];
   const ctx=await browser.newContext({viewport:{width:390,height:600},hasTouch:true,isMobile:true,acceptDownloads:true}),page=await ctx.newPage(),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{Object.defineProperty(window,'isSecureContext',{value:false});document.execCommand=command=>{window.lastCopy={command,text:getSelection()?.toString(),value:document.activeElement?.value};return true;};});
   await page.goto(url);await page.locator('#commands').evaluate(b=>{b.disabled=false;});
   check(await page.locator('#commandsPane [data-tool]').count()===0,'shortcuts contain no keyboard entry');
   await page.locator('#commands').tap();await page.waitForSelector('#keyboardPreview[data-state=text]');
   check(await page.locator('#typeSink').isVisible(),'visible native type/paste field');
   check(await page.locator('#keyBar [data-key="0"],#keyBar [data-key="1"],#keyboardRefresh,#keyboardCopyActions').count()===0,'no Backspace, Enter, refresh or inline copy buttons on the bar');
   const box=s=>page.locator('#keyBar '+s).boundingBox();
   const [fn,m1,m2,m3,up,down,left,right]=await Promise.all(['.k-fn','.k-m1','.k-m2','.k-m3','.k-up','.k-down','.k-left','.k-right'].map(box));
   const [esc,attach,clip,sink]=await Promise.all(['.k-esc','#keyboardAttach','#keyboardPreview','#typeSink'].map(box));
   const [shift,tab]=await Promise.all(['.k-shift','.k-tab'].map(box)),row=[fn,m1,m2,m3,esc,shift,tab,clip,up,attach],gaps=row.slice(1).map((b,i)=>b.x-(row[i].x+row[i].width));
   check(await page.locator('#keyBar .k-del,#keyBar [data-key="8"]').count()===0,'no Del key');
   check(row.every((b,i)=>!i||row[i-1].x<b.x)&&row.every(b=>Math.abs(b.y-esc.y)<1),'one row of keys: fn Control/Win Option/Alt ⌘ Esc ⇧ Tab, clipboard ▲ +');
   check(Math.max(...gaps)-Math.min(...gaps)<1&&row.every(b=>Math.abs(b.width-fn.width)<1),'top row keys are evenly sized and spaced');
   check(clip.x+clip.width<=up.x&&up.x+up.width<=attach.x&&Math.abs(clip.y-up.y)<1&&Math.abs(attach.y-up.y)<1,'clipboard and + flank ▲ in the key row');
   check(sink.x<=fn.x+1&&sink.x+sink.width<=left.x&&Math.abs(left.y-sink.y)<1,'full-width field with ◀ ▼ ▶ to its right');
   check(Math.abs((up.x+up.width/2)-(down.x+down.width/2))<1&&up.y+up.height<=down.y&&Math.abs(left.y-down.y)<1&&left.x<down.x&&down.x<right.x,'arrows form an inverted T');
   check(await page.locator('#keyBar .k-m3').textContent()==='⌘'&&await page.locator('#keyBar .k-m1').textContent()===(platform==='macos'?'⌃':'Win'),'Mac-layout modifier labels');
   await page.locator('#keyboardPreview').click();await page.waitForSelector('#clipSheet button:text("Copy without formatting")');
   check((await page.locator('#clipSheet .row button').allTextContents()).join('|')==='Copy with formatting|Copy without formatting','one menu copies with or without formatting');
   check(await page.locator('#clipRefresh').isVisible(),'refresh lives in the copy menu');
   await page.locator('#clipClose').click();await page.waitForSelector('#typeSink:visible');
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
   const reread=async expected=>{await page.evaluate(()=>ThreeEClip.keyboard());await page.waitForFunction(()=>{const p=document.getElementById('keyboardPreview');return p.dataset.state!=='reading'&&p.title!=='Reading clipboard…';});await page.waitForTimeout(150);await page.waitForFunction(()=>document.getElementById('keyboardPreview').dataset.state!=='reading');};
   const menu=async()=>{await page.locator('#keyboardPreview').click();await page.waitForFunction(()=>!document.getElementById('clipSheet').hidden&&!/Reading/.test(document.getElementById('clipNote').textContent));};
   const back=async()=>{await page.locator('#clipClose').click();await page.waitForSelector('#typeSink:visible');};
   await menu();await page.locator('#clipSheet button:text("Copy without formatting")').click();
   check(await page.evaluate(()=>lastCopy?.value==='Hello from the computer'),'plain copy uses the full text');await back();
   clipboard={text:'https://example.com/watch?v=3'};await reread();
   check(await page.locator('#keyboardPreview').getAttribute('title')==='https://example.com/watch?v=3','link preview stays local');
   await menu();check(await page.locator('#clipSheet button:text("Copy link")').count()===1,'links offer Copy link');await back();
   clipboard={image:{width:1,height:1,size:png.length}};await reread();await page.waitForSelector('#keyboardPreview img');
   await menu();await page.waitForSelector('#clipSheet .clip-image button:text("Download")');
   const downloaded=page.waitForEvent('download');await page.locator('#clipSheet .clip-image button:text("Download")').click();check((await downloaded).suggestedFilename()===(platform==='macos'?'Mac':'PC')+' picture.png','picture downloads from the menu');await back();
   for(const file of ['Voice memo.m4a','Clip.mp4','Document.pdf']){
    clipboard={files:[{name:file,size:100,folder:false}]};await reread();
    await menu();check(await page.locator('#clipSheet .clip-list button:text("Download")').count()===1,file+' downloads from the menu');await back();
    if(file.endsWith('.m4a')||file.endsWith('.mp4')){
     const mime=await page.locator('#keyboardPreview audio,#keyboardPreview video').evaluate(async node=>(await (await fetch(node.src)).blob()).type);
     check(mime===(file.endsWith('.m4a')?'audio/mp4':'video/mp4'),'media preview has the correct MIME type');
    }
   }
   clipboard={text:'Select and copy this',html:'<b>Select</b> and copy this'};await reread();
   await page.locator('#keyboardPreview').click();check(await page.locator('#clipSheet').isVisible(),'preview expands');await page.locator('#clipClose').click();check(await page.locator('#keyBar').isVisible(),'preview Done returns to keyboard');
   for(const width of [320,390,844]){
    await page.setViewportSize({width,height:width===844?390:600});await page.waitForTimeout(80);
    check(await page.evaluate(()=>{const r=document.getElementById('keyBar').getBoundingClientRect();return r.left>=-1&&r.right<=innerWidth+1&&r.top>=-1&&r.bottom<=innerHeight+1&&r.height<=74&&document.getElementById('typeSink').getBoundingClientRect().width>=innerWidth*.44;}),'one key row plus the field stays under 74px with a wide field at '+width+'px');
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

   check(errors.length===0,'no script errors: '+errors.join(';'));console.log(`PASS: ${name} ${platform} keyboard and clipboard (${checks} checks so far)`);await ctx.close();
  }}finally{await browser.close();}
 }
 console.log(`PASS: ${checks} keyboard, clipboard, modifier, disconnect and responsive checks.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>server.close());
