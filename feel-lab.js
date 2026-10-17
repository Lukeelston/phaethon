/* Phaethon feel lab: renderer, input and tuning panel for sim-core.js.
   Keyboard: W/S left lever, Up/Down right lever, E/D both, A left brake,
   Right-arrow right brake, R arm ramjet, Space reignite, H repair, X cut, Backspace respawn.
   Gamepad API: a standard pad drives the levers as tank sticks; a non-standard HID
   device (the printed levers) maps axes 0-3 to L/R throttle and L/R brake. */
(function () {
  'use strict';
  const canvas = document.getElementById('lab-canvas');
  if (!canvas || !window.PhaethonSim) return;
  const ctx = canvas.getContext('2d');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let sim = PhaethonSim.makeSim(), S = sim.S;
  const input = { thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: false };
  const keys = new Set();
  const KEYS = ['KeyW', 'KeyS', 'KeyA', 'KeyE', 'KeyD', 'KeyR', 'KeyH', 'KeyX', 'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Backspace'];
  let focused = false, source = 'Keyboard', gpArmLatch = false, toasts = [];
  const cam = { x: S.pod.x, y: S.pod.y, th: S.pod.th, span: 200 };

  canvas.tabIndex = 0;
  canvas.addEventListener('keydown', (e) => {
    if (!KEYS.includes(e.code)) return;
    e.preventDefault();
    if (!e.repeat && e.code === 'KeyR') S.armed = !S.armed;
    if (!e.repeat && e.code === 'Backspace') sim.respawn();
    keys.add(e.code);
  });
  canvas.addEventListener('keyup', (e) => keys.delete(e.code));
  canvas.addEventListener('focus', () => { focused = true; });
  canvas.addEventListener('blur', () => { focused = false; keys.clear(); });
  canvas.addEventListener('pointerdown', () => canvas.focus());

  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  function readKeyboard(dt) {
    const k = (c) => keys.has(c);
    const up = 0.9 * dt, down = 1.4 * dt;
    if (k('KeyW') || k('KeyE')) input.thrL += up;
    if (k('KeyS') || k('KeyD')) input.thrL -= down;
    if (k('ArrowUp') || k('KeyE')) input.thrR += up;
    if (k('ArrowDown') || k('KeyD')) input.thrR -= down;
    if (k('KeyX')) { input.thrL = 0; input.thrR = 0; }
    input.thrL = clamp01(input.thrL); input.thrR = clamp01(input.thrR);
    input.brkL = clamp01(input.brkL + (k('KeyA') ? 6 : -8) * dt);
    input.brkR = clamp01(input.brkR + (k('ArrowRight') ? 6 : -8) * dt);
    input.reignite = k('Space'); input.repair = k('KeyH');
  }

  function readGamepad() {
    const pads = navigator.getGamepads ? Array.from(navigator.getGamepads()).filter(Boolean) : [];
    const gp = pads[0];
    if (!gp) return false;
    const b = (i) => gp.buttons[i] || { pressed: false, value: 0 };
    let t;
    if (gp.mapping === 'standard') {
      t = { thrL: clamp01(-gp.axes[1]), thrR: clamp01(-gp.axes[3]), brkL: b(6).value, brkR: b(7).value, reignite: b(0).pressed, repair: b(2).pressed, arm: b(3).pressed, respawn: b(8).pressed };
    } else {
      const ax = (i) => clamp01(((gp.axes[i] ?? -1) + 1) / 2);
      t = { thrL: ax(0), thrR: ax(1), brkL: ax(2), brkR: ax(3), reignite: b(0).pressed, arm: b(1).pressed, repair: b(2).pressed, respawn: b(3).pressed };
    }
    const active = t.thrL > 0.04 || t.thrR > 0.04 || t.brkL > 0.04 || t.brkR > 0.04 || t.reignite || t.repair || t.arm;
    if (!active) return false;
    source = 'Gamepad: ' + gp.id.slice(0, 32);
    Object.assign(input, { thrL: t.thrL, thrR: t.thrR, brkL: t.brkL, brkR: t.brkR, reignite: t.reignite, repair: t.repair });
    if (t.arm && !gpArmLatch) S.armed = !S.armed;
    gpArmLatch = t.arm;
    if (t.respawn) sim.respawn();
    return true;
  }

  // ---------- drawing ----------
  const C = {
    sand: '#c9a46c', sandDark: '#b48c55', rock: '#8a6a43', track: '#d9bd8a', wall: '#5a4127',
    kerbA: '#e8e1d2', kerbB: '#b0442a', steel: '#9aa6b2', hot: '#ff8a2a', white: '#fff4dc',
    arc: '#7fd8ff', cable: '#2b2f36', pod: '#d6dbe0', hud: '#f4efe6', hudDim: 'rgba(244,239,230,0.55)', panel: 'rgba(24,26,31,0.72)'
  };
  const mono = '"IBM Plex Mono", ui-monospace, Menlo, Consolas, monospace';
  const T = S.T, left = [], right = [];
  for (const p of T.pts) { left.push([p.x + p.nx * p.w / 2, p.y + p.ny * p.w / 2]); right.push([p.x - p.nx * p.w / 2, p.y - p.ny * p.w / 2]); }
  const hash = (i, j) => { const h = Math.sin(i * 127.1 + j * 311.7) * 43758.5453; return h - Math.floor(h); };

  function lerpColor(a, b, t) {
    const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
    const ch = (s) => Math.round(((pa >> s) & 255) + ((((pb >> s) & 255) - ((pa >> s) & 255)) * t));
    return `rgb(${ch(16)},${ch(8)},${ch(0)})`;
  }
  function heatColor(h) { return h < 0.6 ? lerpColor(C.steel, C.hot, h / 0.6) : lerpColor(C.hot, C.white, Math.min(1, (h - 0.6) / 0.4)); }

  function poly(pts) { ctx.moveTo(pts[0][0], pts[0][1]); for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]); ctx.closePath(); }
  function box(b, len, wid, r) {
    ctx.save(); ctx.translate(b.x, b.y); ctx.rotate(b.th);
    ctx.beginPath(); ctx.roundRect(-len / 2, -wid / 2, len, wid, r); ctx.restore();
  }

  function drawWorld(W, H, dpr) {
    const v = Math.hypot(S.pod.vx, S.pod.vy);
    const span = 90 + v * 0.6;
    cam.span += (span - cam.span) * 0.05;
    const tgtTh = S.pairTh ?? S.pod.th;
    cam.th += Math.atan2(Math.sin(tgtTh - cam.th), Math.cos(tgtTh - cam.th)) * 0.12;
    const look = cam.span * 0.28;
    cam.x = S.pod.x + Math.cos(cam.th) * look; cam.y = S.pod.y + Math.sin(cam.th) * look;
    const s = H / cam.span * dpr, fx = Math.cos(cam.th), fy = Math.sin(cam.th), rx = fy, ry = -fx;
    ctx.setTransform(s * rx, -s * fx, s * ry, -s * fy, W * dpr / 2 - s * (rx * cam.x + ry * cam.y), H * dpr * 0.56 + s * (fx * cam.x + fy * cam.y));

    const R = cam.span * Math.max(1, W / H) * 0.75, g = 36;
    ctx.fillStyle = C.sand; ctx.fillRect(cam.x - R, cam.y - R, 2 * R, 2 * R);
    ctx.fillStyle = C.rock;
    for (let i = Math.floor((cam.x - R) / g); i <= Math.ceil((cam.x + R) / g); i++) {
      for (let j = Math.floor((cam.y - R) / g); j <= Math.ceil((cam.y + R) / g); j++) {
        const h = hash(i, j);
        if (h < 0.55) continue;
        ctx.beginPath(); ctx.arc(i * g + hash(j, i) * g, j * g + h * g, 0.6 + (h - 0.55) * 4, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.beginPath(); poly(left); poly(right); ctx.fillStyle = C.track; ctx.fill('evenodd');
    ctx.lineWidth = 2.2; ctx.strokeStyle = C.wall;
    ctx.beginPath(); poly(left); ctx.stroke(); ctx.beginPath(); poly(right); ctx.stroke();
    for (const edge of [left, right]) {
      for (let i = 0; i < edge.length; i += 2) {
        const a = edge[i], b = edge[(i + 1) % edge.length];
        ctx.strokeStyle = (i / 2) % 2 ? C.kerbA : C.kerbB; ctx.lineWidth = 1.4;
        ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
      }
    }
    for (let c = 0; c < T.checkpoints; c++) {
      const i = Math.round(c * T.N / T.checkpoints), a = left[i], b = right[i];
      ctx.strokeStyle = c === 0 ? C.white : 'rgba(90,65,39,0.35)'; ctx.lineWidth = c === 0 ? 3 : 1;
      ctx.setLineDash(c === 0 ? [3, 3] : []);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
    }
    ctx.setLineDash([]);
    drawCraft();
  }

  function drawCraft() {
    const P = sim.P, L = S.eL, Rr = S.eR;
    S.cables.forEach((c) => {
      if (c.ex === undefined) return;
      ctx.strokeStyle = c.slack ? 'rgba(43,47,54,0.45)' : C.cable; ctx.lineWidth = c.slack ? 0.25 : 0.4 + Math.min(0.6, c.f / 60000);
      ctx.setLineDash(c.slack ? [1, 1] : []);
      ctx.beginPath(); ctx.moveTo(c.ex, c.ey); ctx.lineTo(c.px, c.py); ctx.stroke();
    });
    ctx.setLineDash([]);
    if (!S.binderBroken) {
      const o = P.engineLen / 2 - 1;
      const ax = L.x + Math.cos(L.th) * o, ay = L.y + Math.sin(L.th) * o, bx = Rr.x + Math.cos(Rr.th) * o, by = Rr.y + Math.sin(Rr.th) * o;
      ctx.strokeStyle = C.arc; ctx.lineWidth = 0.35; ctx.shadowColor = C.arc; ctx.shadowBlur = 8;
      ctx.beginPath(); ctx.moveTo(ax, ay);
      for (let k = 1; k < 6; k++) {
        const t = k / 6, j = reduced ? 0 : (Math.random() - 0.5) * 1.2;
        ctx.lineTo(ax + (bx - ax) * t - Math.sin(L.th) * j, ay + (by - ay) * t + Math.cos(L.th) * j);
      }
      ctx.lineTo(bx, by); ctx.stroke(); ctx.shadowBlur = 0;
    }
    for (const e of [L, Rr]) {
      const c = Math.cos(e.th), s = Math.sin(e.th), back = P.engineLen / 2;
      if (!e.flameout && e.thrust > 0.02) {
        const len = 2 + e.thrust * (S.mode === 'normal' ? 6 : 11) * (reduced ? 1 : 0.85 + Math.random() * 0.3);
        ctx.fillStyle = S.mode === 'ramjet' ? '#e9d7ff' : S.mode === 'burner' ? '#bfe9ff' : C.hot;
        ctx.beginPath(); ctx.moveTo(e.x - c * back - s * 0.6, e.y - s * back + c * 0.6);
        ctx.lineTo(e.x - c * (back + len), e.y - s * (back + len)); ctx.lineTo(e.x - c * back + s * 0.6, e.y - s * back - c * 0.6); ctx.fill();
      }
      box(e, P.engineLen, 1.7, 0.8); ctx.fillStyle = e.flameout ? '#3a3a3a' : heatColor(e.heat); ctx.fill();
      ctx.lineWidth = 0.2; ctx.strokeStyle = '#1d2026'; ctx.stroke();
    }
    box(S.pod, P.podLen, P.podWidth, 1); ctx.fillStyle = C.pod; ctx.fill(); ctx.strokeStyle = '#1d2026'; ctx.lineWidth = 0.2; ctx.stroke();
    ctx.save(); ctx.translate(S.pod.x, S.pod.y); ctx.rotate(S.pod.th);
    ctx.fillStyle = '#2a4a63'; ctx.beginPath(); ctx.roundRect(0.2, -0.7, 1.3, 1.4, 0.4); ctx.fill(); ctx.restore();
  }

  function bar(x, y, w, h, frac, color, label, mark) {
    ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = color; ctx.fillRect(x, y + h * (1 - frac), w, h * frac);
    if (mark !== undefined) { ctx.fillStyle = C.white; ctx.fillRect(x - 3, y + h * (1 - mark), w + 6, 1.5); }
    ctx.fillStyle = C.hudDim; ctx.font = `600 10px ${mono}`; ctx.textAlign = 'center'; ctx.fillText(label, x + w / 2, y + h + 13);
  }

  function drawHud(W, H) {
    const v = Math.hypot(S.pod.vx, S.pod.vy) * 3.6, now = S.time;
    ctx.fillStyle = C.panel; ctx.beginPath(); ctx.roundRect(12, H - 156, 236, 144, 8); ctx.fill();
    const y0 = H - 140, bh = 96, gate = sim.P.gate;
    bar(26, y0, 16, bh, input.thrL, '#d8dee6', 'L', gate);
    bar(48, y0, 6, bh, input.brkL, '#ff6b4a', 'B');
    bar(64, y0, 10, bh, Math.min(1, S.eL.heat), heatColor(S.eL.heat), '');
    bar(78, y0, 10, bh, Math.min(1, S.eR.heat), heatColor(S.eR.heat), '');
    bar(94, y0, 6, bh, input.brkR, '#ff6b4a', 'B');
    bar(106, y0, 16, bh, input.thrR, '#d8dee6', 'R', gate);
    bar(138, y0, 10, bh, S.battery, C.arc, 'BAT');
    ctx.fillStyle = C.hudDim; ctx.font = `600 10px ${mono}`; ctx.textAlign = 'center';
    ctx.fillText('HEAT', 76, y0 + bh + 13);
    ctx.textAlign = 'left'; ctx.fillStyle = C.hud; ctx.font = `600 26px ${mono}`;
    ctx.fillText(v.toFixed(0), 180, y0 + 30);
    ctx.font = `500 10px ${mono}`; ctx.fillStyle = C.hudDim; ctx.fillText('KM/H', 182, y0 + 44);
    ctx.fillText('HEALTH', 182, y0 + 66);
    ctx.fillStyle = C.hud; ctx.fillText(`${Math.round(S.eL.health * 100)} ${Math.round(S.eR.health * 100)}`, 182, y0 + 80);
    const mode = S.mode === 'ramjet' ? 'RAMJET' : S.mode === 'burner' ? 'AFTERBURNER' : S.armed ? 'RAMJET ARMED' : '';
    if (mode) { ctx.font = `700 11px ${mono}`; ctx.fillStyle = S.mode === 'normal' ? '#e9d7ff' : C.white; ctx.fillText(mode, 26, H - 162); }

    ctx.fillStyle = C.panel; ctx.beginPath(); ctx.roundRect(12, 12, 200, 62, 8); ctx.fill();
    ctx.fillStyle = C.hud; ctx.font = `600 13px ${mono}`;
    const cur = S.lapStart === null ? 0 : now - S.lapStart;
    ctx.fillText(`LAP ${S.lap + 1}   ${cur.toFixed(2)}s`, 24, 34);
    ctx.fillStyle = C.hudDim; ctx.font = `500 11px ${mono}`;
    ctx.fillText(`LAST ${S.lastLap ? S.lastLap.toFixed(2) : '--'}  BEST ${S.bestLap ? S.bestLap.toFixed(2) : '--'}`, 24, 52);
    ctx.fillText(source, 24, 66);

    const mw = 120, mh = 92, mx = W - mw - 14, my = 14;
    ctx.fillStyle = C.panel; ctx.beginPath(); ctx.roundRect(mx - 6, my - 6, mw + 12, mh + 12, 8); ctx.fill();
    const bx = { x0: -900, x1: 2450, y0: -150, y1: 1850 }, sc = Math.min(mw / (bx.x1 - bx.x0), mh / (bx.y1 - bx.y0));
    const mpx = (x) => mx + (x - bx.x0) * sc, mpy = (y) => my + mh - (y - bx.y0) * sc;
    ctx.strokeStyle = C.hudDim; ctx.lineWidth = 2; ctx.beginPath();
    T.pts.forEach((p, i) => (i ? ctx.lineTo(mpx(p.x), mpy(p.y)) : ctx.moveTo(mpx(p.x), mpy(p.y)))); ctx.closePath(); ctx.stroke();
    ctx.fillStyle = C.hot; ctx.beginPath(); ctx.arc(mpx(S.pod.x), mpy(S.pod.y), 3.5, 0, Math.PI * 2); ctx.fill();

    const warn = [];
    for (const [e, n] of [[S.eL, 'L'], [S.eR, 'R']]) if (e.flameout) warn.push(e.heat < 0.6 ? `FLAMEOUT ${n}: hold SPACE to reignite` : `FLAMEOUT ${n}: cooling ${Math.round(e.heat * 100)}%`);
    if (S.crashT > 0) warn.push(S.binderBroken ? 'BINDER BEAM SNAPPED' : 'POD WRECKED');
    toasts = toasts.filter((t) => now - t.t < 2.2);
    ctx.textAlign = 'center';
    warn.concat(toasts.map((t) => t.msg)).forEach((m, i) => {
      ctx.font = `700 13px ${mono}`; const w = ctx.measureText(m).width + 24;
      ctx.fillStyle = C.panel; ctx.beginPath(); ctx.roundRect(W / 2 - w / 2, 16 + i * 30, w, 24, 6); ctx.fill();
      ctx.fillStyle = i < warn.length ? '#ffb38a' : C.hud; ctx.fillText(m, W / 2, 33 + i * 30);
    });
    if (!focused) {
      ctx.fillStyle = 'rgba(20,22,26,0.62)'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = C.hud; ctx.font = `700 18px ${mono}`; ctx.fillText('Click to take the controls', W / 2, H / 2 - 30);
      ctx.font = `500 12px ${mono}`; ctx.fillStyle = C.hudDim;
      ['W/S left lever   ↑/↓ right lever   E/D both', 'A left brake   → right brake   push both past the line to boost', 'R arm ramjet   SPACE reignite   H repair   ⌫ respawn'].forEach((l, i) => ctx.fillText(l, W / 2, H / 2 + i * 20));
    }
    ctx.textAlign = 'left';
  }

  function handleEvents() {
    while (S.events.length) {
      const e = S.events.shift();
      const msg = e.type === 'lap' ? `LAP ${e.t.toFixed(2)}s` : e.type === 'hit' ? `${e.who === 'pod' ? 'POD' : e.who + ' ENGINE'} HIT -${Math.round(e.dmg * 100)}%` : e.type === 'flameout' ? `${e.who} ENGINE OVERHEAT` : null;
      if (msg) toasts.push({ msg, t: S.time });
    }
  }

  let last = performance.now(), acc = 0;
  const DT = 1 / 480;
  function frame(nowMs) {
    const dt = Math.min(0.05, (nowMs - last) / 1000); last = nowMs;
    if (!readGamepad()) { source = 'Keyboard'; if (focused) readKeyboard(dt); }
    acc += dt;
    while (acc >= DT) { sim.step(input, DT); acc -= DT; }
    handleEvents();
    const dpr = window.devicePixelRatio || 1, W = canvas.clientWidth, H = canvas.clientHeight;
    if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) { canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr); }
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, canvas.width, canvas.height);
    drawWorld(W, H, dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawHud(W, H);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  // ---------- tuning panel ----------
  const TUNE = [
    ['thrustMax', 'Thrust per engine', 50000, 600000, 10000, 'kN', 1e-3],
    ['gripCapG', 'Grip limit (turn rate = g / speed)', 2, 40, 0.5, 'g', 1],
    ['finK', 'Fins (nose locks to path at speed)', 0, 30, 0.5, '', 1],
    ['engineGrip', 'Engine grip', 5, 60, 1, '/s', 1],
    ['yawDamp', 'Yaw damping', 0, 600000, 10000, 'kN·m·s', 1e-3],
    ['finOffset', 'Weathervane arm', 0, 1, 0.05, 'm', 1],
    ['towK', 'Tow bar stiffness', 0, 3000000, 50000, 'kN/m', 1e-3],
    ['cableLen', 'Cable length', 8, 30, 0.5, 'm', 1],
    ['cableK', 'Cable stiffness', 100000, 2000000, 50000, 'kN/m', 1e-3],
    ['brakeConst', 'Air-brake bite', 0, 150000, 5000, 'kN', 1e-3],
    ['brakeCd', 'Air-brake drag (high speed)', 0, 0.2, 0.005, '', 1]
  ];
  const panel = document.getElementById('lab-tune'), out = document.getElementById('lab-json');
  function writeJson() { if (out) out.value = JSON.stringify(Object.fromEntries(TUNE.map(([k]) => [k, sim.P[k]])), null, 1); }
  if (panel) {
    for (const [key, label, min, max, stepv, unit, k] of TUNE) {
      const row = document.createElement('label'); row.className = 'tune-row';
      const id = 'tune-' + key;
      row.htmlFor = id;
      row.innerHTML = `<span class="tune-name">${label}</span><input type="range" id="${id}" min="${min}" max="${max}" step="${stepv}" value="${sim.P[key]}"><output class="tune-val"></output>`;
      const range = row.querySelector('input'), val = row.querySelector('output');
      const show = () => { val.textContent = `${+(sim.P[key] * k).toFixed(2)} ${unit}`.trim(); };
      range.addEventListener('input', () => { sim.P[key] = +range.value; show(); writeJson(); });
      show(); panel.appendChild(row);
    }
    writeJson();
  }
  const btn = (id, fn) => { const b = document.getElementById(id); if (b) b.addEventListener('click', fn); };
  btn('lab-respawn', () => { sim.respawn(); canvas.focus(); });
  btn('lab-defaults', () => {
    for (const [key] of TUNE) { sim.P[key] = PhaethonSim.DEFAULTS[key]; const r = document.getElementById('tune-' + key); if (r) { r.value = sim.P[key]; r.dispatchEvent(new Event('input')); } }
  });
  btn('lab-copy', (ev) => {
    const b = ev.currentTarget;
    navigator.clipboard.writeText(out.value).then(() => { b.textContent = 'Copied'; }, () => { out.select(); b.textContent = 'Selected, press Ctrl+C'; });
    setTimeout(() => { b.textContent = 'Copy tuning JSON'; }, 1800);
  });
  window.PhaethonLab = { get S() { return S; }, sim, input };
})();
