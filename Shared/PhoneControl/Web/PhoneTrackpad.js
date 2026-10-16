// SPDX-License-Identifier: MIT
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const pad = $('pad'), status = $('status'), connectButton = $('connect');
  const buttons = ['apps','media','scrollMode','stepUp','stepDown','stepLeft','stepRight'].map($);
  const token = location.hash.slice(1);
  // Old ?watch=1 links still work, but normal links adapt without an extra route.
  const watchMode = new URLSearchParams(location.search).get('watch') === '1' || window.matchMedia('(max-width: 300px)').matches;
  document.documentElement.classList.toggle('watch', watchMode);
  let scrollMode = false, singleContact = false, holdTimer, releaseTimer;
  try { singleContact = localStorage.getItem('3e-single-contact') === 'true'; } catch {}
  function contactControls() {
    document.documentElement.classList.toggle('single-contact',singleContact);
    $('tongueMode').setAttribute('aria-pressed',String(singleContact));
    $('tongueMode').textContent = 'Single-contact controls: ' + (singleContact ? 'on' : 'off');
  }
  contactControls();
  function hint() { $('padHint').textContent = scrollMode ? 'Swipe to scroll' : 'Swipe to move · tap to click'; }
  hint();
  let socket, ready = false, heartbeat, dragging = false, threeDrag = false;
  let httpClient = null, httpSequence = 0, httpQueue = [], httpBusy = false;
  const clientBytes = new Uint8Array(16); crypto.getRandomValues(clientBytes);
  const controllerId = Array.from(clientBytes,b => b.toString(16).padStart(2,'0')).join('');
  let connectionAttempt = 0, connecting = false, wanted = true, reconnectTimer, connectTimeout;
  let retryDelay = 250, lastReply = 0, lastMotionSent = -Infinity;
  let mode = 0, peak = 0, started = 0, distance = 0, last = null, cancelled = false;
  let lastTap = null, tapCandidate = false, tapDrag = false, gestureOrigin = null, fourOrigin = null, fourDone = false;
  let lastTouchAt = -Infinity;
  let dx = 0, dy = 0, sx = 0, sy = 0;
  const speed = $('speed');
  try { const saved = Number(localStorage.getItem('3e-speed')); if (saved >= .5 && saved <= 20) speed.value = saved; } catch {}
  const showSpeed = () => { $('speedValue').textContent = Number(speed.value).toFixed(1) + '×'; };
  speed.addEventListener('input', () => { showSpeed(); try { localStorage.setItem('3e-speed', speed.value); } catch {} });
  showSpeed();
  function send(type, data = {}) {
    if (ready && httpClient) {
      const previous = httpQueue[httpQueue.length-1];
      // Combine only adjacent motion: clicks and button edges remain ordered.
      if ((type === 'move' || type === 'scroll') && previous?.type === type &&
          Math.abs(previous.x+data.x) <= (type === 'move' ? 8000 : 1000) && Math.abs(previous.y+data.y) <= (type === 'move' ? 8000 : 1000)) {
        previous.x += data.x; previous.y += data.y;
      } else httpQueue.push({ type, ...data });
      if (httpQueue.length > 32) { recover('Connection is slow — reconnecting…'); return false; }
      pump(); return true;
    }
    if (!ready || socket?.readyState !== WebSocket.OPEN) return false;
    if (socket.bufferedAmount > 8192) { recover('Connection is slow — reconnecting…'); return false; }
    try { socket.send(JSON.stringify({ type, ...data })); return true; }
    catch { recover('Connection interrupted — reconnecting…'); return false; }
  }
  function drag(value) {
    if (value === dragging) return;
    if (value && !send('down')) return;
    if (!value) { flush(true); send('up'); }
    dragging = value;
    if(value) $('padHint').textContent='Dragging · lift to drop'; else hint();
    pad.classList.toggle('dragging', value);
  }
  function reset(message) {
    ready = false; dragging = false; threeDrag = false;
    mode = peak = 0; last = null; cancelled = false;
    lastTap = null; tapCandidate = tapDrag = fourDone = false; gestureOrigin = fourOrigin = null;
    dx = dy = sx = sy = 0;
    clearInterval(heartbeat);
    clearTimeout(holdTimer); clearTimeout(releaseTimer); releaseTimer=null; httpQueue = [];
    buttons.forEach(b => b.disabled = true);
    pad.classList.remove('live', 'dragging');
    hint(); window.ThreeESurface?.state(false);
    status.textContent = message; connectButton.textContent = wanted ? 'Pause connection' : 'Connect';
  }
  function connected() {
    clearTimeout(connectTimeout); connecting = false; retryDelay = 250; lastReply = performance.now();
    ready = true; buttons.forEach(b => b.disabled = false); pad.classList.add('live');
    status.textContent = window.ThreeEControl?.info?.inputPermission===false ? 'Allow Accessibility on your Mac for pointer control.' : 'Connected'; connectButton.textContent = 'Pause connection';
    window.ThreeESurface?.state(true);
    heartbeat = setInterval(() => {
      if (performance.now()-lastReply > 4500) recover('Connection interrupted — reconnecting…');
      else send('ping');
    }, 1500);
  }
  async function post(client, type, extra = {}, keepalive = false) {
    const sequence = ++httpSequence;
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 2500);
    try {
      // WebKit sends Origin:null for POST under the page's no-referrer policy.
      // A same-origin referrer for this local request preserves strict origin checks.
      const response = await fetch('/control', { method:'POST', mode:'same-origin', referrerPolicy:'same-origin', cache:'no-store', keepalive,
        headers:{'Content-Type':'application/json','X-Trackpad-Token':token}, signal:abort.signal,
        body:JSON.stringify({client,type,sequence,...extra}) });
      if (!response.ok) {
        const error = new Error(response.status === 409 ? 'Another device is connected — waiting…' : 'Connection interrupted — reconnecting…');
        if (response.status === 401) { error.terminal = true; error.message = 'This link expired. Scan the latest QR code.'; }
        throw error;
      }
      if(response.json) { const result=await response.json(); if(result.host) describe(result.host); }
    } finally { clearTimeout(timeout); }
  }
  async function pump() {
    if (!ready || !httpClient || httpBusy || !httpQueue.length) return;
    const client = httpClient, attempt = connectionAttempt;
    httpBusy = true;
    try { await post(client, 'commands', { commands:httpQueue.splice(0,24) }); if (attempt === connectionAttempt) lastReply = performance.now(); }
    catch (error) { if (attempt === connectionAttempt) recover(error.message || 'Reconnecting…',error.terminal); }
    finally { if (attempt === connectionAttempt) { httpBusy = false; pump(); } }
  }
  async function connectHttp() {
    const client = httpClient = controllerId, attempt = connectionAttempt;
    httpBusy = false;
    try {
      await post(client, 'connect');
      if (attempt !== connectionAttempt) return;
      connected();
    } catch (error) { if (attempt === connectionAttempt) recover(error.message || 'Cannot reach laptop — retrying…',error.terminal); }
  }
  function connect() {
    if (!wanted || document.hidden || ready || connecting) return;
    clearTimeout(reconnectTimer); reconnectTimer = null;
    connecting = true; connectionAttempt++;
    reset('Connecting to your laptop…');
    if (!/^[0-9A-F]{48}$/.test(token)) { recover('Open your pairing link or scan a new QR code.',true); return; }
    if (watchMode || window.ThreeEHost?.http || typeof WebSocket === 'undefined') { connectHttp(); return; }
    let next;
    try { next = socket = new WebSocket('ws://' + location.host + '/ws'); }
    catch { recover('Cannot reach laptop — retrying…'); return; }
    connectTimeout = setTimeout(() => { if (socket === next) recover('Cannot reach laptop — retrying…'); },4000);
    next.onopen = () => { if (socket === next) next.send(JSON.stringify({ token,client:controllerId })); };
    next.onmessage = event => {
      if (socket !== next) return;
      try {
        const message = JSON.parse(event.data);
        if(message.host) describe(message.host);
        if (message.error === 'pairing') recover('This link expired. Scan the latest QR code.',true);
        else if (message.error === 'busy') recover('Another device is connected — waiting…');
        else if (message.ready && !ready) connected();
        else if (message.pong) lastReply = performance.now();
      } catch { recover('Connection interrupted — reconnecting…'); }
    };
    next.onclose = () => { if (socket === next) recover('Connection interrupted — reconnecting…'); };
    next.onerror = () => { if (socket === next) recover('Cannot reach laptop — retrying…'); };
  }
  connectButton.addEventListener('click', () => {
    if (wanted) { wanted = false; suspend('Paused — tap Connect to resume.'); }
    else { wanted = true; retryDelay = 250; connect(); }
  });
  $('tongueMode').addEventListener('click', () => {
    drag(false); clearTimeout(holdTimer); singleContact = !singleContact; lastTap = null;
    try { localStorage.setItem('3e-single-contact',String(singleContact)); } catch {}
    contactControls();
  });
  $('scrollMode').addEventListener('click', () => {
    drag(false); flush(); scrollMode = !scrollMode; mode = peak = 0; last = null;
    $('scrollMode').setAttribute('aria-pressed', String(scrollMode));
    $('scrollMode').setAttribute('aria-label',scrollMode ? 'Switch to pointer movement' : 'Switch to scrolling'); hint();
  });
  [['stepUp',0,-1],['stepDown',0,1],['stepLeft',-1,0],['stepRight',1,0]].forEach(([id,x,y]) => {
    $(id).addEventListener('click', () => send(scrollMode ? 'scroll' : 'move', {x:x*(scrollMode ? 120 : 24),y:y*(scrollMode ? -120 : 24)}));
  });
  function center(touches) {
    return { x: Array.from(touches).reduce((n, t) => n + t.clientX, 0) / touches.length,
             y: Array.from(touches).reduce((n, t) => n + t.clientY, 0) / touches.length };
  }
  pad.addEventListener('touchstart', e => {
    e.preventDefault(); lastTouchAt = performance.now(); if (!ready || !e.touches.length) { wake(); return; }
    clearTimeout(holdTimer);
    if(releaseTimer) { clearTimeout(releaseTimer); releaseTimer=null; }
    const point = center(e.touches), count = e.touches.length;
    if (!mode) {
      started = performance.now(); distance = 0; peak = 0; cancelled = false;
      gestureOrigin = point; fourOrigin = null; fourDone = false;
      tapCandidate = count === 1 && !dragging && !scrollMode && lastTap && started - lastTap.time < (singleContact ? 650 : 500) && Math.hypot(point.x-lastTap.x,point.y-lastTap.y) < 80;
      lastTap = null;
      if(tapCandidate) { drag(true); tapDrag=dragging; }
    }
    if (count > 1) { tapCandidate = false; if (tapDrag) { drag(false); tapDrag = false; cancelled=true; } }
    mode = count; peak = Math.max(peak, count); last = point;
    if (singleContact && count === 1 && !dragging && !scrollMode && !tapCandidate) {
      holdTimer = setTimeout(() => {
        if (ready && mode === 1 && distance < 10 && !dragging && !document.hidden) { flush(true); send('right'); cancelled = true; }
      },800);
    }
    if (count >= 4) {
      // Four fingers must never become an accidental three-finger drag.
      dx = dy = sx = sy = 0; drag(false); threeDrag = tapDrag = false;
      fourOrigin ??= point;
      if (count > 4) cancelled = true;
    }
  }, { passive: false });
  pad.addEventListener('touchmove', e => {
    e.preventDefault(); lastTouchAt = performance.now(); if (!ready || cancelled || !e.touches.length) return;
    const point = center(e.touches), count = e.touches.length;
    if (peak >= 4) {
      if (count === 4 && fourOrigin && !fourDone) {
        const x = point.x-fourOrigin.x, y = point.y-fourOrigin.y;
        if (Math.abs(y) >= 44 && Math.abs(y) > Math.abs(x)*1.3) {
          send(y < 0 ? 'taskView' : 'showDesktop'); fourDone = true;
        } else if(Math.abs(x)>=44 && Math.abs(x)>Math.abs(y)*1.3) {
          send('desktop',{direction:x<0 ? 1 : -1}); fourDone=true;
        }
      }
      last = point; mode = count; return;
    }
    if (last && mode === e.touches.length) {
      let x = point.x - last.x, y = point.y - last.y;
      distance += Math.hypot(x, y);
      if (distance >= 10) clearTimeout(holdTimer);
      if (mode === 3 && !dragging) {
        // Give a fourth finger time to land before any mouse-down is injected.
        if (performance.now()-started < 100 || distance < 4) { last = point; return; }
        drag(true); threeDrag = dragging;
      }
      if (tapCandidate) {
        if (distance < 2) { last = point; return; }
        drag(true); tapDrag = dragging; tapCandidate = false;
        x = point.x-gestureOrigin.x; y = point.y-gestureOrigin.y;
      }
      const limited = n => Math.max(-8000,Math.min(8000,n));
      if ((mode === 2 || scrollMode) && !dragging) { sx = limited(sx+x*3); sy = limited(sy-y*3); }
      else { dx = limited(dx+x*Number(speed.value)); dy = limited(dy+y*Number(speed.value)); }
    }
    last = point; mode = e.touches.length;
    flush(); // First movement goes immediately; subsequent samples are capped at 125 Hz.
  }, { passive: false });
  function flush(all = false) {
    if (!ready) { dx = dy = sx = sy = 0; return; }
    // Keep unsent motion coalesced here during a brief radio stall, instead of
    // filling the socket with old positions and forcing a full reconnect.
    // Button edges still flush immediately to preserve drag/click ordering.
    if (!all && socket?.bufferedAmount > 512) return;
    const now = performance.now();
    if (!all && now-lastMotionSent < 8) return;
    const bounded = n => Math.max(-1000, Math.min(1000, Math.trunc(n)));
    const x = Math.trunc(dx), y = Math.trunc(dy);
    dx -= x; dy -= y;
    if (x || y) { lastMotionSent = now; send('move', {x,y}); }
    for (let i=0; i<(all ? 8 : 1); i++) {
      const a = bounded(sx), b = bounded(sy);
      sx -= a; sy -= b;
      if (a || b) { lastMotionSent = now; send('scroll', { x: a, y: b }); }
      else break;
    }
  }
  pad.addEventListener('touchend', e => {
    e.preventDefault(); clearTimeout(holdTimer); lastTouchAt = performance.now(); flush(true);
    if (peak >= 4) {
      if (!e.touches.length) { mode = peak = 0; last = lastTap = fourOrigin = null; cancelled = false; }
      return;
    }
    if (threeDrag && e.touches.length < 3) { drag(false); threeDrag = false; cancelled = true; }
    if (tapDrag && !e.touches.length) {
      if(distance>=2) releaseTimer=setTimeout(()=>{drag(false);tapDrag=false;releaseTimer=null;},120);
      else { drag(false); tapDrag=false; }
      cancelled = true;
    }
    if (!e.touches.length) {
      if (ready && !cancelled && !dragging && !scrollMode && peak <= 2 && distance < (singleContact ? 14 : 9) && performance.now() - started < (singleContact ? 750 : 300)) {
        send(peak === 2 ? 'right' : 'left');
        if (peak === 1) lastTap = { ...gestureOrigin, time:performance.now() };
      }
      mode = peak = 0; last = null; cancelled = false; tapCandidate = false;
    } else { mode = e.touches.length; last = center(e.touches); }
  }, { passive: false });
  pad.addEventListener('touchcancel', e => { e.preventDefault(); releaseControls(); }, { passive: false });
  // Some watch viewers expose taps as clicks but consume continuous touch events.
  pad.addEventListener('click', () => { if (performance.now()-lastTouchAt > 500 && !scrollMode) send('left'); });
  pad.addEventListener('contextmenu', e => e.preventDefault());
  function frame() { flush(); requestAnimationFrame(frame); } requestAnimationFrame(frame);
  function suspend(message) {
    connectionAttempt++;
    clearTimeout(reconnectTimer); reconnectTimer = null; clearTimeout(connectTimeout); connecting = false;
    // Never replay queued movement after switching devices or waking the watch.
    if (httpClient) { const client = httpClient; httpClient = null; httpQueue = []; post(client, 'disconnect', {}, true).catch(() => {}); }
    if (socket) {
      const old = socket; socket = null; old.onclose = old.onerror = old.onmessage = old.onopen = null;
      try { if (ready && old.readyState === 1) old.send(JSON.stringify({type:'releaseAll'})); old.close(); } catch {}
    }
    httpBusy = false;
    reset(typeof message === 'string' ? message : 'Paused — tap Connect to resume.');
  }
  function recover(message,terminal = false) {
    if (terminal) wanted = false;
    suspend(message);
    if (wanted && !document.hidden) {
      reconnectTimer = setTimeout(connect,retryDelay);
      retryDelay = Math.min(retryDelay*2,2500);
    }
  }
  function wake() {
    if (!wanted || document.hidden) return;
    if (ready && performance.now()-lastReply > 4500) recover('Reconnecting…');
    else if (!ready) connect();
  }
  document.addEventListener('visibilitychange', () => { if (document.hidden) suspend('Sleeping — reconnects when you return.'); else wake(); });
  window.addEventListener('pagehide', () => suspend('Sleeping — reconnects when you return.'));
  ['pageshow','online','focus'].forEach(event => window.addEventListener(event,wake));
  window.addEventListener('offline', () => recover('Wi-Fi unavailable — retrying…'));
  let viewportWidth = window.innerWidth;
  window.addEventListener('resize', () => {
    // Safari's address bar can resize height mid-gesture. Only a layout-width
    // change (including rotation) requires cancelling the current contact.
    if (window.innerWidth !== viewportWidth) { viewportWidth = window.innerWidth; releaseControls(); }
  });
  function releaseControls() {
    clearTimeout(holdTimer); clearTimeout(releaseTimer); releaseTimer=null;
    dx=dy=sx=sy=0; drag(false); send('releaseAll');
    threeDrag=tapDrag=tapCandidate=false; mode=peak=0; last=lastTap=null; cancelled=true;
    window.ThreeESurface?.cancel();
  }
  function settings(show) {
    if (show) releaseControls();
    $('settingsPanel').hidden = !show; $('settings').setAttribute('aria-expanded',String(show));
  }
  $('settings').addEventListener('click', () => settings(true));
  $('closeSettings').addEventListener('click', () => settings(false));
  $('fullscreen').addEventListener('click', async () => {
    try {
      if (document.fullscreenElement && document.exitFullscreen) await document.exitFullscreen();
      else if (document.documentElement.requestFullscreen) await document.documentElement.requestFullscreen();
      else throw new Error('unsupported');
      settings(false);
    } catch { $('fullscreenHelp').textContent = 'This browser manages its own bars. On iPhone, use Share → Add to Home Screen → Open as Web App. The pad already fills the available screen.'; }
  });
  function describe(info) { if(window.ThreeEControl) window.ThreeEControl.info=info; window.ThreeESurface?.describe(info); }
  window.ThreeEControl={send,release:releaseControls,connected:()=>ready,info:null};
  connect();
})();
