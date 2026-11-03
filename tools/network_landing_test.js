// Real-step receiving-deck contact, including imperfect but physically valid approaches.
// Initial placement is the only imposed motion; the sim owns the entire landing.
'use strict';
global.window = global.window || {};
require('../sim-core.js');
const PS = window.PhaethonSim, DT = 1 / 480, MPH = 2.236936;

function surface(sim, body, road) {
  const n = sim.nearestOn(road, body.x, body.y, body.hint, 12), a = sim.T.roads[road].pts[n.i];
  const u = Math.max(0, Math.min(1, ((body.x-a.x)*a.tx + (body.y-a.y)*a.ty)/a.len));
  return { height: sim.netHeight(road, n.i+u) + sim.netEdge(n.w, n.lat)[0], inside: !n.off && Math.abs(n.lat) < n.w/2-2 };
}

function trial(sim, jump, yaw, offset, closing, mph, initialClearance = 10) {
  const road = sim.T.jumps[jump][1], R = sim.T.roads[road], p = R.pts[40];
  sim.respawnOn(road, 40, 1);
  const centre = {x:sim.S.pod.x, y:sim.S.pod.y}, angle = yaw*Math.PI/180;
  const c = Math.cos(angle), s = Math.sin(angle), heading = sim.S.pod.th+angle, speed = mph/MPH;
  for (const b of sim.S.bodies) {
    const dx = b.x-centre.x, dy = b.y-centre.y;
    b.x = centre.x+dx*c-dy*s+p.nx*offset; b.y = centre.y+dx*s+dy*c+p.ny*offset;
    b.th += angle; b.vx = speed*Math.cos(heading); b.vy = speed*Math.sin(heading);
    const at = surface(sim,b,road), x = b.x, y = b.y;
    b.x += b.vx*DT; b.y += b.vy*DT;
    const next = surface(sim,b,road); b.x=x; b.y=y;
    b.z = at.height+sim.P.rideH+initialClearance;
    b.vz = (next.height-at.height)/DT-closing;
    b.offRoad=true; b.lock=false;
  }
  const result = {jump,yaw,offset,closing,mph,initialClearance,minClearance:Infinity,maxAfterLanding:-Infinity,captured:[false,false,false],touchdown:[false,false,false],broken:false,wallEnded:false};
  for (let step=0;step<720;step++) {
    sim.step({thrL:.5,thrR:.5,brkL:0,brkR:0,repair:false,reignite:true},DT);
    sim.S.events.length=0;
    // An unsteered angled arrival eventually reaches a guardrail. This test owns
    // deck contact, not survival of the ensuing sideways wall impact.
    if(sim.S.bodies.some(b=>b.contact.some(Boolean))) { result.wallEnded=true; break; }
    result.broken ||= sim.S.binderBroken;
    for (const [index,b] of sim.S.bodies.entries()) {
      if (b.offRoad || b.path !== road) continue;
      result.captured[index]=true;
      const at=surface(sim,b,road);
      if (!at.inside) continue;
      const clearance=b.z-at.height;
      result.minClearance=Math.min(result.minClearance,clearance);
      if(clearance<=sim.P.rideH+.05)result.touchdown[index]=true;
      if(result.touchdown[index])result.maxAfterLanding=Math.max(result.maxAfterLanding,clearance);
    }
  }
  return result;
}

function main() {
  const sim=PS.makeSim({track:'network',handling:'speed'}), results=[], failures=[];
  for(let jump=0;jump<sim.T.jumps.length;jump++) {
    const minimum=sim.T.jumps[jump][2], high=Math.max(5000,minimum+500);
    const cases=[[0,0,30,minimum],[5,-140,120,minimum],[-5,140,120,high],[15,-80,120,high],[-15,80,120,minimum],
      [30,-100,80,high],[-30,100,80,minimum],[0,170,120,minimum],
      [0,-170,120,minimum],[0,0,240,high]];
    for(const args of cases) {
      const r=trial(sim,jump,...args); results.push(r);
      if(!r.captured.every(Boolean)||r.minClearance<sim.P.rideH-1e-5||r.maxAfterLanding>sim.P.rideH+.1||r.broken||(r.closing>=80&&!r.touchdown.every(Boolean))) failures.push(r);
    }
  }
  for(const jump of [0,1,8,16]) for(const miss of ['below','transverse']) {
    const r=trial(sim,jump,miss==='transverse'?90:0,0,0,3500,miss==='below'?-70:10);
    if(r.captured.some(Boolean))failures.push({negative:miss,...r});
  }
  console.log(JSON.stringify({positiveCases:results.length,negativeCases:8,failures:failures.length,examples:failures.slice(0,8)},null,2));
  console.log(`NETWORK LANDINGS ${failures.length ? 'FAIL' : 'PASS'}`);
  process.exitCode=failures.length?1:0;
}
if(require.main===module)main();
module.exports={surface,trial};
