// SPDX-License-Identifier: MIT
// Phone-sized sibling of Touch DJ. Native Mac gestures use the same engine;
// standalone MIDI keeps its own explicit routing and never invents deck data.
(() => {
  'use strict';
  const $=id=>document.getElementById(id),C=window.ThreeEControl,P=window.ThreeEPrefs;
  const root=$('decksView');if(!root)return;
  root.className='phone-dj';
  root.innerHTML=`<div class="dj-toolbar"><strong class="dj-brand">3£</strong><div class="dj-hosts"><button id="djRekordbox">rekordbox</button><button id="djAbleton">Ableton Live</button></div><button class="dj-settings" id="djSetupOpen" aria-label="DJ connection and help">⚙</button><button class="dj-panic" id="djRelease" aria-label="Release held DJ controls" title="Release held controls">⏏</button></div>
  <div class="dj-decks"></div><div class="dj-hub"><button id="djMode" aria-label="Switch mixer and performance views">MIX <span>⇄ PADS</span></button><label class="dj-cross"><span>A</span><input id="djCross" type="range" min="0" max="127" value="64" aria-label="DJ crossfader"><span>B</span></label><span class="dj-live-status"><i class="dj-connection-dot"></i><span id="djLink">PHONE DJ</span></span></div>
  <dialog class="dj-dialog" id="djSetup"><header><h2>DJ connection</h2><button id="djSetupClose">Done</button></header><label>Control route<select id="djTarget"><option value="auto">Touch DJ · follow app</option><option value="auto-rekordbox">rekordbox · Touch DJ</option><option value="ableton">Ableton · Phone Bar clips</option><option value="auto-live">Ableton · custom Touch DJ mapping</option><option value="rekordbox">rekordbox · standalone MIDI</option></select></label><label>MIDI output<select id="djOutput"><option value="-1">Choose output</option></select></label><p id="djConnection">Local network</p><button id="djUSB" hidden>Use USB</button><p id="djNotice" role="status"></p><details class="dj-help"><summary>Playing & setup</summary><p>Both decks fit on the performance screen. MIX and PADS change the lower controls; Play, Cue/Select, Sync/Stop and Loop stay within reach. When linked to Touch DJ, either screen switches the complementary view.</p><p>rekordbox: use the existing 3£ DJ mapping. Tap the mode chip or disc to switch SEEK/BEND. Turn the rim or drag horizontally. SEEK holds position until you lift. The song, BPM, time, artwork and progress come from the loaded deck when available. Loop uses your mapped Auto Loop.</p><p>Ableton: choose 3E Phone Bar as a Control Surface with the 3E Phone Bar input. Restart Live once after this update to load its new script. Tracks 1/2 are the decks; pads launch existing clips in scenes 1–4. Wheels jog a playing MIDI or warped-audio clip, with JOG and FINE sensitivity. Loop controls halve/double the existing loop or set 1, 2, 4 or 8 bars. Actual clip names, positions, loop lengths and mixer values appear when Live’s script is running. Add EQ Three and Auto Filter to use their knobs.</p><p>USB: trust this computer and enable Personal Hotspot. On Windows install Apple Devices first. A charging cable alone does not create a data connection. Without host feedback, the display shows unavailable fields instead of simulating playback.</p></details></dialog>
  <dialog class="dj-dialog" id="djLoopSheet"><header><h2 id="djLoopTitle">Loop size</h2><button id="djLoopClose">Done</button></header><div class="dj-loop-choices">${[1,2,4,8].map(n=>'<button data-bars="'+n+'">'+n+' '+(n===1?'bar':'bars')+'</button>').join('')}</div><p>Sets this clip’s loop length from its current loop start. MIDI or warped audio clips only.</p></dialog>`;
  let selection=P?.get('djTarget','auto')||'auto', page=0, info={}, native=null, enabled=false, active=false, serial=0, lastPoll=0, lastFullPoll=0;
  let decks=[{},{}],cross=64, usbHost=null, loopDeck=0, sampled=performance.now();
  const contacts=new Map(),localValues=Array.from({length:2},()=>[0,100,64,64,64,64,0,0,0,0,0,0,0,0]);
  const wheels=[],cards=[];
  $('djTarget').value=selection;
  const linked=()=>selection.startsWith('auto')&&native?.available===true;
  const ableton=()=>selection==='ableton'||selection==='auto'&&!linked();
  const requestedTarget=()=>selection==='auto-live'?'live':selection==='auto-rekordbox'?'rekordbox':null;
  const available=()=>C.connected()&&(!requestedTarget()||native?.target===requestedTarget())&&(linked()||info.midi?.selected>=0);
  const command=(op,extra={})=>{if(C.connected())C.send('dj',{op,...extra});};
  const midi=(note,channel,number,value)=>{if(C.connected()&&info.midi?.selected>=0)C.send(note?'midiNote':'midiCC',{channel,number,value:Math.max(0,Math.min(127,Math.round(value)))});};
  function localCC(d,i,value){localValues[d][i]=Math.max(0,Math.min(127,Math.round(value)));const rb=[0,7,16,17,18,19][i],live=[0,16+d,54+d,52+d,50+d,48+d][i];midi(false,ableton()?15:d,ableton()?live:rb,localValues[d][i]);if(ableton()&&window.ThreeESurface?.setControl)window.ThreeESurface.setControl(live,localValues[d][i]);renderValues(d);}
  function localNote(d,i,down){let number=i<10?i-6:16+i-10;
    if(ableton()){number=i===6?36+d:i===7?38+d:i===8?42+d:i===9?64+d:68+d*4+i-10;}
    midi(true,ableton()?15:d,number,down?127:0);
  }
  function cancel(){for(const [id,g] of contacts)end(id,true);contacts.clear();if(enabled)command('cancel');}
  function setPage(next){cancel();if(linked())command('page',{page:next});else{page=next;drawMode();}}
  function drawMode(){root.dataset.mode=page?'pads':'mix';$('djMode').innerHTML=(page?'PADS':'MIX')+' <span>⇄ '+(page?'MIX':'PADS')+'</span>';for(const card of cards){card.querySelector('.dj-mix').hidden=!!page;card.querySelector('.dj-performance').hidden=!page;}}
  function renderValues(d){const values=linked()||ableton()&&info.live?decks[d]?.values||localValues[d]:localValues[d];for(let i=1;i<6;i++){const el=cards[d].querySelector('[data-index="'+i+'"]');if(!el)continue;let value=values[i]??(i===1?100:64);const held=[...contacts.values()].find(g=>g.d===d&&g.i===i);if(held&&!linked())value=held.value;el.style.setProperty('--value',value);el.style.setProperty('--turn',(-135+value/127*270)+'deg');el.setAttribute('aria-valuenow',Math.round(value));el.querySelector('output').textContent=Math.round(value);if(i===1)el.querySelector('input').value=value;}}
  function pointer(el,d,i){el.addEventListener('pointerdown',e=>{if(e.button>0||!available()||ableton()&&info.live&&i===0&&decks[d]?.canJog===false||[...contacts.values()].some(g=>g.d===d&&g.i===i))return;e.preventDefault();el.setPointerCapture(e.pointerId);const r=el.getBoundingClientRect(),id=++serial%1000000;
    const value=(linked()||ableton()&&info.live?decks[d]?.values:localValues[d])?.[i]??64;
    const g={id,d,i,el,x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,value,base:value,baseAngle:+(wheels[d].dataset.angle||0),travel:0,moved:false,at:performance.now(),motion:performance.now(),angle:Math.atan2(e.clientY-r.top-r.height/2,e.clientX-r.left-r.width/2),cx:r.left+r.width/2,cy:r.top+r.height/2,radius:r.width/2,circular:i===0&&Math.hypot(e.clientX-r.left-r.width/2,e.clientY-r.top-r.height/2)>r.width*.32};
    contacts.set(e.pointerId,g);el.classList.add('dj-held');
    if(linked())command('begin',{control:d*14+i,id});else if(i>=6)localNote(d,i,true);
    if(i===1)move(e);
  });el.addEventListener('pointermove',move);for(const type of ['pointerup','pointercancel','lostpointercapture'])el.addEventListener(type,e=>{if(type==='pointerup'&&contacts.has(e.pointerId))move(e);end(e.pointerId,type!=='pointerup');});
    el.addEventListener('dblclick',()=>{if(i>0&&i<6&&!linked())localCC(d,i,i===1?100:64);});
  }
  function move(e){const g=contacts.get(e.pointerId);if(!g)return;e.preventDefault();const dx=e.clientX-g.x,dy=e.clientY-g.y,now=performance.now();if(Math.hypot(dx,dy)>3)g.moved=true;
    if(g.i>=6)return;
    if(g.i===0){let change;if(g.circular){const angle=Math.atan2(e.clientY-g.cy,e.clientX-g.cx);change=angle-g.angle;if(change>Math.PI)change-=2*Math.PI;if(change<-Math.PI)change+=2*Math.PI;g.angle=angle;g.travel+=change*60;}else {change=(e.clientX-g.lastX)*.45;g.travel+=change;}
      g.lastX=e.clientX;g.lastY=e.clientY;
      if(linked())command('move',{control:g.d*14,id:g.id,x:g.travel});else if(ableton()){const ticks=Math.trunc((g.travel-(g.sent||0))/2.4);if(ticks){const step=Math.max(-63,Math.min(63,ticks));midi(false,15,(decks[g.d].search?42:40)+g.d,64+step);g.sent=(g.sent||0)+step*2.4;}}
      else if(g.moved){const search=!!decks[g.d].search,note=search?(change>0?8:7):(change>0?6:5);if(Math.abs(change)>.2&&note!==g.note){if(g.note)midi(true,g.d,g.note,0);midi(true,g.d,note,127);g.note=note;}}
      if(Math.abs(change)>.2)g.motion=now;return;
    }
    const r=g.el.getBoundingClientRect();let x;
    if(g.i===1)x=Math.max(0,Math.min(1,(r.bottom-e.clientY)/r.height));
    else {if(!g.axis&&Math.hypot(dx,dy)>3)g.axis=Math.abs(dy)>Math.abs(dx)?'y':'x';x=(g.axis==='y'?-dy:dx)/Math.max(40,r.width-10);}
    if(Math.abs(x-g.travel)>.006){g.travel=x;g.motion=now;}
    if(linked())command('move',{control:g.d*14+g.i,id:g.id,x});
    else {g.value=g.i===1?x*127:Math.max(0,Math.min(127,g.base+Math.sign(x)*127*Math.pow(Math.abs(x),1.35)+ (g.hold||0)));localCC(g.d,g.i,g.value);}
  }
  function end(pointer,cancelled){const g=contacts.get(pointer);if(!g)return;contacts.delete(pointer);g.el.classList.remove('dj-held');if(linked())command(cancelled?'abort':'end',{control:g.d*14+g.i,id:g.id});else{if(g.i>=6)localNote(g.d,g.i,false);if(g.note)midi(true,g.d,g.note,0);if(g.i===0&&!cancelled&&!g.moved&&performance.now()-g.at<300){decks[g.d].search=!decks[g.d].search;paint();}}}
  for(let d=0;d<2;d++){const card=document.createElement('section');card.className='dj-card '+(d?'dj-b':'dj-a');card.innerHTML=`<header class="dj-track"><div class="dj-track-title"><h2>Deck ${d?'B':'A'}</h2><p><b class="dj-letter">${d?'B':'A'}</b> · <span class="dj-time">— / —</span></p></div><div class="dj-vitals"><strong>—<small></small></strong><span>—% <em>—</em></span></div></header><div class="dj-wheel-zone"><div class="dj-wheel-well"><div class="dj-platter" role="slider" tabindex="0" aria-label="Deck ${d?'B':'A'} wheel" aria-valuemin="0" aria-valuemax="127"><div class="dj-record"><img hidden alt="Loaded track artwork"></div><i class="dj-spindle"></i><svg viewBox="0 0 100 100" aria-hidden="true"><circle class="dj-outline" cx="50" cy="50" r="46"/><circle class="dj-mode-arc" cx="50" cy="50" r="46"/><circle class="dj-inner" cx="50" cy="50" r="38"/><circle class="dj-progress-ring" cx="50" cy="50" r="38"/></svg></div></div><button class="dj-wheel-mode" aria-label="Change deck ${d?'B':'A'} wheel mode">BEND <small>temporary tempo</small></button><div class="dj-loop-tools" hidden><button data-loop="half" aria-label="Halve deck ${d?'B':'A'} loop">½</button><button data-loop="size" aria-label="Choose deck ${d?'B':'A'} loop size">Loop size</button><button data-loop="double" aria-label="Double deck ${d?'B':'A'} loop">2×</button></div></div><div class="dj-transport"></div><div class="dj-mix"><div class="dj-eq"></div><div class="dj-level" data-index="1" role="slider" tabindex="0" aria-label="Deck ${d?'B':'A'} level" aria-valuemin="0" aria-valuemax="127"><span>LEVEL</span><div><input tabindex="-1" type="range" min="0" max="127" value="100" aria-hidden="true"><i class="dj-fader-track"></i></div><output>100</output></div></div><div class="dj-performance" hidden><div class="dj-hotcues"></div></div>`;
    cards.push(card);root.querySelector('.dj-decks').append(card);const wheel=card.querySelector('.dj-platter');wheels.push(wheel);pointer(wheel,d,0);wheel.addEventListener('keydown',e=>{if(!['ArrowLeft','ArrowRight',' ','Enter'].includes(e.key)||!available())return;e.preventDefault();if(linked()){command('begin',{control:d*14,id:999997});if(e.key.startsWith('Arrow'))command('move',{control:d*14,id:999997,x:e.key==='ArrowRight'?2:-2});command('end',{control:d*14,id:999997});}else if(e.key.startsWith('Arrow')){if(ableton())midi(false,15,(decks[d].search?42:40)+d,e.key==='ArrowRight'?65:63);else{const n=decks[d].search?(e.key==='ArrowRight'?8:7):(e.key==='ArrowRight'?6:5);midi(true,d,n,127);midi(true,d,n,0);}}else{decks[d].search=!decks[d].search;paint();}});pointer(card.querySelector('.dj-level'),d,1);
    for(let i=2;i<6;i++){const knob=document.createElement('button');knob.className='dj-knob';knob.dataset.index=i;knob.setAttribute('role','slider');knob.setAttribute('aria-label','Deck '+(d?'B':'A')+' '+['','','HI','MID','LOW','FILTER'][i]);knob.setAttribute('aria-valuemin','0');knob.setAttribute('aria-valuemax','127');knob.innerHTML='<span class="dj-dial"><i></i></span><strong>'+['','','HI','MID','LOW','FILTER'][i]+'</strong><output>64</output>';card.querySelector('.dj-eq').append(knob);pointer(knob,d,i);knob.addEventListener('keydown',e=>{if(['ArrowUp','ArrowRight','ArrowDown','ArrowLeft','Home','End'].includes(e.key)){e.preventDefault();if(linked()){command('begin',{control:d*14+i,id:999999});command('move',{control:d*14+i,id:999999,x:e.key==='Home'?-1:e.key==='End'?1:['ArrowUp','ArrowRight'].includes(e.key)?.03:-.03});command('end',{control:d*14+i,id:999999});}else localCC(d,i,e.key==='Home'?0:e.key==='End'?127:localValues[d][i]+(['ArrowUp','ArrowRight'].includes(e.key)?1:-1));}});}
    for(let i=6;i<14;i++){const button=document.createElement('button');button.className=i<10?'dj-action':'dj-cue';button.dataset.index=i;button.textContent=i<10?['▶','CUE','SYNC','LOOP'][i-6]:i-9;button.setAttribute('aria-label','Deck '+(d?'B':'A')+' '+(i<10?['Play/pause','Cue','Sync','Loop'][i-6]:'Hot cue '+(i-9)));card.querySelector(i<10?'.dj-transport':'.dj-hotcues').append(button);pointer(button,d,i);button.addEventListener('click',e=>{if(e.detail===0&&available()){if(linked()){command('begin',{control:d*14+i,id:999999});command('end',{control:d*14+i,id:999999});}else{localNote(d,i,true);localNote(d,i,false);}}});}
    card.querySelector('.dj-wheel-mode').addEventListener('click',()=>{if(!available())return;if(linked()){command('begin',{control:d*14,id:999996});command('end',{control:d*14,id:999996});}else{decks[d].search=!decks[d].search;paint();}});
    card.querySelectorAll('[data-loop]').forEach(button=>button.addEventListener('click',()=>{if(!ableton()||!available())return;const action=button.dataset.loop;if(action==='size'){cancel();loopDeck=d;$('djLoopTitle').textContent='Deck '+(d?'B':'A')+' · Loop size';$('djLoopSheet').showModal();}else{midi(true,15,(action==='half'?80:82)+d,127);midi(true,15,(action==='half'?80:82)+d,0);}}));
    const cues=card.querySelector('.dj-hotcues');if(!d)[...cues.children].reverse().forEach(b=>cues.append(b));
  }
  function time(seconds){if(!Number.isFinite(seconds))return '—';return Math.floor(Math.max(0,seconds)/60).toString().padStart(2,'0')+':'+Math.floor(Math.max(0,seconds)%60).toString().padStart(2,'0');}
  function paint(){for(let d=0;d<2;d++){
      const deck=decks[d]||{},card=cards[d],face=card.querySelector('.dj-vitals'),live=ableton(),search=!!deck.search;
      card.querySelector('h2').textContent=deck.title||(live?'Track '+(d+1):'Deck '+(d?'B':'A'));
      card.querySelector('.dj-time').textContent=live?(Number.isFinite(deck.positionBeats)?'Beat '+(deck.positionBeats+1).toFixed(1):'Awaiting Live'):time(deck.elapsed)+' / '+time(deck.duration);
      const bpm=Number.isFinite(deck.bpm)?deck.bpm.toFixed(2).split('.'):['—',''];face.querySelector('strong').firstChild.textContent=bpm[0];face.querySelector('strong small').textContent=bpm[1]?'.'+bpm[1]:'';
      face.querySelector('span').firstChild.textContent=live?'LIVE BPM ': (Number.isFinite(deck.tempo)?(deck.tempo>0?'+':'')+deck.tempo.toFixed(1):'—')+'% ';face.querySelector('em').textContent=live?'':deck.tempoRange||'—';
      const art=card.querySelector('.dj-record img'),uri=typeof deck.artwork==='string'&&/^data:image\/jpeg;base64,[a-zA-Z0-9+/=]+$/.test(deck.artwork)&&deck.artwork.length<40000?deck.artwork:null;
      if(uri&&art.getAttribute('src')!==uri)art.src=uri;art.hidden=!uri;if(!uri)art.removeAttribute('src');
      wheels[d].setAttribute('aria-valuetext',(deck.title||'Deck '+(d?'B':'A'))+', '+(live?(search?'Fine clip jog':'Clip jog'):search?'Seek':'Bend')+', '+(Number.isFinite(deck.bpm)?deck.bpm.toFixed(2)+' BPM':'BPM unavailable'));
      card.dataset.search=String(search);wheels[d].setAttribute('aria-disabled',String(live&&info.live&&deck.canJog===false));
      card.querySelector('.dj-wheel-mode').innerHTML=(live?(search?'FINE':'JOG'):search?(linked()?'SEEK':'SCAN'):'BEND')+' <small>'+(live?(deck.recording?'recording':deck.canJog===false?'play a clip':search?'1/64 beat':'1/16 beat'):search?'hold to cue':'temporary tempo')+'</small>';
      card.querySelector('.dj-loop-tools').hidden=!live;
      const length=deck.loopEnd-deck.loopStart,bar=deck.beatsPerBar||4;
      card.querySelector('[data-loop=size]').textContent=Number.isFinite(length)&&length>0?(+(length/bar).toFixed(2))+' bars':'Loop size';
      renderValues(d);
      card.querySelectorAll('.dj-action,.dj-cue').forEach(button=>{
        const i=+button.dataset.index;
        button.setAttribute('aria-label','Deck '+(d?'B':'A')+' '+(i>=10?(live?'Scene ':'Hot cue ')+(i-9):live?['Launch / stop clip','Select clip','Stop clips','Loop'][i-6]:['Play / pause','Cue','Sync','Loop'][i-6]));
        if(i<10)button.textContent=live?['▶','SELECT','STOP','LOOP'][i-6]:['▶','CUE','SYNC','LOOP'][i-6];
        if(i===9&&(live?Number.isFinite(length):Number.isFinite(deck.loopBeats))){const small=document.createElement('small');small.textContent=live?+(length/bar).toFixed(2)+' bars':deck.loopBeats+' beats';button.append(small);}
        button.classList.toggle('confirmed',!!deck.confirmed?.[i]);button.classList.toggle('is-on',!!deck.confirmed?.[i]&&(deck.values?.[i]||0)>0);button.disabled=!available()||live&&i===9&&deck.canLoop===false;
      });
      card.querySelectorAll('[data-loop]').forEach(b=>b.disabled=!available()||deck.canLoop===false);
    }
    if(document.activeElement!==$('djCross'))$('djCross').value=cross;
    root.dataset.ready=String(available());$('djRekordbox').setAttribute('aria-pressed',String(!ableton()&&native?.target!=='live'));$('djAbleton').setAttribute('aria-pressed',String(ableton()||linked()&&native.target==='live'));
  }
  function describe(next){const oldPage=page;info=next||{};native=info.controls?.dj||null;if(linked()){decks=native.decks||[{},{}];page=native.page;cross=native.crossfader;if(page!==oldPage)cancel();}else if(ableton()){const modes=decks.map(d=>!!d.search);decks=(info.live?.decks||[{},{}]).map((d,i)=>({...d,search:modes[i]}));}sampled=performance.now();
    $('studio').dataset.djLinked=String(linked());
    $('djLink').textContent=ableton()?(info.live?'LIVE · CLIPS':'LIVE · MIDI'):linked()&&native.paired?'LINKED · TOUCH BAR '+(native.touchPage?'PADS':'MIX'):'PHONE DJ';
    $('djNotice').textContent=linked()?(native.paired?'Switch either screen to swap MIX and PADS.':'Both modes are available here. Open Touch DJ to link the Touch Bar.'):selection.startsWith('auto')&&info.platform==='macos'?'Connecting to Touch DJ…':ableton()?'Ableton · tracks 1/2 · scenes 1–4. Add EQ Three and Auto Filter.':'rekordbox · use MIDI Learn for this output. Live deck data is unavailable on this connection.';
    const out=$('djOutput'),signature=JSON.stringify(info.midi?.ports||[]);if(out.dataset.ports!==signature){out.replaceChildren(new Option('Choose output',-1));for(const port of info.midi?.ports||[])out.add(new Option(port.name,port.id));out.dataset.ports=signature;}out.value=info.midi?.selected??-1;
    const connection=info.connection;usbHost=connection?.routes?.find(r=>r.kind==='usb')?.host||null;$('djConnection').textContent=connection?.kind==='usb'?'USB · wired':connection?.kind==='wifi'?'Wi-Fi':connection?.kind==='ethernet'?'Ethernet':'Local connection';$('djUSB').hidden=!usbHost||connection?.kind==='usb';drawMode();paint();
  }
  $('djMode').addEventListener('click',()=>setPage(1-page));
  $('djTarget').addEventListener('change',()=>{cancel();selection=$('djTarget').value;P?.set('djTarget',selection);if(selection==='ableton'&&(info.midi?.selected??-1)<0){const port=info.midi?.ports?.find(p=>/^3(?:E|£) Phone Bar$/i.test(p.name));if(port){$('midiOutput').value=port.id;$('midiOutput').dispatchEvent(new Event('change'));}}decks=[{},{}];if(selection.startsWith('auto')){command('open');if(selection!=='auto')command('target',{target:selection==='auto-live'?'live':'rekordbox'});}describe(info);});
  $('djCross').addEventListener('input',()=>{cross=+$('djCross').value;if(linked()){command('begin',{control:28,id:999998});command('move',{control:28,id:999998,x:cross/127});command('end',{control:28,id:999998});}else midi(false,15,ableton()?1:8,cross);});
  $('djUSB').addEventListener('click',()=>{if(!usbHost||!/^\d+\.\d+\.\d+\.\d+:\d+$/.test(usbHost))return;cancel();C.release();location.assign('http://'+usbHost+'/?usb=1'+location.hash);});
  $('djSetupOpen').addEventListener('click',()=>{cancel();$('djSetup').showModal();});
  $('djSetupClose').addEventListener('click',()=>$('djSetup').close());$('djLoopClose').addEventListener('click',()=>$('djLoopSheet').close());
  $('djRelease').addEventListener('click',()=>{cancel();C.send('midiPanic');});
  $('djOutput').addEventListener('change',()=>{const output=$('midiOutput');output.value=$('djOutput').value;output.dispatchEvent(new Event('change'));});
  $('djRekordbox').addEventListener('click',()=>{$('djTarget').value=info.platform==='macos'?'auto-rekordbox':'rekordbox';$('djTarget').dispatchEvent(new Event('change'));});
  $('djAbleton').addEventListener('click',()=>{$('djTarget').value='ableton';$('djTarget').dispatchEvent(new Event('change'));});
  $('djLoopSheet').querySelectorAll('[data-bars]').forEach(button=>button.addEventListener('click',()=>{if(ableton()&&available()){const note=84+[1,2,4,8].indexOf(+button.dataset.bars)*2+loopDeck;midi(true,15,note,127);midi(true,15,note,0);}$('djLoopSheet').close();}));
  const resize=()=>{$('studio').style.setProperty('--dj-height',(window.visualViewport?.height||innerHeight)+'px');};resize();window.addEventListener('resize',resize);window.visualViewport?.addEventListener('resize',resize);
  $('studio').addEventListener('wheel',event=>{if(active&&!event.target.closest('dialog'))event.preventDefault();},{passive:false});
  $('studio').addEventListener('touchmove',event=>{if(active&&!event.target.closest('dialog'))event.preventDefault();},{passive:false});
  window.addEventListener('blur',cancel);document.addEventListener('visibilitychange',()=>{if(document.hidden)cancel();});
  let previous=performance.now();function frame(now){const dt=Math.max(0,Math.min(.05,(now-previous)/1000));previous=now;const visible=!$('studio').hidden&&!root.hidden&&!document.hidden;
    if(visible){$('crossfaderPanel').hidden=true;if(now-lastFullPoll>2000){lastFullPoll=now;C.send('info');}if(now-lastPoll>125){lastPoll=now;if(selection.startsWith('auto')){command('state');if(requestedTarget()&&native?.available&&native.target!==requestedTarget())command('target',{target:requestedTarget()});}C.send('ping');}
      for(const g of contacts.values())if(!linked()&&g.i>1&&g.i<6&&now-g.motion>350&&Math.abs(g.travel)>.01){const rate=Math.sign(g.travel)*(6+18*Math.min(1,Math.abs(g.travel)*2));g.hold=(g.hold||0)+rate*dt;g.value=Math.max(0,Math.min(127,g.value+rate*dt));localCC(g.d,g.i,g.value);}
      for(const g of contacts.values())if(!linked()&&!ableton()&&g.i===0&&g.note&&now-g.motion>=220){midi(true,g.d,g.note,0);g.note=null;}
      for(let d=0;d<2;d++){const g=[...contacts.values()].find(g=>g.d===d&&g.i===0);let angle=+(wheels[d].dataset.angle||0);if(g)angle=g.baseAngle+(g.circular?g.travel/60:g.travel/.45/Math.max(36,g.radius))*180/Math.PI;else if(decks[d]?.playing&&!matchMedia('(prefers-reduced-motion: reduce)').matches)angle+=dt*200;wheels[d].dataset.angle=angle;wheels[d].querySelector('.dj-record').style.transform='rotate('+angle+'deg)';const deck=decks[d]||{};const elapsed=deck.elapsed+(deck.playing&&!g?Math.min(2,(now-sampled)/1000):0);const length=deck.loopEnd-deck.loopStart;const progress=ableton()?(length>0?Math.max(0,Math.min(1,(deck.positionBeats-deck.loopStart)/length)):0):deck.duration>0?Math.max(0,Math.min(1,elapsed/deck.duration)):0;wheels[d].querySelector('.dj-progress-ring').style.strokeDasharray=(progress*238.76)+' 238.76';}
    }$('studio').dataset.djActive=String(visible);if(visible!==active){active=visible;if(visible){enabled=true;if(selection.startsWith('auto'))command('open');}else{cancel();command('close');enabled=false;}}requestAnimationFrame(frame);
  }requestAnimationFrame(frame);
  window.ThreeEDJ={cancel,describe,control(number,value){if(!linked()&&ableton())for(let d=0;d<2;d++)for(let i=1;i<6;i++)if([0,16+d,54+d,52+d,50+d,48+d][i]===number){localValues[d][i]=value;renderValues(d);}},state(ready){if(!ready){cancel();native=null;decks=[{},{}];paint();}},busy:()=>contacts.size>0};
  drawMode();paint();
})();
