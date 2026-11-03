// Full ballistic arrivals, including the fast upward approach seen in Luke's K10 trace.
// Only lineup sets velocity; every subsequent movement is a real fixed simulation step.
'use strict';
const fs=require('fs');global.window={};require('../sim-core.js');
const PS=window.PhaethonSim,DT=1/480,MPH=2.236936;
function surface(sim,b,road){
 const n=sim.nearestOn(road,b.x,b.y,b.hint,12),p=sim.T.roads[road].pts[n.i];
 const u=Math.max(0,Math.min(1,((b.x-p.x)*p.tx+(b.y-p.y)*p.ty)/p.len));
 return {height:sim.netHeight(road,n.i+u)+sim.netEdge(n.w,n.lat)[0],inside:!n.off&&Math.abs(n.lat)<n.w/2-2};
}
function trial(sim,jump,mph,recorded=null){
 const [launch,catcher]=sim.T.jumps[jump],L=sim.T.roads[launch],i=L.N-101,p=L.pts[i];
 sim.respawnOn(launch,i,1);
 for(const b of sim.S.bodies){b.vx=mph/MPH*p.tx;b.vy=mph/MPH*p.ty;}
 if(recorded){
  for(const [k,b]of sim.S.bodies.entries()){
   const r=recorded.bodies[k];[b.x,b.y,b.z]=r.position;[b.vx,b.vy,b.vz]=r.velocity;
   b.th=r.heading;b.w=r.yaw_rate;b.hint=r.sample;b.offRoad=true;b.lock=false;
  }
  sim.S.armed=recorded.mode==='ramjet';
 }
 const r={jump,mph,recorded:!!recorded,airborne:!!recorded,caught:[false,false,false],settled:[false,false,false],maxGap:0,minGap:Infinity,catchMph:0,catchVz:0,seconds:0};
 const at=[null,null,null];let end=null,frame=0;
 for(let f=0;f<15/DT;f++){
  // Reconstruct the recorded 10 Hz input holds; this is a state regression,
  // not a bit-exact replay of the unrecorded 480 Hz controller changes.
  if(recorded)while(frame+1<recorded.inputs.length&&recorded.inputs[frame+1].t<=f*DT)frame++;
  const input=recorded?recorded.inputs[frame].input:{thrL:0.87,thrR:0.87,brkL:0,brkR:0,burner:mph>=5000,gearOverdrive:true,thrMul:1,reignite:true};
  sim.step(input,DT);
  for(const e of sim.S.events)if(e.type==='airborne'&&e.lip)r.airborne=true;
  sim.S.events.length=0;
  for(const [k,b]of sim.S.bodies.entries())if(!b.offRoad&&b.path===catcher){
   if(at[k]===null){at[k]=f*DT;r.caught[k]=true;end=Math.max(end||0,at[k]+3);if(k===2){r.catchMph=Math.hypot(b.vx,b.vy)*MPH;r.catchVz=b.vz;}}
   const a=surface(sim,b,catcher);
   if(a.inside){const gap=b.z-a.height-sim.P.rideH;r.maxGap=Math.max(r.maxGap,gap);r.minGap=Math.min(r.minGap,gap);if(gap<0.05&&!b.lock)r.settled[k]=true;}
  }
  r.seconds=f*DT;
  if(end!==null&&f*DT>=end)break;
 }
 return r;
}
function main(){
 const sim=PS.makeSim({track:'network',handling:'speed'}),results=[];
 for(let j=0;j<20;j++)for(const mph of [sim.T.jumps[j][2],5000,7000,9000])results.push(trial(sim,j,mph));
 const recorded=JSON.parse(fs.readFileSync(__dirname+'/../godot/tests/replay/fast_capture_recorded.json','utf8'));
 results.push(trial(sim,10,Math.hypot(...recorded.bodies[2].velocity.slice(0,2))*MPH,recorded));
 const failed=results.filter(r=>!r.airborne||!r.caught.every(Boolean)||!r.settled.every(Boolean)||r.maxGap>45||r.minGap < -1e-5);
 fs.writeFileSync('evidence/fast-capture-js.json',JSON.stringify(results,null,2));
 console.log(JSON.stringify({cases:results.length,failures:failed.length,examples:failed.slice(0,6),maxGap:Math.max(...results.map(r=>r.maxGap))}));
 if(failed.length)process.exitCode=1;else console.log('NETWORK FAST CAPTURE PASS');
}
if(require.main===module)main();
module.exports={trial};
