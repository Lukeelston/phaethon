// Locked bodies must keep their ride height at their current position, at every shaft speed
// and in both directions. Godot's test_shaft_high_speed additionally checks the rendered mesh.
'use strict';
const assert = require('assert');
const PS = require('./net_route.js').load(process.argv[2] || 'sim-core.js');
const MPH = 2.236936, DT = 1 / 480;
const input = {thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, gearOverdrive: true};
let failures = 0;
for (const name of ['TE1-','TE1+','TE2-','TE2+','TE3-','TE3+','TN1-','TN1+','TN2-','TN2+','TN3-','TN3+'])
for (const mph of [4000, 8000, 12000, 20000]) for (const direction of [1, -1]) {
  const sim = PS.makeSim({track: 'network', handling: 'speed'}), {S,T,P} = sim;
  const r = T.roads.findIndex(road => road.name === name);
  const sh = T.shafts.find(shaft => shaft[0] === r), R = T.roads[r];
  const start = direction > 0 ? sh[1] - 40 : sh[2] + 40, a = R.pts[start];
  sim.respawnOn(r, start, direction);
  for (const b of S.bodies) { b.vx = direction * mph / MPH * a.tx; b.vy = direction * mph / MPH * a.ty; }
  let worst = 0, reached = false, invalid = false, peak = 0;
  for (let step = 0; step < 90 / DT; step++) {
    sim.step(input, DT);
    peak = Math.max(peak, S.pod.z);
    invalid ||= S.crashT > 0 || S.events.some(e => e.type === 'binder') || S.bodies.some(b => b.offRoad);
    S.events.length = 0;
    for (const b of S.bodies) {
      if (b.offRoad || b.lock) continue;
      const n = sim.nearestOn(b.path, b.x, b.y, b.hint, 12);
      const p = T.roads[b.path].pts[n.i];
      const fraction = Math.max(0, Math.min(1, ((b.x - p.x) * p.tx + (b.y - p.y) * p.ty) / p.len));
      const h = sim.netHeight(b.path, n.i + fraction) + sim.netEdge(n.w, n.lat)[0];
      worst = Math.max(worst, Math.abs(b.z - h - P.rideH));
    }
    if (S.pod.path !== r) {
      const parent = T.roads.findIndex(road => road.name === name.slice(1,3));
      const expectedDirection = name.endsWith('+') ? -1 : 1;
      const p = T.roads[parent].pts[0];
      reached = S.pod.path === parent && expectedDirection * (S.pod.vx*p.tx+S.pod.vy*p.ty) > 0;
      break;
    }
    if (direction > 0 ? S.pod.hint > sh[2] + 20 : S.pod.hint < sh[1] - 20) { reached = true; break; }
  }
  const top = 2*sh[3]+sh[4];
  const pass = reached && !invalid && peak > top-2 && worst < 0.05;
  console.log(`${pass ? 'ok' : 'FAIL'} shaft ${name} ${mph} mph dir ${direction}: max deck error ${worst.toFixed(6)} m, apex ${peak.toFixed(2)}/${top.toFixed(2)}, invalid ${invalid}, reached exit ${reached}`);
  if (!pass) failures++;
}
assert.strictEqual(failures, 0, 'all shaft bodies stay within 5 cm of their deck ride height');
console.log('SHAFT HEIGHT OK');
