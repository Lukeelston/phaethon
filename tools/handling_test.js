// Handling report card on the open range (no walls).
// Usage: node tools/handling_test.js <sim-core.js> ['{"overrides":1}']
// Measures: top speeds, 0-4000 mph time, yaw rate at top speed for lever splits and a
// single brake, pod sway in a hard turn and its settle time, binder stretch, brake decel,
// and straight-line stability after a sideways kick.
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2], 'utf8'));
const over = Object.assign({ track: 'range', startY: -3000 }, JSON.parse(process.argv[3] || '{}'));
const DT = 1 / 480, G = 9.81, D = 180 / Math.PI, MPH = 2.236936;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const I = (o) => Object.assign({ thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: true }, o);
const spd = (b) => Math.hypot(b.vx, b.vy);
function fresh(extra) { const sim = window.PhaethonSim.makeSim(Object.assign({}, over, extra || {})); return { sim, S: sim.S }; }
function run(sim, S, inp, secs, cb) { for (let i = 0; i < secs / DT; i++) { sim.step(typeof inp === 'function' ? inp(i * DT) : inp, DT); S.events.length = 0; if (cb) cb(i * DT); } }
// pod sway = pod heading vs direction to the cable anchors' midpoint (0 = pod tracks the engines)
const sway = (S) => { const c = S.cables; if (c[0].ex === undefined) return 0; return Math.abs(wrap(S.pod.th - Math.atan2((c[0].ey + c[1].ey) / 2 - S.pod.y, (c[0].ex + c[1].ex) / 2 - S.pod.x))) * D; };
const out = [];

// top speeds and launch
for (const [label, lever, armed] of [['full lever', 0.87, false], ['afterburner', 1, false], ['ramjet', 1, true]]) {
  const { sim, S } = fresh({ batteryDrain: 0 });   // unlimited battery to find the true top
  S.armed = armed;
  let t4000 = null;
  run(sim, S, I({ thrL: lever, thrR: lever }), 60, (t) => { if (t4000 === null && spd(S.pod) * MPH >= 4000) t4000 = t; });
  out.push(`${label.padEnd(12)} top ${(spd(S.pod) * MPH).toFixed(0).padStart(5)} mph${label === 'full lever' ? `, 0-4000 mph in ${t4000 === null ? 'never' : t4000.toFixed(1) + ' s'}` : ''}`);
}

// cruise at top (full lever), then turn tests
function atLever(l) { const r = fresh(); run(r.sim, r.S, I({ thrL: l, thrR: l }), 40); return r; }
function atTop() { return atLever(0.87); }
function atSpeed(mph) { const r = fresh(); for (const b of r.S.bodies) { b.vx = mph / MPH; b.vy = 0; } run(r.sim, r.S, I({ thrL: 0.3, thrR: 0.3 }), 0.3); return r; }
for (const mid of [false, true]) for (const [label, inp] of [['25% split', I({ thrL: 0.87 * 0.75, thrR: 0.87 })], ['50% split', I({ thrL: 0.435, thrR: 0.87 })],
  ['full split', I({ thrL: 0, thrR: 0.87 })], ['one brake', I({ thrL: 0.87, thrR: 0.87, brkL: 1 })]]) {
  // slow pass: a 300 mph corner on ~0.3 levers, same split ratios scaled down
  const k = mid ? 0.3 / 0.87 : 1;
  const { sim, S } = mid ? atSpeed(300) : atTop();
  const v0 = spd(S.pod) * MPH;
  const scaled = Object.assign({}, inp, { thrL: inp.thrL * k, thrR: inp.thrR * k });
  let th = S.pairTh, vth = Math.atan2(S.pod.vy, S.pod.vx), maxSway = 0, maxStretch = 0, snapped = false;
  run(sim, S, scaled, 1.0, () => { maxSway = Math.max(maxSway, sway(S)); maxStretch = Math.max(maxStretch, Math.abs(S.binderStretch || 0)); snapped = snapped || S.binderBroken; });
  const yaw = Math.abs(wrap(S.pairTh - th)) * D;
  const vturn = Math.abs(wrap(Math.atan2(S.pod.vy, S.pod.vx) - vth)) * D;
  // release and measure settle: time until sway < 1 degree
  let settle = null;
  run(sim, S, I({ thrL: 0.87 * k, thrR: 0.87 * k }), 2.0, (t) => { if (settle === null && sway(S) < 1) settle = t; });
  out.push(`${label.padEnd(12)} @${v0.toFixed(0).padStart(4)} mph: path turns ${vturn.toFixed(1).padStart(5)} deg/s (nose ${yaw.toFixed(1).padStart(5)}), lat ~${(vturn / D * spd(S.pod) / G).toFixed(0)} g, sway ${maxSway.toFixed(1)} deg, settle ${settle === null ? '>2' : settle.toFixed(2)} s, binder ${maxStretch.toFixed(2)} m${snapped ? ' SNAPPED' : ''}`);
}

// brakes (both full, levers 0) from three speeds
for (const mph of [100, 1000, 'top']) {
  const r = mph === 'top' ? atTop() : fresh();
  if (mph !== 'top') for (const b of r.S.bodies) { b.vx = mph / MPH; b.vy = 0; }
  const v0 = spd(r.S.pod);
  run(r.sim, r.S, I({ brkL: 1, brkR: 1 }), 0.5);
  out.push(`brakes from ${String(mph === 'top' ? (v0 * MPH).toFixed(0) : mph).padStart(5)} mph: ${((v0 - spd(r.S.pod)) / 0.5 / G).toFixed(1)} g`);
}

// straight-line stability at top speed after a 30 m/s sideways kick to the pod
{
  const { sim, S } = atTop();
  S.pod.vy += 30;
  const th0 = S.pairTh;
  let maxSway = 0;
  run(sim, S, I({ thrL: 0.87, thrR: 0.87 }), 10, () => { maxSway = Math.max(maxSway, sway(S)); });
  const th1 = S.pairTh;
  run(sim, S, I({ thrL: 0.87, thrR: 0.87 }), 1);
  out.push(`kick @top: peak sway ${maxSway.toFixed(1)} deg, residual drift ${(Math.abs(wrap(S.pairTh - th1)) * D).toFixed(2)} deg/s, heading change ${(Math.abs(wrap(th1 - th0)) * D).toFixed(1)} deg`);
}
console.log(out.join('\n'));
