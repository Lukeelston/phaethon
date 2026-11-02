// Reference sprint for the Godot sprint gate: a scripted pilot sprints, brakes 11.3 km out,
// creeps into the box and stops. Inputs logged at 60 Hz (held 8 substeps).
// Usage: node tools/record_sprint.js <sim-core.js> <out_dir>  -> sprint_inputs.json, sprint_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const DT = 1 / 480, SUB = 8, BRAKE_AT = 11300;
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
  return { log: out, result: S.result, x: S.pod.x - sim.box.x, y: S.pod.y };
}

const rec = run(null);
const rep = run(rec.log);   // the rounded log is the reference
fs.mkdirSync(process.argv[3], { recursive: true });
fs.writeFileSync(path.join(process.argv[3], 'sprint_inputs.json'), JSON.stringify(rep.log));
fs.writeFileSync(path.join(process.argv[3], 'sprint_expected.json'), JSON.stringify({ result: rep.result, dx: rep.x, dy: rep.y, frames: rep.log.length }, null, 1));
console.log(`sprint ref: ${rep.result && rep.result.type} ${rep.result && rep.result.t ? rep.result.t.toFixed(3) + ' s' : ''}, ${rep.x.toFixed(2)} m from box centre, ${rep.log.length} frames`);
