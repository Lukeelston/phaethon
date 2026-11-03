// Cross-language brake dynamics fixture, including the real unlimited fourth-gear drag law.
// node tools/record_speed_brakes.js > godot/tests/replay/speed_brakes_expected.json
'use strict';
const fs = require('fs');
global.window = {};
eval(fs.readFileSync(require('path').join(__dirname, '../sim-core.js'), 'utf8'));
const DT = 1 / 480, MPH = 2.2369362920544, records = [];
for (const mph of [2000, 3000, 4000, 6000]) for (const overdrive of [false, true]) {
  for (const throttle of [0, 0.87]) {
    const sim = window.PhaethonSim.makeSim({track: 'range', handling: 'speed', startY: -3000});
    for (const b of sim.S.bodies) { b.vx = mph / MPH; b.vy = 0; }
    const r = {mph, overdrive, throttle, marks: []};
    for (let i = 0; i < 4 * 480; i++) {
      const active = i < 3 * 480;
      sim.step({thrL: active ? throttle : 0, thrR: active ? throttle : 0,
        brkL: active ? 0.65 : 0, brkR: active ? 0.35 : 0, gearOverdrive: overdrive,
        thrMul: 1, burner: false, repair: false, reignite: true}, DT);
      sim.S.events.length = 0;
      if ([240, 480, 1440, 1920].includes(i + 1)) {
        const b = sim.S.pod;
        r.marks.push({step: i + 1, x: b.x, y: b.y, vx: b.vx, vy: b.vy, th: b.th, pair: sim.S.pairTh});
      }
    }
    records.push(r);
  }
}
console.log(JSON.stringify(records, null, 2));
