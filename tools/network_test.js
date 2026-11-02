// The Network (track "network", docs/superpowers/specs/2026-10-19-network-design.md) in the JS sim:
//   build      every road walked from its pose; each junction's zones lie inside each other's corridors
//   strangers  straight through a crossing (a flyover) at 3,000 mph: never on the other highway,
//              never a wall
//   drive      Eridanus to Glacier by the autopilot (its bypass, highways, a quadrant ramp): every
//              change of road inside a junction zone joining the two; arrives at Glacier, from Eridanus,
//              with a time
//   turnaround out of Glacier to the end of its highway, round the turnaround, back the other way
//   walls      steered into a highway's wall at 3,000 mph: pushed back onto the road, no health lost,
//              no crash
//   crash      a crash puts you back at the last city's terminal, on its road
//   jumps      every launch spur at 4,000 mph: off its lip (airborne), caught by its deck two miles on
//              and 1,500 ft up, on along the deck and back down onto the highway; at 3,000 mph still
//              caught; at 2,500 mph under the deck's lip: turned down, onto the open ground (free)
//   edges      angled at a highway's edge and left alone, the craft drifts up its ramp and is turned
//              back before the wall
//   ground     on the open ground the roads' walls hold you off from outside; an on-ramp's open
//              start takes you in (on its road), and from it (rolling at 1,500 mph: from a standstill
//              on SPEEDCRAFT this autopilot can't get going) the autopilot gets you to the city
// Prints NETWORK OK.
// Usage: node tools/network_test.js [sim-core.js]
'use strict';
const NR = require('./net_route.js');

const simPath = process.argv[2] || 'sim-core.js';
const PS = NR.load(simPath);
const { DT, SUB, MPH } = NR;
const ASK = [undefined, 'speed', 'starfighter'];
let ok = true;
function check(msg, cond) { console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); ok = ok && !!cond; }

const sim = PS.makeSim({ track: 'network', handling: 'speed' });
const { S, T } = sim;
check(`build: kind ${T.kind}, ${T.roads ? T.roads.length : 0} roads, ${T.roads ? T.roads.reduce((a, R) => a + R.N, 0) : 0} samples, ${T.junctions ? T.junctions.length : 0} junctions, ${T.cities ? T.cities.length : 0} cities`,
  T.kind === 'network' && T.roads.length === 72 && T.junctions.length === 119 && T.cities.length === 5);
if (T.kind !== 'network') { console.log('NETWORK FAIL'); process.exit(1); }

// zones: the child's centreline inside the parent's corridor (plus its own half width) through the zone
let worstZone = 0;
for (const J of T.junctions) {
  const P = T.roads[J.a], C = T.roads[J.b];
  for (let i = J.b0; i <= J.b1; i += 3) {
    const n = sim.nearestOn(J.a, C.pts[i].x, C.pts[i].y, NR.across(J, false, i), 40);
    worstZone = Math.max(worstZone, Math.abs(n.lat) - (P.pts[n.i].w + C.pts[i].w) / 2);
  }
}
check(`build: every zone inside its parent (worst ${worstZone.toFixed(0)} m outside the joined corridors; the zone's margin allows 300)`, worstZone < 300);

const city = (name) => T.cities.findIndex((c) => c.name === name);
const road = (name) => T.roads.findIndex((R) => R.name === name);

