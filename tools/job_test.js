// The emergency run's job in the sim (docs/superpowers/specs/2026-10-19-emergency-run-design.md):
// scripted states (place the pod, set the clock, step) check the dawn, the shelter, the pad and
// the finish, each route measured at its own deadline:
//   lit      tLit at the start line's point is dawnT0; 447.04 m along the front's way, 1 s later
//   clock    the job's clock starts on the first move (the levers, as the sprint's)
//   caught   on the open loop once the front reaches the pod: failed ('dawn'), one 'dawn' event
//   shelter  inside a town, or on the shade line past its canopy's start: not caught
//   pad      stopped in the lake town's box 1.5 s: 'drop', then 'home' on leaving; 1.4 s: still 'out'
//   done     home at the start town's mouth before the front: 'done', route 'open', margin > 0;
//            off the shade line: route 'shade', the margin measured as it went under the canopy
//   ramps    (Luke: "a receiving and outgoing onramp ... reach speed inside of a structure before
//            being exposed to light") four covered ramps on the loop, one at each end of each
//            town, 4 mi long: shelter; home along the open loop the deadline is the receiving
//            ramp's entrance (back under cover), the margin taken there, done at the mouth
//   crash    a wreck mid-job fails it ('crash'); restart starts the job over
//   no job   makeSim({ track: 'eridanus' }): S.job === null, no job events
// Prints JOB OK.
// Usage: node tools/job_test.js [sim-core.js]
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2] || 'sim-core.js', 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, MPH = 2.236936;
const IDLE = { thrL: 0, thrR: 0, brkL: 0, brkR: 0, repair: false, reignite: true };
let ok = true;
const out = [];
function check(msg, cond) { out.push(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); ok = ok && !!cond; }
function drain(S) { const e = S.events.slice(); S.events.length = 0; return e; }
function steps(sim, secs, inp) {
  const ev = [];
  for (let k = 0, n = Math.round(secs / DT); k < n; k++) { sim.step(inp || IDLE, DT); ev.push(...drain(sim.S)); }
  return ev;
}
const jobSim = () => makeSim({ track: 'eridanus', job: 'emergency' });
// every body on main sample i, moving at mph along the road there
function placeMain(sim, i, mph) {
  sim.respawn(-1, i);
  const a = sim.T.pts[i], v = (mph || 0) / MPH;
  for (const b of sim.S.bodies) { b.vx = v * a.tx; b.vy = v * a.ty; }
}
// every body on branch sample j, laid out as respawn lays them on the main road
function placeBranch(sim, j, mph) {
  const T = sim.T, B = T.branches[0], S = sim.S;
  sim.respawn(-1, B.from);
  const a = T.pts[B.from], q = B.pts[j], v = (mph || 0) / MPH, dth = Math.atan2(q.ty, q.tx) - Math.atan2(a.ty, a.tx);
  for (const b of S.bodies) {
    const rx = b.x - a.x, ry = b.y - a.y, al = rx * a.tx + ry * a.ty, ac = rx * a.nx + ry * a.ny;
    b.x = q.x + al * q.tx + ac * q.nx; b.y = q.y + al * q.ty + ac * q.ny; b.th += dth;
    b.path = 1; b.hint = Math.min(B.N - 1, j + Math.round(al / 12)); b.vx = v * q.tx; b.vy = v * q.ty;
  }
}
// the clock running since the job's start, now at t
function clockAt(sim, t) { sim.S.job.t0 = 0; sim.S.time = t; }
const firstSp = (T, from) => { for (let i = from; i < T.N; i++) if (T.pts[i].mode === 'sp') return i; return -1; };

