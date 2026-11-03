'use strict';
const {load} = require('./net_route.js');
const PS = load(process.argv[2] || 'sim-core.js');
const dt = 1 / 480;
const idle = {thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: false};
let failures = 0;
function check(label, ok) { console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`); failures += !ok; }
function hit(enabled, shape = {}, height = 0.8) {
  const s = PS.makeSim({track: 'range', obstacleCollisions: enabled});
  s.S.pod.z = height;
  s.S.obstacles = [{id: 1, x: s.S.pod.x + 3, y: s.S.pod.y, vx: 0, vy: 0, r: 3, ...shape}];
  s.step(idle, dt);
  return s;
}
const on = hit(true), off = hit(false);
check('traffic contact emits a bump when enabled', on.S.events.some(e => e.type === 'bump'));
check('traffic contact causes no impact or push when disabled', !off.S.events.some(e => ['bump','smash'].includes(e.type)) && Math.abs(off.S.pod.vx) < 1e-10);
check('height-separated traffic does not hit a craft overhead', !hit(true, {zMin: 0, zMax: 4}, 100).S.events.some(e => e.type === 'bump'));
check('pillar box face responds within its actual footprint', hit(true, {r: 0, halfSize: 2, zMin: 0, zMax: 30}).S.events.some(e => e.type === 'bump'));
check('pillar does not extend through the bridge deck', !hit(true, {r: 0, halfSize: 2, zMin: 0, zMax: 30}, 35).S.events.some(e => e.type === 'bump'));
for (const enabled of [false, true]) {
  const s = PS.makeSim({track: 'gp', obstacleCollisions: enabled});
  const p = s.T.pts[0];
  for (const b of s.S.bodies) { b.x += p.nx * p.w; b.y += p.ny * p.w; }
  s.step(idle, dt);
  check(`guardrails still respond with obstacle collisions ${enabled}`, s.S.events.some(e => ['hit', 'scrape'].includes(e.type)));
  const landing = PS.makeSim({track: 'range', obstacleCollisions: enabled});
  for (const b of landing.S.bodies) { b.z = 0.31; b.vz = -30; }
  landing.step(idle, dt);
  check(`ground and landing stay active with obstacle collisions ${enabled}`, landing.S.events.some(e => e.type === 'land') && landing.S.pod.z >= 0.3);
}
console.log(`OBSTACLE COLLISIONS ${failures ? 'FAIL' : 'PASS'} (${failures} failures)`);
process.exitCode = failures ? 1 : 0;
