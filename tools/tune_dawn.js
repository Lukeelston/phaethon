// Tunes the emergency run's dawn: the front's direction (dawnDir, 1 deg steps) and when it passes
// the start line's point (dawnT0, 0.1 s steps), against tools/record_job.js's autopilot runs:
// Every margin is for a pilot RJ.ALLOWANCE (15 s) slower than the autopilot (a human; the autopilot
// corners at 38 g): the autopilot's own margins are that much bigger.
//   open     makes it home, margin 3-10 s at its deadline: back under cover after the open loop
//            (the start town's receiving ramp)
//   shade    makes it, margin >= 2 s as it goes under the canopy; of the settings that meet the
//            rest, the one with the tightest shade margin (the spec: both routes stay tight)
//   late     (the allowance + 6 s longer on the pad) caught by the dawn, with a second to spare
//   out-leg  the lake town isn't lit before the drop: not for OUT_SLACK s after it, so a pilot a
//            little slower out than the autopilot isn't caught leaving the lake town
//   behind   on the run home the dawn is behind you, catching up (the spec): it reaches the lake
//            town before the start town, and the open run's tightest moment is its deadline (no
//            exposed moment more than CATCH s tighter than the margin there)
// The dawn changes nothing in the physics until it catches you, so each route is flown once with
// the dawn off and the conditions are solved from its track. Every direction is tried; for each,
// the latest dawnT0 that still catches the late run (the most forgiving for a human pilot) is
// taken, and of those that meet everything the tightest shade margin wins (ties: nearest the
// pad-to-mouth bearing).
// Then the setting is flown for real (record_job.js's run) to confirm it. Prints, in
// tools/design_eridanus.py's format (sync_eridanus.py writes it into both sims):
//   dawn: dir N deg, t0 S s: open +x.x s, shade +y.y s, late caught at z.z s
//   DAWN_DIR_DEG = N
//   DAWN_T0 = S
// Usage: node tools/tune_dawn.js [sim-core.js]
'use strict';
const RJ = require('./record_job.js');
const PS = RJ.load(process.argv[2] || 'sim-core.js');
const S0 = PS.makeSim({ track: 'eridanus', job: 'emergency' });
const T = S0.T, SPD = S0.P.dawnSpeed, B = T.branches[0];
const OFF = { dawnT0: 1e9 };
const A = RJ.ALLOWANCE;   // the human allowance: every margin below is for a pilot this much slower than the autopilot
const OUT_SLACK = 15 + A, CATCH = 1.0;

const fly = (kind) => {
  const r = RJ.run(PS, kind, OFF, null, true);
  if (!r.end || r.job.stage !== 'done') { console.log(`${kind}: the autopilot didn't make it home with the dawn off (${r.job.stage})`); process.exit(1); }
  return r;
};
const runs = { open: fly('open'), shade: fly('shade'), late: fly('late') };
const firstT = (tr, pred) => { for (const s of tr) if (pred(s)) return s; return null; };
const drop = firstT(runs.open.track, (s) => s[4] === 'drop');
// each route's deadline: the first step back under cover after the open loop on the way home
const deadline = (tr) => { let out = false; for (const s of tr) { if (s[4] !== 'home') continue; if (s[3] === 0) out = true; else if (out) return s; } return null; };
const ramp = deadline(runs.open.track);
const doneOpen = ramp[0];
const canopy = deadline(runs.shade.track);
const mouth = T.pts[T.mouth], pad = T.pts[T.pad];
console.log(`flown with the dawn off: open under the receiving ramp at ${doneOpen.toFixed(2)} s (home at ${runs.open.job.t.toFixed(2)}), shade under the canopy at ${canopy[0].toFixed(2)} s ` +
  `(home at ${runs.shade.job.t.toFixed(2)}), late home at ${runs.late.job.t.toFixed(2)}; the drop at ${drop[0].toFixed(2)} s`);

