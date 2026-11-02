// Range shakedown: fly the jump lane at full throttle and log every jump.
// Usage: node tools/range_test.js <sim-core.js> [seconds] ['{"overrides":1}']
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const secs = +(process.argv[3] || 60);
const over = Object.assign({ track: 'range', startY: 400 }, JSON.parse(process.argv[4] || '{}'));
const sim = window.PhaethonSim.makeSim(over), S = sim.S, DT = 1 / 480;
let air = null, nan = false, worstStretch = 0, events = {};
for (let i = 0; i < secs / DT; i++) {
  sim.step({ thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
  const p = S.pod, gap = p.z - sim.ground(p.x, p.y), v = Math.hypot(p.vx, p.vy) * 3.6;
  if (!isFinite(p.x) || !isFinite(p.z)) { nan = true; break; }
  worstStretch = Math.max(worstStretch, Math.abs(S.binderStretch || 0));
  if (!air && p.grip < 0.5) air = { t: S.time, x: p.x, v, apex: p.z };
  if (air) air.apex = Math.max(air.apex, p.z);
  if (air && p.grip >= 0.99) {
    console.log(`jump @ x=${air.x.toFixed(0)} m, ${air.v.toFixed(0)} km/h: apex ${air.apex.toFixed(1)} m, ` +
      `${(S.time - air.t).toFixed(2)} s airborne, ${(p.x - air.x).toFixed(0)} m long, lands at ${v.toFixed(0)} km/h, y=${p.y.toFixed(1)}`);
    air = null;
  }
  while (S.events.length) { const e = S.events.shift(); events[e.type] = (events[e.type] || 0) + 1; }
}
const p = S.pod;
console.log(`after ${secs}s: x=${p.x.toFixed(0)} m (mile ${(p.x / 1609.344).toFixed(2)}), y=${p.y.toFixed(1)}, ` +
  `${(Math.hypot(p.vx, p.vy) * 3.6).toFixed(0)} km/h, max binder stretch ${worstStretch.toFixed(3)} m, events ${JSON.stringify(events)}, nan ${nan}`);
