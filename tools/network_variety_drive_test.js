// Drive the complete revised side roads with real throttle/brake inputs.
'use strict';
const assert=require('assert'),NR=require('./net_route.js');
global.window={};require('../sim-core.js');
const sim=window.PhaethonSim.makeSim({track:'network',handling:'speed'}),DT=1/480;
for(const [road,R]of sim.T.roads.entries()){
 if(!/^S\d+$/.test(R.name))continue;
 for(const direction of [1,-1]){
 const first=direction>0?20:R.N-20,last=direction>0?R.N-20:20;
 sim.respawnOn(road,first,direction);
 for(const b of sim.S.bodies){b.vx=direction*1200/2.236936*R.pts[first].tx;b.vy=direction*1200/2.236936*R.pts[first].ty;}
 const route=NR.points(sim.T,[{road,i0:first,i1:last,dir:direction}]);
 // Start rolling into the side road, like a highway exit. This pilot derives
 // heading from velocity and cannot steer a stationary Speedcraft reliably.
 const pilot=NR.makePilot(sim.S,route,NR.plan(route));
 const started=sim.S.time;
 let input,crash=false,off=false,minGap=Infinity,maxGap=0,peak=0;
 for(let step=0;step<480*400;step++){
  if(step%8===0){const u=pilot();if(!u)break;input={thrL:u[0],thrR:u[1],brkL:u[2],brkR:u[3],repair:false,reignite:true};}
  sim.step(input,DT);sim.S.events.length=0;
  crash ||=sim.S.crashT>0; off ||=sim.S.bodies.some(b=>b.offRoad);
  if(step%8===0)for(const b of sim.S.bodies){
   if(b.path!==road)continue;
   const n=sim.nearestOn(road,b.x,b.y,b.hint,12),p=R.pts[n.i];
   const u=Math.max(0,Math.min(1,((b.x-p.x)*p.tx+(b.y-p.y)*p.ty)/p.len));
   const gap=b.z-sim.netHeight(road,n.i+u)-sim.netEdge(n.w,n.lat)[0]-sim.P.rideH;
   minGap=Math.min(minGap,gap);maxGap=Math.max(maxGap,gap);peak=Math.max(peak,b.z);
  }
  if(sim.S.pod.path===road&&(sim.S.pod.hint-last)*direction>=-10)break;
 }
 // The shared end pavement can legitimately assign the craft to its highway.
 const reached=Math.hypot(sim.S.pod.x-R.pts[last].x,sim.S.pod.y-R.pts[last].y)<500;
 assert(!crash&&!off&&!sim.S.binderBroken&&reached,`${R.name} dir ${direction} complete: path=${sim.T.roads[sim.S.pod.path].name}, hint=${sim.S.pod.hint}/${R.N}, t=${sim.S.time}, mph=${Math.hypot(sim.S.pod.vx,sim.S.pod.vy)*2.236936}, crash=${crash}, off=${off}, broken=${sim.S.binderBroken}, input=${JSON.stringify(input)}`);
 assert(minGap>=-0.01&&maxGap<0.1,`${R.name} follows crests/dips: gap ${minGap}..${maxGap}`);
 console.log(`${R.name} dir ${direction} PASS ${(sim.S.time-started).toFixed(1)} s, peak ${peak.toFixed(0)} m, gap ${minGap.toFixed(4)}..${maxGap.toFixed(4)} m`);
 }
}
console.log('NETWORK VARIETY DRIVE PASS');
