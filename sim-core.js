/* Phaethon sim core: twin-engine tethered podracer, top-down slice.
   Three bodies (left engine, right engine, cockpit pod), an energy binder
   between the engines, two cables back to the pod. Engine-agnostic on purpose:
   makeSim(params) -> { S, step(input, dt), respawn() } so the same model ports
   to GDScript. Units: metres, seconds, newtons. x right, y up.
   Heading th: forward = (cos th, sin th), left = (-sin th, cos th). */
(function () {
  'use strict';

  const DEFAULTS = {
    engineMass: 1200, engineLen: 8, engineGap: 6,
    podMass: 500, podLen: 4, podWidth: 2.4,
    // v3 (2026-10-17): ~4,450 mph on full lever, ~5,400 mph on the afterburner, 0-4,000 mph
    // in ~12 s. Lateral grip caps near 15 g, so the path turns ~4 deg/s flat out and 35+
    // deg/s at 350 mph; speed^2 fins pin the nose to the flight path at speed. The pod
    // rides a tow bar (<4 deg sway). tools/handling_test.js measures all of it.
    thrustMax: 350000, burnerMult: 1.45, ramjetMult: 1.9, gate: 0.88,
    engineCd: 0.07, podCd: 0.035, brakeCd: 0.04, brakeLin: 0, brakeConst: 60000,
    engineGrip: 30, podGrip: 10, gripCapG: 15, podCapG: 8, finOffset: 0.2, finK: 8,
    yawDamp: 150000, podYawDamp: 50000, podAlignK: 1e6, towK: 1e6, towC: 40000,
    cableLen: 16, cableK: 600000, cableC: 30000, cableCouple: 0.2, podAnchorW: 0.15,
    binderK: 3e6, binderC: 70000, alignK: 2e7, alignC: 6e5, binderBreak: 3.0,
    wallK: 6e6, wallC: 1.5e5, wallMu: 0.35,
    heatThrottle: 0.15, heatBurner: 0.12, heatRamjet: 0.35, coolBase: 0.05, coolSpeed: 0.10,
    batteryDrain: 0.08, batteryCharge: 0.05, repairRate: 0.12, damagePerMs: 0.012,
    rideH: 1.5, hoverOmega: 9, hoverZeta: 0.9,
    track: 'circuit', startX: 0, startY: 0,
    seed: 1337
  };

  // The range: 100 miles of open desert. Speed runway along y = 0, a jump lane at
  // y = +400 with a kicker every 4 km from 8 km, and a twisty lane at y = -400 that only
  // the view draws. No walls, no laps. Launch speed is slope x speed, so the kickers are
  // long and shallow, sized for 2,000-5,000 mph; at a few hundred mph they're bumps.
  const RANGE_LEN = 160934.4, JUMP_Y = 400, JUMP_W = 40, RAMP_X0 = 8000, RAMP_EVERY = 4000;
  // Sprint: stop dead inside a 50 m box at mile 100. Past BOX_X + OVERRUN is a DNF.
  const BOX_X = RANGE_LEN, BOX_HALF = 25, OVERRUN = 15000, STOPPED = 0.5;
  const RAMP_H = [3, 6, 10, 15], RAMP_SLOPE = [0.007, 0.011, 0.0157, 0.022];
  function buildRange() {
    const ramps = [];
    for (let i = 0; RAMP_X0 + RAMP_EVERY * i < RANGE_LEN - 500; i++) {
      const h = RAMP_H[i % 4];
      ramps.push({ x0: RAMP_X0 + RAMP_EVERY * i, len: h / RAMP_SLOPE[i % 4], h });
    }
    return { kind: 'range', length: RANGE_LEN, ramps, jumpY: JUMP_Y, jumpW: JUMP_W, N: 0, checkpoints: 0, pts: [] };
  }

  function ground(T, x, y) {
    if (T.kind !== 'range' || Math.abs(y - T.jumpY) > T.jumpW / 2 || x < RAMP_X0) return 0;
    const r = T.ramps[Math.floor((x - RAMP_X0) / RAMP_EVERY)];
    if (!r) return 0;
    const u = x - r.x0;
    if (u <= r.len) return r.h * u / r.len;
    if (u <= r.len + r.h) return r.h - (u - r.len);
    return 0;
  }

  // xorshift32: the only randomness in the model, seeded so replays are exact.
  function xorshift32(seed) {
    let x = (seed >>> 0) || 1;
    return () => { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; return (x >>> 0) / 4294967296; };
  }

  const G = 9.81;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

  function buildTrack() {
    const ctrl = [[0, 0], [900, -100], [1700, 150], [2300, 700], [2400, 1300], [2000, 1700],
      [1400, 1600], [1100, 1150], [700, 1300], [300, 1800], [-400, 1700], [-900, 1100],
      [-800, 400], [-400, 80]];
    const per = 48, n = ctrl.length, pts = [];
    for (let i = 0; i < n; i++) {
      const p0 = ctrl[(i - 1 + n) % n], p1 = ctrl[i], p2 = ctrl[(i + 1) % n], p3 = ctrl[(i + 2) % n];
      for (let k = 0; k < per; k++) {
        const t = k / per, t2 = t * t, t3 = t2 * t;
        const cr = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
        pts.push({ x: cr(p0[0], p1[0], p2[0], p3[0]), y: cr(p0[1], p1[1], p2[1], p3[1]) });
      }
    }
    const N = pts.length;
    let s = 0;
    for (let i = 0; i < N; i++) {
      const a = pts[i], b = pts[(i + 1) % N];
      const dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy);
      a.tx = dx / L; a.ty = dy / L; a.nx = -a.ty; a.ny = a.tx; a.len = L; a.s = s; s += L;
      a.w = 82 + 24 * Math.sin((i / N) * Math.PI * 6 + 0.6);
    }
    return { kind: 'circuit', pts, N, length: s, checkpoints: 8 };
  }

  // Nearest centreline point, searched in a window around a hint index.
  function nearest(T, x, y, hint, win) {
    let best = null, bd = Infinity;
    for (let k = -win; k <= win; k++) {
      const i = (((hint + k) % T.N) + T.N) % T.N, a = T.pts[i];
      const t = clamp(((x - a.x) * a.tx + (y - a.y) * a.ty) / a.len, 0, 1);
      const px = a.x + a.tx * a.len * t, py = a.y + a.ty * a.len * t;
      const d = (x - px) ** 2 + (y - py) ** 2;
      if (d < bd) { bd = d; best = { i, lat: (x - a.x) * a.nx + (y - a.y) * a.ny, w: a.w, nx: a.nx, ny: a.ny }; }
    }
    return best;
  }

  function body(m, I) { return { m, I, x: 0, y: 0, vx: 0, vy: 0, th: 0, w: 0, fx: 0, fy: 0, t: 0, hint: 0, contact: [false, false], z: 0, vz: 0, grip: 1 }; }
  function applyAt(b, fx, fy, px, py) {
    b.fx += fx; b.fy += fy; b.t += (px - b.x) * fy - (py - b.y) * fx;
  }
  function pointVel(b, px, py) { return [b.vx - b.w * (py - b.y), b.vy + b.w * (px - b.x)]; }

  function makeSim(overrides) {
    const P = Object.assign({}, DEFAULTS, overrides || {});
    const T = P.track === 'range' ? buildRange() : buildTrack();
    const eI = P.engineMass * P.engineLen ** 2 / 12;
    const pI = P.podMass * (P.podLen ** 2 + P.podWidth ** 2) / 12;
    const S = {
      P, T, eL: body(P.engineMass, eI), eR: body(P.engineMass, eI), pod: body(P.podMass, pI),
      battery: 1, armed: false, mode: 'normal', binderBroken: false, crashT: 0, time: 0,
      lap: 0, lapStart: null, lastLap: null, bestLap: null, visited: new Set(), checkpoint: 0,
      progressI: 0, cables: [{ f: 0 }, { f: 0 }], events: [], rand: xorshift32(P.seed),
      runStart: null, lastRun: null, bestRun: null, finished: false, runActive: false, result: null
    };
    S.bodies = [S.eL, S.eR, S.pod];

    function respawn(ci) {
      // engines placed so each cable is exactly at length: a stretched spawn makes the stiff
      // cables yank the pod forward on the first step
      const lat = P.engineGap / 2 - P.podAnchorW * P.podWidth / 2;
      const ahead = Math.sqrt(P.cableLen * P.cableLen - lat * lat) + P.podLen / 2 + P.engineLen / 2;
      // Circuit: back at a checkpoint. Range: 30 m behind where the pod is, facing +x.
      let a, idx = 0;
      if (T.kind === 'range') {
        a = { x: Math.max(0, S.pod.x - 30), y: S.pod.y, tx: 1, ty: 0, nx: 0, ny: 1 };
      } else {
        idx = Math.round((ci ?? S.checkpoint) * T.N / T.checkpoints) % T.N; a = T.pts[idx];
      }
      const th = Math.atan2(a.ty, a.tx);
      for (const [b, side] of [[S.eL, 1], [S.eR, -1], [S.pod, 0]]) {
        const fwd = side === 0 ? 0 : ahead;
        b.x = a.x + a.tx * fwd + a.nx * side * P.engineGap / 2;
        b.y = a.y + a.ty * fwd + a.ny * side * P.engineGap / 2;
        b.vx = b.vy = b.w = 0; b.th = th; b.hint = idx; b.contact = [false, false];
        b.z = ground(T, b.x, b.y) + P.rideH; b.vz = 0; b.grip = 1;
      }
      for (const e of [S.eL, S.eR]) { e.heat = Math.min(e.heat ?? 0.3, 0.5); e.flameout = false; e.health = e.health ?? 1; e.sputter = 1; e.sputterT = 0; }
      S.pod.health = S.pod.health > 0 ? S.pod.health : 1;
      S.binderBroken = false; S.crashT = 0; S.progressI = idx;
    }

    function collideWalls(b, circles, dt) {
      const near = nearest(T, b.x, b.y, b.hint, 40);
      b.hint = near.i;
      circles.forEach(([cx, cy, r], ci) => {
        const n = nearest(T, cx, cy, b.hint, 12);
        const pen = Math.abs(n.lat) + r - n.w / 2;
        if (pen <= 0) { b.contact[ci] = false; return; }
        const sgn = n.lat > 0 ? -1 : 1, nx = n.nx * sgn, ny = n.ny * sgn;
        const [vx, vy] = pointVel(b, cx, cy), vn = vx * nx + vy * ny;
        if (!b.contact[ci]) {
          const dmg = P.damagePerMs * Math.max(0, -vn - 6);
          if (b === S.pod) S.pod.health -= dmg; else b.health = Math.max(0, b.health - dmg);
          if (dmg > 0.05) S.events.push({ type: 'hit', who: b === S.pod ? 'pod' : b === S.eL ? 'L' : 'R', dmg });
          b.contact[ci] = true;
        }
        const fn = P.wallK * pen - (vn < 0 ? P.wallC * vn : 0);
        const tx = -ny, ty = nx, vt = vx * tx + vy * ty;
        const ft = -Math.sign(vt) * Math.min(P.wallMu * fn, Math.abs(vt) * b.m / dt);
        applyAt(b, fn * nx + ft * tx, fn * ny + ft * ty, cx, cy);
      });
    }

    // Repulsor hover: spring-damper toward ride height over the ground, push-only, plus
    // gravity. Exactly balanced at ride height on flat ground, so flat tracks are unchanged.
    // Grip fades as a body lifts clear (0.5 to 2 m above ride height) and returns on landing.
    function hover(b, dt) {
      const h = ground(T, b.x, b.y), dhdt = (ground(T, b.x + b.vx * dt, b.y + b.vy * dt) - h) / dt;
      const w = P.hoverOmega;
      const up = Math.max(0, G + w * w * (P.rideH - (b.z - h)) - 2 * P.hoverZeta * w * (b.vz - dhdt));
      b.vz += (up - G) * dt; b.z += b.vz * dt;
      if (b.z - h < 0.3) {
        b.z = h + 0.3;
        if (b.vz < dhdt) {
          if (dhdt - b.vz > 12) S.events.push({ type: 'land', v: dhdt - b.vz });
          b.vz = dhdt;
        }
      }
      b.grip = clamp(1 - (b.z - h - P.rideH - 0.5) / 1.5, 0, 1);
    }

    function engineCircles(e) {
      const c = Math.cos(e.th), s = Math.sin(e.th), o = P.engineLen / 2 - 1.2;
      return [[e.x + c * o, e.y + s * o, 1.2], [e.x - c * o, e.y - s * o, 1.2]];
    }

    function bodyPush(a, ca, b, cb) {
      for (const [ax, ay, ar] of ca) for (const [bx, by, br] of cb) {
        const dx = bx - ax, dy = by - ay, d = Math.hypot(dx, dy), pen = ar + br - d;
        if (pen <= 0 || d < 1e-6) continue;
        const nx = dx / d, ny = dy / d, f = 1.0e6 * pen;
        applyAt(b, f * nx, f * ny, bx, by); applyAt(a, -f * nx, -f * ny, ax, ay);
      }
    }

    function step(inp, dt) {
      const L = S.eL, R = S.eR, Pd = S.pod;
      if (S.crashT > 0) {
        S.crashT -= dt;
        if (S.crashT <= 0) {
          if (S.finished) { S.pod.x = 30; S.pod.y = 0; S.finished = false; S.result = null; }   // back to the start line
          respawn();
        }
        return;
      }
      for (const b of S.bodies) { b.fx = 0; b.fy = 0; b.t = 0; hover(b, dt); }
      S.time += dt;
      const inGate = inp.thrL >= P.gate && inp.thrR >= P.gate && !inp.repair;
      const ramjet = S.armed && inGate;
      const burner = !ramjet && inGate && S.battery > 0;
      S.mode = ramjet ? 'ramjet' : burner ? 'burner' : 'normal';
      if (burner) S.battery = Math.max(0, S.battery - P.batteryDrain * dt);
      else if (!inGate) S.battery = Math.min(1, S.battery + P.batteryCharge * dt);
      const speed = Math.hypot(Pd.vx, Pd.vy);

      for (const [e, thr, brk] of [[L, inp.thrL, inp.brkL], [R, inp.thrR, inp.brkR]]) {
        const c = Math.cos(e.th), s = Math.sin(e.th);
        const gain = e.flameout ? 0 : Math.max(0, thr - 0.6) * P.heatThrottle + (burner ? P.heatBurner : 0) + (ramjet ? P.heatRamjet : 0);
        const cool = P.coolBase + P.coolSpeed * Math.min(1.5, speed / 200) + (e.flameout ? 0.15 : 0);
        e.heat = clamp(e.heat + (gain - cool) * dt, 0, 1.25);
        if (e.heat >= 1 && !e.flameout) { e.flameout = true; S.events.push({ type: 'flameout', who: e === L ? 'L' : 'R' }); }
        if (e.flameout && inp.reignite && e.heat < 0.6) e.flameout = false;
        if (inp.repair) e.health = Math.min(1, e.health + P.repairRate * dt);
        e.sputterT -= dt;
        if (e.sputterT <= 0) { e.sputterT = 0.15; e.sputter = S.rand() < (0.5 - e.health) * 1.2 ? 0.3 : 1; }
        let lever = Math.min(thr, P.gate) / P.gate;
        if (inp.repair) lever = Math.min(lever, 0.6);
        const mult = ramjet ? P.ramjetMult : burner ? P.burnerMult : 1;
        const thrust = e.flameout ? 0 : P.thrustMax * lever * mult * (0.45 + 0.55 * e.health) * e.sputter;
        e.thrust = thrust / P.thrustMax;
        e.fx += thrust * c; e.fy += thrust * s;
        // Air brake = quadratic drag plus a linear term, so the flaps still bite at low speed.
        // A constant term keeps the brakes biting across a 100x speed range (smoothed below 2 m/s).
        const v = Math.hypot(e.vx, e.vy), cd = P.engineCd + P.brakeCd * brk;
        const bl = P.brakeLin * brk + P.brakeConst * brk / Math.max(v, 2);
        e.fx -= cd * v * e.vx + bl * e.vx; e.fy -= cd * v * e.vy + bl * e.vy;
        const fxp = e.x - c * P.finOffset, fyp = e.y - s * P.finOffset;
        const [pvx, pvy] = pointVel(e, fxp, fyp), vlat = -s * pvx + c * pvy;
        // Repulsor grip saturates; braking lowers the cap, which is what lets you drift.
        const cap = e.m * P.gripCapG * G * (1 - 0.45 * brk);
        const flat = clamp(-e.m * P.engineGrip * vlat, -cap, cap) * e.grip;
        applyAt(e, -s * flat, c * flat, fxp, fyp);
        e.t -= P.yawDamp * e.w;
        // Aero fins: restoring torque toward the direction of travel, growing with speed^2.
        // Pins the nose to the flight path at speed (a few degrees of authority at the top)
        // and fades out when slow, where the lever split turns you hard.
        if (v > 1) e.t -= P.finK * v * v * Math.sin(wrap(e.th - Math.atan2(e.vy, e.vx)));
      }

      if (!S.binderBroken) {
        const dx = R.x - L.x, dy = R.y - L.y, d = Math.hypot(dx, dy), ax = dx / d, ay = dy / d;
        const dvx = R.vx - L.vx, dvy = R.vy - L.vy, stretch = d - P.engineGap;
        const f = P.binderK * stretch + P.binderC * (dvx * ax + dvy * ay);
        R.fx -= f * ax; R.fy -= f * ay; L.fx += f * ax; L.fy += f * ay;
        // Forward is +90deg from the L->R axis. Align both engines to it; feed the
        // reaction back into the pair as a force couple so angular momentum holds.
        const fx = -ay, fy = ax, thf = Math.atan2(fy, fx), wf = (ax * dvy - ay * dvx) / d;
        let Tq = 0;
        for (const e of [L, R]) { const tq = -P.alignK * wrap(e.th - thf) - P.alignC * (e.w - wf); e.t += tq; Tq += tq; }
        const sc = -Tq / d;
        R.fx += sc * fx; R.fy += sc * fy; L.fx -= sc * fx; L.fy -= sc * fy;
        S.pairTh = thf; S.binderStretch = stretch;
        if (Math.abs(stretch) > P.binderBreak) { S.binderBroken = true; S.events.push({ type: 'binder' }); S.crashT = 1.6; }
      }

      const pc = Math.cos(Pd.th), ps = Math.sin(Pd.th);
      [[L, 1], [R, -1]].forEach(([e, side], k) => {
        const ec = Math.cos(e.th), es = Math.sin(e.th);
        const ex = e.x - ec * P.engineLen / 2, ey = e.y - es * P.engineLen / 2;
        const aw = side * P.podAnchorW * P.podWidth / 2;
        const px = Pd.x + pc * P.podLen / 2 - ps * aw, py = Pd.y + ps * P.podLen / 2 + pc * aw;
        const dx = ex - px, dy = ey - py, d = Math.hypot(dx, dy);
        S.cables[k] = { ex, ey, px, py, f: 0, slack: d < P.cableLen };
        if (d <= P.cableLen) return;
        const nx = dx / d, ny = dy / d;
        const [evx, evy] = pointVel(e, ex, ey), [qvx, qvy] = pointVel(Pd, px, py);
        const f = P.cableK * (d - P.cableLen) + P.cableC * ((evx - qvx) * nx + (evy - qvy) * ny);
        if (f <= 0) return;
        S.cables[k].f = f;
        applyAt(Pd, f * nx, f * ny, px, py);
        // Pure per-engine tension makes pod sway steer the pair: pod drifts right,
        // left cable goes taut, left engine lags, craft turns left, pod is flung
        // further right. Share part of the tension through a bridle on the binder
        // (applied at engine centres, no torque) so sway yanks without steering.
        const own = P.cableCouple + (1 - P.cableCouple) / 2, other = k === 0 ? R : L;
        e.fx -= f * nx * own; e.fy -= f * ny * own;
        other.fx -= f * nx * (1 - own); other.fy -= f * ny * (1 - own);
      });

      const pb = Math.min(inp.brkL, inp.brkR);
      const pv = Math.hypot(Pd.vx, Pd.vy), pcd = P.podCd + 0.5 * P.brakeCd * pb;
      const pbl = 0.5 * (P.brakeLin * pb + P.brakeConst * pb / Math.max(pv, 2));
      Pd.fx -= pcd * pv * Pd.vx + pbl * Pd.vx; Pd.fy -= pcd * pv * Pd.vy + pbl * Pd.vy;
      const qx = Pd.x - pc * 1.2, qy = Pd.y - ps * 1.2, [qvx, qvy] = pointVel(Pd, qx, qy);
      const plat = clamp(-Pd.m * P.podGrip * (-ps * qvx + pc * qvy), -Pd.m * P.podCapG * G, Pd.m * P.podCapG * G) * Pd.grip;
      applyAt(Pd, -ps * plat, pc * plat, qx, qy);
      // Tow bar: hold the pod on the engines' centreline (lateral spring-damper toward the
      // point straight behind the pair) and align its heading to theirs; the reaction goes
      // back into the engines. Without it the pod has a real trailer-sway mode, and in
      // high-g turns its own grip points it along its own velocity, off the engines' line.
      if (!S.binderBroken) {
        const pf = Math.cos(S.pairTh), ps2 = Math.sin(S.pairTh), lx = -ps2, ly = pf;
        const back = P.engineLen / 2 + P.cableLen + P.podLen / 2;
        const mxp = (L.x + R.x) / 2, myp = (L.y + R.y) / 2, wpair = (L.w + R.w) / 2;
        const tx = mxp - pf * back, ty = myp - ps2 * back;
        const tvx = (L.vx + R.vx) / 2 + wpair * ps2 * back, tvy = (L.vy + R.vy) / 2 - wpair * pf * back;
        const e = (Pd.x - tx) * lx + (Pd.y - ty) * ly, ev = (Pd.vx - tvx) * lx + (Pd.vy - tvy) * ly;
        const ft = -P.towK * e - P.towC * ev;
        Pd.fx += ft * lx; Pd.fy += ft * ly;
        L.fx -= ft * lx / 2; L.fy -= ft * ly / 2; R.fx -= ft * lx / 2; R.fy -= ft * ly / 2;
        Pd.t -= P.podAlignK * wrap(Pd.th - S.pairTh) + P.podYawDamp * (Pd.w - wpair);
      }

      const cL = engineCircles(L), cR = engineCircles(R), cP = [[Pd.x, Pd.y, 1.6]];
      if (T.kind === 'circuit') { collideWalls(L, cL, dt); collideWalls(R, cR, dt); collideWalls(Pd, cP, dt); }
      bodyPush(L, cL, Pd, cP); bodyPush(R, cR, Pd, cP); bodyPush(L, cL, R, cR);

      for (const b of S.bodies) {
        b.vx += b.fx / b.m * dt; b.vy += b.fy / b.m * dt; b.w += b.t / b.I * dt;
        b.w *= 1 - 0.5 * dt;
        b.x += b.vx * dt; b.y += b.vy * dt; b.th += b.w * dt;
      }
      if (Pd.health <= 0 && S.crashT <= 0) { S.events.push({ type: 'wreck' }); S.crashT = 1.6; Pd.health = 0; }

      if (T.kind === 'range') {
        // Sprint: the clock starts on the first move and stops when the pod sits still inside
        // the box. Overrunning by OVERRUN, or crashing mid-run, is a DNF back to the start line.
        if (!S.runActive && S.result === null && inp.thrL + inp.thrR > 0.02) { S.runActive = true; S.runStart = S.time; }
        if (S.runActive) {
          const inBox = Math.abs(Pd.x - BOX_X) <= BOX_HALF && Math.abs(Pd.y) <= BOX_HALF;
          let end = null;
          if (inBox && pv < STOPPED) {
            const t = S.time - S.runStart;
            end = { type: 'finish', t, err: Math.hypot(Pd.x - BOX_X, Pd.y) };
            S.lastRun = t; S.bestRun = S.bestRun === null ? t : Math.min(S.bestRun, t);
          } else if (Pd.x > BOX_X + OVERRUN) {
            end = { type: 'overrun' };
          } else if (S.crashT > 0) {
            end = { type: 'crash' };
          }
          if (end) {
            S.runActive = false; S.result = end; S.events.push(end);
            if (end.type !== 'finish') { S.finished = true; S.crashT = Math.max(S.crashT, 1.6); }
          }
        }
        return;
      }
      // Laps: count when the pod wraps past the start having visited every checkpoint.
      const prev = S.progressI, cur = Pd.hint, cps = T.checkpoints;
      const cp = Math.floor(cur * cps / T.N);
      if (cp !== S.checkpoint && ((cp - S.checkpoint + cps) % cps) === 1) { S.checkpoint = cp; S.visited.add(cp); }
      if (S.lapStart === null && pv > 2) S.lapStart = S.time;
      if (prev > T.N * 0.9 && cur < T.N * 0.1 && S.visited.size >= cps - 1 && S.lapStart !== null) {
        S.lastLap = S.time - S.lapStart; S.bestLap = S.bestLap === null ? S.lastLap : Math.min(S.bestLap, S.lastLap);
        S.lap++; S.lapStart = S.time; S.visited = new Set([0]); S.events.push({ type: 'lap', t: S.lastLap });
      }
      S.progressI = cur;
    }

    // Range: back to the start line, run cleared (the Y button).
    function restart() {
      S.pod.x = 30; S.pod.y = 0; S.crashT = 0; S.finished = false;
      S.runActive = false; S.runStart = null; S.result = null;
      respawn();
    }

    S.pod.x = P.startX + 30; S.pod.y = P.startY;   // range spawn point (respawn backs off 30 m)
    respawn(0);
    S.visited.add(0);
    return { S, P, T, step, respawn, restart, DEFAULTS, ground: (x, y) => ground(T, x, y),
      box: { x: BOX_X, half: BOX_HALF, overrun: OVERRUN } };
  }

  window.PhaethonSim = { makeSim, DEFAULTS, xorshift32 };
})();
