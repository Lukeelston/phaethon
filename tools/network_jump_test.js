// Exercise every Network ascent through real sim steps at below-minimum, minimum and high speed.
// The controller only moves both throttle levers; velocities are set once at the initial lineup.
const assert = require('assert');
const NR = require('./net_route.js');
global.window = {};
require('../sim-core.js');
const PS = window.PhaethonSim;
const MPH = 2.236936, DT = 1 / 480;

function traverse(index, targetMph) {
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const [launch, catcher] = s.T.jumps[index], L = s.T.roads[launch];
  const start = L.N - 301, p = L.pts[start], target = targetMph / MPH;
  s.respawnOn(launch, start, 1);
  for (const b of s.S.bodies) { b.vx = target * p.tx; b.vy = target * p.ty; }
  const events = [];
  let peak = 0, crash = false, caughtAt = null;
  const feed = s.P.gate * (2 * s.P.engineCd + s.P.podCd) * target * target / (2 * s.P.thrustMax);
  for (let f = 0; f < 70 / DT; f++) {
    const speed = Math.hypot(s.S.pod.vx, s.S.pod.vy);
    const lever = Math.max(0, Math.min(0.87, feed + (target - speed) * 0.003));
    s.step({ thrL: lever, thrR: lever, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    peak = Math.max(peak, s.S.pod.z);
    crash ||= s.S.crashT > 0;
    while (s.S.events.length) {
      const e = s.S.events.shift();
      events.push({ t: f * DT, ...e });
      if (e.type === 'catch' && e.road === catcher) caughtAt = f * DT;
    }
    // The four transfer decks are long turning interchanges. Check capture here;
    // drive their complete real route below using throttle/brake steering only.
    if (index < 4 && caughtAt !== null && f * DT - caughtAt >= 2) break;
    if (events.some(e => e.type === 'ground' || e.type === 'onroad') || (events.some(e => e.type === 'catch') && s.S.pod.path !== catcher && s.S.pod.path !== launch)) break;
  }
  return { s, events, peak, crash, launch, catcher };
}

function finishTransfer(r) {
  const { s, catcher } = r, C = s.T.roads[catcher];
  const join = s.T.junctions.find(j => j.b === catcher && j.b1 === C.N - 1);
  const end = NR.across(join, false, C.N - 1), direction = join.sense;
  const legs = NR.find(s.T, { road: catcher, i: s.S.pod.hint, dir: 1 }, [{ road: join.a, i: end + direction * 160 }]);
  const route = NR.points(s.T, legs), pilot = NR.makePilot(s.S, route, NR.plan(route));
  let input = null, crash = false;
  for (let step = 0; step < 420 / DT; step++) {
    if (step % 8 === 0) {
      const u = pilot();
      if (!u) break;
      input = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true };
    }
    s.step(input, DT);
    crash ||= s.S.crashT > 0;
    if (!s.S.pod.offRoad && s.S.pod.path === join.a && (s.S.pod.hint - end) * direction > 50) break;
  }
  assert(!crash && !s.S.pod.offRoad && s.S.pod.path === join.a,
    `${C.name} completes its interchange onto ${s.T.roads[join.a].name} with throttle/brake controls`);
  console.log(`TRANSFER ${C.name} -> ${s.T.roads[join.a].name} PASS`);
}

function main() {
  const T = PS.makeSim({ track: 'network', handling: 'speed' }).T;
  assert.strictEqual(T.jumps.length, 20, 'four ascents at each of five non-corner interchanges');
  assert(new Set(T.jumps.map(j => j[2])).size >= 6, 'minimum speeds are meaningfully varied');
  const peaks = [];
  for (let k = 0; k < T.jumps.length; k++) {
    const min = T.jumps[k][2];
    for (const [kind, mph] of [['low', min - 500], ['minimum', min], ['high', Math.max(4200, min + 500)]]) {
      const r = traverse(k, mph), air = r.events.find(e => e.type === 'airborne' && e.lip);
      const cat = r.events.find(e => e.type === 'catch'), ground = r.events.find(e => e.type === 'ground');
      console.log(`J${k} ${kind} ${mph} MPH: lip ${air ? Math.round(air.v * MPH) : '-'}, catch ${cat ? r.s.T.roads[cat.road].name : '-'}, ground ${!!ground}, peak ${Math.round(r.peak)} m, final ${r.s.T.roads[r.s.S.pod.path].name}, crash ${r.crash}`);
      assert(air && !r.crash, `J${k} ${kind} leaves the lip safely`);
      if (kind === 'low') assert(!cat && (ground || r.events.some(e => e.type === 'onroad')), `J${k} under speed misses the raised catch and settles onto ground or a lower road`);
      else {
        assert(cat && cat.road === r.catcher, `J${k} ${kind} catches its intended deck`);
        if (k < 4) {
          assert(!r.s.S.pod.offRoad && r.s.S.pod.path === r.catcher, `J${k} ${kind} settles on its transfer deck`);
          if (kind === 'minimum') finishTransfer(r);
        } else assert(!r.s.S.pod.offRoad && r.s.S.pod.path !== r.catcher && r.s.S.pod.path !== r.launch, `J${k} ${kind} returns to the highway`);
        if (kind === 'minimum') peaks.push(r.peak);
      }
    }
  }
  assert(Math.max(...peaks) - Math.min(...peaks) > 900, 'ascent summits span at least 900 m');
  for (const [city, road] of T.onramps) assert(T.cities[city] && T.roads[road].role === 'on', 'on-ramp indices remain valid');
  console.log('NETWORK JUMP MATRIX PASS');
}
if (require.main === module) main();
module.exports = { traverse };
