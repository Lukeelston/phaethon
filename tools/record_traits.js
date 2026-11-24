// Reference runs for the craft's attributes and powers (sim/pilot_craft.gd TRAITS, sim-core.js PILOT_TRAITS; Luke,
// 2026-11-24: "build the attributes and powers into the game"): one short run a craft, its power armed, on the
// range, through what sets it off. godot/tests/test_traits_parity.gd flies each again in the GD sim (the same
// schedule below, mirrored there) and holds the two to the same place and the same power events, step for step.
//   phaethon   Slipstream: drafting (inp.draft) for 7 s fills the gauge at 6; fired at 7.5 s: 4 s of thrust x1.15
//   talon      Glide (the Talon's row on the Phaethon's chassis until the Talon is merged: traitsOf): the jump
//              lane's 15 m kicker at 3,000 mph, steered in the air by a lever split from 3 to 5 s
//   shrike     Kickdown: idle to full at 1 s (fires), again at 6 s (recharging: nothing), again at 16 s (fires)
//   orrery     Gyro Lock: a hard split-lever turn at 1,000 mph from 1 s, fired at 2 s
//   kiln       Ram Plate: fired at 0.5 s, then a vehicle dead ahead, slower, is driven through
//   vesper     Ground Effect: 2,500 mph straight (engages), a hard split at 3 s (ends), straight again (engages)
//   basilisk   its turret out (inp.turretOut) from 1 to 3 s: the drag
// Usage: node tools/record_traits.js <sim-core.js> <out_dir>  -> traits_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const DT = 1 / 480;

// [craft, overrides, start speed m/s, seconds, obstacles, input(i)]: mirrored in test_traits_parity.gd RUNS
const RUNS = [
  ['phaethon', { vehicle: 'phaethon', track: 'range', startY: -3000 }, 0, 14, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i < 7 * 480) u.draft = true;
    if (i === 3600) u.powerFire = true;
    return u;
  }],
  ['talon', { vehicle: 'phaethon', traitsOf: 'talon', track: 'range', startX: 18000, startY: 400 }, 1341.12, 14, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i >= 3 * 480 && i < 5 * 480) u.thrL = 0.6;
    return u;
  }],
  ['shrike', { vehicle: 'shrike', track: 'range', startY: -3000 }, 0, 20, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i < 480 || (i >= 6 * 480 && i < 6 * 480 + 96) || (i >= 16 * 480 && i < 16 * 480 + 96)) { u.thrL = 0; u.thrR = 0; }
    return u;
  }],
  ['orrery', { vehicle: 'orrery', track: 'range', startY: -3000 }, 447.04, 10, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i >= 480) u.thrL = 0.4;
    if (i === 960) u.powerFire = true;
    return u;
  }],
  ['kiln', { vehicle: 'kiln', track: 'range', startY: -3000 }, 447.04, 6, [[300, 0, 200, 5.2]], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i === 240) u.powerFire = true;
    return u;
  }],
  ['vesper', { vehicle: 'vesper', track: 'range', startY: -3000 }, 1117.6, 6, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i >= 3 * 480 && i < 3 * 480 + 240) u.thrL = 0.6;
    return u;
  }],
  ['basilisk', { vehicle: 'basilisk', track: 'range', startY: -3000 }, 447.04, 5, [], (i) => {
    const u = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, power: true };
    if (i >= 480 && i < 3 * 480) u.turretOut = true;
    return u;
  }]
];

const out = { runs: {} };
for (const [craft, opts, v0, seconds, obstacles, input] of RUNS) {
  const sim = window.PhaethonSim.makeSim(opts), S = sim.S;
  for (const b of S.bodies) { b.vx = v0; b.vy = 0; }
  // obstacles: [ahead of the pod m, across m, speed m/s, radius m], moving +x
  S.obstacles = obstacles.map(([ahead, across, v, r], k) => ({ id: k + 1, x: S.pod.x + ahead, y: S.pod.y + across, vx: v, vy: 0, r }));
  const marks = [], events = [];
  for (let i = 0; i < seconds * 480; i++) {
    sim.step(input(i), DT);
    for (const e of S.events) {
      if (e.type === 'power') events.push([e.state, i]);
      else if (e.type === 'bump' || e.type === 'smash') events.push([e.type + (e.ram ? ' ram' : ''), i]);
    }
    S.events.length = 0;
    if ((i + 1) % 240 === 0) marks.push([S.pod.x, S.pod.y, S.pod.z, S.pod.th, Math.hypot(S.pod.vx, S.pod.vy)]);
  }
  out.runs[craft] = { power: S.power, marks, events, end: [S.powerState, S.powerGauge] };
  console.log(`${craft.padEnd(9)} ${S.power.padEnd(10)} ${events.map((e) => e[0] + '@' + (e[1] * DT).toFixed(2)).join(' ')}  | ${(marks[marks.length - 1][4] * 2.236936).toFixed(0)} mph at the end`);
}
fs.mkdirSync(process.argv[3], { recursive: true });
fs.writeFileSync(path.join(process.argv[3], 'traits_expected.json'), JSON.stringify(out, null, 1));