// Fly a route; returns the log of road changes and the events.
function fly(from, goals, maxT, over) {
  const s = PS.makeSim(Object.assign({ track: 'network', handling: 'speed' }, over || {}));
  if (from.city !== undefined) s.respawn(from.city);
  else {   // a road start, rolling at from.mph
    s.respawnOn(from.road, from.i, from.dir || 1);
    const a = s.T.roads[from.road].pts[from.i], d = from.dir || 1;
    for (const b of s.S.bodies) { b.vx = (from.mph || 0) / MPH * a.tx * d; b.vy = (from.mph || 0) / MPH * a.ty * d; }
  }
  const c0 = from.city !== undefined ? s.T.cities[from.city] : null;
  const start = c0 ? { road: c0.road, i: c0.i, dir: from.dir || 0 } : from;
  const legs = NR.find(s.T, start, goals), last = legs[legs.length - 1];
  last.i1 = Math.max(0, Math.min(s.T.roads[last.road].N - 1, last.i1 + last.dir * 120));   // on past the goal (a terminal is a line to cross)
  const route = NR.points(s.T, legs), vplan = NR.plan(route);
  if (route.pts[1] && from.city !== undefined) {   // face the way the route leaves
    const d = route.pts[1].i - route.pts[0].i;
    s.respawnOn(c0.road, c0.i, d >= 0 ? 1 : -1);
  }
  const pilot = NR.makePilot(s.S, route, vplan);
  const changes = [], events = [];
  let prev = s.S.bodies.map((b) => [b.path, b.hint]), top = 0, scrapes = 0, f = 0;
  for (; f * SUB * DT < maxT; f++) {
    const u = pilot();
    if (!u) break;
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true, handling: ASK[u[4]] };
    for (let k = 0; k < SUB; k++) {
      s.step(inp, DT);
      top = Math.max(top, Math.hypot(s.S.pod.vx, s.S.pod.vy));
      s.S.bodies.forEach((b, bi) => {
        if (b.path !== prev[bi][0]) changes.push({ f, bi, from: prev[bi], to: [b.path, b.hint] });
        prev[bi] = [b.path, b.hint];
      });
      while (s.S.events.length) {
        const e = s.S.events.shift();
        if (e.type === 'scrape' || e.type === 'hit') scrapes++;
        else events.push(Object.assign({ f }, e));
      }
    }
    if (events.some((e) => e.type === 'arrive') && goals.length === 1) break;
  }
  return { s, changes, events, top, scrapes, frames: f, route };
}

// A change of road is legal only inside a zone joining the two roads.
function legal(changes) {
  for (const c of changes) {
    const [p, h] = c.from, q = c.to[0];
    const J = T.junctions.find((j) => (j.a === p && j.b === q && h >= j.a0 - 2 && h <= j.a1 + 2) || (j.b === p && j.a === q && h >= j.b0 - 2 && h <= j.b1 + 2));
    if (!J) return `${T.roads[p].name}:${h} -> ${T.roads[q].name}`;
  }
  return null;
}

// strangers: E2 through its crossing with N2 at 3,000 mph
{
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const E2 = road('E2'), R = s.T.roads[E2];
  let ic = 0, bd = Infinity;
  R.pts.forEach((p, i) => { const d = Math.hypot(p.x - 300000, p.y - 300000); if (d < bd) { bd = d; ic = i; } });
  s.respawnOn(E2, ic - 200, 1);
  for (const b of s.S.bodies) { b.vx = 3000 / MPH * R.pts[ic - 200].tx; b.vy = 3000 / MPH * R.pts[ic - 200].ty; }
  let left = false, scr = 0;
  for (let k = 0; k < 6 * 480; k++) {
    s.step({ thrL: 0.6, thrR: 0.6, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    if (s.S.bodies.some((b) => b.path !== E2)) left = true;
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type === 'scrape' || e.type === 'hit') scr++; }
  }
  check(`strangers: through E2's crossing with N2 (sample ${ic}, ${(s.S.pod.hint - ic) * 24 / 1000 | 0} km past it): on E2 throughout (${!left}), ${scr} wall contacts`, !left && scr === 0 && s.S.pod.hint > ic + 100);
}

