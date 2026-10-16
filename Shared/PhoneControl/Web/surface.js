// SPDX-License-Identifier: MIT
// Shared Windows/macOS controller. MIDI channel numbers are zero-based on the wire.
(() => {
  'use strict';
  const $=id=>document.getElementById(id), C=window.ThreeEControl;
  const values=new Map(), dirty=new Map(), notes=new Set();
  let channel=15, output=-1, dirtyTimer, mediaTimer, active=null, lastPointer=-Infinity, epoch=0;
  const studio=$('studio');
  studio.innerHTML=`<header><h1><span>3£</span> Phone Bar</h1><div class="studio-tabs"><button id="decksTab" aria-pressed="true">Two decks</button><button id="mixerTab" aria-pressed="false">Mixer</button></div><button id="closeStudio">Trackpad</button></header>
  <div class="routing"><label>Output <select id="midiOutput" aria-label="MIDI output"><option value="-1">Choose MIDI output</option></select></label><label>Ch <select id="midiChannel" aria-label="MIDI channel"></select></label></div><p id="midiStatus" role="status">Choose a MIDI output, then map the controls in Ableton.</p>
  <div id="decksView" class="decks"></div><div id="mixerView" class="mixer" hidden></div>
  <div class="crossfader"><label for="crossfader"><span>A</span><span>CROSSFADER</span><span>B</span></label><input id="crossfader" type="range" min="0" max="127" value="64" aria-label="Crossfader"></div>
  <div class="studio-footer"><span>Up turns right · turn the rim to rotate</span><button class="panic" id="panic">Release notes</button></div>
  <details class="studio-help"><summary>Connect to Ableton & control guide</summary><p>Choose this MIDI port in Ableton’s Link, Tempo & MIDI settings and enable Remote for its input. Enter MIDI Map mode (Ctrl+M on Windows, Cmd+M on Mac), choose an Ableton control, then move its matching control here. Turn MIDI Map mode off to perform.</p><p>Windows: create a loopback port in loopMIDI (for example “3E Phone”), then select it here and in Ableton. Mac: select the built-in “3E Phone” virtual source in Ableton. Use Refresh outputs if a port was just added.</p><p>Decks: map Launch/Stop/Cue to your two tracks, the crossfader to Ableton’s crossfader, and assign those tracks to A and B. Knobs map to your EQ, filter, sends or effects. Jog wheels use relative CC (65 forward, 63 backward); use Relative (Bin Offset) mapping. Audio and tempo matching are handled in Ableton. Record animation reflects your Launch/Stop taps, not feedback from Live.</p><p>Move through a knob’s centre vertically for precision, or turn around its outer rim. Double-tap a knob to reset. Mixer has eight volume, pan and send strips plus mute/solo triggers. The default MIDI channel is 16 to keep these assignments separate from other 3£ controls.</p><button id="refreshMidi">Refresh outputs</button></details>`;
  for(let i=0;i<16;i++) {const option=document.createElement('option');option.value=i;option.textContent=i+1;$('midiChannel').append(option);} $('midiChannel').value='15';
  const valid=()=>C.connected()&&output>=0;
  function warn(){ $('midiStatus').textContent=C.connected()?'Choose a MIDI output to send controls.':'Reconnecting — controls will resume when connected.'; }
  function flush(){clearTimeout(dirtyTimer);dirtyTimer=null;if(valid()) for(const [number,value] of dirty) C.send('midiCC',{channel,number,value});dirty.clear();}
  function cc(number,value){value=Math.max(0,Math.min(127,Math.round(value)));values.set(number,value);render(number,value);if(!valid()){warn();return;}dirty.set(number,value);if(!dirtyTimer)dirtyTimer=setTimeout(flush,16);}
  function pulse(number){if(!valid()){warn();return;}flush();C.send('midiNote',{channel,number,value:127});notes.add(number);C.send('midiNote',{channel,number,value:0});notes.delete(number);}
  function render(number,value){
    studio.querySelectorAll('[data-cc="'+number+'"]').forEach(el=>{
      if(el.classList.contains('knob')) {el.style.setProperty('--angle',(-135+value/127*270)+'deg');el.setAttribute('aria-valuenow',value);el.nextElementSibling.textContent=value;}
      else el.value=value;
    });
  }
  function knob(label,number,initial=64){
    const wrap=document.createElement('div');wrap.className='control';
    const title=document.createElement('label');title.textContent=label;
    const button=document.createElement('button');button.className='knob';button.dataset.cc=number;button.setAttribute('role','slider');button.setAttribute('aria-label',label+' (CC '+number+')');button.setAttribute('aria-valuemin','0');button.setAttribute('aria-valuemax','127');button.title=label+' · CC '+number;
    const readout=document.createElement('output');wrap.append(title,button,readout);
    let gesture;
    button.addEventListener('pointerdown',e=>{
      e.preventDefault();if(!C.connected())return;button.setPointerCapture(e.pointerId);
      const r=button.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2;
      gesture={id:e.pointerId,epoch,y:e.clientY,value:values.get(number)??initial,cx,cy,angle:Math.atan2(e.clientY-cy,e.clientX-cx),circular:Math.hypot(e.clientX-cx,e.clientY-cy)>r.width*.32};
    });
    button.addEventListener('pointermove',e=>{
      if(!gesture||gesture.epoch!==epoch||gesture.id!==e.pointerId)return;e.preventDefault();
      if(gesture.circular){const angle=Math.atan2(e.clientY-gesture.cy,e.clientX-gesture.cx);let change=angle-gesture.angle;if(change>Math.PI)change-=2*Math.PI;if(change<-Math.PI)change+=2*Math.PI;gesture.angle=angle;gesture.value=Math.max(0,Math.min(127,gesture.value+change/(Math.PI*1.5)*127));cc(number,gesture.value);}
      else cc(number,gesture.value+(gesture.y-e.clientY)*(e.shiftKey?.15:.8));
    });
    for(const type of ['pointerup','pointercancel','lostpointercapture'])button.addEventListener(type,()=>{gesture=null;flush();});
    button.addEventListener('dblclick',()=>cc(number,initial));
    button.addEventListener('keydown',e=>{if(['ArrowUp','ArrowRight','ArrowDown','ArrowLeft','Home','End'].includes(e.key)){e.preventDefault();cc(number,e.key==='Home'?0:e.key==='End'?127:(values.get(number)??initial)+(['ArrowUp','ArrowRight'].includes(e.key)?1:-1));flush();}});
    if(!values.has(number))values.set(number,initial);queueMicrotask(()=>render(number,values.get(number)));return wrap;
  }
  function trigger(label,note,callback){const b=document.createElement('button');b.textContent=label;b.title='Note '+note;b.addEventListener('click',()=>{if(valid()){pulse(note);callback?.(b);}else warn();});return b;}
  for(let d=0;d<2;d++){
    const deck=document.createElement('section');deck.className='deck '+(d?'deck-b':'deck-a');
    deck.innerHTML='<div class="deck-title">DECK '+(d?'B':'A')+'</div><div class="vinyl" role="slider" tabindex="0" aria-label="Deck '+(d?'B':'A')+' jog wheel" aria-valuemin="0" aria-valuemax="127" aria-valuenow="64"><div class="record-label">'+(d?'B':'A')+'</div></div>';
    const wheel=deck.querySelector('.vinyl'),controls=document.createElement('div');controls.className='deck-controls';
    controls.append(trigger('Launch',36+d,()=>wheel.classList.add('is-spinning')),trigger('Stop',42+d,()=>wheel.classList.remove('is-spinning')),trigger('Cue',38+d));deck.append(controls);
    const row=document.createElement('div');row.className='knob-row';row.append(knob('Low',50+d),knob('Mid',52+d),knob('High',54+d));deck.append(row);
    const fx=document.createElement('div');fx.className='knob-row';fx.append(knob('Filter',48+d),knob('Send',32+d,0),knob('Level',16+d,100));deck.append(fx);
    let jog=null;
    function turn(direction){if(!valid()){warn();return;}C.send('midiCC',{channel,number:40+d,value:direction>0?65:63});}
    wheel.addEventListener('pointerdown',e=>{e.preventDefault();wheel.setPointerCapture(e.pointerId);const r=wheel.getBoundingClientRect();jog={id:e.pointerId,epoch,cx:r.left+r.width/2,cy:r.top+r.height/2,angle:0,pending:0,time:0};jog.angle=Math.atan2(e.clientY-jog.cy,e.clientX-jog.cx);wheel.classList.add('scrubbing');});
    wheel.addEventListener('pointermove',e=>{if(!jog||jog.epoch!==epoch||jog.id!==e.pointerId)return;e.preventDefault();const a=Math.atan2(e.clientY-jog.cy,e.clientX-jog.cx);let delta=a-jog.angle;if(delta>Math.PI)delta-=Math.PI*2;if(delta<-Math.PI)delta+=Math.PI*2;jog.angle=a;jog.pending+=delta;if(performance.now()-jog.time>=24&&Math.abs(jog.pending)>.04){turn(jog.pending);jog.pending=0;jog.time=performance.now();}});
    for(const type of ['pointerup','pointercancel','lostpointercapture'])wheel.addEventListener(type,()=>{jog=null;wheel.classList.remove('scrubbing');});
    wheel.addEventListener('keydown',e=>{if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();turn(e.key==='ArrowRight'?1:-1);}});
    $('decksView').append(deck);
  }
  for(let i=0;i<8;i++){
    const strip=document.createElement('section');strip.className='strip';strip.innerHTML='<h2>TRACK '+(i+1)+'</h2>';
    strip.append(knob('Pan',24+i),knob('Send',32+i,0));
    const volume=document.createElement('input');volume.type='range';volume.min='0';volume.max='127';volume.value=values.get(16+i)??100;volume.className='fader';volume.dataset.cc=16+i;volume.setAttribute('aria-label','Track '+(i+1)+' volume');volume.addEventListener('input',()=>cc(16+i,+volume.value));volume.addEventListener('change',flush);strip.append(volume);
    const triggers=document.createElement('div');triggers.className='strip-buttons';const mute=trigger('M',48+i,b=>b.setAttribute('aria-pressed',String(b.getAttribute('aria-pressed')!=='true'))),solo=trigger('S',56+i,b=>b.setAttribute('aria-pressed',String(b.getAttribute('aria-pressed')!=='true')));mute.className='mute';solo.className='solo';mute.setAttribute('aria-label','Track '+(i+1)+' mute');solo.setAttribute('aria-label','Track '+(i+1)+' solo');triggers.append(mute,solo);strip.append(triggers);$('mixerView').append(strip);
  }
  $('crossfader').dataset.cc=1;$('crossfader').addEventListener('input',()=>cc(1,+$('crossfader').value));$('crossfader').addEventListener('change',flush);
  function tab(mixer){$('mixerView').hidden=!mixer;$('decksView').hidden=mixer;$('mixerTab').setAttribute('aria-pressed',String(mixer));$('decksTab').setAttribute('aria-pressed',String(!mixer));}
  $('mixerTab').addEventListener('click',()=>tab(true));$('decksTab').addEventListener('click',()=>tab(false));
  function openStudio(){C.release();studio.hidden=false;C.send('info');}
  $('closeStudio').addEventListener('click',()=>{cancel();C.release();studio.hidden=true;});
  $('refreshMidi').addEventListener('click',()=>C.send('info'));
  $('midiOutput').addEventListener('change',()=>{cancel();output=-1;C.send('midiPort',{id:+$('midiOutput').value});});
  $('midiChannel').addEventListener('change',()=>{cancel();C.send('midiPanic');channel=+$('midiChannel').value;});
  $('panic').addEventListener('click',()=>{cancel();C.send('midiPanic');});
  function cancel(){epoch++;clearTimeout(mediaTimer);clearTimeout(dirtyTimer);dirtyTimer=null;dirty.clear();if(active?.kind==='apps')C.send('appsEnd');active=null;$('apps').classList.remove('active');for(const number of notes)C.send('midiNote',{channel,number,value:0});notes.clear();}
  for(const kind of ['apps','media']){
    const button=$(kind);button.addEventListener('contextmenu',e=>e.preventDefault());
    button.addEventListener('pointerdown',e=>{
      e.preventDefault();if(!C.connected())return;lastPointer=performance.now();C.release();button.setPointerCapture(e.pointerId);active={kind,id:e.pointerId,x:e.clientX,start:e.clientX,y:e.clientY};
      if(kind==='apps'){C.send('appsBegin');button.classList.add('active');}
      else mediaTimer=setTimeout(()=>{if(active?.kind==='media')openStudio();},500);
    });
    button.addEventListener('pointermove',e=>{if(!active||active.id!==e.pointerId)return;e.preventDefault();const dx=e.clientX-active.x;if(Math.abs(e.clientX-active.start)>12||Math.abs(e.clientY-active.y)>12)clearTimeout(mediaTimer);if(kind==='apps'&&Math.abs(dx)>=32){const count=Math.min(6,Math.floor(Math.abs(dx)/32));for(let i=0;i<count;i++)C.send('appsStep',{direction:dx>0?1:-1});active.x=e.clientX;}else if(kind==='media')active.x=e.clientX;});
    button.addEventListener('pointerup',e=>{lastPointer=performance.now();if(!active||active.id!==e.pointerId)return;e.preventDefault();if(kind==='media'){const dx=e.clientX-active.start;C.send('media',{action:Math.abs(dx)<24?0:dx<0?1:2});}cancel();});
    for(const type of ['pointercancel','lostpointercapture'])button.addEventListener(type,cancel);
    button.addEventListener('click',()=>{if(performance.now()-lastPointer<600||!C.connected())return;if(kind==='apps'){C.send('appsBegin');C.send('appsEnd');}else C.send('media',{action:0});});
  }
  function describe(info){
    if(!info?.midi)return;output=info.midi.selected;
    const select=$('midiOutput'),signature=JSON.stringify(info.midi.ports);
    if(select.dataset.ports!==signature){select.replaceChildren();const off=document.createElement('option');off.value=-1;off.textContent='MIDI off / choose output';select.append(off);for(const port of info.midi.ports){const item=document.createElement('option');item.value=port.id;item.textContent=port.name;select.append(item);}select.dataset.ports=signature;}
    select.value=output;$('midiStatus').textContent=output>=0?'Sending to '+info.midi.status+' · map controls in Ableton':info.platform==='windows'?'Choose a MIDI output. Ableton uses a loopback port such as loopMIDI.':info.midi.status;
  }
  window.ThreeESurface={cancel,describe,state(ready){if(!ready){cancel();studio.querySelectorAll('.vinyl').forEach(v=>v.classList.remove('is-spinning'));$('midiStatus').textContent='Disconnected — controls paused';}else {if(C.info)describe(C.info);if(!studio.hidden)C.send('info');}}};
  if(C.info)describe(C.info);
})();
