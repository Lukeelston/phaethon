// The emergency run flown by an autopilot, and its parity reference: out from the start line to
// the lake town's medical pad (stops on it, holds 1.6 s), then home to the start town's mouth by
// one of the routes, ahead of the dawn:
//   open   the loop all the way home
//   shade  the loop to the split, then the shade line (under its canopy) into the town
//   late   the open route with a longer hold on the pad (the allowance + 6 s): the dawn must catch it
// The route is a list of [path, i] samples (main and branch); the speed plan is record_course.js's
// (each mode's turn-rate and grip limits, STARFIGHTER's speed in the towns, braking distance) over
// the route, with 0 at the pad and STARFIGHTER speed through the shade line's gate zone (the gate
// takes you only below 1,250 mph). Steering and the handling switch are record_course.js's.
// Then the rounded input log is replayed: that replay is what godot/tests/test_job_parity.gd must match.
// Inputs: [thrL, thrR, brkL, brkR, h] per 8 x 1/480 s frame; h 0 = no ask, 1 = speed, 2 = starfighter.
// Usage: node tools/record_job.js <sim-core.js> <out_dir> <open|shade|late>  -> job_<route>_inputs.json, job_<route>_expected.json
// (tools/tune_dawn.js loads it as a module.)
'use strict';
const fs = require('fs');
const path = require('path');

const DT = 1 / 480, SUB = 8, MAX_T = 420, G = 9.81, MPH = 2.236936;
const SF = { omega: 0.95, aLat: 38 * G, top: 1150 / MPH };
const SP = { aLat: 10 * G, top: 4300 / MPH };
const SWITCH_V = 1200 / MPH;
// The human allowance (Luke's first run, 2026-10-19: a lap 8.5 s off the autopilot's, which corners at
// 38 g, before any stop on the pad): the dawn is tuned for a pilot this much slower than the
// autopilot; the late run (which must be caught) is that pilot 6 s slower still.
const ALLOWANCE = 15;
const HOLD = 1.6, LATE_HOLD = ALLOWANCE + 6;
const ASK = [undefined, 'speed', 'starfighter'];
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;

function load(simPath) {
  global.window = {};
  eval(fs.readFileSync(simPath, 'utf8'));
  return window.PhaethonSim;
}

// The route's samples: { x, y, tx, ty, len, mode, path, i, cap } from the start line (main 0).
function buildRoute(T, kind) {
  const B = T.branches[0], out = [];
  const main = (a, b) => { for (let i = a; i <= b; i++) { const p = T.pts[i]; out.push({ x: p.x, y: p.y, tx: p.tx, ty: p.ty, len: p.len, mode: p.mode, path: 0, i }); } };
  main(0, T.pad);
  const padAt = out.length - 1;
  if (kind === 'shade') {
    main(T.pad + 1, B.from - 1);
    for (let k = out.length - 1 - (B.jz + 150); k < out.length; k++) out[k].cap = SWITCH_V;   // into the gate zone below 1,250 mph (with room: the speed lags the plan)
    B.pts.forEach((p, j) => out.push({ x: p.x, y: p.y, tx: p.tx, ty: p.ty, len: p.len, mode: 'sf', path: 1, i: j }));
    main(B.join + 1, B.join + 300);
  } else main(T.pad + 1, T.mouth + 300);
  return { pts: out, padAt };
}

