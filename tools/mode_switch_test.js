// The live handling switch, measured on the range (Luke, 2026-10-18: flip between SPEEDCRAFT and
// STARFIGHTER mid-lap).
//   A  flat out in SPEEDCRAFT to 4,000 mph
//   B  full brakes, asking for STARFIGHTER from 3,000 mph down: it must wait for 1,250 mph, then
//      blend in over a second without a kick (decel, pod sway, cable tension, yaw)
//   C  STARFIGHTER flat out: its own top speed
//   D  back to SPEEDCRAFT at speed: it engages at once and pulls away
//   E  asking for STARFIGHTER at 4,000 mph and coasting: nothing happens until 1,250 mph
// Usage: node tools/mode_switch_test.js [sim-core.js]
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(process.argv[2] || 'sim-core.js', 'utf8'));
const { makeSim } = window.PhaethonSim;

const DT = 1 / 480, MPH = 2.236936, G = 9.81;
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

function phaseRun(sim, secs, inpFn, until) {
  const S = sim.S;
  const st = { decel: 0, sway: 0, cable: 0, yaw: 0, engagedAt: null, events: [], t: 0 };
  const n = Math.round(secs / DT);
  for (let i = 0; i < n; i++) {
    const v0 = Math.hypot(S.pod.vx, S.pod.vy);
    const b0 = S.hblend;
    sim.step(Object.assign({ repair: false, reignite: true }, inpFn(v0)), DT);
    st.t += DT;
    const v = Math.hypot(S.pod.vx, S.pod.vy);
    while (S.events.length) {
      const e = S.events.shift();
      if (e.type === 'handling') st.events.push(`${e.mode} at ${(v * MPH).toFixed(0)} mph`);
    }
    if (b0 !== S.hblend && st.engagedAt === null) st.engagedAt = v0 * MPH;
    if (S.hblend > 0 && S.hblend < 1 || b0 !== S.hblend) {
      st.decel = Math.max(st.decel, (v0 - v) / DT / G);
      st.sway = Math.max(st.sway, Math.abs(wrap(S.pod.th - S.pairTh)) * 180 / Math.PI);
      st.cable = Math.max(st.cable, S.cables[0].f, S.cables[1].f);
      st.yaw = Math.max(st.yaw, Math.abs((S.eL.w + S.eR.w) / 2) * 180 / Math.PI);
    }
    if (until && until(v)) break;
  }
  return st;
}

const out = [];
let ok = true;
const sim = makeSim({ track: 'range', handling: 'speed' });
const S = sim.S;
const mph = () => Math.hypot(S.pod.vx, S.pod.vy) * MPH;
const flat = { thrL: 0.87, thrR: 0.87, brkL: 0, brkR: 0 };

const a = phaseRun(sim, 40, () => flat, () => mph() >= 4000);
out.push(`A  SPEEDCRAFT flat out: 4,000 mph after ${a.t.toFixed(1)} s`);

const x0 = S.pod.x;
const b = phaseRun(sim, 60, (v) => Object.assign({ thrL: 0, thrR: 0, brkL: 1, brkR: 1 }, v * MPH < 3000 ? { handling: 'starfighter' } : {}),
  () => S.hblend === 1);
out.push(`B  braking, STARFIGHTER asked from 3,000 mph: engaged at ${b.engagedAt?.toFixed(0)} mph after ${((S.pod.x - x0) / 1000).toFixed(1)} km; ` +
  `while blending: decel ${b.decel.toFixed(1)} g, pod sway ${b.sway.toFixed(2)} deg, cable ${(b.cable / 1000).toFixed(0)} kN, yaw ${b.yaw.toFixed(2)} deg/s  [${b.events}]`);
ok = ok && b.engagedAt !== null && b.engagedAt <= 1251 && b.sway < 3 && S.P.handling === 'starfighter' && S.P.thrustMax === 180000;

const c = phaseRun(sim, 25, () => flat);
out.push(`C  STARFIGHTER flat out: ${mph().toFixed(0)} mph (thrustMax ${S.P.thrustMax}, engineCd ${S.P.engineCd})`);
ok = ok && mph() > 900 && mph() < 1100;

const vBefore = mph();
const d = phaseRun(sim, 12, () => Object.assign({ handling: 'speed' }, flat));
out.push(`D  back to SPEEDCRAFT at ${vBefore.toFixed(0)} mph: engaged at once (${d.engagedAt?.toFixed(0)} mph), 12 s later ${mph().toFixed(0)} mph; ` +
  `while blending: pod sway ${d.sway.toFixed(2)} deg, cable ${(d.cable / 1000).toFixed(0)} kN  [${d.events}]`);
ok = ok && d.engagedAt !== null && Math.abs(d.engagedAt - vBefore) < 30 && mph() > 3000 && d.sway < 3;

const e = phaseRun(sim, 90, () => ({ thrL: 0, thrR: 0, brkL: 0, brkR: 0, handling: 'starfighter' }), () => S.hblend > 0);
out.push(`E  STARFIGHTER asked at ${(vBefore > 0 ? 'speed' : '')} and coasting: it waited ${e.t.toFixed(1)} s, engaging at ${e.engagedAt?.toFixed(0)} mph`);
ok = ok && e.engagedAt !== null && e.engagedAt <= 1251;

console.log(out.join('\n'));
console.log(ok ? 'MODE SWITCH OK' : 'MODE SWITCH NOT OK');
process.exit(ok ? 0 : 1);
