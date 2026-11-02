// One-sided ramp hit: fly the jump lane's edge so only the right engine catches each kicker,
// and measure how far the engines (and the pod) separate vertically.
// Usage: node tools/split_test.js <sim-core.js> ['{"overrides":1}']
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const over = Object.assign({ track: 'range', startY: 420 }, JSON.parse(process.argv[3] || '{}'));
const sim = window.PhaethonSim.makeSim(over), S = sim.S, DT = 1 / 480;
let maxSplit = 0, maxPodLag = 0, maxZ = 0, snaps = 0;
for (let i = 0; i < 60 / DT; i++) {
  sim.step({ thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, reignite: true }, DT);
  for (const e of S.events) if (e.type === 'binder') snaps++;
  S.events.length = 0;
  maxSplit = Math.max(maxSplit, Math.abs(S.eL.z - S.eR.z));
  maxPodLag = Math.max(maxPodLag, Math.abs((S.eL.z + S.eR.z) / 2 - S.pod.z));
  maxZ = Math.max(maxZ, S.eL.z, S.eR.z);
}
console.log(`engines on y=${(S.eL.y).toFixed(1)}/${(S.eR.y).toFixed(1)} (ramp edge 420): max engine height split ${maxSplit.toFixed(1)} m (${(maxSplit * 3.281).toFixed(0)} ft), ` +
  `max pod vs engines ${maxPodLag.toFixed(1)} m, highest engine ${maxZ.toFixed(1)} m, binder snaps ${snaps}`);