// drive: Eridanus -> Glacier
{
  const r = fly({ city: city('ERIDANUS') }, [{ road: T.cities[city('GLACIER')].road, i: T.cities[city('GLACIER')].i }], 900);
  const arr = r.events.filter((e) => e.type === 'arrive');
  const bad = legal(r.changes);
  const roadsSeen = [...new Set(r.changes.filter((c) => c.bi === 2).map((c) => T.roads[c.to[0]].name))];
  check(`drive: Eridanus -> Glacier over ${roadsSeen.join(' > ')}, top ${(r.top * MPH).toFixed(0)} mph, ${r.scrapes} wall contacts; road changes all in junction zones (${bad || 'yes'})`,
    !bad && roadsSeen.length >= 3);
  const a = arr[0];
  check(`drive: arrived ${a ? `${T.cities[a.city].name} from ${T.cities[a.from].name} in ${a.t.toFixed(1)} s` : 'never'}`,
    a && a.city === city('GLACIER') && a.from === city('ERIDANUS') && a.t > 60 && arr.length === 1);
  check(`drive: Glacier found (${r.s.S.net && [...r.s.S.net.found].map((k) => T.cities[k].name).join(', ')}), the last city now Glacier`,
    r.s.S.net && r.s.S.net.found.has(city('GLACIER')) && r.s.S.net.from === city('GLACIER'));
}

// turnaround: out of Glacier to E3's east end, round, back west along E3
{
  const tn = road('TE3+'), TR = T.roads[tn];
  const r = fly({ city: city('GLACIER') }, [{ road: tn, i: TR.N >> 1 }, { road: road('E3'), i: T.roads[road('E3')].N - 3000 }], 900, { startCity: city('GLACIER') });
  const onTurn = r.changes.some((c) => c.bi === 2 && c.to[0] === tn);
  const P = r.s.S.pod, E3 = T.roads[road('E3')], back = P.path === road('E3') && (P.vx * E3.pts[P.hint].tx + P.vy * E3.pts[P.hint].ty) < 0;
  check(`turnaround: round ${TR.name} (${onTurn}) and back west on E3 (${back}), ${r.scrapes} wall contacts, changes legal (${legal(r.changes) || 'yes'})`,
    onTurn && back && !legal(r.changes));
}

// walls: into E1's wall at 3,000 mph
{
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const E1 = road('E1'), R = s.T.roads[E1], i = 2000, p = R.pts[i];
  s.respawnOn(E1, i, 1);
  const a = Math.atan2(p.ty, p.tx) + 0.08;   // 4.6 deg toward the left wall
  for (const b of s.S.bodies) { b.vx = 3000 / MPH * Math.cos(a); b.vy = 3000 / MPH * Math.sin(a); }
  let scr = 0;
  for (let k = 0; k < 5 * 480; k++) {
    s.step({ thrL: 0.5, thrR: 0.5, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type === 'scrape' || e.type === 'hit') scr++; }
  }
  const n = s.nearestOn(s.S.pod.path, s.S.pod.x, s.S.pod.y, s.S.pod.hint, 40);
  check(`walls: ${scr} contacts at 3,000 mph, health ${s.S.pod.health.toFixed(2)}, crash ${s.S.crashT.toFixed(2)} s, pod ${Math.abs(n.lat).toFixed(0)} m off E1's centre (half width 200)`,
    scr > 0 && s.S.pod.health === 1 && s.S.crashT <= 0 && Math.abs(n.lat) < 200);
}

