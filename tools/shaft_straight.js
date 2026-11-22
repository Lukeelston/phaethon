// The Network's shafts (the vertical turnarounds at the highways' ends) flown hands off, in the JS sim:
// does the craft stay straight? Luke: "Fix vertical turnarounds so the vehicle can enter and exit
// straight with no sideways or spin - right now, going slow makes the vehicle list, going fast makes it
// shift slightly."
// Every shaft, both ways (up its way out, and up its way back: "from the left half of the road you go up
// the rolled side"), at three speeds (STARFIGHTER at the two it can hold), in both handlings, both levers
// always equal (a speed hold, nothing steering), set `--lat` m left of the road's middle just before the
// foot (default 0, 60 and -60): 360 flights. For each, against the road under the pod:
//   creep   how far the pod moves across the road between the feet (m, the most)
//   yaw     the pod's and the engine pair's heading off the road's own direction (deg, the most), and slip,
//           the pod's velocity off it
//   lean    the bank the views draw (view/craft_model.gd's _update_bank and ease_bank at 90 frames a second),
//           deg; --old-view reads the load as the views did before the sims counted the carried turn
//   out     at the far foot the heading off the leg (deg), and how far it then moves across in 600 m
// and the wall contacts. A summary line for each speed and handling, and one for all.
// Usage: node tools/shaft_straight.js [sim-core.js] [--only=47,52] [--lat=0,60,-60] [--speeds=300,900,4000]
//          [--handling=speed,starfighter] [--quiet] [--trace=road:dir:mph:lat:handling] [--old-view]
//          [--limits=creep,yaw,lean,drift]   exits 1, SHAFTS STRAIGHT FAIL, if any flight is over them
//                                            (the build as of 2026-11-22 holds --limits=1,0.03,0.2,0.15)
'use strict';
const NR = require('./net_route.js');
const args = process.argv.slice(2);
const simPath = args.find((a) => !a.startsWith('--')) || 'sim-core.js';
const opt = (k, d) => { const a = args.find((x) => x.startsWith(`--${k}=`)); return a ? a.split('=')[1] : d; };
const PS = NR.load(simPath);
const { MPH } = NR;
const DT = 1 / 480, G = 9.81;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const deg = (a) => a * 180 / Math.PI;
const SPEEDS = opt('speeds', '300,900,4000').split(',').map(Number);
const LATS = opt('lat', '0,60,-60').split(',').map(Number);
const ONLY = opt('only', '') ? opt('only', '').split(',').map(Number) : null;
const TRACE = opt('trace', '');
const HANDLING = opt('handling', 'speed,starfighter').split(',');
const QUIET = args.includes('--quiet');
const SF_TOP = 1000;
// view/craft_model.gd
const BANK = { MAX: null, G: null, TAU: null, TAU_OUT: null, RATE: null, RATE_OUT: null };
{
  const src = require('fs').readFileSync(require('path').join(__dirname, '..', 'godot', 'view', 'craft_model.gd'), 'utf8');
  for (const [k, name] of [['MAX', 'BANK_MAX'], ['G', 'BANK_G'], ['TAU', 'BANK_TAU'], ['TAU_OUT', 'BANK_TAU_OUT'], ['RATE', 'BANK_RATE'], ['RATE_OUT', 'BANK_RATE_OUT']]) {
    const m = src.match(new RegExp(`const ${name}\\s*:?=\\s*([^#\\n]+)`));
    if (!m) throw new Error(`no ${name} in craft_model.gd`);
    BANK[k] = Function('deg_to_rad', 'PI', `return (${m[1].trim()})`)((d) => d * Math.PI / 180, Math.PI);
  }
}
function easeBank(bank, latS, latG, delta) {
  const lettingGo = Math.abs(latG) < Math.abs(latS) || Math.sign(latG) !== Math.sign(latS);
  latS += (latG - latS) * (1 - Math.exp(-delta / (lettingGo ? BANK.TAU_OUT : BANK.TAU)));
  const target = BANK.MAX * Math.tanh(latS / BANK.G);
  const toLevel = bank !== 0 && Math.sign(target - bank) !== Math.sign(bank);
  const rate = (toLevel ? BANK.RATE_OUT : BANK.RATE) * delta;
  return [bank + Math.max(-rate, Math.min(rate, target - bank)), latS];
}

