// Reference sprint for the Godot sprint gate: a scripted pilot sprints, brakes 5.1 km out,
// creeps into the box and stops. Inputs logged at 60 Hz (held 8 substeps).
// Settled 4,448 mph -> stopped measures 4,884 m; the extra 216 m covers a controller frame
// and leaves a short, deliberate creep into the box, rather than kilometres at 40 m/s.
// Usage: node tools/record_sprint.js <sim-core.js> <out_dir> [brakeDistanceM]
'use strict';
const fs = require('fs');
const path = require('path');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const DT = 1 / 480, SUB = 8, BRAKE_AT = Number(process.argv[4] || 5100);
if (!Number.isFinite(BRAKE_AT) || BRAKE_AT <= 0) throw new Error('brakeDistanceM must be positive');
const r4 = (v) => Math.round(v * 1e4) / 1e4;

function pilot(S, BOX, state) {
  const togo = BOX - S.pod.x, v = Math.hypot(S.pod.vx, S.pod.vy);
  if (togo <= BRAKE_AT) state.braked = true;
  if (!state.braked) return [0.87, 0.87, 0, 0];
  const vt = Math.max(0, Math.min(40, togo * 0.5));
  const lever = v < vt - 1 ? 0.01 : 0, brk = v > vt + 0.5 || togo < 0 ? 1 : 0;
  return [lever, lever, brk, brk];
}

function run(log) {
  const sim = window.PhaethonSim.makeSim({ track: 'range' }), S = sim.S, state = { braked: false }, out = [];
  for (let f = 0; f < 200 * 60 && S.result === null; f++) {
    const u = log ? log[f] : pilot(S, sim.box.x, state).map(r4);
    if (!u) break;
    out.push(u);
    for (let k = 0; k < SUB && S.result === null; k++) {
      sim.step({ thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true }, DT);
      S.events.length = 0;
    }
  }
  return { log: out, result: S.result, x: S.pod.x - sim.box.x, y: S.pod.y,
    speed: Math.hypot(S.pod.vx, S.pod.vy), half: sim.box.half };
}

function requireFinish(label, run) {
  if (!run.result || run.result.type !== 'finish' || !Number.isFinite(run.result.t) ||
      run.result.t <= 0 || run.result.t >= 200 || Math.abs(run.x) > run.half || run.speed >= 0.5) {
    throw new Error(`${label} did not finish stopped inside the box: result=${JSON.stringify(run.result)}, ` +
      `offset=${run.x.toFixed(2)} m, speed=${run.speed.toFixed(3)} m/s; refusing to write a failed fixture`);
  }
}

const rec = run(null);
requireFinish('Scripted pilot', rec);
const rep = run(rec.log);   // the rounded log is the reference
requireFinish('Recorded-input replay', rep);
if (Math.abs(rep.result.t - rec.result.t) > DT || Math.abs(rep.x - rec.x) > 0.01)
  throw new Error('Recorded sprint did not reproduce its finish');
fs.mkdirSync(process.argv[3], { recursive: true });
fs.writeFileSync(path.join(process.argv[3], 'sprint_inputs.json'), JSON.stringify(rep.log));
fs.writeFileSync(path.join(process.argv[3], 'sprint_expected.json'), JSON.stringify({ result: rep.result, dx: rep.x, dy: rep.y, frames: rep.log.length }, null, 1));
console.log(`sprint ref: ${rep.result && rep.result.type} ${rep.result && rep.result.t ? rep.result.t.toFixed(3) + ' s' : ''}, ${rep.x.toFixed(2)} m from box centre, ${rep.log.length} frames`);
