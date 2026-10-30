// SPDX-License-Identifier: MIT
// Shared Windows/macOS controller. MIDI channel numbers are zero-based on the wire.
(() => {
  'use strict';
  const $=id=>document.getElementById(id), C=window.ThreeEControl, P=window.ThreeEPrefs||{get:(n,f)=>f,set(){},onLoad(){}};
  const values=new Map(), dirty=new Map(), notes=new Set();
  let autoPicked=null;
  let channel=15, pianoChannel=Math.max(0,Math.min(14,Math.trunc(+P.get('pianoChannel',0))||0)), activeView="decks", output=-1, dirtyTimer, epoch=0;
  const studio=$('studio');
  studio.innerHTML=`<header><h1><span>3£</span> Phone Bar</h1></header>
  <div class="routing"><label>Output <select id="midiOutput" aria-label="MIDI output"><option value="-1">Choose MIDI output</option></select></label><label>Ch <select id="midiChannel" aria-label="MIDI channel"></select></label></div><p id="midiStatus" role="status">Choose a MIDI output and select 3E Phone Bar in Ableton’s Control Surface settings.</p>
  <div id="decksView" class="decks"></div><div id="mixerView" class="mixer" hidden></div>
  <div id="midiView" hidden><div class="piano-toolbar"><button id="octaveDown" aria-label="Lower octave">− Oct</button><output id="octaveLabel"></output><button id="octaveUp" aria-label="Higher octave">+ Oct</button><label>Velocity <input id="noteVelocity" type="range" min="1" max="127" value="100"></label></div><div id="piano" aria-label="MIDI piano keyboard"></div><p class="piano-hint">Hold notes together for chords · slide between keys</p></div>
  <div id="crossfaderPanel" class="crossfader"><label for="crossfader"><span>A</span><span>CROSSFADER</span><span>B</span></label><input id="crossfader" type="range" min="0" max="127" value="64" aria-label="Crossfader"></div>
  <div class="studio-footer"><span id="studioHint">Up turns right · turn the rim to rotate</span><button class="panic" id="panic">Release notes</button></div>
  <details class="studio-help"><summary>Connect to Ableton & control guide</summary><p>In Ableton’s Link, Tempo & MIDI settings, select <strong>3E Phone Bar</strong> as a Control Surface and choose <strong>3E Phone Bar</strong> as its Input. Output can stay None. Enable Track and Remote for that input. Restart Ableton once after installing 3E so the new surface appears.</p><p>Mac: 3E creates the port automatically. Windows: create a loopMIDI port named “3E Phone Bar”, select it here and as the surface Input in Ableton. The script is installed in existing Ableton User Libraries when Phone Bar starts.</p><p>Mixer controls tracks 1–8: volume, pan, Send A, mute and solo. Deck A/B control tracks 1/2. Launch fires the clip in the selected scene; Stop stops that track; Cue selects the track and clip. Using the crossfader assigns those two tracks to A/B. Jog wheels nudge a playing warped audio or MIDI clip. Add EQ Three and Auto Filter to a deck track for its EQ and filter knobs.</p><p>Mixer and decks use channel 16 automatically. The piano uses channel 1 by default, separately from control messages. Arm an instrument track and choose this MIDI input to play it. Hold several keys for chords or slide between them. Changing view, octave, channel or output releases held notes.</p><p>Move through a knob’s centre vertically for precision, or turn around its outer rim. Double-tap a knob to reset.</p><button id="refreshMidi">Refresh outputs</button></details>
  <nav class="studio-nav" aria-label="MIDI views"><div class="studio-tabs"><button id="decksTab" aria-pressed="true" aria-controls="decksView">DJ</button><button id="mixerTab" aria-pressed="false" aria-controls="mixerView">Mixer</button><button id="midiTab" aria-pressed="false" aria-controls="midiView">MIDI</button></div><button id="closeStudio" aria-label="Return to trackpad" title="Return to trackpad"><svg viewBox="0 0 32 32" aria-hidden="true"><rect x="4" y="5" width="24" height="22" rx="5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M4 21h24M16 21v6m3-16-5 4 5 4m-5-4h9" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></button></nav>`;
  for(let i=0;i<16;i++) {const option=document.createElement('option');option.value=i;option.textContent=i+1;$('midiChannel').append(option);} $('midiChannel').value='15';$('midiChannel').disabled=true;
  const valid=()=>C.connected()&&output>=0;
  function warn(){ $('midiStatus').textContent=C.connected()?'Choose a MIDI output to send controls.':'Reconnecting — controls will resume when connected.'; }
  function flush(){clearTimeout(dirtyTimer);dirtyTimer=null;if(valid()) for(const [number,value] of dirty) C.send('midiCC',{channel,number,value});dirty.clear();}
  function cc(number,value){value=Math.max(0,Math.min(127,Math.round(value)));values.set(number,value);render(number,value);if(!valid()){warn();return;}dirty.set(number,value);if(!dirtyTimer)dirtyTimer=setTimeout(flush,16);}
  function pulse(number){if(!valid()){warn();return;}flush();C.send('midiNote',{channel,number,value:127});notes.add(number);C.send('midiNote',{channel,number,value:0});notes.delete(number);}
  function render(number,value){
    window.ThreeEDJ?.control(number,value);
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
  let octave=Math.max(-1,Math.min(7,Math.trunc(+P.get('octave',4))));if(Number.isNaN(octave))octave=4;
  const contacts=new Map(), heldKeys=new Map(), activePointers=new Set(), piano=$('piano');
  const noteNames=['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
  function noteOff(number){if(!notes.has(number))return;C.send('midiNote',{channel,number,value:0});notes.delete(number);piano.querySelector('[data-note="'+number+'"]')?.classList.remove('held');}
  function releaseContact(id){const number=contacts.get(id);contacts.delete(id);if(number!==undefined&&![...contacts.values()].includes(number))noteOff(number);}
  function pressContact(id,number){
    if(contacts.get(id)===number)return;releaseContact(id);
    if(number===null||!valid()){if(number!==null)warn();return;}
    contacts.set(id,number);
    if(!notes.has(number)){flush();notes.add(number);C.send('midiNote',{channel,number,value:+$('noteVelocity').value});}
    piano.querySelector('[data-note="'+number+'"]')?.classList.add('held');
  }
  function drawPiano(){
    piano.replaceChildren();let white=0;
    for(let i=0;i<25;i++) {
      const number=(octave+1)*12+i,black=[1,3,6,8,10].includes(i%12),key=document.createElement('button');
      key.className='piano-key '+(black?'black':'white');key.dataset.note=number;key.type='button';
      const name=noteNames[number%12]+(Math.floor(number/12)-1);key.setAttribute('aria-label',name);key.title=name;
      if(black)key.style.left=((white-.31)/15*100)+'%';else {key.style.left=(white/15*100)+'%';white++;key.textContent=name;}
      key.addEventListener('keydown',e=>{if((e.key===' '||e.key==='Enter')&&!e.repeat){e.preventDefault();const id='key:'+number;heldKeys.set(number,id);pressContact(id,number);}});
      key.addEventListener('keyup',e=>{if(e.key===' '||e.key==='Enter'){e.preventDefault();releaseContact(heldKeys.get(number));heldKeys.delete(number);}});
      key.addEventListener('blur',()=>{releaseContact(heldKeys.get(number));heldKeys.delete(number);});
      // Assistive technology may activate a key without a pointer or key event.
      key.addEventListener('click',e=>{if(e.detail===0&&!notes.has(number)){pulse(number);}});
      piano.append(key);
    }
    $('octaveLabel').textContent='C'+octave+' – C'+(octave+2);$('octaveDown').disabled=octave===-1;$('octaveUp').disabled=octave===7;
  }
  const noteAt=e=>{const key=document.elementFromPoint(e.clientX,e.clientY)?.closest('.piano-key');return key&&piano.contains(key)?+key.dataset.note:null;};
  piano.addEventListener('pointerdown',e=>{if(e.button>0)return;e.preventDefault();piano.setPointerCapture(e.pointerId);activePointers.add(e.pointerId);pressContact(e.pointerId,noteAt(e));});
  piano.addEventListener('pointermove',e=>{if(activePointers.has(e.pointerId)&&piano.hasPointerCapture(e.pointerId)){e.preventDefault();pressContact(e.pointerId,noteAt(e));}});
  for(const type of ['pointerup','pointercancel','lostpointercapture'])piano.addEventListener(type,e=>{activePointers.delete(e.pointerId);releaseContact(e.pointerId);});
  piano.addEventListener('contextmenu',e=>e.preventDefault());
  for(const [id,direction] of [['octaveDown',-1],['octaveUp',1]])$(id).addEventListener('click',()=>{cancel();octave=Math.max(-1,Math.min(7,octave+direction));P.set('octave',octave);drawPiano();});
  drawPiano();
  function tab(name){cancel();activeView=name;P.set('view',name);channel=name==='midi'?pianoChannel:15;$('midiChannel').value=String(channel);$('midiChannel').disabled=name!=='midi';$('midiChannel').options[15].disabled=name==='midi';for(const view of ['decks','mixer','midi']){$(view+'View').hidden=view!==name;$(view+'Tab').setAttribute('aria-pressed',String(view===name));}$('crossfaderPanel').hidden=name==='midi'||name==='decks';$('studioHint').textContent=name==='midi'?'Hold keys to play · lift to release':'Up turns right · turn the rim to rotate';}
  for(const name of ['decks','mixer','midi'])$(name+'Tab').addEventListener('click',()=>tab(name));
  // Read the real Media target so the return target stays identical on phones,
  // landscape layouts, safe-area insets and the compact watch layout.
  function positionReturn(){
    if(studio.hidden)return;const media=$('media'),r=media.getBoundingClientRect(),style=getComputedStyle(media),back=$('closeStudio');
    for(const property of ['backgroundColor','border','borderRadius','padding','boxShadow'])back.style[property]=style[property];
    // Media is still physically held when this opens; use the idle dock color.
    back.style.color=getComputedStyle($('commands')).color;
    Object.assign(back.style,{position:'fixed',left:r.left+'px',top:r.top+'px',width:r.width+'px',minWidth:'0',height:r.height+'px',minHeight:'0'});
    studio.style.setProperty('--studio-bottom',(innerHeight-r.top+12)+'px');
    studio.style.setProperty('--studio-return-left',r.left+'px');
    studio.style.setProperty('--studio-return-top',r.top+'px');
    studio.style.setProperty('--studio-return-height',r.height+'px');
  }
  window.addEventListener('resize',positionReturn);window.visualViewport?.addEventListener('resize',positionReturn);
  if(window.ResizeObserver)new ResizeObserver(positionReturn).observe($('media'));
  function openStudio(){C.release();studio.hidden=false;positionReturn();C.send('info');}
  let returnPressed=false;
  $('closeStudio').addEventListener('pointerdown',()=>{returnPressed=true;});
  $('closeStudio').addEventListener('pointercancel',()=>{returnPressed=false;});
  $('closeStudio').addEventListener('click',e=>{if(e.detail&&!returnPressed)return;returnPressed=false;cancel();C.release();studio.hidden=true;$('media').focus({preventScroll:true});});
  $('refreshMidi').addEventListener('click',()=>C.send('info'));
  $('midiOutput').addEventListener('change',()=>{cancel();output=-1;const select=$('midiOutput');P.set('midiOutput',+select.value>=0?select.selectedOptions[0]?.textContent||null:null);C.send('midiPort',{id:+select.value});});
  $('midiChannel').addEventListener('change',()=>{cancel();C.send('midiPanic');channel=activeView==='midi'?Math.min(14,+$('midiChannel').value):15;if(activeView==='midi'){pianoChannel=channel;P.set('pianoChannel',channel);}});
  $('panic').addEventListener('click',()=>{cancel();C.send('midiPanic');});
  function cancel(){window.ThreeEDJ?.cancel();epoch++;window.ThreeEDock?.cancel();clearTimeout(dirtyTimer);dirtyTimer=null;dirty.clear();for(const number of notes)C.send('midiNote',{channel,number,value:0});notes.clear();contacts.clear();heldKeys.clear();for(const id of activePointers)if(piano.hasPointerCapture(id))piano.releasePointerCapture(id);activePointers.clear();piano.querySelectorAll('.held').forEach(key=>key.classList.remove('held'));}
  function describe(info){
    window.ThreeEDock?.describe(info);window.ThreeEDJ?.describe(info);
    if(!info?.midi)return;output=info.midi.selected;
    const select=$('midiOutput'),signature=JSON.stringify(info.midi.ports);
    if(select.dataset.ports!==signature){select.replaceChildren();const off=document.createElement('option');off.value=-1;off.textContent='MIDI off / choose output';select.append(off);for(const port of info.midi.ports){const item=document.createElement('option');item.value=port.id;item.textContent=port.name;select.append(item);}select.dataset.ports=signature;}
    // Reselect the output chosen last time (by name: port numbers can change).
    const wanted=P.get('midiOutput',null);if(output<0&&wanted){const match=info.midi.ports.find(port=>port.name===wanted);if(match&&autoPicked!==signature){autoPicked=signature;C.send('midiPort',{id:match.id});}}
    select.value=output;$('midiStatus').textContent=output>=0?'Sending to '+info.midi.status+' · Ableton: 3E Phone Bar':info.platform==='windows'?'Choose a MIDI output. Ableton uses a loopback port such as loopMIDI.':info.midi.status;
  }
  // The MIDI controls are in use while a note is held or the studio is open.
  window.ThreeESurface={cancel,describe,openStudio,setControl(number,value){values.set(number,value);render(number,value);},busy:()=>notes.size>0||!studio.hidden,state(ready){window.ThreeEDJ?.state(ready);if(!ready){cancel();studio.querySelectorAll('.vinyl').forEach(v=>v.classList.remove('is-spinning'));$('midiStatus').textContent='Disconnected — controls paused';}else {if(C.info)describe(C.info);if(!studio.hidden)C.send('info');}}};
  // Restore the rest of the studio as it was left: velocity, then view.
  function restore(){const velocity=+P.get('velocity',100);if(velocity>=1&&velocity<=127)$('noteVelocity').value=velocity;
    const p=Math.trunc(+P.get('pianoChannel',pianoChannel));if(p>=0&&p<=14)pianoChannel=p;
    const o=Math.trunc(+P.get('octave',octave));if(o>=-1&&o<=7&&o!==octave){octave=o;drawPiano();}
    const view=P.get('view','decks');if(['decks','mixer','midi'].includes(view)&&view!==activeView)tab(view);}
  $('noteVelocity').addEventListener('change',()=>P.set('velocity',+$('noteVelocity').value));
  restore();P.onLoad(()=>{restore();if(C.info)describe(C.info);});
  if(C.info)describe(C.info);
})();
