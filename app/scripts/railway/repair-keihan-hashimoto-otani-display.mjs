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
export const AUTHORITY_PATH = path.join(EV, 'proposals/keihan-main-hashimoto-otani-20261020/bounded-visible-track-candidate-v2.json');
const LINE = 'jp-京阪電気鉄道-京阪本線', KEY = 'keihan-hashimoto-otani-display';
const STATIONS = ['006356','006351'];
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const BASELINE_SHA='ae1d35c23599b2a28467d4b2bfb416d86ce0ff92c9705f1d0b0223f8d95e5246';
const CANDIDATE_SHA='d15eb240db8c183c7b55925f5a11a283935b5147cbb87081c417544b3b514a58';
const NATIVE_PATH=path.join(EV,'proposals/keihan-main-hashimoto-otani-20261020/baseline-native-references.json');
const SUPPORTS=[["23p4-0",[1075,1250],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p4-1",[1144,1100],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p4-2",[1209,950],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p4-3",[1297,760],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p4-4",[1331,680],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p4-5",[1368,540],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000004/view.json"],["23p5-0",[1159,1120],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-1",[1162,960],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-2",[1181,800],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-3",[1279,530],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-4",[1431,320],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-5",[1544,220],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["23p5-6",[1753,25],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000000/000005/view.json"],["hash-0",[1223,960],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-1",[1376,712],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-2",[1499,480],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-3",[1683,215],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000000/000000/view.json"],["24p2-0",[400,1270],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-1",[480,1225],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-2",[940,1068],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-3",[1100,1028],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-4",[1260,972],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-5",[1740,724],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-6",[1900,676],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-7",[2220,710],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p3-0",[1300,940],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000003/view.json"],["24p3-1",[1620,997],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000003/view.json"],["24p3-2",[1780,1076],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000003/view.json"],["iwa-0",[320,492],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-1",[500,622],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-2",[1040,945],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-3",[1250,1003],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-4",[1630,1031],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-5",[1820,1012],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-6",[2160,917],"diagnostics/sessions/keihan-main-hashimoto-iwashimizu-stations-20261020/alignment/captures/000001/000000/view.json"],["24p2-extra0",[780,1103],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-extra1",[1420,892],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["24p2-extra2",[1580,808],"diagnostics/sessions/keihan-main-hashimoto-otani-detail-20261020/alignment/captures/000001/000002/view.json"],["hash-refine-0",[647,1650],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-refine-1",[757.5,1550],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-refine-2",[854,1450],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-refine-3",[975,1300],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-refine-4",[1054,1200],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["hash-refine-5",[1131,1100],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000000/000000/view.json"],["iwa-refine-0",[600,727],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-1",[750,823.5],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-2",[900,905],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-3",[1050,963],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-4",[1300,1018],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-5",[1350,1023],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-6",[1500,1030],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-7",[1700,1018],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-8",[1900,985.5],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"],["iwa-refine-9",[2000,956.5],"diagnostics/sessions/keihan-main-hashimoto-otani-candidate-stations-20261020/alignment/captures/000001/000000/view.json"]];
const VIEWS=[...new Set(SUPPORTS.map(s=>path.join(EV,s[2])))];
function proposedLine(e) {
 assert.deepEqual([e.format,e.lineID,e.stationIDs,e.intervalIndices,e.sourceInterval23PrefixCount,e.sourceInterval25SuffixStart,e.sourceInterval25SuffixCount,e.commonDisplayPartPrefixCount,e.commonDisplayPartSuffixCount],['jtm-keihan-hashimoto-otani-visible-track-authority-v1',LINE,STATIONS,[23,24,25],25,10,55,502,264],'Hashimoto Otani authority scope changed');
 assert.equal(sha(JSON.stringify(e.baselineLine)),BASELINE_SHA,'Hashimoto Otani baseline changed');
 assert.deepEqual(e.supportAuthority.map(s=>[s.id,s.pixel,s.viewJSON]),SUPPORTS.map(([id,p,v])=>[id,p,path.join(EV,v)]),'Hashimoto Otani own-track pixel authority changed');
 const source=net.decodeIntervals(e.baselineLine),supports=new Map();
 for(const s of e.supportAuthority){
  const v=read(s.viewJSON),q=v.snapshotProjection,c=v.camera,world=2**28;
  assert.equal(v.lineID,LINE);assert([23,24,25].includes(v.intervalIndex));
  assert(q&&q.displayScale===1&&c.heading===0&&c.pitch===0&&q.widthPoints===2400&&q.heightPoints===2000&&[18,19].includes(v.captureSettings.zoom)&&[q.mapPointsPerPointX,q.mapPointsPerPointY,q.centerXPoints,q.centerYPoints,c.latitude,c.longitude].every(Number.isFinite)&&q.mapPointsPerPointX>0&&q.mapPointsPerPointY>0,'Hashimoto Otani actual projection missing');
  const cx=(c.longitude+180)/360*world,cy=(1-Math.asinh(Math.tan(c.latitude*Math.PI/180))/Math.PI)/2*world;
  const x=cx+(s.pixel[0]-q.centerXPoints)*q.mapPointsPerPointX,y=cy+(s.pixel[1]-q.centerYPoints)*q.mapPointsPerPointY;
  const coordinate=[x/world*360-180,Math.atan(Math.sinh(Math.PI*(1-2*y/world)))*180/Math.PI];
  assert(s.coordinate.length===2&&s.coordinate.every((n,k)=>Number.isFinite(n)&&Math.abs(n-coordinate[k])<1e-10),'Hashimoto Otani support projection changed');
  supports.set(s.id,[...s.coordinate]);
 }
 const line=structuredClone(e.baselineLine);line.displayStationCoordinates={...line.displayStationCoordinates};
 for(const [id,supportID]of [['006356','hash-0'],['006351','iwa-3']]){assert.deepEqual(e.aliases[id],e.supportAuthority.find(s=>s.id===supportID),'Hashimoto Otani alias authority changed');line.displayStationCoordinates[id]=supports.get(supportID);}
 line.displayIntervalCoordinates={...line.displayIntervalCoordinates};
 for(const i of [23,24,25]){
  const p=e.proposedDisplayPaths[i],manual=p.manualSupportIDs.map(id=>{assert(supports.has(id),'Hashimoto Otani missing support');return supports.get(id);});
  line.displayIntervalCoordinates[i]=i===23?[...source[23].slice(0,25),...manual]:i===25?[...manual,...source[25].slice(10)]:manual;
 }
 assert.deepEqual([23,24,25].map(i=>line.displayIntervalCoordinates[i].length),[45,26,65],'Hashimoto Otani bounded path lengths changed');
 const before=net.displayPartsForLine(e.baselineLine)[0],after=net.displayPartsForLine(line)[0];
 assert.deepEqual(after.slice(0,502),before.slice(0,502),'Hashimoto Otani protected prefix changed');assert.deepEqual(after.slice(-264),before.slice(-264),'Hashimoto Otani protected suffix changed');
 assert.deepEqual(line,e.candidateLine,'Hashimoto Otani candidate exceeds bounded authority');assert.equal(sha(JSON.stringify(line)),CANDIDATE_SHA,'Hashimoto Otani candidate own hash changed');return line;
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), rows = input.lines.filter(l => l.id === LINE);
  assert.equal(rows.length, 1, 'Hashimoto Otani own line missing/duplicated');
  assert(equal(rows[0], e.baselineLine) || equal(rows[0], line), 'Hashimoto Otani current own source changed');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: STATIONS, intervalIndices: [23,24,25],
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-hashimoto-otani-visible-north-track-display-repair; full-passenger-caps-and-whole-line-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Hashimoto Otani provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const line = pkg.lines.find(l => l.id === LINE);
  assert.deepEqual(line, proposedLine(e));
  const baseline=read(NATIVE_PATH);
  const rows=partRowsForLine(line,net.displayPartsForLine(line),null,null);
  assert.equal(rows.length,1);assert.deepEqual(rows[0].slice(1,7),[0,-1,-1,838,49262.1,'complex']);assert(Array.isArray(rows[0][7]),'Hashimoto Otani native fallback missing');
  const own=input.partsByRegion?.jp?.filter(r=>r[0]===LINE);
  assert(equal(own,baseline.partsByRegion.jp)||equal(own,rows),'Hashimoto Otani stale/foreign own native row');
  // The Kyoto hub report's excluded crossing member is historical, not an active lane.
  for(const [key,value]of Object.entries(input))if(key!=='partsByRegion'){
   if(key==='hubReportByRegion'){
    const ownReports=Object.fromEntries(Object.entries(value).map(([region,reports])=>[region,reports.filter(r=>JSON.stringify(r).includes(LINE))]).filter(([,rs])=>rs.length));
    assert.deepEqual(ownReports,baseline.hubReportByRegion,'Hashimoto Otani own hub report changed');
   }else assert(!JSON.stringify(value)?.includes(LINE),'Hashimoto Otani own native reference requires review: '+key);
  }
  assert.deepEqual(input.hubReportByRegion?.jp?.filter(r=>JSON.stringify(r).includes(LINE))||[],baseline.hubReportByRegion.jp,'Hashimoto Otani known hub report missing');
  for(const [region,rs]of Object.entries(input.partsByRegion||{}))if(region!=='jp')assert(!JSON.stringify(rs).includes(LINE),'Hashimoto Otani foreign region own reference');
  assert(!(input.excludedOperators||[]).includes(line.operator),'Hashimoto Otani operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

// Human review is separate from capture completion; only scoped proof files are bound.
export function validateCandidateReview(receipt,line) {
 assert(receipt,'Hashimoto Otani scoped candidate-review receipt required before --apply');
 assert.deepEqual([receipt.format,receipt.status,receipt.lineID,receipt.stationIDs,receipt.intervalIndices,receipt.wholeLineAccepted,receipt.MainCertified],['jtm-keihan-hashimoto-otani-candidate-review-v1','bounded-candidate-reviewed',LINE,STATIONS,[23,24,25],false,false],'Hashimoto Otani review scope changed');
 assert.equal(receipt.reviewedOwnLineSha256,sha(JSON.stringify(line)),'Hashimoto Otani reviewed own line changed');
 assert(Array.isArray(receipt.captures)&&receipt.captures.length>=5,'Hashimoto Otani scoped reviewed captures required');
 const snapshots=[],seen=new Set(),body=new Set(),stations=new Set();
 for(const capture of receipt.captures){
  assert.equal(capture.originalsActuallyViewed,true,'Hashimoto Otani actual original review required');
  canonicalFile(capture.viewPath);const viewPath=fs.realpathSync(capture.viewPath);
  assert(viewPath.startsWith(path.join(EV,'diagnostics/sessions')+path.sep)&&path.basename(viewPath)==='view.json','Hashimoto Otani noncanonical reviewed view');
  assert(!seen.has(viewPath),'Hashimoto Otani duplicate reviewed capture');seen.add(viewPath);
  for(const [file,key]of [['view.json','viewSha256'],['basemap.png','basemapSha256'],['smooth.png','smoothSha256']]){const p=path.join(path.dirname(viewPath),file),before=fs.readFileSync(p);assert.equal(sha(before),capture[key],'Hashimoto Otani reviewed capture bytes changed');snapshots.push({path:p,before});}
  const v=JSON.parse(snapshots.at(-3).before),i=v.intervalIndex,q=v.snapshotProjection;
  const identity=[v.lineID,i,v.fromStationID,v.toStationID,v.pointOrdinal];
  assert([23,24,25].includes(i),'Hashimoto Otani foreign reviewed interval');
  assert.deepEqual(identity,[LINE,i,line.stations[i][0],line.stations[i+1][0],v.pointOrdinal]);assert.deepEqual(identity,capture.identity,'Hashimoto Otani reviewed identity changed');
  assert(q&&q.displayScale===1&&v.camera.heading===0&&v.camera.pitch===0&&Number.isFinite(q.mapPointsPerPointX)&&q.mapPointsPerPointX>0&&Number.isFinite(q.mapPointsPerPointY)&&q.mapPointsPerPointY>0,'Hashimoto Otani reviewed projection missing');
  assert.deepEqual(q,capture.snapshotProjection,'Hashimoto Otani reviewed projection changed');assert.deepEqual(v.renderContract,capture.renderContract,'Hashimoto Otani render contract changed');
  assert(v.wholeLineRenderDependency);assert.equal(v.wholeLineRenderDependency,capture.wholeLineRenderDependency,'Hashimoto Otani reviewed render dependency changed');
  const identityPath=path.resolve(path.dirname(path.dirname(path.dirname(path.dirname(viewPath)))),v.intervalIdentityPlan);
  canonicalFile(identityPath);const before=fs.readFileSync(identityPath);snapshots.push({path:identityPath,before});
  // Preserve UInt64 bits through JSON parsing rather than rounding them to JS numbers.
  const plan=JSON.parse(before.toString().replace(/("(?:latitudeBits|longitudeBits)"\s*:\s*)(\d+)/g,'$1"$2"'));
  const item=plan.items.find(it=>it.itemID===LINE+'#'+i);assert(item,'Hashimoto Otani reviewed selected identity absent');
  const bits=n=>{const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.readBigUInt64BE().toString();};
  const coords=p=>p.map(([x,y])=>({latitudeBits:bits(y),longitudeBits:bits(x)}));
  const physical=net.decodeIntervals(line),display=line.displayIntervalCoordinates[i]||physical[i];
  assert.deepEqual(item.identity.source,coords(physical[i]),'Hashimoto Otani reviewed source identity changed');assert.deepEqual(item.identity.display,coords(display),'Hashimoto Otani reviewed display identity changed');
  if(v.captureSettings.zoom===17)body.add(i);
  if(v.captureSettings.zoom===19&&v.pointOrdinal===0&&[24,25].includes(i))stations.add(v.fromStationID);
 }
 assert.deepEqual([...body].sort((a,b)=>a-b),[23,24,25],'Hashimoto Otani affected interval review missing');assert.deepEqual([...stations].sort(),[...STATIONS].sort(),'Hashimoto Otani station review missing');return snapshots;
}

function canonicalFile(p) {
  assertAllowedCandidateFile(p);
  assert(fs.realpathSync(p).startsWith(EV + path.sep), 'Hashimoto Otani review receipt must use canonical evidence tree');
}

function main(args) {
  const candidate = args.length === 2 && args[0] === '--candidate-root' ? path.resolve(args[1]) : null;
  const apply = args[0] === '--apply';
  assert(candidate || apply, 'Use --candidate-root <canonical EV/candidates/dir> or --apply --candidate-review <receipt.json>');
  let receiptPath;
  if (apply) {
    assert(args.length === 3 && args[1] === '--candidate-review', 'Hashimoto Otani scoped candidate-review receipt required before --apply');
    receiptPath = path.resolve(args[2]); canonicalFile(receiptPath);
  } else {
    assertAllowedCandidateDirectory(candidate);
    assert(candidate.startsWith(path.join(EV,'candidates') + path.sep), 'Hashimoto Otani candidate must use canonical evidence tree');
    // Reject a lexical canonical path resolving through a symlink to scratch.
    let ancestor = candidate;
    while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
    assert(fs.realpathSync(ancestor).startsWith(EV + path.sep), 'Hashimoto Otani candidate ancestor escaped canonical evidence tree');
  }
  const snapshot = p => ({path:p,before:fs.readFileSync(p)});
  const authority = snapshot(AUTHORITY_PATH), e = JSON.parse(authority.before);
  const paths = {package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([k,p]) => [k,snapshot(path.join(APP,p))]));
  const load = k => JSON.parse(inputs[k].before);
  const pkg = repairPackage(load('package'),e), lanes = repairParts(pkg,load('lanes'),e);
  const custody = [authority,snapshot(NATIVE_PATH),...VIEWS.map(snapshot),snapshot(path.join(APP,'public/rail-network.js')),
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
      assert(!fs.existsSync(p) || !fs.lstatSync(p).isSymbolicLink(), 'Hashimoto Otani candidate output cannot be symlink');
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