// t0 that the front must pass the start line after for a run never to be caught in the open:
// caught at a step iff t >= t0 + (p . u) / speed, i.e. t0 <= t - (p . u) / speed
const exposedMax = (tr, u, until) => {
  let a = -Infinity;
  for (const s of tr) {
    if (until !== undefined && s[0] > until) break;
    if (s[3] === 0 && s[4] !== 'done') a = Math.max(a, s[0] - (s[1] * u[0] + s[2] * u[1]) / SPD);
  }
  return a;
};
const bearing = Math.round(Math.atan2(mouth.y - pad.y, mouth.x - pad.x) * 180 / Math.PI);
const order = [0];
for (let k = 1; k <= 180; k++) order.push(k, -k);
let pick = null;
for (const off of order) {
  const deg = bearing + off, a = deg * Math.PI / 180, u = [Math.cos(a), Math.sin(a)];
  const dot = (p) => (p.x * u[0] + p.y * u[1]) / SPD;
  const cOpen = (ramp[1] * u[0] + ramp[2] * u[1]) / SPD - doneOpen, cShade = (canopy[1] * u[0] + canopy[2] * u[1]) / SPD - canopy[0];
  if (dot(pad) >= dot(mouth)) continue;   // the dawn must come up behind the run home
  const aOpen = exposedMax(runs.open.track, u);
  if (-aOpen < cOpen - CATCH) continue;   // the open run's tightest moment isn't the mouth
  const lo = Math.max(aOpen, exposedMax(runs.shade.track, u, canopy[0]), 3 + A - cOpen, 2 + A - cShade, drop[0] + OUT_SLACK - dot(pad));
  const aLate = exposedMax(runs.late.track, u);
  const hi = Math.min(10 + A - cOpen, aLate - 1.0);
  const t0 = Math.floor(hi * 10) / 10;
  if (t0 > lo + 0.05 && (!pick || t0 + cShade < pick.t0 + pick.cShade - 1e-9)) pick = { deg, t0, u, cOpen, cShade, aLate };
}
if (!pick) { console.log('no dawn setting meets all four'); process.exit(1); }

// fly it for real
const over = { dawnDir: pick.deg * Math.PI / 180, dawnT0: pick.t0 };
const real = { open: RJ.run(PS, 'open', over), shade: RJ.run(PS, 'shade', over), late: RJ.run(PS, 'late', over) };
const o = real.open.job, sh = real.shade.job, la = real.late.job;
const ok = o.stage === 'done' && o.route === 'open' && o.margin >= 3 + A && o.margin <= 10 + A && sh.stage === 'done' && sh.route === 'shade' && sh.margin >= 2 + A &&
  la.stage === 'failed' && la.reason === 'dawn';
console.log(`dawn: dir ${pick.deg} deg, t0 ${pick.t0.toFixed(1)} s: open ${o.margin >= 0 ? '+' : ''}${o.margin.toFixed(1)} s, shade ${sh.margin >= 0 ? '+' : ''}${sh.margin.toFixed(1)} s, ` +
  `late caught at ${la.t.toFixed(1)} s` + (ok ? '' : `  -- FLOWN FOR REAL IT FAILS: open ${o.stage}/${o.reason}, shade ${sh.stage}/${sh.reason}, late ${la.stage}/${la.reason}`));
const lateAt = real.late.sim.S.pod, lateI = lateAt.hint;
console.log(`(the lake town lit at ${(pick.t0 + (pad.x * pick.u[0] + pad.y * pick.u[1]) / SPD).toFixed(1)} s, the drop at ${drop[0].toFixed(1)} s; ` +
  `the open run's tightest moment ${(pick.t0 - exposedMax(runs.open.track, pick.u)).toFixed(1)} s; the late run caught at main sample ${lateI} of ${T.N} (the mouth ${T.mouth}))`);
const norm = ((pick.deg + 180) % 360 + 360) % 360 - 180;   // (-180, 180]
console.log(`DAWN_DIR_DEG = ${norm}\nDAWN_T0 = ${pick.t0.toFixed(1)}`);
process.exit(ok ? 0 : 1);
