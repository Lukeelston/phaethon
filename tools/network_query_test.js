// Real Network cell boundaries must not return a farther run of the same road.
// This caused launch-lip recapture and false deck undersides in the 20-jump layout.
'use strict';
const assert = require('assert');
const PS = require('./net_route.js').load(process.argv[2] || 'sim-core.js');
const sim = PS.makeSim({track: 'network', handling: 'speed'});
let queries = 0, comparisons = 0;
for (const [launch, catcher] of sim.T.jumps) {
  for (const r of [launch, catcher]) {
    const R = sim.T.roads[r];
    for (const [i, along] of [[0, -150], [0, 5], [R.N - 1, -10], [R.N - 1, 50]]) {
      const p = R.pts[i], x = p.x + p.tx * along, y = p.y + p.ty * along;
      const near = sim.netNear(x, y);
      assert.strictEqual(new Set(near.map(n => n.r)).size, near.length, `${R.name}:${i}:${along} returns one candidate per road`);
      const n = near.find(n => n.r === r);
      assert(n, `${R.name} remains inside the unchanged query radius`);
      const exact = sim.nearestOn(r, x, y, R.N >> 1, R.N);
      assert.strictEqual(n.i, exact.i, `${R.name}:${i}:${along} uses its true nearest sample`);
      assert.strictEqual(n.off, exact.off, `${R.name}:${i}:${along} has the true endpoint status`);
      assert(Math.abs(n.lat - exact.lat) < 1e-7, `${R.name} has the true lateral distance`);
      queries++; comparisons += 3;
    }
  }
}
// The aerial crossing exemption must not make a catch deck's ground-level guardrail
// permeable to sideways ground traffic, with either obstacle-collision setting.
for (const obstacleCollisions of [false, true]) {
  const s = PS.makeSim({track: 'network', handling: 'speed', obstacleCollisions});
  const catcher = s.T.jumps[0][1], road = s.T.roads[catcher];
  const i = road.hk.at(-1)[0] + 30, p = road.pts[i];
  s.respawnOn(catcher, i, 1);
  for (const b of s.S.bodies) {
    b.x += p.nx * (road.width / 2 + 1);
    b.y += p.ny * (road.width / 2 + 1);
    b.offRoad = true; b.lock = false; b.z = s.P.rideH; b.vz = 0;
    b.vx = -100 * p.nx; b.vy = -100 * p.ny;
  }
  s.step({thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: false}, 1 / 480);
  const inward = s.S.pod.vx * p.nx + s.S.pod.vy * p.ny;
  assert(inward > -50, `ground-level catch guardrail stops side entry (obstacle collisions ${obstacleCollisions}, ${inward} m/s)`);
}
console.log(`NETWORK QUERY PASS (${queries} boundary queries, ${comparisons} exhaustive comparisons)`);
