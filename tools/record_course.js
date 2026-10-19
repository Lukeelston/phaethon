// Course proof and parity reference: a speed-planning autopilot laps a course (default eridanus,
// the dual-purpose one) and flips the handling as Luke will: SPEEDCRAFT on the speed loop,
// STARFIGHTER in the towns. It plans a target speed along the track from curvature (each mode's
// turn-rate and grip limits, STARFIGHTER's top speed in the towns) and braking distance, steers at
// a point ahead with the levers (inside brake when it's hard), asks for STARFIGHTER once the plan
// says the next stretch is a town's (it engages below 1,250 mph, so asking early is safe) and for
// SPEEDCRAFT back on the loop. Reports the lap, top speed, the switches and wall hits; then the
// rounded input log (with the handling channel) is replayed: that replay is the reference
// godot/tests/test_course_parity.gd must match.
// Inputs: [thrL, thrR, brkL, brkR, h] per 8 x 1/480 s frame; h 0 = no ask, 1 = speed, 2 = starfighter.
// Usage: node tools/record_course.js <sim-core.js> <out_dir> [course]  -> <course>_inputs.json, <course>_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const [simPath, outDir, courseArg] = process.argv.slice(2);
const COURSE = courseArg || 'eridanus';
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, SUB = 8, MAX_T = 600, G = 9.81, MPH = 2.236936;
const SF = { omega: 0.95, aLat: 38 * G, top: 1150 / MPH };   // a little inside each mode's limits
const SP = { aLat: 10 * G, top: 4300 / MPH };
const SWITCH_V = 1200 / MPH;   // the plan reaches each town below this (STARFIGHTER engages at 1,250)
const ASK = [undefined, 'speed', 'starfighter'];
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;

function plan(T) {
  const N = T.N, kap = new Array(N).fill(0), v = new Array(N);
  for (let i = 0; i < N; i++) {
    const a = T.pts[i], b = T.pts[(i + 1) % N];
    kap[i] = Math.abs(wrap(Math.atan2(b.ty, b.tx) - Math.atan2(a.ty, a.tx))) / a.len;
  }
  for (let i = 0; i < N; i++) {
    let k = 0;
    for (let j = -4; j <= 4; j++) k = Math.max(k, kap[(i + j + N) % N]);
    if ((T.pts[i].mode || 'sf') === 'sf') v[i] = k < 1e-6 ? SF.top : Math.min(SF.top, SF.omega / k, Math.sqrt(SF.aLat / k));
    else v[i] = k < 1e-7 ? SP.top : Math.min(SP.top, Math.sqrt(SP.aLat / k));
  }
  // the town's limit reaches back across the blend: STARFIGHTER must have engaged by its first sample
  for (let i = 0; i < N; i++) {
    if ((T.pts[i].mode || 'sf') === 'sf') v[i] = Math.min(v[i], Math.max(SWITCH_V, 0));
  }
  const decel = (s) => (5 + 9 * Math.min(s / 447, 1)) * G;
  for (let pass = 0; pass < 3; pass++) {
    for (let i = N - 1; i >= 0; i--) {
      const nx = v[(i + 1) % N];
      v[i] = Math.min(v[i], Math.sqrt(nx * nx + 2 * decel(nx) * T.pts[i].len));
    }
  }
  return v;
}