// crash: back at the last city's terminal
{
  const s = PS.makeSim({ track: 'network', handling: 'speed', startCity: city('MESA') });
  s.respawnOn(road('E1'), 3000, 1);
  s.S.crashT = 0.01;
  for (let k = 0; k < 10; k++) s.step({ thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
  const c = s.T.cities[city('MESA')], P = s.S.pod, q = s.T.roads[c.road].pts[c.i];
  check(`crash: back at ${s.T.cities[s.S.net.from].name}'s terminal (${Math.hypot(P.x - q.x, P.y - q.y).toFixed(1)} m off it, on ${s.T.roads[P.path].name})`,
    P.path === c.road && Math.hypot(P.x - q.x, P.y - q.y) < 1);
}

// traffic: the sims see it as moving forcefield obstacles (S.obstacles, advanced each step)
{
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const E2 = road('E2'), R = s.T.roads[E2], i = 6000, p = R.pts[i];
  s.respawnOn(E2, i, 1);
  const v = 2000 / MPH;
  for (const b of s.S.bodies) { b.vx = v * p.tx; b.vy = v * p.ty; }
  // slower traffic 600 m ahead, 1.5 m to the left of the pod's line (a glancing catch-up at 800 mph)
  s.S.obstacles = [{ id: 7, x: p.x + p.tx * 600 + p.nx * 1.5, y: p.y + p.ty * 600 + p.ny * 1.5, vx: 1200 / MPH * p.tx, vy: 1200 / MPH * p.ty, r: 3 }];
  const ev = [];
  for (let k = 0; k < 4 * 480; k++) {
    s.step({ thrL: 0.5, thrR: 0.5, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (s.S.events.length) ev.push(s.S.events.shift());
  }
  const bumps = ev.filter((e) => e.type === 'bump'), o = s.S.obstacles[0];
  const ahead = (o.x - p.x) * p.tx + (o.y - p.y) * p.ty;
  check(`traffic: a glancing catch-up on slower traffic: ${bumps.length} bump(s) (closing ${bumps[0] ? (bumps[0].v * MPH).toFixed(0) : '-'} mph), health ${s.S.pod.health}, no crash (${s.S.crashT <= 0}); the obstacle moved on with its speed (${(ahead / 1000).toFixed(1)} km down the road)`,
    bumps.length >= 1 && s.S.pod.health === 1 && s.S.crashT <= 0 && !ev.some((e) => e.type === 'smash') && Math.abs(ahead - (600 + 4 * 1200 / MPH)) < 1);
  // head-on: a 3,000 mph closing speed is the catastrophic hit
  const t = PS.makeSim({ track: 'network', handling: 'speed' });
  t.respawnOn(E2, i, 1);
  for (const b of t.S.bodies) { b.vx = v * p.tx; b.vy = v * p.ty; }
  t.S.obstacles = [{ id: 9, x: p.x + p.tx * 900, y: p.y + p.ty * 900, vx: -1000 / MPH * p.tx, vy: -1000 / MPH * p.ty, r: 3 }];
  const ev2 = [];
  for (let k = 0; k < 3 * 480; k++) {
    t.step({ thrL: 0.5, thrR: 0.5, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (t.S.events.length) ev2.push(t.S.events.shift());
  }
  const sm = ev2.find((e) => e.type === 'smash');
  check(`traffic: head-on at a 3,000 mph closing speed: ${sm ? `a smash at ${(sm.v * MPH).toFixed(0)} mph` : 'no smash'}, then back at the last city (${t.S.pod.path === t.T.cities[t.S.net.from].road})`,
    !!sm && t.S.pod.path === t.T.cities[t.S.net.from].road);
}

// jumps: on launch spur k, 300 samples (7.2 km) short of its lip at `mph`, the levers at `lev`,
// for `secs`: the events, the pod's road at the end, free or not, the highest it got
function jump(k, mph, lev, secs) {
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const [l] = s.T.jumps[k], L = s.T.roads[l];
  s.respawnOn(l, L.N - 1 - 300, 1);
  const a = L.pts[L.N - 1 - 300];
  for (const b of s.S.bodies) { b.vx = mph / MPH * a.tx; b.vy = mph / MPH * a.ty; }
  const ev = [];
  let top = 0, crash = false;
  for (let f = 0; f < secs / DT; f++) {
    s.step({ thrL: lev, thrR: lev, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    top = Math.max(top, s.S.pod.z);
    crash = crash || s.S.crashT > 0;
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type !== 'scrape' && e.type !== 'hit') ev.push(Object.assign({ t: f * DT }, e)); }
  }
  return { s, ev, top, crash, road: s.T.roads[s.S.pod.path].name, offRoad: s.S.pod.offRoad };
}
for (let k = 0; k < T.jumps.length; k++) {
  const [l, c] = T.jumps[k], L = T.roads[l], C = T.roads[c];
  const r = jump(k, 4000, 0.87, 40);
  const air = r.ev.find((e) => e.type === 'airborne'), cat = r.ev.find((e) => e.type === 'catch');
  const home = r.s.T.junctions.some((J) => (J.a === c || J.b === c)) && r.road !== C.name && r.road !== L.name;
  check(`jumps: ${L.name} at 4,000 mph: off the lip at ${air ? (air.v * MPH).toFixed(0) : '-'} mph, ${air ? air.vz.toFixed(0) : '-'} m/s up; caught by ${C.name} ${cat ? (cat.t - air.t).toFixed(2) + ' s later, ' + cat.dz.toFixed(1) + ' m over it closing ' + cat.v.toFixed(0) + ' m/s' : '(never)'}; up to ${r.top.toFixed(0)} m; ${r.road} after 40 s, crash ${r.crash}`,
    air && air.lip && cat && cat.road === c && cat.t - air.t < 2.5 && home && !r.crash && !r.offRoad);
}
{
  const r = jump(0, 3000, 0.5, 12), cat = r.ev.find((e) => e.type === 'catch');
  check(`jumps: at 3,000 mph still caught (${cat ? cat.dz.toFixed(1) + ' m over the deck' : 'missed'})`, !!cat && !r.crash);
  const m = jump(0, 2500, 0.3, 30), air = m.ev.find((e) => e.type === 'airborne');
  const cat2 = m.ev.find((e) => e.type === 'catch'), gr = m.ev.find((e) => e.type === 'ground');
  check(`jumps: at 2,500 mph off the lip (${!!air}), never caught (${!cat2}), down on the open ground ${gr ? (gr.t - air.t).toFixed(1) + ' s later' : '(not yet)'}; free ${m.offRoad}, crash ${m.crash}`,
    air && !cat2 && gr && m.offRoad && !m.crash);
}
// the open ground: free, steered at a highway's side at 400 mph (held off from outside); then
// straight into Eridanus' on-ramp's open start (on it), and on to the city by the autopilot
{
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const E2 = road('E2'), H = s.T.roads[E2];
  const i = 7000, p = H.pts[i];
  s.respawnOn(E2, i, 1);
  // out on the open ground 600 m off the highway's right side, heading in at 25 deg (the engines
  // 25 m ahead of the pod, 3 m either side)
  const ang = 25 * Math.PI / 180, dx = p.tx * Math.cos(ang) - p.ty * Math.sin(ang), dy = p.tx * Math.sin(ang) + p.ty * Math.cos(ang);
  const px0 = p.x - p.nx * 600, py0 = p.y - p.ny * 600, th = Math.atan2(dy, dx);
  for (const [b, side] of [[s.S.eL, 1], [s.S.eR, -1], [s.S.pod, 0]]) {
    const fwd = side === 0 ? 0 : 25;
    b.x = px0 + dx * fwd - dy * side * 3; b.y = py0 + dy * fwd + dx * side * 3;
    b.th = th; b.w = 0; b.offRoad = true; b.lock = false; b.z = s.P.rideH; b.vz = 0;
    b.vx = 400 / MPH * dx; b.vy = 400 / MPH * dy;
  }
  let inside = false, caught = false;
  for (let f = 0; f < 6 / DT; f++) {
    s.step({ thrL: 0.2, thrR: 0.2, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    const n = s.nearestOn(E2, s.S.pod.x, s.S.pod.y, i, 400);
    if (Math.abs(n.lat) < n.w / 2 - 2) inside = true;
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type === 'onroad') caught = true; }
  }
  check(`ground: driven at E2's side from the open ground: held off from outside (never inside: ${!inside}), still free (${s.S.pod.offRoad})`, !inside && !caught && s.S.pod.offRoad);
  // the on-ramp: 1 km short of its start, on its line, at 400 mph (Glacier's: the sim's last city is
  // Eridanus, so reaching Glacier is an arrival)
  const [ci, orr] = s.T.onramps[2], O = s.T.roads[orr], o = O.pts[0];
  for (const [b, side] of [[s.S.eL, 1], [s.S.eR, -1], [s.S.pod, 0]]) {
    const fwd = side === 0 ? -1000 : -1000 + 25;
    b.x = o.x + o.tx * fwd + o.nx * side * 3; b.y = o.y + o.ty * fwd + o.ny * side * 3;   // (o.n: its left)
    b.th = Math.atan2(o.ty, o.tx); b.w = 0; b.offRoad = true; b.lock = false; b.z = s.P.rideH; b.vz = 0;
    b.vx = 400 / MPH * o.tx; b.vy = 400 / MPH * o.ty;
  }
  let on = null;
  for (let f = 0; f < 6 / DT && !on; f++) {
    s.step({ thrL: 0.2, thrR: 0.2, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type === 'onroad') on = e; }
  }
  check(`ground: into ${O.name}'s open start from the open ground: on it (${on ? s.T.roads[on.road].name : 'never'})`, on && on.road === orr && !s.S.pod.offRoad);
  const r = fly({ road: orr, i: 5, dir: 1, mph: 1500 }, [{ road: s.T.cities[ci].road, i: s.T.cities[ci].i }], 400);
  const arr = r.events.find((e) => e.type === 'arrive');
  const bad = legal(r.changes);   // (null: every change inside a zone joining the two)
  check(`ground: from ${O.name} the autopilot gets to ${s.T.cities[ci].name} (${arr ? 'in ' + arr.t.toFixed(0) + ' s' : 'never'}), road changes legal (${bad || 'yes'})`, !!arr && !bad);
}
// the edges ramp up (Luke: "make the walls ramp up on the sides rather than a hard stop? Let the craft
// drift a bit"): on E2 at speed, the craft angled at the left edge and left alone (levers even): it
// drifts up the ramp and is turned back before the wall (no contact), back over the flat
function drift(mph, deg) {
  const s = PS.makeSim({ track: 'network', handling: 'speed' });
  const E2 = road('E2'), i = 6000, p = s.T.roads[E2].pts[i];
  s.respawnOn(E2, i, 1);
  const a = deg * Math.PI / 180, dx = p.tx * Math.cos(a) - p.ty * Math.sin(a), dy = p.tx * Math.sin(a) + p.ty * Math.cos(a);
  for (const b of s.S.bodies) { b.vx = mph / MPH * dx; b.vy = mph / MPH * dy; b.th = Math.atan2(dy, dx); }
  let walls = 0, top = 0, last = 0;
  for (let f = 0; f < 12 / DT; f++) {
    s.step({ thrL: 0.6, thrR: 0.6, brkL: 0, brkR: 0, repair: false, reignite: true }, DT);
    const n = s.nearestOn(E2, s.S.pod.x, s.S.pod.y, s.S.pod.hint, 40);
    top = Math.max(top, n.lat); last = n.lat;
    while (s.S.events.length) { const e = s.S.events.shift(); if (e.type === 'scrape' || e.type === 'hit') walls++; }
  }
  return { walls, top, last };
}
for (const [mph, deg] of [[4000, 2], [2500, 3], [1500, 3], [800, 3]]) {
  const r = drift(mph, deg);
  check(`edges: drifting ${deg} deg at the left edge at ${mph} mph: up the ramp to ${r.top.toFixed(0)} m off the centre (the wall at 200, the ramp from 140), ${r.walls} wall contacts, ${r.last.toFixed(0)} m off after 12 s`,
    r.top > 140 && r.top < 200 && r.walls === 0 && r.last < r.top - 20);
}

console.log(ok ? 'NETWORK OK' : 'NETWORK FAIL');
process.exit(ok ? 0 : 1);
