import fs from 'node:fs';
import { createRequire } from 'node:module';
const repo='/Users/sager/Documents/GitHub/JTM-iOS-App';
const require=createRequire(import.meta.url);
const RailNetwork=require(`${repo}/app/public/rail-network.js`);
const RailStroke=require(`${repo}/app/public/rail-stroke.js`);
const pkg=JSON.parse(fs.readFileSync(`${repo}/app/public/rail/jp-2025.json`,'utf8'));
const lanes=JSON.parse(fs.readFileSync(`${repo}/app/public/rail/display-lanes.json`,'utf8'));
const network=RailNetwork.buildNetworkFromCompactPackage(pkg,null,lanes);
const trunkID='jp-東日本旅客鉄道-京葉線';
const armIDs=['jp-東日本旅客鉄道-京葉線-2','jp-東日本旅客鉄道-京葉線-3'];
const part=id=>network.strokeModel.lines.find(x=>x.lineId===id).parts[0];
const distance=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
const at=(stroke,m)=>{
  if(m<=stroke.measures[0]) return stroke.points[0];
  if(m>=stroke.measures.at(-1)) return stroke.points.at(-1);
  return RailStroke.sliceStroke(stroke.points,stroke.measures,m-0.001,m).at(-1);
};
const angle=(a,b,c,d)=>{const u=[b[0]-a[0],b[1]-a[1]],v=[d[0]-c[0],d[1]-c[1]];return Math.abs(Math.atan2(u[0]*v[1]-u[1]*v[0],u[0]*v[0]+u[1]*v[1])*180/Math.PI)};
const build=(id,z,withFollows=true)=>{const p=part(id);const follows=withFollows?p.follows.map(f=>{const c=part(f.canonLineId);return {...f,points:c.coordinates.map(x=>RailStroke.project(x,z)),measures:c.measures}}):[];return RailStroke.buildStroke(p.coordinates.map(x=>RailStroke.project(x,z)),{measures:p.measures,rows:p.rows,totalMetres:p.totalMetres,laneGapPx:z<12?1.35:2.7,minRampPx:24,cornerRadiusPx:3.6,minCornerRadiusPx:3,anchors:p.anchors,follows,enforceMinimumCornerRadius:true})};
const sampleRange=(from,to,step=10)=>{const xs=[];for(let m=from;m<to;m+=step)xs.push(m);xs.push(to);return xs};
const spansOver=(rows,limit)=>{const out=[];for(const row of rows){if(row.px<=limit)continue;const last=out.at(-1);if(last&&row.s-last.to<=10.000001){last.to=row.s;last.max=Math.max(last.max,row.px)}else out.push({from:row.s,to:row.s,max:row.px})}return out};
const result={};
for(const id of armIDs){
 const p=part(id), f=p.follows[0], tenant=p.tenantWindows[0];
 const canonical=part(f.canonLineId);
 const owner=canonical.familyWindows.find(w=>w.groupId===tenant.groupId &&
   w.to>Math.min(f.canonFrom,f.canonTo) && w.from<Math.max(f.canonFrom,f.canonTo));
 const map=s=>f.canonFrom+(s-f.from)/(f.to-f.from)*(f.canonTo-f.canonFrom);
 const exactIdentity={bounds:f.from===f.canonFrom&&f.to===f.canonTo,points:JSON.stringify(p.coordinates)===JSON.stringify(canonical.coordinates),measures:JSON.stringify(p.measures)===JSON.stringify(canonical.measures)};
 const zooms=[];
 for(let z=10;z<=19;z++){
  const arm=build(id,z,true), own=build(id,z,false), trunk=build(trunkID,z,true);
  const full=sampleRange(0,p.totalMetres), ownStable=sampleRange(0,Math.max(0,f.from-300)), shared=sampleRange(tenant.from,tenant.to);
  const sharedRows=shared.map(s=>({s,px:distance(at(arm,s),at(trunk,map(s)))}));
  const worstShared=sharedRows.reduce((a,b)=>b.px>a.px?b:a);
  const ownRows=ownStable.map(s=>({s,px:distance(at(arm,s),at(own,s))}));
  const worstOwn=ownRows.reduce((a,b)=>b.px>a.px?b:a);
  const finite=full.every(s=>{const q=at(arm,s);return q&&Number.isFinite(q[0])&&Number.isFinite(q[1])});
  const boundary=tenant.from, cBoundary=map(boundary), delta=(f.canonTo-f.canonFrom)/(f.to-f.from);
  const ownerBoundary=f.canonTo<f.canonFrom?owner.to:owner.from;
  zooms.push({z,fullSamples:full.length,finite,ownStableTo:f.from-300,maxOwnStablePx:worstOwn.px,maxOwnStableAt:worstOwn.s,sharedSamples:shared.length,maxSharedPx:worstShared.px,maxSharedAt:worstShared.s,sharedSpansOverPoint05Px:spansOver(sharedRows,0.05),mappedFamilyHandoffPx:distance(at(arm,boundary),at(trunk,cBoundary)),familyHandoffPx:distance(at(arm,boundary),at(trunk,ownerBoundary)),familyHandoffTurnDegrees:angle(at(arm,boundary-1),at(arm,boundary),at(trunk,ownerBoundary),at(trunk,ownerBoundary+Math.sign(delta))),commonStationEndpointPx:distance(at(arm,f.to),at(trunk,f.canonTo))});
 }
 result[id]={total:p.totalMetres,follow:f,tenant,owner,tenantBoundaryMapsTo:map(tenant.from),ownerBoundary:f.canonTo<f.canonFrom?owner.to:owner.from,transition:[f.from-300,f.from+300],canonicalDirection:f.canonTo<f.canonFrom?'reverse':'forward',exactIdentity,newIdentityFilterSkips:Object.values(exactIdentity).every(Boolean),zooms};
}
console.log(JSON.stringify(result,null,2));

