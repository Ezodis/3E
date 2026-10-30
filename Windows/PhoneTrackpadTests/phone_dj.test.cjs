// Real browser + shared receiver, with a simulated DJ bridge. Never sends
// musical controls to a user's DAW or interacts with an installed app.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright-core');
(async()=>{
 const engine=process.env.PLAYWRIGHT_ENGINE==='webkit'?webkit:chromium;
 const options={headless:true};if(process.env.PLAYWRIGHT_BROWSER_PATH)options.executablePath=process.env.PLAYWRIGHT_BROWSER_PATH;
 const browser=await engine.launch(options);
 const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});const p=await context.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));
 await p.goto(fs.readFileSync(process.argv[2],'utf8').trim());await p.waitForFunction(()=>window.ThreeEControl?.connected());
 await p.evaluate(()=>{window.ThreeESurface.openStudio();window.djSent=[];const send=window.ThreeEControl.send;window.ThreeEControl.send=(type,c)=>{if(type==='dj')window.djSent.push(c);else send(type,c);};});
 await p.waitForSelector('.dj-card');
 const fixture={platform:'macos',midi:{selected:0,status:'Fake MIDI',ports:[{id:0,name:'Fake MIDI'}]},connection:{kind:'usb',name:'iPhone USB',routes:[]},controls:{dj:{available:true,paired:true,page:1,touchPage:0,target:'rekordbox',crossfader:64,decks:[{title:'Breaks 3',duration:218,elapsed:73,bpm:121,tempo:0,tempoRange:'±6',search:true,values:[0,100,64,64,64,64,0,0,0,0,0,0,0,0]},{title:'House 4',duration:246,elapsed:25,bpm:121,tempo:-13.5,tempoRange:'±16',search:false,values:[0,100,64,64,64,64,0,0,0,0,0,0,0,0]}]}}};
 // Prevent the preview's ordinary heartbeat from replacing this explicit native fixture.
 await p.evaluate(info=>{window.djFixture=info;window.djDescribe=window.ThreeEDJ.describe;window.ThreeEDJ.describe=()=>window.djDescribe(window.djFixture);window.ThreeESurface.describe(info);},fixture);
 assert.equal(await p.locator('#decksView').getAttribute('data-mode'),'pads');assert.equal(await p.locator('.dj-card').count(),2);assert.equal(await p.locator('.dj-cue').count(),8);assert.equal(await p.locator('.dj-action').count(),8);
 assert.match(await p.locator('#djLink').textContent(),/LINKED.*MIX/);assert.match(await p.locator('#djConnection').textContent(),/USB/);
 assert.equal(await p.locator('.dj-vitals').first().textContent(),'121.000.0% ±6');assert.equal(await p.locator('.dj-card').first().getAttribute('data-search'),'true');
 await p.locator('#djMode').click();assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='page'&&c.page===0)));
 await p.evaluate(()=>{djFixture.controls.dj.page=0;djFixture.controls.dj.touchPage=1;window.ThreeESurface.describe(djFixture);});
 assert.equal(await p.locator('#decksView').getAttribute('data-mode'),'mix');
 await p.screenshot({path:path.join(process.argv[3],'phone-dj-mix.png'),fullPage:true});
 await p.evaluate(()=>{djFixture.controls.dj.page=1;djFixture.controls.dj.touchPage=0;window.ThreeESurface.describe(djFixture);});
 await p.screenshot({path:path.join(process.argv[3],'phone-dj-pads.png'),fullPage:true});
 // Paired pointer protocol: dragging a wheel then resting does not send an early end.
 const wheel=p.locator('.dj-platter').first(),r=await wheel.boundingBox();await p.mouse.move(r.x+r.width*.45,r.y+r.height*.5);await p.mouse.down();await p.mouse.move(r.x+r.width*.45+16,r.y+r.height*.5,{steps:5});await p.waitForTimeout(450);
 assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='move'&&c.control===0)));assert.equal(await p.evaluate(()=>djSent.filter(c=>c.op==='end'&&c.control===0).length),0);await p.mouse.up();assert.equal(await p.evaluate(()=>djSent.filter(c=>c.op==='end'&&c.control===0).length),1);
 // Client cancellation and disconnect release remote ownership.
 await p.evaluate(()=>window.ThreeESurface.state(false));assert.ok(await p.evaluate(()=>djSent.some(c=>c.op==='cancel')));
 assert.deepEqual(errors,[]);await browser.close();console.log('PASS: two-deck native metadata, mode routing, eight accessible pads, USB status, precise wheel lifecycle and disconnect cleanup');
})().catch(e=>{console.error(e);process.exit(1)});
