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
    // forceScale: thrust, drag and the brakes times this. A heavier pod (Luke, 2026-10-20: "giving the
    // pod some weight") comes with forceScale = the total mass over the standard's (2,900 kg), so
    // straight-line speed and acceleration are unchanged and only the turning feels the weight.
    forceScale: 1,
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
    // traffic's forcefields (the Network): a softer push than a wall's, no friction, no damage; a
    // closing speed over smashV (m/s, ~1,500 mph) is the catastrophic hit
    fieldK: 2e6, fieldC: 8e4, smashV: 670,
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
    gp_dunes: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },
    gp_glacier: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },
    gp_basalt: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },
    gp_mesa: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22 },

    eridanus: { wallDmgMin: 25, damagePerMs: 0.004, wallMu: 0.22,
      dawnDir: 2.495821, dawnT0: 171.7 },   // the dawn: written by tools/sync_eridanus.py from tools/tune_dawn.js
    // The Network: walls are forcefields (docs/superpowers/specs/2026-10-19-network-design.md): a
    // wall shoves you off, only a catastrophic crash (the binder breaking) costs you anything
    network: { wallDmgMin: 1e9, damagePerMs: 0, wallMu: 0.22 }
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
  // <gp_variants> (tools/sync_gp_variants.py: the city GPs, the grand prix four ways; don't edit by hand)
  const GP_DUNES_SEGS = [['S', 2798.158], ['R', 230.0, 90.0], ['S', 450.0], ['L', 230.0, 90.0], ['S', 1500.0], ['L', 1100.0, 70.0], ['S', 700.0], ['R', 600.0, 40.0], ['S', 900.0], ['L', 380.0, 150.0], ['S', 1100.0], ['R', 260.0, 120.0], ['S', 700.0], ['L', 900.0, 30.0], ['S', 1278.727], ['L', 500.0, 90.0], ['S', 5200.0], ['R', 420.0, 40.0], ['L', 420.0, 80.0], ['R', 420.0, 40.0], ['S', 1400.0], ['L', 160.0, 180.0], ['S', 500.0], ['R', 350.0, 90.0], ['S', 3200.0], ['L', 1300.0, 90.0]];
  const GP_GLACIER_SEGS = [['S', 2798.158], ['L', 230.0, 90.0], ['S', 450.0], ['R', 230.0, 90.0], ['S', 1500.0], ['R', 1100.0, 70.0], ['S', 700.0], ['L', 600.0, 40.0], ['S', 900.0], ['R', 380.0, 150.0], ['S', 1100.0], ['L', 260.0, 120.0], ['S', 700.0], ['R', 900.0, 30.0], ['S', 1278.727], ['R', 500.0, 90.0], ['S', 5200.0], ['L', 420.0, 40.0], ['R', 420.0, 80.0], ['L', 420.0, 40.0], ['S', 1400.0], ['R', 160.0, 180.0], ['S', 500.0], ['L', 350.0, 90.0], ['S', 3200.0], ['R', 1300.0, 90.0]];
  const GP_BASALT_SEGS = [['S', 5200.0], ['R', 500.0, 90.0], ['S', 1278.727], ['R', 900.0, 30.0], ['S', 700.0], ['L', 260.0, 120.0], ['S', 1100.0], ['R', 380.0, 150.0], ['S', 900.0], ['L', 600.0, 40.0], ['S', 700.0], ['R', 1100.0, 70.0], ['S', 1500.0], ['R', 230.0, 90.0], ['S', 450.0], ['L', 230.0, 90.0], ['S', 2798.158], ['R', 1300.0, 90.0], ['S', 3200.0], ['L', 350.0, 90.0], ['S', 500.0], ['R', 160.0, 180.0], ['S', 1400.0], ['L', 420.0, 40.0], ['R', 420.0, 80.0], ['L', 420.0, 40.0]];
  const GP_MESA_SEGS = [['S', 5200.0], ['L', 500.0, 90.0], ['S', 1278.727], ['L', 900.0, 30.0], ['S', 700.0], ['R', 260.0, 120.0], ['S', 1100.0], ['L', 380.0, 150.0], ['S', 900.0], ['R', 600.0, 40.0], ['S', 700.0], ['L', 1100.0, 70.0], ['S', 1500.0], ['L', 230.0, 90.0], ['S', 450.0], ['R', 230.0, 90.0], ['S', 2798.158], ['L', 1300.0, 90.0], ['S', 3200.0], ['R', 350.0, 90.0], ['S', 500.0], ['L', 160.0, 180.0], ['S', 1400.0], ['R', 420.0, 40.0], ['L', 420.0, 80.0], ['R', 420.0, 40.0]];
  // </gp_variants>
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
  // <network> (tools/sync_network.py from tools/design_network.py: don't edit by hand)
  const NET_STEP = 24.0;
  // [name, x, y, heading deg, width, [[kind, length or radius, deg, mode], ...]]
  const NET_ROADS = [
    ['E1', 25000.0, 100000.0, 0.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 16.0, 'sp'], ['S', 31409.384254095403, 0.0, 'sp'], ['R', 45000.0, 32.0, 'sp'], ['S', 31409.384254095403, 0.0, 'sp'], ['L', 45000.0, 16.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 13.0, 'sp'], ['S', 35668.58872733586, 0.0, 'sp'], ['L', 45000.0, 26.0, 'sp'], ['S', 35668.58872733586, 0.0, 'sp'], ['R', 45000.0, 13.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['E2', 25000.0, 300000.0, 0.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 20.0, 'sp'], ['S', 25772.456402216954, 0.0, 'sp'], ['R', 45000.0, 40.0, 'sp'], ['S', 25772.456402216954, 0.0, 'sp'], ['L', 45000.0, 20.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 15.0, 'sp'], ['S', 32824.76260375352, 0.0, 'sp'], ['L', 45000.0, 30.0, 'sp'], ['S', 32824.76260375352, 0.0, 'sp'], ['R', 45000.0, 15.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['E3', 25000.0, 500000.0, 0.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 14.0, 'sp'], ['S', 34244.22935835813, 0.0, 'sp'], ['R', 45000.0, 28.0, 'sp'], ['S', 34244.22935835813, 0.0, 'sp'], ['L', 45000.0, 14.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 18.0, 'sp'], ['S', 28587.64967214313, 0.0, 'sp'], ['L', 45000.0, 36.0, 'sp'], ['S', 28587.64967214313, 0.0, 'sp'], ['R', 45000.0, 18.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['N1', 100000.0, 25000.0, 90.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 17.0, 'sp'], ['S', 29997.285275513706, 0.0, 'sp'], ['R', 45000.0, 34.0, 'sp'], ['S', 29997.285275513706, 0.0, 'sp'], ['L', 45000.0, 17.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 19.0, 'sp'], ['S', 27179.652269197013, 0.0, 'sp'], ['L', 45000.0, 38.0, 'sp'], ['S', 27179.652269197013, 0.0, 'sp'], ['R', 45000.0, 19.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['N2', 300000.0, 25000.0, 90.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 21.0, 'sp'], ['S', 24365.211496849173, 0.0, 'sp'], ['R', 45000.0, 42.0, 'sp'], ['S', 24365.211496849173, 0.0, 'sp'], ['L', 45000.0, 21.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 14.0, 'sp'], ['S', 34244.22935835813, 0.0, 'sp'], ['L', 45000.0, 28.0, 'sp'], ['S', 34244.22935835813, 0.0, 'sp'], ['R', 45000.0, 14.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['N3', 500000.0, 25000.0, 90.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 13.0, 'sp'], ['S', 35668.58872733586, 0.0, 'sp'], ['R', 45000.0, 26.0, 'sp'], ['S', 35668.58872733586, 0.0, 'sp'], ['L', 45000.0, 13.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 20.0, 'sp'], ['S', 25772.456402216954, 0.0, 'sp'], ['L', 45000.0, 40.0, 'sp'], ['S', 25772.456402216954, 0.0, 'sp'], ['R', 45000.0, 20.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['R00WS', 87900.0, 99900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R00WN', 87900.0, 100100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R00ES', 112100.0, 99900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R00EN', 112100.0, 100100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R01WS', 87900.0, 299900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R01WN', 87900.0, 300100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R01ES', 112100.0, 299900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R01EN', 112100.0, 300100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R02WS', 87900.0, 499900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R02WN', 87900.0, 500100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R02ES', 112100.0, 499900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R02EN', 112100.0, 500100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R10WS', 287900.0, 99900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R10WN', 287900.0, 100100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R10ES', 312100.0, 99900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R10EN', 312100.0, 100100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R11WS', 287900.0, 299900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R11WN', 287900.0, 300100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R11ES', 312100.0, 299900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R11EN', 312100.0, 300100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R12WS', 287900.0, 499900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R12WN', 287900.0, 500100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R12ES', 312100.0, 499900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R12EN', 312100.0, 500100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R20WS', 487900.0, 99900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R20WN', 487900.0, 100100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R20ES', 512100.0, 99900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R20EN', 512100.0, 100100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R21WS', 487900.0, 299900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R21WN', 487900.0, 300100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R21ES', 512100.0, 299900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R21EN', 512100.0, 300100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R22WS', 487900.0, 499900.0, 0.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['R22WN', 487900.0, 500100.0, 0.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R22ES', 512100.0, 499900.0, 180.0, 200.0, [['L', 12000.0, 90.0, 'sp']]],
    ['R22EN', 512100.0, 500100.0, 180.0, 200.0, [['R', 12000.0, 90.0, 'sp']]],
    ['Eridanus', 343000.0, 300100.0, 180.0, 200.0, [['R', 7000.0, 60.0, 'sp'], ['S', 3500.0, 0.0, 'sp'], ['L', 7000.0, 120.0, 'sf'], ['S', 3500.0, 0.0, 'sp'], ['R', 7000.0, 60.0, 'sp']]],
    ['Dunes', 57000.0, 500100.0, 0.0, 200.0, [['L', 7000.0, 60.0, 'sp'], ['S', 3500.0, 0.0, 'sp'], ['R', 7000.0, 120.0, 'sf'], ['S', 3500.0, 0.0, 'sp'], ['L', 7000.0, 60.0, 'sp']]],
    ['Glacier', 543000.0, 500100.0, 180.0, 200.0, [['R', 7000.0, 60.0, 'sp'], ['S', 3500.0, 0.0, 'sp'], ['L', 7000.0, 120.0, 'sf'], ['S', 3500.0, 0.0, 'sp'], ['R', 7000.0, 60.0, 'sp']]],
    ['Basalt', 57000.0, 99900.0, 0.0, 200.0, [['R', 7000.0, 60.0, 'sp'], ['S', 3500.0, 0.0, 'sp'], ['L', 7000.0, 120.0, 'sf'], ['S', 3500.0, 0.0, 'sp'], ['R', 7000.0, 60.0, 'sp']]],
    ['Mesa', 543000.0, 99900.0, 180.0, 200.0, [['L', 7000.0, 60.0, 'sp'], ['S', 3500.0, 0.0, 'sp'], ['R', 7000.0, 120.0, 'sf'], ['S', 3500.0, 0.0, 'sp'], ['L', 7000.0, 60.0, 'sp']]],
    ['TE1-', 26600.0, 100100.0, -180.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TE1+', 573400.0000000542, 99900.00000000012, 3.8246170044598787e-13, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TE2-', 26600.0, 300100.0, -180.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TE2+', 573399.9999999488, 299899.99999999924, -3.26739873311754e-13, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TE3-', 26600.0, 500100.0, -180.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TE3+', 573399.9999999489, 499900.000000001, 3.7730572313033416e-13, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN1-', 99900.0, 26600.0, -90.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN1+', 100099.99999999856, 573399.9999999264, 90.0000000000011, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN2-', 299900.0, 26600.0, -90.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN2+', 300099.9999999948, 573399.9999999453, 90.00000000000979, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN3-', 499900.0, 26600.0, -90.0, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['TN3+', 500099.9999999891, 573400.0000000342, 90.00000000000406, 200.0, [['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp']]],
    ['J0', 268000.0, 299900.0, 0.0, 200.0, [['R', 45000.0, 7.1506790378981435, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['S', 7796.8754358438055, 0.0, 'sp']]],
    ['K0', 290218.6999999926, 299200.00000000047, 0.0, 400.0, [['S', 36578.175435843805, 0.0, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['R', 45000.0, 7.1506790378981435, 'sp']]],
    ['J1', 300100.0, 68000.0, 90.0, 200.0, [['R', 45000.0, 7.1506790378981435, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['S', 7796.8754358438055, 0.0, 'sp']]],
    ['K1', 300799.9999999999, 90218.69999999818, 90.0, 400.0, [['S', 36578.175435843805, 0.0, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['R', 45000.0, 7.1506790378981435, 'sp']]],
    ['J2', 332000.0, 500100.0, -180.0, 200.0, [['R', 45000.0, 7.1506790378981435, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['S', 7796.8754358438055, 0.0, 'sp']]],
    ['K2', 309781.3000000074, 500799.9999999994, -180.0, 400.0, [['S', 36578.175435843805, 0.0, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['R', 45000.0, 7.1506790378981435, 'sp']]],
    ['J3', 99900.0, 332000.0, -90.0, 200.0, [['R', 45000.0, 7.1506790378981435, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['S', 7796.8754358438055, 0.0, 'sp']]],
    ['K3', 99199.99999999994, 309781.3000000074, -90.0, 400.0, [['S', 36578.175435843805, 0.0, 'sp'], ['L', 45000.0, 7.1506790378981435, 'sp'], ['R', 45000.0, 7.1506790378981435, 'sp']]],
    ['OEridanus', 266000.0, 304000.0, 0.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['ODunes', 134000.0, 504000.0, 180.0, 200.0, [['L', 12000.0, 33.12294020774379, 'sp'], ['R', 12000.0, 33.12294020774379, 'sp']]],
    ['OGlacier', 466000.0, 504000.0, 0.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['OBasalt', 134000.0, 96000.0, 180.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['OMesa', 466000.0, 96000.0, 0.0, 200.0, [['L', 12000.0, 33.12294020774379, 'sp'], ['R', 12000.0, 33.12294020774379, 'sp']]],
  ];
  // [parent road, a0, a1, child road, b0, b1, sense]: the two roads are one through these samples
  const NET_JUNCTIONS = [
    [0, 2611, 2731, 6, 0, 101, 1], [3, 2611, 2731, 6, 685, 786, -1], [0, 2611, 2731, 7, 0, 101, 1], [3, 3519, 3639, 7, 685, 786, 1], [0, 3519, 3639, 8, 0, 101, -1], [3, 2611, 2731, 8, 685, 786, -1],
    [0, 3519, 3639, 9, 0, 101, -1], [3, 3519, 3639, 9, 685, 786, 1], [1, 2611, 2731, 10, 0, 101, 1], [3, 11088, 11208, 10, 685, 786, -1], [1, 2611, 2731, 11, 0, 101, 1], [3, 11996, 12116, 11, 685, 786, 1],
    [1, 3519, 3639, 12, 0, 101, -1], [3, 11088, 11208, 12, 685, 786, -1], [1, 3519, 3639, 13, 0, 101, -1], [3, 11996, 12116, 13, 685, 786, 1], [2, 2611, 2731, 14, 0, 101, 1], [3, 19592, 19712, 14, 685, 786, -1],
    [2, 2611, 2731, 15, 0, 101, 1], [3, 20500, 20620, 15, 685, 786, 1], [2, 3519, 3639, 16, 0, 101, -1], [3, 19592, 19712, 16, 685, 786, -1], [2, 3519, 3639, 17, 0, 101, -1], [3, 20500, 20620, 17, 685, 786, 1],
    [0, 11075, 11195, 18, 0, 101, 1], [4, 2611, 2731, 18, 685, 786, -1], [0, 11075, 11195, 19, 0, 101, 1], [4, 3519, 3639, 19, 685, 786, 1], [0, 11983, 12103, 20, 0, 101, -1], [4, 2611, 2731, 20, 685, 786, -1],
    [0, 11983, 12103, 21, 0, 101, -1], [4, 3519, 3639, 21, 685, 786, 1], [1, 11128, 11248, 22, 0, 101, 1], [4, 11144, 11264, 22, 685, 786, -1], [1, 11128, 11248, 23, 0, 101, 1], [4, 12052, 12172, 23, 685, 786, 1],
    [1, 12036, 12156, 24, 0, 101, -1], [4, 11144, 11264, 24, 685, 786, -1], [1, 12036, 12156, 25, 0, 101, -1], [4, 12052, 12172, 25, 685, 786, 1], [2, 11050, 11170, 26, 0, 101, 1], [4, 19583, 19703, 26, 685, 786, -1],
    [2, 11050, 11170, 27, 0, 101, 1], [4, 20491, 20611, 27, 685, 786, 1], [2, 11958, 12078, 28, 0, 101, -1], [4, 19583, 19703, 28, 685, 786, -1], [2, 11958, 12078, 29, 0, 101, -1], [4, 20491, 20611, 29, 685, 786, 1],
    [0, 19502, 19622, 30, 0, 101, 1], [5, 2611, 2731, 30, 685, 786, -1], [0, 19502, 19622, 31, 0, 101, 1], [5, 3519, 3639, 31, 685, 786, 1], [0, 20410, 20530, 32, 0, 101, -1], [5, 2611, 2731, 32, 685, 786, -1],
    [0, 20410, 20530, 33, 0, 101, -1], [5, 3519, 3639, 33, 685, 786, 1], [1, 19578, 19698, 34, 0, 101, 1], [5, 11038, 11158, 34, 685, 786, -1], [1, 19578, 19698, 35, 0, 101, 1], [5, 11946, 12066, 35, 685, 786, 1],
    [1, 20486, 20606, 36, 0, 101, -1], [5, 11038, 11158, 36, 685, 786, -1], [1, 20486, 20606, 37, 0, 101, -1], [5, 11946, 12066, 37, 685, 786, 1], [2, 19543, 19663, 38, 0, 101, 1], [5, 19555, 19675, 38, 685, 786, -1],
    [2, 19543, 19663, 39, 0, 101, 1], [5, 20463, 20583, 39, 685, 786, 1], [2, 20451, 20571, 40, 0, 101, -1], [5, 19555, 19675, 40, 685, 786, -1], [2, 20451, 20571, 41, 0, 101, -1], [5, 20463, 20583, 41, 685, 786, 1],
    [1, 13345, 13444, 42, 0, 80, -1], [1, 12267, 12366, 42, 1435, 1515, -1], [2, 1323, 1422, 43, 0, 80, 1], [2, 2401, 2500, 43, 1435, 1515, 1], [2, 21760, 21859, 44, 0, 80, -1], [2, 20682, 20781, 44, 1435, 1515, -1],
    [0, 1323, 1422, 45, 0, 80, 1], [0, 2401, 2500, 45, 1435, 1515, 1], [0, 21719, 21818, 46, 0, 80, -1], [0, 20641, 20740, 46, 1435, 1515, -1], [0, 0, 77, 47, 0, 74, -1], [0, 0, 77, 47, 1751, 1825, 1],
    [0, 23064, 23141, 48, 0, 74, 1], [0, 23064, 23141, 48, 1751, 1825, -1], [1, 0, 77, 49, 0, 74, -1], [1, 0, 77, 49, 1751, 1825, 1], [1, 23140, 23217, 50, 0, 74, 1], [1, 23140, 23217, 50, 1751, 1825, -1],
    [2, 0, 77, 51, 0, 74, -1], [2, 0, 77, 51, 1751, 1825, 1], [2, 23105, 23182, 52, 0, 74, 1], [2, 23105, 23182, 52, 1751, 1825, -1], [3, 0, 77, 53, 0, 74, -1], [3, 0, 77, 53, 1751, 1825, 1],
    [3, 23154, 23231, 54, 0, 74, 1], [3, 23154, 23231, 54, 1751, 1825, -1], [4, 0, 77, 55, 0, 74, -1], [4, 0, 77, 55, 1751, 1825, 1], [4, 23145, 23222, 56, 0, 74, 1], [4, 23145, 23222, 56, 1751, 1825, -1],
    [5, 0, 77, 57, 0, 74, -1], [5, 0, 77, 57, 1751, 1825, 1], [5, 23117, 23194, 58, 0, 74, 1], [5, 23117, 23194, 58, 1751, 1825, -1], [1, 10299, 10505, 59, 0, 187, 1], [1, 12990, 13235, 60, 1768, 1995, 1],
    [4, 1782, 1988, 61, 0, 187, 1], [4, 4473, 4718, 62, 1768, 1995, 1], [2, 12701, 12907, 63, 0, 187, -1], [2, 9971, 10216, 64, 1768, 1995, -1], [3, 12739, 12945, 65, 0, 187, -1], [3, 10009, 10254, 66, 1768, 1995, -1],
    [1, 10662, 10782, 67, 479, 580, 1], [2, 3985, 4105, 68, 479, 580, -1], [2, 19077, 19197, 69, 479, 580, 1], [0, 3985, 4105, 70, 479, 580, -1], [0, 19036, 19156, 71, 479, 580, 1],
  ];
  // [name, biome, centre x, centre y, road, terminal sample]
  const NET_CITIES = [
    ['ERIDANUS', 'verdant', 329137.64169443276, 313131.07863207115, 42, 757],
    ['DUNES', 'desert', 70862.35830556872, 513131.0786320711, 43, 757],
    ['GLACIER', 'ice', 529137.6416944333, 513131.07863207115, 44, 757],
    ['BASALT', 'basalt', 70862.35830556872, 86868.92136793051, 45, 757],
    ['MESA', 'mesa', 529137.6416944332, 86868.92136793045, 46, 757],
  ];
  // the roads' heights: [road, [[sample, m, slope], ...]], Hermite between keys (flyovers, jumps)
  const NET_HEIGHTS = [
    [3, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11227, 0.0, 0.0], [11477, 120.0, 0.0], [11727, 120.0, 0.0], [11977, 0.0, 0.0], [19731, 0.0, 0.0], [19981, 120.0, 0.0], [20231, 120.0, 0.0], [20481, 0.0, 0.0]]],
    [4, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11283, 0.0, 0.0], [11533, 120.0, 0.0], [11783, 120.0, 0.0], [12033, 0.0, 0.0], [19722, 0.0, 0.0], [19972, 120.0, 0.0], [20222, 120.0, 0.0], [20472, 0.0, 0.0]]],
    [5, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11177, 0.0, 0.0], [11427, 120.0, 0.0], [11677, 120.0, 0.0], [11927, 0.0, 0.0], [19694, 0.0, 0.0], [19944, 120.0, 0.0], [20194, 120.0, 0.0], [20444, 0.0, 0.0]]],
    [59, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
    [60, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
    [61, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
    [62, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
    [63, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
    [64, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
    [65, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
    [66, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
  ];
  // [launch road (its end is a lip), catch deck, the slowest that lands (mph)]
  const NET_JUMPS = [[59, 60, 3000.0], [61, 62, 3000.0], [63, 64, 3000.0], [65, 66, 3000.0]];
  // [city, road]: the on-ramps from the open ground (their start is open)
  const NET_ONRAMPS = [[0, 67], [1, 68], [2, 69], [3, 70], [4, 71]];
  // </network>
  // The courses: straights and exact arcs, sampled every ~12 m. widths: per mode (else GP_WIDTH,
  // constant); widthR: the width-easing box (samples); banks: per mode, degrees (else GP_BANK in
  // the corners), each mode's eased by two passes of its own box, bankR (samples; else GP_BANK_R).
  const COURSES = {
    gp: { segs: GP_SEGS, checkpoints: 12 },
    gp_dunes: { segs: GP_DUNES_SEGS, checkpoints: 12 },
    gp_glacier: { segs: GP_GLACIER_SEGS, checkpoints: 12 },
    gp_basalt: { segs: GP_BASALT_SEGS, checkpoints: 12 },
    gp_mesa: { segs: GP_MESA_SEGS, checkpoints: 12 },

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

  // The Network (tools/design_network.py): open roads, each walked from its own pose as a branch is
  // from its split (NET_STEP samples, a mode per segment; the last sample keeps the end heading), and
  // a junction table: through [a0, a1] on road a and [b0, b1] on road b the two are one road.
  function buildNetwork() {
    const roads = NET_ROADS.map(([name, x0, y0, hdeg, width, segs]) => {
      const pts = [];
      let x = x0, y = y0, h = hdeg * Math.PI / 180, mode = 'sp';
      for (const sg of segs) {
        mode = sg[3];
        if (sg[0] === 'S') {
          const n = Math.max(1, Math.ceil(sg[1] / NET_STEP)), d = sg[1] / n;
          for (let k = 0; k < n; k++) { pts.push({ x, y, mode }); x += d * Math.cos(h); y += d * Math.sin(h); }
        } else {
          const r = sg[1], sn = sg[0] === 'L' ? 1 : -1, ang = sg[2] * Math.PI / 180;
          const n = Math.max(1, Math.ceil(r * ang / NET_STEP)), da = ang / n, c = 2 * r * Math.sin(da / 2);
          for (let k = 0; k < n; k++) {
            pts.push({ x, y, mode });
            x += c * Math.cos(h + sn * da / 2); y += c * Math.sin(h + sn * da / 2); h += sn * da;
          }
        }
      }
      pts.push({ x, y, mode });
      const N = pts.length;
      let s = 0;
      for (let i = 0; i < N; i++) {
        const a = pts[i], b = pts[i + 1];
        const dx = b ? b.x - a.x : NET_STEP * Math.cos(h), dy = b ? b.y - a.y : NET_STEP * Math.sin(h), L = Math.hypot(dx, dy);
        a.tx = dx / L; a.ty = dy / L; a.nx = -a.ty; a.ny = a.tx; a.len = L; a.s = s; s += L;
        a.w = width; a.bank = 0;
      }
      return { name, pts, N, length: s, width, jx: [] };
    });
    const junctions = NET_JUNCTIONS.map(([a, a0, a1, b, b0, b1, sense]) => ({ a, a0, a1, b, b0, b1, sense }));
    junctions.forEach((J, k) => { roads[J.a].jx.push(k); roads[J.b].jx.push(k); });
    const cities = NET_CITIES.map(([name, biome, cx, cy, road, i]) => ({ name, biome, cx, cy, road, i }));
    // Phase 3: the roads' heights (real now: the deck lock), their roles (a launch spur's end is a
    // lip; a catch deck reaches up for a jump; an on-ramp starts on the open ground), which ends are
    // open (no junction holds them: run off one and you're free), and a grid of sample runs per
    // NET_CELL square, so a free body finds what's under it
    const hk = new Map(NET_HEIGHTS.map(([r, keys]) => [r, keys]));
    roads.forEach((R, k) => { R.hk = hk.get(k) || null; R.role = ''; R.open0 = true; R.open1 = true; });
    NET_JUMPS.forEach(([l, c]) => { roads[l].role = 'launch'; roads[c].role = 'catch'; });
    NET_ONRAMPS.forEach(([, r]) => { roads[r].role = 'on'; });
    for (const J of junctions) {
      for (const [r, i0, i1] of [[J.a, J.a0, J.a1], [J.b, J.b0, J.b1]]) {
        if (i0 <= 0) roads[r].open0 = false;
        if (i1 >= roads[r].N - 1) roads[r].open1 = false;
      }
    }
    const cells = new Map();
    roads.forEach((R, r) => {
      let key = null, run = null;
      for (let i = 0; i < R.N; i++) {
        const k = netCell(R.pts[i].x, R.pts[i].y);
        if (k !== key) {
          key = k; run = [r, i, i];
          if (!cells.has(k)) cells.set(k, []);
          cells.get(k).push(run);
        } else run[2] = i;
      }
    });
    return { kind: 'network', course: false, N: 0, pts: [], branches: [], roads, junctions, cities, checkpoints: 1, pad: null,
      cells, jumps: NET_JUMPS, onramps: NET_ONRAMPS };
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
  // The Network's grid: a cell's key from a point (NET_CELL squares)
  const NET_CELL = 2048, NET_EDGE = 300;
  const netCell = (x, y) => Math.floor(x / NET_CELL) * 4096 + Math.floor(y / NET_CELL);
  // A road's height at (fractional) sample i: Hermite cubics between its keys [sample, m, slope]
  // (zero slopes: a smoothstep), 0 off them.
  function netHeight(T, r, i) {
    const K = T.roads[r].hk;
    if (!K) return 0;
    for (let k = 0; k < K.length - 1; k++) {
      const a = K[k], b = K[k + 1];
      if (i >= a[0] && i <= b[0]) {
        const n = Math.max(1, b[0] - a[0]), u = (i - a[0]) / n, d = n * NET_STEP, u2 = u * u, u3 = u2 * u;
        return (2 * u3 - 3 * u2 + 1) * a[1] + (u3 - 2 * u2 + u) * d * a[2] + (-2 * u3 + 3 * u2) * b[1] + (u3 - u2) * d * b[2];
      }
    }
    return 0;
  }
  // The Network's edges ramp up (Luke, 2026-10-20: "make the walls ramp up on the sides rather than a
  // hard stop? Let the craft drift a bit"): the outer EDGE_FRAC of each side (EDGE_MIN-EDGE_MAX m)
  // banks up toward the wall, EDGE_ANG at it, as u^1.5 across (a quarter-pipe: it builds as you drift
  // in). -> [its height there (m), its bank (rad)] at `lat` m off the centreline of a road `w` wide.
  const EDGE_FRAC = 0.15, EDGE_MIN = 30, EDGE_MAX = 60, EDGE_ANG = 18 * Math.PI / 180, EDGE_TAN = Math.tan(EDGE_ANG);
  function netEdge(w, lat) {
    const E = clamp(w * EDGE_FRAC, EDGE_MIN, EDGE_MAX), u = (Math.abs(lat) - (w / 2 - E)) / E;
    if (u <= 0) return [0, 0];
    const v = Math.min(u, 1);
    const r = Math.sqrt(v);   // (u^1.5: under u^2 a 3 deg drift at 2,500 mph still reached the wall)
    return [E * EDGE_TAN * v * v * r / 2.5, EDGE_ANG * v * r];
  }
  // ... and past its ends (a body off its last sample, the step before it's freed), on at the end's slope
  function roadH(T, r, f) {
    const N = T.roads[r].N;
    if (f > N - 1) return netHeight(T, r, N - 1) + (f - (N - 1)) * (netHeight(T, r, N - 1) - netHeight(T, r, N - 1.01)) / 0.01;
    if (f < 0) return netHeight(T, r, 0) + f * (netHeight(T, r, 0.01) - netHeight(T, r, 0)) / 0.01;
    return netHeight(T, r, f);
  }
  function nearestBranch(B, x, y, hint, win) {
    let best = null, bd = Infinity;
    for (let i = Math.max(0, hint - win), hi = Math.min(B.N - 1, hint + win); i <= hi; i++) {
      const a = B.pts[i], u = ((x - a.x) * a.tx + (y - a.y) * a.ty) / a.len, t = clamp(u, 0, 1);
      const px = a.x + a.tx * a.len * t, py = a.y + a.ty * a.len * t;
      const d = (x - px) ** 2 + (y - py) ** 2;
      if (d < bd) {
        bd = d;
        best = { i, lat: (x - a.x) * a.nx + (y - a.y) * a.ny, w: a.w, nx: a.nx, ny: a.ny, tx: a.tx, ty: a.ty, off: (i === 0 && u < 0) || (i === B.N - 1 && u > 1),
          over: i === B.N - 1 ? (u - 1) * a.len : i === 0 ? -u * a.len : -Infinity };   // past an end, how far (m; negative short of it)
      }
    }
    return best;
  }
  // How deep inside its road a point is (negative inside; Infinity off a branch's end).
  const depth = (n, r) => (n.off ? Infinity : Math.abs(n.lat) + r - n.w / 2);

  // path: the road a body's hint is on, 0 the main road, k + 1 branch k
  // offRoad (the Network): off the roads (off a lip, on the open ground): no walls, the hover over
  // the terrain; lock: just caught by a road, easing onto its surface
  function body(m, I) { return { m, I, x: 0, y: 0, vx: 0, vy: 0, th: 0, w: 0, fx: 0, fy: 0, t: 0, hint: 0, path: 0, contact: [false, false], z: 0, vz: 0, grip: 1, touch: new Set(), offRoad: false, lock: false }; }
  function applyAt(b, fx, fy, px, py) {
    b.fx += fx; b.fy += fy; b.t += (px - b.x) * fy - (py - b.y) * fx;
  }
  function pointVel(b, px, py) { return [b.vx - b.w * (py - b.y), b.vy + b.w * (px - b.x)]; }

  function makeSim(overrides) {
    // the grand prix is a STARFIGHTER track unless a handling is asked for
    const hname = (overrides && overrides.handling) || (COURSES[(overrides && overrides.track) || ''] ? 'starfighter' : DEFAULTS.handling);
    const P = Object.assign({}, DEFAULTS, HANDLING[hname] || {}, TRACKS[(overrides && overrides.track) || ''] || {}, overrides || {}, { handling: hname });
    const T = P.track === 'range' ? buildRange() : P.track === 'network' ? buildNetwork() : COURSES[P.track] ? buildCourse(P.track) : buildTrack();
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
      gate: T.branches.map(() => null), podPath: 0, job: null,
      // moving obstacles (the Network's traffic, driven outside the sim): [{id, x, y, vx, vy, r}], each
      // advanced along its velocity every step; a body's circles feel their forcefields
      obstacles: [],
      // the Network: the city you last reached (where a reset or a crash puts you), when you left it
      // (null until the first move), the cities found, the pod's [road, sample] a step ago
      net: T.kind === 'network' ? { from: P.startCity ?? 0, t0: null, found: new Set([P.startCity ?? 0]), prev: null } : null
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

    // Nearest centreline point on a path: 0 the main road, k + 1 branch k (on the Network: road path).
    function nearestOn(path, x, y, hint, win) {
      if (T.kind === 'network') return nearestBranch(T.roads[path], x, y, hint, win);
      return path === 0 ? nearest(T, x, y, hint, win) : nearestBranch(T.branches[path - 1], x, y, hint, win);
    }
    // The Network's other roads at a body's junctions, as [[path, hint there], ...]: every junction
    // whose zone on the body's road holds its hint, mapped linearly onto the other road's zone.
    function netAlts(b) {
      const out = [];
      for (const k of T.roads[b.path].jx) {
        const J = T.junctions[k];
        let f0, f1, t0, t1, q;
        if (J.a === b.path && b.hint >= J.a0 && b.hint <= J.a1) { f0 = J.a0; f1 = J.a1; t0 = J.b0; t1 = J.b1; q = J.b; }
        else if (J.b === b.path && b.hint >= J.b0 && b.hint <= J.b1) { f0 = J.b0; f1 = J.b1; t0 = J.a0; t1 = J.a1; q = J.a; }
        else continue;
        const u = f1 > f0 ? (b.hint - f0) / (f1 - f0) : 0;
        out.push([q, Math.round(J.sense > 0 ? t0 + u * (t1 - t0) : t1 - u * (t1 - t0))]);
      }
      return out;
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
      // The Network: at a city's terminal (the last city reached unless ci names one), facing up its road
      if (T.kind === 'network') {
        const c = T.cities[(ci ?? -1) >= 0 ? ci : S.net.from];
        respawnOn(c.road, c.i, 1);
        return;
      }
      // Circuit: back at a checkpoint. Range: 30 m behind where the pod is, facing +x.
      let a, idx = 0;
      if (T.kind === 'range') {
        a = { x: Math.max(0, S.pod.x - 30), y: S.pod.y, tx: 1, ty: 0, nx: 0, ny: 1 };
      } else {
        idx = atIdx !== undefined && atIdx >= 0 ? atIdx % T.N : Math.round(((ci ?? -1) < 0 ? S.checkpoint : ci) * T.N / T.checkpoints) % T.N;
        a = T.pts[idx];
      }
      place(a, idx, 0);
    }
    // The Network: on road `road` at sample i, facing up it (dir 1) or down it (-1).
    function respawnOn(road, i, dir) {
      const p = T.roads[road].pts[i], d = dir < 0 ? -1 : 1;
      place({ x: p.x, y: p.y, tx: p.tx * d, ty: p.ty * d, nx: p.nx * d, ny: p.ny * d }, i, road);
      if (S.net) { S.net.t0 = null; S.net.prev = null; }
    }
    function place(a, idx, path) {
      // engines placed so each cable is exactly at length: a stretched spawn makes the stiff
      // cables yank the pod forward on the first step
      const lat = P.engineGap / 2 - P.podAnchorW * P.podWidth / 2;
      const ahead = Math.sqrt(P.cableLen * P.cableLen - lat * lat) + P.podLen / 2 + P.engineLen / 2;
      const th = Math.atan2(a.ty, a.tx);
      for (const [b, side] of [[S.eL, 1], [S.eR, -1], [S.pod, 0]]) {
        const fwd = side === 0 ? 0 : ahead;
        b.x = a.x + a.tx * fwd + a.nx * side * P.engineGap / 2;
        b.y = a.y + a.ty * fwd + a.ny * side * P.engineGap / 2;
        b.vx = b.vy = b.w = 0; b.th = th; b.hint = idx; b.path = path; b.contact = [false, false];
        b.z = (T.kind === 'network' ? netHeight(T, path, idx) : ground(T, b.x, b.y)) + P.rideH; b.vz = 0; b.grip = 1;
        b.offRoad = false; b.lock = false;
      }
      for (const e of [S.eL, S.eR]) { e.heat = P.limits ? Math.min(e.heat ?? 0.3, 0.5) : 0; e.flameout = false; e.health = e.health ?? 1; e.sputter = 1; e.sputterT = 0; }
      S.pod.health = S.pod.health > 0 ? S.pod.health : 1;
      S.binderBroken = false; S.towU = -1; S.crashT = 0; S.progressI = idx;
      S.gate = T.branches.map(() => null); S.podPath = 0; S.onGround = false;
    }

    // At a junction the two roads are one (a union): a body takes the road it's deeper inside,
    // when it's off its own or the other is 10 m deeper, and a wall is wherever it's off both.
    // How deep nearest point n on road `path` puts a circle of radius r into a wall. On the Network a
    // closed road end (a junction holds it: a highway's dead end inside its turnaround's zone) is a
    // wall across the road, as deep as the circle is past the end plus r; an open end has none
    // (Infinity: past it you're off the roads). Treating a closed end as Infinity too (no road here)
    // made the junction's other road win however far off it was: past a highway's end, its
    // turnaround's centreline is ~300 m to the side, 210 m of "wall" and a 1.3e9 N kick in one step,
    // the binder torn (Luke's speeds jumping to 10,000-63,000 km/h at mile ~0 and ~346).
    function netDepth(path, n, r) {
      const R = T.roads[path], side = Math.abs(n.lat) + r - n.w / 2;
      if (!((n.i === R.N - 1 && !R.open1) || (n.i === 0 && !R.open0))) return n.off ? Infinity : side;
      return Math.max(side, n.over + r);
    }
    // ... and whether that wall is the end's (1 the far end, -1 the first; 0 the sides)
    function endCap(path, n, r) {
      const R = T.roads[path];
      if (!((n.i === R.N - 1 && !R.open1) || (n.i === 0 && !R.open0)) || !(n.over + r > Math.abs(n.lat) + r - n.w / 2)) return 0;
      return n.i === R.N - 1 ? 1 : -1;
    }
    function collideWalls(b, circles, dt) {
      // (the Network searches 16 samples, not 40: a body moves under a sample a step, and the
      // junctions' linear maps are within 10 samples of the true nearest: the search is ~60% of a step)
      const W = T.kind === 'network' ? 16 : 40;
      const deep = T.kind === 'network' ? netDepth : (path, n, r) => depth(n, r);
      const near = nearestOn(b.path, b.x, b.y, b.hint, W);
      b.hint = near.i;
      // the other roads here: one at most off a course's main road, any number on the Network (the
      // body takes the deepest, under the same rule)
      let alts = [];
      if (T.kind === 'network') alts = netAlts(b);
      else if (T.branches.length) { const a1 = junctionAlt(b); if (a1) alts = [a1]; }
      const others = [];
      if (alts.length) {
        const ms = alts.map((a) => nearestOn(a[0], b.x, b.y, a[1], W)), dOwn = deep(b.path, near, 0);
        let bi = 0;
        for (let k = 1; k < ms.length; k++) if (deep(alts[k][0], ms[k], 0) < deep(alts[bi][0], ms[bi], 0)) bi = k;
        const dAlt = deep(alts[bi][0], ms[bi], 0);
        if (dAlt < dOwn && (dOwn > 0 || dAlt < dOwn - 10)) {
          others.push([b.path, near.i]);
          b.path = alts[bi][0]; b.hint = ms[bi].i;
          ms.forEach((m, k) => { if (k !== bi) others.push([alts[k][0], m.i]); });
        } else ms.forEach((m, k) => others.push([alts[k][0], m.i]));
      }
      if (T.kind === 'network') {   // off an open end: free (a lip, a highway's end)
        const R = T.roads[b.path], n = nearestOn(b.path, b.x, b.y, b.hint, 2);
        if (n.off && ((n.i === 0 && R.open0) || (n.i === R.N - 1 && R.open1))) { goFree(b, n); return; }
      }
      circles.forEach(([cx, cy, r], ci) => {
        let p = b.path, n = nearestOn(b.path, cx, cy, b.hint, 12), pen = deep(b.path, n, r);
        for (const [op, oh] of others) {
          const m = nearestOn(op, cx, cy, oh, 12), pm = deep(op, m, r);
          if (pm < pen) { n = m; pen = pm; p = op; }
        }
        if (pen <= 0 || pen === Infinity) { b.contact[ci] = false; return; }   // (Infinity: past an open end, no wall)
        const cap = T.kind === 'network' ? endCap(p, n, r) : 0;   // a closed end pushes back along the road
        const sgn = n.lat > 0 ? -1 : 1, nx = cap !== 0 ? -cap * n.tx : n.nx * sgn, ny = cap !== 0 ? -cap * n.ty : n.ny * sgn;
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

    // Traffic's forcefields: a body's circle inside an obstacle is pushed straight out (a spring and
    // a damper on the closing speed, no friction, no damage); touching one starts a 'bump' (once per
    // contact); closing faster than smashV is the catastrophic hit: a 'smash' and a crash.
    function collideObstacles(b, circles) {
      const inside = new Set();
      for (const o of S.obstacles) {
        for (const [cx, cy, r] of circles) {
          const dx = cx - o.x, dy = cy - o.y, d = Math.hypot(dx, dy), pen = r + o.r - d;
          if (pen <= 0 || d < 1e-6) continue;
          const nx = dx / d, ny = dy / d;
          const [vx, vy] = pointVel(b, cx, cy), vn = (vx - o.vx) * nx + (vy - o.vy) * ny;
          if (!b.touch.has(o.id) && !inside.has(o.id)) {
            if (-vn > P.smashV && S.crashT <= 0) { S.events.push({ type: 'smash', id: o.id, v: -vn }); S.crashT = 1.6; }
            else S.events.push({ type: 'bump', who: b === S.pod ? 'pod' : b === S.eL ? 'L' : 'R', id: o.id, v: Math.max(0, -vn) });
          }
          inside.add(o.id);
          const fn = P.fieldK * pen - (vn < 0 ? P.fieldC * vn : 0);
          applyAt(b, fn * nx, fn * ny, cx, cy);
        }
      }
      b.touch = inside;
    }

    // Repulsor hover: spring-damper toward ride height over the ground, push-only, plus
    // gravity. Exactly balanced at ride height on flat ground, so flat tracks are unchanged.
    // Grip fades as a body lifts clear (0.5 to 2 m above ride height) and returns on landing.
    function hover(b, dt, az) {
      if (T.kind === 'network' && !b.offRoad) { railHover(b, dt); return; }
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

    // The Network's deck lock: a body on a road rides its surface (the road's forcefield holds it
    // down as well as up: at 4,000 mph any crest tighter than 326 km would throw you off). Just
    // caught (lock), it eases on: a critically damped spring, capped at LOCK_A.
    const LOCK_W = 4, LOCK_A = 20 * G;   // (a deck's pull-out at 4,300 mph is ~10 g: the catch has to follow it)
    function roadF(b) {
      const a = T.roads[b.path].pts[b.hint];
      return b.hint + clamp(((b.x - a.x) * a.tx + (b.y - a.y) * a.ty) / a.len, -1, 2);
    }
    function railHover(b, dt) {
      const a = T.roads[b.path].pts[b.hint], f = roadF(b);
      const lat = (b.x - a.x) * a.nx + (b.y - a.y) * a.ny, vl = b.vx * a.nx + b.vy * a.ny;
      const h = roadH(T, b.path, f) + netEdge(a.w, lat)[0], vs = b.vx * a.tx + b.vy * a.ty;
      const dhdt = (roadH(T, b.path, f + vs * dt / a.len) + netEdge(a.w, lat + vl * dt)[0] - h) / dt;
      if (b.lock) {
        const acc = clamp(LOCK_W * LOCK_W * (h + P.rideH - b.z) - 2 * LOCK_W * (b.vz - dhdt), -LOCK_A, LOCK_A);
        b.vz += acc * dt; b.z += b.vz * dt;
        if (Math.abs(b.z - h - P.rideH) < 0.05 && Math.abs(b.vz - dhdt) < 0.5) b.lock = false;
        b.grip = clamp(1 - (b.z - h - P.rideH - 0.5) / 1.5, 0, 1);
        return;
      }
      b.z = h + P.rideH; b.vz = dhdt; b.grip = 1;
    }
    // Off the roads: off an open end (a launch spur's lip, a highway's end) or never on one.
    function goFree(b, n) {
      b.offRoad = true; b.lock = false; b.contact = [false, false];
      if (b === S.pod) S.events.push({ type: 'airborne', road: b.path, lip: T.roads[b.path].role === 'launch', v: Math.sqrt(b.vx * b.vx + b.vy * b.vy), vz: b.vz });
    }
    // The roads near (x, y), from the grid: per run in its cell (and the next cells if it's within
    // NET_EDGE of an edge), the nearest point (every 8th sample, then the 8 either side).
    function netNear(x, y) {
      const out = [], cx = Math.floor(x / NET_CELL), cy = Math.floor(y / NET_CELL);
      const fx = x - cx * NET_CELL, fy = y - cy * NET_CELL;
      for (let dx = -1; dx <= 1; dx++) {
        if ((dx < 0 && fx > NET_EDGE) || (dx > 0 && fx < NET_CELL - NET_EDGE)) continue;
        for (let dy = -1; dy <= 1; dy++) {
          if ((dy < 0 && fy > NET_EDGE) || (dy > 0 && fy < NET_CELL - NET_EDGE)) continue;
          const runs = T.cells.get((cx + dx) * 4096 + (cy + dy));
          if (!runs) continue;
          for (const [r, i0, i1] of runs) {
            const R = T.roads[r];
            let bi = i0, bd = Infinity;
            for (let i = i0; i <= i1; i += 8) {
              const p = R.pts[i], d = (x - p.x) ** 2 + (y - p.y) ** 2;
              if (d < bd) { bd = d; bi = i; }
            }
            out.push(nearestBranch(R, x, y, bi, 8));
            out[out.length - 1].r = r;
          }
        }
      }
      return out;
    }
    // A free body: caught by a road it touches down inside (a catch deck reaches JC_REACH up for a
    // jump; slower, under its lip, the deck turns it down), else held off the roads' walls from
    // outside near the ground.
    const JC_REACH = 40;
    function freeContact(b, circles, dt) {
      const ns = netNear(b.x, b.y);
      for (const n of ns) {
        const R = T.roads[n.r];
        if (n.off || Math.abs(n.lat) > n.w / 2 - 2) continue;
        const a = R.pts[n.i], u = clamp(((b.x - a.x) * a.tx + (b.y - a.y) * a.ty) / a.len, -1, 2);
        const h = roadH(T, n.r, n.i + u) + netEdge(n.w, n.lat)[0], dz = b.z - h - P.rideH;
        if (dz >= -3 && dz <= (R.role === 'catch' ? JC_REACH : 2.5)) {
          const vs = b.vx * a.tx + b.vy * a.ty, dhdt = (roadH(T, n.r, n.i + u + vs * dt / a.len) - h) / dt;
          b.offRoad = false; b.path = n.r; b.hint = n.i; b.contact = [false, false];
          b.lock = Math.abs(dz) > 0.05 || Math.abs(b.vz - dhdt) > 0.5;
          if (b === S.pod) {
            S.events.push({ type: R.role === 'catch' ? 'catch' : 'onroad', road: n.r, v: Math.abs(b.vz - dhdt), dz });
            S.onGround = false;
          }
          return;
        }
        if (R.role === 'catch' && dz < -3 && dz > -80) {   // under the deck's lip: turned down
          const vs = b.vx * a.tx + b.vy * a.ty, dhdt = (roadH(T, n.r, n.i + u + vs * dt / a.len) - h) / dt;
          if (dz > -8) b.z = h + P.rideH - 8;
          if (b.vz > dhdt - 2) b.vz = dhdt - 2;
        }
      }
      // walls from outside, near the ground
      for (const n of ns) {
        if (n.off) continue;
        const R = T.roads[n.r], h = netHeight(T, n.r, n.i) + netEdge(n.w, n.w / 2)[0];   // (at the wall's foot: the ramp's top)
        if (Math.abs(b.z - h - P.rideH) > 25) continue;
        circles.forEach(([cx, cy, r]) => {
          const m = nearestBranch(R, cx, cy, n.i, 4), al = Math.abs(m.lat), pen = m.w / 2 + r - al;
          if (m.off || al < m.w / 2 - 2 || pen <= 0) return;
          const sgn = m.lat > 0 ? 1 : -1, nx = m.nx * sgn, ny = m.ny * sgn;   // outward
          const [vx, vy] = pointVel(b, cx, cy), vn = vx * nx + vy * ny;
          const fn = P.wallK * pen - (vn < 0 ? P.wallC * vn : 0);
          const tx = -ny, ty = nx, vt = vx * tx + vy * ty;
          const ft = -Math.sign(vt) * Math.min(P.wallMu * fn, Math.abs(vt) * b.m / dt);
          applyAt(b, fn * nx + ft * tx, fn * ny + ft * ty, cx, cy);
        });
      }
      if (b === S.pod && !S.onGround && b.z - P.rideH < 1) { S.onGround = true; S.events.push({ type: 'ground' }); }
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
      for (const o of S.obstacles) { o.x += o.vx * dt; o.y += o.vy * dt; }
      if (S.crashT > 0) {
        S.crashT -= dt;
        if (S.crashT <= 0) {
          if (S.finished) { S.pod.x = 30; S.pod.y = 0; S.finished = false; S.result = null; }   // back to the start line
          respawn();
        }
        return;
      }
      if (inp.handling === 'speed' || inp.handling === 'starfighter') S.hwant = inp.handling;
      if (S.pod.path > 0 && T.kind !== 'network') S.hwant = 'starfighter';   // a shade line is a STARFIGHTER line (its corkscrews are paced for it)
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
      // The burner: an explicit inp.burner (the headset's trigger throttles light it from the left
      // stick, so the levers stay under the gate and still throttle and steer on it), else both
      // levers past the gate (the keyboard, a gamepad, the replays)
      const inGate = (inp.burner ?? (inp.thrL >= P.gate && inp.thrR >= P.gate)) && !inp.repair;
      const ramjet = S.armed && inGate;
      const burner = !ramjet && inGate && S.battery > 0;
      S.mode = ramjet ? 'ramjet' : burner ? 'burner' : 'normal';
      if (burner && P.limits) S.battery = Math.max(0, S.battery - P.batteryDrain * dt);
      else if (!inGate) S.battery = Math.min(1, S.battery + P.batteryCharge * dt);
      const speed = Math.hypot(Pd.vx, Pd.vy);

      const gm = inp.thrMul ?? 1;   // the gearbox's pull (its ratio, at its revs; 1 without one)
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
        e.fx += thrust * P.forceScale * gm * c; e.fy += thrust * P.forceScale * gm * s;
        // Air brake = quadratic drag plus a linear term, so the flaps still bite at low speed.
        // A constant term keeps the brakes biting across a 100x speed range (smoothed below 2 m/s).
        const v = Math.hypot(e.vx, e.vy);
        e.front = P.frontBrakeCd > 0 ? brk * smooth01((v - P.frontBrakeV0) / (P.frontBrakeV1 - P.frontBrakeV0)) : 0;
        const cd = (P.engineCd + P.brakeCd * brk + P.frontBrakeCd * e.front) * P.forceScale;
        const bl = (P.brakeLin * brk + P.brakeConst * brk / Math.max(v, 2)) * P.forceScale;
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
      const pv = Math.hypot(Pd.vx, Pd.vy), pcd = (P.podCd + 0.5 * P.brakeCd * pb) * P.forceScale;
      const pbl = 0.5 * (P.brakeLin * pb + P.brakeConst * pb / Math.max(pv, 2)) * P.forceScale;
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
      // The Network's edges: their ramp pushes you back toward the middle as the GP's banking does
      // toward a corner's (gravity's g tan bank, downforce's bankDown v^2 sin bank)
      if (T.kind === 'network') {
        for (const b of S.bodies) {
          if (b.offRoad) continue;
          const a = T.roads[b.path].pts[b.hint], lat = (b.x - a.x) * a.nx + (b.y - a.y) * a.ny, bk = netEdge(a.w, lat)[1];
          if (bk === 0) continue;
          const v2 = b.vx * b.vx + b.vy * b.vy;
          const f = P.bank * b.m * (G * Math.tan(bk) + P.bankDown * v2 * Math.sin(bk)) * b.grip * (lat > 0 ? -1 : 1);
          b.fx += f * a.nx; b.fy += f * a.ny;
        }
      }
      const cL = engineCircles(L), cR = engineCircles(R), cP = [[Pd.x, Pd.y, 1.6]];
      if (T.branches.length) updateGates();
      if (T.kind === 'network') {
        for (const [b, c] of [[L, cL], [R, cR], [Pd, cP]]) { if (b.offRoad) freeContact(b, c, dt); else collideWalls(b, c, dt); }
      } else if (T.kind === 'circuit') { collideWalls(L, cL, dt); collideWalls(R, cR, dt); collideWalls(Pd, cP, dt); }
      if (S.obstacles.length) { collideObstacles(L, cL); collideObstacles(R, cR); collideObstacles(Pd, cP); }
      bodyPush(L, cL, Pd, cP); bodyPush(R, cR, Pd, cP); bodyPush(L, cL, R, cR);

      for (const b of S.bodies) {
        // in the air (the Network, off the roads), the forces along its path act along it: thrust
        // minus drag scales its climb as it scales its speed, so only gravity bends the line (let
        // off at 4,000 mph and the 16 g of drag would otherwise steepen it)
        if (T.kind === 'network' && b.offRoad) {
          const vh = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
          if (vh > 50) b.vz += (b.fx * b.vx + b.fy * b.vy) / (b.m * vh) * (b.vz / vh) * dt;
        }
        b.vx += b.fx / b.m * dt; b.vy += b.fy / b.m * dt; b.w += b.t / b.I * dt;
        b.w *= 1 - 0.5 * dt;
        b.x += b.vx * dt; b.y += b.vy * dt; b.th += b.w * dt;
      }
      if (Pd.health <= 0 && S.crashT <= 0) { S.events.push({ type: 'wreck' }); S.crashT = 1.6; Pd.health = 0; }
      if (T.kind === 'network') { netStep(inp); return; }

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

    // The Network's clock: it starts on the first move; crossing a city's terminal (its sample on its
    // road, either way) is arriving there: from another city, an 'arrive' with the time since leaving
    // it; then the clock runs from this city.
    function netStep(inp) {
      const Nt = S.net, Pd = S.pod, cur = [Pd.path, Pd.hint];
      if (Nt.t0 === null) {
        if (inp.thrL + inp.thrR <= 0.02) { Nt.prev = cur; return; }
        Nt.t0 = S.time;
      }
      if (Pd.offRoad) { Nt.prev = null; return; }   // off the roads: no terminals crossed
      if (Nt.prev && Nt.prev[0] === cur[0]) {
        for (let k = 0; k < T.cities.length; k++) {
          const c = T.cities[k];
          if (c.road !== cur[0] || (Nt.prev[1] >= c.i) === (cur[1] >= c.i)) continue;
          if (k !== Nt.from) {
            S.events.push({ type: 'arrive', city: k, from: Nt.from, t: S.time - Nt.t0 });
            Nt.found.add(k);
          }
          Nt.from = k; Nt.t0 = S.time;
        }
      }
      Nt.prev = cur;
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
      else if (T.kind === 'network') respawn();
      else { S.lap = 0; S.lapStart = null; S.visited = new Set([0]); S.checkpoint = 0; respawn(0); }
      if (S.job) S.job = newJob();   // the job starts over (its clock on the next first move)
    }

    S.pod.x = P.startX + 30; S.pod.y = P.startY;   // range spawn point (respawn backs off 30 m)
    respawn(T.kind === 'network' ? -1 : 0);   // the Network: at the start city
    S.visited.add(0);
    return { S, P, T, step, respawn, respawnOn, restart, nearestOn, tLit, DEFAULTS, ground: (x, y) => ground(T, x, y),
      netHeight: (r, i) => netHeight(T, r, i), netNear, netEdge,
      box: { x: BOX_X, half: BOX_HALF, overrun: OVERRUN } };
  }

  window.PhaethonSim = { makeSim, DEFAULTS, HANDLING, TRACKS, COURSES, xorshift32 };
})();
