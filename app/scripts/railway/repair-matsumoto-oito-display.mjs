#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const PACKAGE = 'public/rail/jp-2025.json', LANES = 'public/rail/display-lanes.json';
const EVIDENCE = 'scripts/railway/matsumoto-oito-display-evidence.json';
const OVERRIDE = 'matsumoto-oito-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const jsonSha256 = value => sha256(JSON.stringify(value));
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));

function metres(a, b) { return Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360),(b[1]-a[1])*111320); }
function bearing(a,b) { return Math.atan2((b[0]-a[0])*Math.cos((a[1]+b[1])*Math.PI/360),b[1]-a[1])*180/Math.PI; }
function turn(a,b,c) { let d=Math.abs(bearing(b,c)-bearing(a,b))%360; return Math.min(d,360-d); }

export function loadReviewedCandidate(e = read(EVIDENCE)) {
  assert.equal(e.format, 'jtm-matsumoto-oito-display-v1');
  assert(['candidate-only', e.policy.acceptanceGate].includes(e.status));
  const file = path.join(REPO, e.candidate.file);
  assert.equal(sha256(fs.readFileSync(file)), e.candidate.sha256, 'Frozen Matsumoto candidate changed');
  const c = JSON.parse(fs.readFileSync(file));
  assert.deepEqual([c.lineID,c.intervalIndex,c.stationID],[e.lineID,e.intervalIndex,e.stationID]);
  assert.deepEqual([c.sourceCoordinates.length,c.coordinates.length],[9,8]);
  assert.deepEqual(c.coordinates.slice(0,7),c.sourceCoordinates.slice(0,7));
  assert.deepEqual(c.coordinates.at(-1),e.candidate.displayAnchor);
  assert.deepEqual(c.displayStationCoordinates,{[e.stationID]:e.candidate.displayAnchor});
  assert(!c.coordinates.some(p=>equal(p,e.candidate.physicalJunction)), 'Physical J leaked into display tail');
  for (const s of c.sources) assert.equal(sha256(fs.readFileSync(path.join(REPO,s.path))),s.sha256,`Frozen source changed: ${s.path}`);
  for(let i=1;i<c.coordinates.length;i++) assert(metres(c.coordinates[i-1],c.coordinates[i])>=e.candidate.minimumEdgeMetres);
  for(let i=1;i<c.coordinates.length-1;i++) assert(turn(c.coordinates[i-1],c.coordinates[i],c.coordinates[i+1])<=e.candidate.maximumTurnDegrees);
  assert(c.directionEvidence.physicalJunctionExcludedFromDisplay);
  assert(c.directionEvidence.acuteAxisDifferenceDegrees<=c.directionEvidence.maximumAcceptedAxisDifferenceDegrees);
  return c;
}

function baseLine(current,e) { const base=structuredClone(current); delete base.displayIntervalCoordinates; delete base.displayStationCoordinates; assert.equal(jsonSha256(base),e.baseline.lineSha256,'Unreviewed Oito physical dependency changed'); return base; }
function repairedLine(current,c,e) { const base=baseLine(current,e), physical=network.decodeIntervals(base); assert.deepEqual(physical[e.intervalIndex],c.sourceCoordinates); base.displayIntervalCoordinates={[e.intervalIndex]:structuredClone(c.coordinates)}; base.displayStationCoordinates=structuredClone(c.displayStationCoordinates); return base; }
function metadata(e) { return {reviewedAt:e.reviewedAt,status:e.status,lineID:e.lineID,intervalIndex:e.intervalIndex,candidate:e.candidate,nativeReplay:e.nativeReplay,policy:e.policy,physicalTopologyChanged:false,script:'app/scripts/railway/repair-matsumoto-oito-display.mjs',evidence:'app/scripts/railway/matsumoto-oito-display-evidence.json'}; }

export function repairPackage(input,e=read(EVIDENCE)) {
  const c=loadReviewedCandidate(e), current=input.lines[e.packageIndex]; assert.equal(current?.id,e.lineID);
  const shin=input.lines.find(x=>x.id===e.related.shinonoiID), kami=input.lines.find(x=>x.id===e.related.kamikochiID);
  assert.equal(jsonSha256(shin),e.related.shinonoiLineSha256,'Shinonoi dependency changed'); assert.equal(jsonSha256(kami),e.related.kamikochiLineSha256,'Kamikochi dependency changed');
  const fixed=repairedLine(current,c,e), owned=[current.displayIntervalCoordinates,current.displayStationCoordinates];
  assert((owned[0]==null&&owned[1]==null)||(equal(owned[0],fixed.displayIntervalCoordinates)&&equal(owned[1],fixed.displayStationCoordinates)),'Unreviewed Oito display dependency changed');
  const result=structuredClone(input); result.lines[e.packageIndex]=fixed; result.geometrySource||={}; result.geometrySource.manualOverrides||={};
  const override=metadata(e); if(equal(current,fixed)&&result.geometrySource.manualOverrides[OVERRIDE]) assert.deepEqual(result.geometrySource.manualOverrides[OVERRIDE],override);
  result.geometrySource.manualOverrides[OVERRIDE]=override; return result;
}