function fly(sh, dir, mph, lat0, handling, trace) {
  const s = PS.makeSim({ track: 'network', handling });
  const { S, T } = s;
  const [r, iUp, iDn] = sh, R = T.roads[r];
  const lead = 200;   // samples of flat leg before the foot, where the road has them (the way back starts at its foot)
  const near = dir > 0 ? iUp : iDn, far = dir > 0 ? iDn : iUp;   // the foot it goes in at, and the one it comes out at
  const i0 = dir > 0 ? Math.max(80, iUp - lead) : Math.min(R.N - 9, iDn + lead);
  s.respawnOn(r, i0, dir);
  const p0 = R.pts[i0], v0 = mph / MPH;
  for (const b of S.bodies) { b.vx = v0 * p0.tx * dir; b.vy = v0 * p0.ty * dir; }
  const out = { creep: 0, creepEnd: 0, yawPod: 0, yawPair: 0, yawOut: 0, driftOut: 0, slip: 0, lean: 0, leanAll: 0, leanOut: 0, w: 0, vmin: Infinity, vmax: 0, scrapes: 0, done: false, t: 0, where: {} };
  // the leg it comes out along: from the far foot, in the direction of the flat samples beyond it (the foot's own chord is the bulb's first, on the way back)
  const A = R.pts[far], B = R.pts[dir > 0 ? far : far - 1], tA = [B.tx * dir, B.ty * dir], nA = [B.nx * dir, B.ny * dir], thA = Math.atan2(tA[1], tA[0]);
  let latRef = null, prevV = null, prevTurn = 0, bank = [0, 0, 0], latS = [0, 0, 0], frame = 0, integ = 0, hint = i0, shifted = lat0 === 0, latFoot = null;
  const all = [S.eL, S.eR, S.pod];
  const maxT = 60 + (Math.abs(iDn - iUp) + 2 * lead) * 24 / Math.max(40, v0 * 0.5);
  const note = (key, val, f) => { if (Math.abs(val) > Math.abs(out[key])) { out[key] = val; out.where[key] = Math.round(f); } };
  for (let k = 0; k < maxT * 480; k++) {
    const Pd = S.pod, v = Math.hypot(Pd.vx, Pd.vy);
    // the speed hold: both levers the same, always (PI on the pod's speed)
    const err = (v0 - v) / Math.max(20, v0);
    integ = Math.max(-1, Math.min(1, integ + err * DT * 0.8));
    const thr = Math.max(0, Math.min(0.87, 0.25 + 4 * err + integ));
    s.step({ thrL: thr, thrR: thr, brkL: 0, brkR: 0, repair: false, reignite: true, handling }, DT);
    while (S.events.length) { const e = S.events.shift(); if (e.type === 'scrape' || e.type === 'hit') out.scrapes++; }
    out.t += DT;
    const n = s.nearestOn(r, Pd.x, Pd.y, hint, 14), a = R.pts[n.i];
    hint = n.i;
    const f = n.i + clamp01(((Pd.x - a.x) * a.tx + (Pd.y - a.y) * a.ty) / a.len);
    // set across the road just before the foot (or just up it, on the way back: there is no flat before that foot)
    if (!shifted && (dir > 0 ? f >= near - 40 : f <= near - 3)) {
      for (const b of S.bodies) { b.x += a.nx * dir * lat0; b.y += a.ny * dir * lat0; }
      shifted = true;
      continue;
    }
    const past = (Pd.x - A.x) * tA[0] + (Pd.y - A.y) * tA[1];   // m beyond the far foot, along the leg
    const between = (dir > 0 ? f >= near - 20 : f <= near - 4) && (dir > 0 ? f < far : f > far);
    if (between && shifted) {
      const lat = n.lat * dir, thRoad = roadTh(a, f - n.i, dir);
      if (latRef === null) latRef = lat;
      const yawPod = deg(wrap(Pd.th - thRoad));
      const yawPair = deg(wrap(Math.atan2(S.eR.x - S.eL.x, -(S.eR.y - S.eL.y)) - thRoad));   // forward is +90 deg from L->R
      const slip = v > 5 ? deg(wrap(Math.atan2(Pd.vy, Pd.vx) - thRoad)) : 0;
      note('creep', lat - latRef, f); note('yawPod', yawPod, f); note('yawPair', yawPair, f); note('slip', slip, f); note('w', deg(Pd.w), f);
      out.vmin = Math.min(out.vmin, v); out.vmax = Math.max(out.vmax, v);
      out.creepEnd = lat - latRef;
    }
    const out_of_it = latRef !== null && !between && past >= 0 && past < 5000;
    if (out_of_it) {
      const lat = (Pd.x - A.x) * nA[0] + (Pd.y - A.y) * nA[1];
      if (latFoot === null) { latFoot = lat; out.yawOut = deg(wrap(Pd.th - thA)); out.leanOut = deg(bank[2]); }
      out.driftOut = lat - latFoot;
    }
    if (shifted && latRef !== null) {
      // the views' bank, a frame every 1/90 s (view/craft_model.gd _update_bank)
      frame += DT;
      if (frame >= 1 / 90 - 1e-9) {
        if (prevV) {
          const turned = NEWVIEW && S.carryTurn !== undefined ? S.carryTurn - prevTurn : 0, ct = Math.cos(turned), st = Math.sin(turned);
          for (let b = 0; b < 3; b++) {
            const B = all[b];
            let latG;
            if (NEWVIEW && S.carryTurn !== undefined) {   // the frame's own carried turn taken out of the velocity it started with
              const ax = (B.vx - (ct * prevV[b][0] - st * prevV[b][1])) / frame, ay = (B.vy - (st * prevV[b][0] + ct * prevV[b][1])) / frame;
              latG = (-Math.sin(B.th) * ax + Math.cos(B.th) * ay) / G;
            } else {
              const ax = (B.vx - prevV[b][0]) / frame, ay = (B.vy - prevV[b][1]) / frame;
              latG = (-Math.sin(B.th) * ax + Math.cos(B.th) * ay) / G;
              if (!B.offRoad && T.roads[B.path].shaft) latG -= T.roads[B.path].pts[B.hint].kap * (B.vx * B.vx + B.vy * B.vy) / G;
            }
            if (Math.abs(latG) > 150) latG = 0;
            latG *= B.grip;
            const e = easeBank(bank[b], latS[b], latG, frame);
            bank[b] = e[0]; latS[b] = e[1];
          }
          if (between) note('lean', deg(bank[2]), f);
          note('leanAll', Math.max(...bank.map((x) => Math.abs(deg(x)))), f);
        }
        prevV = all.map((B) => [B.vx, B.vy]);
        prevTurn = S.carryTurn || 0;
        frame = 0;
      }
      if (trace && k % 48 === 0) {
        console.log(`  t ${out.t.toFixed(1)} f ${f.toFixed(1)} kap ${(a.kap * 1e4).toFixed(2)}e-4 gs ${a.gs.toFixed(2)} v ${(v * MPH).toFixed(0)} thr ${thr.toFixed(2)} lat ${(n.lat * dir).toFixed(2)} yaw ${deg(wrap(Pd.th - roadTh(a, f - n.i, dir))).toFixed(3)} slip ${deg(wrap(Math.atan2(Pd.vy, Pd.vx) - roadTh(a, f - n.i, dir))).toFixed(3)} lean ${deg(bank[2]).toFixed(2)} w ${deg(Pd.w).toFixed(3)} hb ${S.hblend.toFixed(2)} path ${Pd.path}`);
      }
    }
    if (latRef !== null && !between && past >= 600) { out.done = true; break; }
    if (Pd.offRoad) { out.left = `off the road at sample ${Pd.hint} (road ${Pd.path})`; break; }
  }
  return out;
}
const clamp01 = (u) => Math.max(0, Math.min(1, u));
// The road's own direction u of the way along sample a's chord (a chord's direction is the arc's at its middle), the way it is flown.
const roadTh = (a, u, dir) => Math.atan2(a.ty * dir, a.tx * dir) + (u - 0.5) * a.kap * a.len;
const NEWVIEW = !args.includes('--old-view');

