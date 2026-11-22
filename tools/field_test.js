// The avoidance field (sim-core.js: inp.avoid, inp.avoidPush; Luke, 2026-11-22: "Add a collision avoidance
// force field") in the JS sim: scripted approaches to a wall and to a vehicle, the field off against on.
//   wall      a Network highway's straight, the craft set down `start` m from its left wall and flown at it at
//             an angle, at a speed, the levers held: contacts (hits, scrapes), the hardest sideways g on the
//             pod, the speed kept after 4 s, how near the wall its nearest circle came
//   hugging   flown along the wall 4 m off it, hands off: the field does nothing
//   demand    inp.avoidPush moves the craft sideways as one, by a t^2 / 2, and is capped
//   energy    with the limits on it spends the battery and stops when it is flat
//   off       inp.avoid not given: a flight is step for step what it was
// Usage: node tools/field_test.js <sim-core.js> [--table]
'use strict';
const assert = require('assert');
const NR = require('./net_route.js');

const simPath = process.argv[2];
if (!simPath) { console.log('usage: node tools/field_test.js <sim-core.js> [--table]'); process.exit(1); }
const TABLE = process.argv.includes('--table');
const PS = NR.load(simPath);
const { DT, MPH } = NR;
const G = 9.81;
const NEED = 400;   // samples of straight ahead (9.6 km: 4 s at 4,000 mph is 7.2 km)

function straight(R, from) {
  for (let i = from; i + NEED < R.N; i++) {
    const a = R.pts[i];
    let ok = true;
    for (let k = 0; k <= NEED && ok; k += 10) { const b = R.pts[i + k]; ok = Math.abs(b.tx - a.tx) + Math.abs(b.ty - a.ty) < 1e-9 && b.w === a.w; }
    if (ok) return i;
  }
  return -1;
}

// A craft on road `name`'s first long straight, its pod `start` m from the left wall, turned `deg` toward that wall
// and flying the way it points at mph.
function setUp(name, start, deg, mph, opts = {}) {
  const sim = PS.makeSim({ track: 'network', handling: opts.handling || 'speed' }), S = sim.S, T = sim.T;
  const r = T.roads.findIndex((R) => R.name === name), R = T.roads[r];
  const i = straight(R, opts.from || 300), a = R.pts[i];
  assert(i >= 0, `${name} has a straight`);
  sim.respawnOn(r, i, 1);
  const th = deg * Math.PI / 180, c = Math.cos(th), s = Math.sin(th), v = mph / MPH;
  const px = S.pod.x, py = S.pod.y, off = a.w / 2 - start;
  for (const b of S.bodies) {
    const dx = b.x - px, dy = b.y - py;
    b.x = px + dx * c - dy * s + a.nx * off; b.y = py + dx * s + dy * c + a.ny * off;
    b.th += th;
    b.vx = v * (a.tx * c + a.nx * s); b.vy = v * (a.ty * c + a.ny * s);
  }
  if (opts.limits) { sim.P.limits = true; if (opts.drained) S.battery = 0; }
  for (const a2 of process.argv) { const m = /^--P\.(\w+)=(.+)$/.exec(a2); if (m) sim.P[m[1]] = +m[2]; }
  return { sim, S, T, R, r, i, a };
}

// The nearest any of the craft's circles is to the left wall (m; negative inside it).
function clearance(S, R, a) {
  let least = Infinity;
  for (const b of S.bodies) {
    const lat = (b.x - a.x) * a.nx + (b.y - a.y) * a.ny;
    least = Math.min(least, a.w / 2 - lat - (b === S.pod ? 1.6 : 1.6));
  }
  return least;
}

function fly(tag, start, deg, mph, field, opts = {}) {
  const { sim, S, R, a } = setUp(opts.road || 'N1', start, deg, mph, opts);
  const lev = opts.lev === undefined ? 0.6 : opts.lev, secs = opts.secs || 4;
  const out = { tag, deg, mph, field, hits: 0, scrapes: 0, crashes: 0, others: [], peakG: 0, least: Infinity, fieldPeak: 0, fieldS: 0, avoids: 0 };
  const v0 = Math.hypot(S.pod.vx, S.pod.vy);
  for (let k = 0; k < secs * 480; k++) {
    const inp = { thrL: lev, thrR: lev, brkL: 0, brkR: 0, repair: false, reignite: true };
    if (field) inp.avoid = true; else if (opts.avoidFalse) inp.avoid = false;
    if (opts.push) inp.avoidPush = opts.push(k, S, a);
    const lx0 = S.pod.vx * a.nx + S.pod.vy * a.ny;
    sim.step(inp, DT);
    const lx1 = S.pod.vx * a.nx + S.pod.vy * a.ny;
    out.peakG = Math.max(out.peakG, Math.abs(lx1 - lx0) / DT / G);
    while (S.events.length) {
      const e = S.events.shift();
      if (e.type === 'hit') out.hits++;
      else if (e.type === 'scrape') out.scrapes++;
      else if (e.type === 'crash' || e.type === 'smash') out.crashes++;
      else if (e.type === 'avoid') out.avoids++;
      else if (e.type !== 'land' && e.type !== 'handling') out.others.push(e.type);
    }
    out.least = Math.min(out.least, clearance(S, R, a));
    out.fieldPeak = Math.max(out.fieldPeak, S.avoidA || 0);
    out.lowBattery = Math.min(out.lowBattery === undefined ? 1 : out.lowBattery, S.battery);
    if (S.avoidA > 0) out.fieldS += DT;
  }
  out.kept = Math.hypot(S.pod.vx, S.pod.vy) / v0;
  out.away = Math.atan2(-(S.pod.vx * a.nx + S.pod.vy * a.ny), S.pod.vx * a.tx + S.pod.vy * a.ty) * 180 / Math.PI;   // deg off the wall at the end
  out.battery = S.battery;
  out.end = { x: S.pod.x, y: S.pod.y, vx: S.pod.vx, vy: S.pod.vy, lat: (S.pod.x - a.x) * a.nx + (S.pod.y - a.y) * a.ny };
  return out;
}

