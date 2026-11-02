// The Network's parity reference (godot/tests/test_network_parity.gd): the roads' geometry (every
// 97th sample of every road, and both ends of every junction zone), and a drive from Eridanus to
// Glacier by the autopilot (tools/net_route.js: Eridanus' bypass, highways, quadrant ramps, Glacier's
// bypass). The rounded input log is replayed: that replay is what the GD sim must match (each road
// change [frame, body, road, sample], the arrival [frame, city, from, t], the pod at the end).
// Inputs: [thrL, thrR, brkL, brkR, h] per 8 x 1/480 s frame; h 0 = no ask, 1 = speed, 2 = starfighter.
// Phase 3: the roads' heights (each geometry sample's), and scripted runs: a jump at 4,000 mph (off
// the lip, caught by the deck), one at 2,500 (off the lip, turned down under the deck, onto the open
// ground), and the open ground into Glacier's on-ramp's open start; their events, the pod at the end.
// Usage: node tools/record_network.js <sim-core.js> <out_dir>  -> network_inputs.json, network_expected.json
'use strict';
const fs = require('fs');
const path = require('path');
const NR = require('./net_route.js');

const [simPath, outDir] = process.argv.slice(2);
if (!simPath || !outDir) { console.log('usage: node tools/record_network.js <sim-core.js> <out_dir>'); process.exit(1); }
const PS = NR.load(simPath);
const { DT, SUB, r4 } = NR;
const ASK = [undefined, 'speed', 'starfighter'];
const MAX_T = 600;

function flyOnce(inputs) {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const ci = (n) => T.cities.findIndex((c) => c.name === n);
  const e = T.cities[ci('ERIDANUS')], g = T.cities[ci('GLACIER')];
  const legs = NR.find(T, { road: e.road, i: e.i, dir: 0 }, [{ road: g.road, i: g.i }]), last = legs[legs.length - 1];
  last.i1 = Math.max(0, Math.min(T.roads[last.road].N - 1, last.i1 + last.dir * 120));
  const route = NR.points(T, legs), vplan = NR.plan(route);
  sim.respawnOn(e.road, e.i, route.pts[1].i >= route.pts[0].i ? 1 : -1);
  const pilot = NR.makePilot(S, route, vplan);
  const log = [], switches = [], arrivals = [];
  let prev = S.bodies.map((b) => b.path), hits = 0, scrapes = 0, top = 0;
  for (let f = 0; f * SUB * DT < MAX_T; f++) {
    const u = inputs ? inputs[f] : pilot();
    if (!u) break;
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] };
    for (let k = 0; k < SUB; k++) {
      sim.step(inp, DT);
      top = Math.max(top, Math.hypot(S.pod.vx, S.pod.vy));
      S.bodies.forEach((b, bi) => { if (b.path !== prev[bi]) { switches.push([f, bi, b.path, b.hint]); prev[bi] = b.path; } });
      while (S.events.length) {
        const ev = S.events.shift();
        if (ev.type === 'hit') hits++;
        else if (ev.type === 'scrape') scrapes++;
        else if (ev.type === 'arrive') arrivals.push([f, ev.city, ev.from, ev.t]);
      }
    }
  }
  return { sim, log, switches, arrivals, hits, scrapes, top, start: [e.road, e.i, route.pts[1].i >= route.pts[0].i ? 1 : -1] };
}

