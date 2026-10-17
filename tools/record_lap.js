// Record one autopilot lap through the JS reference sim, for the Godot parity gate.
// Usage: node tools/record_lap.js <path/to/sim-core.js> <out_dir>
// Writes lap_inputs.json (inputs at 60 Hz, each held for 8 substeps of 1/480 s)
// and lap_expected.json (the JS result of replaying exactly those rounded inputs).
'use strict';
const fs = require('fs');
const path = require('path');

const [simPath, outDir] = process.argv.slice(2);
if (!simPath || !outDir) { console.error('usage: record_lap.js <sim-core.js> <out_dir>'); process.exit(2); }
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim, xorshift32 } = window.PhaethonSim;

const DT = 1 / 480, SUB = 8, MAX_T = 200;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;

// Crude autopilot: aim ahead on the centreline, hold a target speed set by the bend ahead
// (~650 mph on straights, ~130 mph in hairpins), brake when over it, split the levers to steer.
function autopilot(S) {
  const T = S.T, v = Math.hypot(S.pod.vx, S.pod.vy);
  const ahead = Math.round((60 + v * 1.2) / 12), p = T.pts[(S.pod.hint + ahead) % T.N];
  const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
  const err = wrap(Math.atan2(p.y - my, p.x - mx) - (S.pairTh ?? 0));
  const far = T.pts[(S.pod.hint + ahead * 3) % T.N];
  const bend = Math.abs(wrap(Math.atan2(far.ty, far.tx) - Math.atan2(p.ty, p.tx)));
  const vt = Math.max(60, 290 - 300 * bend);
  const base = Math.max(0.03, Math.min(0.5, 0.05 + (vt - v) * 0.004));
  const k = Math.max(-0.8, Math.min(0.8, err * 4));
  const brk = Math.max(0, Math.min(1, (v - vt - 20) / 60));
  return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)), Math.max(brk, k > 0.5 ? 0.6 : 0), Math.max(brk, k < -0.5 ? 0.6 : 0)].map(r4);
}

function run(inputsOrNull) {
  const sim = makeSim(), S = sim.S, log = [];
  for (let f = 0; f * SUB * DT < MAX_T; f++) {
    const u = inputsOrNull ? inputsOrNull[f] : autopilot(S);
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true };
    for (let k = 0; k < SUB; k++) {
      sim.step(inp, DT);
      while (S.events.length) {
        const e = S.events.shift();
        if (e.type === 'lap') return { log, lap: e.t, frames: f + 1, x: S.pod.x, y: S.pod.y, T: S.T };
      }
    }
  }
  return { log, lap: null, frames: log.length, T: S.T };
}

const rec = run(null);
if (rec.lap === null) { console.error('autopilot never finished a lap'); process.exit(1); }
const rep = run(rec.log);                       // replay the rounded log: this is the reference
const rng = xorshift32(1337);
const expected = {
  lap_time: rep.lap, frames: rep.frames, final_pod: [rep.x, rep.y],
  track_length: rep.T.length, track_samples: rep.T.N,
  rng_first5: [rng(), rng(), rng(), rng(), rng()]
};
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'lap_inputs.json'), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, 'lap_expected.json'), JSON.stringify(expected, null, 1));
console.log(`recorded lap ${rec.lap.toFixed(3)} s, replayed ${rep.lap.toFixed(3)} s, ${rec.log.length} input frames`);