const T0 = PS.makeSim({ track: 'network', handling: 'speed' }).T;
let worst = { creep: 0, yaw: 0, lean: 0, slip: 0, yawOut: 0, driftOut: 0 };
const rows = [];
for (const sh of T0.shafts) {
  if (ONLY && !ONLY.includes(sh[0])) continue;
  const name = T0.roads[sh[0]].name;
  for (const dir of [1, -1]) for (const mph of SPEEDS) for (const lat0 of LATS) for (const handling of HANDLING) {
    if (handling === 'starfighter' && mph > SF_TOP) continue;   // (STARFIGHTER tops out near 1,000 mph: its fast pass is the middle one)
    const tr = TRACE === `${sh[0]}:${dir}:${mph}:${lat0}:${handling}`;
    if (TRACE && !tr) continue;
    const o = fly(sh, dir, mph, lat0, handling, tr);
    rows.push({ name, road: sh[0], dir, mph, lat0, handling, o });
    const f1 = (v) => (v >= 0 ? '+' : '') + v.toFixed(Math.abs(v) < 10 ? 2 : 1);
    if (!QUIET) console.log(`${name.padEnd(5)} ${dir > 0 ? 'out ' : 'back'} ${String(mph).padStart(4)} mph lat ${String(lat0).padStart(3)} ${handling.padEnd(11)} | creep ${f1(o.creep).padStart(6)} m | yaw pod ${f1(o.yawPod)} pair ${f1(o.yawPair)} slip ${f1(o.slip)} deg | lean ${f1(o.lean)} deg | out: yaw ${f1(o.yawOut)} deg, drift ${f1(o.driftOut)} m in 600 m | v ${(o.vmin * MPH).toFixed(0)}-${(o.vmax * MPH).toFixed(0)} | ${o.scrapes} contacts | ${o.done ? `${o.t.toFixed(0)} s` : (o.left || 'TIMED OUT')}`);
    if (o.done) {
      worst.creep = Math.max(worst.creep, Math.abs(o.creep)); worst.yaw = Math.max(worst.yaw, Math.abs(o.yawPod), Math.abs(o.yawPair));
      worst.lean = Math.max(worst.lean, Math.abs(o.lean), Math.abs(o.leanAll || 0)); worst.slip = Math.max(worst.slip, Math.abs(o.slip));
      worst.yawOut = Math.max(worst.yawOut, Math.abs(o.yawOut)); worst.driftOut = Math.max(worst.driftOut, Math.abs(o.driftOut));
    }
  }
}
const undone = rows.filter((x) => !x.o.done).length, contacts = rows.reduce((a, x) => a + x.o.scrapes, 0);
for (const mph of SPEEDS) for (const handling of HANDLING) {
  const sel = rows.filter((x) => x.mph === mph && x.handling === handling && x.o.done), mx = (k) => Math.max(0, ...sel.map((x) => Math.abs(x.o[k] || 0)));
  console.log(`  ${String(mph).padStart(4)} mph ${handling.padEnd(11)} (${sel.length} flights): creep ${mx('creep').toFixed(2)} m, yaw ${Math.max(mx('yawPod'), mx('yawPair')).toFixed(2)} deg, lean ${Math.max(mx('lean'), mx('leanAll')).toFixed(2)} deg; out of it yaw ${mx('yawOut').toFixed(3)} deg, drift ${mx('driftOut').toFixed(2)} m in 600 m; ${sel.reduce((a, x) => a + x.o.scrapes, 0)} wall contacts`);
}
console.log(`SHAFTS: ${rows.length} flights, ${undone} not through, ${contacts} wall contacts; worst creep ${worst.creep.toFixed(2)} m, yaw ${worst.yaw.toFixed(2)} deg, slip ${worst.slip.toFixed(2)} deg, lean ${worst.lean.toFixed(2)} deg; out of it yaw ${worst.yawOut.toFixed(3)} deg, drift ${worst.driftOut.toFixed(2)} m in 600 m`);
if (opt('limits', '')) {
  const [cm, ym, lm, dm] = opt('limits', '').split(',').map(Number);
  const ok = undone === 0 && contacts === 0 && worst.creep <= cm && worst.yaw <= ym && worst.lean <= lm && worst.driftOut <= dm;
  console.log(ok ? 'SHAFTS STRAIGHT OK' : 'SHAFTS STRAIGHT FAIL');
  process.exit(ok ? 0 : 1);
}
