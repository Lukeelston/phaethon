// Grand prix proof and parity reference: a speed-planning autopilot laps the GP in STARFIGHTER.
// It plans a target speed along the track from curvature (turn-rate and grip limits) and braking
// distance, steers at a point ahead on the centreline with the levers (inside brake when it's
// hard), and reports the lap, top and corner speeds and wall hits. Then the rounded input log is
// replayed: that replay is the reference godot/tests/test_gp_parity.gd must match.
// Usage: node tools/record_gp.js <sim-core.js> <out_dir>  -> gp_inputs.json, gp_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const [simPath, outDir] = process.argv.slice(2);
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, SUB = 8, MAX_T = 240, G = 9.81, MPH = 2.236936;
const OMEGA = 0.95, A_LAT = 38 * G, V_TOP = 1150 / MPH;   // a little inside the limits
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;

function plan(T) {
  const N = T.N, kap = new Array(N).fill(0), v = new Array(N);
  for (let i = 0; i < N; i++) {
    const a = T.pts[i], b = T.pts[(i + 1) % N];
    kap[i] = Math.abs(wrap(Math.atan2(b.ty, b.tx) - Math.atan2(a.ty, a.tx))) / a.len;
  }
  for (let i = 0; i < N; i++) {   // smooth over +-4 samples
    let k = 0;
    for (let j = -4; j <= 4; j++) k = Math.max(k, kap[(i + j + N) % N]);
    v[i] = k < 1e-6 ? V_TOP : Math.min(V_TOP, OMEGA / k, Math.sqrt(A_LAT / k));
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
  const aim = T.pts[(i + Math.round((60 + v * 0.36) / 12)) % N];
  const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
  const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - (S.pairTh ?? 0));
  const k = Math.max(-1, Math.min(1, err * 5));
  let base = v < target - 4 ? 0.87 : Math.max(0, Math.min(0.87, 0.87 * (target / Math.max(v, 1)) - 0.1));
  const brk = Math.max(0, Math.min(1, (v - target - 6) / 25));
  if (brk > 0) base = 0;
  return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)),
    Math.max(brk, k > 0.6 ? (k - 0.6) * 2 : 0), Math.max(brk, k < -0.6 ? (-k - 0.6) * 2 : 0)].map((x) => r4(Math.min(1, x)));
}

function run(inputsOrNull) {
  const sim = makeSim({ track: 'gp' }), S = sim.S, log = [];
  const vplan = plan(S.T);
  let top = 0, hits = 0;
  const minAt = {};
  for (let f = 0; f * SUB * DT < MAX_T; f++) {
    const u = inputsOrNull ? inputsOrNull[f] : autopilot(S, vplan);
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true };
    for (let k = 0; k < SUB; k++) {
      sim.step(inp, DT);
      const v = Math.hypot(S.pod.vx, S.pod.vy);
      top = Math.max(top, v);
      const seg = Math.floor(S.pod.hint / 100);
      minAt[seg] = Math.min(minAt[seg] ?? Infinity, v);
      while (S.events.length) {
        const e = S.events.shift();
        if (e.type === 'hit') hits++;
        if (e.type === 'crash') return { log, lap: null, crash: true, frames: f + 1, T: S.T, top, hits };
        if (e.type === 'lap') return { log, lap: e.t, frames: f + 1, x: S.pod.x, y: S.pod.y, T: S.T, top, hits, minAt };
      }
    }
  }
  return { log, lap: null, frames: log.length, T: S.T, top, hits, x: S.pod.x, y: S.pod.y };
}

const rec = run(null);
console.log(`autopilot: lap ${rec.lap === null ? 'NONE' + (rec.crash ? ' (crashed)' : '') : rec.lap.toFixed(2) + ' s'}, top ${(rec.top * MPH).toFixed(0)} mph, wall hits ${rec.hits}, avg ${rec.lap ? (rec.T.length / rec.lap * MPH).toFixed(0) : '-'} mph`);
if (rec.lap === null) { console.log(`stopped at (${rec.x?.toFixed(0)}, ${rec.y?.toFixed(0)})`); process.exit(1); }
const rep = run(rec.log);
const expected = { lap_time: rep.lap, frames: rep.frames, final_pod: [rep.x, rep.y], track_length: rep.T.length, track_samples: rep.T.N, top_mph: rep.top * MPH, hits: rep.hits };
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'gp_inputs.json'), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, 'gp_expected.json'), JSON.stringify(expected, null, 1));
console.log(`replayed ${rep.lap.toFixed(3)} s (${rec.log.length} input frames) -> ${outDir}`);
