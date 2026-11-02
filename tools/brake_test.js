// Air-brake feel across speeds. Usage: node tools/brake_test.js <sim-core.js> ['{"brakeCd":4}']
// For each speed: (a) both brakes full, throttles 0, for 1 s -> average decel in g, plus
// the closest pod-to-engine approach (overrun) and the worst binder stretch;
// (b) left brake full, both throttles 0.87, for 1 s -> yaw change (pivot).
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const over = JSON.parse(process.argv[3] || '{}');
const DT = 1 / 480, G = 9.81, D = 180 / Math.PI;

function launch(kmh) {
  const sim = window.PhaethonSim.makeSim(over), S = sim.S;
  for (const p of S.T.pts) p.w = 1e6;                       // no walls
  const v = kmh / 3.6;
  for (const b of S.bodies) { b.vx = v * Math.cos(b.th); b.vy = v * Math.sin(b.th); }
  for (let i = 0; i < 240; i++) sim.step({ thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0 }, DT);  // settle 0.5 s
  return { sim, S };
}
const speed = (b) => Math.hypot(b.vx, b.vy);

console.log('speed   | both brakes: decel   min pod-engine gap  max binder | one brake: yaw in 1 s');
for (const kmh of [100, 200, 350, 500, 700]) {
  let { sim, S } = launch(kmh);
  const v0 = speed(S.pod);
  let gap = Infinity, stretch = 0, hits = 0;
  for (let i = 0; i < 480; i++) {
    sim.step({ thrL: 0, thrR: 0, brkL: 1, brkR: 1 }, DT);
    for (const e of [S.eL, S.eR]) gap = Math.min(gap, Math.hypot(e.x - S.pod.x, e.y - S.pod.y) - 4 - 2);
    stretch = Math.max(stretch, Math.abs(S.binderStretch || 0));
    hits += S.events.filter((e) => e.type === 'hit' || e.type === 'binder').length; S.events.length = 0;
  }
  const decel = (v0 - speed(S.pod)) / 1.0 / G;
  ({ sim, S } = launch(kmh));
  const th0 = S.pairTh;
  for (let i = 0; i < 480; i++) sim.step({ thrL: 0.87, thrR: 0.87, brkL: 1, brkR: 0 }, DT);
  const yaw = Math.atan2(Math.sin(S.pairTh - th0), Math.cos(S.pairTh - th0)) * D;
  console.log(`${String(kmh).padStart(4)} km/h | ${decel.toFixed(2).padStart(5)} g   ${gap.toFixed(1).padStart(6)} m           ${stretch.toFixed(3)} m ${hits ? 'HITS ' + hits : ''}| ${yaw.toFixed(1).padStart(6)} deg`);
}
