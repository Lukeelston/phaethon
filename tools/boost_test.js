// The boost (inp.boost held, inp.surge a power-up's gift) and the consumables (P.limits), on the
// open range: the numbers godot/tests/test_boost.gd holds the Godot sim to.
// Usage: node tools/boost_test.js <sim-core.js>
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const DT = 1 / 480, MPH = 2.236936;
const I = (o) => Object.assign({ thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: true }, o);
const spd = (b) => Math.hypot(b.vx, b.vy);
function fresh(extra) { const sim = window.PhaethonSim.makeSim(Object.assign({ track: 'range', startY: -3000 }, extra || {})); return { sim, S: sim.S }; }
function run(sim, S, inp, secs, cb) { const n = Math.round(secs / DT); for (let i = 0; i < n; i++) { sim.step(typeof inp === 'function' ? inp(i * DT) : inp, DT); S.events.length = 0; if (cb) cb(i * DT); } }
const out = {};

// 1. not asked for, nothing changes: the same flight with no boost keys, and with them false
{
  const a = fresh(), b = fresh();
  run(a.sim, a.S, I({ thrL: 0.87, thrR: 0.6 }), 20);
  run(b.sim, b.S, I({ thrL: 0.87, thrR: 0.6, boost: false, surge: false }), 20);
  out.same = a.S.pod.x === b.S.pod.x && a.S.pod.y === b.S.pod.y && a.S.pod.vx === b.S.pod.vx && a.S.eL.th === b.S.eL.th;
  out.plain_x = a.S.pod.x;
}
// 2. the thrust a stage: full lever at rest, a step
for (const [name, inp] of [['none', {}], ['held', { boost: true }], ['surge', { surge: true }], ['both', { boost: true, surge: true }]]) {
  const { sim, S } = fresh();
  sim.step(I(Object.assign({ thrL: 0.87, thrR: 0.87 }, inp)), DT);
  out['thrust_' + name] = S.eL.thrust;
  out['stages_' + name] = S.boost;
}
// 3. thirty seconds at full lever: plain, held from the start, held from 20 s
for (const [name, from] of [['plain', 1e9], ['held', 0], ['late', 20]]) {
  const { sim, S } = fresh();
  run(sim, S, (t) => I(Object.assign({ thrL: 0.87, thrR: 0.87 }, t >= from ? { boost: true } : {})), 30);
  out['mph30_' + name] = spd(S.pod) * MPH;
}
// 4. the consumables: two seconds of held boost off the burner spends the battery and heats the engines;
//    a flat battery is no boost; a surge is free
{
  const { sim, S } = fresh({ limits: true });
  run(sim, S, I({ thrL: 0.87, thrR: 0.87, boost: true }), 2);
  out.battery_2s = S.battery; out.heat_2s = S.eL.heat;
  run(sim, S, I({ thrL: 0.87, thrR: 0.87, boost: true }), 8);
  out.battery_10s = S.battery; out.stages_flat = S.boost; out.thrust_flat = S.eL.thrust;
  sim.step(I({ thrL: 0.87, thrR: 0.87, boost: true, surge: true }), DT);
  out.stages_flat_surge = S.boost;
  const c = fresh({ limits: true });
  run(c.sim, c.S, I({ thrL: 0.87, thrR: 0.87 }), 2);
  out.heat_2s_plain = c.S.eL.heat;
}
for (const k of Object.keys(out)) console.log(k.padEnd(20), typeof out[k] === 'number' ? out[k].toFixed(6) : out[k]);
