// S5 circuit proof: real simulation, armed ramjet and recorded throttle/brake inputs.
'use strict';
const fs = require('fs');
const path = require('path');
const proof = require('./replay_proof.js');
const [simPath, outDir, courseArg] = process.argv.slice(2);
const COURSE = courseArg || 'carving';
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, SUB = 8, MAX_T = 600, G = 9.81, MPH = 2.236936;
const SP = { aLat: 22 * G, top: 6000 / MPH };
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
    v[i] = k < 1e-7 ? SP.top : Math.min(SP.top, Math.sqrt(SP.aLat / k));
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
  const aim = T.pts[(i + Math.round((60 + v * 0.5) / 12)) % N];
  const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
  // Aim the velocity path; the nose points into the curve while the craft slides.
  const course = Math.atan2(S.pod.vy, S.pod.vx);
  const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - course);
  const k = Math.max(-1, Math.min(1, err * 3));
  const top = 1.0;
  let base = v < target - 4 ? top : Math.max(0, Math.min(top, top * (target / Math.max(v, 1)) - 0.1));
  let brk = Math.max(0, Math.min(1, (v - target - 6) / 25));
  if (v - target < 50) {
    // Meter common braking against the speed plan, leaving differential brake
    // authority for steering. Both throttles remain in the ramjet gate.
    const keep = Math.min(top, 0.25 + 0.75 * Math.abs(k));
    if (base < keep) {
      brk = Math.max(brk, Math.min(1, (v - target + 4) / 40));
    }
    brk = Math.min(brk, 1.0 - 0.8 * Math.min(1, Math.abs(k) / 0.4));
  }
  return [1, 1, Math.min(1,brk+Math.max(0,k)*0.8), Math.min(1,brk+Math.max(0,-k)*0.8)].map(r4).concat([1]);
}

function run(inputsOrNull) {
  const sim = makeSim({ track: COURSE }), S = sim.S, log = [], switches = [], hitsAt = [];
  const vplan = plan(S.T);
  S.armed = true;
  let top = 0, hits = 0, ramjetSeconds=0, ramjetCurveSeconds=0;
  for (let f = 0; f * SUB * DT < MAX_T; f++) {
    const u = inputsOrNull ? inputsOrNull[f] : autopilot(S, vplan);
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] };
    for (let k = 0; k < SUB; k++) {
      sim.step(inp, DT);
      if(S.mode==='ramjet'){ramjetSeconds+=DT;const a=S.T.pts[S.pod.hint],b=S.T.pts[(S.pod.hint+1)%S.T.N];if(Math.abs(wrap(Math.atan2(b.ty,b.tx)-Math.atan2(a.ty,a.tx)))>0.0001)ramjetCurveSeconds+=DT;}
      const v = Math.hypot(S.pod.vx, S.pod.vy);
      top = Math.max(top, v);
      while (S.events.length) {
        const e = S.events.shift();
        if (e.type === 'hit') { hits++; hitsAt.push([S.pod.hint, S.T.pts[S.pod.hint].mode, Math.round(v * MPH), S.P.handling]); }
        if (e.type === 'handling') switches.push([f, e.mode, Math.round(v * MPH)]);
        if (e.type === 'crash') return { log, lap: null, crash: true, frames: f + 1, T: S.T, top, hits, switches, x: S.pod.x, y: S.pod.y, i: S.pod.hint };
        if (e.type === 'lap') return { log, ramjetSeconds, ramjetCurveSeconds, lap: e.t, frames: f + 1, x: S.pod.x, y: S.pod.y, T: S.T, top, hits, switches, hitsAt };
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
proof.course(rec);
proof.course(rep);
console.log(`RAMJET ${rep.ramjetSeconds.toFixed(1)}s active; ${rep.ramjetCurveSeconds.toFixed(1)}s in curves`);
if(rep.ramjetCurveSeconds<10)throw new Error('Less than10 seconds of actual ramjet carving');
if (JSON.stringify(rec.switches) !== JSON.stringify(rep.switches) || Math.abs(rec.lap - rep.lap) > 1e-9) {
  throw new Error('Recording refused: lap replay differs from its source run.');
}
const expected = { lap_time: rep.lap, frames: rep.frames, final_pod: [rep.x, rep.y], track_length: rep.T.length, track_samples: rep.T.N,
  ramjet_seconds: rep.ramjetSeconds, ramjet_curve_seconds: rep.ramjetCurveSeconds, top_mph: rep.top * MPH, hits: rep.hits, switches: rep.switches };
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, `${COURSE}_inputs.json`), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, `${COURSE}_expected.json`), JSON.stringify(expected, null, 1));
console.log(`replayed ${rep.lap.toFixed(3)} s (${rec.log.length} input frames) -> ${outDir}`);