function displayInputs(line) { const d={...line,stations:line.stations.map(s=>line.displayStationCoordinates?.[s[0]]?[...s.slice(0,2),...line.displayStationCoordinates[s[0]],...s.slice(4)]:s),segments:line.segments.map((s,i)=>line.displayIntervalCoordinates?.[i]?[s[0],0,line.displayIntervalCoordinates[i]]:s)}; return {stations:d.stations,intervals:network.decodeIntervals(d)}; }
function measured(input, id) {
  const result = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(row => JSON.stringify(row).includes(id));
      if (rows.length) result[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.fromEntries(Object.entries(region).filter(([name, row]) =>
        name === id || JSON.stringify(row).includes(id)));
      if (Object.keys(rows).length) result[key] = rows;
    }
  }
  return result;
}
function replace(rows,id,repl){const i=rows.findIndex(x=>x[0]===id);assert(i>=0);const r=rows.filter(x=>x[0]!==id);r.splice(i,0,...repl);return r;}
export function repairedNativeRow(pkg,e=read(EVIDENCE)){const line=pkg.lines[e.packageIndex],c=loadReviewedCandidate(e);assert(equal(line,repairedLine(line,c,e)));const rows=partRowsForLine(line,network.displayPartsForLine(line),displayInputs(line),null);assert.equal(rows.length,1);assert.equal(jsonSha256(rows[0]),e.nativeReplay.candidateRowSha256);return rows[0];}
export function repairParts(pkg,input,e=read(EVIDENCE)){const row=repairedNativeRow(pkg,e),cur=input.partsByRegion.jp.filter(x=>x[0]===e.lineID);assert.equal(cur.length,1);assert([e.baseline.nativeRowSha256,e.nativeReplay.candidateRowSha256].includes(jsonSha256(cur[0])),'Unreviewed Oito native dependency changed');const refs=measured(input,e.lineID);assert(equal(refs,e.baseline.measuredReferences)||equal(refs,e.nativeReplay.candidateMeasuredReferences),'Unreviewed Oito measured reference');assert.deepEqual(input.byRegion.jp.filter(x=>x[0]===e.related.shinonoiID),[e.related.shinonoiLane]);const out=structuredClone(input);out.partsByRegion.jp=replace(out.partsByRegion.jp,e.lineID,[row]);out.byRegion.jp=replace(out.byRegion.jp,e.lineID,e.nativeReplay.candidateMeasuredReferences.byRegion);return out;}
export function candidateGeoJSON(pkg,e=read(EVIDENCE)){return{type:'Feature',properties:{lineID:e.lineID,referenceLineID:e.lineID,intervalIndex:e.intervalIndex,referenceIntervalIndex:e.intervalIndex,status:e.status,representation:e.policy.representation},geometry:{type:'LineString',coordinates:pkg.lines[e.packageIndex].displayIntervalCoordinates[e.intervalIndex]}};}
export function assertApplyAccepted(e){assert.equal(e.status,e.policy.acceptanceGate,'Matsumoto candidate requires accepted native and Main comparison before apply');}

function main(args=process.argv.slice(2)){const candidate=args[0]==='--candidate-root'&&args.length===2,apply=equal(args,['--apply']);assert(candidate||apply,'Usage: repair-matsumoto-oito-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');const paths={package:PACKAGE,lanes:LANES,evidence:EVIDENCE,...DEPENDENCY_PATHS};const snaps=Object.fromEntries(Object.entries(paths).map(([k,r])=>[k,{path:path.join(ROOT,r),before:fs.readFileSync(path.join(ROOT,r),'utf8')}]));const load=k=>JSON.parse(snaps[k].before),e=load('evidence');if(apply)assertApplyAccepted(e);const c=loadReviewedCandidate(e),candidateFile=path.join(REPO,e.candidate.file),sources=[{path:candidateFile,before:fs.readFileSync(candidateFile)},...c.sources.map(s=>({path:path.join(REPO,s.path),before:fs.readFileSync(path.join(REPO,s.path))}))];const registry=path.join(ROOT,e.related.junctionRegistry);assert.equal(sha256(fs.readFileSync(registry)),e.related.junctionRegistrySha256,'Physical junction registry changed');sources.push({path:registry,before:fs.readFileSync(registry)});const pkg=repairPackage(load('package'),e),lanes=repairParts(pkg,load('lanes'),e),deps=refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,load(k)])));const outputs={package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k=>[k,JSON.stringify(deps[k],null,2)+'\n']))};if(candidate){const dir=path.resolve(args[1]);assert(dir.startsWith('/private/tmp/'));fs.mkdirSync(dir,{recursive:true});for(const[k,v]of Object.entries(outputs))fs.writeFileSync(path.join(dir,path.basename(snaps[k].path)),v);fs.writeFileSync(path.join(dir,'matsumoto-oito-interval-31.geojson'),JSON.stringify(candidateGeoJSON(pkg,e),null,2)+'\n');}else{const writes=Object.entries(outputs).filter(([k,v])=>v!==snaps[k].before).map(([k,v])=>({path:snaps[k].path,before:snaps[k].before,after:v,temporary:`${snaps[k].path}.matsumoto-oito-${process.pid}.tmp`}));applyPreparedWrites(writes,[...Object.values(snaps),...sources]);}const row=lanes.partsByRegion.jp.find(x=>x[0]===e.lineID);console.log(JSON.stringify({mode:apply?'applied':'candidate',status:e.status,lineID:e.lineID,intervalIndex:e.intervalIndex,displayPointCount:pkg.lines[e.packageIndex].displayIntervalCoordinates[e.intervalIndex].length,nativePointCount:row[4],nativeMetres:row[5],physicalTopologyChanged:false}));}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main();
