// Shared menu vocabulary + shared Live command processor; only the rendering differs.
(() => {
  'use strict';
  const C=window.ThreeEControl,$=id=>document.getElementById(id),studio=$('studio');
  let state=null,pending=null,pendingTimer=null,gesture=null,holdTimer=null,lastPointer=-Infinity;
  const bar=document.createElement('div');bar.className='performance-bar';
  bar.innerHTML='<button id="phonePlay" aria-label="Play or pause">▶</button><button id="phoneStop" aria-label="Stop">■</button><button id="phoneRecord" aria-label="Record; hold for workspaces" aria-haspopup="dialog">●</button><button id="phoneMenus" aria-label="Performance menus">☰</button><output id="performanceStatus" role="status">Open Ableton</output>';
  studio.querySelector('.studio-heading').after(bar);
  const dialog=document.createElement('dialog');dialog.id='performanceMenu';dialog.className='dj-dialog performance-menu';
  dialog.innerHTML='<header><button id="performanceBack" aria-label="Back to workspaces">‹</button><h2 id="performanceTitle">Workspaces</h2><button id="performanceClose" aria-label="Close performance menu">×</button></header><div id="performanceChoices"></div>';
  studio.append(dialog);
  const toolbar=studio.querySelector('.piano-toolbar');
  const modes=document.createElement('button');modes.id='phonePianoMode';modes.textContent='♬';modes.setAttribute('aria-label','Piano chord rhythm mode');toolbar.append(modes);
  const labels=document.createElement('button');labels.textContent='1 · C';labels.setAttribute('aria-label','Cycle piano labels and scale pads');toolbar.append(labels);labels.addEventListener('click',()=>{labels.textContent=['1 · C','▥','♩'][window.ThreeESurface.cycleLabels()];});
  function ready(){return C.connected()&&state&&Date.now()/1000-state.time<2.5&&!pending;}
  function refresh(){
    for(const id of ['phonePlay','phoneStop','phoneRecord','phoneMenus'])$(id).disabled=!ready();
    $('phoneRecord').classList.toggle('recording',!!state?.record);$('phoneRecord').setAttribute('aria-pressed',String(!!state?.record));
    $('phonePlay').textContent=state?.playing?'Ⅱ':'▶';
    const ch=String((window.ThreeESurface?.pianoChannel()??0)+1),labels=state?.piano_mode_labels?.[ch],mode=state?.piano_modes?.[ch];
    modes.disabled=!ready()||!labels||!Number.isInteger(mode)||mode>=labels.length;
    modes.textContent=labels?.[mode]||'♬';modes.title='Cycle chord rhythm for piano channel '+ch;
    dialog.querySelectorAll('[data-action]').forEach(b=>{
      const action=b.dataset.action,clip=state?.selected_clip;
      b.disabled=!ready()||(action.startsWith('song-')&&!state?.song_presets)||(action.startsWith('clip-')&&(!clip||clip.recording||(action==='clip-new'?!clip.can_create:!clip.has_clip)));
      b.setAttribute('aria-pressed',String(state?.[action]===true));
    });
  }
  function send(action,extra={}){
    if(!ready())return;
    const id=Array.from(crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,'0')).join('').replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/,'$1-$2-$3-$4-$5');
    pending=id;const payload={id,action,session:state.session_id,track_index:state.track_index,...extra};
    if(action.startsWith('clip-'))payload.clip_token=state.selected_clip?.token;
    C.send('performance',payload);$('performanceStatus').textContent='Applying…';refresh();
    clearTimeout(pendingTimer);pendingTimer=setTimeout(()=>{pending=null;$('performanceStatus').textContent='Not confirmed — check Live';refresh();},3500);
  }
  function show(index=null){
    if(!state)return;
    $('performanceChoices').replaceChildren();$('performanceBack').hidden=index===null;
    const catalog=window.ThreeEWorkspaces;
    $('performanceTitle').textContent=index===null?'Workspaces':catalog[index][0];
    const rows=index===null?catalog:catalog[index][2];
    // Native Control Surface occupies the first workspace; phone uses its mixer.
    rows.forEach((row,i)=>{
      const b=document.createElement('button');b.type='button';
      b.textContent=index===null?row[0]:row[1];
      if(index===null){b.dataset.workspace=i;b.addEventListener('click',()=>choose(i));}
      else {b.dataset.action=row[0];b.addEventListener('click',()=>send(row[0]));}
      $('performanceChoices').append(b);
    });
    if(!dialog.open)dialog.show();refresh();
  }
  function choose(index){if(index===0){dialog.close();$('mixerTab').click();}else show(index);}
  $('phonePlay').addEventListener('click',()=>send('play'));$('phoneStop').addEventListener('click',()=>send('stop'));
  $('phoneMenus').addEventListener('click',()=>show());$('performanceClose').addEventListener('click',()=>dialog.close());$('performanceBack').addEventListener('click',()=>show());
  const record=$('phoneRecord');
  record.addEventListener('pointerdown',e=>{if(!ready()||e.button>0)return;e.preventDefault();lastPointer=performance.now();record.setPointerCapture(e.pointerId);gesture={id:e.pointerId,x:e.clientX,y:e.clientY,held:false};holdTimer=setTimeout(()=>{if(gesture){gesture.held=true;show();}},400);});
  record.addEventListener('pointermove',e=>{if(!gesture||gesture.id!==e.pointerId)return;if(!gesture.held&&Math.hypot(e.clientX-gesture.x,e.clientY-gesture.y)>12){clearTimeout(holdTimer);gesture=null;}});
  record.addEventListener('pointerup',e=>{if(!gesture||gesture.id!==e.pointerId)return;const g=gesture;gesture=null;clearTimeout(holdTimer);lastPointer=performance.now();if(!g.held)send('record');else {const b=document.elementFromPoint(e.clientX,e.clientY)?.closest('[data-workspace]');if(b)choose(+b.dataset.workspace);}});
  function cancel(){clearTimeout(holdTimer);gesture=null;}
  for(const name of ['pointercancel','lostpointercapture'])record.addEventListener(name,cancel);
  record.addEventListener('click',()=>{if(performance.now()-lastPointer>700)send('record');});
  record.addEventListener('contextmenu',e=>{e.preventDefault();if(ready())show();});
  modes.addEventListener('click',()=>{window.ThreeESurface.cancel();const ch=String(window.ThreeESurface.pianoChannel()+1),labels=state?.piano_mode_labels?.[ch];if(labels)send('piano-mode-set',{channel:ch,mode:(state.piano_modes[ch]+1)%labels.length});});
  $('midiChannel').addEventListener('change',refresh);
  function describe(info){
    if(!Object.hasOwn(info||{},'performance'))return;
    state=info.performance;window.ThreeESurface?.setScale(state);
    if(pending&&state?.last_id===pending){clearTimeout(pendingTimer);pending=null;$('performanceStatus').textContent=state.error||state.track_name;}
    else if(!pending)$('performanceStatus').textContent=state?state.track_name:'Open Ableton with the 3£ control surface';
    refresh();
  }
  window.ThreeEPerformance={describe,cancel,state(connected){if(!connected){cancel();state=null;window.ThreeESurface?.setScale(null);pending=null;clearTimeout(pendingTimer);if(dialog.open)dialog.close();$('performanceStatus').textContent='Disconnected';refresh();}}};
  setInterval(refresh,500);if(C.info)describe(C.info);refresh();
})();
