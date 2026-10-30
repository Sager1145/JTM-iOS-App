#!/usr/bin/env node
// Bounded cartographic display repair; physical routing and mileage are unchanged.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {assertAllowedCandidateDirectory, assertAllowedCandidateFile} from './local-evidence-path.mjs';
import {refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const APP = path.join(REPO, 'app'), EV = path.join(REPO, 'railway-evidence/local');
export const AUTHORITY_PATH = path.join(EV, 'proposals/daishi-minatocho-suzukicho-20261020/bounded-visible-north-track-candidate.json');
const LINE = 'jp-京浜急行電鉄-大師線', KEY = 'daishi-minatocho-suzukicho-display';
const STATIONS = ['004417','004415'];
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const PIXELS = [ [[20,658],[100,665],[200,720.5],[300,789.5],[450,864],[700,920],[900,962],[980,979],[1000,983],[1280,1018],[1400,1021],[1600,1009],[1900,989],[2200,968],[2380,954.5]], [[20,1056],[200,1045],[500,1024],[800,1003],[1000,991],[1280,970],[1520,954],[1760,939],[2000,922],[2200,908],[2300,901]] ];
const VIEWS = STATIONS.map((_,i) => path.join(EV,`diagnostics/sessions/keikyu-daishi-seven-station-caps-bundle-20261020/alignment/captures/${String(i+1).padStart(6,'0')}/000000/view.json`));

function proposedLine(e) {
 assert.deepEqual([e.format,e.lineID,e.stationIDs,e.intervalIndices,e.retainedSourceInterval0PrefixCount,e.retainedSourceInterval2SuffixStart,e.retainedKojimashinden],['jtm-daishi-visible-north-track-authority-v1',LINE,STATIONS,[0,1,2],11,2,true],'Minatocho/Suzukicho authority scope changed');
 const source=net.decodeIntervals(e.baselineLine);assert.deepEqual(source.map(p=>p.length),[18,6,5,8,5,11]);
 assert.deepEqual(e.supportAuthority.map(g=>g.supports.map(s=>s.pixel)),PIXELS,'Minatocho/Suzukicho own-track pixel authority changed');
 for(const [i,g] of e.supportAuthority.entries()) {
  assert.equal(g.stationID,STATIONS[i]);assert.equal(g.viewPath,VIEWS[i]);
  const v=read(g.viewPath),q=v.snapshotProjection,c=v.camera,world=2**28;
  assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID,v.pointOrdinal],[LINE,i+1,STATIONS[i],e.baselineLine.stations[i+2][0],0]);
  assert(q&&q.displayScale===1&&c.heading===0&&c.pitch===0&&q.widthPoints===2400&&q.heightPoints===2000,'Minatocho/Suzukicho actual projection missing');
  const cx=(c.longitude+180)/360*world,cy=(1-Math.asinh(Math.tan(c.latitude*Math.PI/180))/Math.PI)/2*world;
  for(const s of g.supports){const x=cx+(s.pixel[0]-q.centerXPoints)*q.mapPointsPerPointX,y=cy+(s.pixel[1]-q.centerYPoints)*q.mapPointsPerPointY;
   const coordinate=[x/world*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/world)))*180/Math.PI];
   assert(s.coordinate.length===2&&s.coordinate.every((n,k)=>Number.isFinite(n)&&Math.abs(n-coordinate[k])<1e-10),'Minatocho/Suzukicho support projection changed');}
 }
 const m=e.supportAuthority[0].supports.map(s=>[...s.coordinate]),z=e.supportAuthority[1].supports.map(s=>[...s.coordinate]);
 const line=structuredClone(e.baselineLine);line.displayStationCoordinates={...line.displayStationCoordinates,'004417':m[9],'004415':z[5]};
 line.displayIntervalCoordinates={...line.displayIntervalCoordinates,0:[...source[0].slice(0,11),...m.slice(0,10)],1:[...m.slice(9),...z.slice(0,6)],2:[...z.slice(5),...source[2].slice(2)]};
 for(const i of [0,1,2])assert(line.displayIntervalCoordinates[i].every((p,n,a)=>n===0||p[0]>a[n-1][0]),'Minatocho/Suzukicho display backtracks');
 assert.deepEqual(line,e.candidateLine,'Minatocho/Suzukicho candidate exceeds bounded authority');return line;
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), rows = input.lines.filter(l => l.id === LINE);
  assert.equal(rows.length, 1, 'Minatocho/Suzukicho own line missing/duplicated');
  assert(equal(rows[0], e.baselineLine) || equal(rows[0], line), 'Minatocho/Suzukicho current own source changed');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: [0,1,2],
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-visible-north-own-track-display-repair; full-passenger-caps-and-whole-line-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Minatocho/Suzukicho provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const line = pkg.lines.find(l => l.id === LINE);
  assert.deepEqual(line, proposedLine(e));
  const baseline = partRowsForLine(e.baselineLine, net.displayPartsForLine(e.baselineLine), null, null);
  // With physical anchors retained, the alias/groomed path cannot be reconstructed
  // from physical intervals. Embed the actual JS display part as native fallback.
  const rows = partRowsForLine(line, net.displayPartsForLine(line), null, null);
  assert.equal(rows.length, 1);
  assert(Array.isArray(rows[0][7]), 'Minatocho/Suzukicho native fallback missing');
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert(equal(own, baseline) || equal(own, rows), 'Minatocho/Suzukicho stale/foreign own native row');
  // No own lanes/follows/family windows/maps exist in the inspected baseline.
  // Unknown newly introduced own references require review rather than guessing.
  for (const [key,value] of Object.entries(input)) if (key !== 'partsByRegion') {
    assert(!JSON.stringify(value)?.includes(LINE), 'Minatocho/Suzukicho own native reference requires review: ' + key);
  }
  assert(!(input.excludedOperators || []).includes(line.operator), 'Minatocho/Suzukicho operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

// Human review is separate from capture completion; only scoped proof files are bound.
export function validateCandidateReview(receipt,line) {
 assert(receipt,'Minatocho/Suzukicho scoped candidate-review receipt required before --apply');
 assert.deepEqual([receipt.format,receipt.status,receipt.lineID,receipt.stationIDs,receipt.intervalIndices,receipt.wholeLineAccepted,receipt.MainCertified],['jtm-daishi-minatocho-suzukicho-candidate-review-v1','bounded-candidate-reviewed',LINE,STATIONS,[0,1,2],false,false],'Minatocho/Suzukicho review scope changed');
 assert.equal(receipt.reviewedOwnLineSha256,sha(JSON.stringify(line)),'Minatocho/Suzukicho reviewed own line changed');
 assert(Array.isArray(receipt.captures)&&receipt.captures.length>=5,'Minatocho/Suzukicho scoped reviewed captures required');
 const snapshots=[],seen=new Set(),body=new Set(),stations=new Set();
 for(const capture of receipt.captures){
  canonicalFile(capture.viewPath);const viewPath=fs.realpathSync(capture.viewPath);
  assert(viewPath.startsWith(path.join(EV,'diagnostics/sessions')+path.sep)&&path.basename(viewPath)==='view.json','Minatocho/Suzukicho noncanonical reviewed view');
  assert(!seen.has(viewPath),'Minatocho/Suzukicho duplicate reviewed capture');seen.add(viewPath);
  for(const [file,key]of [['view.json','viewSha256'],['basemap.png','basemapSha256'],['smooth.png','smoothSha256']]){const p=path.join(path.dirname(viewPath),file),before=fs.readFileSync(p);assert.equal(sha(before),capture[key],'Minatocho/Suzukicho reviewed capture bytes changed');snapshots.push({path:p,before});}
  const v=JSON.parse(snapshots.at(-3).before),i=v.intervalIndex,q=v.snapshotProjection;
  const identity=[v.lineID,i,v.fromStationID,v.toStationID,v.pointOrdinal];
  assert([0,1,2].includes(i),'Minatocho/Suzukicho foreign reviewed interval');
  assert.deepEqual(identity,[LINE,i,line.stations[i][0],line.stations[i+1][0],v.pointOrdinal]);assert.deepEqual(identity,capture.identity,'Minatocho/Suzukicho reviewed identity changed');
  assert(q&&q.displayScale===1&&v.camera.heading===0&&v.camera.pitch===0&&Number.isFinite(q.mapPointsPerPointX)&&q.mapPointsPerPointX>0&&Number.isFinite(q.mapPointsPerPointY)&&q.mapPointsPerPointY>0,'Minatocho/Suzukicho reviewed projection missing');
  assert.deepEqual(q,capture.snapshotProjection,'Minatocho/Suzukicho reviewed projection changed');assert.deepEqual(v.renderContract,capture.renderContract,'Minatocho/Suzukicho render contract changed');
  assert(v.wholeLineRenderDependency);assert.equal(v.wholeLineRenderDependency,capture.wholeLineRenderDependency,'Minatocho/Suzukicho reviewed render dependency changed');
  const identityPath=path.resolve(path.dirname(path.dirname(path.dirname(path.dirname(viewPath)))),v.intervalIdentityPlan);
  canonicalFile(identityPath);const before=fs.readFileSync(identityPath);snapshots.push({path:identityPath,before});
  // Preserve UInt64 bits through JSON parsing rather than rounding them to JS numbers.
  const plan=JSON.parse(before.toString().replace(/("(?:latitudeBits|longitudeBits)"\s*:\s*)(\d+)/g,'$1"$2"'));
  const item=plan.items.find(it=>it.itemID===LINE+'#'+i);assert(item,'Minatocho/Suzukicho reviewed selected identity absent');
  const bits=n=>{const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readBigUInt64BE().toString();};
  const coords=p=>p.map(([x,y])=>({latitudeBits:bits(y),longitudeBits:bits(x)}));
  const physical=net.decodeIntervals(line),display=line.displayIntervalCoordinates[i]||physical[i];
  assert.deepEqual(item.identity.source,coords(physical[i]),'Minatocho/Suzukicho reviewed source identity changed');assert.deepEqual(item.identity.display,coords(display),'Minatocho/Suzukicho reviewed display identity changed');
  if(v.captureSettings.zoom===17)body.add(i);
  if(v.captureSettings.zoom===19&&v.pointOrdinal===0&&[1,2].includes(i))stations.add(v.fromStationID);
 }
 assert.deepEqual([...body].sort(),[0,1,2],'Minatocho/Suzukicho affected interval review missing');assert.deepEqual([...stations].sort(),[...STATIONS].sort(),'Minatocho/Suzukicho station review missing');return snapshots;
}

function canonicalFile(p) {
  assertAllowedCandidateFile(p);
  assert(fs.realpathSync(p).startsWith(EV + path.sep), 'Minatocho/Suzukicho review receipt must use canonical evidence tree');
}

function main(args) {
  const candidate = args.length === 2 && args[0] === '--candidate-root' ? path.resolve(args[1]) : null;
  const apply = args[0] === '--apply';
  assert(candidate || apply, 'Use --candidate-root <canonical EV/candidates/dir> or --apply --candidate-review <receipt.json>');
  let receiptPath;
  if (apply) {
    assert(args.length === 3 && args[1] === '--candidate-review', 'Minatocho/Suzukicho scoped candidate-review receipt required before --apply');
    receiptPath = path.resolve(args[2]); canonicalFile(receiptPath);
  } else {
    assertAllowedCandidateDirectory(candidate);
    assert(candidate.startsWith(path.join(EV,'candidates') + path.sep), 'Minatocho/Suzukicho candidate must use canonical evidence tree');
    // Reject a lexical canonical path resolving through a symlink to scratch.
    let ancestor = candidate;
    while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
    assert(fs.realpathSync(ancestor).startsWith(EV + path.sep), 'Minatocho/Suzukicho candidate ancestor escaped canonical evidence tree');
  }
  const snapshot = p => ({path:p,before:fs.readFileSync(p)});
  const authority = snapshot(AUTHORITY_PATH), e = JSON.parse(authority.before);
  const paths = {package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([k,p]) => [k,snapshot(path.join(APP,p))]));
  const load = k => JSON.parse(inputs[k].before);
  const pkg = repairPackage(load('package'),e), lanes = repairParts(pkg,load('lanes'),e);
  const custody = [authority,...VIEWS.map(snapshot),snapshot(path.join(APP,'public/rail-network.js')),
    snapshot(path.join(APP,'scripts/railway/build-display-lanes.mjs')),
    snapshot(path.join(APP,'scripts/railway/repair-three-reversal-extents.mjs'))];
  if (apply) {
    const receipt = snapshot(receiptPath);
    custody.push(receipt,...validateCandidateReview(JSON.parse(receipt.before),pkg.lines.find(l => l.id === LINE)));
  }
  const deps = refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k,load(k)])));
  const outputs = {package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',
    ...Object.fromEntries(Object.entries(deps).map(([k,v]) => [k,JSON.stringify(v,null,2)+'\n']))};
  let writes;
  if (candidate) {
    fs.mkdirSync(candidate,{recursive:true}); assertAllowedCandidateDirectory(candidate);
    writes = Object.entries(outputs).map(([k,after]) => {
      const p = path.join(candidate,path.basename(inputs[k].path));
      assert(!fs.existsSync(p) || !fs.lstatSync(p).isSymbolicLink(), 'Minatocho/Suzukicho candidate output cannot be symlink');
      if (!fs.existsSync(p)) fs.writeFileSync(p,'',{flag:'wx'});
      return {...snapshot(p),after:Buffer.from(after)};
    });
  } else writes = Object.entries(outputs).map(([k,after]) => ({...inputs[k],after:Buffer.from(after)}));
  applyPreparedWrites(writes,[...Object.values(inputs),...custody,...(candidate ? writes : [])]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,
    nativeRows:lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0,7)),
    fullPassengerCapsCertified:false,imageryRegistrationCertified:false,wholeLineAccepted:false,MainCertified:false}));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
