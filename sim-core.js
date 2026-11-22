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
    // High-speed flaps brake against full thrust; force is bounded per deployed flap so
    // unlimited speed cannot turn braking into an instantaneous impulse.
    frontBrakeCd: 1.0, frontBrakeV0: 558.8, frontBrakeV1: 782.32, frontBrakeMaxG: 90,
    brakeTurnG: 45,   // additional lateral repulsor authority while the high-speed flaps are deployed
    engineGrip: 30, podGrip: 10, gripCapG: 15, podCapG: 8, finOffset: 0.2, finK: 8,
    yawDamp: 150000, podYawDamp: 50000, podAlignK: 1e6, towK: 1e6, towC: 40000,
    cableLen: 16, cableK: 600000, cableC: 30000, cableCouple: 0.2, podAnchorW: 0.15,
    binderK: 3e6, binderC: 70000, alignK: 2e7, alignC: 6e5, binderBreak: 3.0,
    wallK: 6e6, wallC: 1.5e5, wallMu: 0.35, wallDmgMin: 6,   // impacts below wallDmgMin m/s (into the wall) do no damage
    // traffic's forcefields (the Network): a softer push than a wall's, no friction, no damage; a
    // closing speed over smashV (m/s, ~1,500 mph) is the catastrophic hit
    fieldK: 2e6, fieldC: 8e4, smashV: 670,
    damage: false,   // wall hits cost health (and can wreck you) only when this is on
    obstacleCollisions: true, // pillars/traffic only; the release menu defaults this to off
    towLongK: 2e6, towLongC: 8e4, towLongSlack: 0.3,   // pod stand-off: never closer to the engines than its taut-cable spot
    bank: 1, bankDown: 3.9e-4,   // banked corners: downforce per (m/s)^2, as g, presses you into the bank (~8 g at 1,000 mph)
    towAudit: true, towAuditG: 3,   // tow-bar energy audit: drag on the speed, never harder than this (g) ...
    towIntF0: 0.05, towIntF1: 0.3, towIntMax: 60,   // ... shifting onto the swing and spin as their share of the energy grows
    heatThrottle: 0.15, heatBurner: 0.12, heatRamjet: 0.35, coolBase: 0.05, coolSpeed: 0.10,
    batteryDrain: 0.08, batteryCharge: 0.05, repairRate: 0.12, damagePerMs: 0.012,
    limits: false,   // battery and heat: off (Luke, 2026-10-18: "turn off battery and heat, let it be crazy"): the burner never runs dry, engines never heat up
    // the boost (inp.boost: the ramjet ARM button held; inp.surge: a power-up's gift): thrust times
    // boostMult a stage, on top of whatever is lit (1.3: the step the ramjet is over the burner,
    // 1.9 / 1.45). With `limits` on the held one drains the battery at boostDrain a second (five
    // seconds from full) and each stage heats the engines by boostHeat a second. Mirrors craft_sim.gd.
    boostMult: 1.3, boostDrain: 0.2, boostHeat: 0.1,
    // The avoidance field (inp.avoid: the OPTIONS page's AVOIDANCE FIELD; Luke, 2026-11-22: "Add a collision
    // avoidance force field"). Off unless asked for: the replays never ask, and nothing of it runs for them.
    //   the wall's cushion  a body within avoidD m of a wall (and never more than avoidShare of the road's width:
    //                       a 140 m circuit is not all cushion) and CLOSING on it (faster than avoidMinV) asks for
    //                       what would stop it avoidGap m short, v^2 / 2d, times avoidGain. Under avoidMinA it
    //                       is not worth the name and nothing is done; over avoidMaxA it is all the field has.
    //                       It answers closing speed and nothing else: a craft flown along a wall feels nothing.
    //   the view's demand   inp.avoidPush [ax, ay] m/s^2: what misses the traffic and the pillars ahead, worked
    //                       out once a frame in the view (view/avoidance_field.gd); the same cap.
    // What it does with the demand: the part across the craft's path TURNS the craft, as one, about its pod
    // (path, headings and all, at a / v up to avoidMaxW rad/s): a sideways shove alone is undone by the craft's
    // own grip, which holds its path to its heading, and it flew into the wall under 30 g of shove. The part
    // along its path is a plain force on every body by its mass (it slows the craft into a wall it meets square).
    // With `limits` on it spends the battery, avoidDrain a second at full strength, and stops when it is flat.
    avoidD: 120, avoidGap: 1.5, avoidGain: 1.3, avoidMaxA: 300, avoidMinA: 50, avoidMinV: 1.5, avoidMaxW: 2, avoidMinSpeed: 20, avoidDrain: 0.5, avoidShare: 0.3,
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
  // grip, damped yaw and progressive200-500mph air brakes suit the narrow courses;
  // a stiffer tow bar keeps the pod tracking the engines.
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
      // Bounded brake/turn response at200-500mph, with damped grip reversals.
      frontBrakeCd: 4.5, frontBrakeV0: 89.408, frontBrakeV1: 223.52, frontBrakeMaxG: 24, brakeTurnG: 15,
      gripCapG: 50, engineGrip: 90, podGrip: 30, podCapG: 30, finK: 3, yawDamp: 150000,
      podAlignK: 1.2e7, podYawDamp: 250000, towK: 5e6, towC: 200000
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
    ['E2', 25000.0, 300000.0, 0.0, 400.0, [['S', 550000.0, 0.0, 'sp']]],
    ['E3', 25000.0, 500000.0, 0.0, 400.0, [['S', 550000.0, 0.0, 'sp']]],
    ['N1', 100000.0, 25000.0, 90.0, 400.0, [['S', 120000.0, 0.0, 'sp'], ['L', 45000.0, 17.0, 'sp'], ['S', 29997.285275513706, 0.0, 'sp'], ['R', 45000.0, 34.0, 'sp'], ['S', 29997.285275513706, 0.0, 'sp'], ['L', 45000.0, 17.0, 'sp'], ['S', 90000.0, 0.0, 'sp'], ['R', 45000.0, 19.0, 'sp'], ['S', 27179.652269197013, 0.0, 'sp'], ['L', 45000.0, 38.0, 'sp'], ['S', 27179.652269197013, 0.0, 'sp'], ['R', 45000.0, 19.0, 'sp'], ['S', 120000.0, 0.0, 'sp']]],
    ['N2', 300000.0, 25000.0, 90.0, 400.0, [['S', 550000.0, 0.0, 'sp']]],
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
    ['TE1-', 26600.0, 100100.0, -180.0, 200.0, [['S', 6696.0, 0.0, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['L', 4800.0, 298.6168246301553, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['S', 6696.0, 0.0, 'sp']]],
    ['TE1+', 573400.0000000542, 99900.00000000012, 3.8246170044598787e-13, 200.0, [['S', 12696.0, 0.0, 'sp'], ['R', 4200.0, 59.209211533606876, 'sp'], ['L', 4200.0, 298.4184230672138, 'sp'], ['R', 4200.0, 59.209211533606876, 'sp'], ['S', 12696.0, 0.0, 'sp']]],
    ['TE2-', 26600.0, 300100.0, -180.0, 200.0, [['S', 7896.0, 0.0, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp'], ['S', 7896.0, 0.0, 'sp']]],
    ['TE2+', 573400.0000000258, 299900.0, 0.0, 200.0, [['S', 13896.0, 0.0, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['L', 4800.0, 298.6168246301553, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['S', 13896.0, 0.0, 'sp']]],
    ['TE3-', 26600.0, 500100.0, -180.0, 200.0, [['S', 9096.0, 0.0, 'sp'], ['R', 3600.0, 59.07678434464472, 'sp'], ['L', 3600.0, 298.15356868928944, 'sp'], ['R', 3600.0, 59.07678434464472, 'sp'], ['S', 9096.0, 0.0, 'sp']]],
    ['TE3+', 573400.0000000258, 499900.0, 0.0, 200.0, [['S', 10296.0, 0.0, 'sp'], ['R', 5400.0, 59.38549803817441, 'sp'], ['L', 5400.0, 298.7709960763488, 'sp'], ['R', 5400.0, 59.38549803817441, 'sp'], ['S', 10296.0, 0.0, 'sp']]],
    ['TN1-', 99900.0, 26600.0, -90.0, 200.0, [['S', 7512.0, 0.0, 'sp'], ['R', 5400.0, 59.38549803817441, 'sp'], ['L', 5400.0, 298.7709960763488, 'sp'], ['R', 5400.0, 59.38549803817441, 'sp'], ['S', 7512.0, 0.0, 'sp']]],
    ['TN1+', 100099.99999999856, 573399.9999999264, 90.0000000000011, 200.0, [['S', 15096.0, 0.0, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['L', 4800.0, 298.6168246301553, 'sp'], ['R', 4800.0, 59.30841231507766, 'sp'], ['S', 15096.0, 0.0, 'sp']]],
    ['TN2-', 299900.0, 26600.0, -90.0, 200.0, [['S', 9912.0, 0.0, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp'], ['L', 6000.0, 298.89424490328594, 'sp'], ['R', 6000.0, 59.447122451642976, 'sp'], ['S', 9912.0, 0.0, 'sp']]],
    ['TN2+', 300100.0, 573400.0000000258, 90.0, 200.0, [['S', 11496.0, 0.0, 'sp'], ['R', 4200.0, 59.209211533606876, 'sp'], ['L', 4200.0, 298.4184230672138, 'sp'], ['R', 4200.0, 59.209211533606876, 'sp'], ['S', 11496.0, 0.0, 'sp']]],
    ['TN3-', 499900.0, 26600.0, -90.0, 200.0, [['S', 8304.0, 0.0, 'sp'], ['R', 6600.0, 59.49751333740145, 'sp'], ['L', 6600.0, 298.9950266748029, 'sp'], ['R', 6600.0, 59.49751333740145, 'sp'], ['S', 8304.0, 0.0, 'sp']]],
    ['TN3+', 500099.9999999891, 573400.0000000342, 90.00000000000406, 200.0, [['S', 13296.0, 0.0, 'sp'], ['R', 5100.0, 59.34923005987139, 'sp'], ['L', 5100.0, 298.6984601197428, 'sp'], ['R', 5100.0, 59.34923005987139, 'sp'], ['S', 13296.0, 0.0, 'sp']]],
    ['J0', 288841.50914873416, 299863.00800479756, -4.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K0', 300208.77782209043, 298968.3845582778, -4.5, 400.0, [['S', 6000.0, 0.0, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['S', 3637.235599608144, 0.0, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['S', 3637.235599608144, 0.0, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['S', 3637.235599608144, 0.0, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['S', 3637.235599608144, 0.0, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['S', 3637.235599608144, 0.0, 'sp'], ['L', 25000.0, 2.6960403553172143, 'sp'], ['R', 25000.0, 14.731934798697633, 'sp'], ['S', 57054.870366237556, 0.0, 'sp'], ['L', 25000.0, 10.666836996744083, 'sp'], ['R', 25000.0, 1.9521008882930349, 'sp'], ['S', 2654.20231584812, 0.0, 'sp'], ['R', 25000.0, 1.9521008882930349, 'sp'], ['L', 25000.0, 10.666836996744083, 'sp'], ['L', 25000.0, 10.666836996744083, 'sp'], ['R', 25000.0, 1.9521008882930349, 'sp'], ['S', 2654.20231584812, 0.0, 'sp'], ['R', 25000.0, 1.9521008882930349, 'sp'], ['L', 25000.0, 10.666836996744083, 'sp'], ['L', 45000.0, 8.54907883052161, 'sp'], ['R', 45000.0, 8.54907883052161, 'sp'], ['S', 2000.0, 0.0, 'sp']]],
    ['J1', 311158.49085126584, 300136.99199520244, -184.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K1', 298320.53234278644, 301147.361241956, -184.5, 400.0, [['S', 6000.0, 0.0, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['S', 4550.089352477588, 0.0, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['S', 4550.089352477588, 0.0, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['S', 4550.089352477588, 0.0, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['S', 4550.089352477588, 0.0, 'sp'], ['L', 25000.0, 3.4060031356338167, 'sp'], ['R', 25000.0, 18.61137427685621, 'sp'], ['S', 55797.716973672505, 0.0, 'sp'], ['L', 25000.0, 11.05974855371241, 'sp'], ['R', 25000.0, 2.024006271267631, 'sp'], ['S', 2750.2003057610295, 0.0, 'sp'], ['R', 25000.0, 2.024006271267631, 'sp'], ['L', 25000.0, 11.05974855371241, 'sp'], ['L', 25000.0, 11.05974855371241, 'sp'], ['R', 25000.0, 2.024006271267631, 'sp'], ['S', 2750.2003057610295, 0.0, 'sp'], ['R', 25000.0, 2.024006271267631, 'sp'], ['L', 25000.0, 11.05974855371241, 'sp'], ['L', 45000.0, 8.54907883052161, 'sp'], ['R', 45000.0, 8.54907883052161, 'sp'], ['S', 2000.0, 0.0, 'sp']]],
    ['J2', 300136.99199520244, 288841.50914873416, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K2', 301094.749514577, 301010.97227761213, 85.5, 400.0, [['S', 6000.0, 0.0, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['S', 3063.549504884912, 0.0, 'sp'], ['L', 25000.0, 2.259747831063125, 'sp'], ['R', 25000.0, 12.34790779116636, 'sp'], ['S', 56367.83983613081, 0.0, 'sp'], ['L', 25000.0, 10.88072337349908, 'sp'], ['R', 25000.0, 1.9912434931893743, 'sp'], ['S', 2706.4833945110367, 0.0, 'sp'], ['R', 25000.0, 1.9912434931893743, 'sp'], ['L', 25000.0, 10.88072337349908, 'sp'], ['L', 25000.0, 10.88072337349908, 'sp'], ['R', 25000.0, 1.9912434931893743, 'sp'], ['S', 2706.4833945110367, 0.0, 'sp'], ['R', 25000.0, 1.9912434931893743, 'sp'], ['L', 25000.0, 10.88072337349908, 'sp'], ['L', 45000.0, 8.54907883052161, 'sp'], ['R', 45000.0, 8.54907883052161, 'sp'], ['S', 2000.0, 0.0, 'sp']]],
    ['J3', 299863.00800479756, 311158.49085126584, -94.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K3', 298884.20579447143, 298721.6295705473, -94.5, 400.0, [['S', 6000.0, 0.0, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['S', 4537.6400717546285, 0.0, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['S', 4537.6400717546285, 0.0, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['S', 4537.6400717546285, 0.0, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['S', 4537.6400717546285, 0.0, 'sp'], ['L', 25000.0, 3.396166541332584, 'sp'], ['R', 25000.0, 18.55762431513876, 'sp'], ['S', 56139.52432545826, 0.0, 'sp'], ['L', 25000.0, 21.90449726055504, 'sp'], ['R', 25000.0, 4.008666165330334, 'sp'], ['S', 5300.759354757928, 0.0, 'sp'], ['R', 25000.0, 4.008666165330334, 'sp'], ['L', 25000.0, 21.90449726055504, 'sp'], ['L', 45000.0, 8.54907883052161, 'sp'], ['R', 45000.0, 8.54907883052161, 'sp'], ['S', 2000.0, 0.0, 'sp']]],
    ['J4', 288841.50914873416, 99863.00800479754, -4.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K4', 299673.9815184093, 99010.47394017602, -4.5, 400.0, [['S', 19537.765934600946, 0.0, 'sp'], ['L', 45000.0, 18.201565103335405, 'sp'], ['R', 45000.0, 13.701565103335406, 'sp']]],
    ['J5', 311158.49085126584, 100136.99199520246, -184.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K5', 297785.73603910534, 101189.45062386419, -184.5, 400.0, [['S', 16989.628434600952, 0.0, 'sp'], ['L', 45000.0, 18.201565103335405, 'sp'], ['R', 45000.0, 13.701565103335406, 'sp']]],
    ['J6', 300136.99199520244, 88841.50914873414, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K6', 300989.526059819, 99673.98151840431, 85.5, 400.0, [['S', 19537.76593462027, 0.0, 'sp'], ['L', 45000.0, 18.201565103326033, 'sp'], ['R', 45000.0, 13.701565103326033, 'sp']]],
    ['J7', 299863.00800479756, 111158.49085126586, -94.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K7', 298826.3328943545, 97986.28465299071, -94.5, 400.0, [['S', 17190.797184620133, 0.0, 'sp'], ['L', 45000.0, 18.201565103326118, 'sp'], ['R', 45000.0, 13.701565103326116, 'sp']]],
    ['J8', 288841.50914873416, 499863.00800479756, -4.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K8', 300609.87504985125, 498936.8175218504, -4.5, 400.0, [['S', 18598.97843461645, 0.0, 'sp'], ['L', 45000.0, 18.201565103325283, 'sp'], ['R', 45000.0, 13.701565103325283, 'sp']]],
    ['J9', 311158.49085126584, 500136.99199520244, -184.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K9', 299256.4258742284, 501073.7048236254, -184.5, 400.0, [['S', 18464.86593461644, 0.0, 'sp'], ['L', 45000.0, 18.201565103325258, 'sp'], ['R', 45000.0, 13.701565103325256, 'sp']]],
    ['J10', 300136.99199520244, 488841.50914873416, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K10', 301199.972969335, 502347.963036815, 85.5, 400.0, [['S', 16855.515934616495, 0.0, 'sp'], ['L', 45000.0, 18.20156510332522, 'sp'], ['R', 45000.0, 13.701565103325219, 'sp']]],
    ['J11', 299863.00800479756, 511158.49085126584, -94.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K11', 298873.6834489956, 498587.93049462704, -94.5, 400.0, [['S', 17794.30343461641, 0.0, 'sp'], ['L', 45000.0, 18.201565103325308, 'sp'], ['R', 45000.0, 13.701565103325308, 'sp']]],
    ['J12', 88841.50914873414, 299863.00800479756, -4.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K12', 99673.98151840431, 299010.473940181, -4.5, 400.0, [['S', 19537.76593462027, 0.0, 'sp'], ['L', 45000.0, 18.201565103326033, 'sp'], ['R', 45000.0, 13.701565103326033, 'sp']]],
    ['J13', 111158.49085126586, 300136.99199520244, -184.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K13', 98654.78003259213, 301121.0553782665, -184.5, 400.0, [['S', 17861.35968462022, 0.0, 'sp'], ['L', 45000.0, 18.20156510332606, 'sp'], ['R', 45000.0, 13.70156510332606, 'sp']]],
    ['J14', 100136.99199520246, 288841.50914873416, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K14', 101031.61544172718, 300208.77782209043, 85.5, 400.0, [['S', 19001.31593460096, 0.0, 'sp'], ['L', 45000.0, 18.201565103335383, 'sp'], ['R', 45000.0, 13.701565103335382, 'sp']]],
    ['J15', 99863.00800479754, 311158.49085126584, -94.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K15', 98989.42924922441, 300058.6203297501, -94.5, 400.0, [['S', 19269.540934600904, 0.0, 'sp'], ['L', 45000.0, 18.201565103335405, 'sp'], ['R', 45000.0, 13.701565103335406, 'sp']]],
    ['J16', 488841.50914873416, 299863.00800479756, -4.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K16', 501679.46765721356, 298852.638758044, -4.5, 400.0, [['S', 17526.078434616407, 0.0, 'sp'], ['L', 45000.0, 18.201565103325283, 'sp'], ['R', 45000.0, 13.701565103325283, 'sp']]],
    ['J17', 511158.49085126584, 300136.99199520244, -184.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K17', 499390.12495014875, 301063.1824781496, -184.5, 400.0, [['S', 18598.97843461645, 0.0, 'sp'], ['L', 45000.0, 18.201565103325283, 'sp'], ['R', 45000.0, 13.701565103325283, 'sp']]],
    ['J18', 500136.99199520244, 288841.50914873416, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K18', 501031.6154417222, 300208.77782209043, 85.5, 400.0, [['S', 19001.31593461638, 0.0, 'sp'], ['L', 45000.0, 18.201565103325308, 'sp'], ['R', 45000.0, 13.701565103325308, 'sp']]],
    ['J19', 499863.00800479756, 311158.49085126584, -94.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K19', 498826.3328943545, 297986.28465298575, -94.5, 400.0, [['S', 17190.797184616393, 0.0, 'sp'], ['L', 45000.0, 18.201565103325308, 'sp'], ['R', 45000.0, 13.701565103325308, 'sp']]],
    ['S0', 165775.74116385204, 300100.0, 0.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['L', 8000.0, 30.0, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 8000.0, 30.0, 'sp'], ['S', 1500.0, 0.0, 'sp'], ['S', 1500.0, 0.0, 'sp'], ['L', 8000.0, 30.0, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['L', 6000.0, 1.4000000000000001, 'sp'], ['R', 6000.0, 16.4, 'sp'], ['L', 8000.0, 30.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S1', 162835.72897701472, 299900.0, 0.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['S2', 351509.9066914269, 300100.0, 0.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 12000.0, 0.0, 'sp'], ['L', 6000.0, 35.0, 'sp'], ['R', 6000.0, 70.0, 'sp'], ['L', 6000.0, 35.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['L', 6000.0, 35.0, 'sp'], ['R', 6000.0, 70.0, 'sp'], ['L', 6000.0, 35.0, 'sp'], ['S', 12000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S3', 357929.0578748716, 299900.0, 0.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['S4', 299900.0, 156175.21285469842, 90.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['L', 10000.0, 18.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 18.0, 'sp'], ['R', 10000.0, 18.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 18.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S5', 300100.0, 165687.28389573307, 90.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['R', 7699.999999999999, 2.4000000000000012, 'sp'], ['L', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['L', 6000.0, 0.9333333333333333, 'sp'], ['R', 6000.0, 20.933333333333334, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['S6', 299900.0, 362835.7289770147, 90.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['L', 6000.0, 1.1666666666666667, 'sp'], ['R', 6000.0, 26.166666666666668, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['S', 356.5781023319536, 0.0, 'sp'], ['R', 6000.0, 1.1666666666666667, 'sp'], ['L', 6000.0, 26.166666666666668, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S7', 300100.0, 365775.74116385204, 90.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['R', 8000.0, 30.0, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 8000.0, 30.0, 'sp'], ['S', 1500.0, 0.0, 'sp'], ['S', 1500.0, 0.0, 'sp'], ['R', 8000.0, 30.0, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['S', 448.9039047464073, 0.0, 'sp'], ['R', 6000.0, 1.4000000000000001, 'sp'], ['L', 6000.0, 16.4, 'sp'], ['R', 8000.0, 30.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['S8', 165687.28389573307, 500100.0, 0.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['S', 967.5628110900652, 0.0, 'sp'], ['L', 7699.999999999999, 2.4000000000000012, 'sp'], ['R', 7699.999999999999, 22.400000000000002, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['S', 293.1038242710362, 0.0, 'sp'], ['R', 6000.0, 0.9333333333333333, 'sp'], ['L', 6000.0, 20.933333333333334, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S9', 151509.90669142685, 499900.0, 0.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 12000.0, 0.0, 'sp'], ['R', 6000.0, 35.0, 'sp'], ['L', 6000.0, 70.0, 'sp'], ['R', 6000.0, 35.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['R', 6000.0, 35.0, 'sp'], ['L', 6000.0, 70.0, 'sp'], ['R', 6000.0, 35.0, 'sp'], ['S', 12000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['S10', 356175.2128546984, 500100.0, 0.0, 200.0, [['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['L', 10000.0, 18.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 18.0, 'sp'], ['R', 10000.0, 18.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 10000.0, 18.0, 'sp'], ['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp']]],
    ['S11', 357929.0578748716, 499900.0, 0.0, 200.0, [['R', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['S', 2000.0, 0.0, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['S', 557.8962188810953, 0.0, 'sp'], ['R', 6300.0, 1.6500000000000004, 'sp'], ['L', 6300.0, 15.4, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['S', 991.8155002330584, 0.0, 'sp'], ['L', 11200.0, 1.6500000000000004, 'sp'], ['R', 11200.0, 15.4, 'sp'], ['L', 16000.0, 26.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 16000.0, 26.0, 'sp']]],
    ['OEridanus', 266000.0, 304000.0, 0.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['ODunes', 134000.0, 504000.0, 180.0, 200.0, [['L', 12000.0, 33.12294020774379, 'sp'], ['R', 12000.0, 33.12294020774379, 'sp']]],
    ['OGlacier', 466000.0, 504000.0, 0.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['OBasalt', 134000.0, 96000.0, 180.0, 200.0, [['R', 12000.0, 33.12294020774379, 'sp'], ['L', 12000.0, 33.12294020774379, 'sp']]],
    ['OMesa', 466000.0, 96000.0, 0.0, 200.0, [['L', 12000.0, 33.12294020774379, 'sp'], ['R', 12000.0, 33.12294020774379, 'sp']]],
    ['SCoast', 50000.0, 100100.0, 180.0, 200.0, [['R', 16000.0, 40.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 16000.0, 30.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['R', 14000.0, 80.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['L', 12000.0, 22.0, 'sp'], ['R', 10000.0, 44.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 12000.0, 40.0, 'sp'], ['S', 7000.0, 0.0, 'sp'], ['R', 14000.0, 36.0, 'sp'], ['L', 9000.0, 38.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['R', 12000.0, 44.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['L', 16000.0, 48.0, 'sp'], ['R', 11000.0, 40.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 10000.0, 36.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 13000.0, 44.0, 'sp'], ['L', 15000.0, 50.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['R', 10000.0, 50.0, 'sp'], ['L', 16000.0, 24.0, 'sp'], ['S', 8727.098115426663, 0.0, 'sp'], ['R', 14000.0, 70.0, 'sp'], ['S', 18000.0, 0.0, 'sp'], ['R', 16000.0, 20.0, 'sp']]],
    ['SDrop', 548000.0, 499900.0, 0.0, 200.0, [['R', 16000.0, 35.0, 'sp'], ['S', 15000.0, 0.0, 'sp'], ['R', 14000.0, 55.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['L', 12000.0, 25.0, 'sp'], ['R', 12000.0, 50.0, 'sp'], ['L', 12000.0, 25.0, 'sp'], ['S', 8000.0, 0.0, 'sp'], ['R', 10000.0, 30.0, 'sp'], ['L', 10000.0, 60.0, 'sp'], ['R', 10000.0, 30.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 14000.0, 18.0, 'sp'], ['S', 19000.0, 0.0, 'sp'], ['L', 16000.0, 20.0, 'sp'], ['R', 16000.0, 40.0, 'sp'], ['L', 16000.0, 28.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['R', 14000.0, 30.0, 'sp'], ['L', 14000.0, 34.0, 'sp'], ['R', 14000.0, 30.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['R', 12000.0, 26.0, 'sp'], ['L', 12000.0, 26.0, 'sp'], ['S', 5879.783526535728, 0.0, 'sp'], ['R', 14000.0, 70.0, 'sp'], ['S', 30000.0, 0.0, 'sp'], ['R', 16000.0, 20.0, 'sp']]],
    ['SWash', 132998.4291137482, 499900.0, 0.0, 180.0, [['R', 11000.0, 33.15480407817912, 'sp'], ['S', 26195.667069007883, 0.0, 'sp'], ['R', 11000.0, 6.8451959218208644, 'sp'], ['R', 11000.0, 9.597531313110863, 'sp'], ['S', 18633.517030353185, 0.0, 'sp'], ['R', 11000.0, 42.40246868688912, 'sp'], ['R', 11000.0, 46.3290720107088, 'sp'], ['S', 19196.8870664047, 0.0, 'sp'], ['R', 11000.0, 12.67092798929118, 'sp'], ['R', 11000.0, 11.970816332223478, 'sp'], ['S', 25221.928951414746, 0.0, 'sp'], ['L', 11000.0, 9.970816332223476, 'sp'], ['L', 11000.0, 40.588164291493094, 'sp'], ['S', 27512.12935659177, 0.0, 'sp'], ['L', 11000.0, 16.042864647408138, 'sp']]],
    ['SFrost', 455001.7454290838, 499900.0, -180.0, 180.0, [['L', 14000.0, 52.37939196874236, 'sp'], ['S', 8599.16965339394, 0.0, 'sp'], ['R', 14000.0, 15.37939196874232, 'sp'], ['L', 14000.0, 26.085628235877437, 'sp'], ['S', 28556.604357049735, 0.0, 'sp'], ['R', 14000.0, 8.085628235877437, 'sp'], ['R', 14000.0, 41.986130145870845, 'sp'], ['S', 27920.314359602744, 0.0, 'sp'], ['R', 14000.0, 2.0138698541291387, 'sp'], ['R', 14000.0, 1.6588347180102003, 'sp'], ['S', 30811.780924941835, 0.0, 'sp'], ['L', 14000.0, 13.658834718010192, 'sp'], ['R', 14000.0, 4.701542647036069, 'sp'], ['S', 39203.18832614415, 0.0, 'sp'], ['L', 14000.0, 71.7015426470361, 'sp']]],
    ['SReed', 249011.8573179522, 100501.09947944054, -7.64885496181784, 180.0, [['L', 10000.0, 48.42910444138441, 'sp'], ['S', 8889.970689508278, 0.0, 'sp'], ['L', 10000.0, 42.219750520433436, 'sp'], ['L', 10000.0, 44.26716256942032, 'sp'], ['S', 24169.026830220588, 0.0, 'sp'], ['L', 10000.0, 11.73283743057968, 'sp'], ['L', 10000.0, 0.44557878426116015, 'sp'], ['S', 31301.536974713654, 0.0, 'sp'], ['R', 10000.0, 19.445578784261155, 'sp'], ['R', 10000.0, 58.42455950392029, 'sp'], ['S', 5104.852247212923, 0.0, 'sp'], ['R', 10000.0, 43.575440496079686, 'sp'], ['R', 10000.0, 13.847958053858653, 'sp'], ['S', 34055.54808187259, 0.0, 'sp'], ['L', 10000.0, 3.8479580538586537, 'sp'], ['L', 10000.0, 26.644446642937776, 'sp'], ['S', 28311.48045105215, 0.0, 'sp'], ['L', 10000.0, 55.35555335706223, 'sp']]],
    ['SRed', 468992.00000005425, 100100.00000000013, -180.0, 180.0, [['R', 12000.0, 33.36612351957103, 'sp'], ['S', 18103.18121947786, 0.0, 'sp'], ['R', 12000.0, 7.633876480428934, 'sp'], ['R', 12000.0, 8.633586799527224, 'sp'], ['S', 32128.326267828386, 0.0, 'sp'], ['R', 12000.0, 7.366413200472742, 'sp'], ['L', 12000.0, 2.8029871122203907, 'sp'], ['S', 13547.173293570215, 0.0, 'sp'], ['R', 12000.0, 52.80298711222041, 'sp'], ['R', 12000.0, 40.81579174371289, 'sp'], ['S', 21519.85771573024, 0.0, 'sp'], ['R', 12000.0, 9.184208256287098, 'sp'], ['R', 12000.0, 12.793582503504828, 'sp'], ['S', 31766.165676568005, 0.0, 'sp'], ['L', 12000.0, 10.793582503504828, 'sp'], ['L', 12000.0, 37.81411247147964, 'sp'], ['S', 19306.456788310432, 0.0, 'sp'], ['L', 12000.0, 18.185887528559576, 'sp']]],
    ['J20', 500136.99199520244, 88841.50914873414, 85.5, 200.0, [['S', 8183.7185242982905, 0.0, 'sp']]],
    ['K20', 501189.4506238592, 102214.26396088972, 85.5, 400.0, [['S', 16989.628434620266, 0.0, 'sp'], ['L', 45000.0, 18.201565103326033, 'sp'], ['R', 45000.0, 13.701565103326033, 'sp']]],
    ['SNeedle', 173989.83287513995, 300100.0, 0.0, 200.0, [['L', 8500.0, 25.0, 'sp'], ['R', 8500.0, 25.0, 'sp'], ['S', 13000.0, 0.0, 'sp'], ['R', 8500.0, 25.0, 'sp'], ['L', 8500.0, 25.0, 'sp']]],
    ['SHammer', 300100.0, 351995.2437054928, 90.0, 200.0, [['R', 7000.0, 35.0, 'sp'], ['L', 7000.0, 35.0, 'sp'], ['S', 9000.0, 0.0, 'sp'], ['L', 7000.0, 35.0, 'sp'], ['R', 7000.0, 35.0, 'sp']]],
    ['SAurora', 43000.0, 99900.0, -180.0, 200.0, [['L', 8000.0, 70.47214256874965, 'sp'], ['S', 61797.81269915339, 0.0, 'sp'], ['L', 8000.0, 154.5278574312503, 'sp'], ['S', 769332.1779309637, 0.0, 'sp'], ['R', 8000.0, 154.52762865268855, 'sp'], ['S', 61797.72518423367, 0.0, 'sp'], ['R', 8000.0, 70.47237134731147, 'sp']]],
    ['SHelios', 345011.34528947115, 500100.0, 0.0, 200.0, [['L', 9000.0, 35.870698226710616, 'sp'], ['S', 27135.04995349857, 0.0, 'sp'], ['L', 9000.0, 54.12930177328937, 'sp'], ['S', 24000.0, 0.0, 'sp'], ['R', 21000.0, 180.0, 'sp'], ['R', 15000.0, 96.23297123708821, 'sp'], ['R', 4500.0, 98.77802591253484, 'sp'], ['S', 19200.0, 0.0, 'sp'], ['L', 4500.0, 98.77802591253484, 'sp'], ['L', 15000.0, 96.23297123708821, 'sp'], ['L', 21000.0, 90.0, 'sp'], ['L', 60000.0, 25.0, 'sp'], ['R', 9000.0, 97.94332506094679, 'sp'], ['S', 22640.309884132308, 0.0, 'sp'], ['L', 9000.0, 72.94332506094455, 'sp']]],
    ['SHyperion', 131990.4437753533, 300100.0, 0.0, 200.0, [['L', 12000.0, 60.0, 'sp'], ['S', 32400.0, 0.0, 'sp'], ['V', 45014.91590840522, 0.0, 'sp', 87.97715601651902], ['W', 1680.0, 87.97715601651902, 'sp'], ['V', 3000.9943938936817, 87.97715601651902, 'sp', 0.0], ['S', 4800.0, 0.0, 'sp'], ['V', 296.61485379438784, 0.0, 'sp', -88.08350331664974], ['W', 32280.0, -88.08350331664974, 'sp'], ['V', 15985.97948870806, -88.08350331664974, 'sp', 0.0], ['S', 114254.44774058949, 0.0, 'sp'], ['R', 12000.0, 60.0, 'sp']]],
    ['SCaucasus', 552000.0, 299900.0, 0.0, 200.0, [['R', 14000.0, 50.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['R', 12000.0, 70.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 10000.0, 95.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['R', 10000.0, 100.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 11000.0, 80.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['R', 12000.0, 90.0, 'sp'], ['S', 5000.0, 0.0, 'sp'], ['L', 10000.0, 100.0, 'sp'], ['S', 6000.0, 0.0, 'sp'], ['R', 11000.0, 85.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 12000.0, 75.0, 'sp'], ['S', 3000.0, 0.0, 'sp'], ['R', 10000.0, 95.0, 'sp'], ['S', 4000.0, 0.0, 'sp'], ['L', 12000.0, 50.0, 'sp'], ['S', 4773.091248045705, 0.0, 'sp'], ['R', 14000.0, 70.0, 'sp'], ['S', 8000.0, 0.0, 'sp'], ['R', 16000.0, 20.0, 'sp']]],
  ];
  // [parent road, a0, a1, child road, b0, b1, sense]: the two roads are one through these samples
  const NET_JUNCTIONS = [
    [0, 2611, 2731, 6, 0, 101, 1], [3, 2611, 2731, 6, 685, 786, -1], [0, 2611, 2731, 7, 0, 101, 1], [3, 3519, 3639, 7, 685, 786, 1], [0, 3519, 3639, 8, 0, 101, -1], [3, 2611, 2731, 8, 685, 786, -1],
    [0, 3519, 3639, 9, 0, 101, -1], [3, 3519, 3639, 9, 685, 786, 1], [1, 2611, 2731, 10, 0, 101, 1], [3, 11088, 11208, 10, 685, 786, -1], [1, 2611, 2731, 11, 0, 101, 1], [3, 11996, 12116, 11, 685, 786, 1],
    [1, 3519, 3639, 12, 0, 101, -1], [3, 11088, 11208, 12, 685, 786, -1], [1, 3519, 3639, 13, 0, 101, -1], [3, 11996, 12116, 13, 685, 786, 1], [2, 2611, 2731, 14, 0, 101, 1], [3, 19592, 19712, 14, 685, 786, -1],
    [2, 2611, 2731, 15, 0, 101, 1], [3, 20500, 20620, 15, 685, 786, 1], [2, 3519, 3639, 16, 0, 101, -1], [3, 19592, 19712, 16, 685, 786, -1], [2, 3519, 3639, 17, 0, 101, -1], [3, 20500, 20620, 17, 685, 786, 1],
    [0, 11075, 11195, 18, 0, 101, 1], [4, 2611, 2731, 18, 685, 786, -1], [0, 11075, 11195, 19, 0, 101, 1], [4, 3519, 3639, 19, 685, 786, 1], [0, 11983, 12103, 20, 0, 101, -1], [4, 2611, 2731, 20, 685, 786, -1],
    [0, 11983, 12103, 21, 0, 101, -1], [4, 3519, 3639, 21, 685, 786, 1], [1, 10944, 11065, 22, 0, 101, 1], [4, 10944, 11065, 22, 685, 786, -1], [1, 10944, 11065, 23, 0, 101, 1], [4, 11852, 11973, 23, 685, 786, 1],
    [1, 11852, 11973, 24, 0, 101, -1], [4, 10944, 11065, 24, 685, 786, -1], [1, 11852, 11973, 25, 0, 101, -1], [4, 11852, 11973, 25, 685, 786, 1], [2, 10944, 11065, 26, 0, 101, 1], [4, 19278, 19398, 26, 685, 786, -1],
    [2, 10944, 11065, 27, 0, 101, 1], [4, 20186, 20306, 27, 685, 786, 1], [2, 11852, 11973, 28, 0, 101, -1], [4, 19278, 19398, 28, 685, 786, -1], [2, 11852, 11973, 29, 0, 101, -1], [4, 20186, 20306, 29, 685, 786, 1],
    [0, 19502, 19622, 30, 0, 101, 1], [5, 2611, 2731, 30, 685, 786, -1], [0, 19502, 19622, 31, 0, 101, 1], [5, 3519, 3639, 31, 685, 786, 1], [0, 20410, 20530, 32, 0, 101, -1], [5, 2611, 2731, 32, 685, 786, -1],
    [0, 20410, 20530, 33, 0, 101, -1], [5, 3519, 3639, 33, 685, 786, 1], [1, 19278, 19398, 34, 0, 101, 1], [5, 11038, 11158, 34, 685, 786, -1], [1, 19278, 19398, 35, 0, 101, 1], [5, 11946, 12066, 35, 685, 786, 1],
    [1, 20186, 20306, 36, 0, 101, -1], [5, 11038, 11158, 36, 685, 786, -1], [1, 20186, 20306, 37, 0, 101, -1], [5, 11946, 12066, 37, 685, 786, 1], [2, 19278, 19398, 38, 0, 101, 1], [5, 19555, 19675, 38, 685, 786, -1],
    [2, 19278, 19398, 39, 0, 101, 1], [5, 20463, 20583, 39, 685, 786, 1], [2, 20186, 20306, 40, 0, 101, -1], [5, 19555, 19675, 40, 685, 786, -1], [2, 20186, 20306, 41, 0, 101, -1], [5, 20463, 20583, 41, 685, 786, 1],
    [1, 13161, 13260, 42, 0, 80, -1], [1, 12084, 12183, 42, 1435, 1515, -1], [2, 1323, 1422, 43, 0, 80, 1], [2, 2401, 2500, 43, 1435, 1515, 1], [2, 21495, 21594, 44, 0, 80, -1], [2, 20417, 20516, 44, 1435, 1515, -1],
    [0, 1323, 1422, 45, 0, 80, 1], [0, 2401, 2500, 45, 1435, 1515, 1], [0, 21719, 21818, 46, 0, 80, -1], [0, 20641, 20740, 46, 1435, 1515, -1], [0, 0, 77, 47, 0, 78, -1], [0, 0, 77, 47, 1939, 2017, 1],
    [0, 23064, 23141, 48, 0, 78, 1], [0, 23064, 23141, 48, 2254, 2332, -1], [1, 0, 77, 49, 0, 78, -1], [1, 0, 77, 49, 2405, 2483, 1], [1, 22840, 22917, 50, 0, 78, 1], [1, 22840, 22917, 50, 2539, 2617, -1],
    [2, 0, 77, 51, 0, 78, -1], [2, 0, 77, 51, 1771, 1849, 1], [2, 22840, 22917, 52, 0, 78, 1], [2, 22840, 22917, 52, 2422, 2500, -1], [3, 0, 77, 53, 0, 78, -1], [3, 0, 77, 53, 2190, 2268, 1],
    [3, 23154, 23231, 54, 0, 78, 1], [3, 23154, 23231, 54, 2639, 2717, -1], [4, 0, 77, 55, 0, 78, -1], [4, 0, 77, 55, 2573, 2651, 1], [4, 22840, 22917, 56, 0, 78, 1], [4, 22840, 22917, 56, 2154, 2232, -1],
    [5, 0, 77, 57, 0, 78, -1], [5, 0, 77, 57, 2622, 2700, 1], [5, 23117, 23194, 58, 0, 78, 1], [5, 23117, 23194, 58, 2580, 2658, -1], [22, 29, 149, 59, 0, 101, 1], [4, 4782, 5110, 60, 8044, 8354, -1],
    [25, 29, 149, 61, 0, 101, 1], [4, 17807, 18135, 62, 8063, 8373, 1], [24, 637, 757, 63, 0, 101, -1], [1, 17807, 18135, 64, 8071, 8381, 1], [23, 637, 757, 65, 0, 101, -1], [1, 4782, 5110, 66, 8049, 8359, -1],
    [18, 29, 149, 67, 0, 101, 1], [0, 13187, 13432, 68, 1634, 1860, 1], [21, 29, 149, 69, 0, 101, 1], [0, 9746, 9991, 70, 1527, 1753, -1], [20, 637, 757, 71, 0, 101, -1], [4, 4723, 4968, 72, 1634, 1860, 1],
    [19, 637, 757, 73, 0, 101, -1], [4, 1282, 1527, 74, 1536, 1762, -1], [26, 29, 149, 75, 0, 101, 1], [2, 13057, 13302, 76, 1594, 1820, 1], [29, 29, 149, 77, 0, 101, 1], [2, 9615, 9860, 78, 1589, 1815, -1],
    [28, 637, 757, 79, 0, 101, -1], [4, 21390, 21635, 80, 1522, 1748, 1], [27, 637, 757, 81, 0, 101, -1], [4, 17949, 18194, 82, 1561, 1787, -1], [10, 29, 149, 83, 0, 101, 1], [1, 4723, 4968, 84, 1634, 1860, 1],
    [13, 29, 149, 85, 0, 101, 1], [1, 1282, 1527, 86, 1564, 1790, -1], [12, 637, 757, 87, 0, 101, -1], [3, 13200, 13445, 88, 1611, 1837, 1], [11, 637, 757, 89, 0, 101, -1], [3, 9759, 10004, 90, 1622, 1848, -1],
    [34, 29, 149, 91, 0, 101, 1], [1, 21390, 21635, 92, 1550, 1776, 1], [37, 29, 149, 93, 0, 101, 1], [1, 17949, 18194, 94, 1594, 1820, -1], [36, 637, 757, 95, 0, 101, -1], [5, 13150, 13395, 96, 1611, 1837, 1],
    [35, 637, 757, 97, 0, 101, -1], [5, 9709, 9954, 98, 1536, 1762, -1], [1, 5856, 5990, 99, 0, 115, 1], [1, 8594, 8728, 99, 2881, 2996, 1], [1, 5733, 5867, 100, 0, 115, 1], [1, 8716, 8850, 100, 4155, 4270, 1],
    [1, 13595, 13729, 101, 0, 115, 1], [1, 17521, 17656, 101, 4071, 4186, 1], [1, 13862, 13996, 102, 0, 115, 1], [1, 17254, 17388, 102, 3949, 4064, 1], [4, 5456, 5590, 103, 0, 115, 1], [4, 8994, 9128, 103, 3669, 3784, 1],
    [4, 5852, 5986, 104, 0, 115, 1], [4, 8597, 8731, 104, 4683, 4798, 1], [4, 14067, 14201, 105, 0, 115, 1], [4, 17050, 17184, 105, 4155, 4270, 1], [4, 14189, 14323, 106, 0, 115, 1], [4, 16927, 17061, 106, 2881, 2996, 1],
    [2, 5852, 5986, 107, 0, 115, 1], [2, 8597, 8731, 107, 4683, 4798, 1], [2, 5261, 5396, 108, 0, 115, 1], [2, 9188, 9322, 108, 4071, 4186, 1], [2, 13789, 13923, 109, 0, 115, 1], [2, 17327, 17461, 109, 3669, 3784, 1],
    [2, 13862, 13996, 110, 0, 115, 1], [2, 17254, 17388, 110, 3949, 4064, 1], [1, 10478, 10598, 111, 479, 580, 1], [2, 3985, 4105, 112, 479, 580, -1], [2, 18812, 18932, 113, 479, 580, 1], [0, 3985, 4105, 114, 479, 580, -1],
    [0, 19036, 19156, 115, 479, 580, 1], [0, 917, 1052, 116, 0, 115, -1], [1, 589, 723, 116, 10313, 10428, 1], [2, 21782, 21916, 117, 0, 115, 1], [1, 21949, 22084, 117, 10293, 10408, -1], [2, 4490, 4604, 118, 0, 95, 1],
    [3, 15635, 15740, 118, 6621, 6708, -1], [2, 17802, 17927, 119, 0, 106, -1], [4, 15990, 16115, 119, 7949, 8055, -1], [0, 9453, 9575, 120, 0, 102, 1], [4, 7775, 7885, 120, 8088, 8179, 1], [0, 18616, 18734, 121, 0, 99, -1],
    [5, 7779, 7897, 121, 7706, 7805, 1], [32, 637, 757, 122, 0, 101, -1], [5, 4723, 4968, 123, 1527, 1753, 1], [1, 6198, 6304, 124, 0, 87, 1], [1, 7253, 7358, 124, 1075, 1162, 1], [4, 13615, 13714, 125, 0, 80, 1],
    [4, 14581, 14679, 125, 1011, 1091, 1], [0, 657, 760, 126, 0, 84, -1], [2, 22157, 22260, 126, 39742, 39826, -1], [2, 13324, 13432, 127, 0, 89, 1], [2, 17861, 17969, 127, 13459, 13548, 1], [1, 4448, 4568, 128, 0, 101, 1],
    [2, 9732, 9852, 128, 12788, 12889, 1], [1, 21949, 22076, 129, 0, 108, 1], [0, 22435, 22570, 129, 10400, 10515, -1],
  ];
  // Physical pavement unions only; route choices remain in NET_JUNCTIONS.
  const NET_OVERLAPS = [[1, 10984, 11099, 59, 0, 96, 1], [1, 11818, 11933, 61, 0, 96, -1], [4, 10984, 11099, 63, 0, 96, 1], [4, 11818, 11933, 65, 0, 96, -1], [0, 11114, 11230, 67, 0, 96, 1], [0, 11948, 12064, 69, 0, 96, -1], [4, 2650, 2766, 71, 0, 96, 1], [4, 3484, 3600, 73, 0, 96, -1], [2, 10984, 11099, 75, 0, 96, 1], [2, 11818, 11933, 77, 0, 96, -1], [4, 19317, 19433, 79, 0, 96, 1], [4, 20151, 20267, 81, 0, 96, -1], [1, 2650, 2766, 83, 0, 96, 1], [1, 3484, 3600, 85, 0, 96, -1], [3, 11127, 11243, 87, 0, 96, 1], [3, 11961, 12077, 89, 0, 96, -1], [1, 19317, 19433, 91, 0, 96, 1], [1, 20151, 20267, 93, 0, 96, -1], [5, 11077, 11193, 95, 0, 96, 1], [5, 11911, 12027, 97, 0, 96, -1], [5, 2650, 2766, 122, 0, 96, 1]];
  const NET_TWISTS = [[68, 250, 708, 1], [76, 250, 708, -1], [84, 250, 708, 1], [92, 250, 708, -1], [124, 372, 790, 1]];
  const NET_PRESSURE = [126, 3920, 35920];
  const NET_JUMP_PROFILES = ['ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC', 'ARC', 'HIGH ARC', 'SKY ARC'];
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
    [3, [[0, 0.0, 0.0], [417, 0.0, 0.0], [1250, 600.0, 0.0], [21981, 600.0, 0.0], [22814, 0.0, 0.0], [23231, 0.0, 0.0]]],
    [4, [[0, 0.0, 0.0], [417, 0.0, 0.0], [1250, 600.0, 0.0], [21667, 600.0, 0.0], [22500, 0.0, 0.0], [22917, 0.0, 0.0]]],
    [5, [[0, 0.0, 0.0], [417, 0.0, 0.0], [1250, 600.0, 0.0], [21944, 600.0, 0.0], [22777, 0.0, 0.0], [23194, 0.0, 0.0]]],
    [6, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [7, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [8, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [9, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [10, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [11, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [12, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [13, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [14, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [15, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [16, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [17, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [18, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [19, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [20, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [21, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [22, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [23, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [24, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [25, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [26, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [27, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [28, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [29, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [30, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [31, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [32, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [33, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [34, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [35, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [36, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [37, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [38, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [39, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [40, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [41, [[0, 0.0, 0.0], [125, 0.0, 0.0], [661, 600.0, 0.0], [786, 600.0, 0.0]]],
    [47, [[0, 0.0, 0.0], [279, 0.0, 0.0], [303, 68.14866977566095, 0.2366099454222913], [327, 268.72447810914963, 0.45978267998106453], [351, 590.3366128945568, 0.6568440995176786], [375, 1014.7205414907523, 0.8166029760275192], [399, 1517.7752637243907, 0.929986513744755], [423, 2070.9320211416893, 0.9905555982778212], [447, 2643.1926959189313, 1.0], [471, 3216.49325023703, 1.0], [495, 3790.5773288691234, 1.0], [519, 4366.228456129311, 1.0], [543, 4941.879583389478, 1.0], [567, 5517.530710649669, 1.0], [591, 6093.181837909862, 1.0], [615, 6668.832965170028, 1.0], [639, 7244.484092430213, 1.0], [663, 7820.13521969039, 1.0], [687, 8395.786346950568, 1.0], [711, 8971.437474210728, 1.0], [735, 9547.088601470903, 1.0], [759, 10122.739728731074, 1.0], [783, 10698.390855991263, 1.0], [807, 11274.041983251427, 1.0], [831, 11849.693110511602, 1.0], [855, 12425.34423777177, 1.0], [879, 13000.99536503198, 1.0], [903, 13576.646492292133, 1.0], [927, 14152.29761955233, 1.0], [951, 14727.948746812533, 1.0], [975, 15298.356845131615, 0.9722811921169565], [999, 15836.636004027225, 0.8889018914731737], [1023, 16311.967092459641, 0.7546285448714939], [1047, 16697.13504598598, 0.5771489679622172], [1071, 16970.087087222866, 0.3666247475643765], [1095, 17115.19535682576, 0.1351094403763837], [1119, 17124.151686015994, -0.10414155298106421], [1143, 16996.44328048658, -0.3374299254526747], [1167, 16739.38208042189, -0.5513987596284429], [1191, 16367.686115624327, -0.7337972775714868], [1215, 15902.63682524506, -0.8741822586700876], [1239, 15370.86058974776, -0.9645159658597023], [1263, 14802.80423844887, -0.9996263459707234], [1287, 14227.161283291713, -1.0], [1311, 13651.510156031534, -1.0], [1335, 13075.859028771374, -1.0], [1359, 12500.207901511207, -1.0], [1383, 11924.556774251014, -1.0], [1407, 11348.9056469908, -1.0], [1431, 10773.25451973062, -1.0], [1455, 10197.603392470435, -1.0], [1479, 9621.952265210264, -1.0], [1503, 9046.301137950108, -1.0], [1527, 8470.65001068993, -1.0], [1551, 7897.05563475411, -1.0], [1575, 7323.755080436018, -1.0], [1599, 6750.454526117919, -1.0], [1623, 6177.153971799813, -1.0], [1647, 5603.853417481729, -1.0], [1671, 5030.55286316363, -1.0], [1695, 4457.2523088455455, -1.0], [1719, 3883.951754527461, -1.0], [1743, 3310.0888156923284, -1.0], [1767, 2734.0888156923284, -1.0], [1791, 2158.4982398714437, -0.9949243497775843], [1815, 1597.8294549012694, -0.9424888019317087], [1839, 1083.144334604257, -0.8360259786005388], [1863, 643.9467147028847, -0.6816387600233587], [1887, 305.41318165023586, -0.4881772468829366], [1911, 86.94984872188388, -0.2667314366888633], [1935, 1.0799190024322343, -0.02999550020252904], [1938, 0.0, 0.0], [2017, 0.0, 0.0]]],
    [48, [[0, 0.0, 0.0], [529, 0.0, 0.0], [553, 30.638053140599, 0.10637309840239226], [577, 122.20454948819317, 0.21153913582638864], [601, 273.6604449017235, 0.31430474833013117], [625, 483.2871046508444, 0.4135038106184739], [649, 748.7058054980027, 0.5080106685647295], [673, 1066.904728087175, 0.5967529124889267], [697, 1434.2731333447316, 0.6787235462484846], [721, 1846.6972643033082, 0.7530013031650463], [745, 2299.5230354667588, 0.8187414350466414], [769, 2787.5506869106293, 0.8751858236259422], [793, 3305.239299880494, 0.9216936163399112], [817, 3846.71119401158, 0.9577367777379088], [841, 4405.818660738572, 0.9829060846368786], [865, 4976.21376252366, 0.9969157723179103], [889, 5551.4402557743415, 1.0], [913, 6127.102971651639, 1.0], [937, 6702.765687528867, 1.0], [961, 7278.428403406164, 1.0], [985, 7854.091119283326, 1.0], [1009, 8429.753835160667, 1.0], [1033, 9005.416551037913, 1.0], [1057, 9580.494250559292, 0.9962494870477128], [1081, 10150.259802743567, 0.9813872248114848], [1105, 10708.251427419777, 0.9553825880336598], [1129, 11248.133855984408, 0.9185308255166166], [1153, 11763.777426184437, 0.8712503410566386], [1177, 12249.327676453777, 0.8140779430134018], [1201, 12699.271815703929, 0.7476627495497867], [1225, 13108.50131389138, 0.6727588187400246], [1249, 13472.369902726665, 0.5902165872217938], [1273, 13786.746328003257, 0.5009732145951284], [1297, 14048.061254611786, 0.40604194319496006], [1321, 14253.347791694068, 0.3065005940433331], [1345, 14400.275177827247, 0.20347932959453308], [1369, 14487.175243785772, 0.09814782221158477], [1393, 14513.061352431861, -0.008298025941140352], [1417, 14477.63960069578, -0.11464966081017551], [1441, 14381.312156462698, -0.2196995980113839], [1465, 14225.172692479973, -0.3222551322431531], [1489, 14010.993969126184, -0.4211518789030609], [1513, 13741.207707025227, -0.5152669941589565], [1537, 13418.876978023289, -0.6035319233795086], [1561, 13047.661427995235, -0.684944533181058], [1585, 12631.77572632861, -0.758580489347903], [1609, 12175.941713839702, -0.8236037514439681], [1633, 11685.398933158378, -0.8792696304765123], [1657, 11165.739852834708, -0.9249490068265172], [1681, 10622.790262578392, -0.9601325917603981], [1705, 10062.711243277769, -0.9844211421133988], [1729, 9491.858250768386, -0.9975390453312886], [1753, 8916.665580578581, -1.0], [1777, 8341.162022848508, -1.0], [1801, 7765.658465118435, -1.0], [1825, 7189.6998353075505, -1.0], [1849, 6613.6998353075505, -1.0], [1873, 6037.6998353075505, -1.0], [1897, 5461.6998353075505, -1.0], [1921, 4886.477002122632, -0.9954680250227168], [1945, 4317.092724286805, -0.9796858457616473], [1969, 3760.017847010058, -0.9527675833215269], [1993, 3221.5846371074645, -0.9150192174313325], [2017, 2707.9134616719853, -0.8668698335415126], [2041, 2224.843217898142, -0.8088667454122246], [2065, 1777.8649623723522, -0.7416692738010809], [2089, 1372.0594942653875, -0.6660412519680198], [2113, 1012.0396019184327, -0.5828423431871855], [2137, 701.8976293054593, -0.493018268959606], [2161, 445.1589583836276, -0.3975900590025187], [2185, 244.7419360975573, -0.2976424452106507], [2209, 102.92470154697003, -0.1943115315152251], [2233, 21.319290393105803, -0.08877187979733674], [2253, 0.0, 0.0], [2332, 0.0, 0.0]]],
    [49, [[0, 0.0, 0.0], [329, 0.0, 0.0], [353, 54.86742743000106, 0.19037802452174502], [377, 217.46275332480658, 0.3737923474136758], [401, 481.83851952177014, 0.543533987308541], [425, 838.3243139101605, 0.6933940861338058], [449, 1273.8804975210078, 0.8178910184915074], [473, 1772.5751721570898, 0.9124709001140683], [497, 2316.1669419048576, 0.9736741611406334], [521, 2884.7721521120448, 0.9992620912492883], [545, 3459.3853988957135, 1.0], [569, 4034.026996593574, 1.0], [593, 4608.834033120057, 1.0], [617, 5184.468263789698, 1.0], [641, 5760.102494459296, 1.0], [665, 6335.736725128917, 1.0], [689, 6911.370955798532, 1.0], [713, 7487.0051864682255, 1.0], [737, 8062.639417137904, 1.0], [761, 8638.273647807593, 1.0], [785, 9213.907878477228, 1.0], [809, 9789.542109146889, 1.0], [833, 10365.176339816546, 1.0], [857, 10940.810570486181, 1.0], [881, 11516.444801155845, 1.0], [905, 12092.079031825488, 1.0], [929, 12667.71326249513, 1.0], [953, 13243.34749316483, 1.0], [977, 13818.981723834484, 1.0], [1001, 14394.615954504075, 1.0], [1025, 14970.250185173747, 1.0], [1049, 15545.88441584336, 1.0], [1073, 16121.518646513003, 1.0], [1097, 16697.152877182598, 1.0], [1121, 17272.787107852102, 1.0], [1145, 17848.421338521664, 1.0], [1169, 18424.055569191238, 1.0], [1193, 18996.628543049832, 0.9832944037443522], [1217, 19549.15812782183, 0.9305366314512794], [1241, 20061.364414681564, 0.843624092664201], [1265, 20514.44719143617, 0.7257468578944125], [1289, 20891.776337443884, 0.5812315375003718], [1313, 21179.50222181696, 0.4153824761537286], [1337, 21367.06404548211, 0.234287060177721], [1361, 21447.57746872186, 0.04459228383001732], [1385, 21418.087296568698, -0.14673922447445237], [1409, 21279.675947392487, -0.33268476109548967], [1433, 21037.42372340966, -0.5064193111231154], [1457, 20700.222341359986, -0.6615660562918371], [1481, 20280.448567590913, -0.7924304321166153], [1505, 19793.50993657119, -0.894209143329263], [1529, 19257.279226950417, -0.9631664658346579], [1553, 18691.438452370025, -0.9967713641328176], [1577, 18116.06379143693, -1.0], [1601, 17540.429560767276, -1.0], [1625, 16964.7953300976, -1.0], [1649, 16389.161099427896, -1.0], [1673, 15813.526868758234, -1.0], [1697, 15237.892638088588, -1.0], [1721, 14662.258407418927, -1.0], [1745, 14086.624176749252, -1.0], [1769, 13510.989946079584, -1.0], [1793, 12935.355715409894, -1.0], [1817, 12359.721484740241, -1.0], [1841, 11784.08725407069, -1.0], [1865, 11208.453023401065, -1.0], [1889, 10632.818792731383, -1.0], [1913, 10057.970396497729, -1.0], [1937, 9483.32879879984, -1.0], [1961, 8908.687201102059, -1.0], [1985, 8334.045603404256, -1.0], [2009, 7759.404005706338, -1.0], [2033, 7184.762408008462, -1.0], [2057, 6610.120810310682, -1.0], [2081, 6035.479212612843, -1.0], [2105, 5460.837614915004, -1.0], [2129, 4886.196017217195, -1.0], [2153, 4311.554419519334, -1.0], [2177, 3735.6110196152567, -1.0], [2201, 3159.6110196152567, -1.0], [2225, 2584.946647850699, -0.9903832431532995], [2249, 2025.6111466836226, -0.9457839994495334], [2273, 1502.0853058661946, -0.8664263493157799], [2297, 1033.6091674823656, -0.7552267572495182], [2321, 637.3996479001089, -0.6162719075445577], [2345, 328.0178007226673, -0.4546685149944184], [2369, 116.8336850676742, -0.27635564856409844], [2393, 11.608505742745365, -0.08788646530286928], [2404, 0.0, 0.0], [2483, 0.0, 0.0]]],
    [50, [[0, 0.0, 0.0], [579, 0.0, 0.0], [603, 27.368628401746477, 0.09540476621572366], [627, 109.22483300017416, 0.18993916656672047], [651, 244.82184977990573, 0.2827407754281302], [675, 432.92264395277914, 0.37296297521731625], [699, 671.8111952728434, 0.4597826799810547], [723, 959.3081530765882, 0.5424078443068012], [747, 1292.7907182289684, 0.6200846890548422], [771, 1669.2165705953105, 0.6921045779920867], [795, 2085.745420067925, 0.7578956810999925], [819, 2539.3611392216067, 0.8169043646472541], [843, 3024.807056264548, 0.8683993408620441], [867, 3537.618146030759, 0.9119069702375682], [891, 4073.077684492037, 0.9470270791329252], [915, 4626.260632152372, 0.9734366404825968], [939, 5192.078933481574, 0.9908927449285838], [963, 5765.328315735664, 0.9992348350474719], [987, 6340.919570487991, 1.0], [1011, 6916.570697748017, 1.0], [1035, 7492.221825008071, 1.0], [1059, 8067.872952268497, 1.0], [1083, 8643.524079528588, 1.0], [1107, 9219.17520678872, 1.0], [1131, 9794.826334048752, 1.0], [1155, 10370.477461308712, 1.0], [1179, 10945.978803207761, 0.9985899917114763], [1203, 11518.471983740443, 0.9889123121653218], [1227, 12082.769906433325, 0.970138833878631], [1251, 12633.68228265162, 0.942442231190735], [1275, 13166.14194108393, 0.9060772513838206], [1299, 13675.251434473385, 0.8613783715732534], [1323, 14156.328085264193, 0.8087567222603794], [1347, 14604.947055843819, 0.748696305844258], [1371, 15016.982047229649, 0.6817495448736578], [1395, 15388.643251862879, 0.6085322009854982], [1419, 15716.512211427775, 0.5297177112642778], [1443, 15997.573259082323, 0.44603099411531827], [1467, 16229.241256900872, 0.35824178162416187], [1491, 16409.385373406432, 0.2671575397294795], [1515, 16536.348682491545, 0.17361604132833947], [1539, 16608.963403461574, 0.07847766062466313], [1563, 16626.561642025543, -0.017382540404168666], [1587, 16588.981533441514, -0.11308286063551264], [1611, 16496.568731313117, -0.20774306949527035], [1635, 16350.173228343294, -0.3004925031259051], [1659, 16151.141538287746, -0.390478072561667], [1683, 15901.30431101667, -0.4768721102539477], [1707, 15602.959494597897, -0.5588799827762071], [1731, 15258.851199274532, -0.6357473996879108], [1755, 14872.144457740247, -0.7067673513327517], [1779, 14446.396113862354, -0.7712866117585211], [1803, 13985.522107610866, -0.8287117469463535], [1827, 13493.761457100607, -0.8785145730867756], [1851, 12977.529829732175, -0.9201028050813491], [1875, 12440.117010932183, -0.9532736603489007], [1899, 11886.167621269718, -0.9777479180913606], [1923, 11320.735272410948, -0.9933023026868807], [1947, 10748.978333636605, -0.9997949134114497], [1971, 10175.686086701746, -1.0], [1995, 9602.385532383574, -1.0], [2019, 9029.084978065548, -1.0], [2043, 8455.222039230517, -1.0], [2067, 7879.222039230517, -1.0], [2091, 7303.222039230517, -1.0], [2115, 6727.222039230517, -1.0], [2139, 6151.222039230517, -1.0], [2163, 5575.57678999368, -0.9974949866040532], [2187, 5003.856031461424, -0.9861217131597484], [2211, 4441.308687313367, -0.9656673195222051], [2235, 3893.115213449038, -0.9363201686537468], [2259, 3364.3238820633183, -0.89835051624473], [2283, 2859.804292490014, -0.8521080219493539], [2307, 2384.202527430297, -0.7980185293963791], [2331, 1941.8983675288732, -0.7365801446273925], [2355, 1536.9649583056453, -0.6683586490759837], [2379, 1173.1313008670077, -0.5939822893293614], [2403, 853.7479118170013, -0.5141359916530983], [2427, 581.7559686035866, -0.42955505455701015], [2451, 359.66022443820475, -0.3410183774868508], [2475, 189.50594221311349, -0.24934128799829097], [2499, 72.86005983025734, -0.15536803346718894], [2523, 10.796760388769144, -0.05996400647942743], [2538, 0.0, 0.0], [2617, 0.0, 0.0]]],
    [51, [[0, 0.0, 0.0], [379, 0.0, 0.0], [403, 45.78210557197133, 0.15897413188506607], [427, 181.96397718198835, 0.3139048357205854], [451, 405.08189659500096, 0.4608515260402496], [475, 709.4609703990855, 0.5960766867942793], [499, 1087.3594680992826, 0.7161409332128481], [523, 1529.1657291861604, 0.8179904908487947], [547, 2024.0966057372052, 0.8990962751748315], [571, 2559.589129716332, 0.9573281854758321], [595, 3121.629713905724, 0.9911320481323551], [619, 3695.888162540119, 1.0], [643, 4271.5657011120875, 1.0], [667, 4847.243239684076, 1.0], [691, 5422.920778256075, 1.0], [715, 5998.598316828053, 1.0], [739, 6574.275855400063, 1.0], [763, 7149.953393972008, 1.0], [787, 7725.630932544083, 1.0], [811, 8301.308471116105, 1.0], [835, 8876.986009688137, 1.0], [859, 9451.209074002283, 0.9909853746717306], [883, 10013.115541477755, 0.9570099083773743], [907, 10548.377291991646, 0.8986145158834637], [931, 11043.336104944043, 0.8172892665848867], [955, 11485.362165765102, 0.7151093287413198], [979, 11863.176339631833, 0.594682017616057], [1003, 12167.137980024268, 0.45908026487289944], [1027, 12389.490928138797, 0.31176420688616147], [1051, 12524.561426017779, 0.1564928927864224], [1075, 12568.902893264223, -0.002771634820465575], [1099, 12521.383873089371, -0.16196543889859197], [1123, 12383.216903582543, -0.317026387057287], [1147, 12157.927577497816, -0.46399780457740714], [1171, 11851.2645800561, -0.5991294364846989], [1195, 11471.053000318767, -0.7189731424312816], [1219, 11026.994659171994, -0.8204708825483193], [1243, 10530.420548932761, -0.9010327491437551], [1267, 9994.001701550224, -0.9586030531180877], [1291, 9431.42586314943, -0.9917127787777259], [1315, 8857.030213430928, -1.0], [1339, 8282.284873060427, -1.0], [1363, 7707.539532689945, -1.0], [1387, 7132.794192319547, -1.0], [1411, 6558.048851949112, -1.0], [1435, 5983.303511578633, -1.0], [1459, 5408.5581712081475, -1.0], [1483, 4833.133223538345, -1.0], [1507, 4257.133223538345, -1.0], [1531, 3681.133223538345, -1.0], [1555, 3106.690258302974, -0.9905668309146243], [1579, 2544.8559721233632, -0.9560831505545966], [1603, 2009.975797275688, -0.8971759118918256], [1627, 1515.7134795625975, -0.815349925859439], [1651, 1074.6951640286015, -0.71269547272164], [1675, 698.1868546146488, -0.5918349049587468], [1699, 395.8066192064716, -0.4558556581369521], [1723, 175.27889192342946, -0.3082313810291564], [1747, 42.23714910232957, -0.1527331997521118], [1770, 0.0, 0.0], [1849, 0.0, 0.0]]],
    [52, [[0, 0.0, 0.0], [429, 0.0, 0.0], [453, 39.16856392586921, 0.13625243357939995], [477, 155.94369551305957, 0.26996352803756535], [501, 348.147340377576, 0.3986393445407185], [525, 612.194574352205, 0.5198798607342527], [549, 943.1604684070082, 0.6314237352330929], [573, 1334.8719469327398, 0.7311904854757644], [597, 1780.0229260789515, 0.8173192922554807], [621, 2270.310584615096, 0.8882037071558596], [645, 2796.590225638689, 0.9425216155405537], [669, 3349.436573046732, 0.9792791397765227], [693, 3919.363724200667, 0.9977651694528761], [717, 4494.796315647213, 1.0], [741, 5070.438152330505, 1.0], [765, 5646.079989013996, 1.0], [789, 6221.721825697728, 1.0], [813, 6797.363662381048, 1.0], [837, 7373.005499064081, 1.0], [861, 7948.64733574754, 1.0], [885, 8524.28917243084, 1.0], [909, 9099.93100911449, 1.0], [933, 9675.572845797917, 1.0], [957, 10251.214682481383, 1.0], [981, 10826.856519164827, 1.0], [1005, 11402.498355848365, 1.0], [1029, 11978.140192531566, 1.0], [1053, 12553.782029215163, 1.0], [1077, 13129.423865898698, 1.0], [1101, 13705.065702581975, 1.0], [1125, 14280.707539265484, 1.0], [1149, 14856.349375949147, 1.0], [1173, 15430.416381003533, 0.9914226275516135], [1197, 15994.188047053562, 0.9642686600332291], [1221, 16537.09076519648, 0.9190294548167867], [1245, 17048.94218158034, 0.8565534909761571], [1269, 17520.14232172197, 0.7780125297676042], [1293, 17941.85364180072, 0.684879637786966], [1317, 18306.166780266576, 0.5789015590266466], [1341, 18606.24890102453, 0.4620659540055052], [1365, 18836.47184596069, 0.33656412041473116], [1389, 18992.517693259982, 0.2047498944683558], [1413, 19071.459741726772, 0.06909550378003172], [1437, 19071.817402216187, -0.06785480023782485], [1461, 18993.583966665115, -0.20353246080878348], [1485, 18838.22673390492, -0.3353927900843865], [1509, 18608.6594898947, -0.46096269576517446], [1533, 18309.18785852109, -0.5778870649182143], [1557, 17945.428547929376, -0.683972935046218], [1581, 17524.204006955446, -0.777230623960759], [1605, 17053.414467415656, -0.8559110470539459], [1629, 16541.889772155035, -0.9185385220674674], [1653, 15999.223767874082, -0.9639384460934322], [1677, 15435.594368762728, -0.9912593257135837], [1701, 14861.57259098248, -1.0], [1725, 14285.930754298784, -1.0], [1749, 13710.288917615337, -1.0], [1773, 13134.64708093191, -1.0], [1797, 12559.00524424847, -1.0], [1821, 11983.363407564877, -1.0], [1845, 11408.25357607831, -1.0], [1869, 10834.207754986146, -1.0], [1893, 10260.16193389401, -1.0], [1917, 9686.116112802065, -1.0], [1941, 9112.070291710053, -1.0], [1965, 8538.024470618027, -1.0], [1989, 7963.97864952606, -1.0], [2013, 7389.932828433983, -1.0], [2037, 6815.887007341644, -1.0], [2061, 6241.841186249581, -1.0], [2085, 5666.65542746137, -1.0], [2109, 5090.65542746137, -1.0], [2133, 4514.65542746137, -1.0], [2157, 3938.8240464757364, -0.9980646556025705], [2181, 3368.1914729630835, -0.9801919895685355], [2205, 2813.179184585675, -0.9439125894524583], [2229, 2284.2095921703194, -0.8899077353277322], [2253, 1791.216058495629, -0.8191915683009895], [2277, 1343.4563626243694, -0.7330920462576396], [2301, 949.3388508216276, -0.6332260065353764], [2325, 616.2645387190682, -0.5214688038162998], [2349, 350.48812984179494, -0.3999190933986527], [2373, 157.00056038959792, -0.27085942117264517], [2397, 39.4352759292542, -0.1367133603695025], [2421, 0.0, 0.0], [2500, 0.0, 0.0]]],
    [53, [[0, 0.0, 0.0], [313, 0.0, 0.0], [337, 58.4726760680978, 0.20301128725258136], [361, 231.45548073495385, 0.39756772177176863], [385, 511.74416364256365, 0.5755665718106897], [409, 887.6654845051537, 0.7295946827405524], [433, 1343.5633709424874, 0.8532372142224902], [457, 1860.45095013848, 0.9413448003793017], [481, 2416.801299029047, 0.9902480064926859], [505, 2989.5704830969753, 1.0], [529, 3563.616304189096, 1.0], [553, 4138.061129179041, 1.0], [577, 4713.702965862511, 1.0], [601, 5289.344802545998, 1.0], [625, 5864.986639229459, 1.0], [649, 6440.628475912947, 1.0], [673, 7016.270312596387, 1.0], [697, 7591.912149279857, 1.0], [721, 8167.553985963326, 1.0], [745, 8743.195822646796, 1.0], [769, 9318.83765933028, 1.0], [793, 9894.479496013742, 1.0], [817, 10470.12133269723, 1.0], [841, 11045.763169380685, 1.0], [865, 11621.405006064144, 1.0], [889, 12197.046842747595, 1.0], [913, 12772.688679431061, 1.0], [937, 13348.330516114556, 1.0], [961, 13923.972352797993, 1.0], [985, 14499.614189481466, 1.0], [1009, 15075.256026164947, 1.0], [1033, 15650.897862848395, 1.0], [1057, 16226.539699531882, 1.0], [1081, 16801.411441148837, 0.9930358816732511], [1105, 17362.121981365046, 0.9482597652691189], [1129, 17885.49686897365, 0.8637721445318259], [1153, 18349.61805485101, 0.7431112171577063], [1177, 18735.048934008515, 0.5913300573314652], [1201, 19025.64831751423, 0.4147850015833297], [1225, 19209.246398001058, 0.22086945623834892], [1249, 19278.15440047731, 0.017704274148548443], [1273, 19229.486575131436, -0.18620233279688062], [1297, 19065.281047620454, -0.3823111030982499], [1321, 18792.414465837814, -0.56240933537685], [1345, 18422.314017608744, -0.7189548223246509], [1369, 17970.478879521597, -0.8453917055039623], [1393, 17455.831137803412, -0.9364250235358962], [1417, 16899.92336356792, -0.9882424560670166], [1441, 16325.972097981872, -1.0], [1465, 15750.330261298373, -1.0], [1489, 15174.688424614875, -1.0], [1513, 14599.046587931376, -1.0], [1537, 14023.404751247877, -1.0], [1561, 13447.76291456438, -1.0], [1585, 12872.121077880889, -1.0], [1609, 12296.479241197463, -1.0], [1633, 11720.837404514, -1.0], [1657, 11145.195567830546, -1.0], [1681, 10569.553731147083, -1.0], [1705, 9993.9118944636, -1.0], [1729, 9418.802062977295, -1.0], [1753, 8844.75624188516, -1.0], [1777, 8270.710420793053, -1.0], [1801, 7696.6645997009255, -1.0], [1825, 7122.618778608761, -1.0], [1849, 6548.572957516604, -1.0], [1873, 5974.527136424491, -1.0], [1897, 5400.48131533237, -1.0], [1921, 4826.4354942402715, -1.0], [1945, 4252.38967314818, -1.0], [1969, 3677.2039143598086, -1.0], [1993, 3101.2039143598086, -1.0], [2017, 2525.681723525089, -0.9949329466335706], [2041, 1962.5297159932102, -0.9535946522879398], [2065, 1434.8284835623367, -0.8722719017227809], [2089, 964.7046675412248, -0.7543745776925982], [2113, 571.8706741334472, -0.6048461437327357], [2137, 272.7981284401603, -0.4299563635283165], [2161, 80.02721520447858, -0.23703840819460284], [2185, 1.6408658083864793, -0.034181374624592926], [2189, 0.0, 0.0], [2268, 0.0, 0.0]]],
    [54, [[0, 0.0, 0.0], [629, 0.0, 0.0], [653, 24.883857249526574, 0.08675452599744195], [677, 99.34779070978588, 0.1728548740432062], [701, 222.83030041394488, 0.2576517990554467], [725, 394.40025874254917, 0.34050588449564045], [749, 612.7639316497732, 0.4207923639290566], [773, 876.2747341461176, 0.4979058321152761], [797, 1182.9456464760622, 0.5712648101044849], [821, 1530.4641973653615, 0.6403161299160084], [845, 1916.7619578795093, 0.704623349242937], [869, 2339.6672241211613, 0.7637560728496998], [893, 2794.961601975974, 0.817082353159628], [917, 3279.1837232372336, 0.8641967779817816], [941, 3788.6522969925495, 0.9047411606569249], [965, 4319.494096579294, 0.9384072631659021], [989, 4867.673405728116, 0.964939139504229], [1013, 5429.022700031698, 0.9841350815075066], [1037, 5999.274330481759, 0.9958491523344672], [1061, 6574.092968201196, 0.9999922959494718], [1085, 7149.744028931362, 1.0], [1109, 7725.395156191766, 1.0], [1133, 8301.046283451846, 1.0], [1157, 8876.697410711959, 1.0], [1181, 9452.348537972017, 1.0], [1205, 10027.9972748969, 0.9999161163892285], [1229, 10602.545646218327, 0.9949869335131127], [1253, 11172.076126710954, 0.9824933784298113], [1277, 11732.258870029347, 0.9625304331915079], [1301, 12278.835095850129, 0.9352498657692636], [1325, 12807.649467180876, 0.900859076239461], [1349, 13314.681681243299, 0.8596195200280304], [1373, 13796.077033760303, 0.8118447201997888], [1397, 14248.175724283708, 0.7578978839043454], [1421, 14667.540679768279, 0.6981891410995923], [1445, 15050.983684864636, 0.6331724265452463], [1469, 15395.589620275032, 0.5633420287711647], [1493, 15698.73862490139, 0.4892288322566723], [1517, 15958.126013297075, 0.41139628138985923], [1541, 16171.779797001276, 0.33043609689057873], [1565, 16338.075676549175, 0.2469637772633476], [1589, 16455.74939018322, 0.16161391947959464], [1613, 16523.906325382453, 0.07503539446447696], [1637, 16542.02832013987, -0.012113585933854878], [1661, 16509.97760228093, -0.09917047298933158], [1685, 16427.997836874227, -0.1854734181141392], [1709, 16296.712273771682, -0.2703663045518534], [1733, 16117.119009361708, -0.3532037354945508], [1757, 15890.583398557046, -0.43335594070187555], [1781, 15618.8276747062, -0.5102135643190108], [1805, 15303.917856342101, -0.5831922974948149], [1829, 14948.248040309365, -0.6517373205805178], [1853, 14554.52220068117, -0.7153275211372487], [1877, 14125.73363183963, -0.7734794556849885], [1901, 13666.840375733496, -0.8255752153900423], [1925, 13180.090861088727, -0.8714174573709954], [1949, 12668.928184059754, -0.9106887212870985], [1973, 12137.206798914885, -0.943092879706466], [1997, 11588.936184152608, -0.9683855870374459], [2021, 11028.250608776652, -0.9863761220319487], [2045, 10459.37795758067, -0.9969288259309959], [2069, 9886.60718198873, -1.0], [2093, 9312.744243153698, -1.0], [2117, 8736.744243153698, -1.0], [2141, 8160.744243153698, -1.0], [2165, 7584.744243153698, -1.0], [2189, 7008.744243153698, -1.0], [2213, 6432.762144683992, -0.9996789142433975], [2237, 5858.3142456130945, -0.9936656848019265], [2261, 5289.511832928331, -0.9800889743811607], [2285, 4730.684457599532, -0.9590521247716032], [2309, 4186.0857436459755, -0.9307152620743355], [2333, 3659.86101084406, -0.8952940778698381], [2357, 3156.015721813916, -0.8530581874392785], [2381, 2678.3849936561674, -0.8043290775349935], [2405, 2230.604406206973, -0.7494776593211059], [2429, 1816.0823291100369, -0.6889214451105531], [2453, 1437.9739783435025, -0.6231213703883427], [2477, 1099.157399675555, -0.5525782853108299], [2501, 802.2115618553635, -0.47782914238665497], [2525, 549.3967262873257, -0.39944290935755766], [2549, 342.6372426086982, -0.31801623838897114], [2573, 183.50690112542816, -0.23416892453520624], [2597, 73.21695359899331, -0.14853918804800076], [2621, 12.606893566386134, -0.06177881643807323], [2638, 0.0, 0.0], [2717, 0.0, 0.0]]],
    [55, [[0, 0.0, 0.0], [413, 0.0, 0.0], [437, 41.12371486095972, 0.14288295849617325], [461, 163.65096726620803, 0.2828338421202446], [485, 365.06739803880265, 0.4169807445684811], [509, 641.2397777039688, 0.5425708619657396], [533, 986.5008237298534, 0.657026982646755], [557, 1393.7654977884945, 0.7580003736419948], [581, 1854.6763965221444, 0.8434189785942486], [605, 2359.775252278071, 0.9115299380454747], [629, 2898.6970244771114, 0.9609355595429018], [653, 3460.382598702106, 0.9906219994283617], [677, 4033.471335710836, 1.0], [701, 4609.105566380476, 1.0], [725, 5184.739797050061, 1.0], [749, 5760.374027719681, 1.0], [773, 6336.008258389284, 1.0], [797, 6911.64248905897, 1.0], [821, 7487.276719728678, 1.0], [845, 8062.910950398367, 1.0], [869, 8638.545181068002, 1.0], [893, 9214.179411737663, 1.0], [917, 9789.81364240732, 1.0], [941, 10365.447873076959, 1.0], [965, 10941.082103746623, 1.0], [989, 11516.716334416265, 1.0], [1013, 12092.350565085915, 1.0], [1037, 12667.984795755594, 1.0], [1061, 13243.619026425247, 1.0], [1085, 13819.253257094817, 1.0], [1109, 14394.887487764492, 1.0], [1133, 14970.521718434116, 1.0], [1157, 15546.155949103759, 1.0], [1181, 16121.790179773365, 1.0], [1205, 16697.424410442873, 1.0], [1229, 17273.058641112435, 1.0], [1253, 17846.97906130471, 0.9906383244989652], [1277, 18409.63270927415, 0.9609000893101031], [1301, 18949.43381716806, 0.9113753356757954], [1325, 19455.266989435066, 0.8430838599954568], [1349, 19916.71628636946, 0.7574318964429113], [1373, 20324.279705497596, 0.6561831602842995], [1397, 20669.564843488675, 0.541422530070291], [1421, 20945.461709587245, 0.41551311654656503], [1445, 21146.289132055685, 0.2810476023040109], [1469, 21267.911742874752, 0.14079485416597823], [1493, 21307.825131795034, -0.0023570923486764643], [1517, 21265.207416276484, -0.14546050244235764], [1541, 21140.936165406274, -0.28556864076252314], [1565, 20937.570329303027, -0.4197964495450824], [1589, 20659.29754611149, -0.545379956714309], [1613, 20311.847911622775, -0.6597331906289627], [1637, 19902.375987146814, -0.7605014295054418], [1661, 19439.313475289044, -0.8456096890249433], [1685, 18932.195597280213, -0.9133054496845918], [1709, 18391.46474703709, -0.962194744065845], [1733, 17828.255465040398, -0.9912708609238784], [1757, 17254.164171348988, -1.0], [1781, 16678.529940679335, -1.0], [1805, 16102.895710009674, -1.0], [1829, 15527.261479339999, -1.0], [1853, 14951.627248670331, -1.0], [1877, 14375.993018000627, -1.0], [1901, 13800.358787330973, -1.0], [1925, 13224.724556661415, -1.0], [1949, 12649.090325991783, -1.0], [1973, 12073.4560953221, -1.0], [1997, 11498.607699088447, -1.0], [2021, 10923.96610139055, -1.0], [2045, 10349.324503692762, -1.0], [2069, 9774.682905994989, -1.0], [2093, 9200.041308297063, -1.0], [2117, 8625.399710599173, -1.0], [2141, 8050.758112901392, -1.0], [2165, 7476.116515203554, -1.0], [2189, 6901.474917505722, -1.0], [2213, 6326.833319807913, -1.0], [2237, 5752.191722110052, -1.0], [2261, 5176.248322205975, -1.0], [2285, 4600.248322205975, -1.0], [2309, 4024.2483222059745, -1.0], [2333, 3450.0661636091427, -0.9902635782118754], [2357, 2887.387407756337, -0.9601183351300386], [2381, 2347.8131980949092, -0.9101775814705576], [2405, 1842.4683580804285, -0.8414709848078857], [2429, 1381.771977485314, -0.7554151227775348], [2453, 975.2225938767269, -0.6537842763871258], [2477, 631.2023538392004, -0.5386738482772757], [2501, 356.8041917032351, -0.41245716016664263], [2525, 157.68558897116418, -0.27773652022199125], [2549, 37.9519295965747, -0.13728956923557833], [2572, 0.0, 0.0], [2651, 0.0, 0.0]]],
    [56, [[0, 0.0, 0.0], [479, 0.0, 0.0], [503, 34.45914318940506, 0.11960952494618997], [527, 137.34180919534145, 0.23750169916444702], [551, 307.17081113470164, 0.3519838296080588], [575, 541.5077482177654, 0.4614121845580403], [599, 836.9880162487417, 0.5642155942842269], [623, 1189.369116533543, 0.6589180098632497], [647, 1593.5915695759145, 0.7441596962540219], [671, 2043.911282608778, 0.8187254815526457], [695, 2533.888870528964, 0.8815415285348591], [719, 3056.4212057006, 0.9316934297566047], [743, 3604.001635920496, 0.9684607075470141], [767, 4168.763670320899, 0.9913151665232646], [791, 4742.5939886646065, 0.9999284815975625], [815, 5318.255335974234, 1.0], [839, 5893.918051851324, 1.0], [863, 6469.580767728632, 1.0], [887, 7045.243483605889, 1.0], [911, 7620.906199483186, 1.0], [935, 8196.568915360342, 1.0], [959, 8772.231631237526, 1.0], [983, 9347.89434711479, 1.0], [1007, 9923.542814525144, 0.9996590107950611], [1031, 10496.730413748777, 0.9893543432403031], [1055, 11059.883029432083, 0.9648367007932825], [1079, 11604.910462100928, 0.9264583016849197], [1103, 12123.98289701939, 0.8747704865209645], [1127, 12609.643386597776, 0.8105157977728998], [1151, 13054.914976227914, 0.7346173124798886], [1175, 13453.400934579804, 0.6481653814077954], [1199, 13799.37664846543, 0.5524019651687202], [1223, 14087.871862113097, 0.44870279232734966], [1247, 14314.742079411648, 0.3385575958090146], [1271, 14476.728103366295, 0.2235487115313942], [1295, 14571.50285742748, 0.10532834671001924], [1319, 14597.704816061812, -0.014405155600915863], [1343, 14554.957564304575, -0.13393171475115187], [1367, 14443.875205303038, -0.2515342230170274], [1391, 14266.053538166165, -0.3655232134157468], [1415, 14024.047132859476, -0.4742611304347656], [1439, 13721.332631483501, -0.5761858550063881], [1463, 13362.258803149349, -0.669833145768315], [1487, 12951.984069954677, -0.7538576742228137], [1511, 12496.402401559415, -0.827052351603931], [1535, 12002.058642950638, -0.8883656698054954], [1559, 11476.054491793631, -0.9369168072511284], [1583, 10926.017381513937, -0.9720047120096689], [1607, 10359.86790955381, -0.9931303181172518], [1631, 9785.654049846184, -1.0], [1655, 9210.150492115907, -1.0], [1679, 8634.646934385564, -1.0], [1703, 8059.143376655375, -1.0], [1727, 7483.639818925323, -1.0], [1751, 6908.1362611952645, -1.0], [1775, 6332.17763138438, -1.0], [1799, 5756.17763138438, -1.0], [1823, 5180.17763138438, -1.0], [1847, 4604.231946040247, -0.999167945271475], [1871, 4031.4993045366955, -0.9871001010138465], [1895, 3469.819799728412, -0.960835064206066], [1919, 2927.271915320388, -0.9207505977361262], [1943, 2411.6589701196094, -0.8674232255940049], [1967, 1930.3968850208753, -0.8016199408837626], [1991, 1490.4075218315306, -0.7242871743701258], [2015, 1098.0191280138147, -0.6365371822219493], [2039, 758.8753192210479, -0.539632048733949], [2063, 477.85390870710035, -0.4349655341112084], [2087, 258.99675106370523, -0.32404302839484556], [2111, 105.45160932406452, -0.20845989984607594], [2135, 19.426881542417505, -0.08987854919798709], [2153, 0.0, 0.0], [2232, 0.0, 0.0]]],
    [57, [[0, 0.0, 0.0], [346, 0.0, 0.0], [370, 51.48031867737807, 0.17854093463660425], [394, 204.266953104568, 0.3513444509136293], [418, 453.450100141768, 0.5128575025848081], [442, 791.0222517874215, 0.6578898628270565], [466, 1206.1355166911258, 0.7817809123371218], [490, 1685.4502174718396, 0.8805494084745252], [514, 2213.5635616557515, 0.9510214226147653], [538, 2773.5046108807487, 0.990932334442143], [562, 3347.3274403606756, 1.0], [586, 3922.4562038509357, 1.0], [610, 4497.584967341001, 1.0], [634, 5072.7553249895645, 1.0], [658, 5648.383218380595, 1.0], [682, 6224.011111771844, 1.0], [706, 6799.639005162988, 1.0], [730, 7375.266898554111, 1.0], [754, 7950.894791945242, 1.0], [778, 8526.52268533641, 1.0], [802, 9102.150578727595, 1.0], [826, 9677.778472118773, 1.0], [850, 10253.406365509918, 1.0], [874, 10829.03425890107, 1.0], [898, 11404.662152292234, 1.0], [922, 11980.290045683394, 1.0], [946, 12555.91793907455, 1.0], [970, 13131.545832465725, 1.0], [994, 13707.173725856877, 1.0], [1018, 14282.801619248103, 1.0], [1042, 14858.429512639284, 1.0], [1066, 15434.057406030463, 1.0], [1090, 16009.685299421695, 1.0], [1114, 16585.313192812806, 1.0], [1138, 17160.941086203922, 1.0], [1162, 17736.56897959512, 1.0], [1186, 18312.196872986337, 1.0], [1210, 18887.82476637746, 1.0], [1234, 19463.452659768773, 1.0], [1258, 20039.08055315991, 1.0], [1282, 20614.582662854173, 0.9980933283897734], [1306, 21182.844268191584, 0.9709991634455384], [1330, 21726.44711750088, 0.912647873520457], [1354, 22227.892264500566, 0.8249178264140041], [1378, 22671.0378480838, 0.7106331121463061], [1402, 23041.618709832183, 0.5734726335751101], [1426, 23327.70559918901, 0.4178516800049851], [1450, 23520.089184166463, 0.2487797960148833], [1474, 23612.576506020356, 0.07169952080311705], [1498, 23602.190334813506, -0.10768881085936581], [1522, 23489.26500847711, -0.2836105662910742], [1546, 23277.435670244762, -0.4504027042625518], [1570, 22973.521250913673, -0.6026960721538631], [1594, 22587.30496281424, -0.7355882426373791], [1618, 22131.21937153569, -0.8448013261555093], [1642, 21619.9461831653, -0.9268196791015246], [1666, 21069.943630160717, -0.9790030747839379], [1690, 20498.916669628226, -0.9996716941234128], [1714, 19923.297761393063, -1.0], [1738, 19347.669868001918, -1.0], [1762, 18772.041974610744, -1.0], [1786, 18196.41408121952, -1.0], [1810, 17620.786187828337, -1.0], [1834, 17045.158294437177, -1.0], [1858, 16469.53040104601, -1.0], [1882, 15893.902507654864, -1.0], [1906, 15318.274614263646, -1.0], [1930, 14742.646720872486, -1.0], [1954, 14167.01882748134, -1.0], [1978, 13591.39093409024, -1.0], [2002, 13015.763040699087, -1.0], [2026, 12440.135147307985, -1.0], [2050, 11864.507253916818, -1.0], [2074, 11289.004143000973, -1.0], [2098, 10713.875379510828, -1.0], [2122, 10138.746616020697, -1.0], [2146, 9563.617852530486, -1.0], [2170, 8988.489089040253, -1.0], [2194, 8413.360325550108, -1.0], [2218, 7838.231562059977, -1.0], [2242, 7263.102798569802, -1.0], [2266, 6687.974035079649, -1.0], [2290, 6112.845271589482, -1.0], [2314, 5537.716508099278, -1.0], [2338, 4962.587744609089, -1.0], [2362, 4387.168568948968, -1.0], [2386, 3811.1685689489677, -1.0], [2410, 3235.1685689489677, -1.0], [2434, 2661.7905060576936, -0.9855767697223283], [2458, 2105.8895403644647, -0.9394335473216331], [2482, 1585.3830921410647, -0.8630103136427872], [2506, 1117.048230044973, -0.7587703577436554], [2530, 715.9804176634257, -0.6300735628743713], [2554, 395.1069534911794, -0.4810681100438141], [2578, 164.77029564216537, -0.31655677301398], [2602, 32.39470165681814, -0.14184211432891392], [2621, 0.0, 0.0], [2700, 0.0, 0.0]]],
    [58, [[0, 0.0, 0.0], [554, 0.0, 0.0], [578, 28.846352404681596, 0.10047843465902041], [602, 115.09344047941694, 0.19993987411269926], [626, 257.86831197977176, 0.29737761670024054], [650, 455.7258671661159, 0.391805443663689], [674, 706.6634854200321, 0.4822676011878733], [698, 1008.1412948230276, 0.5678484740884887], [722, 1357.1078795391643, 0.6476818532361109], [746, 1750.0311648034804, 0.7209597029154644], [770, 2182.9341669125574, 0.7869403393808273], [794, 2652.9142617357375, 0.8451201240771858], [818, 3154.3359193703723, 0.8947298656176604], [842, 3681.7223851159156, 0.935213701879286], [866, 4229.694517047148, 0.9661587130867588], [890, 4792.663207251408, 0.9872492718624836], [914, 5364.8863886096315, 0.9982702625061157], [938, 5940.599041799203, 1.0], [962, 6516.505048301558, 1.0], [986, 7092.411054804001, 1.0], [1010, 7668.31706130665, 1.0], [1034, 8244.223067809085, 1.0], [1058, 8820.129074311499, 1.0], [1082, 9396.035080813755, 1.0], [1106, 9971.941087316136, 1.0], [1130, 10547.847093818804, 1.0], [1154, 11123.753100321232, 1.0], [1178, 11699.659106823772, 1.0], [1202, 12275.520248828485, 0.9993467775515225], [1226, 12849.02084526744, 0.9906051752840968], [1250, 13414.570917145304, 0.9717597759424941], [1274, 13966.402068228934, 0.9430027954523699], [1298, 14498.88583007393, 0.904627544107875], [1322, 15006.591070268396, 0.8570254349178719], [1346, 15484.339387923355, 0.8006819913417039], [1370, 15927.257931397431, 0.7361718951341076], [1394, 16330.829099536295, 0.6641531248091633], [1418, 16690.936619490003, 0.5853602445091486], [1442, 17003.907531135508, 0.5005969117288034], [1466, 17266.54964987666, 0.4107276803137238], [1490, 17476.184125716558, 0.31666918233895425], [1514, 17630.672766511016, 0.2193807788096778], [1538, 17728.439846718, 0.11985477454256692], [1562, 17768.48817920011, 0.019106297033297442], [1586, 17750.409286155482, -0.08183705745909246], [1610, 17674.387565436304, -0.18194570500430218], [1634, 17541.198409760567, -0.28019857536631426], [1658, 17352.20029800056, -0.37559352653247513], [1682, 17109.320939213667, -0.46715756618196064], [1706, 16815.037610740997, -0.5539567758384796], [1730, 16472.351890918035, -0.6351058364844943], [1754, 16084.759044114311, -0.70977705847936], [1778, 15656.21237036171, -0.7772088236798822], [1802, 15191.082883195195, -0.8367133536562359], [1826, 14694.11472697051, -0.8876837247714193], [1850, 14170.376788393081, -0.9296000585718951], [1874, 13625.210995794509, -0.9620348243508233], [1898, 13065.538368784737, -0.9846148695111173], [1922, 12496.582202433849, -0.9971894218088939], [1946, 11923.287558859105, -1.0], [1970, 11349.592375832726, -1.0], [1994, 10775.897192806224, -1.0], [2018, 10202.20200977999, -1.0], [2042, 9628.5068267538, -1.0], [2066, 9054.811643727546, -1.0], [2090, 8481.116460701109, -1.0], [2114, 7906.460937269047, -1.0], [2138, 7330.460937269047, -1.0], [2162, 6754.460937269047, -1.0], [2186, 6178.460937269047, -1.0], [2210, 5602.4656975042735, -0.9998535913111287], [2234, 5028.027270627438, -0.9930266658526739], [2258, 4460.444946241057, -0.9760679414398243], [2282, 3905.5097370122576, -0.9491504470477147], [2306, 3368.883617755982, -0.9125488204589094], [2330, 2856.0417566030997, -0.8666365061485202], [2354, 2372.216652147329, -0.8118819450498272], [2378, 1922.3447465367021, -0.7488437950760212], [2402, 1511.0160592134098, -0.6781652311628357], [2426, 1142.4273551863307, -0.6005673829884339], [2450, 820.3393256579075, -0.5168419773251494], [2474, 548.0382178891832, -0.4278432600927805], [2498, 328.3023057914643, -0.33447928053230386], [2522, 163.37354334342035, -0.2377026264271273], [2546, 54.934690052309634, -0.1385007048999291], [2570, 4.092141847030689, -0.03788566794960846], [2579, 0.0, 0.0], [2658, 0.0, 0.0]]],
    [59, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 18.23855171893241, 0.05267952873262114], [170, 70.96266295139438, 0.09710819996977343], [199, 151.02123950074238, 0.13122684286160402], [227, 247.5254184290227, 0.15438610018455257], [255, 356.3632378896943, 0.1679341063508635], [284, 475.2004163680528, 0.1718337006443374], [313, 593.1638226104972, 0.1654232665924896], [341, 699.4998067036523, 0.1494510013491279]]],
    [60, [[0, 1148.6536860839753, 0.13150334629453153], [208, 1476.886038435126, 0.0], [6896, 1476.886038435126, 0.0], [7375, 1038.443019217563, -0.057208118373899136], [7854, 600.0, 0.0], [8354, 600.0, 0.0]]],
    [61, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 31.18841819529795, 0.08974840663875748], [170, 120.3817850049233, 0.1632565932612368], [199, 253.85108863723016, 0.21697811015221005], [227, 411.8129383057945, 0.25007217587126884], [255, 585.8162787495137, 0.26472064222112346], [284, 769.7221573317654, 0.2604467478300961], [313, 943.7676443512979, 0.2363861837075627], [341, 1089.538139511988, 0.1943803091377186]]],
    [62, [[0, 1949.1338585935202, 0.2543803091377185], [208, 2584.0671102012657, 0.0], [6915, 2584.0671102012657, 0.0], [7394, 1592.0335551006328, -0.12944070395363164], [7873, 600.0, 0.0], [8373, 600.0, 0.0]]],
    [63, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 642.7772807651077, 0.12226079609744549], [170, 762.7016038200807, 0.21692944786554205], [199, 937.198599570529, 0.27907882108444393], [227, 1136.2315234399232, 0.30822853187099697], [255, 1344.6671332996848, 0.30706300557958505], [284, 1548.7274210989287, 0.27389725201636467], [313, 1718.3876354830516, 0.20821221990395025], [341, 1828.3269590364976, 0.11393560830164559]]],
    [64, [[0, 2215.338149819972, 0.1739356083016455], [208, 2649.481428140879, 0.0], [6923, 2649.481428140879, 0.0], [7402, 1324.7407140704395, -0.17285238962296967], [7881, 0.0, 0.0], [8381, 0.0, 0.0]]],
    [65, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 619.3227715719917, 0.05630937520930071], [170, 676.6181981609951, 0.10704661870396781], [199, 766.5415019791709, 0.1500676431092211], [227, 879.2863049041315, 0.18428349207915387], [255, 1012.6072293268872, 0.21130609994789706], [284, 1167.2245886196356, 0.23171062012555818], [313, 1333.35824971292, 0.24439892121380552], [341, 1499.653317697734, 0.24932800284318068]]],
    [66, [[0, 2536.6600310797116, 0.23534284876553296], [208, 3124.075781598482, 0.0], [6901, 3124.075781598482, 0.0], [7380, 1562.037890799241, -0.20381496487464001], [7859, 0.0, 0.0], [8359, 0.0, 0.0]]],
    [67, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 30.028050517405838, 0.08586362578424257], [170, 114.32904557215547, 0.15262017128835267], [199, 237.24079425684684, 0.19681406724959236], [227, 377.8213950012439, 0.21807500563879093], [255, 525.6221128197806, 0.21830251092262634], [284, 671.2348673561985, 0.19636450305131473], [313, 793.7269663732648, 0.15186384563713282], [341, 875.3272817059521, 0.08748866352592423]]],
    [68, [[0, 1058.5105201796398, 0.147488663525924], [208, 1426.642224340346, 0.0], [972, 1426.642224340346, 0.0], [1201, 713.321112170173, -0.1946837096534315], [1430, 0.0, 0.0], [1860, 0.0, 0.0]]],
    [69, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 43.45457347124803, 0.12452829612165861], [170, 166.23451528261683, 0.22313779988957586], [199, 346.89382931970084, 0.2908483312530243], [227, 556.0719798652918, 0.326904896637512], [255, 779.801746503034, 0.33415671247966483], [284, 1006.2132718502619, 0.31130129024380826], [313, 1205.9645809245783, 0.2575468956034831], [341, 1353.3592693397636, 0.17632698070846486]]],
    [70, [[0, 2203.0719858773027, 0.23632698070846497], [208, 2792.9441297256312, 0.0], [866, 2792.9441297256312, 0.0], [1095, 1396.4720648628156, -0.3811332054756593], [1324, 0.0, 0.0], [1753, 0.0, 0.0]]],
    [71, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 617.8530125692256, 0.05138878689623379], [170, 668.9516038200807, 0.09357418470764726], [199, 745.5023691514527, 0.12452721816208727], [227, 836.2315234399232, 0.1437548476604706], [255, 936.3633637187611, 0.15251140265722823], [284, 1042.4774210989285, 0.15054198885846998], [313, 1143.3119036789335, 0.13734021070273825], [341, 1228.3269590364976, 0.11393560830164542]]],
    [72, [[0, 1502.310972284849, 0.0925954855548939], [208, 1733.429304229864, 0.0], [972, 1733.429304229864, 0.0], [1201, 1166.714652114932, -0.15467102950735045], [1430, 600.0, 0.0], [1860, 600.0, 0.0]]],
    [73, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 631.4849305444958, 0.0907410967310768], [170, 721.9284602721565, 0.16597455113470047], [199, 858.0955686425182, 0.22213069053194165], [227, 1020.4989027204549, 0.25824851195342396], [255, 1201.1978805365038, 0.27658201118108483], [284, 1394.8889197926392, 0.27682188245617045], [313, 1582.1080038340124, 0.25798443872487364], [341, 1744.2761039364518, 0.22169466264293997]]],
    [74, [[0, 2805.9120511639962, 0.28169466264293985], [208, 3509.021929120774, 0.0], [874, 3509.021929120774, 0.0], [1104, 2049.7576682751733, -0.3961067703447474], [1333, 600.0, 0.0], [1762, 600.0, 0.0]]],
    [75, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 42.68141134740259, 0.1219398360383796], [170, 162.20152732191895, 0.21605066814732474], [199, 335.8262593369137, 0.2774128706374555], [227, 533.4231468144851, 0.3055849300740457], [255, 739.6938996024029, 0.3032279459658672], [284, 940.5904147679126, 0.2686027857801629], [313, 1105.9912953368248, 0.2012289959756443], [341, 1210.6288874724155, 0.10510423526567637]]],
    [76, [[0, 1519.9437473493665, 0.16510423526567647], [208, 1932.043918572495, 0.0], [933, 1932.043918572495, 0.0], [1162, 966.0219592862475, -0.2636522814645872], [1391, 0.0, 0.0], [1820, 0.0, 0.0]]],
    [77, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 18.726284097356885, 0.05431240203815162], [170, 73.5067850049233, 0.10157896168228943], [199, 158.00297342769204, 0.13970230869103173], [227, 261.8129383057945, 0.16783533376600565], [255, 381.6643939590519, 0.18744484075994503], [284, 516.5971573317654, 0.1987691162511487], [313, 656.2297784492391, 0.20095017910695684], [341, 789.538139511988, 0.1943803091377186]]],
    [78, [[0, 1487.1448432958694, 0.1787641478261213], [208, 1933.3401562698682, 0.0], [927, 1933.3401562698682, 0.0], [1156, 969.8291256796979, -0.2632531290368532], [1386, 0.0, 0.0], [1815, 0.0, 0.0]]],
    [79, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 631.7849056699328, 0.09174537980990656], [170, 723.4931981609951, 0.16872425028291518], [199, 862.389617188709, 0.22734344457039946], [227, 1029.2863049041314, 0.266520334184417], [255, 1216.7591141173489, 0.28858190140907536], [284, 1420.3495886196356, 0.29338825170450544], [313, 1620.8961156149787, 0.2798349258144113], [341, 1799.6533176977339, 0.24932800284318063]]],
    [80, [[0, 3083.2837895440134, 0.3093280028431807], [208, 3855.3664846405923, 0.0], [861, 3855.3664846405923, 0.0], [1090, 2227.683242320296, -0.4442366927730066], [1319, 600.0, 0.0], [1748, 600.0, 0.0]]],
    [81, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 642.9696073549204, 0.12290468395140187], [170, 763.7048226758864, 0.21869239490795633], [199, 939.9516935551586, 0.28242093555573045], [227, 1141.865494232792, 0.3135319428085078], [255, 1354.6440905007958, 0.314756636717547], [284, 1565.051319964587, 0.2845186437016542], [313, 1743.2563150218612, 0.2222214803769813], [341, 1863.8316051651414, 0.1316524975873959]]],
    [82, [[0, 2374.816628574201, 0.19165249758739583], [208, 2853.1812625523407, 0.0], [899, 2853.1812625523407, 0.0], [1128, 1730.2722941808022, -0.3068042712145035], [1358, 600.0, 0.0], [1787, 600.0, 0.0]]],
    [83, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 17.853012569225587, 0.05138878689623379], [170, 68.95160382008066, 0.09357418470764726], [199, 145.50236915145277, 0.12452721816208727], [227, 236.23152343992325, 0.1437548476604706], [255, 336.36336371876115, 0.15251140265722823], [284, 442.4774210989286, 0.15054198885846998], [313, 543.3119036789334, 0.13734021070273825], [341, 628.3269590364974, 0.11393560830164542]]],
    [84, [[0, 902.310972284849, 0.0925954855548939], [208, 1133.429304229864, 0.0], [972, 1133.429304229864, 0.0], [1201, 566.714652114932, -0.15467102950735045], [1430, 0.0, 0.0], [1860, 0.0, 0.0]]],
    [85, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 30.99243937330697, 0.08909229152105275], [170, 119.35951528261683, 0.1614601683106285], [199, 251.04571411016275, 0.21357252979184602], [227, 406.07197986529184, 0.2446680545322488], [255, 575.6498617125723, 0.25688091101848654], [284, 753.0882718502619, 0.24962365866486091], [313, 918.4267150225196, 0.22211089100287706], [341, 1053.3592693397636, 0.17632698070846486]]],
    [86, [[0, 1769.3901052422627, 0.23632698070846497], [208, 2359.2622490905915, 0.0], [902, 2359.2622490905915, 0.0], [1132, 1175.7761269695854, -0.3212487814301247], [1361, 0.0, 0.0], [1790, 0.0, 0.0]]],
    [87, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 642.490184615347, 0.12129963038484841], [170, 761.2040455721555, 0.21429780286730005], [199, 933.088909466385, 0.27408986871077073], [227, 1127.821395001244, 0.3003118477440541], [255, 1329.7739976102425, 0.2955783123838047], [284, 1524.3598673561985, 0.25804213463026215], [313, 1681.2648322753237, 0.18729985023773865], [341, 1775.3272817059521, 0.08748866352592423]]],
    [88, [[0, 1985.8711928498844, 0.147488663525924], [208, 2354.002897010591, 0.0], [950, 2354.002897010591, 0.0], [1179, 1477.0014485052955, -0.23935629053092128], [1408, 600.0, 0.0], [1837, 600.0, 0.0]]],
    [89, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 618.0453391590382, 0.052032674750190175], [170, 669.9548226758864, 0.09533713175006163], [199, 748.2554631360822, 0.12786933263337374], [227, 841.8654942327919, 0.1490582585979815], [255, 946.340320919872, 0.1602050337951903], [284, 1058.801319964587, 0.16116338054375956], [313, 1168.1805832177436, 0.15134947117576955], [341, 1263.8316051651414, 0.1316524975873959]]],
    [90, [[0, 1620.5263053977806, 0.11216905672683439], [208, 1900.500270987959, 0.0], [961, 1900.500270987959, 0.0], [1190, 1250.2501354939795, -0.17747001514573676], [1419, 600.0, 0.0], [1848, 600.0, 0.0]]],
    [91, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 31.18841819529795, 0.08974840663875748], [170, 120.3817850049233, 0.1632565932612368], [199, 253.85108863723016, 0.21697811015221005], [227, 411.8129383057945, 0.25007217587126884], [255, 585.8162787495137, 0.26472064222112346], [284, 769.7221573317654, 0.2604467478300961], [313, 943.7676443512979, 0.2363861837075627], [341, 1089.538139511988, 0.1943803091377186]]],
    [92, [[0, 1949.1338585935202, 0.2543803091377185], [208, 2584.0671102012657, 0.0], [888, 2584.0671102012657, 0.0], [1118, 1287.8112299016693, -0.35185931983856567], [1347, 0.0, 0.0], [1776, 0.0, 0.0]]],
    [93, [[0, 0.0, 0.0], [113, 0.0, 0.0], [141, 42.68141134740259, 0.1219398360383796], [170, 162.20152732191895, 0.21605066814732474], [199, 335.8262593369137, 0.2774128706374555], [227, 533.4231468144851, 0.3055849300740457], [255, 739.6938996024029, 0.3032279459658672], [284, 940.5904147679126, 0.2686027857801629], [313, 1105.9912953368248, 0.2012289959756443], [341, 1210.6288874724155, 0.10510423526567637]]],
    [94, [[0, 1519.9437473493665, 0.16510423526567647], [208, 1932.043918572495, 0.0], [933, 1932.043918572495, 0.0], [1162, 966.0219592862475, -0.2636522814645872], [1391, 0.0, 0.0], [1820, 0.0, 0.0]]],
    [95, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 618.2385517189324, 0.05267952873262114], [170, 670.9626629513943, 0.09710819996977343], [199, 751.0212395007424, 0.13122684286160402], [227, 847.5254184290227, 0.15438610018455257], [255, 956.3632378896943, 0.1679341063508635], [284, 1075.2004163680529, 0.1718337006443374], [313, 1193.1638226104972, 0.1654232665924896], [341, 1299.4998067036522, 0.1494510013491279]]],
    [96, [[0, 1748.6536860839753, 0.13150334629453153], [208, 2076.886038435126, 0.0], [950, 2076.886038435126, 0.0], [1179, 1338.443019217563, -0.20154012533230428], [1408, 600.0, 0.0], [1837, 600.0, 0.0]]],
    [97, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 631.4849305444958, 0.0907410967310768], [170, 721.9284602721565, 0.16597455113470047], [199, 858.0955686425182, 0.22213069053194165], [227, 1020.4989027204549, 0.25824851195342396], [255, 1201.1978805365038, 0.27658201118108483], [284, 1394.8889197926392, 0.27682188245617045], [313, 1582.1080038340124, 0.25798443872487364], [341, 1744.2761039364518, 0.22169466264293997]]],
    [98, [[0, 2805.9120511639962, 0.28169466264293985], [208, 3509.021929120774, 0.0], [874, 3509.021929120774, 0.0], [1104, 2049.7576682751733, -0.3961067703447474], [1333, 600.0, 0.0], [1762, 600.0, 0.0]]],
    [99, [[0, 0.0, 0.0], [500, 0.0, 0.0], [899, 360.0, 0.0], [1298, 60.0, 0.0], [1698, 430.0, 0.0], [2097, 100.0, 0.0], [2496, 0.0, 0.0], [2996, 0.0, 0.0]]],
    [100, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1154, 360.0, 0.0], [1808, 60.0, 0.0], [2462, 430.0, 0.0], [3116, 100.0, 0.0], [3770, 0.0, 0.0], [4270, 0.0, 0.0]]],
    [101, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1137, 360.0, 0.0], [1774, 60.0, 0.0], [2412, 430.0, 0.0], [3049, 100.0, 0.0], [3686, 0.0, 0.0], [4186, 0.0, 0.0]]],
    [102, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1113, 360.0, 0.0], [1726, 60.0, 0.0], [2338, 430.0, 0.0], [2951, 100.0, 0.0], [3564, 0.0, 0.0], [4064, 0.0, 0.0]]],
    [103, [[0, 600.0, 0.0], [500, 600.0, 0.0], [1057, 960.0, 0.0], [1614, 660.0, 0.0], [2170, 1030.0, 0.0], [2727, 700.0, 0.0], [3284, 600.0, 0.0], [3784, 600.0, 0.0]]],
    [104, [[0, 600.0, 0.0], [500, 600.0, 0.0], [1260, 960.0, 0.0], [2019, 660.0, 0.0], [2779, 1030.0, 0.0], [3538, 700.0, 0.0], [4298, 600.0, 0.0], [4798, 600.0, 0.0]]],
    [105, [[0, 600.0, 0.0], [500, 600.0, 0.0], [1154, 960.0, 0.0], [1808, 660.0, 0.0], [2462, 1030.0, 0.0], [3116, 700.0, 0.0], [3770, 600.0, 0.0], [4270, 600.0, 0.0]]],
    [106, [[0, 600.0, 0.0], [500, 600.0, 0.0], [899, 960.0, 0.0], [1298, 660.0, 0.0], [1698, 1030.0, 0.0], [2097, 700.0, 0.0], [2496, 600.0, 0.0], [2996, 600.0, 0.0]]],
    [107, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1260, 360.0, 0.0], [2019, 60.0, 0.0], [2779, 430.0, 0.0], [3538, 100.0, 0.0], [4298, 0.0, 0.0], [4798, 0.0, 0.0]]],
    [108, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1137, 360.0, 0.0], [1774, 60.0, 0.0], [2412, 430.0, 0.0], [3049, 100.0, 0.0], [3686, 0.0, 0.0], [4186, 0.0, 0.0]]],
    [109, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1057, 360.0, 0.0], [1614, 60.0, 0.0], [2170, 430.0, 0.0], [2727, 100.0, 0.0], [3284, 0.0, 0.0], [3784, 0.0, 0.0]]],
    [110, [[0, 0.0, 0.0], [500, 0.0, 0.0], [1113, 360.0, 0.0], [1726, 60.0, 0.0], [2338, 430.0, 0.0], [2951, 100.0, 0.0], [3564, 0.0, 0.0], [4064, 0.0, 0.0]]],
    [116, [[0, 0.0, 0.0], [1373, 0.0, 0.0], [2057, 26.0, 0.0], [2446, 150.0, 0.0], [2724, 18.0, 0.0], [3236, 215.0, 0.0], [3615, 70.0, 0.0], [3905, 22.0, 0.0], [4194, 245.0, 0.0], [4678, 20.0, 0.0], [5400, 180.0, 0.0], [5855, 24.0, 0.0], [6339, 200.0, 0.0], [6803, 16.0, 0.0], [7284, 230.0, 0.0], [7906, 22.0, 0.0], [8256, 120.0, 0.0], [8623, 30.0, 0.0], [9053, 0.0, 0.0], [10428, 0.0, 0.0]]],
    [117, [[0, 0.0, 0.0], [1509, 0.0, 0.0], [2280, 1050.0, 0.062], [3074, 2250.0, 0.0], [3818, 2330.0, 0.0], [4399, 2390.0, 0.0], [4938, 330.0, 0.0], [5974, 190.0, 0.0], [7193, 90.0, 0.0], [8090, 0.0, 0.0], [10408, 0.0, 0.0]]],
    [118, [[0, 0.0, 0.0], [235, 0.0, 0.0], [1476, 0.0, 0.0], [3756, 0.0, 0.0], [4561, 0.0, 0.0], [5702, 260.0, 0.0], [6473, 600.0, 0.0], [6708, 600.0, 0.0]]],
    [119, [[0, 0.0, 0.0], [282, 0.0, 0.0], [1772, 180.0, 0.0], [3141, 780.0, 0.0], [4511, 320.0, 0.0], [5880, 490.0, 0.0], [7250, 415.0, 0.0], [7773, 600.0, 0.0], [8055, 600.0, 0.0]]],
    [120, [[0, 0.0, 0.0], [286, 0.0, 0.0], [736, 42.0, 0.0], [1636, 68.0, 0.0], [2617, 44.0, 0.0], [3844, 12.0, 0.0], [5235, 0.0, 0.0], [6298, 100.0, 0.0], [7893, 600.0, 0.0], [8179, 600.0, 0.0]]],
    [121, [[0, 0.0, 0.0], [273, 0.0, 0.0], [1405, 0.0, 0.0], [2810, 0.0, 0.0], [3902, 0.0, 0.0], [5385, 0.0, 0.0], [6322, 150.0, 0.0], [7532, 600.0, 0.0], [7805, 600.0, 0.0]]],
    [122, [[0, 600.0, 0.0], [113, 600.0, 0.0], [141, 643.4545734712481, 0.12452829612165861], [170, 766.2345152826168, 0.22313779988957586], [199, 946.8938293197009, 0.2908483312530243], [227, 1156.0719798652917, 0.326904896637512], [255, 1379.8017465030339, 0.33415671247966483], [284, 1606.213271850262, 0.31130129024380826], [313, 1805.9645809245783, 0.2575468956034831], [341, 1953.3592693397636, 0.17632698070846486]]],
    [123, [[0, 2803.0719858773027, 0.23632698070846497], [208, 3392.9441297256312, 0.0], [866, 3392.9441297256312, 0.0], [1095, 1996.4720648628156, -0.3811332054756593], [1324, 600.0, 0.0], [1753, 600.0, 0.0]]],
    [124, [[0, 0.0, 0.0], [105, 0.0, 0.0], [320, 510.0, 0.0], [842, 510.0, 0.0], [1057, 0.0, 0.0], [1162, 0.0, 0.0]]],
    [125, [[0, 600.0, 0.0], [98, 600.0, 0.0], [393, 1950.0, 0.0], [458, 1950.0, 0.0], [731, 400.0, 0.0], [884, 820.0, 0.0], [1004, 600.0, 0.0], [1091, 600.0, 0.0]]],
    [126, [[0, 0.0, 0.0], [150, 0.0, 0.0], [3885, 2400.0, 0.0], [35941, 2400.0, 0.0], [39676, 0.0, 0.0], [39826, 0.0, 0.0]]],
    [127, [[0, 0.0, 0.0], [1614, 0.0, 0.0], [1615, 0.0004502135620255983, 0.00021485886015148163], [1625, 1.4973626974986007, 0.012130800569147095], [1650, 16.928900738542996, 0.03847624960862105], [1675, 46.65434366282383, 0.05975247197772166], [1700, 87.59878926097201, 0.07586652334505098], [1710, 106.42325111060312, 0.08086680303165393], [1715, 116.26088033727814, 0.08305946259667961], [1718, 122.28544785962538, 0.08427723440599758], [1719, 124.312796016879, 0.0846669049832845], [1721, 128.3950617279418, 0.08556612514828049], [1725, 136.72686227359296, 0.08797698924922769], [1750, 193.8183058409596, 0.10211733284156327], [1775, 259.01833666760297, 0.11501096217614303], [1800, 331.58855475352084, 0.1266899716985866], [1825, 410.8098193579735, 0.13718646355205993], [1850, 495.982248999478, 0.14653253472829417], [1875, 586.4252214558131, 0.15476028517961518], [1900, 681.4773737640131, 0.16190181284514435], [1925, 780.4966022203755, 0.16798921744036], [1950, 882.8600623804533, 0.17305460175975892], [1975, 987.9641690590636, 0.1771300600713251], [2000, 1095.2245963302778, 0.18024768309032876], [2025, 1204.0762775274284, 0.1824395866378836], [2050, 1313.9734052431083, 0.18373785385013736], [2075, 1424.3894313291687, 0.18417459604809966], [2100, 1534.8170668967196, 0.18378190039432712], [2125, 1644.7682823161322, 0.1825918767887439], [2150, 1753.7743072170335, 0.1806366213941146], [2175, 1861.3856304883136, 0.17794822895211834], [2200, 1967.1720002781192, 0.17455879420443426], [2225, 2070.722423993858, 0.17050041757708334], [2250, 2171.6451683021955, 0.1658052080225995], [2275, 2269.567759129056, 0.16050526217744238], [2300, 2364.1369816596252, 0.15463267288851054], [2325, 2455.018880338348, 0.14821953679226377], [2350, 2541.8987588689247, 0.141297954314723], [2375, 2624.4811802143186, 0.1339000239871287], [2400, 2702.4899665967546, 0.12605785665679528], [2425, 2775.6681994977102, 0.1178035347493278], [2450, 2843.7782196579265, 0.10916916153291821], [2475, 2906.601627077403, 0.100186847854881], [2500, 2963.9392810153977, 0.09088867045647929], [2525, 3015.611299990429, 0.08130674681675978], [2550, 3061.4570617802738, 0.07147316883523065], [2575, 3101.335203421971, 0.061420034095741954], [2600, 3135.123621211811, 0.05117944681387598], [2625, 3162.7194707053554, 0.04078349604696995], [2650, 3184.039166717414, 0.030264282221044894], [2675, 3199.0183833220613, 0.019653911446463702], [2700, 3207.6120538526325, 0.008984484149247388], [2710, 3209.2551411937457, 0.00470736457221695], [2715, 3209.6916569887476, 0.0025678284979827972], [2718, 3209.8303211594366, 0.0012839412496153575], [2719, 3209.856000038259, 0.0008559652542317052], [2721, 3209.8765432152827, 0.00012227682570179846], [2723, 3209.8794777317294, 0.00012230903697248624], [2725, 3209.8882812737547, 0.000244515755791023], [2750, 3210.4934985940886, 0.0017727870726957915], [2775, 3212.015483505007, 0.0033003705842323443], [2800, 3214.4536448180825, 0.004826623959767554], [2825, 3217.8070333117043, 0.006350979712503127], [2850, 3222.07433910861, 0.007872897829959886], [2875, 3227.253888085801, 0.009391716086308103], [2900, 3233.3436373371674, 0.01090679688786622], [2925, 3240.3411697093816, 0.012417525378320228], [2950, 3248.24368744036, 0.013923263963988573], [2975, 3257.0480049320695, 0.015423392104215354], [3000, 3266.750540694796, 0.016917247573170847], [3025, 3277.347308504143, 0.018404118880728976], [3050, 3288.8339078164445, 0.019883215903367574], [3075, 3301.2055134924103, 0.021353983470362433], [3100, 3314.456864882262, 0.02281555661435656], [3125, 3328.5822543305444, 0.02426734984813568], [3150, 3343.575515160585, 0.025708349464063453], [3175, 3359.43000920352, 0.027137944395387116], [3200, 3376.1386139388355, 0.028555265885188415], [3225, 3393.6937093166753, 0.02995943475525564], [3250, 3412.0871643350292, 0.031349598354305876], [3275, 3431.31032344606, 0.03272492582103344], [3300, 3451.3539928697664, 0.034084537029836305], [3325, 3472.2084268928074, 0.035427368061391455], [3350, 3493.863314233647, 0.03675255015878064], [3375, 3516.3077645546246, 0.03805908477261254], [3400, 3539.530295206177, 0.03934596103742175], [3425, 3563.518818281808, 0.04061222872072297], [3450, 3588.2606280713567, 0.041856736743284266], [3475, 3613.742388994093, 0.04307859455821016], [3500, 3639.950124094401, 0.04427655161028572], [3525, 3666.8692041839863, 0.0454495553488717], [3550, 3694.484337710403, 0.04659647648471339], [3575, 3722.7795614337174, 0.047716324047541996], [3600, 3751.7382319891326, 0.04880784748214258], [3625, 3781.343018412989, 0.0498697573902973], [3650, 3811.5758957064872, 0.05090118785725886], [3675, 3842.4181395109986, 0.05190080495746466], [3700, 3873.8503219620675, 0.05286748413861156], [3725, 3905.8523087919602, 0.053799975792874946], [3750, 3938.403257741236, 0.05469719989529645], [3775, 3971.481618343344, 0.0555578168359716], [3800, 4005.0651331341114, 0.056380810065093094], [3825, 4039.1308403423823, 0.057164959343936055], [3850, 4073.6550781079873, 0.05790901695945649], [3875, 4108.613490271836, 0.05861201467875313], [3900, 4143.981033777736, 0.05927260341801835], [3925, 4179.731987719267, 0.05988980357566712], [3950, 4215.839964063589, 0.06046251996849605], [3975, 4252.277920075355, 0.060989634675934205], [4000, 4289.018172461018, 0.061470084726048896], [4025, 4326.032413247495, 0.061902778725198], [4050, 4363.291727404514, 0.0622868185473635], [4075, 4400.766612214173, 0.06262120564315408], [4100, 4438.426998385156, 0.06290503809699051], [4125, 4476.2422729050695, 0.06313734009684897], [4150, 4514.181303616196, 0.06331737836262617], [4175, 4552.212465497903, 0.06344425476830413], [4200, 4590.303668629685, 0.0635174198275005], [4225, 4628.422387806097, 0.0635358105682826], [4250, 4666.535693767965, 0.06349923561780693], [4275, 4704.610286008169, 0.06340677221790732], [4300, 4742.6125271075525, 0.06325793151518154], [4325, 4780.508478548939, 0.06305233644828452], [4350, 4818.263937950799, 0.06278958911328421], [4375, 4855.844477662882, 0.06246919118287526], [4400, 4893.215484654098, 0.06209105928671002], [4425, 4930.342201622904, 0.061654865627739724], [4450, 4967.189769255295, 0.061160636732893174], [4475, 5003.723269548756, 0.06060804101556034], [4500, 5039.907770120717, 0.0599972414268753], [4525, 5075.708369411669, 0.059328313758063196], [4550, 5111.0902426922285, 0.05860155359490211], [4575, 5146.018688779537, 0.057817021570372155], [4600, 5180.459177365997, 0.056975130746650386], [4625, 5214.377396857844, 0.056076195657321165], [4650, 5247.739302621314, 0.055120727893154246], [4675, 5280.511165531712, 0.054109420943859725], [4700, 5312.659620716419, 0.053042915245290104], [4725, 5344.151716384265, 0.05192172807255701], [4750, 5374.954962629974, 0.05074681439509731], [4775, 5405.037380102653, 0.04951913676147038], [4800, 5434.367548426104, 0.04823944550480518], [4825, 5462.914654259567, 0.046909121920180034], [4850, 5490.648538884399, 0.04552891255116264], [4875, 5517.5397452069965, 0.044100410908261736], [4900, 5543.559564065573, 0.04262454922354663], [4925, 5568.680079728568, 0.04110293616577109], [4950, 5592.874214479145, 0.039536822290150056], [4975, 5616.115772175171, 0.037928000059158265], [5000, 5638.379480680225, 0.03627764613156614], [5025, 5659.641033062439, 0.03458768181493117], [5050, 5679.877127459885, 0.0328597006197621], [5075, 5699.0655055152465, 0.031095618169274527], [5100, 5717.184989284163, 0.02929707723827353], [5125, 5734.2155165270615, 0.02746608629422553], [5150, 5750.138174296022, 0.02560449085346287], [5175, 5764.935230733068, 0.023714373279896485], [5200, 5778.590165000944, 0.021797817832217938], [5225, 5791.0876952717335, 0.019856732554520324], [5250, 5802.413804702206, 0.017893402552241845], [5275, 5812.555765331576, 0.01590992345275784], [5300, 5821.5021598405865, 0.013908517833745766], [5325, 5829.242901118108, 0.011891482169327595], [5350, 5835.769249584875, 0.009860961351175016], [5375, 5841.073828231214, 0.00781926322209377], [5400, 5845.150635330027, 0.0057687410996247], [5425, 5847.995054793595, 0.0037116933526704084], [5450, 5849.603864147239, 0.0016504543509654466], [5460, 5849.900961541388, 0.000825330441026987], [5465, 5849.975240100271, 0.0004126623783425505], [5470, 5849.999999994124, 4.9448090067016885e-05], [5475, 5850.034649286804, 0.000577476081768206], [5500, 5851.247206444201, 0.0034640152080100957], [5525, 5854.190627205646, 0.00634645781853275], [5550, 5858.861508150878, 0.009221590365389904], [5575, 5865.254440479237, 0.012086034454720597], [5600, 5873.362005488073, 0.014936538642965992], [5625, 5883.174768511425, 0.017769529373860372], [5650, 5894.681271441813, 0.020581734361257983], [5675, 5907.868023991871, 0.023369805527787925], [5700, 5922.719493883565, 0.02613022616060334], [5725, 5939.218096179756, 0.028859621655404524], [5750, 5957.344182003694, 0.03155459088096298], [5775, 5977.07602691515, 0.03421158870272241], [5800, 5998.389819238064, 0.0368271666199386], [5825, 6021.259648653895, 0.03939779465630029], [5850, 6045.657495396873, 0.041919975046766915], [5875, 6071.553220400089, 0.044390094444679555], [5900, 6098.914556760091, 0.04680472140231964], [5925, 6127.707102895043, 0.049160170571364376], [5950, 6157.894317780057, 0.051452985871947014], [5975, 6189.437518652434, 0.053679553957408636], [6000, 6222.2958815748025, 0.05583630316626416], [6025, 6256.426445250679, 0.05791965994224786], [6050, 6291.784118476736, 0.05992604314997151], [6075, 6328.321691613425, 0.061852063026890385], [6100, 6365.989852441027, 0.06369414980630002], [6125, 6404.737206759326, 0.06544883225008864], [6150, 6444.510304068552, 0.06711269217400209], [6175, 6485.253668652944, 0.06868245160755274], [6200, 6526.909836364485, 0.07015489321323305], [6225, 6569.41939737959, 0.0715266272284983], [6250, 6612.721045174745, 0.07279460495131691], [6275, 6656.7516319379165, 0.07395594631513328], [6300, 6701.446230597699, 0.07500751166844564], [6325, 6746.738203621801, 0.07594665021315448], [6350, 6792.559278697858, 0.07677079262672729], [6375, 6838.839631373, 0.07747721231983935], [6400, 6885.507974689355, 0.0780636393452975], [6425, 6932.491655814397, 0.07852795154879762], [6450, 6979.716759620442, 0.07886803246037742], [6475, 7027.108219129019, 0.07908220140961929], [6500, 7074.589932694852, 0.07916870572444167], [6510, 7093.590666115273, 0.07916720695296438], [6515, 7103.0902795965885, 0.07915865201842583], [6517, 7106.889787000306, 0.07915385253909334], [6518, 7108.789448338491, 0.07915114300279431], [6519, 7110.689041449693, 0.07914824398843241], [6520, 7112.5885613433, 0.07942439689638073], [6521, 7114.501444101459, 0.08042464401114556], [6522, 7116.44894930916, 0.08186635227502846], [6525, 7122.498785426404, 0.08618115619659267], [6550, 7184.848445766712, 0.12141927830574178], [6575, 7267.8759237008635, 0.15502365802907053], [6600, 7370.450455479337, 0.1864915115371938], [6625, 7491.138055695133, 0.2153155776341009], [6650, 7628.200224595886, 0.2409892507178786], [6675, 7779.596942886546, 0.2630157723615411], [6700, 7942.995851906565, 0.28091967957758845], [6725, 8115.789347422284, 0.29426146284095006], [6750, 8295.12098207102, 0.3026541245768991], [6775, 8477.92209422427, 0.305780239765833], [6800, 8660.958990145122, 0.30340983130372473], [6825, 8840.890341104252, 0.2954168697518374], [6834, 8904.25379047189, 0.2911574104776567], [6839, 8939.034223306187, 0.2884764361018218], [6841, 8952.854056680197, 0.28734135639751907], [6842, 8959.74332745042, 0.2867603825507103], [6843, 8966.618548606531, 0.2861705449201205], [6844, 8973.479506169177, 0.2859035854877826], [6845, 8980.341879970736, 0.2856289484043372], [6847, 8994.02291507039, 0.2844136247404094], [6850, 9014.434892487874, 0.2825845172083063], [6869, 9140.624999996351, 0.27083334922887536], [6870, 9147.22863985807, 0.2794763493814874], [6875, 9183.384805105221, 0.3233032278634103], [6881, 9233.816088164838, 0.3774359053447066], [6887, 9292.18266230401, 0.43357662207199604], [6893, 9358.801213020402, 0.49211622202468175], [6900, 9447.459102921324, 0.5640465171078782], [6906, 9533.34359555599, 0.6294202004634523], [6912, 9628.928477490994, 0.6988885881279807], [6918, 9734.855976771076, 0.7732051434080252], [6925, 9872.533822082009, 0.8672618984443639], [6931, 10003.678732602655, 0.9554863027005921], [6937, 10148.122579547204, 1.052237701060221], [6943, 10307.219115165739, 1.1593377583570448], [6946, 10392.764400345815, 1.2174750736448912], [6950, 10513.574885900967, 1.300529644746954], [6953, 10609.59867676159, 1.367515574202116], [6956, 10710.606690402226, 1.4390690125765102], [6959, 10816.947984345219, 1.515765859494422], [6962, 10929.016519481396, 1.598280812231678], [6965, 11047.259042413645, 1.6874096255984719], [6968, 11172.184787572838, 1.7840977079686124], [6971, 11304.377527253406, 1.8894771869781832], [6973, 11396.87155971771, 1.9652225205391003], [6975, 11493.11790570047, 2.045908346796447], [6978, 11645.077325677357, 2.1774164300344028], [6981, 11807.015166458454, 2.323496403278113], [6984, 11980.076317704583, 2.4869133198990307], [6987, 12165.63019160228, 2.6711758020307266], [6990, 12365.333323985937, 2.880804314978983], [6991, 12435.383296687087, 2.957291121674643], [6993, 12581.215459076622, 3.1217245577863646], [6994, 12657.190526146873, 3.2102816286775724], [6996, 12815.800552078865, 3.4018598398688478], [6997, 12898.679962986826, 3.505718056355059], [6999, 13072.281197392695, 3.7320499927773194], [7000, 13159.94774957083, 3.5755733051701095], [7001, 13244.002649535987, 3.4308444658866692], [7002, 13324.711779450276, 3.296558111287595], [7003, 13402.31198626704, 3.171594706448862], [7004, 13477.015158447395, 3.054989133488561], [7006, 13618.472916820934, 2.8436134887973212], [7007, 13685.55428457314, 2.7474773332869513], [7009, 13813.128015280461, 2.5714956564115705], [7010, 13873.865659536112, 2.4907178461338235], [7012, 13989.779310743734, 2.341635369399834], [7013, 14045.144069224489, 2.27267280858238], [7015, 14151.107006114848, 2.1445068568937127], [7018, 14299.207609008266, 1.973241050260791], [7021, 14435.751565977856, 1.8227592552951437], [7023, 14521.038879797754, 1.7320507519495245], [7025, 14602.13407670924, 1.6479489469626665], [7028, 14716.559467879026, 1.5325347476391469], [7031, 14823.083402803048, 1.428147963148755], [7034, 14922.4363156978, 1.3330859549872305], [7037, 15015.238390641638, 1.2459741393892423], [7040, 15102.020310850528, 1.1656902264197317], [7043, 15183.239316870744, 1.0913084679486926], [7046, 15259.29178969346, 1.0220580747954953], [7050, 15353.249094634204, 0.9366021799905865], [7053, 15418.516701108503, 0.8769764387276759], [7056, 15479.61352990142, 0.8206787659522281], [7062, 15590.171334750594, 0.716589844766228], [7068, 15686.43877609244, 0.6218399410803006], [7075, 15782.27742854275, 0.5205670352855425], [7081, 15851.378286369969, 0.4400105164374205], [7087, 15909.21692024969, 0.3639702223760347], [7093, 15956.37156785027, 0.2914734106222264], [7100, 15998.475120676336, 0.21027738057455278], [7104, 16016.487349246405, 0.16510066037274856], [7109, 16032.95613617117, 0.10951780495815909], [7114, 16042.798031956127, 0.054595686075723876], [7119, 16046.072148083478, 0.0], [7369, 16046.072148083478, 0.0], [7370, 16045.941245793809, -0.01090874093279126], [7375, 16041.356390860332, -0.06554345948946623], [7381, 16027.16851457263, -0.1316524920487912], [7387, 16003.38529626275, -0.19891236130812706], [7393, 15969.796562207945, -0.2679491823679806], [7400, 15917.804353632439, -0.3516652138083979], [7406, 15861.782791130163, -0.42705194497708965], [7412, 15794.6052894615, -0.506780421953105], [7418, 15715.567471956672, -0.5919874259537512], [7421, 15671.332271763897, -0.6370702408275973], [7425, 15607.172397276541, -0.7002075146071243], [7431, 15499.092052889035, -0.8025848273973678], [7434, 15439.334025051066, -0.8578607927726503], [7437, 15375.483475840605, -0.9163311422829186], [7440, 15307.295597911425, -0.9784179193654077], [7443, 15234.492745855887, -1.0446136002428827], [7446, 15156.758815272975, -1.1154969797644296], [7450, 15044.810646204634, -1.2185034885684822], [7453, 14954.070334810143, -1.3032253339891515], [7456, 14856.96514838835, -1.395498342541638], [7459, 14752.906780416231, -1.4966057165111122], [7462, 14641.204206173728, -1.608130757328278], [7465, 14521.038879879765, -1.7320507557390856], [7468, 14391.431909798901, -1.8708683531561592], [7471, 14251.199884743892, -2.0277993409460273], [7473, 14151.107006216385, -2.1445068531041516], [7475, 14045.144069332096, -2.2726728123719413], [7476, 13989.779310854607, -2.341635369399834], [7478, 13873.86565965404, -2.4907178423442624], [7480, 13750.396575593673, -2.656936184545581], [7482, 13618.472916955572, -2.8436134925868823], [7483, 13549.011611406191, -2.9459049111816658], [7485, 13402.31198641721, -3.1715947026593003], [7486, 13324.711779606361, -3.2965581074980337], [7487, 13244.002649698428, -3.4308444658866692], [7488, 13159.947749740124, -3.5755733013805484], [7489, 13072.2811975694, -3.7320499851981968], [7490, 12984.123172323387, -3.6155968018647395], [7492, 12815.80055223994, -3.4018598360792867], [7493, 12735.34648736611, -3.3035281679379596], [7495, 12581.215459224431, -3.1217245615759257], [7497, 12435.383296827107, -2.957291121674643], [7500, 12230.534191194829, -2.737974462737232], [7503, 12040.46434044744, -2.545818692093841], [7506, 11863.40380818488, -2.375886583649844], [7509, 11697.895408742474, -2.2243670779668414], [7512, 11542.725250341535, -2.0882714125036723], [7515, 11396.871559810761, -1.9652225205391003], [7518, 11259.4663026139, -1.8533060445709753], [7521, 11129.765941611155, -1.7509628643589772], [7525, 10967.720938039603, -1.627212251757252], [7528, 10853.646911696247, -1.5425878283773877], [7531, 10745.442739738297, -1.4640320462907157], [7534, 10642.697822505354, -1.3908326044050527], [7537, 10545.048915591986, -1.3223828280691425], [7540, 10452.173234939373, -1.2581626947394395], [7543, 10363.782779481648, -1.197723804580164], [7546, 10279.619622427228, -1.1406773713436753], [7550, 10173.58060841011, -1.0693131457628622], [7556, 10026.795795783257, -0.9709755242207998], [7562, 9893.517833999544, -0.8814389010088537], [7568, 9772.591237287557, -0.7992068200716553], [7575, 9645.845855391082, -0.7109155641652856], [7581, 9548.584751227427, -0.6406952441769438], [7587, 9461.123697289735, -0.5746858657100044], [7593, 9382.904418388005, -0.5122380950221365], [7600, 9302.703310719546, -0.4431553027946695], [7609, 9216.138015098224, -0.3591864469854044], [7619, 9140.625000009173, -0.27083334922887536], [7620, 9134.117491981628, -0.2714588617891422], [7625, 9101.355268271745, -0.27457494221986656], [7634, 9041.445504009604, -0.2801343953251489], [7639, 9007.645536108512, -0.2831950306851164], [7641, 8994.022915083857, -0.28441362095084816], [7642, 8987.18968950048, -0.2850216939502085], [7643, 8980.341879984262, -0.285628944614776], [7644, 8973.479506182728, -0.2859035854877826], [7645, 8966.618548620114, -0.28617054113055923], [7647, 8952.854056693835, -0.28734136018708034], [7650, 8932.104089741579, -0.28903054195931566], [7675, 8755.124620916677, -0.2999586778666222], [7700, 8573.281358800814, -0.30524418737816933], [7725, 8389.945810273319, -0.3049537175077906], [7750, 8208.415415380803, -0.29926520710432664], [7775, 8031.851202770099, -0.2884526584997123], [7800, 7863.225209750664, -0.2728690693250731], [7825, 7705.278365675172, -0.25292888684210385], [7850, 7560.488851163585, -0.22909085638881754], [7875, 7431.050310794226, -0.20184219806651524], [7900, 7318.858756116193, -0.17168566538809193], [7925, 7225.506584553119, -0.1391291201950177], [7950, 7152.2818833757465, -0.10467813922332424], [7959, 7131.047371677856, -0.09190858918373122], [7963, 7122.498785449971, -0.08618115240703142], [7965, 7118.431035946763, -0.08330641397454504], [7966, 7116.4489493327865, -0.08186635227502846], [7967, 7114.501444125107, -0.0804246459059262], [7968, 7112.588561366969, -0.07942438931725822], [7969, 7110.6890414733825, -0.07914823830409053], [7971, 7106.889787024032, -0.07915384685475145], [7975, 7099.290559151685, -0.07916275042892569], [8000, 7051.792296351559, -0.07914317355547003], [8025, 7004.344346677886, -0.07899524803178791], [8050, 6957.023301303965, -0.07872046505023414], [8075, 6909.904780279339, -0.0783204825438588], [8100, 6863.063311906961, -0.07779734498096028], [8125, 6816.572218776384, -0.07715293956304473], [8150, 6770.503510600494, -0.07638974087361323], [8175, 6724.927783964169, -0.07551011549367102], [8200, 6679.9141290482485, -0.07451667443092445], [8225, 6635.530043354267, -0.0734120040609317], [8250, 6591.841352412355, -0.07219911329533109], [8275, 6548.912137415589, -0.07088087083199449], [8300, 6506.8046696873225, -0.06946047127106188], [8325, 6465.579351849636, -0.06794088752333967], [8350, 6425.294665525602, -0.06632558324781711], [8375, 6386.00712537803, -0.06461774736029231], [8400, 6347.771239251932, -0.06282059340871152], [8425, 6310.639474162763, -0.06093783137354572], [8450, 6274.662227844324, -0.058972752488746956], [8475, 6239.887805548637, -0.0569290193652705], [8500, 6206.362401766168, -0.05480999144917101], [8525, 6174.130086520332, -0.05261935219399068], [8550, 6143.232795872364, -0.05036047051968731], [8575, 6113.710326262631, -0.04803717956747277], [8600, 6085.6003323048135, -0.045652889942478694], [8625, 6058.938327643513, -0.043211141094919484], [8650, 6033.757688483442, -0.04071559374096977], [8675, 6010.089659399337, -0.03816971722396071], [8700, 5987.963361038604, -0.035577096468841767], [8725, 5967.40579933553, -0.032941187555479694], [8750, 5948.441875866759, -0.03026555456623706], [8775, 5931.094398987684, -0.027553572105413572], [8800, 5915.384095407161, -0.024808859204010027], [8825, 5901.329621874828, -0.022034796150668015], [8850, 5888.9475766752785, -0.019234628704604496], [8875, 5878.252510647015, -0.016412025161116613], [8900, 5869.2569374679815, -0.01357028054371767], [8925, 5861.971342976735, -0.010712655769869645], [8950, 5856.404193327494, -0.00784264292027122], [8975, 5852.561941805901, -0.004963561650583869], [9000, 5850.4490341643295, -0.00207873351124969], [9009, 5850.112262747663, -0.0010394577050950222], [9013, 5850.034649299934, -0.0005774722922069485], [9018, 5850.000000007087, -4.9552303001595036e-05], [9021, 5849.99109290506, -0.00024743750752046856], [9025, 5849.9515060782405, -0.0005772998671697375], [9050, 5848.986725100705, -0.0026383058108573696], [9075, 5846.7861093866595, -0.004696378634131785], [9100, 5843.352150752328, -0.006749066490859452], [9125, 5838.6887357985825, -0.008794125960775999], [9150, 5832.801139199899, -0.010829262464540078], [9175, 5825.696014603437, -0.012852202265397256], [9200, 5817.381383162803, -0.014860574992781038], [9225, 5807.866619734333, -0.016852269861071058], [9250, 5797.162436772489, -0.018824997975267856], [9275, 5785.280865963196, -0.020776548126377744], [9300, 5772.23523764273, -0.02270482089746413], [9325, 5758.04015805436, -0.024607696029003513], [9350, 5742.711484498305, -0.02648316126396821], [9375, 5726.266298439298, -0.028329039499415856], [9400, 5708.722876638594, -0.030143583747606797], [9425, 5690.100660382212, -0.0319247116446301], [9450, 5670.420222882684, -0.033670691360991135], [9475, 5649.703234935834, -0.03537958453610675], [9500, 5627.972428917239, -0.03704982797595827], [9525, 5605.251561207543, -0.03867952689991701], [9550, 5581.5653731402135, -0.04026728674944024], [9575, 5556.939550566779, -0.04181137569503334], [9600, 5531.400682139017, -0.04331053370757823], [9625, 5504.9762164100875, -0.04476322411998504], [9650, 5477.694417857749, -0.04616808079542048], [9675, 5449.584321937665, -0.047523940338578534], [9700, 5420.675689274187, -0.04882962419590815], [9725, 5390.99895909618, -0.05008411865977298], [9750, 5360.585202032016, -0.05128617317495809], [9775, 5329.466072372895, -0.05243521362293298], [9800, 5297.67375991715, -0.05353003302843717], [9825, 5265.240941507051, -0.05457008758943023], [9850, 5232.200732372152, -0.05555462886756382], [9875, 5198.586637387222, -0.056482957688785966], [9900, 5164.432502358917, -0.057354613621403885], [9925, 5129.772465447831, -0.058169272657930066], [9950, 5094.640908836195, -0.0589263985754466], [9975, 5059.072410746064, -0.059625720420323575], [10000, 5023.101697912405, -0.06026695587024732], [10025, 4986.763598613156, -0.060850281139816303], [10050, 4950.092996355853, -0.0613753381154917], [10075, 4913.124784315715, -0.06184235227616833], [10100, 4875.893820618721, -0.06225115877593149], [10125, 4838.434884560544, -0.06260222373081584], [10150, 4800.782633844768, -0.06289556987818892], [10175, 4762.971562923657, -0.06313171070360112], [10200, 4725.035962519096, -0.06331085084336033], [10225, 4687.009880396751, -0.06343347346652686], [10250, 4648.927083461932, -0.06349999731961967], [10275, 4610.821021241015, -0.06351102304809804], [10300, 4572.724790808862, -0.06346728014250401], [10325, 4534.6711032144, -0.06336931429965867], [10350, 4496.692251454118, -0.06321797438128365], [10375, 4458.8200800368795, -0.06301384776937387], [10384, 4445.218269525713, -0.06292757840734944], [10388, 4439.17914367, -0.06288721768517765], [10390, 4436.161053193391, -0.06286647173207408], [10393, 4431.635802452173, -0.06292419811870785], [10396, 4427.076461614413, -0.06379778104322516], [10400, 4420.891339509535, -0.06505849796667461], [10425, 4379.506961754902, -0.07286915698993349], [10450, 4333.474077676149, -0.08055112440767212], [10475, 4282.874194707211, -0.08809011925829205], [10500, 4227.7972946858945, -0.0954721770085598], [10525, 4168.34179090077, -0.10268313606805651], [10550, 4104.614481103045, -0.10970917211731526], [10575, 4036.7304965018316, -0.11653651862767825], [10600, 3964.813246766301, -0.12315112959034497], [10625, 3888.994361054473, -0.1295396108010512], [10650, 3809.4136250960373, -0.13568843731566932], [10675, 3726.2189143539995, -0.14158399229321122], [10700, 3639.566123293166, -0.14721304258576612], [10725, 3549.6190907844057, -0.15256260136690494], [10750, 3456.549521677178, -0.1576194231726428], [10775, 3360.536904571823, -0.162370685075075], [10800, 3261.7684258254585, -0.16680353098763587], [10825, 3160.438879828815, -0.17090546104251791], [10850, 3056.7505755896805, -0.17466401137274562], [10875, 2950.9132396638943, -0.17806690758940624], [10900, 2843.143915471554, -0.1811019236204932], [10925, 2733.666859043297, -0.18375732224740202], [10950, 2622.713431238044, -0.18602124024861644], [10975, 2510.5219864776254, -0.1878821630422559], [11000, 2397.337758045439, -0.1893286177316137], [11025, 2283.412739995869, -0.19034955869301481], [11050, 2169.0055657241514, -0.190934038831377], [11075, 2054.3813832477904, -0.19107121147499126], [11100, 1939.811727250282, -0.1907504985373028], [11125, 1825.5743879418887, -0.1899617771528028], [11150, 1711.9532767913545, -0.18869473308313897], [11175, 1599.2382891846291, -0.18693967878865198], [11200, 1487.7251640677164, -0.1846869589409531], [11225, 1377.7153406334126, -0.1819271223742665], [11250, 1269.5158121101754, -0.17865110351067412], [11275, 1163.4389767145701, -0.17485006604071407], [11300, 1059.8024858308006, -0.17051524991984476], [11325, 958.9290894784688, -0.16563836643020596], [11350, 861.1464791351365, -0.16021131585830514], [11375, 766.7871279783034, -0.15422623912778968], [11400, 676.1881286137176, -0.1476755798535123], [11425, 589.6910283581225, -0.14055202110322776], [11450, 507.6416621450844, -0.13284863745373815], [11475, 430.3899831233188, -0.12455864878783508], [11479, 418.4985321749282, -0.12317739788159086], [11484, 403.8218870777317, -0.12147311766833958], [11485, 400.9097244312163, -0.12141269299566676], [11486, 397.9941286334433, -0.1215521057436793], [11488, 392.153333335169, -0.12180919360578929], [11492, 380.4382275088634, -0.12223566893491501], [11500, 356.91357628293844, -0.12273293978163714], [11525, 283.5101285239813, -0.12113770514095751], [11550, 212.53833015093, -0.11459500951123874], [11575, 147.01487629076846, -0.10296116125611357], [11600, 90.01174493156692, -0.08619605604091399], [11625, 44.59335736544154, -0.06436510605981974], [11650, 13.753237896481224, -0.03763904441456133], [11675, 0.3513341635136978, -0.006291884124704864], [11679, 0.0066460968191797655, -0.0008710970419237758], [11680, 0.0, 0.0], [13548, 0.0, 0.0]]],
    [128, [[0, 0.0, 0.0], [1874, 0.0, 0.0], [1898, 3.6851282123122044, 0.012795409483435766], [1922, 14.73990948613216, 0.02558872398464069], [1946, 33.16253383090862, 0.0383778488643937], [1970, 58.94998492498699, 0.05116069016943713], [1994, 92.09804060948304, 0.063935154975318], [2018, 132.60127357957415, 0.07669915172906089], [2042, 180.45305227309328, 0.08945059059161622], [2066, 235.64554195633534, 0.102187383780028], [2090, 298.16970600679156, 0.11490744590926479], [2114, 368.0153073927617, 0.1276086943336582], [2138, 445.170910349404, 0.1402890494878928], [2162, 529.6238822511333, 0.1529464352274917], [2186, 621.3603956799477, 0.16557877916874195], [2210, 720.3654306893733, 0.1781840130280044], [2234, 826.622777263672, 0.19076007296035213], [2258, 940.1150379718897, 0.20330489989748202], [2282, 1060.8236308163364, 0.2158164398848445], [2306, 1188.7287922749817, 0.22829264441793587], [2330, 1323.8095805373498, 0.2407314707776982], [2354, 1466.0438789332736, 0.2531308823649722], [2378, 1615.4083995540536, 0.26548884903394815], [2402, 1771.8786870653828, 0.2778033474245596], [2426, 1935.4291227113763, 0.290072361293767], [2450, 2106.0329285091175, 0.3022938818456753], [2474, 2283.6621716329987, 0.3144659080604325], [2498, 2468.2877689881416, 0.3265864470218552], [2522, 2659.87949197215, 0.338653514243727], [2546, 2858.4059714244027, 0.35066513399471705], [2570, 3063.83470276212, 0.3626193396218648], [2594, 3276.1320513022993, 0.37451417387257857], [2618, 3495.263257768702, 0.38634768921509505], [2642, 3721.192443982953, 0.39811794815734697], [2666, 3953.882618738862, 0.4098230235641873], [2690, 4193.295683858948, 0.4214609989729175], [2714, 4439.392440432232, 0.43302996890706835], [2738, 4692.13259523225, 0.4445280391883822], [2762, 4951.474767314213, 0.4559533272469452], [2786, 5217.376494790295, 0.4673039624294192], [2810, 5489.794241781867, 0.47857808630532184], [2834, 5768.683405547609, 0.48977385297130654], [2858, 6053.998323786271, 0.5008894293533902], [2882, 6345.692282112929, 0.5119229955070813], [2906, 6643.717521707482, 0.5228727449153581], [2930, 6948.025247134187, 0.5337368847844474], [2954, 7258.565634330886, 0.5445136363373585], [2978, 7575.2878387666515, 0.55520123510512], [3002, 7898.140003766541, 0.5657979312156751], [3026, 8227.069269002035, 0.5763019896803872], [3050, 8562.021779145813, 0.5867116906781074], [3074, 8902.942692689454, 0.5970253298367603], [3098, 9249.77619092259, 0.6072412185123989], [3122, 9602.465487072062, 0.6173576840656853], [3146, 9960.952835599564, 0.6273730701357502], [3170, 10325.179541656276, 0.6372857369113881], [3194, 10695.085970692946, 0.6470940613995417], [3218, 11070.61155822377, 0.6567964376910339], [3242, 11451.694819742594, 0.6663912772235012], [3266, 11838.273360789732, 0.6758770090414887], [3290, 12230.283887167718, 0.6852520800536607], [3314, 12627.662215304457, 0.6945149552870871], [3338, 13030.343282761949, 0.7036641181385641], [3362, 13438.26115888887, 0.7126980706229253], [3386, 13851.349055615396, 0.7216153336183068], [3410, 14269.539338388322, 0.7304144471083213], [3434, 14692.763537244835, 0.7390939704211066], [3458, 15120.952358023043, 0.7476524824652054], [3482, 15554.035693707443, 0.756088581962239], [3506, 15991.942635907495, 0.7644008876763378], [3530, 16434.601486467407, 0.77258803864029], [3554, 16881.93976920519, 0.7806486943783717], [3578, 17333.884241779157, 0.7885815351258217], [3602, 17790.3609076798, 0.7963852620449259], [3626, 18251.295028345216, 0.8040585974376745], [3650, 18716.61113539796, 0.811600284954959], [3674, 19186.233043001444, 0.8190090898022727], [3698, 19660.08386033378, 0.8262837989418832], [3722, 20138.08600417704, 0.8334232212914415], [3746, 20620.161211619907, 0.8404261879189975], [3770, 21106.2305528716, 0.847291552234388], [3794, 21596.214444184974, 0.854018190176967], [3818, 22090.032660886714, 0.8606050003996475], [3842, 22587.604350512476, 0.8670509044492238], [3866, 23088.848046044735, 0.8733548469429462], [3890, 23593.681679251396, 0.8795157957413174], [3914, 24102.022594122696, 0.8855327421170849], [3938, 24613.78756040444, 0.8914047009203977], [3962, 25128.89278722521, 0.8971307107401055], [3986, 25647.25393681538, 0.9027098340611689], [4010, 26168.786138315692, 0.9081411574181582], [4034, 26693.404001673065, 0.9134237915448143], [4058, 27221.02163162145, 0.9185568715196482], [4082, 27751.55264174541, 0.9235395569075527], [4106, 28284.91016862408, 0.9283710318974073], [4130, 28821.006886053234, 0.9330505054356498], [4154, 29359.755019343185, 0.9375772113557947], [4178, 29901.066359690027, 0.9419504085038777], [4202, 30444.852278617956, 0.9461693808598033], [4226, 30991.023742490444, 0.9502334376545789], [4250, 31539.49132708754, 0.9541419134834139], [4274, 32090.165232247295, 0.9578941684146655], [4298, 32642.955296568638, 0.9614895880946143], [4322, 33197.77101217344, 0.9649275838480521], [4346, 33754.52153952529, 0.9682075927746651], [4370, 34313.11572230261, 0.9713290778411972], [4394, 34873.46210232354, 0.9742915279693779], [4418, 35435.4689345204, 0.9770944581196009], [4442, 35999.044201960976, 0.9797374093703394], [4466, 36564.0956309144, 0.9822199489932842], [4490, 37130.53070595905, 0.9845416705241952], [4514, 37698.25668513003, 0.9867021938294499], [4538, 38267.18061510374, 0.9887011651682841], [4562, 38837.20934641703, 0.9905382572507082], [4586, 39408.24954871853, 0.9922131692910947], [4610, 39980.20772604952, 0.993725627057426], [4634, 40552.99023215194, 0.995075382916193], [4658, 41126.50328580106, 0.9962622158729415], [4682, 41700.65298616017, 0.997285931608454], [4706, 42275.34532815489, 0.9981463625105663], [4730, 42850.48621786456, 0.9988433677016104], [4754, 43425.98148792817, 0.99937683306148], [4824, 45104.93456747146, 0.99937683306148], [4830, 45248.66768695521, 0.9965334440503064], [4836, 45391.82607643404, 0.9913960035385548], [4842, 45534.0801807684, 0.9839763380767395], [4848, 45675.102526511764, 0.9742915279693778], [4854, 45814.56847576483, 0.9623638679555901], [4860, 45952.15697350221, 0.9482208158859047], [4866, 46087.5512866513, 0.9318949295134172], [4872, 46220.4397332218, 0.9134237915448143], [4878, 46350.516399807486, 0.892849923123794], [4884, 46477.481845808616, 0.8702206859460481], [4890, 46601.043792753575, 0.8455881732311413], [4896, 46720.91779713324, 0.8190090898022727], [4902, 46836.82790519886, 0.790544621549979], [4908, 46948.507288216366, 0.7602602945802802], [4914, 47055.69885671452, 0.7282258243715115], [4920, 47158.15585231304, 0.6945149552870871], [4926, 47255.642415768154, 0.6592052908136443], [4932, 47347.93412992807, 0.6223781149153631], [4938, 47434.81853634834, 0.58411820491571], [4944, 47516.095624377944, 0.5445136363373586], [4950, 47591.57829159008, 0.5036555801495519], [4956, 47661.092774497905, 0.4616380928896475], [4962, 47724.4790485636, 0.4185579001419942], [4968, 47781.59119657985, 0.3745141738725787], [4974, 47832.297744575924, 0.3296083041320237], [4980, 47876.4819644749, 0.28394366565248513], [4986, 47914.04214280537, 0.23762537987574991], [4992, 47944.89181484909, 0.1907600729603523], [4998, 47968.95996368549, 0.14345563032478612], [5004, 47986.19118367487, 0.09582094829185946], [5010, 47996.54580800392, 0.04796568340591532], [5016, 48000.0, 0.0], [5216, 48000.0, 0.0], [5217, 47999.02957352052, -0.0808247483395746], [5218, 47996.12464391615, -0.16112063256474127], [5219, 47991.30421913994, -0.2403622491008061], [5220, 47984.59984088839, -0.3180310928090024], [5221, 47976.05537821323, -0.39361894974386563], [5222, 47965.72674047116, -0.46663122257179335], [5223, 47953.681511489725, -0.5365901668914318], [5224, 47939.99850734308, -0.6030380172795338], [5225, 47924.7672606313, -0.6655399826074937], [5226, 47908.08743463785, -0.7236870910291755], [5227, 47890.0681711984, -0.7770988660242983], [5228, 47870.827376548325, -0.8254258159871095], [5229, 47850.490949821644, -0.8683517210701095], [5230, 47829.19195924971, -0.905595702319225], [5231, 47807.06977145001, -0.9369140595613656], [5232, 47784.269139502525, -0.962101866018436], [5233, 47760.93925578051, -0.9809943092136955], [5234, 47737.23277573353, -0.9934677693964523], [5235, 47713.30481901038, -0.9994406284285906], [6580, 15451.361333335477, -0.9994406284285906], [6604, 14876.155090856286, -0.9975871835223822], [6628, 14302.389549004594, -0.9944387369167409], [6652, 13730.809532256953, -0.9899993757168063], [6676, 13162.157027985766, -0.9842748628076606], [6700, 12597.170223260378, -0.9772726293733331], [6724, 12036.582546581434, -0.9690017652501278], [6748, 11481.121715792524, -0.9594730071267995], [6772, 10931.508793404992, -0.9486987246068947], [6796, 10388.457250562293, -0.9366929041513503], [6820, 9852.672040858937, -0.923471130922195], [6844, 9324.848685216359, -0.9090505685509229], [6868, 8805.672369003663, -0.8934499368578025], [6892, 8295.817052575308, -0.8766894875510439], [6916, 7795.944596380323, -0.8587909779373708], [6940, 7306.703901778873, -0.8397776426781237], [6964, 6828.730068681431, -0.8196741636275602], [6988, 6362.643571104072, -0.7985066377925031], [7012, 5909.049451710151, -0.7763025434549333], [7036, 5468.53653638393, -0.753090704501501], [7060, 5041.676669855764, -0.7289012530062624], [7084, 4629.023973371102, -0.7037655901152149], [7108, 4231.114125366927, -0.6777163452834054], [7132, 3848.463666089441, -0.6507873339175307], [7156, 3481.569327055686, -0.6230135134790126], [7180, 3130.9073862295427, -0.5944309381045335], [7204, 2796.933049749179, -0.5650767118029418], [7228, 2480.0798610085494, -0.5349889402892807], [7252, 2180.759137860032, -0.5042066815184694], [7276, 1899.3594386688092, -0.47276989498285044], [7300, 1636.2460579120852, -0.4407193898394183], [7324, 1391.7605519779663, -0.4080967719340723], [7348, 1166.2202957795453, -0.3749443897916581], [7372, 959.9180707597734, -0.34130527964191454], [7396, 773.1216848219756, -0.30722310955268695], [7420, 606.0736246793222, -0.2727421227429285], [7444, 458.9907410746382, -0.23790708014908138], [7468, 332.06396727908214, -0.20276320231938796], [7492, 225.45807123523628, -0.16735611071156772], [7516, 139.3114416662338, -0.13173176847005655], [7540, 73.73590842869089, -0.09593642075969458], [7564, 28.816597342574823, -0.06001653473331008], [7588, 4.611819686486342, -0.0240187392111369], [7604, 0.0, 0.0], [12889, 0.0, 0.0]]],
    [129, [[0, 0.0, 0.0], [614, 0.0, 0.0], [1414, 620.0, 0.045], [1912, 1250.0, 0.04], [2355, 1720.0, 0.0], [3208, 1040.0, 0.0], [4036, 2150.0, 0.075], [4534, 3260.0, 0.0], [4969, 3150.0, -0.02], [5500, 2330.0, 0.0], [6039, 2560.0, 0.0], [6522, 2480.0, -0.03], [7223, 1500.0, -0.07], [8086, 620.0, -0.045], [8861, 60.0, -0.01], [9136, 0.0, 0.0], [10515, 0.0, 0.0]]],
  ];
  // [launch road (its end is a lip), catch deck, the slowest that lands (mph)]
  const NET_JUMPS = [[59, 60, 3000.0], [61, 62, 3500.0], [63, 64, 2500.0], [65, 66, 4000.0], [67, 68, 2000.0], [69, 70, 3250.0], [71, 72, 2500.0], [73, 74, 3750.0], [75, 76, 2250.0], [77, 78, 3500.0], [79, 80, 4000.0], [81, 82, 2750.0], [83, 84, 2500.0], [85, 86, 3250.0], [87, 88, 2000.0], [89, 90, 2750.0], [91, 92, 3500.0], [93, 94, 2250.0], [95, 96, 3000.0], [97, 98, 3750.0], [122, 123, 3250.0]];
  // [city, road]: the on-ramps from the open ground (their start is open)
  const NET_ONRAMPS = [[0, 111], [1, 112], [2, 113], [3, 114], [4, 115]];
  // [road, pull-up sample, landing sample, R, V]: the shafts (their bulb carries you round; view/network_shaft.gd)
  const NET_SHAFTS = [[47, 279, 1938, 2400.0, 12337.201721565565], [48, 529, 2253, 5400.0, 3713.2472701655643], [49, 329, 2404, 3000.0, 15450.561660621179], [50, 579, 2538, 6000.0, 4627.468168640793], [51, 379, 1770, 3600.0, 5368.916720818019], [52, 429, 2421, 4200.0, 10681.497532786905], [53, 313, 2189, 2808.0, 13662.59450658454], [54, 629, 2638, 6600.0, 3342.5125764871227], [55, 413, 2572, 4008.0, 13291.836265802718], [56, 479, 2153, 4800.0, 4998.202862319289], [57, 346, 2621, 3204.0, 17212.82271344183], [58, 554, 2579, 5700.0, 6369.528668337596]];
  // [road, sea side, [[sample, left m, its run m, right m, its run m, gap m], ...]]: the land beside the scenic roads (the views' only)
  const NET_SCENIC = [
    [116, 1, [[1373, -4.0, 400.0, -4.0, 400.0, 1.0], [1682, -5.0, 2600.0, 260.0, 1500.0, 1.0], [2057, -5.0, 0.0, 520.0, 2000.0, 1.0], [3236, -5.0, 0.0, 760.0, 2300.0, 1.0], [4194, -5.0, 0.0, 900.0, 2400.0, 1.0], [5400, -5.0, 0.0, 700.0, 2200.0, 1.0], [6339, -5.0, 0.0, 980.0, 2500.0, 1.0], [7284, -5.0, 0.0, 1150.0, 2600.0, 1.0], [7906, -5.0, 0.0, 900.0, 2400.0, 1.0], [8623, -5.0, 0.0, 520.0, 2000.0, 1.0], [8910, -5.0, 2600.0, 200.0, 1400.0, 1.0], [9053, -4.0, 400.0, -4.0, 400.0, 1.0]]],
    [117, 0, [[1509, -4.0, 400.0, -4.0, 400.0, 1.0], [1743, 30.0, 700.0, 657.8, 1800.0, 1.0], [2280, 60.0, 1300.0, 1850.0, 2200.0, 1.0], [3074, 110.0, 1600.0, 3200.0, 2400.0, 1.0], [3818, 140.0, 1600.0, 3330.0, 2400.0, 1.0], [4228, 150.0, 1600.0, 3077.5, 2200.0, 1.0], [4336, 150.0, 1500.0, 2388.0, 1400.0, 1.0], [4391, 150.0, 1400.0, 170.0, 1400.0, 1.0], [4447, 150.0, 1400.0, 170.0, 1400.0, 1500.0], [4795, 150.0, 1400.0, 170.0, 1400.0, 500.0], [4938, 324.0, 1300.0, 324.0, 1300.0, 1.0], [5974, 184.0, 1100.0, 184.0, 1100.0, 1.0], [7193, 84.0, 900.0, 84.0, 900.0, 1.0], [8040, -4.0, 400.0, -4.0, 400.0, 1.0]]],
    [119, 0, [[362, -4.0, 1750.0, -4.0, 2200.0, 5.500966308730878], [967, 259.15102379147925, 1750.0, 169.15102379147925, 2200.0, 1.0], [2094, 733.9663240960934, 1750.0, 198.96632409609344, 2200.0, 1.0], [3141, 1410.0, 1750.0, 590.0, 2200.0, 1.0], [3786, 850.1230869507222, 1750.0, 800.1230869507222, 2200.0, 1.0], [4511, 235.0, 1750.0, 750.0, 2200.0, 1.0], [5397, 541.4487098495622, 1750.0, 651.4487098495622, 2200.0, 1.0], [6041, -4.0, 1750.0, -4.0, 2200.0, 491.1360773491621]]],
    [127, 0, [[1620, 0.0, 600.0, 5.77, 600.0, 1.0], [1680, 24.75, 600.0, 93.15, 600.0, 1.0], [1740, 107.22, 600.0, 244.69, 600.0, 1.0], [1800, 241.09, 600.0, 433.26, 600.0, 1.0], [1860, 415.07, 600.0, 658.49, 600.0, 1.0], [1920, 619.66, 600.0, 910.88, 600.0, 1.0], [1980, 846.02, 600.0, 1181.59, 600.0, 1.0], [2040, 1085.93, 600.0, 1462.4, 600.0, 1.0], [2100, 1331.83, 600.0, 1745.75, 600.0, 1.0], [2160, 1576.78, 600.0, 2024.69, 600.0, 1.0], [2220, 1814.48, 600.0, 2292.94, 600.0, 1.0], [2280, 2039.29, 600.0, 2544.84, 600.0, 1.0], [2340, 2246.18, 600.0, 2775.37, 600.0, 1.0], [2400, 2430.78, 600.0, 2980.16, 600.0, 1.0], [2460, 2589.36, 600.0, 3155.47, 600.0, 1.0], [2520, 2718.8, 600.0, 3298.2, 600.0, 1.0], [2580, 2816.66, 600.0, 3405.9, 600.0, 1.0], [2640, 2881.1, 600.0, 3476.73, 600.0, 1.0], [2700, 2910.96, 600.0, 3509.52, 600.0, 1.0], [2760, 2914.21, 600.0, 3513.01, 600.0, 1.0], [2820, 2920.19, 600.0, 3519.15, 600.0, 1.0], [2880, 2931.35, 600.0, 3530.61, 600.0, 1.0], [2940, 2947.68, 600.0, 3547.36, 600.0, 1.0], [3000, 2969.13, 600.0, 3569.36, 600.0, 1.0], [3060, 2995.66, 600.0, 3596.57, 600.0, 1.0], [3120, 3027.21, 600.0, 3628.89, 600.0, 1.0], [3180, 3063.72, 600.0, 3666.26, 600.0, 1.0], [3240, 3105.08, 600.0, 3708.57, 600.0, 1.0], [3300, 3151.21, 600.0, 3755.7, 600.0, 1.0], [3360, 3201.97, 600.0, 3807.51, 600.0, 1.0], [3420, 3257.23, 600.0, 3863.84, 600.0, 1.0], [3480, 3316.83, 600.0, 3924.52, 600.0, 1.0], [3540, 3380.59, 600.0, 3989.36, 600.0, 1.0], [3600, 3448.31, 600.0, 4058.13, 600.0, 1.0], [3660, 3519.76, 600.0, 4130.6, 600.0, 1.0], [3720, 3594.71, 600.0, 4206.49, 600.0, 1.0], [3780, 3672.87, 600.0, 4285.53, 600.0, 1.0], [3840, 3753.96, 600.0, 4367.4, 600.0, 1.0], [3900, 3837.64, 600.0, 4451.78, 600.0, 1.0], [3960, 3923.59, 600.0, 4538.32, 600.0, 1.0], [4020, 4011.43, 600.0, 4626.63, 600.0, 1.0], [4080, 4100.77, 600.0, 4716.32, 600.0, 1.0], [4140, 4191.21, 600.0, 4806.99, 600.0, 1.0], [4200, 4282.31, 600.0, 4898.19, 600.0, 1.0], [4260, 4373.63, 600.0, 4989.5, 600.0, 1.0], [4320, 4464.71, 600.0, 5080.45, 600.0, 1.0], [4380, 4555.09, 600.0, 5170.58, 600.0, 1.0], [4440, 4644.27, 600.0, 5259.42, 600.0, 1.0], [4500, 4731.77, 600.0, 5346.48, 600.0, 1.0], [4560, 4817.11, 600.0, 5431.3, 600.0, 1.0], [4620, 4899.8, 600.0, 5513.4, 600.0, 1.0], [4680, 4979.36, 600.0, 5592.31, 600.0, 1.0], [4740, 5055.31, 600.0, 5667.58, 600.0, 1.0], [4800, 5127.21, 600.0, 5738.77, 600.0, 1.0], [4860, 5194.61, 600.0, 5805.45, 600.0, 1.0], [4920, 5257.1, 600.0, 5867.23, 600.0, 1.0], [4980, 5314.28, 600.0, 5923.73, 600.0, 1.0], [5040, 5365.79, 600.0, 5974.59, 600.0, 1.0], [5100, 5411.3, 600.0, 6019.51, 600.0, 1.0], [5160, 5450.52, 600.0, 6058.2, 600.0, 1.0], [5220, 5483.19, 600.0, 6090.42, 600.0, 1.0], [5280, 5509.09, 600.0, 6115.96, 600.0, 1.0], [5340, 5528.06, 600.0, 6134.66, 600.0, 1.0], [5400, 5539.98, 600.0, 6146.41, 600.0, 1.0], [5460, 5544.76, 600.0, 6151.12, 600.0, 1.0], [5520, 5548.39, 600.0, 6154.6, 600.0, 1.0], [5580, 5561.92, 600.0, 6167.57, 600.0, 1.0], [5640, 5585.5, 600.0, 6190.18, 600.0, 1.0], [5700, 5618.99, 600.0, 6222.27, 600.0, 1.0], [5760, 5662.15, 600.0, 6263.62, 600.0, 1.0], [5820, 5714.69, 600.0, 6313.94, 600.0, 1.0], [5880, 5776.27, 600.0, 6372.86, 600.0, 1.0], [5940, 5846.43, 600.0, 6439.96, 600.0, 1.0], [6000, 5924.7, 600.0, 6514.73, 600.0, 1.0], [6060, 6010.47, 600.0, 6596.62, 600.0, 1.0], [6120, 6103.12, 600.0, 6684.98, 600.0, 1.0], [6180, 6201.92, 600.0, 6779.1, 600.0, 1.0], [6240, 6306.08, 600.0, 6878.23, 600.0, 1.0], [6300, 6414.73, 600.0, 6981.53, 600.0, 1.0], [6360, 6526.97, 600.0, 7088.12, 600.0, 1.0], [6420, 6641.82, 600.0, 7197.07, 600.0, 1.0], [6480, 6758.24, 600.0, 7307.39, 600.0, 1.0], [6540, 6887.1, 600.0, 7419.56, 600.0, 1.0], [6600, 7129.09, 600.0, 7602.38, 600.0, 1.0], [6660, 7489.8, 600.0, 7873.41, 600.0, 1.0], [6690, 7705.86, 600.0, 8034.89, 600.0, 1.0], [6720, 7939.59, 600.0, 8208.89, 600.0, 1.0], [6750, 8185.58, 600.0, 8391.26, 600.0, 1.0], [6765, 8311.3, 600.0, 8484.18, 600.0, 1.0], [6780, 8437.8, 600.0, 8577.49, 600.0, 1.0], [6795, 8564.26, 600.0, 8670.57, 600.0, 1.0], [6802, 8623.02, 600.0, 8713.77, 600.0, 1.0], [6810, 8689.83, 600.0, 8762.83, 600.0, 1.0], [6817, 8747.88, 600.0, 8805.42, 600.0, 1.0], [6821, 8780.86, 600.0, 8829.6, 600.0, 1.0], [6825, 8813.66, 600.0, 8853.64, 600.0, 1.0], [6832, 8870.62, 600.0, 8895.35, 600.0, 1.0], [6836, 8902.89, 600.0, 8918.97, 600.0, 1.0], [6840, 8934.92, 600.0, 8942.4, 600.0, 1.0], [6843, 8958.79, 600.0, 8959.85, 600.0, 1.0], [6847, 8986.71, 600.0, 8986.71, 600.0, 1.0], [6851, 9013.89, 600.0, 9013.89, 600.0, 1.0], [6855, 9040.83, 600.0, 9040.83, 600.0, 1.0], [6858, 9060.88, 600.0, 9060.88, 600.0, 1.0], [6862, 9087.41, 600.0, 9087.41, 600.0, 1.0], [6866, 9113.69, 600.0, 9113.69, 600.0, 1.0], [6870, 9139.74, 600.0, 9139.74, 600.0, 1.0], [6873, 9160.03, 600.0, 9160.03, 600.0, 1.0], [6877, 9190.0, 600.0, 9190.0, 600.0, 1.0], [6881, 9223.37, 600.0, 9223.37, 600.0, 1.0], [6885, 9260.21, 600.0, 9260.21, 600.0, 1.0], [6888, 9290.18, 600.0, 9290.18, 600.0, 1.0], [6890, 9311.29, 600.0, 9311.29, 600.0, 1.0], [6892, 9333.32, 600.0, 9333.32, 600.0, 1.0], [6894, 9356.29, 600.0, 9356.29, 600.0, 1.0], [6896, 9380.2, 600.0, 9380.2, 600.0, 1.0], [6898, 9405.08, 600.0, 9405.08, 600.0, 1.0], [6900, 9430.94, 600.0, 9430.94, 600.0, 1.0], [6903, 9471.61, 600.0, 9471.61, 600.0, 1.0], [6905, 9500.0, 600.0, 9500.0, 600.0, 1.0], [6907, 9529.43, 600.0, 9529.43, 600.0, 1.0], [6909, 9559.92, 600.0, 9559.92, 600.0, 1.0], [6911, 9591.51, 600.0, 9591.51, 600.0, 1.0], [6913, 9624.2, 600.0, 9624.2, 600.0, 1.0], [6915, 9658.03, 600.0, 9658.03, 600.0, 1.0], [6918, 9710.95, 600.0, 9710.95, 600.0, 1.0], [6920, 9747.73, 600.0, 9747.73, 600.0, 1.0], [6922, 9785.74, 600.0, 9785.74, 600.0, 1.0], [6924, 9825.01, 600.0, 9825.01, 600.0, 1.0], [6926, 9865.58, 600.0, 9865.58, 600.0, 1.0], [6928, 9907.49, 600.0, 9907.49, 600.0, 1.0], [6930, 9950.76, 600.0, 9950.76, 600.0, 1.0], [6933, 10018.32, 600.0, 10018.32, 600.0, 1.0], [6935, 10065.2, 600.0, 10065.2, 600.0, 1.0], [6937, 10113.6, 600.0, 10113.6, 600.0, 1.0], [6939, 10163.57, 600.0, 10163.57, 600.0, 1.0], [6941, 10215.16, 600.0, 10215.16, 600.0, 1.0], [6943, 10268.44, 600.0, 10268.44, 600.0, 1.0], [6945, 10323.46, 600.0, 10323.46, 600.0, 1.0], [6948, 10409.39, 600.0, 10409.39, 600.0, 1.0], [6950, 10469.06, 600.0, 10469.06, 600.0, 1.0], [6952, 10530.72, 600.0, 10530.72, 600.0, 1.0], [6954, 10594.46, 600.0, 10594.46, 600.0, 1.0], [6956, 10660.36, 600.0, 10660.36, 600.0, 1.0], [6958, 10728.53, 600.0, 10728.53, 600.0, 1.0], [6960, 10799.06, 600.0, 10799.06, 600.0, 1.0], [6963, 10909.56, 600.0, 10909.56, 600.0, 1.0], [6965, 10986.53, 600.0, 10986.53, 600.0, 1.0], [6967, 11066.32, 600.0, 11066.32, 600.0, 1.0], [6969, 11149.08, 600.0, 11149.08, 600.0, 1.0], [6971, 11234.97, 600.0, 11234.97, 600.0, 1.0], [6975, 11416.93, 600.0, 11416.93, 600.0, 1.0], [6978, 11563.15, 600.0, 11563.15, 600.0, 1.0], [6982, 11772.76, 600.0, 11772.76, 600.0, 1.0], [6986, 12001.45, 600.0, 12001.45, 600.0, 1.0], [6990, 12252.37, 600.0, 12252.37, 600.0, 1.0], [6993, 12457.55, 600.0, 12457.55, 600.0, 1.0], [6997, 12757.95, 600.0, 12757.95, 600.0, 1.0], [7001, 13095.07, 600.0, 13095.07, 600.0, 1.0], [7005, 13419.51, 600.0, 13419.51, 600.0, 1.0], [7008, 13632.38, 600.0, 13632.38, 600.0, 1.0], [7012, 13884.23, 600.0, 13884.23, 600.0, 1.0], [7016, 14106.4, 600.0, 14106.4, 600.0, 1.0], [7020, 14304.37, 600.0, 14304.37, 600.0, 1.0], [7023, 14439.41, 600.0, 14439.41, 600.0, 1.0], [7027, 14604.06, 600.0, 14604.06, 600.0, 1.0], [7031, 14753.35, 600.0, 14753.35, 600.0, 1.0], [7035, 14889.25, 600.0, 14889.25, 600.0, 1.0], [7038, 14983.33, 600.0, 14983.33, 600.0, 1.0], [7042, 15099.36, 600.0, 15099.36, 600.0, 1.0], [7046, 15205.64, 600.0, 15205.64, 600.0, 1.0], [7050, 15303.05, 600.0, 15303.05, 600.0, 1.0], [7053, 15370.76, 600.0, 15370.76, 600.0, 1.0], [7057, 15454.43, 600.0, 15454.43, 600.0, 1.0], [7061, 15531.04, 600.0, 15531.04, 600.0, 1.0], [7065, 15601.09, 600.0, 15601.09, 600.0, 1.0], [7068, 15649.56, 600.0, 15649.56, 600.0, 1.0], [7072, 15709.06, 600.0, 15709.06, 600.0, 1.0], [7076, 15762.99, 600.0, 15762.99, 600.0, 1.0], [7080, 15811.62, 600.0, 15811.62, 600.0, 1.0], [7083, 15844.76, 600.0, 15844.76, 600.0, 1.0], [7087, 15884.67, 600.0, 15884.67, 600.0, 1.0], [7091, 15919.86, 600.0, 15919.86, 600.0, 1.0], [7095, 15950.48, 600.0, 15950.48, 600.0, 1.0], [7098, 15970.54, 600.0, 15970.54, 600.0, 1.0], [7102, 15993.48, 600.0, 15993.48, 600.0, 1.0], [7106, 16012.18, 600.0, 16012.18, 600.0, 1.0], [7110, 16026.73, 600.0, 16026.73, 600.0, 1.0], [7117, 16042.38, 600.0, 16042.38, 600.0, 1.0], [7125, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7140, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7200, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7260, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7320, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7350, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7365, 16046.07, 600.0, 16046.07, 600.0, 1.0], [7372, 16040.9, 600.0, 16040.9, 600.0, 1.0], [7380, 16019.97, 600.0, 16019.97, 600.0, 1.0], [7383, 16007.9, 600.0, 16007.9, 600.0, 1.0], [7387, 15988.15, 600.0, 15988.15, 600.0, 1.0], [7391, 15964.12, 600.0, 15964.12, 600.0, 1.0], [7395, 15935.73, 600.0, 15935.73, 600.0, 1.0], [7398, 15911.5, 600.0, 15911.5, 600.0, 1.0], [7402, 15875.15, 600.0, 15875.15, 600.0, 1.0], [7406, 15834.03, 600.0, 15834.03, 600.0, 1.0], [7410, 15787.95, 600.0, 15787.95, 600.0, 1.0], [7413, 15750.02, 600.0, 15750.02, 600.0, 1.0], [7417, 15694.72, 600.0, 15694.72, 600.0, 1.0], [7421, 15633.78, 600.0, 15633.78, 600.0, 1.0], [7425, 15566.86, 600.0, 15566.86, 600.0, 1.0], [7428, 15512.52, 600.0, 15512.52, 600.0, 1.0], [7432, 15434.19, 600.0, 15434.19, 600.0, 1.0], [7436, 15348.68, 600.0, 15348.68, 600.0, 1.0], [7440, 15255.4, 600.0, 15255.4, 600.0, 1.0], [7443, 15179.93, 600.0, 15179.93, 600.0, 1.0], [7447, 15071.31, 600.0, 15071.31, 600.0, 1.0], [7451, 14952.67, 600.0, 14952.67, 600.0, 1.0], [7455, 14822.87, 600.0, 14822.87, 600.0, 1.0], [7458, 14717.35, 600.0, 14717.35, 600.0, 1.0], [7462, 14564.42, 600.0, 14564.42, 600.0, 1.0], [7466, 14395.57, 600.0, 14395.57, 600.0, 1.0], [7470, 14208.13, 600.0, 14208.13, 600.0, 1.0], [7473, 14053.31, 600.0, 14053.31, 600.0, 1.0], [7477, 13824.3, 600.0, 13824.3, 600.0, 1.0], [7481, 13563.95, 600.0, 13563.95, 600.0, 1.0], [7485, 13263.79, 600.0, 13263.79, 600.0, 1.0], [7488, 13007.04, 600.0, 13007.04, 600.0, 1.0], [7492, 12679.69, 600.0, 12679.69, 600.0, 1.0], [7496, 12387.39, 600.0, 12387.39, 600.0, 1.0], [7500, 12123.9, 600.0, 12123.9, 600.0, 1.0], [7503, 11942.33, 600.0, 11942.33, 600.0, 1.0], [7507, 11718.68, 600.0, 11718.68, 600.0, 1.0], [7511, 11513.42, 600.0, 11513.42, 600.0, 1.0], [7515, 11324.19, 600.0, 11324.19, 600.0, 1.0], [7518, 11191.62, 600.0, 11191.62, 600.0, 1.0], [7520, 11107.32, 600.0, 11107.32, 600.0, 1.0], [7522, 11026.07, 600.0, 11026.07, 600.0, 1.0], [7524, 10947.7, 600.0, 10947.7, 600.0, 1.0], [7526, 10872.08, 600.0, 10872.08, 600.0, 1.0], [7528, 10799.06, 600.0, 10799.06, 600.0, 1.0], [7530, 10728.53, 600.0, 10728.53, 600.0, 1.0], [7533, 10627.14, 600.0, 10627.14, 600.0, 1.0], [7535, 10562.33, 600.0, 10562.33, 600.0, 1.0], [7537, 10499.64, 600.0, 10499.64, 600.0, 1.0], [7539, 10438.98, 600.0, 10438.98, 600.0, 1.0], [7541, 10380.28, 600.0, 10380.28, 600.0, 1.0], [7543, 10323.46, 600.0, 10323.46, 600.0, 1.0], [7545, 10268.44, 600.0, 10268.44, 600.0, 1.0], [7548, 10189.16, 600.0, 10189.16, 600.0, 1.0], [7550, 10138.38, 600.0, 10138.38, 600.0, 1.0], [7552, 10089.21, 600.0, 10089.21, 600.0, 1.0], [7554, 10041.57, 600.0, 10041.57, 600.0, 1.0], [7556, 9995.44, 600.0, 9995.44, 600.0, 1.0], [7558, 9950.76, 600.0, 9950.76, 600.0, 1.0], [7560, 9907.49, 600.0, 9907.49, 600.0, 1.0], [7563, 9845.14, 600.0, 9845.14, 600.0, 1.0], [7565, 9805.22, 600.0, 9805.22, 600.0, 1.0], [7567, 9766.58, 600.0, 9766.58, 600.0, 1.0], [7569, 9729.19, 600.0, 9729.19, 600.0, 1.0], [7571, 9693.01, 600.0, 9693.01, 600.0, 1.0], [7573, 9658.03, 600.0, 9658.03, 600.0, 1.0], [7575, 9624.2, 600.0, 9624.2, 600.0, 1.0], [7578, 9575.58, 600.0, 9575.58, 600.0, 1.0], [7580, 9544.54, 600.0, 9544.54, 600.0, 1.0], [7582, 9514.58, 600.0, 9514.58, 600.0, 1.0], [7584, 9485.67, 600.0, 9485.67, 600.0, 1.0], [7586, 9457.8, 600.0, 9457.8, 600.0, 1.0], [7588, 9430.94, 600.0, 9430.94, 600.0, 1.0], [7590, 9405.08, 600.0, 9405.08, 600.0, 1.0], [7593, 9368.13, 600.0, 9368.13, 600.0, 1.0], [7595, 9344.69, 600.0, 9344.69, 600.0, 1.0], [7597, 9322.19, 600.0, 9322.19, 600.0, 1.0], [7599, 9300.62, 600.0, 9300.62, 600.0, 1.0], [7601, 9279.97, 600.0, 9279.97, 600.0, 1.0], [7605, 9241.35, 600.0, 9241.35, 600.0, 1.0], [7608, 9214.7, 600.0, 9214.7, 600.0, 1.0], [7612, 9182.19, 600.0, 9182.19, 600.0, 1.0], [7616, 9153.06, 600.0, 9153.06, 600.0, 1.0], [7620, 9126.75, 600.0, 9126.75, 600.0, 1.0], [7623, 9107.14, 600.0, 9107.14, 600.0, 1.0], [7627, 9080.8, 600.0, 9080.8, 600.0, 1.0], [7631, 9054.21, 600.0, 9054.21, 600.0, 1.0], [7635, 9027.39, 600.0, 9027.39, 600.0, 1.0], [7638, 9007.11, 600.0, 9007.11, 600.0, 1.0], [7642, 8979.88, 600.0, 8979.88, 600.0, 1.0], [7646, 8955.12, 600.0, 8949.78, 600.0, 1.0], [7650, 8931.78, 600.0, 8917.85, 600.0, 1.0], [7653, 8914.16, 600.0, 8893.76, 600.0, 1.0], [7657, 8890.52, 600.0, 8861.43, 600.0, 1.0], [7661, 8866.71, 600.0, 8828.9, 600.0, 1.0], [7665, 8842.74, 600.0, 8796.18, 600.0, 1.0], [7672, 8800.48, 600.0, 8738.5, 600.0, 1.0], [7680, 8751.72, 600.0, 8672.04, 600.0, 1.0], [7695, 8659.34, 600.0, 8546.29, 600.0, 1.0], [7710, 8566.19, 600.0, 8419.79, 600.0, 1.0], [7725, 8472.9, 600.0, 8293.35, 600.0, 1.0], [7740, 8380.06, 600.0, 8167.8, 600.0, 1.0], [7770, 8198.08, 600.0, 7922.49, 600.0, 1.0], [7800, 8024.72, 600.0, 7689.84, 600.0, 1.0], [7830, 7864.12, 600.0, 7475.23, 600.0, 1.0], [7860, 7719.96, 600.0, 7283.37, 600.0, 1.0], [7920, 7493.28, 600.0, 6983.3, 600.0, 1.0], [7980, 7359.15, 600.0, 6812.72, 600.0, 1.0], [8040, 7248.53, 600.0, 6695.93, 600.0, 1.0], [8100, 7138.82, 600.0, 6580.22, 600.0, 1.0], [8160, 7031.01, 600.0, 6466.64, 600.0, 1.0], [8220, 6926.06, 600.0, 6356.2, 600.0, 1.0], [8280, 6824.87, 600.0, 6249.83, 600.0, 1.0], [8340, 6728.3, 600.0, 6148.44, 600.0, 1.0], [8400, 6637.16, 600.0, 6052.83, 600.0, 1.0], [8460, 6552.17, 600.0, 5963.76, 600.0, 1.0], [8520, 6473.99, 600.0, 5881.92, 600.0, 1.0], [8580, 6403.24, 600.0, 5807.92, 600.0, 1.0], [8640, 6340.44, 600.0, 5742.28, 600.0, 1.0], [8700, 6286.05, 600.0, 5685.48, 600.0, 1.0], [8760, 6240.47, 600.0, 5637.91, 600.0, 1.0], [8820, 6204.02, 600.0, 5599.89, 600.0, 1.0], [8880, 6176.95, 600.0, 5571.67, 600.0, 1.0], [8940, 6159.46, 600.0, 5553.43, 600.0, 1.0], [9000, 6151.66, 600.0, 5545.31, 600.0, 1.0], [9060, 6149.49, 600.0, 5543.1, 600.0, 1.0], [9120, 6141.03, 600.0, 5534.51, 600.0, 1.0], [9180, 6125.58, 600.0, 5518.83, 600.0, 1.0], [9240, 6103.23, 600.0, 5496.15, 600.0, 1.0], [9300, 6074.13, 600.0, 5466.63, 600.0, 1.0], [9360, 6038.46, 600.0, 5430.46, 600.0, 1.0], [9420, 5996.45, 600.0, 5387.88, 600.0, 1.0], [9480, 5948.36, 600.0, 5339.16, 600.0, 1.0], [9540, 5894.49, 600.0, 5284.62, 600.0, 1.0], [9600, 5835.17, 600.0, 5224.6, 600.0, 1.0], [9660, 5770.77, 600.0, 5159.48, 600.0, 1.0], [9720, 5701.68, 600.0, 5089.67, 600.0, 1.0], [9780, 5628.31, 600.0, 5015.59, 600.0, 1.0], [9840, 5551.08, 600.0, 4937.7, 600.0, 1.0], [9900, 5470.46, 600.0, 4856.46, 600.0, 1.0], [9960, 5386.9, 600.0, 4772.34, 600.0, 1.0], [10020, 5300.88, 600.0, 4685.83, 600.0, 1.0], [10080, 5212.85, 600.0, 4597.41, 600.0, 1.0], [10140, 5123.31, 600.0, 4507.57, 600.0, 1.0], [10200, 5032.72, 600.0, 4416.8, 600.0, 1.0], [10260, 4941.56, 600.0, 4325.56, 600.0, 1.0], [10320, 4850.28, 600.0, 4234.33, 600.0, 1.0], [10380, 4759.34, 600.0, 4143.56, 600.0, 1.0], [10440, 4658.74, 600.0, 4046.74, 600.0, 1.0], [10500, 4531.25, 600.0, 3925.19, 600.0, 1.0], [10560, 4377.87, 600.0, 3779.19, 600.0, 1.0], [10620, 4200.13, 600.0, 3610.32, 600.0, 1.0], [10680, 3999.81, 600.0, 3420.45, 600.0, 1.0], [10740, 3778.97, 600.0, 3211.72, 600.0, 1.0], [10800, 3539.93, 600.0, 2986.55, 600.0, 1.0], [10860, 3285.25, 600.0, 2747.61, 600.0, 1.0], [10920, 3017.74, 600.0, 2497.82, 600.0, 1.0], [10980, 2740.45, 600.0, 2240.36, 600.0, 1.0], [11040, 2456.64, 600.0, 1978.64, 600.0, 1.0], [11100, 2169.82, 600.0, 1716.29, 600.0, 1.0], [11160, 1883.67, 600.0, 1457.18, 600.0, 1.0], [11220, 1602.11, 600.0, 1205.37, 600.0, 1.0], [11280, 1329.22, 600.0, 965.12, 600.0, 1.0], [11340, 1069.27, 600.0, 740.86, 600.0, 1.0], [11400, 826.69, 600.0, 537.22, 600.0, 1.0], [11460, 606.05, 600.0, 358.96, 600.0, 1.0], [11520, 394.38, 600.0, 213.0, 600.0, 1.0], [11580, 189.48, 600.0, 88.01, 600.0, 1.0], [11640, 42.85, 600.0, 10.28, 600.0, 1.0]]],
    [128, 0, [[1814, -4.0, 600.0, -4.0, 600.0, 1.0], [1874, -4.0, 600.0, -4.0, 600.0, 1.0], [1934, 23.03, 600.0, 23.03, 600.0, 1.0], [1994, 92.1, 600.0, 92.1, 600.0, 1.0], [2054, 207.13, 600.0, 207.13, 600.0, 1.0], [2114, 368.02, 600.0, 368.02, 600.0, 1.0], [2174, 574.58, 600.0, 574.58, 600.0, 1.0], [2234, 826.62, 600.0, 826.62, 600.0, 1.0], [2294, 1123.88, 600.0, 1123.88, 600.0, 1.0], [2354, 1466.04, 600.0, 1466.04, 600.0, 1.0], [2414, 1852.77, 600.0, 1852.77, 600.0, 1.0], [2474, 2283.66, 600.0, 2283.66, 600.0, 1.0], [2534, 2758.28, 600.0, 2758.28, 600.0, 1.0], [2594, 3276.13, 600.0, 3276.13, 600.0, 1.0], [2654, 3836.69, 600.0, 3836.69, 600.0, 1.0], [2714, 4439.39, 600.0, 4439.39, 600.0, 1.0], [2774, 5083.61, 600.0, 5083.61, 600.0, 1.0], [2834, 5768.68, 600.0, 5768.68, 600.0, 1.0], [2894, 6493.92, 600.0, 6493.92, 600.0, 1.0], [2954, 7258.57, 600.0, 7258.57, 600.0, 1.0], [3014, 8061.85, 600.0, 8061.85, 600.0, 1.0], [3074, 8902.94, 600.0, 8902.94, 600.0, 1.0], [3134, 9780.99, 600.0, 9780.99, 600.0, 1.0], [3194, 10695.09, 600.0, 10695.09, 600.0, 1.0], [3254, 11644.3, 600.0, 11644.3, 600.0, 1.0], [3314, 12627.66, 600.0, 12627.66, 600.0, 1.0], [3374, 13644.16, 600.0, 13644.16, 600.0, 1.0], [3434, 14692.76, 600.0, 14692.76, 600.0, 1.0], [3494, 15772.39, 600.0, 15772.39, 600.0, 1.0], [3554, 16881.94, 600.0, 16881.94, 600.0, 1.0], [3614, 18020.28, 600.0, 18020.28, 600.0, 1.0], [3674, 19186.23, 600.0, 19186.23, 600.0, 1.0], [3734, 20378.62, 600.0, 20378.62, 600.0, 1.0], [3794, 21596.21, 600.0, 21596.21, 600.0, 1.0], [3854, 22837.77, 600.0, 22837.77, 600.0, 1.0], [3914, 24102.02, 600.0, 24102.02, 600.0, 1.0], [3974, 25387.67, 600.0, 25387.67, 600.0, 1.0], [4034, 26693.4, 600.0, 26693.4, 600.0, 1.0], [4094, 28017.88, 600.0, 28017.88, 600.0, 1.0], [4154, 29359.76, 600.0, 29359.76, 600.0, 1.0], [4214, 30717.65, 600.0, 30717.65, 600.0, 1.0], [4274, 32090.17, 600.0, 32090.17, 600.0, 1.0], [4334, 33475.91, 600.0, 33475.91, 600.0, 1.0], [4394, 34873.46, 600.0, 34873.46, 600.0, 1.0], [4454, 36281.39, 600.0, 36281.39, 600.0, 1.0], [4514, 37698.26, 600.0, 37698.26, 600.0, 1.0], [4574, 39122.61, 600.0, 39122.61, 600.0, 1.0], [4634, 40552.99, 600.0, 40552.99, 600.0, 1.0], [4694, 41987.94, 600.0, 41987.94, 600.0, 1.0], [4754, 43425.98, 600.0, 43425.98, 600.0, 1.0], [4814, 44865.08, 600.0, 44865.08, 600.0, 1.0], [4874, 46264.13, 600.0, 46264.13, 600.0, 1.0], [4934, 47377.51, 600.0, 47377.51, 600.0, 1.0], [4994, 47953.67, 600.0, 47953.67, 600.0, 1.0], [5054, 48000.0, 600.0, 48000.0, 600.0, 1.0], [5114, 48000.0, 600.0, 48000.0, 600.0, 1.0], [5174, 48000.0, 600.0, 48000.0, 600.0, 1.0], [5234, 47737.23, 600.0, 47737.23, 600.0, 1.0], [5294, 46298.1, 600.0, 46298.1, 600.0, 1.0], [5354, 44858.9, 600.0, 44858.9, 600.0, 1.0], [5414, 43419.71, 600.0, 43419.71, 600.0, 1.0], [5474, 41980.51, 600.0, 41980.51, 600.0, 1.0], [5534, 40541.32, 600.0, 40541.32, 600.0, 1.0], [5594, 39102.12, 600.0, 39102.12, 600.0, 1.0], [5654, 37662.93, 600.0, 37662.93, 600.0, 1.0], [5714, 36223.74, 600.0, 36223.74, 600.0, 1.0], [5774, 34784.54, 600.0, 34784.54, 600.0, 1.0], [5834, 33345.35, 600.0, 33345.35, 600.0, 1.0], [5894, 31906.15, 600.0, 31906.15, 600.0, 1.0], [5954, 30466.96, 600.0, 30466.96, 600.0, 1.0], [6014, 29027.76, 600.0, 29027.76, 600.0, 1.0], [6074, 27588.57, 600.0, 27588.57, 600.0, 1.0], [6134, 26149.37, 600.0, 26149.37, 600.0, 1.0], [6194, 24710.18, 600.0, 24710.18, 600.0, 1.0], [6254, 23270.98, 600.0, 23270.98, 600.0, 1.0], [6314, 21831.79, 600.0, 21831.79, 600.0, 1.0], [6374, 20392.6, 600.0, 20392.6, 600.0, 1.0], [6434, 18953.4, 600.0, 18953.4, 600.0, 1.0], [6494, 17514.21, 600.0, 17514.21, 600.0, 1.0], [6554, 16075.01, 600.0, 16075.01, 600.0, 1.0], [6614, 14636.87, 600.0, 14636.87, 600.0, 1.0], [6674, 13209.41, 600.0, 13209.41, 600.0, 1.0], [6734, 11804.48, 600.0, 11804.48, 600.0, 1.0], [6794, 10433.44, 600.0, 10433.44, 600.0, 1.0], [6854, 9107.44, 600.0, 9107.44, 600.0, 1.0], [6914, 7837.2, 600.0, 7837.2, 600.0, 1.0], [6974, 6633.05, 600.0, 6633.05, 600.0, 1.0], [7034, 5504.73, 600.0, 5504.73, 600.0, 1.0], [7094, 4461.41, 600.0, 4461.41, 600.0, 1.0], [7154, 3511.53, 600.0, 3511.53, 600.0, 1.0], [7214, 2662.81, 600.0, 2662.81, 600.0, 1.0], [7274, 1922.12, 600.0, 1922.12, 600.0, 1.0], [7334, 1295.47, 600.0, 1295.47, 600.0, 1.0], [7394, 787.94, 600.0, 787.94, 600.0, 1.0], [7454, 403.65, 600.0, 403.65, 600.0, 1.0], [7514, 145.71, 600.0, 145.71, 600.0, 1.0], [7574, 16.21, 600.0, 16.21, 600.0, 1.0], [7634, -4.0, 600.0, -4.0, 600.0, 1.0], [7664, -4.0, 600.0, -4.0, 600.0, 1.0]]],
    [129, 0, [[614, -4.0, 400.0, -4.0, 400.0, 1.0], [1024, 471.0, 1500.0, 20.0, 700.0, 1.0], [1414, 1270.0, 2200.0, 60.0, 1500.0, 1.0], [1912, 2200.0, 2400.0, 120.0, 1600.0, 1.0], [2251, 2472.4, 2300.0, 2052.4, 1700.0, 1.0], [2355, 2340.0, 2000.0, 2280.0, 1900.0, 1.0], [2761, 1904.5, 1900.0, 2104.5, 2200.0, 1.0], [3052, 1030.0, 1300.0, 1599.9, 1900.0, 1.0], [3208, 1034.0, 1200.0, 1034.0, 1200.0, 1.0], [3612, 2093.2, 2200.0, 1034.0, 1500.0, 1.0], [4036, 3150.0, 2500.0, 1040.0, 1600.0, 1.0], [4298, 3204.3, 1600.0, 1150.0, 1600.0, 1.0], [4471, 1900.0, 1600.0, 1200.0, 1600.0, 1.0], [4770, 1900.0, 1600.0, 1200.0, 1600.0, 1.0], [5032, 3644.6, 1900.0, 1200.0, 1600.0, 1.0], [5354, 1500.0, 1500.0, 1500.0, 1500.0, 1.0], [5442, 1500.0, 1400.0, 1500.0, 1400.0, 1.0], [5478, 1500.0, 1400.0, 1500.0, 1400.0, 760.0], [5558, 1500.0, 1400.0, 1500.0, 1400.0, 760.0], [5602, 1500.0, 1400.0, 1500.0, 1400.0, 1.0], [5939, 3389.2, 2400.0, 1250.0, 1600.0, 1.0], [6454, 3320.5, 2300.0, 1200.0, 1600.0, 1.0], [6878, 2715.9, 2000.0, 2565.9, 1800.0, 1.0], [7288, 1997.3, 1900.0, 2047.3, 2000.0, 1.0], [7879, 1233.4, 1700.0, 1193.4, 1600.0, 1.0], [8516, 387.6, 1100.0, 367.6, 1000.0, 1.0], [8905, 88.4, 600.0, 78.4, 600.0, 1.0], [9155, -4.0, 400.0, -4.0, 400.0, 1.0]]],
  ];
  // [road, [[sample, width m], ...]]: the roads whose width changes along them (a straight line from key to key)
  const NET_WIDTHS = [[128, [[0, 200.0], [544, 200.0], [764, 800.0], [12125, 800.0], [12345, 200.0], [12889, 200.0]]]];
  // the roads sampled every NET_STEP of their deck, flown at the speed along it (Mount Hyperion's)
  const NET_DECK = [128];
  // [road, [[sample, m], ...] on its left, the same on its right]: the open edges' aprons (the deck runs on level that much further before its ramp and wall; a smoothstep from key to key, none outside them)
  const NET_APRONS = [[116, [[1536, 0.0], [1736, 150.0], [8773, 150.0], [8973, 0.0]], []], [117, [[1586, 0.0], [1786, 150.0], [4718, 150.0], [4918, 0.0]], [[4347, 0.0], [4547, 150.0], [4718, 150.0], [4918, 0.0]]], [129, [[2996, 0.0], [3076, 60.0], [3156, 0.0], [4353, 0.0], [4553, 150.0], [4732, 150.0], [4932, 0.0], [5174, 0.0], [5374, 150.0], [5561, 150.0], [5761, 0.0]], [[707, 0.0], [907, 150.0], [1926, 150.0], [2126, 0.0], [3264, 0.0], [3464, 150.0], [6535, 150.0], [6735, 0.0]]]];
  // </network>
  // The courses: straights and exact arcs, sampled every ~12 m. widths: per mode (else GP_WIDTH,
  // constant); widthR: the width-easing box (samples); banks: per mode, degrees (else GP_BANK in
  // the corners), each mode's eased by two passes of its own box, bankR (samples; else GP_BANK_R).
  const CARVING_SEGS = [["S",3000.0,0.0,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7000.0,25.2,"sp"],["R",7000.0,2.7,"sp"],["S",977.1199743205441,0.0,"sp"],["R",7000.0,2.7,"sp"],["L",7000.0,25.2,"sp"],["L",7000.0,25.2,"sp"],["R",7000.0,2.7,"sp"],["S",977.1199743205441,0.0,"sp"],["R",7000.0,2.7,"sp"],["L",7000.0,25.2,"sp"],["S",2500.0,0.0,"sp"],["L",9800.0,25.2,"sp"],["R",9800.0,2.6999999999999997,"sp"],["S",1367.967964048762,0.0,"sp"],["R",9800.0,2.6999999999999997,"sp"],["L",9800.0,25.2,"sp"],["L",9800.0,25.2,"sp"],["R",9800.0,2.6999999999999997,"sp"],["S",1367.967964048762,0.0,"sp"],["R",9800.0,2.6999999999999997,"sp"],["L",9800.0,25.2,"sp"],["S",3000.0,0.0,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",6000.0,0.9333333333333333,"sp"],["S",293.1038242710362,0.0,"sp"],["L",6000.0,0.9333333333333333,"sp"],["R",6000.0,20.933333333333334,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["S",967.5628110900652,0.0,"sp"],["R",7699.999999999999,2.4000000000000012,"sp"],["L",7699.999999999999,22.400000000000002,"sp"],["L",7000.0,25.2,"sp"],["R",7000.0,2.7,"sp"],["S",977.1199743205441,0.0,"sp"],["R",7000.0,2.7,"sp"],["L",7000.0,25.2,"sp"],["L",7000.0,25.2,"sp"],["R",7000.0,2.7,"sp"],["S",977.1199743205441,0.0,"sp"],["R",7000.0,2.7,"sp"],["L",7000.0,25.2,"sp"],["S",2500.0,0.0,"sp"],["L",9800.0,25.2,"sp"],["R",9800.0,2.6999999999999997,"sp"],["S",1367.967964048762,0.0,"sp"],["R",9800.0,2.6999999999999997,"sp"],["L",9800.0,25.2,"sp"],["L",9800.0,25.2,"sp"],["R",9800.0,2.6999999999999997,"sp"],["S",1367.967964048762,0.0,"sp"],["R",9800.0,2.6999999999999997,"sp"],["L",9800.0,25.2,"sp"]];
  const COURSES = {
    carving: { segs: CARVING_SEGS, checkpoints: 16, widths: {sf:200,sp:200}, widthR:0, banks:{sf:0,sp:0} },
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
          for (let k = 0; k < n; k++) { pts.push({ x, y, mode, kap: 0, gs: 0 }); x += d * Math.cos(h); y += d * Math.sin(h); }
        } else if (sg[0] === 'W') {
          // a wall: straight in plan, sg[1] m of deck at a pitch of sg[2] degrees, a sample every NET_STEP of the deck
          const n = Math.max(1, Math.round(sg[1] / NET_STEP)), d = sg[1] / n * Math.cos(sg[2] * Math.PI / 180);
          for (let k = 0; k < n; k++) { pts.push({ x, y, mode, kap: 0, gs: 0 }); x += d * Math.cos(h); y += d * Math.sin(h); }
        } else if (sg[0] === 'V') {
          // a vertical arc: straight in plan, the deck a circle of radius sg[1] in profile from a pitch of sg[2]
          // degrees to one of sg[4], a sample every NET_STEP of the deck (each step's plan: its chord's)
          const a0 = sg[2] * Math.PI / 180, a1 = sg[4] * Math.PI / 180;
          const n = Math.max(1, Math.round(sg[1] * Math.abs(a1 - a0) / NET_STEP)), da = (a1 - a0) / n, c = 2 * sg[1] * Math.sin(Math.abs(da) / 2);
          for (let k = 0; k < n; k++) {
            pts.push({ x, y, mode, kap: 0, gs: 0 });
            const d = c * Math.cos(a0 + (k + 0.5) * da);
            x += d * Math.cos(h); y += d * Math.sin(h);
          }
        } else {
          const r = sg[1], sn = sg[0] === 'L' ? 1 : -1, ang = sg[2] * Math.PI / 180;
          const n = Math.max(1, Math.ceil(r * ang / NET_STEP)), da = ang / n, c = 2 * r * Math.sin(da / 2);
          for (let k = 0; k < n; k++) {
            pts.push({ x, y, mode, kap: sn / r, gs: 0 });
            x += c * Math.cos(h + sn * da / 2); y += c * Math.sin(h + sn * da / 2); h += sn * da;
          }
        }
      }
      pts.push({ x, y, mode, kap: 0, gs: 0 });
      const N = pts.length;
      let s = 0;
      for (let i = 0; i < N; i++) {
        const a = pts[i], b = pts[i + 1];
        const dx = b ? b.x - a.x : NET_STEP * Math.cos(h), dy = b ? b.y - a.y : NET_STEP * Math.sin(h), L = Math.hypot(dx, dy);
        a.tx = dx / L; a.ty = dy / L; a.nx = -a.ty; a.ny = a.tx; a.len = L; a.s = s; s += L;
        a.w = width; a.bank = 0;
      }
      return { name, pts, N, length: s, width, jx: [], sjx: [] };
    });
    // the roads whose width changes along them, and the deck roads (mirrors craft_sim.gd)
    for (const [r, keys] of NET_WIDTHS) {
      for (let k = 0; k < keys.length - 1; k++) {
        const [i0, w0] = keys[k], [i1, w1] = keys[k + 1];
        for (let i = i0; i <= i1; i++) roads[r].pts[i].w = w0 + (w1 - w0) * ((i - i0) / Math.max(1, i1 - i0));
      }
    }
    roads.forEach((R) => { R.deck = false; });
    for (const r of NET_DECK) roads[r].deck = true;
    // the open edges' aprons: a smoothstep from key to key, none outside them (mirrors craft_sim.gd)
    for (const [r, left, right] of NET_APRONS) {
      roads[r].pts.forEach((p) => { p.al = 0; p.ar = 0; });
      [left, right].forEach((keys, side) => {
        for (let k = 0; k < keys.length - 1; k++) {
          const [i0, m0] = keys[k], [i1, m1] = keys[k + 1];
          for (let i = i0; i <= i1; i++) {
            const u = (i - i0) / Math.max(1, i1 - i0), wide = m0 + (m1 - m0) * (u * u * (3 - 2 * u));
            if (side === 0) roads[r].pts[i].al = wide; else roads[r].pts[i].ar = wide;
          }
        }
      });
    }
    const junctions = NET_JUNCTIONS.map(([a, a0, a1, b, b0, b1, sense]) => ({ a, a0, a1, b, b0, b1, sense }));
    junctions.forEach((J, k) => { roads[J.a].jx.push(k); roads[J.b].jx.push(k); });
    const surfaceJunctions = junctions.concat(NET_OVERLAPS.map(([a, a0, a1, b, b0, b1, sense]) => ({ a, a0, a1, b, b0, b1, sense })));
    surfaceJunctions.forEach((J, k) => { roads[J.a].sjx.push(k); roads[J.b].sjx.push(k); });
    const cities = NET_CITIES.map(([name, biome, cx, cy, road, i]) => ({ name, biome, cx, cy, road, i }));
    // Phase 3: the roads' heights (real now: the deck lock), their roles (a launch spur's end is a
    // lip; a catch deck reaches up for a jump; an on-ramp starts on the open ground), which ends are
    // open (no junction holds them: run off one and you're free), and a grid of sample runs per
    // NET_CELL square, so a free body finds what's under it
    const hk = new Map(NET_HEIGHTS.map(([r, keys]) => [r, keys]));
    roads.forEach((R, k) => { R.hk = hk.get(k) || null; R.role = ''; R.open0 = true; R.open1 = true; });
    NET_JUMPS.forEach(([l, c]) => { roads[l].role = 'launch'; roads[c].role = 'catch'; });
    NET_ONRAMPS.forEach(([, r]) => { roads[r].role = 'on'; });
    // The shafts: flat in the sims, a paperclip whose bulb carries you round (kap: its curvature, which
    // turns a body with the road, nothing to steer) and whose height is the real altitude along the
    // shape the view draws (gs: the slope, so gravity pulls along the climb). Outside the stretch
    // between the feet, a road like any other.
    roads.forEach((R) => { R.shaft = false; });
    NET_SHAFTS.forEach(([r, i0, i1]) => {
      const R = roads[r];
      R.shaft = true; R.sh0 = i0; R.sh1 = i1;
      for (let i = 0; i < R.N; i++) {
        const a = R.pts[i];
        if (i < i0 || i >= i1) { a.kap = 0; a.gs = 0; continue; }
        a.gs = (netHeight({ roads }, r, i + 0.5) - netHeight({ roads }, r, i - 0.5)) / a.len;
      }
    });
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
      cells, jumps: NET_JUMPS, onramps: NET_ONRAMPS, shafts: NET_SHAFTS, twists: NET_TWISTS, surfaceJunctions };
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
  // A shaft road's turn (radians, + to the left going up its samples) over ds m of its centreline, for
  // a body `off` m along sample i's chord and `lat` m left of it: the curvature is a sample's own (kap),
  // so a stretch that crosses samples takes each one's share. ds < 0 is down the samples. The body's
  // place along the chord is first read as a place on the centreline: off the road's middle its lane's
  // arc is shorter or longer than the centreline's, and meets the next sample's where the two chords'
  // corner is halved, not square to this chord (taken square, a lane 60 m out changed arcs 0.15 m early
  // or late and came away 0.005 deg off the road each time).
  function shaftTurn(R, i, off, lat, ds) {
    { const a = R.pts[i]; if (a.kap !== 0) off = a.len / 2 + (off - a.len / 2) / (1 - a.kap * lat); }
    while (off < 0 && i > 0) { i--; off += R.pts[i].len; }
    while (off > R.pts[i].len && i < R.N - 1) { off -= R.pts[i].len; i++; }
    const way = ds >= 0 ? 1 : -1;
    let turn = 0, left = Math.abs(ds);
    for (let guard = 0; left > 0 && guard < 64; guard++) {
      const a = R.pts[i], room = Math.max(0, way > 0 ? a.len - off : off);
      if (left <= room || (way > 0 ? i >= R.N - 1 : i <= 0)) { turn += a.kap * left * way; break; }
      turn += a.kap * room * way; left -= room;
      i += way; off = way > 0 ? 0 : R.pts[i].len;
    }
    return turn;
  }
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
  // A road's climb at (fractional) sample i, metres a sample: the slope of netHeight's cubic there.
  function netSlope(T, r, i) {
    const K = T.roads[r].hk;
    if (!K) return 0;
    for (let k = 0; k < K.length - 1; k++) {
      const a = K[k], b = K[k + 1];
      if (i >= a[0] && i <= b[0]) {
        const n = Math.max(1, b[0] - a[0]), u = (i - a[0]) / n, d = n * NET_STEP, u2 = u * u;
        return ((6 * u2 - 6 * u) * a[1] + (3 * u2 - 4 * u + 1) * d * a[2] + (-6 * u2 + 6 * u) * b[1] + (3 * u2 - 2 * u) * d * b[2]) / n;
      }
    }
    return 0;
  }
  // The deck roads (NET_DECK: Mount Hyperion's). Every other road is sampled every NET_STEP of the map and
  // a body's speed is its speed over the map, whatever the grade. A deck road is sampled every NET_STEP of
  // its DECK, and a body on it travels at its speed along the deck: over the map, that speed times the
  // cosine of the deck's pitch along the road (step, railHover). The sine of the deck's pitch at sample f
  // of a deck road (+: climbing the way its samples run); 0 on any other road. Mirrors craft_sim.gd deck_sine.
  // (T.deckRule false: no road is treated as a deck road, and every body moves at its speed over the map as all
  // did before there was one. A test's switch, as craft_sim.gd's deck_rule.)
  function deckSine(T, r, f) {
    if (T.deckRule === false || !T.roads[r].deck) return 0;
    return clamp(netSlope(T, r, f) / NET_STEP, -0.9999, 0.9999);
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
  // The open edges' aprons (NET_APRONS; Luke, 2026-11-22: "Extend the transparent edges on the coastal road
  // and the drop so you can drive farther over the beach and ocean"): where a scenic road's land falls
  // away on a side, its deck runs on level for the apron's width before that side's ramp and wall. The
  // edge code (netEdge, the walls) is given the offset with the apron taken out of that side. `a`: the
  // road's sample (al, ar: its aprons, only on the roads that have them), `b` the next (or a again at
  // the road's end), `t` how far along the sample the point is (0..1): the apron's width runs straight
  // from one sample's to the next's, so its wall comes in at a slant and not in steps.
  function netLat(a, b, t, lat) {
    if (a.al === undefined) return lat;
    return lat > 0 ? Math.max(0, lat - (a.al + (b.al - a.al) * t)) : Math.min(0, lat + (a.ar + (b.ar - a.ar) * t));
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
        best = { i, lat: netLat(a, B.pts[Math.min(i + 1, B.N - 1)], t, (x - a.x) * a.nx + (y - a.y) * a.ny), w: a.w, nx: a.nx, ny: a.ny, tx: a.tx, ty: a.ty, off: (i === 0 && u < 0) || (i === B.N - 1 && u > 1),
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
  function body(m, I) { return { m, I, x: 0, y: 0, vx: 0, vy: 0, th: 0, w: 0, fx: 0, fy: 0, t: 0, hint: 0, path: 0, contact: [false, false], z: 0, vz: 0, grip: 1, touch: new Set(), offRoad: false, lock: false, lockGap: 0, lockV: 0 }; }
  function applyAt(b, fx, fy, px, py) {
    b.fx += fx; b.fy += fy; b.t += (px - b.x) * fy - (py - b.y) * fx;
  }
  function pointVel(b, px, py) { return [b.vx - b.w * (py - b.y), b.vy + b.w * (px - b.x)]; }

  function makeSim(overrides) {
    const vehicle = overrides && overrides.vehicle === 'shrike' ? 'shrike' : 'phaethon';
    const chassis = vehicle === 'shrike' ? { engineMass: 1000, podMass: 410, engineGap: 7.2, cableLen: 12.5 } : {};
    overrides = Object.assign({}, chassis, overrides, { vehicle });
    // the grand prix is a STARFIGHTER track unless a handling is asked for
    const hname = (overrides && overrides.handling) || (COURSES[(overrides && overrides.track) || ''] && overrides.track !== 'carving' ? 'starfighter' : DEFAULTS.handling);
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
      hwant: hname, hblend: hname === 'starfighter' ? 1 : 0, carryTurn: 0,
      battery: 1, armed: false, mode: 'normal', boost: 0, binderBroken: false, crashT: 0, time: 0, towU: -1, towSwing: 0,
      avoidA: 0, avoidX: 0, avoidY: 0, avoidSrc: '',   // the avoidance field this step: m/s^2, its direction, 'wall' or 'traffic'
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
      for (const k of T.roads[b.path].sjx) {
        const J = T.surfaceJunctions[k];
        let f0, f1, t0, t1, q;
        if (J.a === b.path && b.hint >= J.a0 && b.hint <= J.a1) { f0 = J.a0; f1 = J.a1; t0 = J.b0; t1 = J.b1; q = J.b; }
        else if (J.b === b.path && b.hint >= J.b0 && b.hint <= J.b1) { f0 = J.b0; f1 = J.b1; t0 = J.a0; t1 = J.a1; q = J.a; }
        else continue;
        // a catch deck or an on-ramp is one-way: it lets you off onto its highway, it doesn't take you on
        // against its way (drifting into a deck's merge at speed, on a road rising under one engine, tore
        // the binder)
        const Q = T.roads[q];
        if (Q.role === 'catch' || Q.role === 'on') { const e = Q.pts[Q.N - 1]; if (b.vx * e.tx + b.vy * e.ty < 0) continue; }
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
      S.pressureArc = 0;
      S.pressureWeight = 0;
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
      S.binderBroken = false; S.towU = -1; S.towSwing = 0; S.crashT = 0; S.progressI = idx;
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
    // The avoidance field's cushion (P.avoidD): a circle within its depth of a wall and closing on it asks for
    // what would stop it short; the craft is given the most that any circle asks (avoidApply).
    let avoidOn = false, avoidNeed = 0, avoidNx = 0, avoidNy = 0;
    function avoidWall(b, cx, cy, r, p, n, pen) {
      const cap = T.kind === 'network' ? endCap(p, n, r) : 0;
      const sgn = n.lat > 0 ? -1 : 1, nx = cap !== 0 ? -cap * n.tx : n.nx * sgn, ny = cap !== 0 ? -cap * n.ty : n.ny * sgn;
      const [vx, vy] = pointVel(b, cx, cy), closing = -(vx * nx + vy * ny);
      if (closing <= P.avoidMinV) return;
      const need = closing * closing / (2 * Math.max(-pen - P.avoidGap, P.avoidGap));
      if (need > avoidNeed) { avoidNeed = need; avoidNx = nx; avoidNy = ny; }
    }
    function avoidApply(inp, dt) {
      let ax = 0, ay = 0, src = '';
      // (once it is working it works on down to 0.4 of the threshold: at the threshold itself it would chatter, on
      // and off every few steps, as its own push took the need away)
      const want = avoidNeed * P.avoidGain;
      if (want >= (S.avoidSrc === 'wall' ? 0.4 : 1) * P.avoidMinA) { const a = Math.min(P.avoidMaxA, want); ax = a * avoidNx; ay = a * avoidNy; src = 'wall'; }
      const push = inp.avoidPush;
      if (push && (push[0] !== 0 || push[1] !== 0)) { ax += push[0]; ay += push[1]; if (src === '') src = 'traffic'; }
      let mag = Math.hypot(ax, ay);
      if (mag > P.avoidMaxA) { ax *= P.avoidMaxA / mag; ay *= P.avoidMaxA / mag; mag = P.avoidMaxA; }
      const Pd = S.pod, v = Math.hypot(Pd.vx, Pd.vy);
      if (mag <= 0 || v < P.avoidMinSpeed || (P.limits && S.battery <= 0)) { S.avoidA = 0; S.avoidX = 0; S.avoidY = 0; S.avoidSrc = ''; return; }
      if (P.limits) S.battery = Math.max(0, S.battery - P.avoidDrain * (mag / P.avoidMaxA) * dt);
      const ux = Pd.vx / v, uy = Pd.vy / v, along = ax * ux + ay * uy, across = -ax * uy + ay * ux;   // across: to the path's left
      const dth = Math.max(-P.avoidMaxW, Math.min(P.avoidMaxW, across / v)) * dt, c = Math.cos(dth), s = Math.sin(dth);
      for (const b of S.bodies) {
        const dx = b.x - Pd.x, dy = b.y - Pd.y, u = b.vx;
        b.x = Pd.x + dx * c - dy * s; b.y = Pd.y + dx * s + dy * c;
        b.vx = c * u - s * b.vy; b.vy = s * u + c * b.vy;
        b.th += dth;
        b.fx += b.m * along * ux; b.fy += b.m * along * uy;
      }
      if (S.avoidA === 0) S.events.push({ type: 'avoid', who: src });
      S.avoidA = mag; S.avoidX = ax; S.avoidY = ay; S.avoidSrc = src;
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
        if (pen <= 0 || pen === Infinity) {   // (Infinity: past an open end, no wall)
          b.contact[ci] = false;
          if (avoidOn && pen !== Infinity && pen > -Math.min(P.avoidD, P.avoidShare * n.w)) avoidWall(b, cx, cy, r, p, n, pen);
          return;
        }
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
      if (!P.obstacleCollisions) { b.touch.clear(); return; }
      const inside = new Set();
      for (const o of S.obstacles) {
        if (b.z + 1 < (o.zMin ?? -Infinity) || b.z - 1 > (o.zMax ?? Infinity)) continue;
        for (const [cx, cy, r] of circles) {
          let dx = cx - o.x, dy = cy - o.y, depth = o.r;
          if (o.halfSize > 0) {
            const h = o.halfSize, qx = dx - clamp(dx, -h, h), qy = dy - clamp(dy, -h, h);
            if (qx === 0 && qy === 0) {
              depth = h - Math.max(Math.abs(dx), Math.abs(dy)) + 1;
              if (Math.abs(dx) >= Math.abs(dy)) { dx = dx >= 0 ? 1 : -1; dy = 0; }
              else { dx = 0; dy = dy >= 0 ? 1 : -1; }
            } else { dx = qx; dy = qy; depth = 0; }
          }
          const d = Math.hypot(dx, dy), pen = r + depth - d;
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
    const LOCK_W = 6, LOCK_A = 30 * G;   // relative arrival cushioning; surface-following is separate
    function roadF(b, i = b.hint) {
      const a = T.roads[b.path].pts[i];
      return i + clamp(((b.x - a.x) * a.tx + (b.y - a.y) * a.ty) / a.len, -1, 2);
    }
    function railHover(b, dt, afterMove = false) {
      // Match the view's nearest segment after moving, without altering collision/routing's hint.
      const nearest = afterMove ? nearestOn(b.path, b.x, b.y, b.hint, 2) : null;
      const i = nearest ? nearest.i : b.hint, a = T.roads[b.path].pts[i];
      const f = nearest && !nearest.off ? clamp(roadF(b, i), i, i + 1) : roadF(b, i);
      const lat = (b.x - a.x) * a.nx + (b.y - a.y) * a.ny, vl = b.vx * a.nx + b.vy * a.ny;
      const next = T.roads[b.path].pts[Math.min(i + 1, T.roads[b.path].N - 1)], along = clamp(f - i, 0, 1);   // (for an open apron's width there: netLat)
      const h = roadH(T, b.path, f) + netEdge(a.w, netLat(a, next, along, lat))[0];
      let vs = b.vx * a.tx + b.vy * a.ty;
      if (T.roads[b.path].deck && T.deckRule !== false) vs *= Math.sqrt(1 - deckSine(T, b.path, f) ** 2);   // (a deck road: over the map, its speed along the deck by the cosine of the deck's pitch)
      const dhdt = (roadH(T, b.path, f + vs * dt / a.len) + netEdge(a.w, netLat(a, next, along, lat + vl * dt))[0] - h) / dt;
      if (b.lock) {
        if (!afterMove) {
          // The deck carries its own slope/curvature acceleration. Dampen only
          // arrival motion relative to it, so a fast crest cannot outrun the spring.
          // Retain the gentler 20 g upward cushion; 30 g downward arrests overshoot.
          const acc = clamp(-LOCK_W * LOCK_W * b.lockGap - 2 * LOCK_W * b.lockV, -LOCK_A, 20 * G);
          b.lockV += acc * dt; b.lockGap += b.lockV * dt;
        }
        b.z = h + P.rideH + b.lockGap; b.vz = dhdt + b.lockV;
        // Soft capture above, hard support at touchdown. The spring alone lets
        // fast arrivals tunnel; afterMove checks the new surface without a second integration.
        if (b.lockGap <= 0 || (b.lockGap < 0.05 && Math.abs(b.lockV) < 0.5)) {
          b.z = h + P.rideH; b.vz = dhdt; b.lock = false;
        }
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
            const n = nearestBranch(R, x, y, bi, 8), a = R.pts[n.i];
            const t = clamp(((x - a.x) * a.tx + (y - a.y) * a.ty) / a.len, 0, 1);
            const d = (x - a.x - a.tx * a.len * t) ** 2 + (y - a.y - a.ty * a.len * t) ** 2;
            const old = out.findIndex((q) => q.r === r);
            n.r = r; n.d2 = d;
            // Adjacent cells can contain several runs of one road. Only its actual nearest
            // segment may supply a deck height or wall, not a farther run's extrapolated line.
            if (old < 0) out.push(n);
            else if (d < out[old].d2) out[old] = n;
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
        // a catch deck only takes what's flying along it: crossing another way's deck you fly on through
        if (R.role === 'catch' && Math.abs(b.vx * a.tx + b.vy * a.ty) < 0.7 * Math.hypot(b.vx, b.vy)) continue;
        // A genuine landing supports the nearby linked bodies on this same deck.
        // It cannot grant an entirely below-lip or transverse craft its first catch.
        const linkedCatch = R.role === 'catch' && !S.binderBroken && S.bodies.some(other =>
          other !== b && !other.offRoad && other.path === n.r && Math.abs(other.z-b.z) <= JC_REACH &&
          (other.x-b.x)**2 + (other.y-b.y)**2 <= 2500);
        if (dz >= (linkedCatch ? -JC_REACH : -3) && dz <= (R.role === 'catch' ? JC_REACH : 2.5)) {
          const vs = b.vx * a.tx + b.vy * a.ty, vl = b.vx * a.nx + b.vy * a.ny;
          const dhdt = (roadH(T, n.r, n.i + u + vs * dt / a.len) + netEdge(n.w, n.lat + vl * dt)[0] - h) / dt;
          b.offRoad = false; b.path = n.r; b.hint = n.i; b.contact = [false, false];
          b.lock = Math.abs(dz) > 0.05 || Math.abs(b.vz - dhdt) > 0.5;
          b.lockGap = dz; b.lockV = b.vz - dhdt;
          if (b === S.pod) {
            S.events.push({ type: R.role === 'catch' ? 'catch' : 'onroad', road: n.r, v: Math.abs(b.vz - dhdt), dz });
            S.onGround = false;
          }
          return;
        }
        if (R.role === 'catch' && dz < -3 && dz > -80) {   // under the deck's lip: turned down
          const vs = b.vx * a.tx + b.vy * a.ty, vl = b.vx * a.nx + b.vy * a.ny;
          const dhdt = (roadH(T, n.r, n.i + u + vs * dt / a.len) + netEdge(n.w, n.lat + vl * dt)[0] - h) / dt;
          if (dz > -8) b.z = h + P.rideH - 8;
          if (b.vz > dhdt - 2) b.vz = dhdt - 2;
        }
      }
      // walls from outside, near the ground
      for (const n of ns) {
        if (n.off) continue;
        const R = T.roads[n.r], h = netHeight(T, n.r, n.i) + netEdge(n.w, n.w / 2)[0];   // (at the wall's foot: the ramp's top)
        // The same crossing-deck rule applies to elevated forcefields: otherwise an unrelated
        // approach stops a jump its surface lets through. Ground-level guardrails stay solid.
        const a = R.pts[n.i];
        if (R.role === 'catch' && h > 25 && Math.abs(b.vx * a.tx + b.vy * a.ty) < 0.7 * Math.hypot(b.vx, b.vy)) continue;
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

    // Evaluate endpoint responses before blending; coefficient interpolation can
    // create a mid-transition brake/grip spike. Explicit overrides fall back to P.
    function brakeProfile(profile, speed, mass) {
      const get = k => k in profile ? profile[k] : P[k];
      const active = smooth01((speed-get('frontBrakeV0'))/(get('frontBrakeV1')-get('frontBrakeV0')));
      let cd = get('frontBrakeCd');
      const maxG = get('frontBrakeMaxG');
      if (maxG > 0) cd = Math.min(cd,mass*maxG*G/Math.max(speed*speed,1));
      return [cd > 0 ? active : 0,cd*active,get('brakeTurnG')*active];
    }
    function brakeResponse(speed,mass) {
      const a=brakeProfile(H0,speed,mass), b=brakeProfile(H1,speed,mass);
      return a.map((v,i) => v+(b[i]-v)*S.hblend);
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
      else if (!inGate && !inp.boost) S.battery = Math.min(1, S.battery + P.batteryCharge * dt);   // (no charging under a held boost: a flat battery stays flat until it is let go)
      // The boost: the held one wants charge in the battery when the limits are on, and spends it;
      // a surge is a gift. Neither asked for (the replays, every flight before them): nothing here runs.
      let boostMult = 1;
      S.boost = 0;
      if (inp.boost !== undefined || inp.surge !== undefined) {
        const held = !!inp.boost && !inp.repair && (S.battery > 0 || !P.limits);
        const surge = !!inp.surge && !inp.repair;
        S.boost = (held ? 1 : 0) + (surge ? 1 : 0);
        if (held && P.limits) S.battery = Math.max(0, S.battery - P.boostDrain * dt);
        if (S.boost > 0) boostMult = P.boostMult ** S.boost;
      }
      const speed = Math.hypot(Pd.vx, Pd.vy);

      const gm = inp.thrMul ?? 1;   // the gearbox's pull (its ratio, at its revs; 1 without one)
      let brakeGrip = P.brakeTurnG * Math.max(inp.brkL, inp.brkR) * smooth01((speed - P.frontBrakeV0) / (P.frontBrakeV1 - P.frontBrakeV0));
      if (S.hblend>0 && S.hblend<1) brakeGrip=Math.max(inp.brkL,inp.brkR)*brakeResponse(speed,L.m)[2];
      const line = 1 / lineSpeed() ** 2;   // the Aurora Line: the body's drag in air that goes along with it
      let cruiseDrag = line;
      if (inp.gearOverdrive) {
        // Fourth's baseline drag approaches full-throttle thrust, giving logarithmic
        // speed growth without a terminal speed. Brake drag remains fully effective.
        let driveMult = ramjet ? P.ramjetMult : burner ? P.burnerMult : 1;
        if (S.boost > 0) driveMult *= boostMult;   // (the drag fourth is shaped to follows the boost up: more speed, still no runaway)
        const nominalThrust = 2 * P.thrustMax * (0.87 / P.gate) * driveMult * gm;
        const totalCd = (2 * P.engineCd + P.podCd) * line;
        const referenceSpeed = Math.sqrt(Math.max(1, nominalThrust / totalCd));
        const blend = smooth01((speed / referenceSpeed - 0.6) / 0.2);
        const shapedDrag = nominalThrust * (1 - Math.exp(-speed / (0.65 * referenceSpeed)));
        cruiseDrag = line * (1 + (shapedDrag / Math.max(1, totalCd * speed * speed) - 1) * blend);
      }
      for (const [e, thr, brk] of [[L, inp.thrL, inp.brkL], [R, inp.thrR, inp.brkR]]) {
        const c = Math.cos(e.th), s = Math.sin(e.th);
        let gain = e.flameout || !P.limits ? 0 : Math.max(0, thr - 0.6) * P.heatThrottle + (burner ? P.heatBurner : 0) + (ramjet ? P.heatRamjet : 0);
        if (S.boost > 0 && !e.flameout && P.limits) gain += P.boostHeat * S.boost;
        const cool = P.coolBase + P.coolSpeed * Math.min(1.5, speed / 200) + (e.flameout ? 0.15 : 0);
        e.heat = clamp(e.heat + (gain - cool) * dt, 0, 1.25);
        if (e.heat >= 1 && !e.flameout) { e.flameout = true; S.events.push({ type: 'flameout', who: e === L ? 'L' : 'R' }); }
        if (e.flameout && inp.reignite && e.heat < 0.6) e.flameout = false;
        if (inp.repair) e.health = Math.min(1, e.health + P.repairRate * dt);
        e.sputterT -= dt;
        if (e.sputterT <= 0) { e.sputterT = 0.15; e.sputter = S.rand() < (0.5 - e.health) * 1.2 ? 0.3 : 1; }
        let lever = Math.min(thr, P.gate) / P.gate;
        if (inp.repair) lever = Math.min(lever, 0.6);
        let mult = ramjet ? P.ramjetMult : burner ? P.burnerMult : 1;
        if (S.boost > 0) mult *= boostMult;
        const thrust = e.flameout ? 0 : P.thrustMax * lever * mult * (0.45 + 0.55 * e.health) * e.sputter;
        e.thrust = thrust / P.thrustMax;
        e.fx += thrust * P.forceScale * gm * c; e.fy += thrust * P.forceScale * gm * s;
        // Air brake = quadratic drag plus a linear term, so the flaps still bite at low speed.
        // A constant term keeps the brakes biting across a 100x speed range (smoothed below 2 m/s).
        const v = Math.hypot(e.vx, e.vy);
        e.front = P.frontBrakeCd > 0 ? brk * smooth01((v - P.frontBrakeV0) / (P.frontBrakeV1 - P.frontBrakeV0)) : 0;
        const frontCd = P.frontBrakeMaxG > 0 ? Math.min(P.frontBrakeCd, e.m * P.frontBrakeMaxG * G / Math.max(v * v, 1)) : P.frontBrakeCd;
        let frontDrag=frontCd*e.front;
        if (S.hblend>0 && S.hblend<1) {
          const response=brakeResponse(v,e.m);
          e.front=brk*response[0];
          frontDrag=brk*response[1];
        }
        const cd = (P.engineCd * cruiseDrag + P.brakeCd * brk + frontDrag) * P.forceScale;
        const bl = (P.brakeLin * brk + P.brakeConst * brk / Math.max(v, 2)) * P.forceScale;
        e.fx -= cd * v * e.vx + bl * e.vx; e.fy -= cd * v * e.vy + bl * e.vy;
        const fxp = e.x - c * P.finOffset, fyp = e.y - s * P.finOffset;
        const [pvx, pvy] = pointVel(e, fxp, fyp), vlat = -s * pvx + c * pvy;
        // Low-speed braking permits drift; deployed high-speed flaps restore cornering grip.
        const cap = e.m * G * (P.gripCapG * (1 - 0.45 * brk) + brakeGrip);
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
      const pv = Math.hypot(Pd.vx, Pd.vy), pcd = (P.podCd * cruiseDrag + 0.5 * P.brakeCd * pb) * P.forceScale;
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
        const turnG = wpair * Math.max(0, Pd.vx * pf + Pd.vy * ps2) / G;
        const steer = inp.thrR - inp.thrL + inp.brkL - inp.brkR;
        const load = smoothstep(2.5, 11, Math.abs(turnG)) * smoothstep(0.15, 0.65, steer * Math.sign(turnG));
        const prevSwing = S.towSwing;
        S.towSwing += (Math.sign(turnG) * Math.PI / 60 * load - prevSwing) * (1 - Math.exp(-dt / 0.28));
        const swingRate = (S.towSwing - prevSwing) / dt;
        const tx = mxp - pf * back, ty = myp - ps2 * back;
        const tvx = (L.vx + R.vx) / 2 + wpair * ps2 * back, tvy = (L.vy + R.vy) / 2 - wpair * pf * back;
        const e = (Pd.x - tx) * lx + (Pd.y - ty) * ly + back * Math.sin(S.towSwing);
        const ev = (Pd.vx - tvx) * lx + (Pd.vy - tvy) * ly + back * Math.cos(S.towSwing) * swingRate;
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
        const elv = (Pd.vx - (L.vx + R.vx) / 2) * pf + (Pd.vy - (L.vy + R.vy) / 2) * ps2;
        if (P.towLongK > 0 && (el > 0 || (S.hblend > 0 && elv > 0))) {
          // SF pre-damps closing motion before the slack ends; Speedcraft unchanged.
          const fl = el > 0 ? Math.min(0, -P.towLongK * el - P.towLongC * elv) : -P.towLongC * elv * S.hblend;
          Pd.fx += fl * pf; Pd.fy += fl * ps2;
          L.fx -= fl * pf / 2; L.fy -= fl * ps2 / 2; R.fx -= fl * pf / 2; R.fy -= fl * ps2 / 2;
        }
        const dth = wrap(Pd.th - S.pairTh - S.towSwing);
        const podTw = P.podAlignK * dth + P.podYawDamp * (Pd.w - wpair - swingRate);
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
          const a = T.roads[b.path].pts[b.hint], lat = (b.x - a.x) * a.nx + (b.y - a.y) * a.ny;
          const bk = netEdge(a.w, a.al === undefined ? lat : netLat(a, T.roads[b.path].pts[Math.min(b.hint + 1, T.roads[b.path].N - 1)], clamp(((b.x - a.x) * a.tx + (b.y - a.y) * a.ty) / a.len, 0, 1), lat))[1];
          if (bk === 0) continue;
          const v2 = b.vx * b.vx + b.vy * b.vy;
          const f = P.bank * b.m * (G * Math.tan(bk) + P.bankDown * v2 * Math.sin(bk)) * b.grip * (lat > 0 ? -1 : 1);
          b.fx += f * a.nx; b.fy += f * a.ny;
        }
      }
      const cL = engineCircles(L), cR = engineCircles(R), cP = [[Pd.x, Pd.y, 1.6]];
      if (T.branches.length) updateGates();
      avoidOn = !!inp.avoid; avoidNeed = 0;
      if (T.kind === 'network') {
        for (const [b, c] of [[L, cL], [R, cR], [Pd, cP]]) { if (b.offRoad) freeContact(b, c, dt); else collideWalls(b, c, dt); }
      } else if (T.kind === 'circuit') { collideWalls(L, cL, dt); collideWalls(R, cR, dt); collideWalls(Pd, cP, dt); }
      if (avoidOn) avoidApply(inp, dt); else if (S.avoidA !== 0) { S.avoidA = 0; S.avoidX = 0; S.avoidY = 0; S.avoidSrc = ''; }
      if (S.obstacles.length) { collideObstacles(L, cL); collideObstacles(R, cR); collideObstacles(Pd, cP); }
      bodyPush(L, cL, Pd, cP); bodyPush(R, cR, Pd, cP); bodyPush(L, cL, R, cR);

      // On a deck road (Mount Hyperion's) the craft's speed is its speed along the deck: the cosine of the
      // deck's pitch under the pod, before the move (mirrors craft_sim.gd)
      let deckCos = 1, deckAt = null;
      if (T.deckRule !== false && T.kind === 'network' && !Pd.offRoad && T.roads[Pd.path].deck) {
        deckAt = T.roads[Pd.path].pts[Pd.hint];
        deckCos = Math.sqrt(1 - deckSine(T, Pd.path, roadF(Pd)) ** 2);
      }
      // the road under the pod, on a shaft (null off one): what carries the craft; and between its feet
      // (and a step's reach each side of them) the craft is moved together
      const shaftRoad = T.kind === 'network' && !Pd.offRoad && T.roads[Pd.path].shaft ? T.roads[Pd.path] : null;
      const shaftAt = shaftRoad !== null ? shaftRoad.pts[Pd.hint] : null;
      const carrying = shaftRoad !== null && Pd.hint >= shaftRoad.sh0 - 2 && Pd.hint <= shaftRoad.sh1 + 1;
      const carried = [];
      // ... and the way its gravity pulls: along the road's own direction under the pod, which round the
      // bulb is its arc's there, not its sample's chord's (a chord's direction is the arc's only at its
      // middle; a lane off the road's middle spends each sample off-centre, and 300 mph up a wall the
      // difference carried it 3 m across)
      let gravX = 0, gravY = 0;
      if (shaftAt !== null && shaftAt.gs !== 0) {
        gravX = shaftAt.tx; gravY = shaftAt.ty;
        if (shaftAt.kap !== 0) {
          const off = (Pd.x - shaftAt.x) * shaftAt.tx + (Pd.y - shaftAt.y) * shaftAt.ty, lat = (Pd.x - shaftAt.x) * shaftAt.nx + (Pd.y - shaftAt.y) * shaftAt.ny;
          const bend = (off - shaftAt.len / 2) * shaftAt.kap / (1 - shaftAt.kap * lat), c = Math.cos(bend), s = Math.sin(bend);
          gravX = c * shaftAt.tx - s * shaftAt.ty; gravY = s * shaftAt.tx + c * shaftAt.ty;
        }
      }
      for (const b of S.bodies) {
        // in the air (the Network, off the roads), the forces along its path act along it: thrust
        // minus drag scales its climb as it scales its speed, so only gravity bends the line (let
        // off at 4,000 mph and the 16 g of drag would otherwise steepen it)
        if (T.kind === 'network' && b.offRoad) {
          const vh = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
          if (vh > 50) b.vz += (b.fx * b.vx + b.fy * b.vy) / (b.m * vh) * (b.vz / vh) * dt;
        }
        // up a shaft: gravity along the climb, and round its bulb the road turns the craft with it. To the
        // craft that stretch is straight (it's the shaft's, in the world), so the craft is carried WHOLE:
        // one slope and one turn for all three bodies, the road's under the pod (shaftAt), and between
        // the shaft's feet they are moved together, below. Carried a body at a time, each by the road
        // under itself, the craft was bent along the plan's arc (the engines are 22 m up the road from
        // the pod); the cables and the binder know only the plan, and steered it 1.2% further than the
        // road turned (0.23 deg/s at 4,000 mph), so hands off it crept across to the wall and came out
        // askew. (Luke: "enter and exit straight with no sideways or spin".) A body the pod is not
        // with keeps the old rule.
        let carry = 0, reach = 0, kt = null;
        const whole = shaftAt !== null && !b.offRoad && b.path === Pd.path;
        if (whole) {
          if (shaftAt.gs !== 0) { b.fx -= b.m * G * shaftAt.gs * gravX; b.fy -= b.m * G * shaftAt.gs * gravY; }
        } else if (T.kind === 'network' && !b.offRoad && T.roads[b.path].shaft) {
          const a = T.roads[b.path].pts[b.hint];
          if (a.gs !== 0) { b.fx -= b.m * G * a.gs * a.tx; b.fy -= b.m * G * a.gs * a.ty; }
          if (a.kap !== 0) { carry = a.kap * (b.vx * a.tx + b.vy * a.ty) * dt; reach = -a.kap * ((b.x - a.x) * a.nx + (b.y - a.y) * a.ny); kt = a; }
        }
        b.vx += b.fx / b.m * dt; b.vy += b.fy / b.m * dt; b.w += b.t / b.I * dt;
        b.w *= 1 - 0.5 * dt;
        if (whole && carrying) { carried.push(b); continue; }
        if (carry !== 0) { const c = Math.cos(carry / 2), s = Math.sin(carry / 2), u = b.vx; b.vx = c * u - s * b.vy; b.vy = s * u + c * b.vy; }
        b.x += b.vx * dt; b.y += b.vy * dt; b.th += b.w * dt + carry;
        if (kt) { const vs = b.vx * kt.tx + b.vy * kt.ty; b.x += reach * vs * kt.tx * dt; b.y += reach * vs * kt.ty * dt; }
        if (carry !== 0) { const c = Math.cos(carry / 2), s = Math.sin(carry / 2), u = b.vx; b.vx = c * u - s * b.vy; b.vy = s * u + c * b.vy; }
        // Match the moved position: a pre-move deck height sinks a climbing craft by speed * dt.
        // Catch springs already advanced above; afterMove projects their contact only.
        if (T.kind === 'network' && !b.offRoad) railHover(b, dt, true);
      }
      // Between a shaft's feet the craft moves as on a straight road, in a frame that turns with the
      // road under the pod. The turn is the road's own over the stretch of its centreline the pod covers
      // in the step (shaftTurn: taken from the one sample the step began in, each change of curvature
      // left the craft up to 0.09 deg off the road at 4,000 mph, and 21 m across it by the far foot).
      // The pod goes round its own lane of the plan's arc (half the turn each side of its move; the arc
      // is longer on its outside: reach); the others keep their places from it, turned with it, so
      // between themselves the bodies are exactly where a straight road would have them.
      if (carried.length) {
        const a = shaftAt, ds = (Pd.vx * a.tx + Pd.vy * a.ty) * dt;
        const lat = (Pd.x - a.x) * a.nx + (Pd.y - a.y) * a.ny;
        const turn = shaftTurn(shaftRoad, Pd.hint, (Pd.x - a.x) * a.tx + (Pd.y - a.y) * a.ty, lat, ds);
        const reach = ds !== 0 ? -(turn / ds) * lat : 0;
        const ch = Math.cos(turn / 2), sh = Math.sin(turn / 2), c = Math.cos(turn), s = Math.sin(turn);
        const ox = Pd.x, oy = Pd.y, ovx = Pd.vx, ovy = Pd.vy;
        const ux = ch * ovx - sh * ovy, uy = sh * ovx + ch * ovy, us = ux * a.tx + uy * a.ty;
        const px = ox + (ux + reach * us * a.tx) * dt, py = oy + (uy + reach * us * a.ty) * dt;
        for (const b of carried) {
          const rx = b.x - ox + (b.vx - ovx) * dt, ry = b.y - oy + (b.vy - ovy) * dt;
          b.x = px + c * rx - s * ry; b.y = py + s * rx + c * ry;
          const u = b.vx; b.vx = c * u - s * b.vy; b.vy = s * u + c * b.vy;
          b.th += b.w * dt + turn;
          railHover(b, dt, true);
        }
        S.carryTurn += turn;
      }
      // ... so over the map it has travelled that speed times the cosine. The whole craft is set back by what
      // the pod's own move over-ran: one shift for all three bodies, so between themselves they move as on
      // the flat, and each takes its height from where it now is.
      if (deckCos < 1) {
        const back = (1 - deckCos) * (Pd.vx * deckAt.tx + Pd.vy * deckAt.ty) * dt;
        for (const b of S.bodies) {
          if (b.offRoad) continue;
          b.x -= back * deckAt.tx; b.y -= back * deckAt.ty;
          railHover(b, dt, true);
        }
      }
      if (Pd.health <= 0 && S.crashT <= 0) { S.events.push({ type: 'wreck' }); S.crashT = 1.6; Pd.health = 0; }
      if (T.kind === 'network') {
        if (Pd.path === NET_PRESSURE[0] || S.pressureWeight > 0) stepPressure();
        netStep(inp); return;
      }

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
    // The Aurora Line carries its air along with a craft: in the bore the air it meets comes at half its
    // ground speed, so its body's drag is a quarter and the same engines hold twice the speed (mirrors
    // craft_sim.gd line_speed: 1 anywhere else, rising to 2 across each lock's 900 m gallery).
    function lineSpeed() {
      if (!T.roads) return 1;
      const pod = S.pod, [road, first, last] = NET_PRESSURE;
      const R = T.roads[road];
      if (!R || pod.offRoad || pod.path !== road) return 1;
      const depth = Math.min(roadF(pod) - first, last - roadF(pod)) * R.pts[first].len;
      return 1 + smoothstep(0, 900, depth);
    }

    function stepPressure() {
      const pod = S.pod, [road, first, last] = NET_PRESSURE;
      const R = T.roads[road], p = R.pts[first], q = R.pts[pod.hint];
      if (pod.offRoad || pod.path !== road || !q) {
        S.pressureArc = S.pressureWeight = 0;
        return;
      }
      const f = roadF(pod);
      const depth = Math.min(f - first, last - f) * p.len;
      if (depth < 0) { S.pressureArc = S.pressureWeight = 0; return; }
      const lat = (pod.x - p.x) * p.nx + (pod.y - p.y) * p.ny;
      const shift = lat * smoothstep(70, 300, depth);
      const weight = smoothstep(70, 8000, depth), radius = 160;
      S.pressureArc = Math.atan2(Math.sin((S.pressureArc + shift) / radius),
                                 Math.cos((S.pressureArc + shift) / radius)) * radius;
      if (weight < S.pressureWeight) S.pressureArc *= weight / S.pressureWeight;
      S.pressureArc = clamp(S.pressureArc, -Math.PI * radius * weight, Math.PI * radius * weight);
      S.pressureWeight = weight;
      for (const body of S.bodies) { body.x -= p.nx * shift; body.y -= p.ny * shift; }
    }

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
      netSlope: (r, i) => netSlope(T, r, i), deckSine: (r, f) => deckSine(T, r, f),
      // the deck's pitch under body b along its own heading, radians (+: nose up); 0 off the deck roads (mirrors craft_sim.gd deck_pitch)
      deckPitch: (b) => (T.kind !== 'network' || b.offRoad || !T.roads[b.path].deck) ? 0
        : Math.asin(deckSine(T, b.path, roadF(b)) * (Math.cos(b.th) * T.roads[b.path].pts[b.hint].tx + Math.sin(b.th) * T.roads[b.path].pts[b.hint].ty)),
      box: { x: BOX_X, half: BOX_HALF, overrun: OVERRUN } };
  }

  window.PhaethonSim = { makeSim, DEFAULTS, HANDLING, TRACKS, COURSES, xorshift32 };
})();