function autopilot(S, vplan) {
  const T = S.T, N = T.N, v = Math.hypot(S.pod.vx, S.pod.vy), i = S.pod.hint;
  const lead = Math.ceil((v * 0.35) / 12);
  const target = vplan[(i + lead) % N];
  const aim = T.pts[(i + Math.round((60 + v * (S.P.handling === 'speed' ? 0.5 : 0.36)) / 12)) % N];
  const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
  // aim the craft's path, not its nose: in SPEEDCRAFT it slides, the nose pointing into the curve
  // while it travels wider (STARFIGHTER's grip keeps the two together: the GP autopilot's nose aim)
  const course = S.P.handling === 'speed' ? Math.atan2(S.pod.vy, S.pod.vx) : (S.pairTh ?? 0);
  const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - course);
  const k = Math.max(-1, Math.min(1, err * (S.P.handling === 'speed' ? 3 : 5)));
  const top = 0.87;
  let base = v < target - 4 ? top : Math.max(0, Math.min(top, top * (target / Math.max(v, 1)) - 0.1));
  let brk = Math.max(0, Math.min(1, (v - target - 6) / 25));
  if (S.P.handling === 'speed' && v - target < 50) {
    // SPEEDCRAFT turns hardest on a lever split (~14 g; one brake alone gives ~10): holding speed
    // through a curve, keep the levers in to steer with and bleed the surplus off on both brakes.
    // (A real braking zone, 50 m/s or more over the plan, is levers off, brakes on.)
    const keep = Math.min(top, 0.25 + 0.75 * Math.abs(k));
    if (base < keep) {
      brk = Math.max(brk, Math.min(1, (v - target + 4) / 40));
      base = keep;
    }
    brk = Math.min(brk, 1.0 - 0.8 * Math.min(1, Math.abs(k) / 0.4));   // turning hard: the split needs room to work
  } else if (brk > 0) {
    base = 0;
  }
  // the switch: STARFIGHTER when the plan ahead (2 s) wants town speeds, SPEEDCRAFT on the loop
  const ahead = vplan[(i + Math.ceil(v * 2 / 12)) % N];
  const here = T.pts[i].mode || 'sf';
  const h = here === 'sf' || ahead <= SWITCH_V * 1.05 ? 2 : 1;
  // steering: the levers' difference, the inside brake too when it's hard
  const kb = 0.6, gb = 2;
  return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)),
    Math.max(brk, k > kb ? (k - kb) * gb : 0), Math.max(brk, k < -kb ? (-k - kb) * gb : 0)].map((x) => r4(Math.min(1, x))).concat([h]);
}

function run(inputsOrNull) {
  const sim = makeSim({ track: COURSE }), S = sim.S, log = [], switches = [], hitsAt = [];
  const vplan = plan(S.T);
  let top = 0, hits = 0;
  for (let f = 0; f * SUB * DT < MAX_T; f++) {
    const u = inputsOrNull ? inputsOrNull[f] : autopilot(S, vplan);
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] };
    for (let k = 0; k < SUB; k++) {
      sim.step(inp, DT);
      const v = Math.hypot(S.pod.vx, S.pod.vy);
      top = Math.max(top, v);
      while (S.events.length) {
        const e = S.events.shift();
        if (e.type === 'hit') { hits++; hitsAt.push([S.pod.hint, S.T.pts[S.pod.hint].mode, Math.round(v * MPH), S.P.handling]); }
        if (e.type === 'handling') switches.push([f, e.mode, Math.round(v * MPH)]);
        if (e.type === 'crash') return { log, lap: null, crash: true, frames: f + 1, T: S.T, top, hits, switches, x: S.pod.x, y: S.pod.y, i: S.pod.hint };
        if (e.type === 'lap') return { log, lap: e.t, frames: f + 1, x: S.pod.x, y: S.pod.y, T: S.T, top, hits, switches, hitsAt };
      }
    }
  }
  return { log, lap: null, frames: log.length, T: S.T, top, hits, switches, x: S.pod.x, y: S.pod.y, i: S.pod.hint };
}

const rec = run(null);
const tag = rec.lap === null ? 'NONE' + (rec.crash ? ' (crashed)' : '') : `${rec.lap.toFixed(2)} s (${(rec.lap / 60).toFixed(2)} min)`;
console.log(`${COURSE} autopilot: lap ${tag}, top ${(rec.top * MPH).toFixed(0)} mph, wall hits ${rec.hits}, ` +
  `avg ${rec.lap ? (rec.T.length / rec.lap * MPH).toFixed(0) : '-'} mph, ${rec.switches.length} switches: ${JSON.stringify(rec.switches)}`);
if (rec.hitsAt && rec.hitsAt.length) console.log(`hits at [sample, section, mph, handling]: ${JSON.stringify(rec.hitsAt)}`);
if (rec.lap === null) {
  console.log(`stopped at (${rec.x?.toFixed(0)}, ${rec.y?.toFixed(0)}), sample ${rec.i} of ${rec.T.N} (${rec.T.pts[rec.i]?.mode})`);
  process.exit(1);
}
const rep = run(rec.log);
const expected = { lap_time: rep.lap, frames: rep.frames, final_pod: [rep.x, rep.y], track_length: rep.T.length, track_samples: rep.T.N,
  top_mph: rep.top * MPH, hits: rep.hits, switches: rep.switches };
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, `${COURSE}_inputs.json`), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, `${COURSE}_expected.json`), JSON.stringify(expected, null, 1));
console.log(`replayed ${rep.lap.toFixed(3)} s (${rec.log.length} input frames) -> ${outDir}`);
