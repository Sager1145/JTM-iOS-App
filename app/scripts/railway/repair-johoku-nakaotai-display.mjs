#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(APP);
const EVIDENCE = path.join(APP,'scripts/railway/johoku-nakaotai-display-evidence.json');
const LINE = 'jp-JR東海交通事業-城北線';
const KEY = 'johoku-nakaotai-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p,'utf8'));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);

function sourceTexts(e) {
  return Object.fromEntries(Object.keys(e.sourceFiles).map(name=>[name,fs.readFileSync(path.resolve(REPO,e.sourceRoot,name),'utf8')]));
}

// This is a correspondence between two positively identified passenger ways,
// not a nearest-rail search or an average of duplicate/generalised N02 lines.
export function deriveOwnPair(e=read(EVIDENCE), texts=sourceTexts(e)) {
  const tracks=[];
  for(const [id,version,routeID,routeVersion,memberIndex,direction] of [
    [58218285,8,11728676,2,17,'東海交通事業城北線 (枇杷島=>勝川)'],
    [768955042,7,11728762,3,15,'東海交通事業城北線 (勝川=>枇杷島)'],
  ]) {
    for(const suffix of ['full','relations']) {
      const name=`way-${id}-${suffix}.json`;
      assert.equal(texts[name],e.sourceFiles[name],'Johoku source bytes changed: '+name);
    }
    const full=JSON.parse(texts[`way-${id}-full.json`]);
    const way=full.elements.find(r=>r.type==='way'&&r.id===id);
    assert.equal(way?.version,version,'Johoku own way version changed');
    for(const [key,value] of Object.entries({railway:'rail',operator:'東海交通事業',name:'東海交通事業城北線',usage:'branch',bridge:'viaduct',layer:'1',source:'KSJ2'}))
      assert.equal(way.tags[key],value,'Johoku own track identity changed: '+key);
    assert.equal(way.tags.service,undefined,'Johoku passenger reference cannot be a siding/yard way');
    const relations=JSON.parse(texts[`way-${id}-relations.json`]);
    const route=relations.elements.find(r=>r.type==='relation'&&r.id===routeID);
    assert.equal(route?.version,routeVersion,'Johoku passenger route version changed');
    for(const [key,value] of Object.entries({type:'route',route:'train',operator:'東海交通事業','name:ja':direction,'public_transport:version':'2'}))
      assert.equal(route.tags[key],value,'Johoku passenger route identity changed: '+key);
    assert.deepEqual(route.members[memberIndex],{type:'way',ref:id,role:''},'Johoku own passenger way membership changed');
    const railway=relations.elements.find(r=>r.type==='relation'&&r.id===10406558);
    assert.equal(railway?.version,12);
    assert.equal(railway.tags.route,'railway');
    assert.equal(railway.tags.operator,'JR東海交通事業');
    assert(railway.members.some(r=>r.type==='way'&&r.ref===id));
    const nodes=new Map(full.elements.filter(r=>r.type==='node').map(r=>[r.id,r]));
    assert.equal(way.nodes.length,82);
    const coords=way.nodes.map(nodeID=>{
      const node=nodes.get(nodeID);
      assert(node&&Number.isInteger(node.version),'Johoku own node proof missing');
      return [node.lon,node.lat];
    });
    // First direction is west→east, reverse passenger direction east→west.
    if(id===768955042)coords.reverse();
    assert(coords.slice(1).every((p,i)=>p[0]>coords[i][0]),'Johoku reference longitude order changed');
    tracks.push(coords);
  }
  const low=Math.max(...tracks.map(t=>t[0][0])), high=Math.min(...tracks.map(t=>t.at(-1)[0]));
  const longitudes=[...new Set(tracks.flatMap(t=>t.map(p=>p[0]).filter(x=>x>=low&&x<=high)))].sort((a,b)=>a-b);
  const latitudeAt=(track,x)=>{
    const index=track.findIndex((p,i)=>i+1<track.length&&p[0]<=x&&x<=track[i+1][0]);
    assert(index>=0,'Johoku paired correspondence outside identified track');
    const a=track[index],b=track[index+1];
    return a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0]);
  };
  const mean=longitudes.map(x=>[x,(latitudeAt(tracks[0],x)+latitudeAt(tracks[1],x))/2]);
  const old=e.fragment.oldDecodedInterval;
  const first=projectPointOntoPolyline(old[26],mean), last=projectPointOntoPolyline(old[33],mean);
  assert.deepEqual([first.insertIndex,last.insertIndex],[120,156],'Johoku frozen own window changed');
  // Retain exact N02 boundary controls: the projection locates interior source
  // supports only. It does not move either station or insert a transverse leg.
  const replacement=[old[26],...mean.slice(first.insertIndex+1,last.insertIndex+1),old[33]];
  assert.deepEqual(replacement,e.fragment.replacementCoordinates,'Johoku paired support derivation changed');
  return {mean,replacement,projections:[first,last]};
}

function proposedLine(e) {
  assert.equal(e.format,'jtm-johoku-nakaotai-display-v1');
  assert.equal(e.lineID,LINE);
  const line=structuredClone(e.baselineLine), old=network.decodeIntervals(line)[1];
  assert.deepEqual(line.stations.slice(1,3).map(s=>s[0]),['005319','005303']);
  assert.deepEqual(old,e.fragment.oldDecodedInterval);
  assert.deepEqual([e.fragment.firstDecodedVertexInclusive,e.fragment.lastDecodedVertexInclusive],[26,33]);
  assert.deepEqual(old.slice(26,34),[[136.86961,35.21779],[136.87115,35.21781],[136.87205,35.21794],[136.87338,35.21824],[136.87427,35.21849],[136.87531,35.21882],[136.87571,35.21894],[136.87634,35.21915]]);
  const {replacement}=deriveOwnPair(e);
  const interval=[...old.slice(0,26),...replacement,...old.slice(34)];
  assert.deepEqual(interval,e.fragment.candidateDecodedInterval);
  line.displayIntervalCoordinates={...line.displayIntervalCoordinates,1:interval};
  return line;
}

