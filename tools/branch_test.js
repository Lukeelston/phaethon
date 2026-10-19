// Branch roads (the shade line, a private covered STARFIGHTER line off Eridanus' loop into the
// start town: tools/design_eridanus.py). Scripted drives at the split check the junction rule:
//   locked   outside the job the gate is shut: steering into the branch mouth meets the main wall
//   open     on the job, at 600 mph (r300 at 40 deg holds ~640 mph): every body takes the branch inside the junction zone, flies
//            it end to end, and comes back onto the main road at the join
//   fast     on the job, but at 1,300 mph at the zone's start (then slowed to the open run's
//            speed, as if braking): the gate stays shut for that pass, the main wall holds
//   straight on the job, straight down the main road past the split: never leaves it
//   restart / respawn on the branch: every body back on the main road (path 0) at a checkpoint
// (The job's drives run with the dawn off: the gate is under test here, not the dawn.)
// Prints BRANCH OK. With --dump <file>: the branch's samples and each drive's inputs and
// outcomes, which godot/tests/test_branch.gd replays and must match.
// Usage: node tools/branch_test.js [sim-core.js] [--dump godot/tests/replay/branch_expected.json]
'use strict';
const fs = require('fs');
const args = process.argv.slice(2);
const di = args.indexOf('--dump');
const dumpPath = di >= 0 ? args[di + 1] : null;
const simPath = args.filter((a, i) => a !== '--dump' && i !== di + 1)[0] || 'sim-core.js';
global.window = {};
eval(fs.readFileSync(simPath, 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, SUB = 8, MPH = 2.236936;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const r4 = (v) => Math.round(v * 1e4) / 1e4;
let ok = true;
const out = [];
function check(msg, cond) { out.push(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); ok = ok && !!cond; }

// The line a drive steers along: main samples up to the split, the branch, main from the join.
function routeOf(T, viaBranch) {
  const B = T.branches[0], pts = [];
  if (!viaBranch) { for (let k = -400; k < 900; k++) pts.push(T.pts[(B.from + k + T.N) % T.N]); return pts; }
  for (let k = -400; k < 0; k++) pts.push(T.pts[(B.from + k + T.N) % T.N]);
  for (const p of B.pts) pts.push(p);
  for (let k = 1; k < 400; k++) pts.push(T.pts[(B.join + k) % T.N]);
  return pts;
}

// STARFIGHTER steering at a point ~(60 + 0.36 v) m ahead on the route, holding a set speed.
function pilot(S, route, st, vT) {
  const v = Math.hypot(S.pod.vx, S.pod.vy);
  let bd = Infinity, bi = st.i;
  for (let k = Math.max(0, st.i - 20); k < Math.min(route.length, st.i + 60); k++) {
    const d = (route[k].x - S.pod.x) ** 2 + (route[k].y - S.pod.y) ** 2;
    if (d < bd) { bd = d; bi = k; }
  }
  st.i = bi;
  const aim = route[Math.min(route.length - 1, bi + Math.round((60 + v * 0.36) / 12))];
  const mx = (S.eL.x + S.eR.x) / 2, my = (S.eL.y + S.eR.y) / 2;
  const err = wrap(Math.atan2(aim.y - my, aim.x - mx) - (S.pairTh ?? 0));
  const k = Math.max(-1, Math.min(1, err * 5));
  const top = 0.87;
  let base = v < vT - 4 ? top : Math.max(0, Math.min(top, top * (vT / Math.max(v, 1)) - 0.1));
  const brk = Math.max(0, Math.min(1, (v - vT - 6) / 25));
  if (brk > 0) base = 0;
  const kb = 0.6, gb = 2;
  return [base * (1 - Math.max(0, k)), base * (1 + Math.min(0, k)),
    Math.max(brk, k > kb ? (k - kb) * gb : 0), Math.max(brk, k < -kb ? (-k - kb) * gb : 0)].map((x) => r4(Math.min(1, x)));
}

// One drive: respawned at main sample `at`, every body moving at `mph` along the track there.
// `slow`: [frame, mph] rescales every body's velocity at that frame (the gate test's "braking").
function drive(sc) {
  const sim = makeSim(Object.assign({ track: 'eridanus' }, sc.over)), S = sim.S, T = sim.T;
  const B = T.branches[0], route = routeOf(T, sc.viaBranch);
  sim.respawn(-1, sc.at);
  const a = T.pts[sc.at], v0 = sc.mph / MPH;
  for (const b of S.bodies) { b.vx = v0 * a.tx; b.vy = v0 * a.ty; }
  const names = ['L', 'R', 'pod'], st = { i: 400 + (sc.at - B.from) };
  const log = [], switches = [], walls = { hit: 0, scrape: 0 }, gates = [];
  let gate = null, maxBranchI = -1;
  const frames = sc.inputs ? sc.inputs.length : Math.round(sc.secs * 60);
  for (let f = 0; f < frames; f++) {
    if (sc.slow && f === sc.slow[0]) {
      const k = (sc.slow[1] / MPH) / Math.hypot(S.pod.vx, S.pod.vy);
      for (const b of S.bodies) { b.vx *= k; b.vy *= k; }
    }
    if (sc.restartAt !== undefined && f === sc.restartAt) break;
    if (!sc.inputs && sc.until && sc.until(S, B)) break;
    const u = sc.inputs ? sc.inputs[f] : pilot(S, route, st, (sc.slow && f >= sc.slow[0] ? sc.slow[1] : sc.mph) / MPH);
    log.push(u);
    const inp = { thrL: u[0], thrR: u[1], brkL: u[2], brkR: u[3], repair: false, reignite: true };
    for (let k = 0; k < SUB; k++) {
      const was = S.bodies.map((b) => b.path);
      sim.step(inp, DT);
      S.bodies.forEach((b, j) => { if (b.path !== was[j]) switches.push([f, names[j], b.path, b.hint]); if (b.path === 1) maxBranchI = Math.max(maxBranchI, b.hint); });
      if (S.gate[0] !== gate) { gate = S.gate[0]; gates.push([f, gate]); }
      while (S.events.length) { const e = S.events.shift(); if (e.type in walls) walls[e.type]++; }
    }
  }
  return { sim, log, switches, walls, gates, maxBranchI, pod: [S.pod.x, S.pod.y], paths: S.bodies.map((b) => b.path), hints: S.bodies.map((b) => b.hint) };
}

const probe = makeSim({ track: 'eridanus' });
const B = probe.T.branches && probe.T.branches[0];
check(`one branch on Eridanus, locked outside the job (${probe.T.branches && probe.T.branches.length} branch, open ${B && B.open})`,
  probe.T.branches && probe.T.branches.length === 1 && B.open === false);
const jobProbe = makeSim({ track: 'eridanus', job: 'emergency' });
check(`the job opens it (open ${jobProbe.T.branches[0].open}); no branches on the GP (${makeSim({ track: 'gp' }).T.branches.length})`,
  jobProbe.T.branches[0].open === true && makeSim({ track: 'gp' }).T.branches.length === 0);
const end = B.pts[B.N - 1], J = probe.T.pts[B.join];
check(`the branch: ${B.N} samples from main ${B.from} to the join at ${B.join}, ending ${Math.hypot(end.x - J.x, end.y - J.y).toFixed(4)} m from it`,
  B.N > 1000 && Math.hypot(end.x - J.x, end.y - J.y) < 0.02 && B.pts.every((p) => p.w === 120 && p.bank === 0));
check(`every body starts on the main road (path ${probe.S.bodies.map((b) => b.path)})`, probe.S.bodies.every((b) => b.path === 0));

const at = B.from - B.jz - 10;
const SC = [
  { name: 'locked', over: {}, at, mph: 600, secs: 9, viaBranch: true },
  { name: 'open', over: { job: 'emergency', dawnT0: 1e9 }, at, mph: 600, secs: 100, viaBranch: true,
    until: (S, B) => S.pod.path === 0 && S.pod.hint >= B.join + 150 && S.pod.hint < B.join + 1000 },   // into the town, then stop
  { name: 'fast', over: { job: 'emergency', dawnT0: 1e9 }, at, mph: 1300, slow: [30, 600], secs: 10, viaBranch: true },
  { name: 'straight', over: { job: 'emergency', dawnT0: 1e9 }, at, mph: 800, secs: 10, viaBranch: false }
];
const R = {};
for (const sc of SC) { R[sc.name] = drive(sc); sc.inputs = R[sc.name].log; }
const fmt = (r) => `paths ${r.paths}, walls ${JSON.stringify(r.walls)}, switches ${JSON.stringify(r.switches)}`;

const lk = R.locked;
check(`locked: the main wall holds (${fmt(lk)})`, lk.walls.hit + lk.walls.scrape > 0 && lk.switches.length === 0 && lk.paths.every((p) => p === 0));
const op = R.open;
const ins = op.switches.filter((s) => s[2] === 1), outs = op.switches.filter((s) => s[2] === 0);
check(`open: all three onto the branch inside the junction zone (${JSON.stringify(ins)})`,
  ins.length === 3 && ins.every((s) => s[3] < B.jz));
check(`open: all three back onto the main road at the join (${JSON.stringify(outs)}), deepest branch sample ${op.maxBranchI}`,
  outs.length === 3 && outs.every((s) => Math.abs(s[3] - B.join) <= B.jz) && op.maxBranchI >= B.N - 1 - B.jz && op.paths.every((p) => p === 0));
check(`open: clean (${JSON.stringify(op.walls)}), the gate opened once (${JSON.stringify(op.gates)})`,
  op.walls.hit === 0 && op.walls.scrape === 0 && op.gates.length >= 1 && op.gates[0][1] === true);
const fs_ = R.fast;
check(`fast: over 1,250 mph at the zone's start the gate stays shut (${JSON.stringify(fs_.gates)}), the main wall holds (${fmt(fs_)})`,
  fs_.gates.length >= 1 && fs_.gates[0][1] === false && fs_.switches.length === 0 && fs_.walls.hit + fs_.walls.scrape > 0);
const sr = R.straight;
check(`straight: past the split on the main road, never on the branch (${fmt(sr)})`,
  sr.switches.length === 0 && sr.walls.hit + sr.walls.scrape === 0 && sr.paths.every((p) => p === 0));

// restart / respawn mid-branch: replay the open drive until every body is well along it
const midF = op.switches.length ? Math.max(...ins.map((s) => s[0])) + 600 : 600;
const half = drive(Object.assign({}, SC[1], { inputs: op.log.slice(0, midF), restartAt: midF }));
const onIt = half.paths.every((p) => p === 1);
half.sim.restart();
const hs = half.sim.S;
check(`restart on the branch (frame ${midF}, on it: ${onIt}): every body path ${hs.bodies.map((b) => b.path)}, hint ${hs.bodies.map((b) => b.hint)}`,
  onIt && hs.bodies.every((b) => b.path === 0 && b.hint === 0));
const half2 = drive(Object.assign({}, SC[1], { inputs: op.log.slice(0, midF), restartAt: midF }));
half2.sim.respawn();
const h2 = half2.sim.S, cpI = Math.round(h2.checkpoint * h2.T.N / h2.T.checkpoints) % h2.T.N;
check(`respawn on the branch: every body path ${h2.bodies.map((b) => b.path)} at checkpoint ${h2.checkpoint}'s sample (${h2.bodies.map((b) => b.hint)})`,
  h2.bodies.every((b) => b.path === 0 && b.hint === cpI));

console.log(out.join('\n'));
if (dumpPath) {
  const g = (k) => B.pts.map((p) => p[k]);
  const dump = {
    branch: { name: B.name, N: B.N, from: B.from, join: B.join, jz: B.jz, covered: B.covered,
      px: g('x'), py: g('y'), tx: g('tx'), ty: g('ty'), nx: g('nx'), ny: g('ny'), len: g('len'), w: g('w') },
    drives: SC.map((sc) => ({ name: sc.name, over: sc.over, at: sc.at, mph: sc.mph, slow: sc.slow || null, inputs: sc.inputs,
      pod: R[sc.name].pod, paths: R[sc.name].paths, hints: R[sc.name].hints, switches: R[sc.name].switches, walls: R[sc.name].walls, gates: R[sc.name].gates })),
    restart_at: midF
  };
  fs.writeFileSync(dumpPath, JSON.stringify(dump));
  console.log(`dumped -> ${dumpPath}`);
}
console.log(ok ? 'BRANCH OK' : 'BRANCH FAIL');
process.exit(ok ? 0 : 1);