// Target speed per route sample: curvature limits per mode, 0 at the pad, braking distance.
function plan(route) {
  const R = route.pts, N = R.length, kap = new Array(N).fill(0), v = new Array(N);
  for (let i = 0; i + 1 < N; i++) kap[i] = Math.abs(wrap(Math.atan2(R[i + 1].ty, R[i + 1].tx) - Math.atan2(R[i].ty, R[i].tx))) / R[i].len;
  for (let i = 0; i < N; i++) {
    let k = 0;
    for (let j = -4; j <= 4; j++) k = Math.max(k, kap[Math.min(N - 1, Math.max(0, i + j))]);
    if (R[i].mode === 'sf') v[i] = Math.min(SWITCH_V, k < 1e-6 ? SF.top : Math.min(SF.top, SF.omega / k, Math.sqrt(SF.aLat / k)));
    else v[i] = k < 1e-7 ? SP.top : Math.min(SP.top, Math.sqrt(SP.aLat / k));
    if (R[i].cap !== undefined) v[i] = Math.min(v[i], R[i].cap);
  }
  v[route.padAt] = 0;
  // braking: record_course.js's, gentler into the pad (a stop in its +-40 m box)
  const decel = (s, i) => (i <= route.padAt && route.padAt - i < 400 ? Math.min(3, 5 + 9 * Math.min(s / 447, 1)) : 5 + 9 * Math.min(s / 447, 1)) * G;
  for (let pass = 0; pass < 3; pass++) {
    for (let i = N - 2; i >= 0; i--) {
      const nx = v[i + 1];
      v[i] = Math.min(v[i], Math.sqrt(nx * nx + 2 * decel(nx, i) * R[i].len));
    }
  }
  return v;
}

function makePilot(S, route, vplan, hold) {
  const R = route.pts, N = R.length;
  const st = { i: 0, held: 0, phase: 'run' };
  return function pilot() {
    const v = Math.hypot(S.pod.vx, S.pod.vy);
    let bd = Infinity, bi = st.i;
    for (let k = Math.max(0, st.i - 10); k < Math.min(N, st.i + 60); k++) {
      const d = (R[k].x - S.pod.x) ** 2 + (R[k].y - S.pod.y) ** 2;
      if (d < bd) { bd = d; bi = k; }
    }
    st.i = bi;
    const i = bi;
    // the pad: brake to a stop on it, hold, go
    if (st.phase === 'run' && i >= route.padAt - 3 && i <= route.padAt + 3 && v < 25) st.phase = 'stop';
    if (st.phase === 'stop') {
      if (v < 0.4) st.held += SUB * DT;
      if (st.held >= hold) st.phase = 'home';
      else return [0, 0, 1, 1, 2];
    }
    // off the pad, plan from past it (the plan's 0 there is the stop, not the start)
    const iT = st.phase === 'home' ? Math.max(i, route.padAt + 1) : i;
    const lead = Math.ceil((v * 0.35) / 12);
    const target = vplan[Math.min(N - 1, iT + lead)];
    const aim = R[Math.min(N - 1, iT + Math.round((60 + v * (S.P.handling === 'speed' ? 0.5 : 0.36)) / 12))];
    const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
    const course = S.P.handling === 'speed' ? Math.atan2(S.pod.vy, S.pod.vx) : (S.pairTh ?? 0);
    const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - course);
    const k = Math.max(-1, Math.min(1, err * (S.P.handling === 'speed' ? 3 : 5)));
    const top = 0.87;
    let base = v < target - 4 ? top : Math.max(0, Math.min(top, top * (target / Math.max(v, 1)) - 0.1));
    let brk = Math.max(0, Math.min(1, (v - target - 6) / 25));
    // (record_course.js's SPEEDCRAFT curve hold, but not into the gate zone: there it's a plain stop to the cap)
    if (S.P.handling === 'speed' && v - target < 50 && R[Math.min(N - 1, iT + lead)].cap === undefined) {
      const keep = Math.min(top, 0.25 + 0.75 * Math.abs(k));
      if (base < keep) { brk = Math.max(brk, Math.min(1, (v - target + 4) / 40)); base = keep; }
      brk = Math.min(brk, 1.0 - 0.8 * Math.min(1, Math.abs(k) / 0.4));
    } else if (brk > 0) base = 0;
    const ahead = vplan[Math.min(N - 1, iT + Math.ceil(v * 2 / 12))];
    const h = R[i].mode === 'sf' || ahead <= SWITCH_V * 1.05 ? 2 : 1;
    const kb = 0.6, gb = 2;
    return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)),
      Math.max(brk, k > kb ? (k - kb) * gb : 0), Math.max(brk, k < -kb ? (-k - kb) * gb : 0)].map((x) => r4(Math.min(1, x))).concat([h]);
  };
}

