// Live handling switch parity reference: a scripted run on the range that flips between
// SPEEDCRAFT and STARFIGHTER (tools/mode_switch_test.js measures the same moves). Flat out in
// SPEEDCRAFT, full brakes asking for STARFIGHTER from 3,000 mph (it waits for 1,250), flat out in
// STARFIGHTER, back to SPEEDCRAFT, then a STARFIGHTER ask while coasting. The input log and a
// trace (pod state and the blend every second) are what godot/tests/test_mode_parity.gd matches.
// Inputs: [thrL, thrR, brkL, brkR, h] per 1/480 s step; h 0 = no ask, 1 = speed, 2 = starfighter.
// Usage: node tools/record_modes.js <sim-core.js> <out_dir>  -> modes_inputs.json, modes_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const [simPath, outDir] = process.argv.slice(2);
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, MPH = 2.236936;
const ASK = [undefined, 'speed', 'starfighter'];

function run(script) {
  const sim = makeSim({ track: 'range', handling: 'speed' });
  const S = sim.S, log = [], trace = [], events = [];
  let phase = 0, pt = 0;
  for (let i = 0; i < 480 * 120; i++) {
    const v = Math.hypot(S.pod.vx, S.pod.vy) * MPH;
    let u;
    if (script) {
      u = script[i];
      if (!u) break;
    } else {
      // the scripted pilot
      if (phase === 0 && v >= 4000) { phase = 1; pt = 0; }
      if (phase === 1 && S.hblend === 1) { phase = 2; pt = 0; }
      if (phase === 2 && pt > 20) { phase = 3; pt = 0; }
      if (phase === 3 && pt > 8) { phase = 4; pt = 0; }
      if (phase === 4 && S.hblend > 0 && pt > 1.5) { phase = 5; pt = 0; }
      if (phase === 5 && pt > 3) break;
      u = phase === 0 ? [0.87, 0.87, 0, 0, 0]
        : phase === 1 ? [0, 0, 1, 1, v < 3000 ? 2 : 0]
        : phase === 2 ? [0.87, 0.87, 0, 0, 0]
        : phase === 3 ? [0.87, 0.82, 0, 0, 1]        // a slight split: the pair yaws through the blend
        : phase === 4 ? [0, 0, 0.6, 0.6, 2]
        : [0.6, 0.6, 0, 0, 0];
      pt += DT;
    }
    log.push(u);
    sim.step({ thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] }, DT);
    while (S.events.length) {
      const e = S.events.shift();
      if (e.type === 'handling') events.push([i, e.mode]);
    }
    if (i % 480 === 479) trace.push([i, S.pod.x, S.pod.y, S.pod.vx, S.pod.vy, S.pod.th, S.hblend, S.P.thrustMax]);
  }
  return { log, trace, events, S };
}

const rec = run(null);
const rep = run(rec.log);
const same = JSON.stringify(rec.trace) === JSON.stringify(rep.trace);
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'modes_inputs.json'), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, 'modes_expected.json'), JSON.stringify({ trace: rep.trace, events: rep.events }, null, 0));
console.log(`modes ref: ${rec.log.length} steps (${(rec.log.length / 480).toFixed(1)} s), switches ${JSON.stringify(rep.events)}, ` +
  `end x=${rep.S.pod.x.toFixed(1)} m at ${(Math.hypot(rep.S.pod.vx, rep.S.pod.vy) * MPH).toFixed(0)} mph, replay ${same ? 'identical' : 'DIFFERS'}`);
