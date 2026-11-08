'use strict';
const assert=require('assert');
global.window={};require('../sim-core.js');
const sim=window.PhaethonSim.makeSim({track:'carving'}),T=sim.T;
assert.equal(T.name,'carving','selectable S5 carving circuit exists');
assert.equal(sim.P.handling,'speed','starts in Speedcraft');
assert(T.length>80000 && T.length<220000,'high-speed lap length');
let left=0,right=0;
const wrap=a=>Math.atan2(Math.sin(a),Math.cos(a));
for(let i=0;i<T.N;i++){
 const p=T.pts[i],q=T.pts[(i+1)%T.N];
 assert(p.len>0 && p.len<=12.01,'continuous sampled pavement, including seam');
 assert.equal(p.w,200,'S5 road width');assert.equal(p.mode,'sp');
 const k=wrap(Math.atan2(q.ty,q.tx)-Math.atan2(p.ty,p.tx))/p.len;
 assert(Math.abs(k)<1/5900,'no corner tighter than S5');
 if(k>1/17000)left++; if(k< -1/17000)right++;
}
assert(left>500 && right>500,'substantial sweeps in both directions');
console.log(`CARVING GEOMETRY PASS ${T.N} samples, ${(T.length/1000).toFixed(2)}km`);