// Traffic: the pod on E2 at 2,000 mph, levers at 0.5, two obstacles (a glancing catch-up, then 2 s in
// a road train's car head-on 1 km ahead: the smash, and back at Eridanus); every bump and smash, the
// pod at the end. Obstacles as [step added, id, r, x, y, vx, vy].
function trafficDrive() {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const E2 = T.roads.findIndex((R) => R.name === 'E2'), i = 6000, p = T.roads[E2].pts[i];
  sim.respawnOn(E2, i, 1);
  const v = 2000 / NR.MPH;
  for (const b of S.bodies) { b.vx = v * p.tx; b.vy = v * p.ty; }
  const at = (ahead, left, sv, sl) => ({ x: p.x + p.tx * ahead + p.nx * left, y: p.y + p.ty * ahead + p.ny * left, vx: sv / NR.MPH * p.tx + sl * p.nx, vy: sv / NR.MPH * p.ty + sl * p.ny });
  S.obstacles = [Object.assign({ id: 1, r: 3 }, at(600, 1.5, 1200, 0))];
  const events = [];
  let late = null;
  for (let k = 0; k < 6 * 480; k++) {
    if (k === 960) {   // 2 s in: a road train's car head-on, 1 km ahead of where the pod is going
      const sp = Math.hypot(S.pod.vx, S.pod.vy), ux = S.pod.vx / sp, uy = S.pod.vy / sp;
      late = { id: 3, r: 10, x: S.pod.x + ux * 1000, y: S.pod.y + uy * 1000, vx: -1000 / NR.MPH * ux, vy: -1000 / NR.MPH * uy };
      S.obstacles.push(Object.assign({}, late));
    }
    sim.step({ thrL: 0.5, thrR: 0.5, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (S.events.length) {
      const e = S.events.shift();
      if (e.type === 'bump' || e.type === 'smash') events.push([k, e.type, e.id, Math.round(e.v * 1000) / 1000]);
    }
  }
  const o1 = at(600, 1.5, 1200, 0);
  return { start: [E2, i, 1], obstacles: [[0, 1, 3, o1.x, o1.y, o1.vx, o1.vy], [960, 3, 10, late.x, late.y, late.vx, late.vy]],
    speed: v, events, final_pod: [S.pod.x, S.pod.y], final_path: S.pod.path, crash: S.crashT };
}

// a jump: on launch spur k, 300 samples short of its lip at mph, the levers at lev, for secs
const JEV = ['airborne', 'catch', 'onroad', 'ground'];
function jumpRun(k, mph, lev, secs) {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const [l] = T.jumps[k], L = T.roads[l], i = L.N - 1 - 300, a = L.pts[i];
  sim.respawnOn(l, i, 1);
  const v = mph / NR.MPH;
  for (const b of S.bodies) { b.vx = v * a.tx; b.vy = v * a.ty; }
  return runOut(sim, { start: [l, i, 1], speed: v, lev, secs }, lev, secs);
}
function runOut(sim, out, lev, secs) {
  const S = sim.S, events = [];
  for (let k = 0; k < secs * 480; k++) {
    sim.step({ thrL: lev, thrR: lev, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (S.events.length) {
      const e = S.events.shift();
      if (JEV.includes(e.type)) events.push([k, e.type, e.road ?? -1, Math.round((e.v ?? 0) * 1000) / 1000]);
    }
  }
  return Object.assign(out, { events, final_pod: [S.pod.x, S.pod.y, S.pod.z], final_path: S.pod.path, off_road: S.pod.offRoad });
}
// the burner as the headset lights it (inp.burner, the levers under the gate): on E2 at 3,000 mph,
// the levers split 0.87 / 0.6 for 2 s, then swapped for 2 s, the burner flagged on throughout; then
// 1 s flagged off at 0.87 both
function burnerRun() {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const E2 = T.roads.findIndex((R) => R.name === 'E2'), a = T.roads[E2].pts[6000];
  sim.respawnOn(E2, 6000, 1);
  for (const b of S.bodies) { b.vx = 3000 / NR.MPH * a.tx; b.vy = 3000 / NR.MPH * a.ty; }
  const modes = [];
  for (let k = 0; k < 5 * 480; k++) {
    const on = k < 4 * 480, swap = k >= 2 * 480;
    sim.step({ thrL: on ? (swap ? 0.6 : 0.87) : 0.87, thrR: on ? (swap ? 0.87 : 0.6) : 0.87, brkL: 0, brkR: 0, repair: false, reignite: true, burner: on }, DT);
    if (k % 480 === 479) modes.push(S.mode);
  }
  return { start: [E2, 6000, 1], speed: 3000 / NR.MPH, modes, final_pod: [S.pod.x, S.pod.y, S.pod.th], battery: S.battery, heat: [S.eL.heat, S.eR.heat] };
}
// a highway's dead end (its turnaround's junction holds it closed, so the end is a wall across the
// road): every body at 2,500 km/h along N1, ~2 s short of its far end, full brakes for 5 s. The
// binder holds and the end stops the craft (a circle just past the end used to take the turnaround's
// road ~300 m to the side as 210 m of wall: a 1.3e9 N kick, the binder torn). Wall hits, the bodies.
function deadEndRun() {
  const sim = PS.makeSim({ track: 'network', handling: 'starfighter' }), S = sim.S, T = sim.T;
  const N1 = T.roads.findIndex((R) => R.name === 'N1'), R = T.roads[N1], i = R.N - 1 - 58, a = R.pts[i];
  sim.respawnOn(N1, i, 1);
  const v = 2500 / 3.6;
  for (const b of S.bodies) { b.vx = v * a.tx; b.vy = v * a.ty; }
  const events = [];
  for (let k = 0; k < 5 * 480; k++) {
    sim.step({ thrL: 0, thrR: 0, brkL: 1, brkR: 1, repair: false, reignite: true, handling: 'starfighter' }, DT);
    while (S.events.length) { const e = S.events.shift(); if (e.type === 'binder' || e.type === 'hit') events.push([k, e.type, e.who ?? '']); }
  }
  return { start: [N1, i, 1], speed: v, events: events.slice(0, 12), binder: S.binderBroken, bodies: S.bodies.map((b) => [b.x, b.y, b.th, b.vx, b.vy]) };
}
// the open ground: on E2, then every body put 1 km short of Glacier's on-ramp's start, on its line,
// off the roads, at 400 mph (bodies0: [x, y, th, vx, vy, z] each, eL eR pod), levers 0.2
function groundRun() {
  const sim = PS.makeSim({ track: 'network', handling: 'speed' }), S = sim.S, T = sim.T;
  const E2 = T.roads.findIndex((R) => R.name === 'E2');
  sim.respawnOn(E2, 7000, 1);
  const O = T.roads[T.onramps[2][1]], o = O.pts[0], bodies0 = [];
  for (const [b, side] of [[S.eL, 1], [S.eR, -1], [S.pod, 0]]) {
    const fwd = side === 0 ? -1000 : -975;
    b.x = o.x + o.tx * fwd + o.nx * side * 3; b.y = o.y + o.ty * fwd + o.ny * side * 3;
    b.th = Math.atan2(o.ty, o.tx); b.w = 0; b.offRoad = true; b.lock = false; b.z = S.P.rideH; b.vz = 0;
    b.vx = 400 / NR.MPH * o.tx; b.vy = 400 / NR.MPH * o.ty;
    bodies0.push([b.x, b.y, b.th, b.vx, b.vy, b.z]);
  }
  return runOut(sim, { start: [E2, 7000, 1], bodies0, lev: 0.2, secs: 6 }, 0.2, 6);
}

const first = flyOnce(null);
const rec = flyOnce(first.log);
const T = rec.sim.T;
const geom = T.roads.map((R) => {
  const want = new Set();
  for (let i = 0; i < R.N; i += 97) want.add(i);
  want.add(R.N - 1);
  for (const k of R.jx) { const J = T.junctions[k]; for (const i of (J.a === T.roads.indexOf(R) ? [J.a0, J.a1] : [J.b0, J.b1])) want.add(i); }
  const r = T.roads.indexOf(R);
  const samples = [...want].sort((a, b) => a - b).map((i) => { const p = R.pts[i]; return [i, p.x, p.y, p.tx, p.ty, p.len, p.w, p.mode === 'sf' ? 0 : 1, rec.sim.netHeight(r, i)]; });
  return { name: R.name, N: R.N, length: R.length, samples };
});
const P = rec.sim.S.pod;
const expected = {
  roads: geom, junctions: T.junctions.map((J) => [J.a, J.a0, J.a1, J.b, J.b0, J.b1, J.sense]),
  cities: T.cities.map((c) => [c.name, c.road, c.i]), start: rec.start,
  frames: rec.log.length, switches: rec.switches, arrivals: rec.arrivals, hits: rec.hits, scrapes: rec.scrapes,
  final_pod: [P.x, P.y], final_path: P.path, top_mph: Math.round(rec.top * NR.MPH),
  traffic: trafficDrive(),
  jumps: [jumpRun(0, 4000, 0.87, 12), jumpRun(0, 2500, 0.3, 25), groundRun()],
  burner: burnerRun(),
  dead_end: deadEndRun()
};
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'network_inputs.json'), JSON.stringify(rec.log));
fs.writeFileSync(path.join(outDir, 'network_expected.json'), JSON.stringify(expected));
const a = rec.arrivals[0];
console.log(`traffic: ${JSON.stringify(expected.traffic.events)}`);
console.log(`dead end: binder ${expected.dead_end.binder ? 'TORN' : 'holds'}, events ${JSON.stringify(expected.dead_end.events)}, pod at ${Math.hypot(expected.dead_end.bodies[2][3], expected.dead_end.bodies[2][4]).toFixed(2)} m/s`);
console.log(`network: ${rec.log.length} frames, ${rec.switches.length} road changes, arrival ${a ? `${T.cities[a[1]].name} from ${T.cities[a[2]].name} in ${a[3].toFixed(2)} s at frame ${a[0]}` : 'none'}, ${rec.hits} hits / ${rec.scrapes} scrapes, top ${expected.top_mph} mph`);