const row = (o) => `${o.tag.padEnd(10)} ${String(o.deg).padStart(4)} deg ${String(o.mph).padStart(5)} mph field ${o.field ? 'on ' : 'off'} | hits ${o.hits} scrapes ${String(o.scrapes).padStart(2)} crashes ${o.crashes} | peak ${o.peakG.toFixed(1).padStart(6)} g | nearest ${o.least.toFixed(2).padStart(7)} m | speed kept ${(o.kept * 100).toFixed(1).padStart(5)}% | leaves at ${o.away.toFixed(1).padStart(5)} deg | field ${(o.fieldPeak / G).toFixed(1).padStart(5)} g for ${o.fieldS.toFixed(2)} s${o.others.length ? ' | ' + [...new Set(o.others)].join(',') : ''}`;

const results = {};
let fails = 0;
const check = (label, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + label); if (!ok) fails++; };

// ---- walls: off against on ----
const ANGLES = [1, 3, 6, 12, 30], SPEEDS = [500, 2000, 4000], START = 150;   // m from the wall, the pod, at the start
const walls = [];
for (const mph of SPEEDS) for (const deg of ANGLES) {
  const off = fly('wall', START, deg, mph, false), on = fly('wall', START, deg, mph, true);
  walls.push([off, on]);
  if (TABLE) { console.log(row(off)); console.log(row(on)); }
}
results.walls = walls.map(([off, on]) => ({ deg: off.deg, mph: off.mph, off: [off.hits, off.scrapes, +off.peakG.toFixed(2), +off.kept.toFixed(4), +off.least.toFixed(3)], on: [on.hits, on.scrapes, +on.peakG.toFixed(2), +on.kept.toFixed(4), +on.least.toFixed(3)] }));
module.exports = { fly, setUp, row, results, PS };

