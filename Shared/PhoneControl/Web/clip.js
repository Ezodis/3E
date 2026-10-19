// SPDX-License-Identifier: MIT
// Phone keyboard and two-way clipboard for the ⌘ palette's bottom row (Windows and Mac hosts).
(() => {
  'use strict';
  const C=window.ThreeEControl, $=id=>document.getElementById(id);
  const token=location.hash.slice(1), secure=window.isSecureContext;
  const mac=window.ThreeEHost?.platform==='macos', computer=mac?'Mac':'PC', pasteKeys=mac?'⌘V':'Ctrl+V';
  const cp=s=>Array.from(s).length;

  // ---------- Keyboard ----------
  // A hidden textarea mirrors what the phone keyboard types. Each change is
  // diffed against the previous value and replayed on the computer as backspaces,
  // text and arrow moves, so autocorrect, predictions, dictation and the
  // space-bar cursor all carry over. The computer is assumed to follow our caret.
  const sink=$('typeSink'), bar=$('keyBar');
  let last='', caret=0, repeatTimer, repeatDelay;
  function sendText(text){
    // Control messages are capped at 1 KB: send short chunks, never splitting a surrogate pair.
    const chars=Array.from(text);let chunk='';
    for(const ch of chars){if(chunk.length+ch.length>120){C.send('text',{text:chunk});chunk='';}chunk+=ch;}
    if(chunk)C.send('text',{text:chunk});
  }
  function sendKey(id,n=1){while(n>0){const step=Math.min(n,64);C.send('key',{id,n:step});n-=step;}}
  function arrows(delta){if(delta<0)sendKey(4,-delta);else if(delta>0)sendKey(6,delta);}
  function resetSink(){sink.value='';last='';caret=0;}
  function sync(){
    const cur=sink.value;if(cur===last)return;
    const max=Math.min(cur.length,last.length);let p=0,s=0;
    while(p<max&&cur.charCodeAt(p)===last.charCodeAt(p))p++;
    // Text after the caret is unchanged by typing: never let the edit extend
    // past either caret, so autocorrect at the end becomes plain backspaces.
    const after=Math.min(max-p,last.length-caret,cur.length-(sink.selectionEnd??cur.length));
    while(s<after&&cur.charCodeAt(cur.length-1-s)===last.charCodeAt(last.length-1-s))s++;
    // Keep surrogate pairs whole on both edges.
    if(p>0&&/[\ud800-\udbff]/.test(last[p-1]||''))p--;
    if(s>0&&/[\udc00-\udfff]/.test(last[last.length-s]||''))s--;
    const oldEnd=last.length-s, removed=last.slice(p,oldEnd), added=cur.slice(p,cur.length-s);
    if(C.connected()){
      arrows(cp(last.slice(caret,oldEnd))-cp(last.slice(oldEnd,caret)));
      if(removed)sendKey(0,cp(removed));
      if(added)sendText(added);
    }
    last=cur;caret=p+added.length;
    const now=sink.selectionStart??caret;
    if(now!==caret&&C.connected()){arrows(cp(cur.slice(caret,now))-cp(cur.slice(now,caret)));caret=now;}
    // A new line starts a fresh buffer; a long one is trimmed so diffs stay cheap.
    if(added.includes('\n')||cur.length>2000)resetSink();
  }
  sink.addEventListener('input',sync);
  sink.addEventListener('keydown',e=>{
    // Backspace in an empty buffer produces no input event; forward it directly.
    if(e.key==='Backspace'&&sink.value===''){e.preventDefault();if(C.connected())sendKey(0);}
    else if(e.key==='Enter'&&!e.isComposing&&sink.value===''){e.preventDefault();if(C.connected())sendKey(1);}
  });
  document.addEventListener('selectionchange',()=>{
    if(document.activeElement!==sink||sink.value!==last||sink.selectionStart!==sink.selectionEnd)return;
    const now=sink.selectionStart;if(now===caret)return;
    if(C.connected())arrows(cp(last.slice(caret,now))-cp(last.slice(now,caret)));
    caret=now;
  });
  function placeBar(){
    const v=window.visualViewport;if(bar.hidden)return;
    if(v)bar.style.top=Math.max(0,v.offsetTop+v.height-bar.offsetHeight)+'px';
    else{bar.style.top='auto';bar.style.bottom='0';}
  }
  window.visualViewport?.addEventListener('resize',placeBar);
  window.visualViewport?.addEventListener('scroll',placeBar);
  function keyboard(){
    if(!C.connected())return;
    C.release();resetSink();bar.hidden=false;
    sink.focus({preventScroll:true});placeBar();setTimeout(placeBar,350);
  }
  sink.addEventListener('blur',()=>{bar.hidden=true;stopRepeat();resetSink();});
  function stopRepeat(){clearTimeout(repeatDelay);clearInterval(repeatTimer);bar.querySelectorAll('.held').forEach(b=>b.classList.remove('held'));}
  for(const button of bar.querySelectorAll('button')){
    const keep=e=>e.preventDefault();
    button.addEventListener('mousedown',keep);
    button.addEventListener('touchstart',keep,{passive:false});
    button.addEventListener('pointerdown',e=>{
      e.preventDefault();stopRepeat();
      if(button.dataset.action==='done'){sink.blur();return;}
      if(!C.connected())return;
      const id=+button.dataset.key;button.classList.add('held');
      // Typed text not yet replayed is flushed so the key lands after it.
      sync();sendKey(id);
      if(id===1)resetSink();
      if([0,4,5,6,7,8].includes(id))repeatDelay=setTimeout(()=>{repeatTimer=setInterval(()=>sendKey(id),70);},420);
    });
    for(const type of ['pointerup','pointercancel','pointerleave'])button.addEventListener(type,stopRepeat);
  }

  // ---------- Clipboard ----------
  const sheet=$('clipSheet'), body=$('clipBody'), title=$('clipTitle'), note=$('clipNote');
  $('clipClose').addEventListener('click',()=>closeSheet());
  function closeSheet(){clipGeneration++;transferBusy=false;sheet.hidden=true;body.replaceChildren();note.textContent='';pending=null;urls.forEach(URL.revokeObjectURL);urls=[];}
  let pending=null, urls=[], clipGeneration=0, transferBusy=false;
  const el=(tag,props={},...kids)=>{const n=Object.assign(document.createElement(tag),props);n.append(...kids.filter(k=>k!=null));return n;};
  const size=n=>n<1024?n+' B':n<1048576?(n/1024).toFixed(0)+' KB':(n/1048576).toFixed(1)+' MB';
  const say=(text,error=false)=>{note.textContent=text;note.classList.toggle('error',error);};
  const failure={401:'Pairing expired — scan a new QR code.',403:'Pairing expired — scan a new QR code.',409:'Connect the trackpad first.',413:'Too large — 200 MB maximum.',501:'This computer does not support clipboard transfer.'};
  async function post(path,options){
    const res=await fetch(path,{method:'POST',cache:'no-store',...options,headers:{'X-Trackpad-Token':token,...(options.headers||{})}});
    if(!res.ok){let message=failure[res.status];try{message=(await res.json()).error||message;}catch{}throw new Error(message||'The '+computer+' could not complete the transfer.');}
    return res;
  }
  const postJson=(path,data)=>post(path,{headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  function open(name){
    if(!C.connected())return false;
    C.release();closeSheet();title.textContent=name;sheet.hidden=false;return true;
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
    if(generation!==clipGeneration||sheet.hidden)return;
    pending=parts;
    $('clipPreview')?.replaceChildren(el('ul',{className:'clip-list'},...rows));
    say('');
  }
  async function upload(paste){
    if(!pending)return;
    const generation=clipGeneration, parts=pending, manifest=parts.map(p=>({kind:p.kind,name:p.name||'',size:p.blob.size}));
    const bytes=new TextEncoder().encode(JSON.stringify(manifest));let binary='';bytes.forEach(b=>binary+=String.fromCharCode(b));
    if(binary.length>9000||parts.length>64){say('Too many files at once — send fewer.',true);return;}
    for(const b of $('clipActions').querySelectorAll('button'))b.disabled=true;say('Sending…');
    try{
      await post('/clipboard/write',{headers:{'Content-Type':'application/octet-stream','X-Clip-Manifest':btoa(binary)},body:new Blob(parts.map(p=>p.blob))});
      if(generation!==clipGeneration||sheet.hidden)return;
      if(paste){C.release();C.send('shortcut',{id:1});}
      say(paste?'Pasted on the '+computer+'.':'On the '+computer+' clipboard — press '+pasteKeys+' where you want it.');
      setTimeout(()=>{if(!sheet.hidden&&pending===parts)closeSheet();},900);
    }catch(e){if(generation!==clipGeneration)return;say(e.message,true);$('clipActions').hidden=false;for(const b of $('clipActions').querySelectorAll('button'))b.disabled=false;}
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
    say('Reading the '+computer+' clipboard…');
    let info;
    try{info=await (await postJson('/clipboard/read',{})).json();}catch(e){say(e.message,true);return;}
    if(sheet.hidden)return;say('');
    let any=false;
    if(info.html){
      any=true;const rich=el('div',{className:'clip-rich'});rich.append(...cleanHtml(info.html));
      const copy=copyButton('Copy formatted',async()=>{
        if(secure&&navigator.clipboard?.write&&window.ClipboardItem){try{await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([rich.innerHTML],{type:'text/html'}),'text/plain':new Blob([info.text||rich.innerText],{type:'text/plain'})})]);return true;}catch{}}
        return copySelection(rich,true);
      });
      body.append(el('h2',{textContent:'Formatted text'}),rich,el('div',{className:'row'},copy));
    }
    if(info.text){
      any=true;const area=el('textarea',{readOnly:true,value:info.text,className:'clip-text'});
      const copy=copyButton('Copy text',async()=>{
        if(secure&&navigator.clipboard?.writeText){try{await navigator.clipboard.writeText(info.text);return true;}catch{}}
        area.focus();area.select();area.setSelectionRange(0,area.value.length);
        let ok=false;try{ok=document.execCommand('copy');}catch{}area.blur();return ok;
      });
      body.append(el('h2',{textContent:info.html?'Plain text':'Text'}),area,el('div',{className:'row'},copy));
    }
    if(info.image){
      any=true;const holder=el('div',{className:'clip-image'},el('span',{textContent:'Loading picture…'}));
      body.append(el('h2',{textContent:`Picture · ${info.image.width}×${info.image.height}`}),holder);
      try{
        const blob=await (await postJson('/clipboard/item',{index:-1})).blob();
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

  window.ThreeEClip={keyboard,sendClip,getClip,close:()=>{closeSheet();sink.blur();}};
})();