export function repairPackage(input,e=read(EVIDENCE)) {
  const line=proposedLine(e), indices=input.lines.flatMap((l,i)=>l.id===LINE?[i]:[]);
  assert.equal(indices.length,1);
  assert(equal(input.lines[indices[0]],e.baselineLine)||equal(input.lines[indices[0]],line),'Johoku baseline changed');
  assert.match(input.geometrySource.license,/OpenStreetMap.*ODbL/i);
  const result=structuredClone(input);
  result.lines[indices[0]]=line;
  result.geometrySource.manualOverrides??={};
  result.geometrySource.manualOverrides[KEY]={reviewedAt:e.reviewedAt,status:e.status,lineID:LINE,intervalIndex:1,
    ways:[[58218285,8],[768955042,7]],passengerRoutes:[[11728676,2],[11728762,3]],
    policy:e.policy,research:e.research,script:'app/scripts/railway/repair-johoku-nakaotai-display.mjs',physicalTopologyChanged:false};
  return result;
}

export function repairParts(pkg,input,e=read(EVIDENCE)) {
  const line=pkg.lines.find(l=>l.id===LINE);
  assert.deepEqual(line,proposedLine(e));
  const rows=partRowsForLine(line,network.displayPartsForLine(line));
  assert.equal(rows.length,1);
  assert.deepEqual(rows[0].slice(0,4),[LINE,0,-1,-1]);
  assert.deepEqual(rows[0].slice(4,6),[e.expectedNativePart.controls,e.expectedNativePart.roundedMetres]);
  assert.deepEqual(rows[0][8],[]);
  for(const key of ['partsByRegion','byRegion','followsByRegion','familyWindowsByRegion','strokeExcludedByRegion','chainBoundariesByRegion','releasedIntervalsByRegion']) {
    const own=(input[key]?.jp||[]).filter(r=>r[0]===LINE||key==='followsByRegion'&&r[4]===LINE);
    const expected=key==='partsByRegion'?rows:[];
    assert(equal(own,e.baselineRows[key])||equal(own,expected),'Johoku measured reference changed: '+key);
  }
  assert.deepEqual((input.loopsByRegion?.jp||[]).filter(r=>(r.lineIds||[]).includes(LINE)),e.baselineRows.loopsByRegion,'Johoku measured reference changed: loopsByRegion');
  assert.deepEqual((input.reversedLoopParts?.jp||[]).filter(r=>r.startsWith(LINE+'#')),e.baselineRows.reversedLoopParts,'Johoku measured reference changed: reversedLoopParts');
  const hubs=(input.hubReportByRegion?.jp||[]).flatMap(h=>(h.members||[]).filter(m=>m.lineId===LINE).map(member=>({hubID:h.hubId,member})));
  assert.deepEqual(hubs,e.baselineRows.hubReportByRegion,'Johoku measured reference changed: hubReportByRegion');
  const result=structuredClone(input);
  result.partsByRegion.jp=result.partsByRegion.jp.map(r=>r[0]===LINE?rows[0]:r);
  return result;
}

function main(args) {
  const candidate=args.length===2&&args[0]==='--candidate-root'?path.resolve(args[1]):null;
  assert(candidate||equal(args,['--apply']),'Use --candidate-root /private/tmp/<dir> or --apply');
  if(candidate)assert(candidate.startsWith('/private/tmp/'));
  const paths={package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const snapshots=Object.fromEntries(Object.entries(paths).map(([k,p])=>[k,{path:path.join(APP,p),before:fs.readFileSync(path.join(APP,p),'utf8')}]));
  const evidenceText=fs.readFileSync(EVIDENCE,'utf8'), e=JSON.parse(evidenceText);
  const sources=[{path:EVIDENCE,before:evidenceText},...Object.keys(e.sourceFiles).map(name=>({path:path.resolve(REPO,e.sourceRoot,name),before:e.sourceFiles[name]}))];
  const external=e.externalNoOwnReferencePaths.map(p=>{
    const input={path:path.resolve(REPO,p),before:fs.readFileSync(path.resolve(REPO,p),'utf8')};
    assert(!input.before.includes(LINE),'Johoku external reference requires review: '+p);
    return input;
  });
  const load=k=>JSON.parse(snapshots[k].before);
  const pkg=repairPackage(load('package'),e), lanes=repairParts(pkg,load('lanes'),e);
  const deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));
  const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.entries(deps).map(([k,v])=>[k,JSON.stringify(v,null,2)+'\n']))};
  const inputs=[...Object.values(snapshots),...sources,...external];
  // The same targeted byte preflight guards candidate export and production
  // application. No input is reloaded or silently replaced during preparation.
  for(const input of inputs)assert.equal(fs.readFileSync(input.path,'utf8'),input.before,'Johoku input bytes changed before write: '+input.path);
  if(candidate){
    fs.mkdirSync(candidate,{recursive:true});
    for(const [k,after] of Object.entries(outputs))fs.writeFileSync(path.join(candidate,path.basename(snapshots[k].path)),after);
  }else applyPreparedWrites(Object.entries(outputs).filter(([k,after])=>after!==snapshots[k].before).map(([k,after])=>({...snapshots[k],after})),inputs);
  const row=lanes.partsByRegion.jp.find(r=>r[0]===LINE);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',lineID:LINE,nativeControls:row[4],nativeMetres:row[5],physicalTopologyChanged:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2));
