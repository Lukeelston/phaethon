// Over Mount Hyperion's lip at a held speed, as sim-core.js flies it (Luke, 2026-11-22: "going over the edge
// slowly goes in chunks rather than just smoothly rolling over"): the reference for godot/tests/test_brink.gd,
// which flies each run again in the GD sim and holds the two to the same place.
// Each run: the craft set down `lead` samples short of a sample of SHyperion and held to mph along the road
// after every step (the sim's own thrust and drag left out of it, as tools/network_test.js's deck check holds
// it), until it is `past` samples beyond another. Recorded every 48th step (a tenth of a second): the step,
// the pod's x, y, z and the pitch the views are given (deckPitch, radians).
//   creep, slow, brisk   from 3 samples short of the lip to 3 down the wall, at 20, 80 and 250 mph
//   fast                 from 3 short of the crest over the summit and the lip to 3 down the wall, at 3,000 mph
//                        (a step is 2.8 m there: the pod is a sample or two on from its hint, which roadF walks)
// Usage: node tools/record_brink.js <sim-core.js> <out_dir>  -> brink_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const NR = require('./net_route.js');

const [simPath, outDir] = process.argv.slice(2);
if (!simPath || !outDir) { console.log('usage: node tools/record_brink.js <sim-core.js> <out_dir>'); process.exit(1); }
const PS = NR.load(simPath);
const { DT, MPH } = NR;
const EVERY = 48;

const probe = PS.makeSim({ track: 'network', handling: 'speed' });
const road = probe.T.roads.findIndex((R) => R.name === 'SHyperion');
assert(road >= 0 && probe.T.roads[road].deck, 'SHyperion is a deck road');
// the mountain's parts, found from the heights: the summit is where the road is highest, the crest and the lip's
// foot where the pitch stops turning either side of it
const N = probe.T.roads[road].N;
let hi = 0, summit = -1, lip = -1;
for (let i = 0; i < N; i++) hi = Math.max(hi, probe.netHeight(road, i));
for (let i = 0; i < N; i++) if (probe.netHeight(road, i) > hi - 1e-6) { if (summit < 0) summit = i; lip = i; }
const turning = (i) => Math.abs(probe.deckSine(road, i + 1) - probe.deckSine(road, i)) > 1e-9;
let drop = lip, crest = summit;
while (turning(drop)) drop++;
while (turning(crest - 1)) crest--;

function run(tag, mph, from, to) {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, a = sim.T.roads[road].pts[from];
  const v = mph / MPH;
  const hold = () => { for (const b of S.bodies) { b.vx = v * a.tx; b.vy = v * a.ty; b.w = 0; b.th = Math.atan2(a.ty, a.tx); } };
  const inp = { thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: true, handling: 'speed' };
  sim.respawnOn(road, from, 1);
  hold();
  const samples = [];
  let steps = 0;
  while (steps < 480 * 400 && sim.roadF(S.pod) < to) {
    sim.step(inp, DT);
    hold();
    S.events.length = 0;
    steps++;
    if (steps % EVERY === 0) samples.push([steps, S.pod.x, S.pod.y, S.pod.z, sim.deckPitch(S.pod)]);
  }
  assert(!S.pod.offRoad && S.pod.path === road, `${tag}: still on the road`);
  const end = [steps, S.pod.x, S.pod.y, S.pod.z, sim.deckPitch(S.pod)];
  console.log(`${tag}: ${mph} mph from sample ${from} to ${to}: ${steps} steps (${(steps * DT).toFixed(2)} s), ${samples.length} samples; ends ${(hi - end[3]).toFixed(2)} m under the summit, pitched ${(end[4] * 180 / Math.PI).toFixed(3)} deg`);
  return { tag, mph, from, to, steps, every: EVERY, samples, end };
}

const out = { road, summit, crest, lip, drop, height: hi, runs: [
  run('creep', 20, lip - 3, drop + 3),
  run('slow', 80, lip - 3, drop + 3),
  run('brisk', 250, lip - 3, drop + 3),
  run('fast', 3000, crest - 3, drop + 3),
] };
fs.writeFileSync(path.join(outDir, 'brink_expected.json'), JSON.stringify(out));
console.log('wrote', path.join(outDir, 'brink_expected.json'));
