// Real browser + shared receiver; all music controls are captured by a fixture.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
(async()=>{
 const engine=process.env.PLAYWRIGHT_ENGINE==='webkit'?webkit:chromium;
 const options={headless:true};if(process.env.PLAYWRIGHT_BROWSER_PATH)options.executablePath=process.env.PLAYWRIGHT_BROWSER_PATH;
 const browser=await engine.launch(options),context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
 const p=await context.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto(fs.readFileSync(process.argv[2],'utf8').trim());await p.waitForFunction(()=>window.ThreeEControl?.connected());
 await p.evaluate(()=>{window.ThreeESurface.openStudio();window.djSent=[];const send=window.ThreeEControl.send;window.ThreeEControl.send=(type,c)=>{if(['dj','midiCC','midiNote'].includes(type))window.djSent.push({type,...c});else send(type,c);};});
 const values=[0,100,64,64,64,64,0,0,0,0,0,0,0,0],confirmed=Array(14).fill(true);
 const fixture={platform:'macos',midi:{selected:0,status:'Test MIDI',ports:[{id:0,name:'Test MIDI'}]},connection:{kind:'usb',routes:[]},controls:{dj:{available:true,paired:true,page:1,touchPage:0,target:'rekordbox',crossfader:64,decks:[{title:'Breaks 3',duration:218,elapsed:73,bpm:121,tempo:0,tempoRange:'±6',search:true,loopBeats:4,values,confirmed},{title:'House 4',duration:246,elapsed:25,bpm:121,tempo:-13.5,tempoRange:'±16',search:false,values,confirmed}]}},live:{decks:[{title:'Live Clip A',bpm:124,positionBeats:4,loopStart:0,loopEnd:16,beatsPerBar:4,looping:true,playing:true,values:[0,90,100,50,30,64,127,0,0,127,0,0,0,0],confirmed},{title:'Live Clip B',bpm:124,positionBeats:6,loopStart:0,loopEnd:8,beatsPerBar:4,looping:false,playing:false,values,confirmed}]}};
 await p.evaluate(info=>{window.djFixture=info;window.djDescribe=window.ThreeEDJ.describe;window.ThreeEDJ.describe=()=>window.djDescribe(window.djFixture);window.ThreeESurface.describe(info);},fixture);
 await p.waitForFunction(()=>document.querySelector('#studio').dataset.djActive==='true');
 assert.equal(await p.locator('.dj-card').count(),2);assert.equal(await p.locator('.dj-cue').count(),8);assert.equal(await p.locator('.dj-action').count(),8);
 assert.deepEqual(await p.locator('.dj-a .dj-cue').allTextContents(),['4','3','2','1']);assert.deepEqual(await p.locator('.dj-b .dj-cue').allTextContents(),['1','2','3','4']);
 assert.equal(await p.locator('.dj-vitals').first().textContent(),'121.000.0% ±6');assert.equal(await p.locator('.dj-card').first().getAttribute('data-search'),'true');
 await p.locator('#djMode').click();assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='page'&&c.page===0)));
 async function setMode(mode){await p.evaluate(mode=>{djFixture.controls.dj.page=mode;djFixture.controls.dj.touchPage=1-mode;window.ThreeESurface.describe(djFixture);},mode);}
 async function fits(label){await p.waitForTimeout(100);const result=await p.evaluate(()=>{
  const studio=document.querySelector('#studio'),stage=document.querySelector('.phone-dj'),rect=stage.getBoundingClientRect();
  const bad=[];for(const e of document.querySelectorAll('.dj-platter,.dj-action,.dj-cue,.dj-knob,.dj-level,#djCross,#djMode')){if(!e.getClientRects().length)continue;const r=e.getBoundingClientRect();if(r.left<rect.left-1||r.right>rect.right+1||r.top<rect.top-1||r.bottom>rect.bottom+1||r.width<16||r.height<16)bad.push([e.className,r.toJSON()]);const card=e.closest('.dj-card');if(card){const c=card.getBoundingClientRect();if(r.left<c.left-1||r.right>c.right+1||r.top<c.top-1||r.bottom>c.bottom+1)bad.push(['outside-deck',e.className]);}}
  return {scroll:studio.scrollHeight-studio.clientHeight,x:studio.scrollWidth-studio.clientWidth,top:studio.scrollTop,bad,squares:[...document.querySelectorAll('.dj-platter')].map(e=>Math.abs(e.clientWidth-e.clientHeight))};});
  assert.ok(result.scroll<=1&&result.x<=1&&result.top===0,label+' has no scroll range: '+JSON.stringify(result));assert.deepEqual(result.bad,[],label+' has clipped controls');assert.ok(result.squares.every(n=>n<=1),label+' has square wheels');
 }
 for(const size of [[390,844],[375,667],[320,568],[844,390],[667,375],[1024,768]]){
  await p.setViewportSize({width:size[0],height:size[1]});for(const mode of [0,1]){await setMode(mode);await fits(size.join('x')+' mode '+mode);}
 }
 await p.setViewportSize({width:390,height:844});await setMode(0);await p.screenshot({path:path.join(process.argv[3],'phone-dj-mix.png')});await setMode(1);await p.screenshot({path:path.join(process.argv[3],'phone-dj-pads.png')});
 await p.setViewportSize({width:844,height:390});await setMode(0);await p.screenshot({path:path.join(process.argv[3],'phone-dj-landscape.png')});
 // Dragging/resting never ends the native gesture early or scrolls the page.
 const wheel=p.locator('.dj-platter').first(),r=await wheel.boundingBox();await p.mouse.move(r.x+r.width*.45,r.y+r.height*.5);await p.mouse.down();await p.mouse.move(r.x+r.width*.45+16,r.y+r.height*.5,{steps:5});await p.waitForTimeout(450);
 assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='move'&&c.control===0)));assert.equal(await p.evaluate(()=>djSent.filter(c=>c.op==='end'&&c.control===0).length),0);await p.mouse.up();assert.equal(await p.evaluate(()=>djSent.filter(c=>c.op==='end'&&c.control===0).length),1);
 if(engine===webkit)assert.ok(await p.locator('#studio').evaluate(e=>{const event=new WheelEvent('wheel',{deltaY:600,cancelable:true,bubbles:true});e.dispatchEvent(event);return event.defaultPrevented;}));else await p.mouse.wheel(0,600);await fits('wheel gesture');
 // Setup remains reachable while the performance page itself cannot scroll.
 await p.locator('#djSetupOpen').click();assert.ok(await p.locator('#djSetup').evaluate(e=>e.open));await p.locator('#djSetupClose').click();
 await p.evaluate(()=>{window.ThreeESurface.describe(window.djFixture);const old=window.ThreeEDJ.describe;window.ThreeEDJ.describe=info=>window.partialMidi=info.midi;window.ThreeESurface.describe({platform:'macos',live:djFixture.live});window.ThreeEDJ.describe=old;});assert.equal(await p.evaluate(()=>window.partialMidi.selected),0);
 await p.locator('#djAbleton').click();assert.equal(await p.locator('.dj-track h2').first().textContent(),'Live Clip A');assert.match(await p.locator('.dj-time').first().textContent(),/Beat 5/);assert.equal(await p.locator('.dj-a .dj-knob[data-index="2"] output').textContent(),'100');
 assert.equal(await p.locator('.dj-a .dj-action[data-index="8"]').textContent(),'STOP');
 await p.locator('.dj-a [data-loop="half"]').click();assert.ok(await p.evaluate(()=>djSent.some(c=>c.type==='midiNote'&&c.number===80&&c.channel===15&&c.value===127)));
 await p.locator('.dj-b [data-loop="double"]').click();assert.ok(await p.evaluate(()=>djSent.some(c=>c.type==='midiNote'&&c.number===83&&c.value===127)));
 await p.locator('.dj-a [data-loop="size"]').click();await p.locator('[data-bars="2"]').click();assert.ok(await p.evaluate(()=>djSent.some(c=>c.type==='midiNote'&&c.number===86&&c.value===127)));
 await p.locator('.dj-a .dj-wheel-mode').click();assert.match(await p.locator('.dj-a .dj-wheel-mode').textContent(),/FINE/);
 const fine=await wheel.boundingBox();await p.mouse.move(fine.x+fine.width*.45,fine.y+fine.height*.5);await p.mouse.down();await p.mouse.move(fine.x+fine.width*.45+24,fine.y+fine.height*.5,{steps:4});await p.mouse.up();assert.ok(await p.evaluate(()=>djSent.some(c=>c.type==='midiCC'&&c.number===42&&c.value>64)));
 for(const size of [[390,844],[375,667],[320,568],[844,390],[667,375]]){await p.setViewportSize({width:size[0],height:size[1]});await fits('Live '+size.join('x'));}
 await p.setViewportSize({width:844,height:390});await p.screenshot({path:path.join(process.argv[3],'phone-live-landscape.png')});
 // Mixer banks and piano fit the same viewport without scrolling.
 for(const size of [[390,844],[375,667],[844,390],[667,375]]){
  await p.setViewportSize({width:size[0],height:size[1]});
  for(const tab of ['mixer','midi']){
   await p.locator('#'+tab+'Tab').click();await p.waitForTimeout(100);
   const layout=await p.locator('#studio').evaluate(e=>{const r=e.getBoundingClientRect();const bad=[];for(const item of e.querySelectorAll('#mixerView .control,#mixerView .strip-buttons,#midiView .piano-toolbar,#piano')){if(!item.getClientRects().length)continue;const q=item.getBoundingClientRect();if(q.left<r.left-1||q.right>r.right+1||q.bottom>r.bottom-45||q.top<r.top)bad.push([item.className,q.toJSON()]);}return {scroll:e.scrollHeight-e.clientHeight,width:e.scrollWidth-e.clientWidth,bad};});
   assert.ok(layout.scroll<=1&&layout.width<=1,tab+' '+size+' cannot scroll: '+JSON.stringify(layout));assert.deepEqual(layout.bad,[],tab+' '+size+' clips controls');
  }
 }
 await p.locator('#mixerTab').click();assert.equal(await p.locator('.strip:visible').count(),4);await p.locator('#mixerBank').click();assert.equal(await p.locator('.strip:visible h2').first().textContent(),'TRACK 5');
 await p.locator('#studioSetupOpen').click();assert.ok(await p.locator('#studioSetup').evaluate(e=>e.open));await p.locator('#studioSetupClose').click();
 await p.locator('#decksTab').click();
 await p.evaluate(()=>window.ThreeESurface.state(false));assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='cancel')));assert.deepEqual(errors,[]);
 await browser.close();console.log('PASS: scroll-free portrait/landscape decks, persistent transport, exact pad order, independent wheel lifecycle, Live feedback, fine jog, loop sizing, setup and disconnect cleanup');
})().catch(e=>{console.error(e);process.exit(1)});
