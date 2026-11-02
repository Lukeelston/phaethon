// Reference run for the starfighter parity gate: 30 s of slalom on open desert.
// Inputs are a pure function of the step index (whole seconds), mirrored in
// godot/tests/test_handling_parity.gd: launch 5 s, then 1 s splits alternating sides for
// 20 s (one brake at 12 s, both at 20 s), then 5 s straight.
// Usage: node tools/record_handling.js <sim-core.js> <out_dir>  -> handling_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const DT = 1 / 480, SECONDS = 30;
function input(i) {
  const s = Math.floor(i / 480);
  const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true };
  if (s >= 5 && s < 25) {
    if (s % 2 === 0) u.thrL = 0.25; else u.thrR = 0.25;
    if (s === 12) u.brkL = 1;
    if (s === 20) { u.brkL = 1; u.brkR = 1; }
  }
  return u;
}
const sim = window.PhaethonSim.makeSim({ track: 'range', startY: -3000, handling: 'starfighter' }), S = sim.S;
const marks = [];
for (let i = 0; i < SECONDS * 480; i++) {
  sim.step(input(i), DT);
  S.events.length = 0;
  if ((i + 1) % 1200 === 0) marks.push([S.pod.x, S.pod.y, S.pod.th, Math.hypot(S.pod.vx, S.pod.vy)]);
}
const out = { seconds: SECONDS, handling: 'starfighter', marks };
fs.mkdirSync(process.argv[3], { recursive: true });
fs.writeFileSync(path.join(process.argv[3], 'handling_expected.json'), JSON.stringify(out, null, 1));
const top = Math.max(...marks.map((m) => m[3])) * 2.236936;
console.log(`handling ref: ${marks.length} marks, end x=${S.pod.x.toFixed(1)} y=${S.pod.y.toFixed(1)} m, fastest mark ${top.toFixed(0)} mph`);
