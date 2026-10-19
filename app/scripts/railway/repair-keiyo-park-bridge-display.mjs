#!/usr/bin/env node
// Outer display-only park/bridge stage; prior shared passenger stages stay strict.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { isDeepStrictEqual } from 'node:util';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { repairPackage as replayEast, repairWestPackage, repairParts as replayParts } from './repair-keiyo-midcurve.mjs';
import { partsForRetainedKeiyoStage } from './repair-keiyo-minami-passenger-centre.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'), REPO=path.resolve(ROOT,'..');
const network=createRequire(import.meta.url)('../../public/rail-network.js');
const read=p=>JSON.parse(fs.readFileSync(path.join(ROOT,p))), SAME=isDeepStrictEqual, STAGE='keiyo-park-bridge-display';
const evidence=()=>read('scripts/railway/keiyo-park-bridge-display-evidence.json');
const taper=t=>t*t*t*(10+t*(-15+6*t));
function latitudeAt(points,lon){const edges=points.slice(1).map((b,i)=>[points[i],b]).filter(([a,b])=>lon<=Math.max(a[0],b[0])&&lon>=Math.min(a[0],b[0]));const vals=edges.map(([a,b])=>a[1]+(b[1]-a[1])*(lon-a[0])/(b[0]-a[0]));assert(vals.length&&vals.every(v=>Math.abs(v-vals[0])<1e-10),'Ambiguous identified longitude');return vals[0];}
function tracks(e){
 const cache=JSON.parse(fs.readFileSync(e.source.cacheAbsolutePath));assert.equal(cache.fetchedAt,e.source.fetchedAt);
 return e.chains.map(ids=>{let points=[],last;
  for(const id of ids){const w=e.ways.find(x=>x.id===id);assert(w);const a=JSON.parse(fs.readFileSync(path.join(REPO,e.source.primarySourceDirectory,`way-${id}-full.json`)));const actual=a.elements.find(x=>x.type==='way');assert.deepEqual([actual.id,actual.nodes,actual.tags,actual.version,actual.timestamp],[w.id,w.nodes,w.tags,w.version,w.timestamp]);const nodes=new Map(a.elements.filter(x=>x.type==='node').map(x=>[x.id,x]));assert.deepEqual(actual.nodes.map(n=>[nodes.get(n).lon,nodes.get(n).lat]),w.coordinates);const cached=cache.elements.find(x=>x.id===id);assert.deepEqual([cached.tags,cached.geometry.map(x=>[x.lon,x.lat])],[w.tags,w.coordinates]);assert(w.tags.railway==='rail'&&w.tags.usage==='main'&&w.tags.operator==='東日本旅客鉄道'&&w.tags.name==='JR京葉線'&&!w.tags.service,'Passenger identity changed');
   const reverse=w.coordinates[0][0]<w.coordinates.at(-1)[0],co=reverse?w.coordinates.toReversed():w.coordinates,ns=reverse?w.nodes.toReversed():w.nodes;if(last!==undefined){assert.equal(ns[0],last,'Passenger leg disconnected');assert.deepEqual(co[0],points.at(-1));}last=ns.at(-1);points.push(...co.slice(points.length?1:0));
  }return points;});
}
export function corridor(e=evidence()){
 assert.equal(e.format,'jtm-keiyo-park-bridge-display-v1');assert.deepEqual(e.window,{eastGuard:[139.87822,35.63813],westGuard:[139.83812,35.64694],coreLongitudes:[139.87176,139.84131]});
 const line=e.baselineLines.find(l=>l.id===e.lineID),iv=network.decodeIntervals(line),original=[...iv[11],...iv[12].slice(1)];assert.deepEqual(iv[11][3],e.window.eastGuard);assert.deepEqual(iv[12][16],e.window.westGuard);const t=tracks(e),mean=lon=>[lon,(latitudeAt(t[0],lon)+latitudeAt(t[1],lon))/2];
 const lo=e.window.westGuard[0],hi=e.window.eastGuard[0],longitudes=[...new Set(t.flat().map(p=>p[0]).concat(original.map(p=>p[0])).filter(l=>l<hi&&l>lo))].sort((a,b)=>b-a);const meanPoints=longitudes.map(mean),physicalStation=line.stations.find(r=>r[0]===e.stationID).slice(2,4),station=projectPointOntoPolyline(physicalStation,meanPoints);assert(station.distanceM>20&&station.distanceM<40,'Station longitudinal alias escaped identified corridor');
 const lons=[...new Set([...longitudes,station.point[0],hi-.00001,lo+.00001])].sort((a,b)=>b-a),core=[];
 const middle=lons.map(lon=>{const target=mean(lon),projection=projectPointOntoPolyline(target,original);assert(projection.distanceM<50);let weight=lon>e.window.coreLongitudes[0]?taper((hi-lon)/(hi-e.window.coreLongitudes[0])):lon<e.window.coreLongitudes[1]?taper((lon-lo)/(e.window.coreLongitudes[1]-lo)):1;
  if(lon===hi-.00001||lon===lo+.00001)weight=0;
  if(weight===1){core.push(target);return lon===station.point[0]?station.point:target;}
  return projection.point.map((v,i)=>v+weight*(target[i]-v));});
 const points=[...iv[11].slice(0,4),...middle,...iv[12].slice(16)],stationIndex=points.findIndex(p=>SAME(p,station.point));assert(stationIndex>4&&stationIndex<points.length-4);return {points,station,stationIndex,core,interval11:points.slice(0,stationIndex+1),interval12:points.slice(stationIndex)};
}
function baselinePackage(input,e){const p=structuredClone(input);for(const l of e.baselineLines){const i=p.lines.findIndex(x=>x.id===l.id);assert(i>=0);p.lines[i]=structuredClone(l);}delete p.geometrySource.manualOverrides[STAGE];return p;}
export function repairPackage(input,e=evidence()){
 const c=corridor(e),old=e.baselineLines.find(l=>l.id===e.lineID),line=structuredClone(old);line.displayIntervalCoordinates={...line.displayIntervalCoordinates,11:c.interval11,12:c.interval12};line.displayStationCoordinates={...line.displayStationCoordinates,[e.stationID]:c.station.point};
 for(const b of e.baselineLines){const actual=input.lines.find(l=>l.id===b.id);assert(SAME(actual,b)||(b.id===e.lineID&&SAME(actual,line)),'Unreviewed Keiyo source changed');}
 for(const [k,v] of Object.entries(e.baselineMarkers))assert.deepEqual(input.geometrySource.manualOverrides[k],v,'Prior Keiyo provenance changed');
 const base=baselinePackage(input,e),mid=read('scripts/railway/keiyo-midcurve-evidence.json'),cache=JSON.parse(fs.readFileSync(e.source.cacheAbsolutePath));assert.deepEqual(repairWestPackage(replayEast(base,mid,cache)),base,'Strict prior Keiyo replay changed');
 const pkg=structuredClone(input);pkg.lines[pkg.lines.findIndex(l=>l.id===e.lineID)]=line;pkg.geometrySource.manualOverrides[STAGE]={reviewedAt:e.reviewedAt,script:'app/scripts/railway/repair-keiyo-park-bridge-display.mjs',evidence:'app/scripts/railway/keiyo-park-bridge-display-evidence.json',lineID:e.lineID,intervals:[11,12],stationID:e.stationID,point:c.station.point,projection:c.station,window:e.window,source:e.source,imageEvidence:e.imageEvidence,policy:e.policy};return pkg;
}
export function repairParts(pkg,input,e=evidence()){
 const base=baselinePackage(pkg,e),out=partsForRetainedKeiyoStage(pkg,input,base,true);const retained=partsForRetainedKeiyoStage(pkg,out,base,false);assert.deepEqual(replayParts(base,retained,read('scripts/railway/keiyo-midcurve-evidence.json')),retained,'Strict prior native replay changed');
 for(const k of Object.keys(e.baselineMeasuredReferences))assert.deepEqual(out[k],input[k],'Park correction changed earlier shared ruler');
 assert.deepEqual(out.partsByRegion.jp.filter(r=>r[0]!==e.lineID),input.partsByRegion.jp.filter(r=>r[0]!==e.lineID));return out;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const apply=process.argv.slice(2).join(' ')==='--apply';assert(process.argv.length===2||apply);const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',evidence:'scripts/railway/keiyo-park-bridge-display-evidence.json',mid:'scripts/railway/keiyo-midcurve-evidence.json',shared:'scripts/railway/keiyo-shared-corridor-evidence.json',minami:'scripts/railway/keiyo-minami-passenger-centre-evidence.json',shio:'scripts/railway/keiyo-shio-transverse-display-evidence.json',...DEPENDENCY_PATHS};const snapshots=Object.fromEntries(Object.entries(paths).map(([k,v])=>[k,{path:path.join(ROOT,v),before:fs.readFileSync(path.join(ROOT,v),'utf8')}])),load=k=>JSON.parse(snapshots[k].before),e=load('evidence'),pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e),deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
 if(apply){const writes=[{...snapshots.package,after:JSON.stringify(pkg)},{...snapshots.lanes,after:JSON.stringify(lanes)+'\n'},...Object.keys(DEPENDENCY_PATHS).map(k=>({...snapshots[k],after:JSON.stringify(deps[k],null,2)+'\n'}))].filter(w=>w.before!==w.after).map(w=>({...w,tmp:w.path+`.keiyo-park-${process.pid}.tmp`}));try{for(const w of writes)fs.writeFileSync(w.tmp,w.after);for(const s of Object.values(snapshots))assert.equal(fs.readFileSync(s.path,'utf8'),s.before,'Concurrent dependency changed');for(const w of writes)fs.renameSync(w.tmp,w.path);}finally{for(const w of writes)if(fs.existsSync(w.tmp))fs.unlinkSync(w.tmp);}}
 console.log(JSON.stringify({mode:apply?'applied':'candidate',station:corridor(e).station,points:pkg.lines.find(l=>l.id===e.lineID).displayIntervalCoordinates[11].length+pkg.lines.find(l=>l.id===e.lineID).displayIntervalCoordinates[12].length-1,physicalChanged:false}));
}
