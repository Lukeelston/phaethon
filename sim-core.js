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
    // Front speed brakes (Luke, 2026-10-19: "front speed brake flaps for braking done at high
    // speed"): flaps ahead of the intakes open with the air brakes, phasing in from 1,500 to
    // 2,500 mph, and add 0.05 to the drag coefficient (the air brakes: 0.04; STARFIGHTER never gets there).
    frontBrakeCd: 0.05, frontBrakeV0: 670.6, frontBrakeV1: 1117.6,
    engineGrip: 30, podGrip: 10, gripCapG: 15, podCapG: 8, finOffset: 0.2, finK: 8,
    yawDamp: 150000, podYawDamp: 50000, podAlignK: 1e6, towK: 1e6, towC: 40000,
    cableLen: 16, cableK: 600000, cableC: 30000, cableCouple: 0.2, podAnchorW: 0.15,
    binderK: 3e6, binderC: 70000, alignK: 2e7, alignC: 6e5, binderBreak: 3.0,
    wallK: 6e6, wallC: 1.5e5, wallMu: 0.35, wallDmgMin: 6,   // impacts below wallDmgMin m/s (into the wall) do no damage
    damage: false,   // wall hits cost health (and can wreck you) only when this is on
    towLongK: 2e6, towLongC: 8e4, towLongSlack: 0.3,   // pod stand-off: never closer to the engines than its taut-cable spot
    bank: 1, bankDown: 3.9e-4,   // banked corners: downforce per (m/s)^2, as g, presses you into the bank (~8 g at 1,000 mph)
    towAudit: true, towAuditG: 3,   // tow-bar energy audit: drag on the speed, never harder than this (g) ...
    towIntF0: 0.05, towIntF1: 0.3, towIntMax: 60,   // ... shifting onto the swing and spin as their share of the energy grows
    heatThrottle: 0.15, heatBurner: 0.12, heatRamjet: 0.35, coolBase: 0.05, coolSpeed: 0.10,
    batteryDrain: 0.08, batteryCharge: 0.05, repairRate: 0.12, damagePerMs: 0.012,
    limits: false,   // battery and heat: off (Luke, 2026-10-18: "turn off battery and heat, let it be crazy"): the burner never runs dry, engines never heat up
    rideH: 1.5, hoverOmega: 9, hoverZeta: 0.9,
    binderKz: 3e6, binderCz: 60000, towKz: 2e5, towCz: 16000,
    track: 'circuit', startX: 0, startY: 0, handling: 'speed',
    job: '',   // the job being flown ('emergency': the emergency run, which opens the shade line)
    // the dawn (the job's clock): a straight front at 1,000 mph travelling dawnDir (rad), passing
    // the start line's point dawnT0 s into the job (tools/job_test.js)
    dawnSpeed: 447.04, dawnDir: 0, dawnT0: 0,
    sfEngageV: 558.8, modeBlendT: 1.0,   // live switch: STARFIGHTER engages below 1,250 mph; the handling blends over 1 s
    seed: 1337
  };

  // Handling modes: named overrides on top of DEFAULTS (explicit overrides still win).
  // speed: the v3 model above, built for the 100-mile sprint.
  // starfighter (2026-10-17, retuned per Luke: "top out at maybe 1200"): tight. Less thrust and
  // more drag cap it at ~990 mph on the lever and 1,200 on the burner (still supersonic); 50 g
  // grip, light yaw damping and small fins bring the nose round ~56 deg/s at 320 mph and ~60
  // flat out; a stiffer tow bar keeps pod sway under 3 deg.
  // tools/handling_test.js '{"handling":"starfighter"}' measures it.
  // Track settings: named overrides per track, on top of DEFAULTS and the handling (explicit
  // overrides still win). The GP's walls deflect rather than wreck (Luke, 2026-10-17): at
  // ~1,000 mph even a shallow scrape meets the wall at 30-60 m/s, which the circuit's rule
  // (damage above 6 m/s) turned into a wrecked engine. On the GP only impacts harder than
  // 25 m/s into the wall do damage, a third as much, and lower wall friction lets you slide
  // off: a scrape costs speed, not health.
  const TRACKS = {
    gp: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },
    eridanus: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22,
      dawnDir: 2.495821, dawnT0: 156.7 }   // the dawn: written by tools/sync_eridanus.py from tools/tune_dawn.js
  };

  const HANDLING = {
    speed: {},
    starfighter: {
      thrustMax: 180000, engineCd: 0.725, podCd: 0.3625,
      gripCapG: 50, engineGrip: 90, podGrip: 30, podCapG: 30, finK: 3, yawDamp: 20000,
      podAlignK: 6e6, podYawDamp: 250000, towK: 5e6, towC: 200000
    }
  };

  // The range: 100 miles of open desert. Speed runway along y = 0, a jump lane at
  // y = +400 with a kicker every 4 km from 8 km, and a twisty lane at y = -400 that only
  // the view draws. No walls, no laps. Launch speed is slope x speed, so the kickers are
  // long and shallow, sized for 2,000-5,000 mph; at a few hundred mph they're bumps.
  const RANGE_LEN = 160934.4, JUMP_Y = 400, JUMP_W = 40, RAMP_X0 = 8000, RAMP_EVERY = 4000;
  // Sprint: stop dead inside a 50 m box at mile 100. Past BOX_X + OVERRUN is a DNF.
  const BOX_X = RANGE_LEN, BOX_HALF = 25, OVERRUN = 15000, STOPPED = 0.5;
  const PAD_HALF = 40, PAD_HOLD = 1.5;   // the job's medical pad: a box +-40 m along and across, held 1.5 s stopped
  const RAMP_H = [3, 6, 10, 15], RAMP_SLOPE = [0.007, 0.011, 0.0157, 0.022];
  function buildRange() {
    const ramps = [];
    for (let i = 0; RAMP_X0 + RAMP_EVERY * i < RANGE_LEN - 500; i++) {
      const h = RAMP_H[i % 4];
      ramps.push({ x0: RAMP_X0 + RAMP_EVERY * i, len: h / RAMP_SLOPE[i % 4], h });
    }
    return { kind: 'range', length: RANGE_LEN, ramps, jumpY: JUMP_Y, jumpW: JUMP_W, N: 0, checkpoints: 0, pts: [], branches: [] };
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
  const smooth01 = (x) => { const t = clamp(x, 0, 1); return t * t * (3 - 2 * t); };   // GDScript's smoothstep
  const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
  // as Godot's smoothstep, so the two sims stay bit-identical
  const smoothstep = (a, b, x) => { const s = Math.min(Math.max((x - a) / (b - a), 0), 1); return s * s * (3 - 2 * s); };

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
    return { kind: 'circuit', pts, N, length: s, checkpoints: 8, branches: [] };
  }

  // The grand prix: a 29.3 km circuit built for STARFIGHTER at ~1,000 mph (tools/design_gp.py
  // designed it: two straights solved so it closes, never within 184 m of itself). Straights and
  // exact arcs, sampled every ~12 m (arc steps are chords on the circle); 64 m wide; walls as on
  // the circuit. Braking: T1-T2 (r230), T5 (r380), T6 (r260), the esses (r420), the hairpin (r160).
  const GP_SEGS = [['S', 2798.158], ['R', 230, 90], ['S', 450], ['L', 230, 90], ['S', 1500], ['L', 1100, 70], ['S', 700],
    ['R', 600, 40], ['S', 900], ['L', 380, 150], ['S', 1100], ['R', 260, 120], ['S', 700], ['L', 900, 30],
    ['S', 1278.727], ['L', 500, 90], ['S', 5200], ['R', 420, 40], ['L', 420, 80], ['R', 420, 40], ['S', 1400],
    ['L', 160, 180], ['S', 500], ['R', 350, 90], ['S', 3200], ['L', 1300, 90]];
  // 96 m wide, every corner banked to GP_BANK degrees toward its inside (Luke, 2026-10-18: "a
  // wider, more banked track"), easing in and out over ~360 m (two passes of a 15-sample box).
  const GP_STEP = 12, GP_WIDTH = 96, GP_BANK = 15, GP_BANK_R = 7;   // bank was 30: "50% smaller"
  // Eridanus (2026-10-18, Luke: "a much much larger course where you switch to speedcraft on long
  // straights and sweeping curves, then brake back down, flip back to starfighter and run the
  // turns"): 199 km, tools/design_eridanus.py. Each segment names its mode: 'sf' (the two towns,
  // STARFIGHTER's) 140 m wide, corners banked 10 deg; 'sp' (the speed loop, SPEEDCRAFT's) 400 m
  // wide, sweepers banked 3 deg so the road ahead tilts into view (Luke, 2026-10-19: "much wider",
  // "bank the speedcraft corners just slightly to help with sight"). Widths ease over ~1 km where
  // the two meet; banks ease over ~1 km in the towns and ~5 km on the loop ("quick elevation
  // changes that are just too intense for the sport").
  const ERI_SEGS = [['S', 3390.539, 0, 'sf'], ['L', 450, 90, 'sf'], ['S', 900, 0, 'sf'], ['R', 300, 90, 'sf'], 
    ['S', 700, 0, 'sf'], ['L', 600, 60, 'sf'], ['R', 600, 60, 'sf'], ['S', 1500, 0, 'sf'], ['S', 9000, 0, 'sp'], 
    ['L', 30000, 8, 'sp'], ['R', 30000, 8, 'sp'], ['S', 8000, 0, 'sp'], ['L', 22000, 90, 'sp'], ['S', 11000, 0, 'sp'], 
    ['L', 500, 50, 'sf'], ['S', 600, 0, 'sf'], ['R', 320, 70, 'sf'], ['S', 500, 0, 'sf'], ['L', 400, 80, 'sf'], 
    ['S', 1500, 0, 'sf'], ['S', 4000, 0, 'sp'], ['R', 15000, 30, 'sp'], ['S', 1000, 0, 'sp'], ['L', 15000, 30, 'sp'], 
    ['S', 3000, 0, 'sp'], ['L', 20000, 30, 'sp'], ['S', 13100, 0, 'sp'], ['L', 16000, 90, 'sp'], 
    ['S', 36152.417, 0, 'sp'], ['L', 700, 60, 'sf'], ['S', 900, 0, 'sf'], ['R', 350, 80, 'sf'], ['S', 800, 0, 'sf'], 
    ['L', 300, 100, 'sf'], ['S', 1000, 0, 'sf'], ['R', 500, 50, 'sf'], ['S', 1200, 0, 'sf'], ['L', 900, 60, 'sf']];
  // <shade> written by tools/sync_eridanus.py: the shade line (a private covered STARFIGHTER line
  // into the start town, tools/design_eridanus.py) and the lake town's medical pad
  const SHADE_SEGS = [['R', 1200, 40, 'sf'], ['S', 500, 0, 'sf'], ['L', 1200, 40, 'sf'], ['S', 1500, 0, 'sf'], ['R', 600, 30, 'sf'], ['S', 3569.081, 0, 'sf'], ['L', 350, 70, 'sf'], ['S', 700, 0, 'sf'], ['R', 300, 40, 'sf'], ['S', 600, 0, 'sf'], ['L', 500, 30, 'sf'], ['S', 2365.036, 0, 'sf'], ['R', 450, 30, 'sf'], ['S', 1500, 0, 'sf'], ['L', 1200, 40, 'sf'], ['S', 500, 0, 'sf'], ['R', 1200, 40, 'sf']];
  const ERI_SHADE = { name: 'shade', segs: SHADE_SEGS, from: 14838, join: 16046, width: 120, jz: 120, covered: [237, 1341], roll: [[182, 292, 0, 180], [1050, 1160, 180, 0]], height: 62 };
  const ERI_PAD = 6932;
  const ERI_RAMPS = [[747, 1283], [6124, 6660], [6995, 7532], [15509, 16045]];   // the covered ramps at each end of each town: [first, last] main samples
  // </shade>
  // The courses: straights and exact arcs, sampled every ~12 m. widths: per mode (else GP_WIDTH,
  // constant); widthR: the width-easing box (samples); banks: per mode, degrees (else GP_BANK in
  // the corners), each mode's eased by two passes of its own box, bankR (samples; else GP_BANK_R).
  const COURSES = {
    gp: { segs: GP_SEGS, checkpoints: 12 },
    eridanus: { segs: ERI_SEGS, checkpoints: 24, widths: { sf: 140, sp: 400 }, widthR: 40, banks: { sf: 10, sp: 3 }, bankR: { sf: 20, sp: 100 }, branches: [ERI_SHADE], pad: ERI_PAD, ramps: ERI_RAMPS }
  };
  function buildCourse(name) {
    const C = COURSES[name];
    const pts = [], raw = [], wraw = [], modes = [];
    let x = 0, y = 0, h = 0;
    for (const sg of C.segs) {
      const m = sg[3] || 'sf';
      const w = C.widths ? C.widths[m] : GP_WIDTH;
      if (sg[0] === 'S') {
        const n = Math.max(1, Math.ceil(sg[1] / GP_STEP)), d = sg[1] / n;
        for (let k = 0; k < n; k++) { pts.push({ x, y }); raw.push(0); wraw.push(w); modes.push(m); x += d * Math.cos(h); y += d * Math.sin(h); }
      } else {
        const r = sg[1], sn = sg[0] === 'L' ? 1 : -1, ang = sg[2] * Math.PI / 180;
        const n = Math.max(1, Math.ceil(r * ang / GP_STEP)), da = ang / n, c = 2 * r * Math.sin(da / 2);
        for (let k = 0; k < n; k++) {
          pts.push({ x, y }); raw.push(sn * (C.banks ? C.banks[m] : m === 'sf' ? GP_BANK : 0) * Math.PI / 180); wraw.push(w); modes.push(m);
          x += c * Math.cos(h + sn * da / 2); y += c * Math.sin(h + sn * da / 2); h += sn * da;
        }
      }
    }
    let bank = null;
    if (C.bankR) {
      bank = new Array(raw.length).fill(0);
      for (const m of ['sf', 'sp']) {
        const part = raw.map((b, i) => (modes[i] === m ? b : 0));
        const sm = smoothRun(smoothRun(part, C.bankR[m]), C.bankR[m]);
        for (let i = 0; i < bank.length; i++) bank[i] += sm[i];
      }
    } else bank = smoothBank(smoothBank(raw));
    const width = C.widths ? smoothBox(wraw, C.widthR) : wraw;
    for (let i = 0; i < pts.length; i++) { pts[i].bank = bank[i]; pts[i].mode = modes[i]; }
    const N = pts.length;
    let s = 0;
    for (let i = 0; i < N; i++) {
      const a = pts[i], b = pts[(i + 1) % N];
      const dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy);
      a.tx = dx / L; a.ty = dy / L; a.nx = -a.ty; a.ny = a.tx; a.len = L; a.s = s; s += L;
      a.w = width[i];
    }
    // the start town's mouth: where the loop last turns into a town (its STARFIGHTER ZONE gate)
    let mouth = -1;
    for (let i = N - 1; i > 0 && mouth < 0; i--) if (modes[i] === 'sf' && modes[i - 1] === 'sp') mouth = i;
    // the covered ramps (shelter from the dawn on the loop at each end of each town): per sample, 1 under one
    const ramps = (C.ramps || []).map((r) => r.slice()), cover = new Uint8Array(N);
    for (const [a, b] of ramps) for (let i = a; i <= b; i++) cover[((i % N) + N) % N] = 1;
    const T = { kind: 'circuit', name, course: true, pts, N, length: s, checkpoints: C.checkpoints, branches: [], pad: C.pad ?? null, mouth, ramps, cover };
    for (const Bd of C.branches || []) T.branches.push(buildBranch(T, Bd));
    return T;
  }

  // A branch road (the shade line): its segments walked from the main road's sample `from` (that
  // point and heading), sampled as the courses are, one width, unbanked, ending on main's `join`
  // (its last sample's segment runs on along the main road's). Open ended, not a loop. Locked
  // unless the job opens it (makeSim).
  function buildBranch(T, Bd) {
    const a0 = T.pts[Bd.from], pts = [];
    let x = a0.x, y = a0.y, h = Math.atan2(a0.ty, a0.tx);
    for (const sg of Bd.segs) {
      if (sg[0] === 'S') {
        const n = Math.max(1, Math.ceil(sg[1] / GP_STEP)), d = sg[1] / n;
        for (let k = 0; k < n; k++) { pts.push({ x, y }); x += d * Math.cos(h); y += d * Math.sin(h); }
      } else {
        const r = sg[1], sn = sg[0] === 'L' ? 1 : -1, ang = sg[2] * Math.PI / 180;
        const n = Math.max(1, Math.ceil(r * ang / GP_STEP)), da = ang / n, c = 2 * r * Math.sin(da / 2);
        for (let k = 0; k < n; k++) {
          pts.push({ x, y });
          x += c * Math.cos(h + sn * da / 2); y += c * Math.sin(h + sn * da / 2); h += sn * da;
        }
      }
    }
    pts.push({ x, y });
    const N = pts.length, J = T.pts[Bd.join];
    let s = 0;
    for (let i = 0; i < N; i++) {
      const a = pts[i], b = pts[i + 1];
      const dx = b ? b.x - a.x : J.tx * J.len, dy = b ? b.y - a.y : J.ty * J.len, L = Math.hypot(dx, dy);
      a.tx = dx / L; a.ty = dy / L; a.nx = -a.ty; a.ny = a.tx; a.len = L; a.s = s; s += L;
      a.w = Bd.width; a.bank = 0; a.mode = 'sf';
    }
    return { name: Bd.name, pts, N, length: s, from: Bd.from, join: Bd.join, jz: Bd.jz, covered: Bd.covered.slice(),
      roll: Bd.roll, height: Bd.height, open: false };
  }

  // A centred moving average round the closed loop (box of 2 * R + 1 samples; banks: GP_BANK_R).
  function smoothBox(a, R) {
    const N = a.length, out = new Array(N);
    for (let i = 0; i < N; i++) {
      let acc = 0;
      for (let k = -R; k <= R; k++) acc += a[(((i + k) % N) + N) % N];
      out[i] = acc / (2 * R + 1);
    }
    return out;
  }
  function smoothBank(a) { return smoothBox(a, GP_BANK_R); }
  // The same average as a running sum: O(N) for the wide boxes (a 5 km bank ramp is 400 samples).
  function smoothRun(a, R) {
    const N = a.length, W = 2 * R + 1, out = new Array(N), at = (k) => a[((k % N) + N) % N];
    let acc = 0;
    for (let k = -R; k <= R; k++) acc += at(k);
    for (let i = 0; i < N; i++) { out[i] = acc / W; acc += at(i + R + 1) - at(i - R); }
    return out;
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
  // The same on an open-ended branch: the window stops at its ends, and a point past either end
  // is off it (off: no road there, however close to the centreline's line).
  function nearestBranch(B, x, y, hint, win) {
    let best = null, bd = Infinity;
    for (let i = Math.max(0, hint - win), hi = Math.min(B.N - 1, hint + win); i <= hi; i++) {
      const a = B.pts[i], u = ((x - a.x) * a.tx + (y - a.y) * a.ty) / a.len, t = clamp(u, 0, 1);
      const px = a.x + a.tx * a.len * t, py = a.y + a.ty * a.len * t;
      const d = (x - px) ** 2 + (y - py) ** 2;
      if (d < bd) {
        bd = d;
        best = { i, lat: (x - a.x) * a.nx + (y - a.y) * a.ny, w: a.w, nx: a.nx, ny: a.ny, off: (i === 0 && u < 0) || (i === B.N - 1 && u > 1) };
      }
    }
    return best;
  }
  // How deep inside its road a point is (negative inside; Infinity off a branch's end).
  const depth = (n, r) => (n.off ? Infinity : Math.abs(n.lat) + r - n.w / 2);

  // path: the road a body's hint is on, 0 the main road, k + 1 branch k
  function body(m, I) { return { m, I, x: 0, y: 0, vx: 0, vy: 0, th: 0, w: 0, fx: 0, fy: 0, t: 0, hint: 0, path: 0, contact: [false, false], z: 0, vz: 0, grip: 1 }; }
  function applyAt(b, fx, fy, px, py) {
    b.fx += fx; b.fy += fy; b.t += (px - b.x) * fy - (py - b.y) * fx;
  }
  function pointVel(b, px, py) { return [b.vx - b.w * (py - b.y), b.vy + b.w * (px - b.x)]; }

  function makeSim(overrides) {
    // the grand prix is a STARFIGHTER track unless a handling is asked for
    const hname = (overrides && overrides.handling) || (COURSES[(overrides && overrides.track) || ''] ? 'starfighter' : DEFAULTS.handling);
    const P = Object.assign({}, DEFAULTS, HANDLING[hname] || {}, TRACKS[(overrides && overrides.track) || ''] || {}, overrides || {}, { handling: hname });
    const T = P.track === 'range' ? buildRange() : COURSES[P.track] ? buildCourse(P.track) : buildTrack();
    const eI = P.engineMass * P.engineLen ** 2 / 12;
    const pI = P.podMass * (P.podLen ** 2 + P.podWidth ** 2) / 12;
    // Live handling switch (Luke, 2026-10-18: "flip a switch on the dashboard" between SPEEDCRAFT
    // and STARFIGHTER mid-lap). inp.handling asks for a mode. STARFIGHTER only engages below
    // P.sfEngageV (its drag at 4,000 mph would be ~200 g), so a flip made while braking waits,
    // then takes; SPEEDCRAFT engages at once. Either way the handling keys blend over
    // P.modeBlendT s, so grip, drag and the tow bar change without a kick. Keys given explicitly
    // in the overrides stay fixed. Inputs without .handling change nothing (old replays hold).
    const HK = Object.keys(HANDLING.starfighter).filter((k) => !(overrides && k in overrides));
    const H0 = {}, H1 = {};
    for (const k of HK) { H0[k] = k in HANDLING.speed ? HANDLING.speed[k] : DEFAULTS[k]; H1[k] = HANDLING.starfighter[k]; }
    const S = {
      P, T, eL: body(P.engineMass, eI), eR: body(P.engineMass, eI), pod: body(P.podMass, pI),
      hwant: hname, hblend: hname === 'starfighter' ? 1 : 0,
      battery: 1, armed: false, mode: 'normal', binderBroken: false, crashT: 0, time: 0, towU: -1,
      lap: 0, lapStart: null, lastLap: null, bestLap: null, visited: new Set(), checkpoint: 0,
      progressI: 0, cables: [{ f: 0 }, { f: 0 }], events: [], rand: xorshift32(P.seed),
      runStart: null, lastRun: null, bestRun: null, finished: false, runActive: false, result: null,
      gate: T.branches.map(() => null), podPath: 0, job: null
    };
    S.bodies = [S.eL, S.eR, S.pod];
    // Branches open only on the job that authorizes them (the shade line: the emergency run).
    for (const B of T.branches) B.open = P.job === 'emergency';
    // The job: out to the pad, home to the start town's mouth, ahead of the dawn. t0: when its
    // clock started (the first move), null until then; prevD: the pod's main-road gap to the mouth.
    // exposed: out in the open on the way home; safe: back under cover since (the margin taken then)
    const newJob = () => ({ stage: 'out', t: 0, t0: null, held: 0, route: 'open', margin: 0, reason: '', prevD: null, exposed: false, safe: false });
    if (P.job === 'emergency' && T.pad !== null && T.pad !== undefined) S.job = newJob();
    // When the dawn front reaches (x, y), in the job's seconds.
    const tLit = (x, y) => P.dawnT0 + (x * Math.cos(P.dawnDir) + y * Math.sin(P.dawnDir)) / P.dawnSpeed;

    // Nearest centreline point on a path: 0 the main road, k + 1 branch k.
    function nearestOn(path, x, y, hint, win) {
      return path === 0 ? nearest(T, x, y, hint, win) : nearestBranch(T.branches[path - 1], x, y, hint, win);
    }
    const cyc = (d) => (d > T.N / 2 ? d - T.N : d < -T.N / 2 ? d + T.N : d);   // a signed sample gap round the loop
    // The other road at a junction, as [path, hint there], or null. A body on the main road sees a
    // branch within jz samples of its split, and only once its craft has passed the gate; a body
    // on a branch sees the main road within jz samples of either end.
    function junctionAlt(b) {
      for (let k = 0; k < T.branches.length; k++) {
        const B = T.branches[k];
        if (b.path === 0) {
          const d = cyc(b.hint - B.from);
          if (S.gate[k] === true && Math.abs(d) <= B.jz) return [k + 1, clamp(d, 0, B.N - 1)];
        } else if (b.path === k + 1) {
          if (b.hint < B.jz) return [0, (B.from + b.hint) % T.N];
          if (b.hint > B.N - 1 - B.jz) return [0, (((B.join - (B.N - 1 - b.hint)) % T.N) + T.N) % T.N];
        }
      }
      return null;
    }
    // The gates: a branch joins a craft's roads only if the craft reached its split's zone at or
    // below sfEngageV (and the job opened it). Arrive faster and it stays shut for that pass, so
    // the main wall holds. Decided once a pass, on the pod's speed as the first body comes into
    // the zone; cleared once no body is in the zone or on the branch.
    function updateGates() {
      for (let k = 0; k < T.branches.length; k++) {
        const B = T.branches[k];
        let busy = false;
        for (const b of S.bodies) if (b.path === k + 1 || (b.path === 0 && Math.abs(cyc(b.hint - B.from)) <= B.jz)) busy = true;
        if (!busy) S.gate[k] = null;
        else if (S.gate[k] === null) S.gate[k] = B.open && Math.hypot(S.pod.vx, S.pod.vy) <= P.sfEngageV;
      }
    }

    function respawn(ci, atIdx) {   // atIdx: a start at that main-road sample (tests, debug views)
      // engines placed so each cable is exactly at length: a stretched spawn makes the stiff
      // cables yank the pod forward on the first step
      const lat = P.engineGap / 2 - P.podAnchorW * P.podWidth / 2;
      const ahead = Math.sqrt(P.cableLen * P.cableLen - lat * lat) + P.podLen / 2 + P.engineLen / 2;
      // Circuit: back at a checkpoint. Range: 30 m behind where the pod is, facing +x.
      let a, idx = 0;
      if (T.kind === 'range') {
        a = { x: Math.max(0, S.pod.x - 30), y: S.pod.y, tx: 1, ty: 0, nx: 0, ny: 1 };
      } else {
        idx = atIdx !== undefined && atIdx >= 0 ? atIdx % T.N : Math.round(((ci ?? -1) < 0 ? S.checkpoint : ci) * T.N / T.checkpoints) % T.N;
        a = T.pts[idx];
      }
      const th = Math.atan2(a.ty, a.tx);
      for (const [b, side] of [[S.eL, 1], [S.eR, -1], [S.pod, 0]]) {
        const fwd = side === 0 ? 0 : ahead;
        b.x = a.x + a.tx * fwd + a.nx * side * P.engineGap / 2;
        b.y = a.y + a.ty * fwd + a.ny * side * P.engineGap / 2;
        b.vx = b.vy = b.w = 0; b.th = th; b.hint = idx; b.path = 0; b.contact = [false, false];
        b.z = ground(T, b.x, b.y) + P.rideH; b.vz = 0; b.grip = 1;
      }
      for (const e of [S.eL, S.eR]) { e.heat = P.limits ? Math.min(e.heat ?? 0.3, 0.5) : 0; e.flameout = false; e.health = e.health ?? 1; e.sputter = 1; e.sputterT = 0; }
      S.pod.health = S.pod.health > 0 ? S.pod.health : 1;
      S.binderBroken = false; S.towU = -1; S.crashT = 0; S.progressI = idx;
      S.gate = T.branches.map(() => null); S.podPath = 0;
    }

    // At a junction the two roads are one (a union): a body takes the road it's deeper inside,
    // when it's off its own or the other is 10 m deeper, and a wall is wherever it's off both.
    function collideWalls(b, circles, dt) {
      const near = nearestOn(b.path, b.x, b.y, b.hint, 40);
      b.hint = near.i;
      const alt = T.branches.length ? junctionAlt(b) : null;
      let altPath = 0, altHint = 0;
      if (alt) {
        const m = nearestOn(alt[0], b.x, b.y, alt[1], 40), dOwn = depth(near, 0), dAlt = depth(m, 0);
        if (dAlt < dOwn && (dOwn > 0 || dAlt < dOwn - 10)) { altPath = b.path; altHint = near.i; b.path = alt[0]; b.hint = m.i; }
        else { altPath = alt[0]; altHint = m.i; }
      }
      circles.forEach(([cx, cy, r], ci) => {
        let n = nearestOn(b.path, cx, cy, b.hint, 12), pen = depth(n, r);
        if (alt) {
          const m = nearestOn(altPath, cx, cy, altHint, 12), pm = depth(m, r);
          if (pm < pen) { n = m; pen = pm; }
        }
        if (pen <= 0) { b.contact[ci] = false; return; }
        const sgn = n.lat > 0 ? -1 : 1, nx = n.nx * sgn, ny = n.ny * sgn;
        const [vx, vy] = pointVel(b, cx, cy), vn = vx * nx + vy * ny;
        if (!b.contact[ci]) {
          const dmg = P.damagePerMs * Math.max(0, -vn - P.wallDmgMin);
          if (P.damage) { if (b === S.pod) S.pod.health -= dmg; else b.health = Math.max(0, b.health - dmg); }
          const who = b === S.pod ? 'pod' : b === S.eL ? 'L' : 'R';
          if (dmg > 0.05) S.events.push({ type: 'hit', who, dmg });
          else S.events.push({ type: 'scrape', who });   // contact without (much) damage: feel it, don't pay for it
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
    function hover(b, dt, az) {
      const h = ground(T, b.x, b.y), dhdt = (ground(T, b.x + b.vx * dt, b.y + b.vy * dt) - h) / dt;
      const w = P.hoverOmega;
      const up = Math.max(0, G + w * w * (P.rideH - (b.z - h)) - 2 * P.hoverZeta * w * (b.vz - dhdt));
      b.vz += (up - G + az) * dt; b.z += b.vz * dt;
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
      if (inp.handling === 'speed' || inp.handling === 'starfighter') S.hwant = inp.handling;
      if (S.pod.path > 0) S.hwant = 'starfighter';   // a shade line is a STARFIGHTER line (its corkscrews are paced for it)
      let htgt = 0;
      if (S.hwant === 'starfighter') htgt = S.hblend > 0 || Math.hypot(S.pod.vx, S.pod.vy) <= P.sfEngageV ? 1 : 0;
      if (S.hblend !== htgt) {
        S.hblend = htgt > S.hblend ? Math.min(htgt, S.hblend + dt / P.modeBlendT) : Math.max(htgt, S.hblend - dt / P.modeBlendT);
        for (const k of HK) P[k] = S.hblend === 1 ? H1[k] : S.hblend === 0 ? H0[k] : H0[k] + (H1[k] - H0[k]) * S.hblend;
        P.handling = S.hblend >= 0.5 ? 'starfighter' : 'speed';
        if (S.hblend === htgt) S.events.push({ type: 'handling', mode: P.handling });
      }
      // Vertical ties: the binder holds both engines at one height and the tow bar lifts the
      // pod toward their mean, so a one-sided ramp hit lifts the whole craft instead of
      // flinging one engine skyward. Exactly zero when heights match (flat ground).
      const az = [0, 0, 0];
      if (!S.binderBroken) {
        const fz = P.binderKz * (R.z - L.z) + P.binderCz * (R.vz - L.vz);
        az[0] += fz / L.m; az[1] -= fz / R.m;
      }
      const ft = P.towKz * ((L.z + R.z) / 2 - Pd.z) + P.towCz * ((L.vz + R.vz) / 2 - Pd.vz);
      az[2] += ft / Pd.m; az[0] -= ft / 2 / L.m; az[1] -= ft / 2 / R.m;
      S.bodies.forEach((b, k) => { b.fx = 0; b.fy = 0; b.t = 0; hover(b, dt, az[k]); });
      S.time += dt;
      const inGate = inp.thrL >= P.gate && inp.thrR >= P.gate && !inp.repair;
      const ramjet = S.armed && inGate;
      const burner = !ramjet && inGate && S.battery > 0;
      S.mode = ramjet ? 'ramjet' : burner ? 'burner' : 'normal';
      if (burner && P.limits) S.battery = Math.max(0, S.battery - P.batteryDrain * dt);
      else if (!inGate) S.battery = Math.min(1, S.battery + P.batteryCharge * dt);
      const speed = Math.hypot(Pd.vx, Pd.vy);

      for (const [e, thr, brk] of [[L, inp.thrL, inp.brkL], [R, inp.thrR, inp.brkR]]) {
        const c = Math.cos(e.th), s = Math.sin(e.th);
        const gain = e.flameout || !P.limits ? 0 : Math.max(0, thr - 0.6) * P.heatThrottle + (burner ? P.heatBurner : 0) + (ramjet ? P.heatRamjet : 0);
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
        const v = Math.hypot(e.vx, e.vy);
        e.front = P.frontBrakeCd > 0 ? brk * smooth01((v - P.frontBrakeV0) / (P.frontBrakeV1 - P.frontBrakeV0)) : 0;
        const cd = P.engineCd + P.brakeCd * brk + P.frontBrakeCd * e.front;
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
        // Stand-off: the pod never closes on the engines past its taut-cable spot (hard or
        // one-sided braking used to fling it into them). Compression only, along the pair's axis
        // through its centre, equal and opposite: it can't twist them or make energy.
        // (its spot: where the diagonal cables are just taut, as respawn lays them out, plus a
        // little slack, so it only ever meets a real overrun and never fights the cables)
        const latC = P.engineGap / 2 - P.podAnchorW * P.podWidth / 2;
        const rest = Math.sqrt(P.cableLen * P.cableLen - latC * latC) + P.podLen / 2 + P.engineLen / 2;
        const el = (Pd.x - tx) * pf + (Pd.y - ty) * ps2 - (back - rest) - P.towLongSlack;
        if (el > 0 && P.towLongK > 0) {
          const elv = (Pd.vx - (L.vx + R.vx) / 2) * pf + (Pd.vy - (L.vy + R.vy) / 2) * ps2;
          const fl = Math.min(0, -P.towLongK * el - P.towLongC * elv);
          Pd.fx += fl * pf; Pd.fy += fl * ps2;
          L.fx -= fl * pf / 2; L.fy -= fl * ps2 / 2; R.fx -= fl * pf / 2; R.fy -= fl * ps2 / 2;
        }
        const podTw = P.podAlignK * wrap(Pd.th - S.pairTh) + P.podYawDamp * (Pd.w - wpair);
        Pd.t -= podTw;
        // Energy audit (see godot/sim/craft_sim.gd). The tow bar is one-way on purpose, so its
        // pull and the pod's twist have no equal and opposite, and that let it create energy:
        // the pod whirled round a pivoting or spinning pair and the craft pinballed. Whatever
        // power these forces put in beyond what their springs gave up is taken back out: from
        // the speed when the craft is travelling (gently, never past towAuditG), from the swing
        // and spin about the centre of mass as their share of the energy grows. Normal flight is
        // untouched; it can never add energy (godot/tests/test_energy.gd).
        if (P.towAudit) {
          const mvx = (L.vx + R.vx) / 2, mvy = (L.vy + R.vy) / 2;
          const pIn = ft * ((Pd.vx - mvx) * lx + (Pd.vy - mvy) * ly) - podTw * Pd.w;
          const dth = wrap(Pd.th - S.pairTh);
          const u = 0.5 * P.towK * e * e + 0.5 * P.podAlignK * dth * dth;
          if (S.towU >= 0) {
            const created = pIn + (u - S.towU) / dt;
            if (created > 0) {
              const msum = Pd.m + L.m + R.m;
              const cvx = (Pd.m * Pd.vx + L.m * L.vx + R.m * R.vx) / msum;
              const cvy = (Pd.m * Pd.vy + L.m * L.vy + R.m * R.vy) / msum;
              let ke = 0, rot = 0, kin = 0;
              for (const b of [Pd, L, R]) {
                ke += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy);
                rot += 0.5 * b.I * b.w * b.w;
                kin += 0.5 * b.m * ((b.vx - cvx) * (b.vx - cvx) + (b.vy - cvy) * (b.vy - cvy));
              }
              kin += rot;
              const cInt = created * smoothstep(P.towIntF0, P.towIntF1, kin / Math.max(ke + rot, 1));
              const cLin = created - cInt;
              if (cInt > 0 && kin > 1) {
                const gi = Math.min(cInt / (2 * kin), P.towIntMax);
                for (const b of [Pd, L, R]) { b.fx -= gi * b.m * (b.vx - cvx); b.fy -= gi * b.m * (b.vy - cvy); b.t -= gi * b.I * b.w; }
              }
              if (cLin > 0 && ke > 1) {
                const vrms = Math.sqrt(2 * ke / msum);
                const gam = Math.min(cLin / (2 * ke), P.towAuditG * G / Math.max(vrms, 1));
                for (const b of [Pd, L, R]) { b.fx -= gam * b.m * b.vx; b.fy -= gam * b.m * b.vy; }
              }
            }
          }
          S.towU = u;
        }
      }

      // Banked corners: the surface tilts toward the inside, so its push has a part toward the
      // corner's centre: gravity's (g tan bank) plus downforce's (bankDown v^2 sin bank).
      if (T.course) {
        for (const b of S.bodies) {
          const a = (b.path === 0 ? T.pts : T.branches[b.path - 1].pts)[b.hint], bk = a.bank;
          if (bk === 0) continue;
          const v2 = b.vx * b.vx + b.vy * b.vy;
          const f = P.bank * b.m * (G * Math.tan(bk) + P.bankDown * v2 * Math.sin(bk)) * b.grip;
          b.fx += f * a.nx; b.fy += f * a.ny;
        }
      }
      const cL = engineCircles(L), cR = engineCircles(R), cP = [[Pd.x, Pd.y, 1.6]];
      if (T.branches.length) updateGates();
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
      // Laps: count when the pod wraps past the start having visited every checkpoint. On the
      // main road only: on a branch the pod keeps its progress, and back on the main road it
      // carries on from that checkpoint (a shortcut visits none of the ones it skipped).
      if (Pd.path !== 0) S.podPath = Pd.path;
      else {
        const prev = S.progressI, cur = Pd.hint, cps = T.checkpoints;
        const cp = Math.floor(cur * cps / T.N);
        if (S.podPath !== 0) { S.podPath = 0; S.checkpoint = cp; }
        if (cp !== S.checkpoint && ((cp - S.checkpoint + cps) % cps) === 1) { S.checkpoint = cp; S.visited.add(cp); }
        if (S.lapStart === null && pv > 2) S.lapStart = S.time;
        if (prev > T.N * 0.9 && cur < T.N * 0.1 && S.visited.size >= cps - 1 && S.lapStart !== null) {
          S.lastLap = S.time - S.lapStart; S.bestLap = S.bestLap === null ? S.lastLap : Math.min(S.bestLap, S.lastLap);
          S.lap++; S.lapStart = S.time; S.visited = new Set([0]); S.events.push({ type: 'lap', t: S.lastLap });
        }
        S.progressI = cur;
      }
      if (S.job) jobStep(inp, dt, pv);
    }

    // The job (the emergency run, docs/superpowers/specs/2026-10-19-emergency-run-design.md): its
    // clock starts on the first move. Out to the lake town's pad (stopped in its box PAD_HOLD s:
    // the drop), then home to the start town's mouth before the dawn front. The towns are shelter,
    // and so is the shade line past its canopy's start; caught in the open, the job fails. Each
    // route's margin is taken at its own deadline: the open loop's at the mouth, the shade line's
    // as the pod goes under the canopy.
    function jobStep(inp, dt, pv) {
      const J = S.job, Pd = S.pod;
      if (J.stage === 'done' || J.stage === 'failed') return;
      if (J.t0 === null) {
        if (inp.thrL + inp.thrR <= 0.02) return;
        J.t0 = S.time;
      }
      const t = J.t = S.time - J.t0;
      const to = (stage, extra) => { J.stage = stage; S.events.push(Object.assign({ type: 'job', stage }, extra || {})); };
      if (S.crashT > 0) { J.reason = 'crash'; to('failed'); return; }   // wrecked this step
      const lit = tLit(Pd.x, Pd.y), B = Pd.path > 0 ? T.branches[Pd.path - 1] : null;
      const covered = B !== null && Pd.hint >= B.covered[0];
      // under the canopy you've made it: coming off the shade line the main road joins under it
      // (the join's zone, short of the mouth), and the town is shelter from there
      const Bs = T.branches[0], dj = Bs ? cyc(Pd.hint - Bs.join) : 1;
      const merging = Pd.path === 0 && J.route === 'shade' && dj >= -Bs.jz && dj <= 0;
      // shelter: a town, a covered ramp, the shade line's canopy
      const sheltered = covered || merging || (Pd.path === 0 && (T.pts[Pd.hint].mode === 'sf' || T.cover[Pd.hint] === 1));
      if (!sheltered && t >= lit) {
        J.reason = 'dawn'; S.events.push({ type: 'dawn' }); to('failed'); S.crashT = 1.6;
        return;
      }
      // home: the deadline is getting back under cover after the open loop (a receiving ramp, or
      // the shade line's canopy); the margin is taken there
      if (J.stage === 'home') {
        if (!sheltered) J.exposed = true;
        else if (J.exposed && !J.safe) { J.safe = true; J.route = covered ? 'shade' : 'open'; J.margin = lit - t; }
      }
      if (J.stage === 'out' || J.stage === 'drop') {
        const a = T.pts[T.pad], dx = Pd.x - a.x, dy = Pd.y - a.y;
        const onPad = Pd.path === 0 && Math.abs(dx * a.tx + dy * a.ty) <= PAD_HALF && Math.abs(dx * a.nx + dy * a.ny) <= PAD_HALF;
        if (J.stage === 'out') {
          J.held = onPad && pv < STOPPED ? J.held + dt : 0;
          if (J.held >= PAD_HOLD - 1e-9) to('drop');
        } else if (!onPad) to('home');
      } else if (J.stage === 'home') {
        const d = Pd.path === 0 ? cyc(Pd.hint - T.mouth) : null;
        if (d !== null && d >= 0 && d < 100 && J.prevD !== null && J.prevD < 0 && J.prevD > -100) {   // crossed the mouth, coming home
          if (!J.safe) J.margin = tLit(T.pts[T.mouth].x, T.pts[T.mouth].y) - t;   // never out in the open: the mouth's
          to('done', { route: J.route, margin: J.margin });
        }
        J.prevD = d;
      }
    }

    // Range: back to the start line, run cleared (the Y button).
    // A fresh start (the player's restart): whole engines and pod, full battery, cool engines;
    // the range goes back to its start line, a circuit to its grid with the lap count reset.
    // Crashes still respawn through respawn(), keeping the damage.
    function restart() {
      S.crashT = 0; S.finished = false; S.runActive = false; S.runStart = null; S.result = null;
      for (const e of [S.eL, S.eR]) { e.health = 1; e.heat = P.limits ? 0.3 : 0; }
      S.pod.health = 1; S.battery = 1;
      if (T.kind === 'range') { S.pod.x = 30; S.pod.y = 0; respawn(); }
      else { S.lap = 0; S.lapStart = null; S.visited = new Set([0]); S.checkpoint = 0; respawn(0); }
      if (S.job) S.job = newJob();   // the job starts over (its clock on the next first move)
    }

    S.pod.x = P.startX + 30; S.pod.y = P.startY;   // range spawn point (respawn backs off 30 m)
    respawn(0);
    S.visited.add(0);
    return { S, P, T, step, respawn, restart, nearestOn, tLit, DEFAULTS, ground: (x, y) => ground(T, x, y),
      box: { x: BOX_X, half: BOX_HALF, overrun: OVERRUN } };
  }

  window.PhaethonSim = { makeSim, DEFAULTS, HANDLING, TRACKS, COURSES, xorshift32 };
})();
