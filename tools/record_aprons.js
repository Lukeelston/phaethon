// The open edges' aprons (NET_APRONS: where a scenic road's land falls away on a side its deck runs on
// level past its old edge, the ramp and the wall that much further out), as sim-core.js flies them:
// the reference for godot/tests/test_scenic_range.gd, which replays each run in the GD sim.
// Each run: on a straight of a scenic road where one side's apron is whole, the craft set down `off` m
// to that side of the centreline (the old wall stood at 100) with `drift` m/s more that way, at mph, the
// levers at lev, for secs. Recorded: the pod every half second ([road, sample, x, y, z, vx, vy] and, to
// read, how far it is across the road and how high over the flat deck), every wall contact's step.
// Usage: node tools/record_aprons.js <sim-core.js> <out_dir>  -> aprons_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const NR = require('./net_route.js');

const [simPath, outDir] = process.argv.slice(2);
if (!simPath || !outDir) { console.log('usage: node tools/record_aprons.js <sim-core.js> <out_dir>'); process.exit(1); }
const PS = NR.load(simPath);
const { DT } = NR;
const NEED = 160;   // samples of straight a run wants ahead of it (3.8 km: 4 s at 2,000 mph is 149)

// The first sample of road R from `from` on with `NEED` samples of straight ahead and that side's apron whole all the way.
function straight(R, side, from) {
  const wide = (p) => (side > 0 ? p.al : p.ar);
  for (let i = from; i + NEED < R.N; i++) {
    const a = R.pts[i];
    let ok = true;
    for (let k = 0; k <= NEED && ok; k += 10) {
      const b = R.pts[i + k];
      ok = Math.abs(b.tx - a.tx) + Math.abs(b.ty - a.ty) < 1e-9 && wide(b) >= 149.999;
    }
    if (ok) return i;
  }
  return -1;
}

function run(tag, name, side, from, off, drift, mph, lev, secs, exact = false) {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const r = T.roads.findIndex((R) => R.name === name), R = T.roads[r];
  assert(r >= 0 && R.pts[0].al !== undefined, `${name} has aprons`);
  const i = exact ? from : straight(R, side, from), a = R.pts[i];
  assert(i >= 0, `${name} has a straight with its ${side > 0 ? 'left' : 'right'} apron whole`);
  assert(Math.abs(R.pts[i + NEED].tx - a.tx) + Math.abs(R.pts[i + NEED].ty - a.ty) < 1e-9, `${name} is straight for ${NEED} samples from ${i}`);
  sim.respawnOn(r, i, 1);
  const v = mph / NR.MPH;
  for (const b of S.bodies) {
    b.x += a.nx * side * off; b.y += a.ny * side * off;
    b.vx = v * a.tx + drift * side * a.nx; b.vy = v * a.ty + drift * side * a.ny;
  }
  const samples = [], events = [];
  let reach = -Infinity, high = 0;
  for (let k = 0; k < secs * 480; k++) {
    sim.step({ thrL: lev, thrR: lev, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (S.events.length) {
      const e = S.events.shift();
      if (e.type === 'hit' || e.type === 'scrape' || e.type === 'crash' || e.type === 'binder' || e.type === 'airborne') events.push([k, e.type]);
    }
    const p = S.pod, q = R.pts[p.hint];
    const lat = ((p.x - q.x) * q.nx + (p.y - q.y) * q.ny) * side;       // m toward the open side
    const over = p.z - sim.P.rideH - sim.netHeight(r, p.hint);          // m over the flat deck (the road is level across; its grade along is the hint's own)
    reach = Math.max(reach, lat);
    high = Math.max(high, over);
    if (k % 240 === 239) samples.push([p.path, p.hint, p.x, p.y, p.z, p.vx, p.vy, lat, over]);
  }
  const last = samples[samples.length - 1];
  console.log(`${tag}: ${name} sample ${i}, ${off} m to the ${side > 0 ? 'left' : 'right'} with ${drift} m/s more: reached ${reach.toFixed(2)} m, ends ${last[7].toFixed(2)} m out, ${high.toFixed(3)} m over the deck at most, events ${JSON.stringify(events.slice(0, 4))}${events.length > 4 ? ' ...' + events.length : ''}`);
  return { tag, name, side, start: [r, i, 1], off, drift, speed: v, lev, secs, samples, events, reach, high };
}

const out = { runs: [
  // on the coast's apron, 80 m past where its wall stood: level, nothing touched
  run('cruise', 'SCoast', 1, 2000, 180, 0, 2000, 0.6, 4),
  // ... drifting on out: the wall is 150 m further out than it was, and turns the craft back
  run('wall', 'SCoast', 1, 2000, 200, 40, 2000, 0.6, 4),
  // ... and up its ramp, which is the old ramp moved out
  run('ramp', 'SCoast', 1, 2000, 238, 0, 2000, 0.6, 2),
  // the drop's dive: an apron either side of the viaduct
  run('dive-right', 'SDrop', -1, 4400, 190, 0, 2000, 0.6, 4),
  run('dive-left', 'SDrop', 1, 4400, 190, 20, 2000, 0.6, 4),
  // the Caucasus: its right apron over the Network's side
  run('caucasus', 'SCaucasus', -1, 800, 170, 0, 2000, 0.6, 4),
  // where an apron grows (the drop's right, samples 4,347 to 4,547, on the dive's straight): from inside the old
  // wall, drifting out as it opens
  run('ease-in', 'SDrop', -1, 4352, 80, 30, 2000, 0.6, 4, true),
  // ... and where one goes (its left, 4,718 to 4,918): 200 m out as the wall comes in at a slant
  run('ease-out', 'SDrop', 1, 4698, 200, 0, 2000, 0.6, 5, true),
] };
// the closed side is where it was: the coast's mountain side still turns the craft back at 100 m
{
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const r = T.roads.findIndex((R) => R.name === 'SCoast'), R = T.roads[r], i = straight(R, 1, 2000), a = R.pts[i];
  sim.respawnOn(r, i, 1);
  const v = 2000 / NR.MPH;
  for (const b of S.bodies) { b.x -= a.nx * 60; b.y -= a.ny * 60; b.vx = v * a.tx - 40 * a.nx; b.vy = v * a.ty - 40 * a.ny; }
  let reach = -Infinity;
  const samples = [];
  for (let k = 0; k < 4 * 480; k++) {
    sim.step({ thrL: 0.6, thrR: 0.6, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    S.events.length = 0;
    const p = S.pod, q = R.pts[p.hint], lat = -((p.x - q.x) * q.nx + (p.y - q.y) * q.ny);
    reach = Math.max(reach, lat);
    if (k % 240 === 239) samples.push([p.path, p.hint, p.x, p.y, p.z, p.vx, p.vy, lat, 0]);
  }
  console.log(`closed: SCoast sample ${i}, 60 m to the right with 40 m/s more: reached ${reach.toFixed(2)} m`);
  out.closed = { start: [r, i, 1], off: 60, drift: 40, speed: v, lev: 0.6, secs: 4, samples, reach };
}
fs.writeFileSync(path.join(outDir, 'aprons_expected.json'), JSON.stringify(out));
console.log('wrote', path.join(outDir, 'aprons_expected.json'));
