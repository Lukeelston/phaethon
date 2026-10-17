// Reference run for the range parity gate: 50 s down the jump lane at a fixed lever.
// Usage: node tools/record_range.js <sim-core.js> <out_dir>  -> range_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const sim = window.PhaethonSim.makeSim({ track: 'range', startY: 400 }), S = sim.S, DT = 1 / 480;
const apexes = [];
let air = false, apex = 0;
for (let i = 0; i < 50 / DT; i++) {
  sim.step({ thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
  S.events.length = 0;
  const p = S.pod;
  if (!air && p.grip < 0.5) { air = true; apex = p.z; }
  if (air) apex = Math.max(apex, p.z);
  if (air && p.grip >= 0.99) { air = false; apexes.push(apex); }
}
const out = { seconds: 50, final_pod: [S.pod.x, S.pod.y, S.pod.z], apexes, ramps: S.T.ramps.length };
fs.mkdirSync(process.argv[3], { recursive: true });
fs.writeFileSync(path.join(process.argv[3], 'range_expected.json'), JSON.stringify(out, null, 1));
console.log(`range ref: x=${S.pod.x.toFixed(1)} m, apexes ${apexes.map((a) => a.toFixed(2)).join(', ')}, ${out.ramps} ramps`);
