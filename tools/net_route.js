// Routes on the Network (track "network": tools/design_network.py) and an autopilot that flies
// them, for tools/network_test.js and tools/record_network.js.
//   find(T, from, goals)  the shortest drive from `from` ({road, i, dir}: dir +1 up the samples,
//                         -1 down; 0 either) through each goal ({road, i}) in turn, as legs
//                         [{road, i0, i1, dir}], switching roads only inside junction zones and only
//                         the way a road can be entered (a ramp's start going up it, its end going down)
//   points(T, legs)       the legs as route samples {x, y, tx, ty, len, mode, path, i} (tangents the
//                         way you drive)
//   plan(route)           target speed per route sample (record_job.js's: each mode's grip and
//                         turn-rate limits, braking distance)
//   makePilot(S, route, vplan)  levers and the handling ask per frame, following the route
'use strict';
const fs = require('fs');

const DT = 1 / 480, SUB = 8, G = 9.81, MPH = 2.236936;
const SF = { omega: 0.95, aLat: 38 * G, top: 1150 / MPH };
const SP = { aLat: 8.5 * G, top: 4300 / MPH };   // a margin under record_job.js's 10 g: the bypasses' 7 km arcs, ridden clean
const SWITCH_V = 1200 / MPH;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;

function load(simPath) {
  global.window = {};
  eval(fs.readFileSync(simPath, 'utf8'));
  return window.PhaethonSim;
}

// The index on the other road a junction maps road index i to (the sims' linear map).
function across(J, onA, i) {
  const [f0, f1, t0, t1] = onA ? [J.a0, J.a1, J.b0, J.b1] : [J.b0, J.b1, J.a0, J.a1];
  const u = f1 > f0 ? (i - f0) / (f1 - f0) : 0;
  return Math.round(J.sense > 0 ? t0 + u * (t1 - t0) : t1 - u * (t1 - t0));
}

// Dijkstra over states (road, i, dir). From a state you either drive on to the goal (if it's on
// this road, ahead) or to the middle of a junction zone ahead and over onto the other road.
function leg(T, from, goal) {
  const key = (r, i, d) => `${r}:${i}:${d}`;
  const dist = new Map(), prev = new Map(), heap = [];
  const push = (r, i, d, c, p) => {
    const k = key(r, i, d);
    if (dist.has(k) && dist.get(k) <= c) return;
    dist.set(k, c); prev.set(k, p); heap.push([c, r, i, d]);
  };
  for (const d of from.dir ? [from.dir] : [1, -1]) push(from.road, from.i, d, 0, null);
  let best = null;
  while (heap.length) {
    let m = 0;
    for (let k = 1; k < heap.length; k++) if (heap[k][0] < heap[m][0]) m = k;
    const [c, r, i, d] = heap.splice(m, 1)[0];
    if (c > dist.get(key(r, i, d))) continue;
    if (best && c >= best.c) break;
    if (r === goal.road && (goal.i - i) * d >= 0) {
      const cg = c + Math.abs(goal.i - i);
      if (!best || cg < best.c) best = { c: cg, r, i, d };
    }
    for (const k of T.roads[r].jx) {
      const J = T.junctions[k], onA = J.a === r;
      // over where the two coincide: the joining road's end (b) and the parent's sample there
      const C = T.roads[J.b], cb = J.b0 === 0 ? 0 : J.b1 === C.N - 1 ? J.b1 : Math.round((J.b0 + J.b1) / 2);
      const ca = across(J, false, cb), zc = onA ? ca : cb;
      if ((zc - i) * d <= 0) continue;   // behind
      const q = onA ? J.b : J.a, iq = onA ? cb : ca, dq = d * J.sense;
      const Q = T.roads[q], qz0 = onA ? J.b0 : J.a0, qz1 = onA ? J.b1 : J.a1;
      if (qz0 === 0 && dq < 0) continue;            // a road's start: only going up it
      if (qz1 === Q.N - 1 && dq > 0) continue;      // its end: only going down it
      push(q, iq, dq, c + Math.abs(zc - i), { r, i, d, at: zc });
    }
  }
  if (!best) throw new Error(`no route from ${T.roads[from.road].name}:${from.i} to ${T.roads[goal.road].name}:${goal.i}`);
  const legs = [{ road: best.r, i0: best.i, i1: goal.i, dir: best.d }];
  let k = key(best.r, best.i, best.d);
  while (prev.get(k)) {
    const p = prev.get(k);
    legs.unshift({ road: p.r, i0: p.i, i1: p.at, dir: p.d });
    k = key(p.r, p.i, p.d);
  }
  return legs;
}

