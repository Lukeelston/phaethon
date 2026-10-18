// Sprint-mode check: a scripted pilot sprints, brakes at a chosen distance before the box,
// creeps in and stops; then a no-brake run must DNF on overrun and reset to the start line.
// Usage: node tools/sprint_test.js <sim-core.js> [brakeAtMetresBeforeBox]
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const brakeAt = +(process.argv[3] || 11300);
const DT = 1 / 480;
const sim = window.PhaethonSim.makeSim({ track: 'range' }), S = sim.S, BOX = sim.box.x;
const ev = [];
const drain = () => { while (S.events.length) ev.push(S.events.shift()); };
const speed = () => Math.hypot(S.pod.vx, S.pod.vy);

// run 1: sprint, brake, creep, stop in the box
let braked = false;
for (let i = 0; i < 400 / DT && S.result === null; i++) {
  const togo = BOX - S.pod.x, v = speed();
  if (togo <= brakeAt) braked = true;
  let u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, reignite: true };
  if (braked) {
    // creep controller: target speed proportional to distance left, brake when above it
    const vt = Math.max(0, Math.min(40, togo * 0.5));
    const lever = v < vt - 1 ? 0.01 : 0;
    const brk = v > vt + 0.5 || togo < 0 ? 1 : 0;
    u = { thrL: lever, thrR: lever, brkL: brk, brkR: brk, reignite: true };
  }
  sim.step(u, DT); drain();
}
const r = S.result;
console.log(`run 1: ${r ? r.type : 'no result'}${r && r.type === 'finish' ? ` in ${r.t.toFixed(2)} s, ${r.err.toFixed(2)} m off centre` : ''}; pod x - box = ${(S.pod.x - BOX).toFixed(1)} m, speed ${speed().toFixed(2)} m/s`);

// a finished run must not restart on its own
for (let i = 0; i < 2 / DT; i++) { sim.step({ thrL: 0.2, thrR: 0.2, brkL: 0, brkR: 0, reignite: true }, DT); drain(); }
console.log(`after finish, moving again: runActive=${S.runActive} (want false), result kept=${S.result && S.result.type}`);

// restart, run 2: never brake -> overrun DNF -> back at the start line
sim.restart();
console.log(`restart: pod x=${S.pod.x.toFixed(1)}, speed ${speed().toFixed(1)}, result=${S.result}`);
let sawOverrun = false;
for (let i = 0; i < 200 / DT && !sawOverrun; i++) {
  sim.step({ thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, reignite: true }, DT);
  while (S.events.length) { const e = S.events.shift(); if (e.type === 'overrun') sawOverrun = true; }
}
for (let i = 0; i < 2 / DT; i++) { sim.step({ thrL: 0, thrR: 0, brkL: 0, brkR: 0, reignite: true }, DT); drain(); }
console.log(`run 2: overrun=${sawOverrun}, after the fade pod x=${S.pod.x.toFixed(1)} (want ~0), result=${S.result}, runActive=${S.runActive}`);
