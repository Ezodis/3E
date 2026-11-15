const assert=require('node:assert/strict'),fs=require('node:fs');
const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
(async()=>{
 const browser=await (process.env.PLAYWRIGHT_ENGINE==='webkit'?webkit:chromium).launch({headless:true}),context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
 const p=await context.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto(fs.readFileSync(process.argv[2],'utf8').trim());await p.waitForFunction(()=>window.ThreeEControl?.connected());
 await p.evaluate(()=>{
  ThreeESurface.openStudio();window.sent=[];
  const send=ThreeEControl.send;ThreeEControl.send=(type,c)=>{if(['performance','midiNote','midiCC','dj'].includes(type)){sent.push({type,...c});return true;}return send(type,c);};
  window.fixture={time:Date.now()/1000,session_id:'test-session',protocol:1,track_index:1,track_name:'P2 CHORDS',record:false,playing:false,song_presets:true,scale_supported:true,scale_mode:true,root_note:1,scale_intervals:[0,2,4,5,7,9,11],piano_modes:{2:0},piano_mode_labels:{2:['Chord','Arpeggio','Bounce','RUFF']},selected_clip:{token:'clip-1',has_clip:true,can_create:false,midi:true}};
  window.describe=ThreeEPerformance.describe;ThreeEPerformance.describe=()=>{fixture.time=Date.now()/1000;describe({performance:fixture});};ThreeEPerformance.describe();
 });
 await p.locator('#phoneRecord').click();assert.equal(await p.evaluate(()=>sent.filter(x=>x.action==='record').length),1);
 await p.evaluate(()=>{fixture.last_id=sent.at(-1).id;fixture.record=true;ThreeEPerformance.describe();});
 assert.equal(await p.locator('#phoneRecord').getAttribute('aria-pressed'),'true');
 assert.equal(await p.locator('#phoneRecord').evaluate(e=>getComputedStyle(e).backgroundColor),'rgb(182, 31, 53)');
 // Long press opens shared workspaces and does not send a record toggle.
 const r=await p.locator('#phoneRecord').boundingBox();await p.mouse.move(r.x+r.width/2,r.y+r.height/2);await p.mouse.down();await p.waitForTimeout(480);await p.mouse.up();
 assert.ok(await p.locator('#performanceMenu').evaluate(e=>e.open));assert.equal(await p.locator('[data-workspace]').count(),12);
 assert.equal(await p.evaluate(()=>sent.filter(x=>x.action==='record').length),1);
 await p.locator('[data-workspace="2"]').click();await p.locator('[data-action="clip-double"]').click();
 assert.equal(await p.evaluate(()=>sent.at(-1).clip_token),'clip-1');
 await p.evaluate(()=>{fixture.last_id=sent.at(-1).id;fixture.error='Selected clip changed; try again';ThreeEPerformance.describe();});
 assert.match(await p.locator('#performanceStatus').textContent(),/Selected clip changed/);
 await p.locator('#performanceClose').click();await p.locator('#midiTab').click();
 await p.evaluate(()=>{const select=document.getElementById('midiChannel');select.value='1';select.dispatchEvent(new Event('change'));ThreeEPerformance.describe();});
 await p.locator('#phonePianoMode').click();assert.equal(await p.evaluate(()=>sent.at(-1).mode),1);assert.equal(await p.evaluate(()=>sent.at(-1).channel),'2');
 await p.evaluate(()=>{fixture.last_id=sent.at(-1).id;fixture.error='';fixture.piano_modes[2]=1;ThreeEPerformance.describe();});
 const label=p.getByRole('button',{name:'Cycle piano labels and scale pads'});await label.click();await label.click();
 assert.equal(await p.locator('#piano.scale-pads .black').count(),0);assert.match((await p.locator('#piano .piano-key').allTextContents()).join(' '),/D♭/);
 assert.equal(await p.locator('#piano .piano-key').first().evaluate(e=>getComputedStyle(e).backgroundColor),'rgb(255, 255, 255)');
 for(const [width,height] of [[390,844],[320,568],[844,390],[667,375]]){
  await p.setViewportSize({width,height});
  const layout=await p.locator('#studio').evaluate(e=>{const r=e.getBoundingClientRect();return [...e.querySelectorAll('.performance-bar,.piano-toolbar,#piano')].map(n=>{const q=n.getBoundingClientRect();return q.left>=r.left&&q.right<=r.right+1&&q.top>=r.top&&q.bottom<=r.bottom-45;});});
  assert.ok(layout.every(Boolean),'Piano and transport fit '+width+'x'+height);
 }
 await p.evaluate(()=>ThreeEPerformance.state(false));assert.ok(await p.locator('#phoneRecord').isDisabled());
 assert.deepEqual(errors,[]);await browser.close();console.log('PASS: shared menus, Record tap/hold, acknowledgement, stale-clip feedback, piano modes, accidental labels, white scale pads and disconnected controls');
})().catch(e=>{console.error(e);process.exit(1)});
