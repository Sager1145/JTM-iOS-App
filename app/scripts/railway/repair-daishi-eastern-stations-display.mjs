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
export const AUTHORITY_PATH = path.join(EV, 'proposals/daishi-eastern-stations-20261020/bounded-visible-track-candidate.json');
const LINE = 'jp-京浜急行電鉄-大師線', KEY = 'daishi-eastern-stations-display';
const STATIONS = ['004413','004408','004407'];
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const PIXELS = [[[20,1100],[300,1081],[400,1074],[700,1052],[900,1037],[1180,995],[1190,992.5],[1400,930],[1500,891.5],[1800,761.5],[2100,665],[2380,633]],[[20,1001],[300,999],[700,996],[1000,993],[1220,993],[1500,990.5],[2200,989],[2380,987]],[[300,992],[700,988.5],[900,988.5],[1250,989],[1600,990],[2000,1092],[2200,1193.5],[2380,1284]]];
const ALIAS_PIXELS = [[1190,992.5],[1220,993],[1250,989]];
const VIEWS = STATIONS.map((_,i) => path.join(EV,`diagnostics/sessions/keikyu-daishi-seven-station-caps-bundle-20261020/alignment/captures/${String(i+3).padStart(6,'0')}/000000/view.json`));

function proposedLine(e) {
 assert.deepEqual([e.format,e.lineID,e.stationIDs,e.intervalIndices,e.retainedInterval2PrefixCount,e.retainedInterval5SuffixCount,e.retainedWesternIntervals,e.retainedAliases,e.commonDisplayPartPrefixCount],['jtm-daishi-eastern-visible-track-authority-v1',LINE,STATIONS,[2,3,4,5],6,9,[0,1],['004417','004415','004418'],55],'Daishi eastern stations authority scope changed');
 assert.equal(sha(JSON.stringify(e.baselineLine)),'5a786b7a13f78addb3b285e41c429584c8d595c7758649592a2dba2dadda4cc8','Daishi eastern stations baseline changed');
 const source=net.decodeIntervals(e.baselineLine);assert.deepEqual(source.map(p=>p.length),[18,6,5,8,5,11]);
 assert.deepEqual(e.supportAuthority.map(g=>g.supports.map(s=>s.pixel)),PIXELS,'Daishi eastern stations own-track pixel authority changed');
 for(const [i,g] of e.supportAuthority.entries()) {
  assert.equal(g.stationID,STATIONS[i]);assert.equal(g.viewPath,VIEWS[i]);assert.deepEqual(g.aliasPixel,ALIAS_PIXELS[i]);assert.deepEqual(g.aliasCoordinate,g.supports.find(s=>equal(s.pixel,g.aliasPixel))?.coordinate,'Daishi eastern stations alias not on selected visible support');
  const v=read(g.viewPath),q=v.snapshotProjection,c=v.camera,world=2**28;
  assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID,v.pointOrdinal],[LINE,i+3,STATIONS[i],e.baselineLine.stations[i+4][0],0]);
  assert(q&&q.displayScale===1&&c.heading===0&&c.pitch===0&&q.widthPoints===2400&&q.heightPoints===2000,'Daishi eastern stations actual projection missing');
  const cx=(c.longitude+180)/360*world,cy=(1-Math.asinh(Math.tan(c.latitude*Math.PI/180))/Math.PI)/2*world;
  for(const s of g.supports){const x=cx+(s.pixel[0]-q.centerXPoints)*q.mapPointsPerPointX,y=cy+(s.pixel[1]-q.centerYPoints)*q.mapPointsPerPointY;
   const coordinate=[x/world*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/world)))*180/Math.PI];
   assert(s.coordinate.length===2&&s.coordinate.every((n,k)=>Number.isFinite(n)&&Math.abs(n-coordinate[k])<1e-10),'Daishi eastern stations support projection changed');}
 }
 const [a,b,c]=e.supportAuthority.map(g=>g.supports.map(s=>[...s.coordinate]));
 const line=structuredClone(e.baselineLine);
 for(const g of e.supportAuthority)line.displayStationCoordinates[g.stationID]=[...g.aliasCoordinate];
 line.displayIntervalCoordinates={...line.displayIntervalCoordinates,
  2:[...line.displayIntervalCoordinates[2].slice(0,6),...a.slice(2,7)],
  3:[...a.slice(6),...b.slice(0,5)],4:[...b.slice(4),...c.slice(0,4)],
  5:[...c.slice(3),...line.displayIntervalCoordinates[5].slice(-9)]};
 for(const i of [2,3,4,5])assert(line.displayIntervalCoordinates[i].every((p,n,a)=>n===0||p[0]>a[n-1][0]),'Daishi eastern stations display backtracks');
 assert.deepEqual(net.displayPartsForLine(line)[0].slice(0,55),net.displayPartsForLine(e.baselineLine)[0].slice(0,55),'Daishi eastern stations protected prefix changed');
 assert.deepEqual(line,e.candidateLine,'Daishi eastern stations candidate exceeds bounded authority');return line;
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), rows = input.lines.filter(l => l.id === LINE);
  assert.equal(rows.length, 1, 'Daishi eastern stations own line missing/duplicated');
  assert(equal(rows[0], e.baselineLine) || equal(rows[0], line), 'Daishi eastern stations current own source changed');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: [2,3,4,5],
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-eastern-visible-north-track-display-repair; full-passenger-caps-and-whole-line-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Daishi eastern stations provenance changed');
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
  assert(Array.isArray(rows[0][7]), 'Daishi eastern stations native fallback missing');
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert(equal(own, baseline) || equal(own, rows), 'Daishi eastern stations stale/foreign own native row');
  // No own lanes/follows/family windows/maps exist in the inspected baseline.
  // Unknown newly introduced own references require review rather than guessing.
  for (const [key,value] of Object.entries(input)) if (key !== 'partsByRegion') {
    assert(!JSON.stringify(value)?.includes(LINE), 'Daishi eastern stations own native reference requires review: ' + key);
  }
  assert(!(input.excludedOperators || []).includes(line.operator), 'Daishi eastern stations operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

// Human review is separate from capture completion; only scoped proof files are bound.
export function validateCandidateReview(receipt,line) {
 assert(receipt,'Daishi eastern stations scoped candidate-review receipt required before --apply');
 assert.deepEqual([receipt.format,receipt.status,receipt.lineID,receipt.stationIDs,receipt.intervalIndices,receipt.wholeLineAccepted,receipt.MainCertified],['jtm-daishi-eastern-stations-candidate-review-v1','bounded-candidate-reviewed',LINE,STATIONS,[2,3,4,5],false,false],'Daishi eastern stations review scope changed');
 assert.equal(receipt.reviewedOwnLineSha256,sha(JSON.stringify(line)),'Daishi eastern stations reviewed own line changed');
 assert(Array.isArray(receipt.captures)&&receipt.captures.length>=7,'Daishi eastern stations scoped reviewed captures required');
 const snapshots=[],seen=new Set(),body=new Set(),stations=new Set();
 for(const capture of receipt.captures){
  canonicalFile(capture.viewPath);const viewPath=fs.realpathSync(capture.viewPath);
  assert(viewPath.startsWith(path.join(EV,'diagnostics/sessions')+path.sep)&&path.basename(viewPath)==='view.json','Daishi eastern stations noncanonical reviewed view');
  assert(!seen.has(viewPath),'Daishi eastern stations duplicate reviewed capture');seen.add(viewPath);
  for(const [file,key]of [['view.json','viewSha256'],['basemap.png','basemapSha256'],['smooth.png','smoothSha256']]){const p=path.join(path.dirname(viewPath),file),before=fs.readFileSync(p);assert.equal(sha(before),capture[key],'Daishi eastern stations reviewed capture bytes changed');snapshots.push({path:p,before});}
  const v=JSON.parse(snapshots.at(-3).before),i=v.intervalIndex,q=v.snapshotProjection;
  const identity=[v.lineID,i,v.fromStationID,v.toStationID,v.pointOrdinal];
  assert([2,3,4,5].includes(i),'Daishi eastern stations foreign reviewed interval');
  assert.deepEqual(identity,[LINE,i,line.stations[i][0],line.stations[i+1][0],v.pointOrdinal]);assert.deepEqual(identity,capture.identity,'Daishi eastern stations reviewed identity changed');
  assert(q&&q.displayScale===1&&v.camera.heading===0&&v.camera.pitch===0&&Number.isFinite(q.mapPointsPerPointX)&&q.mapPointsPerPointX>0&&Number.isFinite(q.mapPointsPerPointY)&&q.mapPointsPerPointY>0,'Daishi eastern stations reviewed projection missing');
  assert.deepEqual(q,capture.snapshotProjection,'Daishi eastern stations reviewed projection changed');assert.deepEqual(v.renderContract,capture.renderContract,'Daishi eastern stations render contract changed');
  assert(v.wholeLineRenderDependency);assert.equal(v.wholeLineRenderDependency,capture.wholeLineRenderDependency,'Daishi eastern stations reviewed render dependency changed');
  const identityPath=path.resolve(path.dirname(path.dirname(path.dirname(path.dirname(viewPath)))),v.intervalIdentityPlan);
  canonicalFile(identityPath);const before=fs.readFileSync(identityPath);snapshots.push({path:identityPath,before});
  // Preserve UInt64 bits through JSON parsing rather than rounding them to JS numbers.
  const plan=JSON.parse(before.toString().replace(/("(?:latitudeBits|longitudeBits)"\s*:\s*)(\d+)/g,'$1"$2"'));
  const item=plan.items.find(it=>it.itemID===LINE+'#'+i);assert(item,'Daishi eastern stations reviewed selected identity absent');
  const bits=n=>{const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readBigUInt64BE().toString();};
  const coords=p=>p.map(([x,y])=>({latitudeBits:bits(y),longitudeBits:bits(x)}));
  const physical=net.decodeIntervals(line),display=line.displayIntervalCoordinates[i]||physical[i];
  assert.deepEqual(item.identity.source,coords(physical[i]),'Daishi eastern stations reviewed source identity changed');assert.deepEqual(item.identity.display,coords(display),'Daishi eastern stations reviewed display identity changed');
  if(v.captureSettings.zoom===17)body.add(i);
  if(v.captureSettings.zoom===19&&v.pointOrdinal===0&&[3,4,5].includes(i))stations.add(v.fromStationID);
 }
 assert.deepEqual([...body].sort(),[2,3,4,5],'Daishi eastern stations affected interval review missing');assert.deepEqual([...stations].sort(),[...STATIONS].sort(),'Daishi eastern stations station review missing');return snapshots;
}

function canonicalFile(p) {
  assertAllowedCandidateFile(p);
  assert(fs.realpathSync(p).startsWith(EV + path.sep), 'Daishi eastern stations review receipt must use canonical evidence tree');
}

function main(args) {
  const candidate = args.length === 2 && args[0] === '--candidate-root' ? path.resolve(args[1]) : null;
  const apply = args[0] === '--apply';
  assert(candidate || apply, 'Use --candidate-root <canonical EV/candidates/dir> or --apply --candidate-review <receipt.json>');
  let receiptPath;
  if (apply) {
    assert(args.length === 3 && args[1] === '--candidate-review', 'Daishi eastern stations scoped candidate-review receipt required before --apply');
    receiptPath = path.resolve(args[2]); canonicalFile(receiptPath);
  } else {
    assertAllowedCandidateDirectory(candidate);
    assert(candidate.startsWith(path.join(EV,'candidates') + path.sep), 'Daishi eastern stations candidate must use canonical evidence tree');
    // Reject a lexical canonical path resolving through a symlink to scratch.
    let ancestor = candidate;
    while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
    assert(fs.realpathSync(ancestor).startsWith(EV + path.sep), 'Daishi eastern stations candidate ancestor escaped canonical evidence tree');
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
      assert(!fs.existsSync(p) || !fs.lstatSync(p).isSymbolicLink(), 'Daishi eastern stations candidate output cannot be symlink');
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
