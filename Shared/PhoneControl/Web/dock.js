// SPDX-License-Identifier: MIT
// Captured single-contact dock gestures, shared by Safari and both desktop hosts.
(() => {
  'use strict';
  const C=window.ThreeEControl, $=id=>document.getElementById(id);
  const svg=body=>'<svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">'+body+'</svg>';
  const icons={
    apps:svg('<rect x="1" y="1" width="30" height="30" rx="8" fill="#e8e9ed"/>'+['#ff605b','#ffbe43','#73c95d','#5fbcd9','#5689ef','#9975df','#ed7fab','#7fc7a0','#6c96d6'].map((color,i)=>`<rect x="${6+i%3*7.5}" y="${6+Math.floor(i/3)*7.5}" width="5" height="5" rx="1.4" fill="${color}"/>`).join('')),
    windows:svg('<rect x="3" y="5" width="18" height="15" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><rect x="11" y="12" width="18" height="15" rx="2" fill="currentColor"/>'),
    desktop:svg('<rect x="3" y="5" width="26" height="18" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 27h8M16 23v4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    left:svg('<path d="M20 7 11 16l9 9" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'),
    right:svg('<path d="m12 7 9 9-9 9" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'),
    previous:svg('<path d="M6 6h3v20H6zm20 0L11 16l15 10z" fill="currentColor"/>'),
    next:svg('<path d="M23 6h3v20h-3zM6 6l15 10L6 26z" fill="currentColor"/>'),
    piano:svg('<rect x="3" y="6" width="26" height="20" rx="2" fill="currentColor"/><path d="M10 7v18m6-18v18m6-18v18" stroke="#17222c"/><path d="M8 6h4v12H8zm12 0h4v12h-4z" fill="#17222c"/>'),
    play:svg('<path d="M9 5 27 16 9 27z" fill="currentColor"/>'),
    pause:svg('<path d="M8 6h6v20H8zm10 0h6v20h-6z" fill="currentColor"/>'),
    stop:svg('<rect x="6" y="6" width="20" height="20" rx="2" fill="currentColor"/>')
  };
  let active=null, holdTimer, restoreTimer, lastPointer=-Infinity, controls={}, controlsSignature='',multipleDesktops=true;
  // Task View / Mission Control is treated as open until it is closed here,
  // any click or other navigation happens, or a minute passes.
  const OVERVIEW_TIMEOUT=60000;let overviewUntil=0;
  // Fixed palette: ids match PhoneTrackpad.ShortcutCount and the host mapping.
  // Rows are listed top to bottom; the most used sit nearest the thumb.
  const shortcuts=[[12,'⌘R','Refresh'],[16,'⌘Space','Search'],[17,'⌘Q','Quit app'],
    [9,'⌘N','New window'],[10,'⌘F','Find'],[11,'⌘S','Save'],
    [13,'⇧⌘3','Screenshot'],[14,'⇧⌘4','Area shot'],[15,'⇧⌘5','Record'],
    [6,'⌘T','New tab'],[7,'⇧⌘T','Reopen tab'],[8,'⌘W','Close tab'],
    [3,'⌘A','Select all'],[4,'⌘Z','Undo'],[5,'⇧⌘Z','Redo'],
    [0,'⌘C','Copy'],[1,'⌘V','Paste'],[2,'⌘X','Cut']];
  const commandsButton=$('commands'),commandsPane=$('commandsPane');
  let commandsTimer,picking=null,commandsPointerAt=-Infinity;
  function showCommands(show){
    clearTimeout(commandsTimer);commandsPane.hidden=!show;commandsButton.setAttribute('aria-expanded',String(show));
    commandsPane.querySelectorAll('.sent,.picking').forEach(b=>b.classList.remove('sent','picking'));
  }
  function fireShortcut(button,id){
    if(!C.connected()||!C.send('shortcut',{id}))return;
    // Close after a short confirmation so the shortcut lands in the app underneath.
    button.classList.add('sent');clearTimeout(commandsTimer);commandsTimer=setTimeout(()=>showCommands(false),160);
  }
  const shortcutAt=(x,y)=>{const hit=document.elementFromPoint?.(x,y);const button=hit?.closest?.('#commandsPane button')||(hit?.parentElement?.closest?.('#commandsPane button'));return button&&commandsPane.contains(button)?button:null;};
  for(const [id,keys,label] of shortcuts){
    const button=document.createElement('button');button.type='button';
    button.setAttribute('aria-label',label+' ('+keys+')');
    const kbd=document.createElement('kbd'),small=document.createElement('small');kbd.textContent=keys;small.textContent=label;button.append(kbd,small);
    button.dataset.shortcut=id;
    button.addEventListener('click',()=>fireShortcut(button,id));
    commandsPane.append(button);
  }
  // Bottom row: phone keyboard and two-way clipboard (see clip.js). Each button
  // appears only when the computer reports support for it in host.js.
  const toolIcons={
    keyboard:svg('<rect x="3" y="8" width="26" height="17" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M8 13h2m4 0h2m4 0h2m4 0h0M8 17h2m4 0h2m4 0h2M11 21h10" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
    sendClip:svg('<rect x="7" y="6" width="18" height="23" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 6V4h8v2" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M16 24V13m-4.5 4.5L16 13l4.5 4.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    getClip:svg('<rect x="7" y="6" width="18" height="23" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 6V4h8v2" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M16 12v11m-4.5-4.5L16 23l4.5-4.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
  };
  const toolRule=document.createElement('div');toolRule.className='pane-rule';commandsPane.append(toolRule);
  const computer=window.ThreeEHost?.platform==='macos'?'Mac':'PC';
  const toolButtons=[['keyboard','Keyboard','Type on the '+computer+' with the phone keyboard'],['sendClip','Paste to '+computer,'Send the phone clipboard to the '+computer+' and paste it'],['getClip','Copy from '+computer,'Copy the '+computer+' clipboard to this phone']].map(([tool,label,description])=>{
    const button=document.createElement('button');button.type='button';button.className='tool';button.dataset.tool=tool;
    button.setAttribute('aria-label',description);
    const kbd=document.createElement('kbd'),small=document.createElement('small');kbd.innerHTML=toolIcons[tool];small.textContent=label;button.append(kbd,small);
    button.addEventListener('click',()=>runTool(tool));
    commandsPane.append(button);return button;
  });
  function runTool(tool){
    if(!C.connected())return;
    showCommands(false);window.ThreeEClip?.[tool]?.();
  }
  function showTools(){
    const host=window.ThreeEHost||{},ready=!!window.ThreeEClip;
    toolButtons[0].hidden=!(ready&&host.keyboard);toolButtons[1].hidden=toolButtons[2].hidden=!(ready&&host.clipboard);
    toolRule.hidden=toolButtons.every(b=>b.hidden);
  }
  showTools();
  // Press ⌘ and slide onto a shortcut, then release to send it. A plain tap
  // opens (or closes) the palette for tapping instead.
  commandsButton.addEventListener('pointerdown',e=>{
    e.preventDefault();if(!C.connected()||e.button>0)return;
    C.release();hideVolume(true);commandsPointerAt=performance.now();
    picking={id:e.pointerId,x:e.clientX,y:e.clientY,moved:false,wasOpen:!commandsPane.hidden,target:null};
    showCommands(true);commandsButton.setPointerCapture?.(e.pointerId);
  });
  commandsButton.addEventListener('pointermove',e=>{
    if(!picking||picking.id!==e.pointerId)return;e.preventDefault();
    if(Math.hypot(e.clientX-picking.x,e.clientY-picking.y)>10)picking.moved=true;
    const target=shortcutAt(e.clientX,e.clientY);
    if(target!==picking.target){picking.target?.classList.remove('picking');target?.classList.add('picking');picking.target=target;}
  });
  commandsButton.addEventListener('pointerup',e=>{
    if(!picking||picking.id!==e.pointerId)return;
    const p=picking;picking=null;commandsPointerAt=performance.now();
    const target=shortcutAt(e.clientX,e.clientY)||p.target;target?.classList.remove('picking');
    if(target&&p.moved){if(target.dataset.tool)runTool(target.dataset.tool);else fireShortcut(target,+target.dataset.shortcut);}
    else if(p.moved||p.wasOpen)showCommands(false);
  });
  commandsButton.addEventListener('pointercancel',()=>{picking?.target?.classList.remove('picking');picking=null;showCommands(false);});
  // Keyboard / assistive activation (no pointer) toggles the palette.
  commandsButton.addEventListener('click',()=>{if(performance.now()-commandsPointerAt<700||!C.connected())return;C.release();hideVolume(true);showCommands(commandsPane.hidden);});
  commandsButton.addEventListener('contextmenu',e=>e.preventDefault());
  document.addEventListener('pointerdown',e=>{if(!commandsPane.hidden&&!commandsPane.contains(e.target)&&!commandsButton.contains(e.target))showCommands(false);});
  let volume={available:false,level:null},volumeEditing=false,volumePending=null,volumeSendTimer,volumeHideTimer,volumeQuiet=0;
  const volumePane=$('volumePane'),volumeSlider=$('outputVolume');
  function showVolume(){clearTimeout(volumeHideTimer);volumePane.hidden=false;$('media').setAttribute('aria-expanded','true');}
  function hideVolume(discard=false){
    clearTimeout(volumeHideTimer);volumePane.hidden=true;volumeEditing=false;$('media').setAttribute('aria-expanded','false');
    if(discard){clearTimeout(volumeSendTimer);volumeSendTimer=null;volumePending=null;}
  }
  function flushVolume(){
    clearTimeout(volumeSendTimer);volumeSendTimer=null;
    if(volumePending!==null&&C.connected())C.send('volume',{level:volumePending});
    volumePending=null;
  }
  function changeVolume(value){
    if(!C.connected()||!volume.available)return;
    const level=Math.max(0,Math.min(100,Math.round(value)));
    volumeSlider.value=level;volumePane.style.setProperty('--volume',level+'%');$('volumeValue').textContent=level+'%';volumeQuiet=performance.now()+1200;
    volumePending=level;if(!volumeSendTimer)volumeSendTimer=setTimeout(flushVolume,40);
  }
  function finishVolume(){volumeEditing=false;flushVolume();clearTimeout(volumeHideTimer);volumeHideTimer=setTimeout(()=>hideVolume(),3500);}
  // Drag anywhere on the track: the level follows the finger (top = 100%).
  const volumeTrack=$('volumeTrack');let trackPointer=null;
  function levelAt(y){const r=volumeTrack.getBoundingClientRect();return (r.bottom-y)*100/Math.max(1,r.height);}
  volumeTrack.addEventListener('pointerdown',e=>{
    if(!C.connected()||!volume.available)return;e.preventDefault();C.release();showVolume();volumeEditing=true;
    trackPointer=e.pointerId;volumeTrack.setPointerCapture?.(e.pointerId);changeVolume(levelAt(e.clientY));
  });
  volumeTrack.addEventListener('pointermove',e=>{if(trackPointer!==e.pointerId)return;e.preventDefault();changeVolume(levelAt(e.clientY));});
  for(const type of ['pointerup','pointercancel','lostpointercapture'])volumeTrack.addEventListener(type,e=>{if(trackPointer!==e.pointerId)return;trackPointer=null;finishVolume();});
  // Up/down use the laptop's own volume keys (system steps and on-screen flyout).
  for(const [id,direction] of [['volumeUp',1],['volumeDown',-1]]){
    $(id).addEventListener('click',()=>{
      if(!C.connected())return;showVolume();C.send('volumeStep',{direction});
      if(volume.available&&volume.level!=null){const level=Math.max(0,Math.min(100,+volumeSlider.value+direction*2));volumeSlider.value=level;volumePane.style.setProperty('--volume',level+'%');$('volumeValue').textContent=level+'%';volumeQuiet=performance.now()+700;}
      finishVolume();
    });
  }
  volumeSlider.addEventListener('pointerdown',()=>{C.release();showVolume();volumeEditing=true;});
  volumeSlider.addEventListener('input',()=>{showVolume();changeVolume(+volumeSlider.value);if(!volumeEditing)finishVolume();});
  volumeSlider.addEventListener('pointerup',finishVolume);
  volumeSlider.addEventListener('change',finishVolume);
  volumeSlider.addEventListener('pointercancel',()=>hideVolume(true));
  document.addEventListener('pointerdown',e=>{if(!volumePane.contains(e.target)&&!$('media').contains(e.target))hideVolume(true);});
  const validImage=value=>typeof value==='string'&&value.length<32768&&/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(value);
  function picture(parent,value,fallback) {
    const span=document.createElement('span');span.className='dock-glyph';
    if(validImage(value)){const image=document.createElement('img');image.src=value;image.alt='';span.append(image);}else span.innerHTML=icons[fallback];
    parent.append(span);
  }
  function paint(kind,feedback) {
    const button=$(kind);button.replaceChildren();button.dataset.icon=feedback||kind;
    if(feedback){button.innerHTML=icons[feedback];return;}
    if(kind==='apps'){picture(button,controls.appsIcon,'apps');return;}
    const media=controls.media||{};
    // An actual host-provided app icon is optional; no generic source placeholder.
    if(validImage(media.artwork))picture(button,media.artwork);
    const action=media.playing===true?(media.stop?'stop':'pause'):'play';
    picture(button,null,action);button.dataset.icon=action;
  }
  function restore(){clearTimeout(restoreTimer);if(!active){paint('apps');paint('media');}}
  function finishFeedback(kind,icon){paint(kind,icon);clearTimeout(restoreTimer);restoreTimer=setTimeout(restore,icon==='next'||icon==='previous'?1000:650);}
  function cancel(event,keepVolume=false){
    if(event&&active&&event.pointerId!==active.id)return;
    clearTimeout(holdTimer);
    if(active?.kind==='apps'){C.send('navigateEnd');C.send('appsEnd');}
    if(!keepVolume)hideVolume(true);
    active=null;for(const kind of ['apps','media'])$(kind).classList.remove('active');restore();
  }
  function move(e){
    if(!active||active.id!==e.pointerId)return;e.preventDefault();
    const a=active,dx=e.clientX-a.startX,dy=e.clientY-a.startY;
    a.max=Math.max(a.max,Math.hypot(dx,dy));
    if(a.max>(a.kind==='media'?6:10))clearTimeout(holdTimer);
    // Media: only a clearly upward/downward start is a volume swipe, so a thumb
    // swipe that arcs a little is still read as previous/next.
    // Media keeps re-reading the direction until the volume actually opens.
    if(a.kind==='media'&&!a.volume&&Math.max(Math.abs(dx),Math.abs(dy))>=12)a.axis=Math.abs(dy)>Math.abs(dx)*1.4?'vertical':'horizontal';
    else if(!a.axis&&Math.max(Math.abs(dx),Math.abs(dy))>=12)a.axis=Math.abs(dx)>Math.abs(dy)*1.15?'horizontal':'vertical';
    if(a.kind==='media'&&a.axis==='vertical'&&(dy<=-18||a.volume)){
      if(!a.volume){a.volume=true;a.volumeY=e.clientY;a.volumeLevel=volume.available?+volumeSlider.value:null;showVolume();}
      else if(a.volumeLevel===null&&volume.available){a.volumeY=e.clientY;a.volumeLevel=+volumeSlider.value;}
      else if(a.volumeLevel!==null)changeVolume(a.volumeLevel+(a.volumeY-e.clientY)*100/Math.max(70,volumeSlider.getBoundingClientRect().height));
      return;
    }
    // Apps: swipe up shows all windows (Task View / Mission Control), swipe
    // down shows the desktop. Fires once per contact, before lifting.
    // Swipe down closes an open all-windows view first; otherwise it shows
    // the desktop, and swiping down again brings the windows back (toggle).
    if(a.kind==='apps'&&a.axis==='vertical'&&!a.held&&!a.vertical&&Math.abs(dy)>=36){
      a.vertical=true;const now=performance.now(),open=now<overviewUntil;
      if(dy<0){if(!open)C.send('taskView');overviewUntil=now+OVERVIEW_TIMEOUT;paint('apps','windows');}
      else if(open){C.send('taskView');overviewUntil=0;paint('apps','windows');}
      else{C.send('showDesktop');paint('apps','desktop');}
      return;
    }
    if(a.axis!=='horizontal')return;
    if(a.kind==='media'){if(Math.abs(dx)>=24)paint('media',dx<0?'previous':'next');else paint('media');return;}
    const change=e.clientX-a.stepX,threshold=a.steps?48:26,now=performance.now();
    if(Math.abs(change)<threshold||now-a.lastStep<240)return;
    const direction=change<0?-1:1;
    if(a.held)C.send('appsStep',{direction});
    else C.send('navigate',{direction,swipe:true});
    a.steps++;a.stepX=e.clientX;a.lastStep=now;
    const destination=a.held||a.windows?direction:-direction;
    paint('apps',destination<0?'left':'right');
  }
  for(const kind of ['apps','media']){
    const button=$(kind);
    button.addEventListener('contextmenu',e=>e.preventDefault());
    button.addEventListener('pointerdown',e=>{
      e.preventDefault();if(!C.connected()||e.button>0)return;
      if(active)cancel(); // a contact the browser never finished must not swallow this one
      C.release();showCommands(false);lastPointer=performance.now();clearTimeout(restoreTimer);
      button.setPointerCapture(e.pointerId);
      active={kind,id:e.pointerId,startX:e.clientX,startY:e.clientY,stepX:e.clientX,start:performance.now(),lastStep:-Infinity,steps:0,max:0,axis:null,held:false,windows:!multipleDesktops};
      button.classList.add('active');
      holdTimer=setTimeout(()=>{
        if(!active||active.kind!==kind||active.axis||active.max>(kind==='media'?6:10))return;
        active.held=true;
        if(kind==='apps'){C.send('appsBegin');paint('apps','windows');}
        else {window.ThreeESurface.openStudio();finishFeedback('media','piano');}
      },500);
    });
    button.addEventListener('pointermove',move);
    button.addEventListener('pointerup',e=>{
      lastPointer=performance.now();
      if(!active||active.id!==e.pointerId)return;
      move(e);lastPointer=performance.now();const a=active,dx=e.clientX-a.startX,dy=e.clientY-a.startY;
      let feedback=null;
      // Media skip is decided from where the finger ended up, so a swipe whose
      // first few pixels wobbled still counts (unless it opened the volume).
      if(kind==='media'&&!a.held&&!a.volume&&Math.abs(dx)>=24&&Math.abs(dx)>=Math.abs(dy)*0.8){C.send('media',{action:dx<0?1:2});feedback=dx<0?'previous':'next';}
      else if(!a.held&&a.axis!=='vertical'){
        if(!a.axis&&a.max<12){
          if(kind==='apps'){C.send('appsBegin');C.send('appsEnd');feedback='windows';}
          else C.send('media',{action:0}); // Wait for confirmed host state; never guess an opposite icon.
        }
      }
      if(a.volume)flushVolume();cancel(null,a.volume);if(a.volume)finishVolume();if(feedback)finishFeedback(kind,feedback);
      if(button.hasPointerCapture(e.pointerId))button.releasePointerCapture(e.pointerId);
    });
    button.addEventListener('pointercancel',e=>{lastPointer=performance.now();cancel(e);});
    button.addEventListener('lostpointercapture',e=>{if(active?.id===e.pointerId)cancel(e);});
    button.addEventListener('click',()=>{
      if(performance.now()-lastPointer<700||!C.connected())return;
      if(kind==='apps'){C.send('appsBegin');C.send('appsEnd');finishFeedback('apps','windows');}
      else C.send('media',{action:0});
    });
    button.addEventListener('keydown',e=>{
      if(kind==='media'&&C.connected()&&['ArrowUp','ArrowDown'].includes(e.key)){
        e.preventDefault();const wasOpen=!volumePane.hidden;showVolume();if(wasOpen)changeVolume(+volumeSlider.value+(e.key==='ArrowUp'?5:-5));finishVolume();return;
      }
      if(!C.connected()||!['ArrowLeft','ArrowRight'].includes(e.key))return;e.preventDefault();
      if(kind==='apps'){C.send('navigate',{direction:e.key==='ArrowLeft'?-1:1});C.send('navigateEnd');}
      else C.send('media',{action:e.key==='ArrowLeft'?1:2});
    });
  }
  $('media').addEventListener('wheel',e=>{
    if(!C.connected()||!e.deltaY)return;e.preventDefault();showVolume();changeVolume(+volumeSlider.value+(e.deltaY<0?2:-2));finishVolume();
  },{passive:false});
  // A held Apps/Media contact (app switcher, swipe or volume) or a volume
  // slider being dragged: the page must not reload under the finger.
  const busy=()=>!!active||volumeEditing||trackPointer!==null;
  window.ThreeEDock={cancel,busy,commands:showCommands,overviewEnded(){overviewUntil=0;},describe(info){
    if(typeof info?.multipleDesktops==='boolean')multipleDesktops=info.multipleDesktops;
    // Windows and macOS hosts map the shortcut palette; unknown hosts hide it.
    if(info?.platform){commandsButton.hidden=!['windows','macos'].includes(info.platform);if(commandsButton.hidden)showCommands(false);}
    // Repaint artwork only when the host state actually changed. Rebuilding
    // images on every heartbeat stalled touch handling on the phone.
    if(info?.controls){const signature=JSON.stringify(info.controls);if(signature!==controlsSignature){controlsSignature=signature;controls=info.controls;if(!active)restore();}}
    if(info?.volume){
      volume=info.volume;volumeSlider.disabled=!volume.available;
      if(!volume.available){$('volumeValue').textContent='—';volumeSlider.setAttribute('aria-label','Output volume unavailable for this device');}
      else if(!active?.volume&&!volumeEditing&&performance.now()>=volumeQuiet){
        volumeSlider.value=volume.level;volumePane.style.setProperty('--volume',volume.level+'%');$('volumeValue').textContent=volume.level+'%';volumeSlider.setAttribute('aria-label','Laptop output volume');
      }
    }
  }};
  if(C.info)window.ThreeEDock.describe(C.info);restore();
})();