// no job
{
  const sim = makeSim({ track: 'eridanus' });
  const ev = steps(sim, 1, { thrL: 0.5, thrR: 0.5, brkL: 0, brkR: 0, repair: false, reignite: true });
  check(`no job: S.job ${sim.S.job}, ${ev.filter((e) => e.type === 'job' || e.type === 'dawn').length} job events`,
    sim.S.job === null && !ev.some((e) => e.type === 'job' || e.type === 'dawn'));
}
// lit
{
  const sim = jobSim(), P = sim.P, u = [Math.cos(P.dawnDir), Math.sin(P.dawnDir)];
  const t1 = sim.tLit(447.04 * u[0], 447.04 * u[1]) - sim.tLit(0, 0);
  check(`lit: the start line's point at dawnT0 (${sim.tLit(0, 0)} vs ${P.dawnT0}), 447.04 m on ${t1.toFixed(9)} s later; ${P.dawnSpeed} m/s`,
    sim.tLit(0, 0) === P.dawnT0 && Math.abs(t1 - 1) < 1e-9 && P.dawnSpeed === 447.04 && typeof P.dawnDir === 'number');
  const J = sim.S.job;
  check(`a job: stage ${J && J.stage}, t ${J && J.t}, route ${J && J.route}, reason '${J && J.reason}', pad ${sim.T.pad}, mouth ${sim.T.mouth}`,
    J && J.stage === 'out' && J.t === 0 && J.route === 'open' && J.reason === '' && sim.T.pad === 6932 && sim.T.mouth === 16046);
}
// clock: frozen until the first move
{
  const sim = jobSim();
  steps(sim, 2);
  const t0 = sim.S.job.t;
  steps(sim, 1, { thrL: 0.3, thrR: 0.3, brkL: 0, brkR: 0, repair: false, reignite: true });
  check(`clock: ${t0} s after 2 s at rest, ${sim.S.job.t.toFixed(3)} s a second after the levers move`, t0 === 0 && Math.abs(sim.S.job.t - 1) < 0.01);
}
// caught, and not yet
{
  const sim = jobSim(), i = firstSp(sim.T, 2000);
  placeMain(sim, i, 0);
  clockAt(sim, sim.tLit(sim.S.pod.x, sim.S.pod.y) - 0.5);
  let ev = steps(sim, DT);
  const before = sim.S.job.stage;
  clockAt(sim, sim.tLit(sim.S.pod.x, sim.S.pod.y) + 0.001);
  ev = steps(sim, DT);
  const J = sim.S.job;
  check(`caught on the loop (sample ${i}, ${sim.T.pts[i].mode}): ${before} half a second before, then ${J.stage} (${J.reason}), ` +
    `${ev.filter((e) => e.type === 'dawn').length} dawn event, job event ${JSON.stringify(ev.find((e) => e.type === 'job'))}, crashT ${sim.S.crashT.toFixed(2)}`,
    before === 'out' && J.stage === 'failed' && J.reason === 'dawn' && ev.filter((e) => e.type === 'dawn').length === 1 &&
    ev.some((e) => e.type === 'job' && e.stage === 'failed') && sim.S.crashT > 1.5);
  const ev2 = steps(sim, 3);
  check(`failed stays failed through the fade and respawn (${sim.S.job.stage}, ${ev2.filter((e) => e.type === 'dawn').length} more dawn events)`,
    sim.S.job.stage === 'failed' && !ev2.some((e) => e.type === 'dawn' || e.type === 'job'));
}
// shelter
{
  const sim = jobSim(), T = sim.T, B = T.branches[0];
  placeMain(sim, T.pad, 0);
  clockAt(sim, sim.tLit(sim.S.pod.x, sim.S.pod.y) + 5);
  steps(sim, DT);
  const town = sim.S.job.stage;
  const sim2 = jobSim();
  placeBranch(sim2, B.covered[0] + 50, 0);
  clockAt(sim2, sim2.tLit(sim2.S.pod.x, sim2.S.pod.y) + 5);
  steps(sim2, DT);
  const sim3 = jobSim();
  placeBranch(sim3, B.covered[0] - 50, 0);
  clockAt(sim3, sim3.tLit(sim3.S.pod.x, sim3.S.pod.y) + 0.001);
  steps(sim3, DT);
  check(`shelter: in the lake town ${town}; under the canopy ${sim2.S.job.stage} (path ${sim2.S.pod.path}, sample ${sim2.S.pod.hint}); ` +
    `on the shade line short of it ${sim3.S.job.stage} (${sim3.S.job.reason})`,
    town === 'out' && sim2.S.job.stage === 'out' && sim2.S.pod.path === 1 && sim3.S.job.stage === 'failed' && sim3.S.job.reason === 'dawn');
}
// the pad
{
  const sim = jobSim(), T = sim.T;
  placeMain(sim, T.pad, 0);
  clockAt(sim, 10);
  let ev = steps(sim, 1.4);
  const J = sim.S.job, held = J.held, at14 = J.stage;
  ev = steps(sim, 0.2);
  const at16 = J.stage, dropEv = ev.filter((e) => e.type === 'job').map((e) => e.stage);
  placeMain(sim, T.pad + 20, 0);
  ev = steps(sim, DT);
  check(`pad: held ${held.toFixed(3)} s at 1.4 s, still ${at14}; ${at16} by 1.6 s ${JSON.stringify(dropEv)}; ${J.stage} once off it ${JSON.stringify(ev.filter((e) => e.type === 'job').map((e) => e.stage))}`,
    at14 === 'out' && held > 1.3 && at16 === 'drop' && dropEv.join() === 'drop' && J.stage === 'home' && ev.some((e) => e.type === 'job' && e.stage === 'home'));
  const sim2 = jobSim();
  placeMain(sim2, T.pad, 60);
  clockAt(sim2, 10);
  steps(sim2, 0.5);
  check(`pad: rolling through it doesn't count (${sim2.S.job.stage}, held ${sim2.S.job.held})`, sim2.S.job.stage === 'out' && sim2.S.job.held === 0);
}
// done: the open loop
{
  const sim = jobSim(), T = sim.T;
  placeMain(sim, T.mouth - 20, 400);
  sim.S.job.stage = 'home';
  clockAt(sim, 50);
  const ev = steps(sim, 3), d = ev.find((e) => e.type === 'job' && e.stage === 'done'), J = sim.S.job;
  const want = sim.tLit(T.pts[T.mouth].x, T.pts[T.mouth].y);
  check(`done on the open loop: ${J.stage}, route ${J.route}, margin ${J.margin.toFixed(2)} s (tLit(mouth) ${want.toFixed(2)} - t), event ${JSON.stringify(d)}`,
    J.stage === 'done' && J.route === 'open' && J.margin > 0 && d && d.route === 'open' && d.margin === J.margin && Math.abs(J.margin - (want - 50 - (J.t - 50))) < 1e-9);
}
// done: the shade line
{
  const sim = jobSim(), T = sim.T, B = T.branches[0];
  placeBranch(sim, B.covered[0] - 10, 600);
  sim.S.job.stage = 'home';
  clockAt(sim, 50);
  let ev = steps(sim, 1);
  const J = sim.S.job, m = J.margin, r = J.route;
  placeBranch(sim, B.N - 25, 500);   // ~300 m short of the join, on the merge
  ev = steps(sim, 3);
  const d = ev.find((e) => e.type === 'job' && e.stage === 'done');
  check(`done off the shade line: under the canopy route ${r}, margin ${m.toFixed(2)} s; ${J.stage} at the mouth, route ${J.route}, margin ${J.margin.toFixed(2)}, event ${JSON.stringify(d)}`,
    r === 'shade' && m > 0 && J.stage === 'done' && J.route === 'shade' && J.margin === m && d && d.route === 'shade');
}
// the shade line's merge: under the canopy you've made it, onto the main road and into the town
{
  const sim = jobSim(), T = sim.T, B = T.branches[0];
  placeBranch(sim, B.covered[0] - 10, 600);
  sim.S.job.stage = 'home';
  clockAt(sim, 50);
  steps(sim, 1);
  const m = sim.S.job.margin;
  placeBranch(sim, B.N - 25, 500);
  const q = T.pts[B.join - 40];
  clockAt(sim, sim.tLit(q.x, q.y) + 5);   // the merge long since lit
  const ev = steps(sim, 3), J = sim.S.job;
  check(`the shade line's merge, lit: ${J.stage}${J.reason ? ' (' + J.reason + ')' : ''}, route ${J.route}, margin ${J.margin.toFixed(2)} (the canopy's ${m.toFixed(2)}), ` +
    `${ev.filter((e) => e.type === 'dawn').length} dawn events`, J.stage === 'done' && J.route === 'shade' && J.margin === m && !ev.some((e) => e.type === 'dawn'));
}
// the covered ramps
{
  const sim = jobSim(), T = sim.T;
  const tr = []; for (let i = 1; i < T.N; i++) if (T.pts[i].mode !== T.pts[i - 1].mode) tr.push([i, T.pts[i].mode]);
  const len = (r) => { let a = 0; for (let i = r[0]; i <= r[1]; i++) a += T.pts[i].len; return a / 1609.344; };
  const atEnds = T.ramps && T.ramps.length === 4 && tr.every(([i, m]) => T.ramps.some((r) => (m === 'sp' ? r[0] === i : r[1] === i - 1)));
  check(`ramps: ${T.ramps && T.ramps.length} (${JSON.stringify(T.ramps)}), ${T.ramps ? T.ramps.map((r) => len(r).toFixed(2)).join(' / ') : '-'} mi, one at each end of each town, on the loop`,
    atEnds && T.ramps.every((r) => Math.abs(len(r) - 4) < 0.02 && T.pts[r[0]].mode === 'sp' && T.pts[r[1]].mode === 'sp'));
  // sheltered in one: the front long past, not caught
  const r = T.ramps.find((q) => q[1] === T.mouth - 1);
  placeMain(sim, r[0] + 100, 0);
  clockAt(sim, sim.tLit(sim.S.pod.x, sim.S.pod.y) + 5);
  steps(sim, DT);
  const inRamp = sim.S.job.stage;
  // home along the loop into the receiving ramp at 3,000 mph: the margin at its entrance, done at the mouth
  const sim2 = makeSim({ track: 'eridanus', job: 'emergency', handling: 'speed' }), T2 = sim2.T;   // coasting: STARFIGHTER's drag would stop it
  placeMain(sim2, r[0] - 60, 3000);
  sim2.S.job.stage = 'home';
  clockAt(sim2, 50);
  let ev = steps(sim2, 1.5);
  const J = sim2.S.job, e = T2.pts[r[0]];
  const m = J.margin, safe = J.safe, route = J.route;
  const want = sim2.tLit(e.x, e.y) - 50 - (60 * 12) / (3000 / 2.236936);   // roughly: the entrance's light less the time to it
  ev = ev.concat(steps(sim2, 12));
  const d = ev.find((x) => x.type === 'job' && x.stage === 'done');
  check(`ramps: sheltered inside one (${inRamp}); home along the loop the margin is taken at the receiving ramp's entrance (${m.toFixed(2)} s, about ${want.toFixed(2)}; ${route}, safe ${safe}), done at the mouth with it (${JSON.stringify(d)})`,
    inRamp === 'out' && safe === true && route === 'open' && Math.abs(m - want) < 0.5 && d && d.margin === m && d.route === 'open');
}
// the shade line is a STARFIGHTER line: asking for SPEEDCRAFT there does nothing, and a craft that
// came through the gate in SPEEDCRAFT (under 1,250 mph) goes STARFIGHTER (the corkscrews' roll is
// paced for its speeds: 90 deg/s at 1,200 mph)
{
  const sim = makeSim({ track: 'eridanus', job: 'emergency', dawnT0: 1e9, handling: 'speed' }), B = sim.T.branches[0];
  placeBranch(sim, 150, 600);
  steps(sim, 1.5, { thrL: 0.3, thrR: 0.3, brkL: 0, brkR: 0, repair: false, reignite: true, handling: 'speed' });
  const S = sim.S;
  check(`the shade line holds STARFIGHTER: arrived in SPEEDCRAFT, asking for it, after 1.5 s: ${S.hwant}, blend ${S.hblend.toFixed(2)}, ${sim.P.handling} (path ${S.pod.path})`,
    S.pod.path === 1 && S.hwant === 'starfighter' && S.hblend === 1);
}
// crash, restart
{
  const sim = jobSim();
  placeMain(sim, 3000, 300);
  clockAt(sim, 5);
  sim.S.pod.health = 0;
  const ev = steps(sim, DT);
  const J = sim.S.job, st = J.stage, rs = J.reason;
  sim.restart();
  const K = sim.S.job;
  check(`crash: ${st} (${rs}) ${JSON.stringify(ev.filter((e) => e.type === 'job'))}; restart: ${K.stage}, t ${K.t}, held ${K.held}, route ${K.route}, reason '${K.reason}'`,
    st === 'failed' && rs === 'crash' && K.stage === 'out' && K.t === 0 && K.held === 0 && K.route === 'open' && K.reason === '' && K.t0 === null);
}

console.log(out.join('\n'));
console.log(ok ? 'JOB OK' : 'JOB FAIL');
process.exit(ok ? 0 : 1);