const cameraProbe=(id,z,ownMeasure,canonicalMeasure=null)=>{
 const p=part(id), f=p.follows[0];
 const ownStroke=build(id,z,true), trunkStroke=build(trunkID,z,true);
 const map=s=>f.canonFrom+(s-f.from)/(f.to-f.from)*(f.canonTo-f.canonFrom);
 const canonMeasure=canonicalMeasure??map(ownMeasure);
 const ownPixel=at(ownStroke,ownMeasure), trunkPixel=at(trunkStroke,canonMeasure);
 const midpoint=[(ownPixel[0]+trunkPixel[0])/2,(ownPixel[1]+trunkPixel[1])/2];
 const toLatLon=pixel=>{const [lon,lat]=RailStroke.unproject(pixel,z);return {lat,lon}};
 return {id,z,ownMeasure,canonMeasure,own:toLatLon(ownPixel),canonical:toLatLon(trunkPixel),midpoint:toLatLon(midpoint),seamPx:distance(ownPixel,trunkPixel)};
};
const east=part(armIDs[0]), eastTenant=east.tenantWindows[0], eastFollow=east.follows[0], eastOwner=part(trunkID).familyWindows.find(w=>w.groupId===eastTenant.groupId&&w.to>Math.min(eastFollow.canonFrom,eastFollow.canonTo)&&w.from<Math.max(eastFollow.canonFrom,eastFollow.canonTo));
const west=part(armIDs[1]), westTenant=west.tenantWindows[0], westFollow=west.follows[0], westOwner=part(trunkID).familyWindows.find(w=>w.groupId===westTenant.groupId&&w.to>Math.min(westFollow.canonFrom,westFollow.canonTo)&&w.from<Math.max(westFollow.canonFrom,westFollow.canonTo));
console.log('CAMERA_PROBES '+JSON.stringify({
 eastFamilyHandoff:cameraProbe(armIDs[0],19,eastTenant.from,eastFollow.canonTo<eastFollow.canonFrom?eastOwner.to:eastOwner.from),
 westFamilyHandoff:cameraProbe(armIDs[1],19,westTenant.from,westFollow.canonTo<westFollow.canonFrom?westOwner.to:westOwner.from),
 eastZ18Peak:cameraProbe(armIDs[0],18,4188.8),
 westZ14Requested:cameraProbe(armIDs[1],14,2429.9),
 westZ14Peak:cameraProbe(armIDs[1],14,2449.9)
},null,2));
