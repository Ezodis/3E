// SPDX-License-Identifier: MIT
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const pad = $('pad'), status = $('status'), connectButton = $('connect');
  const buttons = [$('left'), $('right'), $('drag')];
  const token = location.hash.slice(1);
  let socket, ready = false, heartbeat, dragging = false, threeDrag = false;
  let mode = 0, peak = 0, started = 0, distance = 0, last = null, cancelled = false;
  let dx = 0, dy = 0, sx = 0, sy = 0;
  const speed = $('speed');
  try { const saved = Number(localStorage.getItem('3e-speed')); if (saved >= .5 && saved <= 3) speed.value = saved; } catch {}
  const showSpeed = () => { $('speedValue').textContent = Number(speed.value).toFixed(1) + '×'; };
  speed.addEventListener('input', () => { showSpeed(); try { localStorage.setItem('3e-speed', speed.value); } catch {} });
  showSpeed();
  function send(type, data = {}) {
    if (!ready || socket?.readyState !== WebSocket.OPEN) return false;
    if (socket.bufferedAmount > 4096) { socket.close(); reset('Connection is slow — tap Connect to retry.'); return false; }
    socket.send(JSON.stringify({ type, ...data })); return true;
  }
  function drag(value) {
    if (value === dragging) return;
    if (value && !send('down')) return;
    if (!value) send('up');
    dragging = value;
    $('drag').setAttribute('aria-pressed', String(value));
    $('drag').textContent = value ? 'Release' : 'Drag';
    pad.classList.toggle('dragging', value);
  }
  function reset(message) {
    ready = false; dragging = false; threeDrag = false;
    mode = peak = 0; last = null; cancelled = false;
    dx = dy = sx = sy = 0;
    clearInterval(heartbeat);
    buttons.forEach(b => b.disabled = true);
    pad.classList.remove('live', 'dragging');
    $('drag').setAttribute('aria-pressed', 'false'); $('drag').textContent = 'Drag';
    status.textContent = message; connectButton.textContent = 'Connect';
  }
  function connect() {
    if (socket) { socket.onclose = null; socket.close(); }
    reset('Connecting to your laptop…');
    if (!/^[0-9A-F]{48}$/.test(token)) { status.textContent = 'Scan the QR code in 3£Windows to pair this phone.'; return; }
    const next = socket = new WebSocket('ws://' + location.host + '/ws');
    next.onopen = () => next.send(JSON.stringify({ token }));
    next.onmessage = event => {
      if (socket !== next) return;
      try {
        if (JSON.parse(event.data).ready) {
          ready = true; buttons.forEach(b => b.disabled = false); pad.classList.add('live');
          status.textContent = 'Connected · keep this page open'; connectButton.textContent = 'Reconnect';
          heartbeat = setInterval(() => send('ping'), 2000);
        }
      } catch { next.close(); }
    };
    next.onclose = () => { if (socket === next) reset('Disconnected — check Wi-Fi and tap Connect, or scan a new QR code.'); };
    next.onerror = () => next.close();
  }
  connectButton.addEventListener('click', connect);
  $('left').addEventListener('click', () => send('left'));
  $('right').addEventListener('click', () => send('right'));
  $('drag').addEventListener('click', () => drag(!dragging));
  function center(touches) {
    return { x: Array.from(touches).reduce((n, t) => n + t.clientX, 0) / touches.length,
             y: Array.from(touches).reduce((n, t) => n + t.clientY, 0) / touches.length };
  }
  pad.addEventListener('touchstart', e => {
    e.preventDefault(); if (!ready) return;
    if (!mode) { started = performance.now(); distance = 0; peak = 0; cancelled = false; }
    mode = e.touches.length; peak = Math.max(peak, mode); last = center(e.touches);
    if (mode >= 3 && !cancelled) { drag(true); threeDrag = true; }
  }, { passive: false });
  pad.addEventListener('touchmove', e => {
    e.preventDefault(); if (!ready || cancelled || !e.touches.length) return;
    const point = center(e.touches);
    if (last && mode === e.touches.length) {
      const x = point.x - last.x, y = point.y - last.y;
      distance += Math.hypot(x, y);
      if (mode === 2 && !dragging) { sx -= x * 3; sy += y * 3; }
      else { dx += x * Number(speed.value); dy += y * Number(speed.value); }
    }
    last = point; mode = e.touches.length;
  }, { passive: false });
  function flush() {
    if (!ready) { dx = dy = sx = sy = 0; return; }
    const bounded = n => Math.max(-1000, Math.min(1000, Math.trunc(n)));
    const x = bounded(dx), y = bounded(dy), a = bounded(sx), b = bounded(sy);
    dx -= x; dy -= y; sx -= a; sy -= b;
    if (x || y) send('move', { x, y });
    if (a || b) send('scroll', { x: a, y: b });
  }
  pad.addEventListener('touchend', e => {
    e.preventDefault(); flush();
    if (threeDrag && e.touches.length < 3) { drag(false); threeDrag = false; cancelled = true; }
    if (!e.touches.length) {
      if (ready && !cancelled && !dragging && distance < 9 && performance.now() - started < 300)
        send(peak === 2 ? 'right' : 'left');
      mode = peak = 0; last = null; cancelled = false;
    } else { mode = e.touches.length; last = center(e.touches); }
  }, { passive: false });
  pad.addEventListener('touchcancel', e => { e.preventDefault(); drag(false); threeDrag = false; mode = peak = 0; last = null; cancelled = true; dx = dy = sx = sy = 0; }, { passive: false });
  pad.addEventListener('contextmenu', e => e.preventDefault());
  function frame() { flush(); requestAnimationFrame(frame); } requestAnimationFrame(frame);
  function suspend() { drag(false); socket?.close(); reset('Paused — tap Connect to resume.'); }
  document.addEventListener('visibilitychange', () => { if (document.hidden) suspend(); });
  window.addEventListener('pagehide', suspend);
  connect();
})();
