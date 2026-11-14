// SPDX-License-Identifier: MIT
// Phone keyboard and two-way clipboard for the ⌘ palette's bottom row (Windows and Mac hosts).
(() => {
  'use strict';
  const C=window.ThreeEControl, $=id=>document.getElementById(id);
  const token=location.hash.slice(1), secure=window.isSecureContext;
  const mac=window.ThreeEHost?.platform==='macos', computer=mac?'Mac':'PC', pasteKeys=mac?'⌘V':'Ctrl+V';
  const cp=s=>Array.from(s).length;

  // ---------- Keyboard ----------
  // A visible native textarea keeps iOS typing, autocorrect and its Paste menu.
  const sink=$('typeSink'), bar=$('keyBar');
  let last='', caret=0, repeatTimer, repeatDelay, modifiers=0;
  let dismissTimer, noteTimer, filePicking=false, viewportBase=0, viewportWidth=0, keyboardSeen=false;
  const modifierButtons=[...bar.querySelectorAll('[data-modifier]')];
  const functions=$('functionKeys');
  for(let n=1;n<=12;n++){const b=document.createElement('button');b.type='button';b.dataset.key=48+n;b.textContent='F'+n;functions.append(b);}
  // Same Mac order on both hosts: fn, Control (Win on Windows), Option/Alt, ⌘.
  // Windows uses the Mac layout, so ⌘ sends Ctrl there.
  for(const [key,mask,label,name] of mac?[['m1',2,'⌃','Control'],['m2',4,'⌥','Option'],['m3',8,'⌘','Command']]:[['m1',8,'Win','Windows'],['m2',4,'Alt','Alt'],['m3',2,'⌘','Command (Ctrl)']]){
    const button=bar.querySelector('.k-'+key);button.dataset.modifier=mask;button.textContent=label;button.setAttribute('aria-label',name);button.title=name;
  }
  bar.dataset.modifiers=String(!!window.ThreeEHost?.keyboardModifiers);bar.dataset.mac=String(mac);
  sink.disabled=!window.ThreeEHost?.keyboard;
  function clearModifiers(){modifiers=0;drawModifiers();}
  function drawModifiers(){modifierButtons.forEach(b=>b.setAttribute('aria-pressed',String(!!(modifiers&+b.dataset.modifier))));functions.hidden=!(modifiers&16);bar.dataset.fn=String(!!(modifiers&16));placeBar();}
  function sendText(text){
    const chars=Array.from(text);let chunk='';
    for(const ch of chars){if(chunk.length+ch.length>120){C.send('text',{text:chunk});chunk='';}chunk+=ch;}
    if(chunk)C.send('text',{text:chunk});
  }
  function sendKey(id,n=1,mask=0){while(n>0){const step=Math.min(n,64);C.send('key',{id,n:step,...(mask?{modifiers:mask}:{})});n-=step;}}
  function arrows(delta){if(delta<0)sendKey(4,-delta);else if(delta>0)sendKey(6,delta);}
  function resetSink(){sink.value='';last='';caret=0;}
  const chordName=(mask,key)=>(mask&16?'fn ':'')+(mac?[[2,'⌃'],[4,'⌥'],[1,'⇧'],[8,'⌘']]:[[8,'Win+'],[2,'Ctrl+'],[4,'Alt+'],[1,'Shift+']]).filter(([m])=>mask&m).map(([,l])=>l).join('')+key;
  let swallowUntil=0;
  function chord(text){
    const ch=Array.from(text)[0]||'',lower=ch.toLowerCase();
    const id=/^[a-z]$/.test(lower)?12+lower.charCodeAt(0)-97:/^[0-9]$/.test(ch)?38+Number(ch):ch===' '?48:ch==='\n'?1:ch==='\t'?2:-1;
    if(id>=0&&C.connected()){sendKey(id,1,modifiers);say(chordName(modifiers,ch===' '?'Space':ch==='\n'?'Return':ch==='\t'?'Tab':ch.toUpperCase())+' sent');}
    else say('Use a letter, number, Space or a key above with modifiers.',true);
    clearModifiers();resetSink();
  }
  function sync(){
    if(!C.connected()){resetSink();return;}
    const cur=sink.value;if(cur===last)return;
    const max=Math.min(cur.length,last.length);let p=0,s=0;
    while(p<max&&cur.charCodeAt(p)===last.charCodeAt(p))p++;
    const after=Math.min(max-p,last.length-caret,cur.length-(sink.selectionEnd??cur.length));
    while(s<after&&cur.charCodeAt(cur.length-1-s)===last.charCodeAt(last.length-1-s))s++;
    if(p>0&&/[\ud800-\udbff]/.test(last[p-1]||''))p--;
    if(s>0&&/[\udc00-\udfff]/.test(last[last.length-s]||''))s--;
    const oldEnd=last.length-s,removed=last.slice(p,oldEnd),added=cur.slice(p,cur.length-s);
    if(modifiers){if(added)chord(added);else{sendKey(0,Math.max(1,cp(removed)),modifiers);clearModifiers();resetSink();}return;}
    if(C.connected()){
      arrows(cp(last.slice(caret,oldEnd))-cp(last.slice(oldEnd,caret)));
      if(removed)sendKey(0,cp(removed));if(added)sendText(added);
    }
    last=cur;caret=p+added.length;
    const now=sink.selectionStart??caret;
    if(now!==caret&&C.connected()){arrows(cp(cur.slice(caret,now))-cp(cur.slice(now,caret)));caret=now;}
    if(added.includes('\n')||cur.length>2000)resetSink();
  }
  // With a modifier latched, the next typed key is a shortcut (⌘A selects
  // all), never text: take it before Safari inserts the letter.
  sink.addEventListener('beforeinput',e=>{
    if(!modifiers||e.isComposing)return;
    const text=e.inputType==='insertText'?e.data:/^insert(LineBreak|Paragraph)$/.test(e.inputType)?'\n':null;
    if(!text)return;
    e.preventDefault();swallowUntil=performance.now()+400;chord(text);
  });
  sink.addEventListener('input',e=>{
    // If the browser inserted the letter anyway, it was already sent as a shortcut.
    if(performance.now()<swallowUntil){swallowUntil=0;sink.value='';resetSink();return;}
    if(!e.isComposing)sync();
  });
  sink.addEventListener('compositionend',sync);
  sink.addEventListener('keydown',e=>{
    if((e.key==='Backspace'||e.key==='Enter')&&!e.isComposing&&sink.value===''){
      e.preventDefault();if(C.connected())sendKey(e.key==='Backspace'?0:1,1,modifiers);clearModifiers();
    }
  });
  document.addEventListener('selectionchange',()=>{
    if(bar.hidden||document.activeElement!==sink||sink.value!==last||sink.selectionStart!==sink.selectionEnd)return;
    const now=sink.selectionStart;if(now===caret)return;
    if(C.connected())arrows(cp(last.slice(caret,now))-cp(last.slice(now,caret)));caret=now;
  });
  function placeBar(){
    const v=window.visualViewport;if(bar.hidden)return;
    if(v)bar.style.top=Math.max(v.offsetTop,v.offsetTop+v.height-bar.offsetHeight)+'px';
    else{bar.style.top='auto';bar.style.bottom='0';}
  }
  function viewportChanged(){
    placeBar();const v=window.visualViewport;if(bar.hidden||!v||Math.abs(v.scale-1)>.05)return;
    if(Math.abs(v.width-viewportWidth)>40){viewportWidth=v.width;viewportBase=Math.max(window.innerHeight,v.height);keyboardSeen=false;return;}
    const gap=viewportBase-v.height;
    if(gap>100){keyboardSeen=true;clearTimeout(dismissTimer);}
    // iOS can dismiss its keyboard while the textarea still has focus.
    // Browser chrome/pinch changes are too small (or scaled) to count.
    else if(keyboardSeen&&gap<70&&!filePicking&&!transferBusy){
      clearTimeout(dismissTimer);dismissTimer=setTimeout(()=>{if(!bar.hidden&&!filePicking&&!transferBusy&&viewportBase-v.height<70)closeKeyboard();},180);
    }
  }
  window.visualViewport?.addEventListener('resize',viewportChanged);
  window.visualViewport?.addEventListener('scroll',placeBar);
  function keyboard(){
    if(!C.connected())return;
    C.release();closeSheet();resetSink();clearModifiers();bar.hidden=false;
    clearTimeout(dismissTimer);clearTimeout(noteTimer);$('keyboardNote').textContent='';
    viewportBase=Math.max(window.innerHeight,window.visualViewport?.height||0);viewportWidth=window.visualViewport?.width||window.innerWidth;keyboardSeen=false;
    sink.focus({preventScroll:true});placeBar();setTimeout(placeBar,350);refreshClipboard();
  }
  function closeKeyboard(){clearTimeout(dismissTimer);clearTimeout(noteTimer);stopRepeat();clearModifiers();bar.hidden=true;keyboardSeen=false;filePicking=false;sink.blur();resetSink();closeSheet();clearInlineClipboard();}
  sink.addEventListener('blur',()=>{
    stopRepeat();clearTimeout(dismissTimer);
    dismissTimer=setTimeout(()=>{if(!bar.hidden&&!filePicking&&!transferBusy&&!bar.contains(document.activeElement))closeKeyboard();},180);
  });
  // Toolbar taps must keep iOS's typing focus; text selection and paste retain
  // their native touch behavior. A pointer-down cancellation does not cancel click.
  bar.addEventListener('pointerdown',e=>{if(e.target.closest('button'))e.preventDefault();});
  function stopRepeat(){clearTimeout(repeatDelay);clearInterval(repeatTimer);bar.querySelectorAll('.held').forEach(b=>b.classList.remove('held'));}
  for(const button of bar.querySelectorAll('[data-key],[data-modifier]')){
    button.addEventListener('mousedown',e=>e.preventDefault());
    if(!functions.contains(button))button.addEventListener('touchstart',e=>e.preventDefault(),{passive:false});
    function press(){
      stopRepeat();
      if(!C.connected())return;
      if(button.dataset.modifier){sync();modifiers^=+button.dataset.modifier;drawModifiers();return;}
      sync();const id=+button.dataset.key,mask=modifiers;button.classList.add('held');sendKey(id,1,mask);clearModifiers();resetSink();
      if([0,4,5,6,7,8].includes(id))repeatDelay=setTimeout(()=>{repeatTimer=setInterval(()=>{if(C.connected())sendKey(id,1,mask);else stopRepeat();},70);},420);
    }
    // One tap is one press: a click that follows the pointer press (some
    // iOS versions report it with detail 0) must not toggle ⌘ back off.
    let pressedAt=-Infinity;
    if(!functions.contains(button))button.addEventListener('pointerdown',e=>{e.preventDefault();pressedAt=performance.now();press();});
    button.addEventListener('click',e=>{if(functions.contains(button)||e.detail===0&&performance.now()-pressedAt>800)press();});
    for(const type of ['pointerup','pointercancel','pointerleave'])button.addEventListener(type,stopRepeat);
  }
  window.addEventListener('blur',()=>{stopRepeat();clearModifiers();});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stopRepeat();clearModifiers();}else if(!bar.hidden)refreshClipboard();});
  function connection(ready){
    // A temporary reconnect must not blur the field, dismiss iOS's keyboard,
    // or make the page think it is safe to reload while the user is typing.
    sink.disabled=!window.ThreeEHost?.keyboard;
    sink.setAttribute('aria-disabled',String(!ready||sink.disabled));
    if(!ready){stopRepeat();clearModifiers();resetSink();clearInlineClipboard();if(!bar.hidden)say('Reconnecting…',true);}
    else if(!bar.hidden)refreshClipboard();
  }

  // ---------- Clipboard ----------
  const sheet=$('clipSheet'), body=$('clipBody'), title=$('clipTitle'), note=$('clipNote');
  let returnToKeyboard=false;
  $('clipClose').addEventListener('click',()=>{const resume=returnToKeyboard;closeSheet();if(resume)keyboard();});
  function closeSheet(){clipGeneration++;transferBusy=false;sheet.hidden=true;clipRefresh.hidden=true;body.replaceChildren();note.textContent='';pending=null;urls.forEach(URL.revokeObjectURL);urls=[];}
  let pending=null, urls=[], clipGeneration=0, transferBusy=false;
  const el=(tag,props={},...kids)=>{const n=Object.assign(document.createElement(tag),props);n.append(...kids.filter(k=>k!=null));return n;};
  // Copy from the computer: refresh lives in this menu, not on the key bar.
  const clipRefresh=el('button',{type:'button',id:'clipRefresh',hidden:true,textContent:'↻'});
  clipRefresh.setAttribute('aria-label','Refresh clipboard');clipRefresh.title='Refresh clipboard';
  $('clipClose').before(clipRefresh);
  clipRefresh.addEventListener('click',()=>{const resume=returnToKeyboard;getClip();returnToKeyboard=resume;});
  const size=n=>n<1024?n+' B':n<1048576?(n/1024).toFixed(0)+' KB':(n/1048576).toFixed(1)+' MB';
  const say=(text,error=false)=>{const inline=sheet.hidden&&!bar.hidden,target=inline?$('keyboardNote'):note;target.textContent=text;target.classList.toggle('error',error);if(inline){clearTimeout(noteTimer);noteTimer=setTimeout(()=>{target.textContent='';},error?6000:2500);}};
  const failure={401:'Pairing expired — scan a new QR code.',403:'Pairing expired — scan a new QR code.',409:'Connect the trackpad first.',413:'Too large — 200 MB maximum.',501:'This computer does not support clipboard transfer.'};
  async function post(path,options){
    const res=await fetch(path,{method:'POST',cache:'no-store',...options,headers:{'X-Trackpad-Token':token,...(options.headers||{})}});
    if(!res.ok){let message=failure[res.status];try{message=(await res.json()).error||message;}catch{}throw new Error(message||'The '+computer+' could not complete the transfer.');}
    return res;
  }
  const postJson=(path,data)=>post(path,{headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  function open(name){
    if(!C.connected())return false;
    returnToKeyboard=!bar.hidden;
    C.release();bar.hidden=true;sink.blur();stopRepeat();clearModifiers();clearInlineClipboard();closeSheet();title.textContent=name;sheet.hidden=false;return true;
  }

  // Phone → computer. Plain-HTTP pages cannot read the clipboard directly, so the
  // system Paste menu (or a picker) hands the content to this page instead.
  async function pngOf(file){
    let source;
    try{source=await createImageBitmap(file);}
    catch{source=await new Promise((resolve,reject)=>{const url=URL.createObjectURL(file),image=new Image();image.onload=()=>{URL.revokeObjectURL(url);resolve(image);};image.onerror=()=>{URL.revokeObjectURL(url);reject(new Error('image'));};image.src=url;});}
    const w=source.width||source.naturalWidth,h=source.height||source.naturalHeight;
    const scale=Math.min(1,Math.sqrt(16e6/(w*h))); // Safari canvas area limit
    const canvas=el('canvas',{width:Math.max(1,Math.round(w*scale)),height:Math.max(1,Math.round(h*scale))});
    canvas.getContext('2d').drawImage(source,0,0,canvas.width,canvas.height);source.close?.();
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
    if(!blob)throw new Error('image');
    return {blob,width:canvas.width,height:canvas.height};
  }
  async function stage({text='',html='',files=[]},generation=clipGeneration){
    pending=null;
    if(files.length&&html&&!text.trim())html=''; // an image paste's HTML is just a placeholder <img>
    const parts=[],rows=[];
    if(text){parts.push({kind:'text',blob:new Blob([text])});rows.push(el('li',{},el('strong',{textContent:'Text'}),' · '+cp(text)+' characters',el('span',{className:'clip-snippet',textContent:text.slice(0,160)})));}
    if(html){parts.push({kind:'html',blob:new Blob([html])});rows.push(el('li',{},el('strong',{textContent:'Formatting'}),' · kept for apps that accept rich text'));}
    const images=files.filter(f=>/^image\//.test(f.type)), others=files.filter(f=>!/^image\//.test(f.type));
    if(images.length){
      say('Preparing picture…');
      try{
        const png=await pngOf(images[0]);
        parts.push({kind:'image',name:'Phone picture.png',blob:png.blob});
        const url=URL.createObjectURL(png.blob);urls.push(url);
        rows.push(el('li',{},el('strong',{textContent:'Picture'}),` · ${png.width}×${png.height}`,el('img',{src:url,alt:'',className:'clip-thumb'})));
      }catch{others.unshift(images[0]);}
      say('');
    }
    // With several items, everything also travels as files (paste into a folder or an email).
    const asFiles=others.length?[...images,...others]:images.slice(1);
    for(const file of asFiles){parts.push({kind:'file',name:file.name||'Phone file',blob:file});rows.push(el('li',{},el('strong',{textContent:file.name||'File'}),' · '+size(file.size)));}
    if(!parts.length){say('Nothing to send — that item has no text, picture or file the page can read.',true);return;}
    const total=parts.reduce((n,p)=>n+p.blob.size,0);
    if(total>200*1048576){say('Too large — 200 MB maximum.',true);return;}
    if(generation!==clipGeneration||(sheet.hidden&&bar.hidden))return;
    pending=parts;
    $('clipPreview')?.replaceChildren(el('ul',{className:'clip-list'},...rows));
    say('');
  }
  async function upload(paste){
    if(!pending)return;
    const generation=clipGeneration, parts=pending, manifest=parts.map(p=>({kind:p.kind,name:p.name||'',size:p.blob.size}));
    const bytes=new TextEncoder().encode(JSON.stringify(manifest));let binary='';bytes.forEach(b=>binary+=String.fromCharCode(b));
    if(binary.length>9000||parts.length>64){say('Too many files at once — send fewer.',true);return;}
    for(const b of ($('clipActions')?.querySelectorAll('button')||[]))b.disabled=true;say('Sending…');
    try{
      await post('/clipboard/write',{headers:{'Content-Type':'application/octet-stream','X-Clip-Manifest':btoa(binary)},body:new Blob(parts.map(p=>p.blob))});
      if(generation!==clipGeneration||(sheet.hidden&&bar.hidden))return;
      if(paste){C.release();if(!C.connected()||!C.send('shortcut',{id:1})){say('On the '+computer+' clipboard. Reconnect before pasting.');return;}}
      say(paste?'Pasted on the '+computer+'.':'On the '+computer+' clipboard — press '+pasteKeys+' where you want it.');
      setTimeout(()=>{if(!sheet.hidden&&pending===parts)closeSheet();},900);
    }catch(e){if(generation!==clipGeneration)return;say(e.message,true);if($('clipActions'))$('clipActions').hidden=false;for(const b of ($('clipActions')?.querySelectorAll('button')||[]))b.disabled=false;}
  }
  async function sendClip(){
    if(!open('Paste on '+computer))return;
    const generation=clipGeneration;
    // This small native-paste target is needed only when the browser cannot
    // read the clipboard. Content goes straight to the host, without staging.
    const zone=el('div',{className:'clip-paste',contentEditable:'true',role:'textbox',ariaLabel:'Paste from phone'});
    zone.setAttribute('inputmode','none');zone.dataset.placeholder='Touch and hold → Paste';
    zone.addEventListener('beforeinput',e=>{if(e.inputType!=='insertFromPaste')e.preventDefault();});
    async function receive(data){
      if(transferBusy||generation!==clipGeneration)return;
      transferBusy=true;
      try{await stage(data,generation);if(generation===clipGeneration&&pending)await upload(true);}
      catch(e){if(generation===clipGeneration)say(e.message||'Could not read that item.',true);}
      finally{if(generation===clipGeneration)transferBusy=false;}
    }
    zone.addEventListener('paste',e=>{
      e.preventDefault();const data=e.clipboardData;if(!data)return;
      let files=[...(data.files||[])];
      if(!files.length)for(const item of data.items||[])if(item.kind==='file'){const f=item.getAsFile();if(f)files.push(f);}
      zone.blur();receive({text:data.getData('text/plain'),html:data.getData('text/html'),files});
    });
    const picker=el('input',{type:'file',multiple:true,hidden:true});
    picker.addEventListener('change',()=>{if(picker.files.length)receive({files:[...picker.files]});});
    const choose=el('button',{type:'button',textContent:'Choose photo or file'});choose.addEventListener('click',()=>picker.click());
    const retry=el('button',{type:'button',className:'primary',textContent:'Retry paste'});retry.addEventListener('click',()=>upload(true));
    const fallback=el('div',{},el('p',{textContent:'Choose Paste in your phone’s menu. It will paste on the '+computer+' immediately.'}),zone,el('div',{className:'row'},choose),picker);
    body.append(fallback,el('div',{id:'clipActions',className:'row',hidden:true},retry));
    if(secure&&navigator.clipboard?.read){
      fallback.hidden=true;say('Reading phone clipboard…');
      try{
        // Start inside the original tap so Safari retains user activation.
        const items=await navigator.clipboard.read();let text='',html='';const files=[];
        for(const item of items)for(const type of item.types){const blob=await item.getType(type);
          if(type==='text/plain')text=await blob.text();else if(type==='text/html')html=await blob.text();
          else files.push(new File([blob],type.startsWith('image/')?'Phone picture.'+type.split('/')[1]:'Phone file',{type}));}
        if(generation!==clipGeneration)return;
        fallback.hidden=false;await receive({text,html,files});
      }catch{if(generation!==clipGeneration)return;fallback.hidden=false;say('Use your phone’s Paste menu to continue.');zone.focus({preventScroll:true});}
    }else zone.focus({preventScroll:true});
  }

  // Computer → phone. Copying uses the page's selection (works over plain HTTP);
  // pictures use the system menu: touch and hold → Copy or Save to Photos.
  function cleanHtml(html){
    const doc=new DOMParser().parseFromString(html,'text/html');
    doc.querySelectorAll('script,style,link,meta,base,title,iframe,frame,object,embed,form,input,button,textarea,select,svg,math').forEach(n=>n.remove());
    for(const node of doc.body.querySelectorAll('*'))for(const a of [...node.attributes]){
      const v=a.value.trim();
      if(/^on/i.test(a.name)||/^(srcset|action|formaction|xlink:href|background)$/i.test(a.name)||
        (a.name==='src'&&!/^data:image\//i.test(v))||(a.name==='href'&&!/^(https?:|mailto:|#)/i.test(v)))node.removeAttribute(a.name);
    }
    return [...doc.body.childNodes].map(n=>document.importNode(n,true));
  }
  function copySelection(node,editable){
    const selection=getSelection(),range=document.createRange();
    if(editable)node.contentEditable='true';
    range.selectNodeContents(node);selection.removeAllRanges();selection.addRange(range);
    let ok=false;try{ok=document.execCommand('copy');}catch{}
    selection.removeAllRanges();if(editable)node.contentEditable='false';
    return ok;
  }
  function copyButton(label,action){
    const button=el('button',{type:'button',className:'primary',textContent:label});
    button.addEventListener('click',async()=>{const ok=await action();say(ok?'Copied to your phone.':'Copy was blocked — select it and use the Copy menu.',!ok);});
    return button;
  }
  async function download(name,blob){
    const url=URL.createObjectURL(blob);urls.push(url);
    const link=el('a',{href:url,download:name});document.body.append(link);link.click();link.remove();
  }
  async function getClip(){
    if(!open('Copy from '+computer))return;
    clipRefresh.hidden=false;
    const generation=clipGeneration;
    say('Reading the '+computer+' clipboard…');
    let info;
    try{info=await (await postJson('/clipboard/read',{})).json();}catch(e){say(e.message,true);return;}
    if(sheet.hidden||generation!==clipGeneration)return;say('');
    let any=false;
    if(info.html||info.text){
      // One menu for text: copy with or without formatting, then the preview.
      any=true;const actions=el('div',{className:'row'});
      const plain=info.text||'',link=/^https?:\/\/\S+$/i.test(plain.trim());
      let rich=null;
      if(info.html){
        rich=el('div',{className:'clip-rich'});rich.append(...cleanHtml(info.html));
        actions.append(copyButton('Copy with formatting',async()=>{
          if(secure&&navigator.clipboard?.write&&window.ClipboardItem){try{await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([rich.innerHTML],{type:'text/html'}),'text/plain':new Blob([plain||rich.innerText],{type:'text/plain'})})]);return true;}catch{}}
          return copySelection(rich,true);
        }));
      }
      const area=el('textarea',{readOnly:true,value:plain||rich?.innerText||'',className:'clip-text',hidden:!!rich});
      const copyPlain=copyButton(rich?'Copy without formatting':link?'Copy link':'Copy text',async()=>{
        if(secure&&navigator.clipboard?.writeText){try{await navigator.clipboard.writeText(area.value);return true;}catch{}}
        area.hidden=false;area.focus();area.select();area.setSelectionRange(0,area.value.length);
        let ok=false;try{ok=document.execCommand('copy');}catch{}area.blur();if(rich)area.hidden=true;return ok;
      });
      if(rich)copyPlain.classList.remove('primary');
      actions.append(copyPlain);
      body.append(el('h2',{textContent:rich?'Formatted text':link?'Link':'Text'}),actions,rich,area);
    }
    if(info.image){
      any=true;const holder=el('div',{className:'clip-image'},el('span',{textContent:'Loading picture…'}));
      body.append(el('h2',{textContent:`Picture · ${info.image.width}×${info.image.height}`}),holder);
      try{
        const blob=await (await postJson('/clipboard/item',{index:-1})).blob();
        if(sheet.hidden||generation!==clipGeneration)return;
        const url=URL.createObjectURL(blob);urls.push(url);
        const image=el('img',{src:url,alt:'Picture from the '+computer+' clipboard'});
        const actions=el('div',{className:'row'});
        if(secure&&navigator.clipboard?.write&&window.ClipboardItem)actions.append(copyButton('Copy picture',async()=>{try{await navigator.clipboard.write([new ClipboardItem({'image/png':blob})]);return true;}catch{return false;}}));
        const save=el('button',{type:'button',textContent:'Download'});save.addEventListener('click',()=>download(computer+' picture.png',blob));actions.append(save);
        holder.replaceChildren(image,el('small',{textContent:'Touch and hold the picture → Copy, or Save to Photos.'}),actions);
      }catch(e){holder.replaceChildren(el('span',{className:'error',textContent:e.message}));}
    }
    if(info.files?.length){
      any=true;const list=el('ul',{className:'clip-list'});
      info.files.forEach((file,index)=>{
        const row=el('li',{},el('strong',{textContent:file.name}),file.folder?' · folder (not transferable)':file.size>=0?' · '+size(file.size):' · unavailable');
        if(!file.folder&&file.size>=0){
          const get=el('button',{type:'button',textContent:'Download'});
          get.addEventListener('click',async()=>{
            get.disabled=true;get.textContent='Downloading…';
            try{const blob=await (await postJson('/clipboard/item',{index})).blob();
              if(secure&&navigator.canShare?.({files:[new File([blob],file.name)]})){await navigator.share({files:[new File([blob],file.name,{type:blob.type})]});}
              else await download(file.name,blob);
              get.textContent='Downloaded';}
            catch(e){say(e.message,true);get.textContent='Download';get.disabled=false;}
          });
          row.append(get);
        }
        list.append(row);
      });
      body.append(el('h2',{textContent:info.files.length===1?'File':'Files'}),list);
    }
    if(!any)say('The '+computer+' clipboard is empty, or holds something the phone cannot use.');
  }

  // Clipboard controls share the keyboard surface. Read only while the user
  // opens/refreshes it; opening this panel never reads the phone clipboard.
  const preview=$('keyboardPreview');
  let inlineGeneration=0,inlineUrls=[],inlineReading=false;
  function clearInlineClipboard(){inlineGeneration++;inlineUrls.forEach(URL.revokeObjectURL);inlineUrls=[];preview.replaceChildren();}
  function inlineLive(generation){return generation===inlineGeneration&&!bar.hidden;}
  const mediaType=name=>/\.(png|jpe?g|gif|webp|heic)$/i.test(name)?'image':/\.(mp4|mov|m4v|webm)$/i.test(name)?'video':/\.(mp3|m4a|aac|wav|ogg|flac)$/i.test(name)?'audio':'file';
  const mediaMime=name=>({png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',gif:'image/gif',webp:'image/webp',heic:'image/heic',mp4:'video/mp4',mov:'video/quicktime',m4v:'video/mp4',webm:'video/webm',mp3:'audio/mpeg',m4a:'audio/mp4',aac:'audio/aac',wav:'audio/wav',ogg:'audio/ogg',flac:'audio/flac'}[name.split('.').pop().toLowerCase()]||'application/octet-stream');
  // The key bar shows only a preview of the computer clipboard. Tapping it
  // opens the Copy menu (formatted/plain copy, downloads, refresh). It is
  // re-read whenever the keyboard opens or the page returns to the front.
  let readAgain=false;
  async function refreshClipboard(){
    // A request during a read runs once that read finishes, so the preview
    // never keeps showing an older clipboard.
    if(inlineReading){readAgain=true;return;}
    if(bar.hidden||transferBusy||!C.connected())return;
    clearInlineClipboard();const generation=inlineGeneration;
    if(!window.ThreeEHost?.clipboard){preview.textContent='Clipboard unavailable';preview.dataset.state='empty';return;}
    inlineReading=true;preview.dataset.state='reading';preview.title='Reading clipboard…';
    try{
      const info=await (await postJson('/clipboard/read',{})).json();if(!inlineLive(generation))return;
      preview.replaceChildren();
      const files=info.files||[],text=info.text||'',rich=info.html?el('div'):null;
      if(rich)rich.append(...cleanHtml(info.html));
      preview.title=files.length?files.map(f=>f.name).join(', '):info.image?'Picture':text||rich?.textContent||'Clipboard is empty';
      preview.dataset.state=files.length>1?'files':files.length||info.image?'media':text||rich?'text':'empty';
      if(files.length===1||info.image){
        const file=files[0],isImage=!file,kind=isImage?'image':mediaType(file.name);
        preview.append(el('span',{className:'clipboard-snippet',textContent:isImage?'Picture':file.name}));
        // Small media thumbnails only; large files stay a deliberate download in the menu.
        if(kind!=='file'&&!(file&&(file.folder||file.size<0))&&(isImage?info.image.size:file.size)<=8*1048576){
          try{const blob=await (await postJson('/clipboard/item',{index:isImage?-1:0})).blob();if(!inlineLive(generation))return;
            const url=URL.createObjectURL(isImage?blob:blob.slice(0,blob.size,mediaMime(file.name)));inlineUrls.push(url);
            const media=el(kind==='image'?'img':kind,{src:url});
            if(kind==='image')media.alt='';
            else{media.preload='metadata';media.controls=kind==='audio';media.setAttribute('playsinline','');media.muted=kind==='video';}
            preview.prepend(media);
          }catch{}
        }
      }else if(files.length)preview.append(el('span',{className:'clipboard-snippet',textContent:files.length+' files'}));
      else if(text||rich)preview.append(el('span',{className:'clipboard-snippet',textContent:text||rich.textContent}));
    }catch(e){if(inlineLive(generation)){preview.dataset.state='error';preview.title='Could not read clipboard';say(e.message,true);}}
    finally{inlineReading=false;placeBar();if(readAgain){readAgain=false;refreshClipboard();}}
  }  preview.addEventListener('click',()=>{if(!inlineReading&&!transferBusy)getClip();});
  preview.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();if(!inlineReading&&!transferBusy)getClip();}});
  async function receiveInline(data){
    if(!C.connected()||transferBusy)return;
    clearModifiers();resetSink();transferBusy=true;const generation=clipGeneration;
    try{await stage(data,generation);if(generation===clipGeneration&&pending)await upload(true);}
    catch(e){if(generation===clipGeneration)say(e.message||'Could not paste that item.',true);}
    finally{transferBusy=false;if(!bar.hidden){sink.focus({preventScroll:true});placeBar();}}
  }
  sink.addEventListener('paste',e=>{
    const data=e.clipboardData;if(!data)return;e.preventDefault();
    let files=[...(data.files||[])];if(!files.length)for(const item of data.items||[])if(item.kind==='file'){const f=item.getAsFile();if(f)files.push(f);}
    receiveInline({text:data.getData('text/plain'),html:data.getData('text/html'),files});
  });
  $('keyboardAttach').addEventListener('click',()=>{filePicking=true;clearTimeout(dismissTimer);$('keyboardFile').click();});
  $('keyboardFile').addEventListener('change',()=>{filePicking=false;const input=$('keyboardFile');if(input.files.length)receiveInline({files:[...input.files]});input.value='';});
  $('keyboardFile').addEventListener('cancel',()=>{filePicking=false;if(!bar.hidden)sink.focus({preventScroll:true});});

  window.ThreeEClip={keyboard,sendClip,getClip,close:closeKeyboard,connection};
})();