function find(T, from, goals) {
  let at = from;
  const legs = [];
  for (const g of goals) {
    const L = leg(T, at, g);
    legs.push(...L);
    const last = L[L.length - 1];
    at = { road: last.road, i: last.i1, dir: last.dir };
  }
  return legs;
}

function points(T, legs) {
  const out = [];
  for (const L of legs) {
    const R = T.roads[L.road];
    for (let i = L.i0; L.dir > 0 ? i <= L.i1 : i >= L.i1; i += L.dir) {
      const p = R.pts[i];
      out.push({ x: p.x, y: p.y, tx: p.tx * L.dir, ty: p.ty * L.dir, len: p.len, mode: p.mode, path: L.road, i });
    }
  }
  return { pts: out };
}

function plan(route) {
  const R = route.pts, N = R.length, kap = new Array(N).fill(0), v = new Array(N);
  for (let i = 0; i + 1 < N; i++) kap[i] = Math.abs(wrap(Math.atan2(R[i + 1].ty, R[i + 1].tx) - Math.atan2(R[i].ty, R[i].tx))) / R[i].len;
  for (let i = 0; i < N; i++) {
    let k = 0;
    for (let j = -4; j <= 4; j++) k = Math.max(k, kap[Math.min(N - 1, Math.max(0, i + j))]);
    if (R[i].mode === 'sf') v[i] = Math.min(SWITCH_V, k < 1e-6 ? SF.top : Math.min(SF.top, SF.omega / k, Math.sqrt(SF.aLat / k)));
    else v[i] = k < 1e-7 ? SP.top : Math.min(SP.top, Math.sqrt(SP.aLat / k));
    if (R[i].cap !== undefined) v[i] = Math.min(v[i], R[i].cap);
  }
  const decel = (s) => (5 + 9 * Math.min(s / 447, 1)) * G;
  for (let pass = 0; pass < 3; pass++) {
    for (let i = N - 2; i >= 0; i--) {
      const nx = v[i + 1];
      v[i] = Math.min(v[i], Math.sqrt(nx * nx + 2 * decel(nx) * R[i].len));
    }
  }
  return v;
}

// record_job.js's pilot (no pad), its look-ahead in metres over the route's spacing.
function makePilot(S, route, vplan) {
  const R = route.pts, N = R.length, sp = R.length > 1 ? Math.max(1, R[0].len) : 24;
  const st = { i: 0 };
  return function pilot() {
    const v = Math.hypot(S.pod.vx, S.pod.vy);
    let bd = Infinity, bi = st.i;
    for (let k = Math.max(0, st.i - 10); k < Math.min(N, st.i + 60); k++) {
      const d = (R[k].x - S.pod.x) ** 2 + (R[k].y - S.pod.y) ** 2;
      if (d < bd) { bd = d; bi = k; }
    }
    st.i = bi;
    const i = bi;
    if (i >= N - 2) return null;   // the route's end
    const lead = Math.ceil((v * 0.35) / sp);
    const target = vplan[Math.min(N - 1, i + lead)];
    const aim = R[Math.min(N - 1, i + Math.round((60 + v * (S.P.handling === 'speed' ? 0.5 : 0.36)) / sp))];
    const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
    const course = S.P.handling === 'speed' ? Math.atan2(S.pod.vy, S.pod.vx) : (S.pairTh ?? 0);
    const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - course);
    const k = Math.max(-1, Math.min(1, err * (S.P.handling === 'speed' ? 3 : 5)));
    const top = 0.87;
    let base = v < target - 4 ? top : Math.max(0, Math.min(top, top * (target / Math.max(v, 1)) - 0.1));
    let brk = Math.max(0, Math.min(1, (v - target - 6) / 25));
    if (S.P.handling === 'speed' && v - target < 50) {
      const keep = Math.min(top, 0.25 + 0.75 * Math.abs(k));
      if (base < keep) { brk = Math.max(brk, Math.min(1, (v - target + 4) / 40)); base = keep; }
      brk = Math.min(brk, 1.0 - 0.8 * Math.min(1, Math.abs(k) / 0.4));
    } else if (brk > 0) base = 0;
    const ahead = vplan[Math.min(N - 1, i + Math.ceil(v * 2 / sp))];
    const h = R[i].mode === 'sf' || ahead <= SWITCH_V * 1.05 ? 2 : 1;
    const kb = 0.6, gb = 2;
    return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)),
      Math.max(brk, k > kb ? (k - kb) * gb : 0), Math.max(brk, k < -kb ? (-k - kb) * gb : 0)].map((x) => r4(Math.min(1, x))).concat([h]);
  };
}

module.exports = { load, find, points, plan, makePilot, across, DT, SUB, MPH, wrap, r4 };