// One run. kind: open | shade | late; over: extra makeSim overrides (tune_dawn: the dawn off);
// inputs: replay these instead of flying. Returns the log, the job events and the track of the pod.
function run(PS, kind, over, inputs, keepTrack) {
  const sim = PS.makeSim(Object.assign({ track: 'eridanus', job: 'emergency' }, over || {})), S = sim.S;
  const route = buildRoute(sim.T, kind === 'shade' ? 'shade' : 'open'), vplan = plan(route);
  const pilot = makePilot(S, route, vplan, HOLD + (kind === 'late' ? LATE_HOLD : 0));
  const log = [], events = [], track = [];
  let top = 0, hits = 0, end = null;
  for (let f = 0; f * SUB * DT < MAX_T && !end; f++) {
    const u = inputs ? inputs[f] : pilot();
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] };
    for (let k = 0; k < SUB && !end; k++) {
      sim.step(inp, DT);
      top = Math.max(top, Math.hypot(S.pod.vx, S.pod.vy));
      if (keepTrack && S.job.t0 !== null) {   // every step: [t, x, y, sheltered, stage, under the canopy]
        const Pd = S.pod, Bp = Pd.path > 0 ? sim.T.branches[Pd.path - 1] : null;
        const covered = Bp !== null && Pd.hint >= Bp.covered[0];
        const shelter = covered || (Pd.path === 0 && (sim.T.pts[Pd.hint].mode === 'sf' || sim.T.cover[Pd.hint] === 1));   // the sim's rule: towns, ramps, the canopy
        track.push([S.job.t, Pd.x, Pd.y, shelter ? 1 : 0, S.job.stage, covered ? 1 : 0]);
      }
      while (S.events.length) {
        const e = S.events.shift();
        if (e.type === 'hit') hits++;
        if (e.type === 'job' || e.type === 'dawn') events.push([f, e.type, e.stage || '']);
        if (e.type === 'job' && (e.stage === 'done' || e.stage === 'failed')) end = e;
      }
    }
  }
  return { sim, log, events, end, top, hits, track, frames: log.length, job: S.job };
}

module.exports = { load, buildRoute, plan, run, HOLD, LATE_HOLD, ALLOWANCE };

if (require.main === module) {
  const [simPath, outDir, kind] = process.argv.slice(2);
  if (!['open', 'shade', 'late'].includes(kind)) { console.log('usage: node tools/record_job.js <sim-core.js> <out_dir> <open|shade|late>'); process.exit(2); }
  const PS = load(simPath);
  const rec = run(PS, kind);
  const J = rec.job, P = rec.sim.P;
  console.log(`job ${kind}: ${J.stage}${J.reason ? ' (' + J.reason + ')' : ''} at ${J.t.toFixed(2)} s, route ${J.route}, margin ${J.margin.toFixed(2)} s, ` +
    `top ${(rec.top * MPH).toFixed(0)} mph, wall hits ${rec.hits}, dawn dir ${(P.dawnDir * 180 / Math.PI).toFixed(1)} deg t0 ${P.dawnT0} s; events ${JSON.stringify(rec.events)}`);
  const rep = run(PS, kind, null, rec.log);
  const same = JSON.stringify(rep.events) === JSON.stringify(rec.events);
  const expected = { frames: rep.frames, events: rep.events, final_pod: [rep.sim.S.pod.x, rep.sim.S.pod.y], margin: rep.job.margin, route: rep.job.route,
    stage: rep.job.stage, reason: rep.job.reason, t: rep.job.t, hits: rep.hits, dawn: [P.dawnDir, P.dawnT0] };
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, `job_${kind}_inputs.json`), JSON.stringify(rec.log));
  fs.writeFileSync(path.join(outDir, `job_${kind}_expected.json`), JSON.stringify(expected, null, 1));
  console.log(`replayed: ${rep.job.stage} at ${rep.job.t.toFixed(3)} s (${rec.log.length} frames, events ${same ? 'identical' : 'DIFFER'}) -> ${outDir}`);
  if (!same) process.exit(1);
}