if (require.main === module) {
  const glancing = walls.filter(([off]) => off.deg <= 6);
  check(`glancing approaches (1, 3 and 6 deg at 500, 2,000 and 4,000 mph, from ${START} m out): with the field off ${glancing.filter(([off]) => off.hits + off.scrapes > 0).length} of ${glancing.length} touch the wall (the edge's own ramp turns the shallowest); with it on ${glancing.filter(([, on]) => on.hits + on.scrapes > 0).length} do, the nearest ${Math.min(...glancing.map(([, on]) => on.least)).toFixed(2)} m off it, the hardest ${Math.max(...glancing.map(([, on]) => on.peakG)).toFixed(0)} g sideways`,
    glancing.filter(([off]) => off.hits + off.scrapes > 0).length >= 3 && glancing.every(([, on]) => on.hits + on.scrapes === 0 && on.least > 0 && on.peakG < 40));
  const square = walls.filter(([off]) => off.deg >= 12);
  check(`squarer ones (12 and 30 deg): missed where there is time, else softened, never worse: the hardest sideways g on the pod ${square.map(([off, on]) => `${off.peakG.toFixed(0)} -> ${on.peakG.toFixed(0)}`).join(', ')}; wall contacts ${square.map(([off, on]) => `${off.hits + off.scrapes} -> ${on.hits + on.scrapes}`).join(', ')}`,
    square.every(([off, on]) => on.peakG <= off.peakG * 1.02 + 1 && on.hits + on.scrapes <= off.hits + off.scrapes) && square.filter(([off, on]) => on.peakG < off.peakG * 0.8).length >= 4
    && square.filter(([, on]) => on.hits + on.scrapes === 0).length >= 2);
  check(`the field never costs speed worth the name: speed kept after 4 s, off against on, worst ${Math.min(...walls.map(([off, on]) => on.kept - off.kept)).toFixed(3)} of the starting speed`,
    walls.every(([off, on]) => on.kept >= off.kept - 0.02));
  check(`nobody crashes with it on who did not with it off (${walls.map(([off, on]) => `${off.crashes}/${on.crashes}`).join(' ')})`, walls.every(([off, on]) => on.crashes <= off.crashes));
  check(`it says so once a save, not once a step: 'avoid' events ${walls.map(([, on]) => on.avoids).join(' ')} over the fifteen flights`, walls.every(([, on]) => on.avoids <= 6));
  // ---- along the wall ----
  const hug = fly('hug', 12, 0, 2000, true, { secs: 2 }), hugOff = fly('hug', 12, 0, 2000, false, { secs: 2 });
  if (TABLE) { console.log(row(hugOff)); console.log(row(hug)); }
  check(`set down along the wall 12 m off it at 2,000 mph, 2 s: the field does nothing (${hug.fieldS.toFixed(2)} s working) and the flight is the one without it (${Math.hypot(hug.end.x - hugOff.end.x, hug.end.y - hugOff.end.y)} m apart)`,
    hug.fieldS === 0 && hug.end.x === hugOff.end.x && hug.end.y === hugOff.end.y && hug.end.vx === hugOff.end.vx);
  const lean = fly('lean', 6, 0.25, 2000, true, { secs: 1.2 });
  if (TABLE) console.log(row(lean));
  check(`leaning on a wall is still allowed: closing on it at ${(2000 / MPH * Math.sin(0.25 * Math.PI / 180)).toFixed(1)} m/s from 6 m the field stays out of it (${lean.fieldS.toFixed(2)} s working; ${lean.scrapes + lean.hits} contacts)`, lean.fieldS === 0);
  // ---- the view's demand ----
  const a10 = 10 * G;
  const plain = fly('push', 200, 0, 2000, false, { secs: 1 });
  const pushed = fly('push', 200, 0, 2000, true, { secs: 1, push: (k, S, a) => (k < 240 ? [a.nx * a10, a.ny * a10] : [0, 0]) });
  const over = fly('push', 200, 0, 2000, true, { secs: 1, push: (k, S, a) => (k < 240 ? [a.nx * 900, a.ny * 900] : [0, 0]) });
  const moved = pushed.end.lat - plain.end.lat;
  if (TABLE) { console.log(row(pushed)); console.log(row(over)); }
  check(`a demand of 10 g to the left for half a second in the road's middle: the craft is ${moved.toFixed(1)} m further left a second on (a t^2 / 2 and the half second's coast at a t: ${(a10 * 0.125 + a10 * 0.25).toFixed(1)} m), its speed ${(pushed.kept / plain.kept * 100).toFixed(2)}% of the flight without; a demand of 92 g is given as ${(over.fieldPeak / G).toFixed(1)} g`,
    moved > 0.6 * (a10 * 0.375) && moved < 1.4 * (a10 * 0.375) && Math.abs(pushed.kept / plain.kept - 1) < 0.01 && Math.abs(over.fieldPeak - PS.makeSim({ track: 'network' }).P.avoidMaxA) < 1e-6);
  // ---- energy ----
  const paid = fly('energy', START, 6, 2000, true, { limits: true });
  const flat = fly('energy', START, 6, 2000, true, { limits: true, drained: true, lev: 1 });   // (the burner held on a flat battery: it does not charge)
  if (TABLE) { console.log(row(paid)); console.log(row(flat)); }
  check(`with the heat and energy on a save costs battery (the 6 deg approach at 2,000 mph: ${((1 - paid.lowBattery) * 100).toFixed(1)}% of it, charged back after); flat, with the burner held so that it stays flat, the field is dead and the wall is met as before (${flat.hits + flat.scrapes} contacts, ${flat.fieldS.toFixed(2)} s working)`,
    paid.lowBattery < 0.99 && paid.lowBattery > 0.7 && paid.hits + paid.scrapes === 0 && flat.fieldS === 0 && flat.hits + flat.scrapes > 0);
  // ---- off ----
  const never = fly('off', START, 6, 2000, false), no = fly('off', START, 6, 2000, false, { avoidFalse: true });
  check(`not asked for, or asked not to: the same flight to the last digit, and nothing of the field in the sim's state`,
    never.end.x === no.end.x && never.end.y === no.end.y && never.end.vx === no.end.vx && never.fieldPeak === 0 && no.fieldPeak === 0 && never.avoids + no.avoids === 0);
  if (TABLE || process.argv.includes('--figures')) {
    // for godot/tests/test_avoidance_field.gd: the same flights in the GD sim must end where these do
    for (const [deg, mph] of [[6, 2000], [12, 500], [30, 4000]]) {
      const o = fly('parity', START, deg, mph, true), s = setUp('N1', START, deg, mph);
      console.log(`PARITY {"deg": ${deg}, "mph": ${mph}, "road": ${s.r}, "i": ${s.i}, "x": ${o.end.x.toFixed(6)}, "y": ${o.end.y.toFixed(6)}, "vx": ${o.end.vx.toFixed(6)}, "vy": ${o.end.vy.toFixed(6)}, "contacts": ${o.hits + o.scrapes}, "field_s": ${o.fieldS.toFixed(4)}, "peak": ${o.fieldPeak.toFixed(4)}}`);
    }
  }
  if (fails) { console.log(`FIELD FAIL (${fails})`); process.exit(1); }
  console.log('FIELD PASS');
}
